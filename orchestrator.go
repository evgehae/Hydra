package hydra

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
)

type Config struct {
	Stagger       time.Duration // пауза между стартами кандидатов в гонке
	DialTimeout   time.Duration
	ProbeEvery    time.Duration
	BadProbes     int     // сколько плохих проб подряд = деградация
	MaxRTTFactor  float64 // во сколько раз RTT может вырасти от базового
	MaxLoss       float64
	StandbyWait   time.Duration // сколько ждать резерв при сбое
	Colo          *ColoPolicy   // политика дата-центров (nil — без ограничений)
}

func DefaultConfig() Config {
	return Config{
		Stagger:      300 * time.Millisecond,
		DialTimeout:  10 * time.Second,
		ProbeEvery:   5 * time.Second,
		BadProbes:    3,
		MaxRTTFactor: 3,
		MaxLoss:      0.2,
		StandbyWait:  2 * time.Second,
		Colo:         DefaultColoPolicy(),
	}
}

var errNoStrategies = errors.New("нет доступных стратегий")

type Orchestrator struct {
	cfg    Config
	mem    *Memory
	ts     map[string]Transport
	order  []Transport
	diag   Diagnoser
	events chan Event
	front  *Front
}

func New(cfg Config, mem *Memory, ts []Transport, d Diagnoser) *Orchestrator {
	if d == nil {
		d = nopDiagnoser{}
	}
	o := &Orchestrator{cfg: cfg, mem: mem, ts: map[string]Transport{}, order: ts, diag: d,
		events: make(chan Event, 64), front: NewFront()}
	for _, t := range ts {
		o.ts[t.Name()] = t
	}
	return o
}

func (o *Orchestrator) Events() <-chan Event { return o.events }

// Front — постоянный локальный SOCKS5-вход; туннель под ним меняется на лету.
func (o *Orchestrator) Front() *Front { return o.front }

func (o *Orchestrator) emit(kind, strategy string, c Cause, msg string) {
	select {
	case o.events <- Event{Kind: kind, Strategy: strategy, Cause: c, Msg: msg, At: time.Now()}:
	default: // UI не успевает — не блокируем ядро
	}
}

func (o *Orchestrator) candidates(net, skip string) []Strategy {
	var all []Strategy
	for _, t := range o.order {
		for _, s := range t.Strategies() {
			if s.ID != skip {
				all = append(all, s)
			}
		}
	}
	return o.mem.Rank(net, all)
}

type dialRes struct {
	t    Tunnel
	s    Strategy
	d    time.Duration
	err  error
	colo string
}

func drain(res <-chan dialRes, n int) {
	for i := 0; i < n; i++ {
		if r := <-res; r.err == nil && r.t != nil {
			r.t.Close()
		}
	}
}

// checkColo спрашивает у туннеля, через какой дата-центр он идёт, и отбрасывает
// запрещённые политикой. Туннели без ColoReporter пропускаются без проверки.
func (o *Orchestrator) checkColo(ctx context.Context, t Tunnel) (Tunnel, string, error) {
	rep, ok := t.(ColoReporter)
	if !ok || o.cfg.Colo == nil {
		return t, "", nil
	}
	cctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	colo, err := rep.Colo(cctx)
	cancel()
	if err != nil {
		return t, "", nil // не смогли узнать — не блокируем
	}
	if !o.cfg.Colo.Allows(colo) {
		t.Close()
		return nil, colo, &ColoError{Colo: colo}
	}
	return t, colo, nil
}

// race — «гонка стратегий»: кандидаты стартуют по очереди с небольшим
// сдвигом, побеждает первый рабочий, остальные отменяются.
func (o *Orchestrator) race(ctx context.Context, net, skip string) (Tunnel, Strategy, error) {
	cands := o.candidates(net, skip)
	if len(cands) == 0 {
		return nil, Strategy{}, errNoStrategies
	}
	rctx, cancel := context.WithCancel(ctx)
	defer cancel()
	res := make(chan dialRes, len(cands))
	started, finished := 0, 0
	var blockedColos []string
	start := func() {
		s := cands[started]
		started++
		go func() {
			t0 := time.Now()
			dctx, c := context.WithTimeout(rctx, o.cfg.DialTimeout)
			defer c()
			t, err := o.ts[s.Transport].Dial(dctx, s)
			colo := ""
			if err == nil {
				t, colo, err = o.checkColo(rctx, t)
			}
			res <- dialRes{t, s, time.Since(t0), err, colo}
		}()
	}
	timer := time.NewTimer(0)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			go drain(res, started-finished)
			return nil, Strategy{}, ctx.Err()
		case <-timer.C:
			if started < len(cands) {
				start()
				timer.Reset(o.cfg.Stagger)
			}
		case r := <-res:
			finished++
			if r.err == nil {
				o.mem.Record(net, r.s.ID, true, r.d)
				if r.colo != "" {
					o.emit("colo", r.s.ID, CauseUnknown, r.colo)
				}
				cancel()
				go drain(res, started-finished)
				return r.t, r.s, nil
			}
			if ctx.Err() == nil {
				o.mem.Record(net, r.s.ID, false, r.d)
			}
			var ce *ColoError
			if errors.As(r.err, &ce) {
				blockedColos = append(blockedColos, ce.Colo)
				o.emit("colo_blocked", r.s.ID, CauseUnknown, ce.Colo)
			}
			if finished == len(cands) {
				if len(blockedColos) > 0 {
					return nil, Strategy{}, fmt.Errorf("все %d стратегий не сработали (запрещённые дата-центры: %s)",
						len(cands), strings.Join(blockedColos, ", "))
				}
				return nil, Strategy{}, fmt.Errorf("все %d стратегий не сработали", len(cands))
			}
			if finished == started && started < len(cands) {
				start() // ничего не бежит — не ждём паузу
				timer.Reset(o.cfg.Stagger)
			}
		}
	}
}

