package hydra

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Engine — «сердце» Гидры на телефоне. Android отдаёт TUN (поток IP-пакетов),
// Engine гоняет их через туннель WARP и сам следит за ним:
//   - после подключения узнаёт дата-центр Cloudflare; запрещённый — отбрасывает;
//   - проверяет, что через туннель реально проходит TCP, а не только «рукопожатие»;
//   - при смене сети (Wi-Fi ↔ мобильная) сразу переподключается;
//   - при сбое переходит на другую стратегию; запоминает, что работало в каждой сети;
//   - всё, что происходит и почему, пишет в журнал.

// PacketDevice — «сетевая карта» для туннеля (те же методы, что у TunnelDevice в usque).
type PacketDevice interface {
	ReadPacket(buf []byte) (int, error)
	WritePacket(pkt []byte) error
}

// Runner держит туннель по стратегии s, пока ctx не отменён или не случилась
// непоправимая ошибка. Пакеты читает/пишет через dev.
type Runner func(ctx context.Context, dev PacketDevice, s Strategy) error

type EngineConfig struct {
	LocalIP      net.IP // IPv4-адрес внутри туннеля (из аккаунта)
	Strategies   []Strategy
	Runner       Runner
	Policy       *ColoPolicy
	SoftFallback bool // если все адреса ведут в запрещённый дата-центр — всё равно подключиться
	Mem          *Memory
	NetKey       func() string
	NetChanged   <-chan struct{} // сигнал «сеть сменилась» от Android
	ProbeEvery   time.Duration
	UpTimeout    time.Duration // сколько ждать первого ответа после старта стратегии
	BadProbes    int           // сколько проб подряд без ответа = туннель умер
	TCPCheck     bool          // проверять реальную передачу TCP
	TCPTimeout   time.Duration // ожидание SYN-ACK (по умолчанию 2 с)
	NetAlive     func() bool   // есть ли вообще интернет мимо туннеля (nil — не проверять)
	DropV6       bool          // в аккаунте нет IPv6: пакеты v6 из TUN отбрасываются
	Parallel     int           // >1: параллельная гонка стратегий и горячий резерв; 0/1 — по очереди
}

