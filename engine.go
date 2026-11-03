package hydra

import (
	"context"
	"errors"
	"io"
	"math/rand"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

// Engine — «сердце» Гидры на телефоне. Android отдаёт TUN (поток IP-пакетов),
// Engine гоняет их через туннель WARP и сам следит за ним:
//   - после подключения спрашивает у Cloudflare, в какой дата-центр попали;
//     запрещённый дата-центр (например DME) — туннель отбрасывается, пробуем следующий;
//   - постоянно проверяет задержку и потери, при сбое переходит на другую стратегию;
//   - память по сетям запоминает, что работало, и пробует это первым.

// PacketDevice — «сетевая карта» для туннеля (те же методы, что у TunnelDevice в usque).
type PacketDevice interface {
	ReadPacket(buf []byte) (int, error)
	WritePacket(pkt []byte) error
}

// Runner держит туннель по стратегии s, пока ctx не отменён или не случилась
// непоправимая ошибка. Пакеты читает/пишет через dev.
type Runner func(ctx context.Context, dev PacketDevice, s Strategy) error

type EngineConfig struct {
	LocalIP    net.IP // IPv4-адрес внутри туннеля (из аккаунта)
	Strategies []Strategy
	Runner     Runner
	Policy     *ColoPolicy
	Mem        *Memory
	NetKey     func() string
	ProbeEvery time.Duration
	UpTimeout  time.Duration // сколько ждать первого ответа после старта стратегии
	BadProbes  int           // сколько проб подряд без ответа = туннель умер
}

func DefaultEngineConfig() EngineConfig {
	return EngineConfig{ProbeEvery: 3 * time.Second, UpTimeout: 10 * time.Second, BadProbes: 3}
}

type Status struct {
	State    string // connecting | up | reconnecting | failed
	Strategy string
	Colo     string
	RTT      time.Duration
	Message  string
}

type Engine struct {
	cfg     EngineConfig
	tun     io.ReadWriteCloser
	out     chan []byte // пакеты из TUN (от приложений)
	probeQ  chan []byte
	port    uint16
	nextID  uint32
	events  chan Event
	tunDead chan struct{}
	once    sync.Once

	mu      sync.Mutex
	status  Status
	waiters map[uint16]chan string
}

func NewEngine(tun io.ReadWriteCloser, cfg EngineConfig) *Engine {
	d := DefaultEngineConfig()
	if cfg.ProbeEvery <= 0 {
		cfg.ProbeEvery = d.ProbeEvery
	}
	if cfg.UpTimeout <= 0 {
		cfg.UpTimeout = d.UpTimeout
	}
	if cfg.BadProbes <= 0 {
		cfg.BadProbes = d.BadProbes
	}
	if cfg.Mem == nil {
		cfg.Mem, _ = LoadMemory("")
	}
	if cfg.NetKey == nil {
		cfg.NetKey = func() string { return "default" }
	}
	return &Engine{
		cfg:     cfg,
		tun:     tun,
		out:     make(chan []byte, 512),
		probeQ:  make(chan []byte, 16),
		port:    uint16(20000 + rand.Intn(30000)),
		events:  make(chan Event, 64),
		tunDead: make(chan struct{}),
		waiters: map[uint16]chan string{},
		status:  Status{State: "connecting"},
	}
}

func (e *Engine) Events() <-chan Event { return e.events }

func (e *Engine) Status() Status {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.status
}

func (e *Engine) setStatus(s Status) {
	e.mu.Lock()
	e.status = s
	e.mu.Unlock()
}

func (e *Engine) emit(kind, strategy, msg string) {
	select {
	case e.events <- Event{Kind: kind, Strategy: strategy, Msg: msg, At: time.Now()}:
	default:
	}
}

func (e *Engine) Close() { e.once.Do(func() { e.tun.Close() }) }

// readTun читает пакеты приложений. Пока туннеля нет, лишние пакеты отбрасываются.
func (e *Engine) readTun() {
	defer close(e.tunDead)
	for {
		buf := make([]byte, 2048)
		n, err := e.tun.Read(buf)
		if err != nil {
			return
		}
		select {
		case e.out <- buf[:n]:
		default:
		}
	}
}

// attemptDev — «карта» одной попытки: после отмены попытки её горутины
// просыпаются с ошибкой и не крадут пакеты у следующей попытки.
type attemptDev struct {
	e    *Engine
	done <-chan struct{}
}

func (d *attemptDev) ReadPacket(buf []byte) (int, error) {
	select {
	case <-d.done:
		return 0, io.EOF
	case <-d.e.tunDead:
		return 0, io.EOF
	case p := <-d.e.probeQ:
		return copy(buf, p), nil
	case p := <-d.e.out:
		return copy(buf, p), nil
	}
}

func (d *attemptDev) WritePacket(pkt []byte) error {
	select {
	case <-d.done:
		return io.ErrClosedPipe
	default:
	}
	if id, colo, ok := ParseColoReply(pkt, d.e.port); ok {
		d.e.deliver(id, colo)
		return nil
	}
	_, err := d.e.tun.Write(pkt)
	return err
}

func (e *Engine) deliver(id uint16, colo string) {
	e.mu.Lock()
	ch := e.waiters[id]
	e.mu.Unlock()
	if ch != nil {
		select {
		case ch <- colo:
		default:
		}
	}
}

// probe шлёт пробу и ждёт ответ: возвращает задержку и код дата-центра.
func (e *Engine) probe(ctx context.Context, timeout time.Duration) (time.Duration, string, error) {
	id := uint16(atomic.AddUint32(&e.nextID, 1))
	ch := make(chan string, 1)
	e.mu.Lock()
	e.waiters[id] = ch
	e.mu.Unlock()
	defer func() {
		e.mu.Lock()
		delete(e.waiters, id)
		e.mu.Unlock()
	}()
	pkt := BuildColoProbe(e.cfg.LocalIP, e.port, id)
	if pkt == nil {
		return 0, "", errors.New("нет IPv4-адреса туннеля")
	}
	t0 := time.Now()
	select {
	case e.probeQ <- pkt:
	default:
		return 0, "", errors.New("очередь проб переполнена")
	}
	select {
	case colo := <-ch:
		return time.Since(t0), colo, nil
	case <-time.After(timeout):
		return 0, "", errors.New("нет ответа на пробу")
	case <-ctx.Done():
		return 0, "", ctx.Err()
	}
}

type outcome struct {
	wasUp      bool
	netChanged bool
	reason     string
}

func (e *Engine) runStrategy(ctx context.Context, nk string, s Strategy) outcome {
	e.setStatus(Status{State: "connecting", Strategy: s.ID})
	e.emit("connecting", s.ID, "")
	actx, cancel := context.WithCancel(ctx)
	defer cancel()
	dev := &attemptDev{e: e, done: actx.Done()}
	errc := make(chan error, 1)
	go func() { errc <- e.cfg.Runner(actx, dev, s) }()

	start := time.Now()
	var colo string
	var rtt time.Duration
	up := false
	for !up && time.Since(start) < e.cfg.UpTimeout {
		select {
		case err := <-errc:
			msg := "туннель не поднялся"
			if err != nil {
				msg = err.Error()
			}
			e.cfg.Mem.Record(nk, s.ID, false, 0)
			e.emit("failed", s.ID, msg)
			return outcome{reason: msg}
		case <-ctx.Done():
			return outcome{reason: "остановка"}
		default:
		}
		r, c, err := e.probe(actx, 1500*time.Millisecond)
		if err == nil {
			up, colo, rtt = true, c, r
		} else {
			time.Sleep(200 * time.Millisecond)
		}
	}
	if !up {
		e.cfg.Mem.Record(nk, s.ID, false, 0)
		e.emit("failed", s.ID, "нет ответа от туннеля")
		return outcome{reason: "нет ответа от туннеля"}
	}
	if !e.cfg.Policy.Allows(colo) {
		e.cfg.Mem.Record(nk, s.ID, false, 0)
		e.emit("colo_blocked", s.ID, colo)
		return outcome{reason: "дата-центр " + colo + " запрещён"}
	}
	e.cfg.Mem.Record(nk, s.ID, true, time.Since(start))
	e.setStatus(Status{State: "up", Strategy: s.ID, Colo: colo, RTT: rtt})
	e.emit("connected", s.ID, colo)

	bad := 0
	tk := time.NewTicker(e.cfg.ProbeEvery)
	defer tk.Stop()
	for {
		select {
		case <-ctx.Done():
			return outcome{wasUp: true, reason: "остановка"}
		case err := <-errc:
			msg := "туннель закрылся"
			if err != nil {
				msg = err.Error()
			}
			e.cfg.Mem.Record(nk, s.ID, false, 0)
			return outcome{wasUp: true, reason: msg}
		case <-tk.C:
			if e.cfg.NetKey() != nk {
				return outcome{wasUp: true, netChanged: true, reason: "сменилась сеть"}
			}
			r, c, err := e.probe(actx, e.cfg.ProbeEvery)
			if err != nil {
				bad++
				if bad >= e.cfg.BadProbes {
					e.cfg.Mem.Record(nk, s.ID, false, 0)
					e.emit("degraded", s.ID, "туннель перестал отвечать")
					return outcome{wasUp: true, reason: "туннель перестал отвечать"}
				}
				continue
			}
			bad = 0
			if c != colo {
				colo = c
				if !e.cfg.Policy.Allows(c) {
					e.cfg.Mem.Record(nk, s.ID, false, 0)
					e.emit("colo_blocked", s.ID, c)
					return outcome{wasUp: true, reason: "дата-центр " + c + " запрещён"}
				}
			}
			e.setStatus(Status{State: "up", Strategy: s.ID, Colo: colo, RTT: r})
		}
	}
}

// Run — главный цикл: подключиться, следить, при сбое перейти на другую стратегию.
func (e *Engine) Run(ctx context.Context) error {
	defer e.Close()
	go e.readTun()
	backoff := time.Second
	skip := ""
	for ctx.Err() == nil {
		select {
		case <-e.tunDead:
			return errors.New("TUN закрыт")
		default:
		}
		nk := e.cfg.NetKey()
		cands := e.cfg.Mem.Rank(nk, e.cfg.Strategies)
		ran := 0
		lastReason := ""
		restart := false
		for _, s := range cands {
			if ctx.Err() != nil {
				break
			}
			if s.ID == skip {
				continue
			}
			ran++
			r := e.runStrategy(ctx, nk, s)
			if ctx.Err() != nil {
				break
			}
			lastReason = r.reason
			if r.wasUp {
				skip = s.ID
				if r.netChanged {
					skip = ""
				}
				e.setStatus(Status{State: "reconnecting", Message: r.reason})
				backoff = time.Second
				restart = true
				break
			}
		}
		if ctx.Err() != nil {
			break
		}
		if restart {
			continue
		}
		skip = ""
		if ran == 0 {
			lastReason = "нет стратегий"
		}
		e.setStatus(Status{State: "failed", Message: lastReason})
		e.emit("failed", "", lastReason)
		if !sleep(ctx, backoff) {
			break
		}
		if backoff < 30*time.Second {
			backoff *= 2
		}
	}
	return ctx.Err()
}