// watch следит за качеством. Возвращает причину и флаг «сменилась сеть».
func (o *Orchestrator) watch(ctx context.Context, netKey func() string, net string, t Tunnel) (string, bool) {
	tk := time.NewTicker(o.cfg.ProbeEvery)
	defer tk.Stop()
	var base time.Duration
	bad := 0
	for {
		select {
		case <-ctx.Done():
			return "остановка", false
		case <-t.Done():
			return "туннель закрылся", false
		case <-tk.C:
			if netKey() != net {
				return "сменилась сеть", true
			}
			pctx, c := context.WithTimeout(ctx, o.cfg.ProbeEvery)
			q, err := t.Probe(pctx)
			c()
			degraded := err != nil || q.Loss > o.cfg.MaxLoss ||
				(base > 0 && float64(q.RTT) > float64(base)*o.cfg.MaxRTTFactor)
			if !degraded {
				if base == 0 {
					base = q.RTT
				} else {
					base = (base*9 + q.RTT) / 10
				}
				bad = 0
				continue
			}
			bad++
			if bad >= o.cfg.BadProbes {
				return "качество упало", false
			}
		}
	}
}

type standbyRes struct {
	t   Tunnel
	s   Strategy
	err error
}

type standby struct {
	cancel context.CancelFunc
	ch     chan standbyRes
}

// warm прогревает резервный туннель на другой стратегии.
func (o *Orchestrator) warm(ctx context.Context, net, skip string) *standby {
	cctx, cancel := context.WithCancel(ctx)
	sb := &standby{cancel: cancel, ch: make(chan standbyRes, 1)}
	go func() {
		t, s, err := o.race(cctx, net, skip)
		sb.ch <- standbyRes{t, s, err}
	}()
	return sb
}

func (sb *standby) stop() {
	sb.cancel()
	go func() {
		if r := <-sb.ch; r.err == nil {
			r.t.Close()
		}
	}()
}

// session ведёт активный туннель + резерв; возвращается, когда нужна новая гонка.
func (o *Orchestrator) session(ctx context.Context, netKey func() string, net string, t Tunnel, s Strategy) {
	defer o.front.Set(nil)
	sb := o.warm(ctx, net, s.ID)
	for {
		reason, netChanged := o.watch(ctx, netKey, net, t)
		if ctx.Err() != nil || netChanged {
			t.Close()
			sb.stop()
			return
		}
		o.mem.Record(net, s.ID, false, 0)
		cause := o.diag.Diagnose(ctx)
		o.emit("degraded", s.ID, cause, reason)
		select {
		case r := <-sb.ch:
			if r.err == nil {
				old := t
				t, s = r.t, r.s
				o.front.Set(t)
				old.Close()
				o.emit("failover", s.ID, cause, "переключился на резерв")
				sb = o.warm(ctx, net, s.ID)
				continue
			}
			t.Close()
			return
		case <-time.After(o.cfg.StandbyWait):
			t.Close()
			sb.stop()
			return
		}
	}
}

func sleep(ctx context.Context, d time.Duration) bool {
	select {
	case <-ctx.Done():
		return false
	case <-time.After(d):
		return true
	}
}

// Run — главный цикл Гидры: подключиться, следить, лечить.
func (o *Orchestrator) Run(ctx context.Context, netKey func() string) error {
	backoff := time.Second
	for ctx.Err() == nil {
		net := netKey()
		o.emit("connecting", "", CauseUnknown, net)
		t, s, err := o.race(ctx, net, "")
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			c := o.diag.Diagnose(ctx)
			o.emit("failed", "", c, err.Error())
			if !sleep(ctx, backoff) {
				break
			}
			if backoff < 30*time.Second {
				backoff *= 2
			}
			continue
		}
		backoff = time.Second
		o.front.Set(t)
		o.emit("connected", s.ID, CauseUnknown, "net="+net)
		o.session(ctx, netKey, net, t, s)
		_ = o.mem.Save()
	}
	return ctx.Err()
}