func DefaultEngineConfig() EngineConfig {
	return EngineConfig{ProbeEvery: 3 * time.Second, UpTimeout: 6 * time.Second, BadProbes: 3, TCPCheck: true}
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
	tcpPort uint16
	tcpSeq  uint32
	tcpAck  chan struct{}
	nextID  uint32
	events  chan Event
	tunDead chan struct{}
	rx, tx  uint64 // байты из туннеля в приложения / из приложений в туннель
	once    sync.Once
	soft    bool

	// статистика работы (под mu)
	nConnect, nFailover, nLost int
	upSince                    time.Time
	lastFail                   string
	lastFailAt                 time.Time
	probesTotal, probesLost    int
	testFail                   chan struct{}

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
	if cfg.TCPTimeout <= 0 {
		cfg.TCPTimeout = 2 * time.Second
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
		port:    uint16(20000 + rand.Intn(20000)),
		tcpPort: uint16(41000 + rand.Intn(20000)),
		tcpAck:  make(chan struct{}, 1),
		events:  make(chan Event, 64),
		tunDead: make(chan struct{}),
		waiters: map[uint16]chan string{},
		status:  Status{State: "connecting"},
		testFail: make(chan struct{}, 1),
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

func (e *Engine) policy() *ColoPolicy {
	if e.soft {
		return nil
	}
	return e.cfg.Policy
}

// readTun читает пакеты приложений. Пока туннеля нет, лишние пакеты отбрасываются.
func (e *Engine) readTun() {
	defer close(e.tunDead)
	for {
		buf := make([]byte, 2048)
		n, err := e.tun.Read(buf)
		if err != nil {
			return
		}
		if e.cfg.DropV6 && n > 0 && buf[0]>>4 == 6 {
			continue
		}
		atomic.AddUint64(&e.tx, uint64(n))
		select {
		case e.out <- buf[:n]:
		default:
		}
	}
}

// attemptDev — «карта» одной попытки: после отмены попытки её горутины просыпаются с ошибкой
// и не крадут пакеты у следующей. У каждой попытки свои порты и очередь проб, поэтому несколько
// попыток могут работать одновременно; трафик приложений идёт только через активную.
type attemptDev struct {
	e       *Engine
	done    <-chan struct{}
	probeQ  chan []byte
	port    uint16
	tcpPort uint16
	tcpSeq  uint32
	tcpAck  chan struct{}
	active  int32         // 1 — через эту карту идёт трафик приложений
	sent    int32         // сколько пакетов клиент туннеля забрал у нас (пробы и трафик)
	recv    int32         // сколько пакетов клиент туннеля отдал нам
	wake    chan struct{} // будит ReadPacket, когда карта становится активной
	stats   atomic.Value  // func() string: дополнительные счётчики клиента туннеля (например WireGuard)
}

// SetStats принимает от клиента туннеля функцию с его счётчиками для диагностики.
func (d *attemptDev) SetStats(f func() string) { d.stats.Store(f) }

func (d *attemptDev) extra() string {
	if f, ok := d.stats.Load().(func() string); ok {
		return f()
	}
	return ""
}

func newAttemptDev(e *Engine, done <-chan struct{}, active bool) *attemptDev {
	d := &attemptDev{
		e:       e,
		done:    done,
		probeQ:  make(chan []byte, 16),
		port:    uint16(20000 + rand.Intn(20000)),
		tcpPort: uint16(41000 + rand.Intn(20000)),
		tcpAck:  make(chan struct{}, 1),
		wake:    make(chan struct{}, 1),
	}
	if active {
		d.active = 1
	}
	return d
}

// promote делает карту активной: с этого момента через неё идёт трафик приложений.
func (d *attemptDev) promote() {
	atomic.StoreInt32(&d.active, 1)
	select {
	case d.wake <- struct{}{}:
	default:
	}
}

// demote лишает карту трафика приложений (она остаётся пригодной для проб).
func (d *attemptDev) demote() { atomic.StoreInt32(&d.active, 0) }

func (d *attemptDev) ReadPacket(buf []byte) (int, error) {
	for {
		var outc <-chan []byte
		if atomic.LoadInt32(&d.active) == 1 {
			outc = d.e.out
		}
		select {
		case <-d.done:
			return 0, io.EOF
		case <-d.e.tunDead:
			return 0, io.EOF
		case p := <-d.probeQ:
			atomic.AddInt32(&d.sent, 1)
			return copy(buf, p), nil
		case p := <-outc:
			atomic.AddInt32(&d.sent, 1)
			return copy(buf, p), nil
		case <-d.wake:
		}
	}
}

func (d *attemptDev) WritePacket(pkt []byte) error {
	select {
	case <-d.done:
		return io.ErrClosedPipe
	default:
	}
	atomic.AddInt32(&d.recv, 1)
	if id, colo, ok := ParseColoReply(pkt, d.port); ok {
		d.e.deliver(id, colo)
		return nil
	}
	if ParseTCPSynAck(pkt, d.tcpPort, atomic.LoadUint32(&d.tcpSeq)+1) {
		select {
		case d.tcpAck <- struct{}{}:
		default:
		}
		return nil
	}
	if atomic.LoadInt32(&d.active) != 1 {
		return nil // резервный туннель трафик приложений не пропускает
	}
	atomic.AddUint64(&d.e.rx, uint64(len(pkt)))
	_, err := d.e.tun.Write(pkt)
	return err
}

// Traffic — сколько байт получено из туннеля и отправлено в него с запуска.
func (e *Engine) Traffic() (rx, tx uint64) {
	return atomic.LoadUint64(&e.rx), atomic.LoadUint64(&e.tx)
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

// probe шлёт UDP-пробу (DNS id.server) через эту карту и ждёт ответ: задержка и код дата-центра.
func (d *attemptDev) probe(ctx context.Context, timeout time.Duration) (time.Duration, string, error) {
	e := d.e
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
	pkt := BuildColoProbe(e.cfg.LocalIP, d.port, id)
	if pkt == nil {
		return 0, "", errors.New("нет IPv4-адреса туннеля")
	}
	t0 := time.Now()
	select {
	case d.probeQ <- pkt:
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

// tcpProbe: SYN на 1.1.1.1:443 через эту карту, ждём SYN-ACK.
func (d *attemptDev) tcpProbe(ctx context.Context, timeout time.Duration) (time.Duration, error) {
	e := d.e
	seq := rand.Uint32()
	atomic.StoreUint32(&d.tcpSeq, seq)
	select {
	case <-d.tcpAck:
	default:
	}
	id := uint16(atomic.AddUint32(&e.nextID, 1))
	syn := BuildTCPSyn(e.cfg.LocalIP, d.tcpPort, seq, id)
	if syn == nil {
		return 0, errors.New("нет IPv4-адреса туннеля")
	}
	t0 := time.Now()
	select {
	case d.probeQ <- syn:
	default:
		return 0, errors.New("очередь проб переполнена")
	}
	select {
	case <-d.tcpAck:
		rtt := time.Since(t0)
		if rst := BuildTCPRst(e.cfg.LocalIP, d.tcpPort, seq+1, id+1); rst != nil {
			select {
			case d.probeQ <- rst:
			default:
			}
		}
		return rtt, nil
	case <-time.After(timeout):
		return 0, errors.New("нет SYN-ACK")
	case <-ctx.Done():
		return 0, ctx.Err()
	}
}

type outcome struct {
	wasUp       bool
	netChanged  bool
	coloBlocked string
	reason      string
	offline     bool // интернета нет совсем: стратегию не винить, ждать сеть
}

func policyText(p *ColoPolicy) string {
	if p == nil || (len(p.Block) == 0 && len(p.Allow) == 0) {
		return "нет"
	}
	s := strings.Join(p.Block, ",")
	if len(p.Allow) > 0 {
		s += "; только: " + strings.Join(p.Allow, ",")
	}
	return s
}

func (e *Engine) fail(nk string, s Strategy, msg string) outcome {
	if !e.blame(nk, s.ID) {
		return outcome{reason: "нет интернета", offline: true}
	}
	e.emit("failed", s.ID, msg)
	return outcome{reason: msg}
}

func (e *Engine) runStrategy(ctx context.Context, nk string, s Strategy) outcome {
	e.setStatus(Status{State: "connecting", Strategy: s.ID})
	e.emit("connecting", s.ID, "")
	Logf("▶ стратегия %s", s.ID)
	Logf("   %s", describeStrategy(s))
	select {
	case <-e.cfg.NetChanged:
	default:
	}
	// старые пробы от прошлых попыток в очереди только мешают
	for drained := false; !drained; {
		select {
		case <-e.probeQ:
		default:
			drained = true
		}
	}

	actx, cancel := context.WithCancel(ctx)
	defer cancel()
	dev := newAttemptDev(e, actx.Done(), true)
	errc := make(chan error, 1)
	go func() { errc <- e.cfg.Runner(actx, dev, s) }()

	timeout := e.cfg.UpTimeout
	if e.cfg.Mem.Worked(nk, s.ID) {
		timeout = timeout * 5 / 3 // уже работала здесь: на медленной сети рукопожатие бывает 5–6 с
	} else if e.cfg.Mem.Doomed(nk, s.ID) {
		timeout = timeout * 2 / 3 // не раз подводила: не тратим на неё время
	}
	start := time.Now()
	var colo string
	var rtt time.Duration
	up := false
	for !up && time.Since(start) < timeout {
		select {
		case err := <-errc:
			msg := "туннель не поднялся"
			if err != nil {
				msg = err.Error()
			}
			Logf("   ✘ клиент остановился: %s", msg)
			return e.fail(nk, s, msg)
		case <-ctx.Done():
			return outcome{reason: "остановка"}
		case <-e.cfg.NetChanged:
			Logf("   ↻ сеть сменилась во время подключения — начинаю заново")
			return outcome{netChanged: true, reason: "сменилась сеть"}
		default:
		}
		r, c, err := dev.probe(actx, 1500*time.Millisecond)
		if err == nil {
			up, colo, rtt = true, c, r
		} else {
			time.Sleep(200 * time.Millisecond)
		}
	}
	if !up {
		hint := ""
		if s.Transport == "wg" {
			hint = " — похоже, провайдер режет WireGuard (UDP) к этому адресу"
		} else if s.Params["h2"] != "1" {
			hint = " — похоже, провайдер режет QUIC к этому адресу"
		}
		msg := fmt.Sprintf("нет ответа от туннеля за %d с%s", int(timeout.Seconds()), hint)
		Logf("   ✘ %s", msg)
		return e.fail(nk, s, msg)
	}
	Logf("   туннель ответил за %d мс, дата-центр Cloudflare: %s", rtt.Milliseconds(), colo)

	if !e.policy().Allows(colo) {
		Logf("   ✘ дата-центр %s запрещён настройками — отбрасываю этот туннель", colo)
		e.cfg.Mem.Record(nk, s.ID, false, 0)
		e.emit("colo_blocked", s.ID, colo)
		return outcome{coloBlocked: colo, reason: "дата-центр " + colo + " запрещён"}
	}

	if e.cfg.TCPCheck {
		var tcpRTT time.Duration
		var terr error
		for i := 0; i < 3; i++ {
			if tcpRTT, terr = dev.tcpProbe(actx, e.cfg.TCPTimeout); terr == nil {
				break
			}
			if ctx.Err() != nil {
				return outcome{reason: "остановка"}
			}
		}
		if terr != nil {
			msg := "UDP через туннель идёт, а TCP — нет (туннель не пропускает интернет)"
			Logf("   ✘ %s", msg)
			return e.fail(nk, s, msg)
		}
		Logf("   ✔ TCP до 1.1.1.1:443 проходит (%d мс)", tcpRTT.Milliseconds())
	}

	e.cfg.Mem.Record(nk, s.ID, true, time.Since(start))
	msg := ""
	if e.soft {
		msg = "режим «всё равно»: другого дата-центра нет"
		Logf("   ⚠ %s", msg)
	}
	e.setStatus(Status{State: "up", Strategy: s.ID, Colo: colo, RTT: rtt, Message: msg})
	e.emit("connected", s.ID, colo)
	Logf("✔ подключено за %.1f с: %s, дата-центр %s, пинг %d мс", time.Since(start).Seconds(), s.ID, colo, rtt.Milliseconds())

	bad, ticks := 0, 0
	tk := time.NewTicker(e.cfg.ProbeEvery)
	defer tk.Stop()
	for {
		select {
		case <-ctx.Done():
			return outcome{wasUp: true, reason: "остановка"}
		case <-e.cfg.NetChanged:
			Logf("↻ сеть сменилась — переподключаюсь")
			return outcome{wasUp: true, netChanged: true, reason: "сменилась сеть"}
		case err := <-errc:
			msg := "туннель закрылся"
			if err != nil {
				msg = err.Error()
			}
			Logf("✘ %s", msg)
			e.blame(nk, s.ID)
			return outcome{wasUp: true, reason: msg}
		case <-tk.C:
			if e.cfg.NetKey() != nk {
				Logf("↻ сеть сменилась (%s → %s) — переподключаюсь", nk, e.cfg.NetKey())
				return outcome{wasUp: true, netChanged: true, reason: "сменилась сеть"}
			}
			ticks++
			r, c, err := dev.probe(actx, e.cfg.ProbeEvery)
			if err == nil && e.cfg.TCPCheck && ticks%5 == 0 {
				_, err = dev.tcpProbe(actx, e.cfg.TCPTimeout)
			}
			if err != nil {
				bad++
				Logf("   проба без ответа (%d из %d): %v", bad, e.cfg.BadProbes, err)
				if bad >= e.cfg.BadProbes {
					e.blame(nk, s.ID)
					e.emit("degraded", s.ID, "туннель перестал отвечать")
					Logf("✘ туннель перестал отвечать — меняю стратегию")
					return outcome{wasUp: true, reason: "туннель перестал отвечать"}
				}
				continue
			}
			bad = 0
			if c != colo {
				Logf("   дата-центр сменился: %s → %s", colo, c)
				colo = c
				if !e.policy().Allows(c) {
					e.cfg.Mem.Record(nk, s.ID, false, 0)
					e.emit("colo_blocked", s.ID, c)
					Logf("✘ дата-центр %s запрещён — меняю стратегию", c)
					return outcome{wasUp: true, coloBlocked: c, reason: "дата-центр " + c + " запрещён"}
				}
			}
			e.setStatus(Status{State: "up", Strategy: s.ID, Colo: colo, RTT: r, Message: e.Status().Message})
		}
	}
}

// Run — главный цикл: подключиться, следить, при сбое перейти на другую стратегию.
func (e *Engine) Run(ctx context.Context) error {
	defer e.Close()
	go e.readTun()
	select { // стартовый сигнал о смене сети (его присылает Android при запуске) не нужен
	case <-e.cfg.NetChanged:
	default:
	}
	Logf("Гидра запущена: стратегий %d, запрещённые дата-центры: %s", len(e.cfg.Strategies), policyText(e.cfg.Policy))

	backoff := time.Second
	skip := ""
	lastNK := ""
	blocked := map[string]time.Time{}
	for ctx.Err() == nil {
		select {
		case <-e.tunDead:
			return errors.New("TUN закрыт")
		default:
		}
		nk := e.cfg.NetKey()
		if nk != lastNK {
			if lastNK != "" {
				Logf("↻ сеть: %s → %s", lastNK, nk)
			} else {
				Logf("сеть: %s", nk)
			}
			lastNK = nk
			blocked = map[string]time.Time{}
			e.soft = false
			skip = ""
			if n := e.cfg.Mem.Prune(nk); n > 0 {
				Logf("🧹 убрал %d придуманных способов, которые в этой сети не работают", n)
			}
		}
		cands := e.cfg.Mem.Rank(nk, e.allStrategies(nk))
		ran, skipped := 0, 0
		lastReason := ""
		sawBlocked := false
		restart := false
		if e.cfg.Parallel > 1 {
			ran, skipped, lastReason, sawBlocked, restart, skip = e.raceRound(ctx, nk, cands, skip, blocked)
			cands = nil // старый последовательный перебор ниже не нужен
		}
		for _, s := range cands {
			if ctx.Err() != nil {
				break
			}
			if s.ID == skip {
				continue
			}
			ep := s.Params["endpoint"]
			epKey := hostOnly(ep)
			if until, ok := blocked[epKey]; ep != "" && ok && time.Now().Before(until) {
				skipped++
				continue
			}
			ran++
			r := e.runStrategy(ctx, nk, s)
			if ctx.Err() != nil {
				break
			}
			lastReason = r.reason
			if r.offline {
				e.setStatus(Status{State: "reconnecting", Message: "нет интернета — жду сеть"})
				e.waitOnline(ctx)
				skip = ""
				restart = true
				break
			}
			if r.coloBlocked != "" {
				sawBlocked = true
				if ep != "" {
					blocked[epKey] = time.Now().Add(10 * time.Minute)
					Logf("   адрес %s ведёт в запрещённый %s — остальные стратегии с ним пропускаю на 10 минут", ep, r.coloBlocked)
				}
			}
			if r.netChanged {
				skip = ""
				restart = true
				break
			}
			if r.wasUp {
				skip = s.ID
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
		if sawBlocked && e.cfg.SoftFallback && !e.soft {
			e.soft = true
			blocked = map[string]time.Time{}
			Logf("⚠ все рабочие адреса ведут в запрещённые дата-центры; включён режим «всё равно» — принимаю любой")
			continue
		}
		skip = ""
		if ran > 0 && !sawBlocked {
			e.learn(nk) // все способы подвели — придумываем новые на основе лучших
		}
		msg := lastReason
		switch {
		case ran == 0 && skipped > 0:
			msg = "⛔ все адреса сейчас ведут в запрещённые дата-центры — жду"
		case ran == 0:
			msg = "нет стратегий"
		case sawBlocked:
			msg = "⛔ рабочие маршруты ведут только в запрещённые дата-центры"
		}
		Logf("✘ подключиться не удалось: %s; повтор через %s", msg, backoff)
		e.setStatus(Status{State: "failed", Message: msg})
		e.emit("failed", "", msg)
		if !sleep(ctx, backoff) {
			break
		}
		if backoff < 30*time.Second {
			backoff *= 2
		}
	}
	return ctx.Err()
}

func (e *Engine) noteProbe(ok bool) {
	e.mu.Lock()
	e.probesTotal++
	if !ok {
		e.probesLost++
	}
	e.mu.Unlock()
}

func (e *Engine) probeStats() (total, lost int) {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.probesTotal, e.probesLost
}

// TestFailover просит движок имитировать отказ основного туннеля, чтобы проверить горячий резерв.
func (e *Engine) TestFailover() {
	select {
	case e.testFail <- struct{}{}:
	default:
	}
}

func (e *Engine) noteConnect() {
	e.mu.Lock()
	e.nConnect++
	e.upSince = time.Now()
	e.mu.Unlock()
}

func (e *Engine) noteLoss(reason string, failover bool) {
	e.mu.Lock()
	if failover {
		e.nFailover++
	} else {
		e.nLost++
	}
	e.lastFail = reason
	e.lastFailAt = time.Now()
	e.mu.Unlock()
}

// Stats — сводка работы движка для диагностики.
func (e *Engine) Stats() string {
	e.mu.Lock()
	defer e.mu.Unlock()
	mode := "по очереди"
	if e.cfg.Parallel > 1 {
		mode = "параллельный (гонка + горячий резерв)"
	}
	s := "режим: " + mode + "\n"
	s += "подключений: " + itoa(e.nConnect) + ", мгновенных переходов на резерв: " + itoa(e.nFailover) + ", потерь без резерва: " + itoa(e.nLost) + "\n"
	if !e.upSince.IsZero() {
		s += "с последнего подключения: " + time.Since(e.upSince).Round(time.Second).String() + "\n"
	}
	if e.probesTotal > 0 {
		s += "проб: " + itoa(e.probesTotal) + ", потеряно: " + itoa(e.probesLost) + "\n"
	}
	if e.lastFail != "" {
		s += "последний сбой: " + e.lastFail + " (" + e.lastFailAt.Format("15:04:05") + ")\n"
	}
	return s
}
