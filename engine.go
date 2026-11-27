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
	NetState     func() string // "ok" | "whitelist" | "dead": доступен ли зарубежный интернет (nil — не проверять)
	WLScan       func(ctx context.Context) []string // какие SNI проходят к Cloudflare в режиме белых списков
	CanRun       func(Strategy) bool                // можно ли сейчас запускать стратегию (например, свободен ли аккаунт WG)
	Allow        func(Strategy) bool                // разрешена ли стратегия выбранным протоколом (nil — все)
	ServiceGate  bool                               // после подключения проверять Telegram и обходить дата-центры, где он недоступен
	YouTubeGate  bool                               // после подключения проверять YouTube (для ТВ, где Telegram нет)
	Rotate       bool                               // плановая ротация потоков по FlowTTL (патч 4)
}

func DefaultEngineConfig() EngineConfig {
	return EngineConfig{
		ProbeEvery:  4 * time.Second,
		UpTimeout:   2 * time.Second, // жёсткий timeout: не ждём 5–6 с amnezia-retry
		BadProbes:   2,               // быстрее считаем туннель мёртвым и делаем failover
		TCPCheck:    true,
		ServiceGate: true, // после подключения сразу проверяем Telegram / YouTube / WhatsApp
	}
}

type Status struct {
	State    string // connecting | up | reconnecting | failed
	Strategy string
	Colo     string
	RTT      time.Duration
	Message  string
}

type Engine struct {
	rx, tx uint64 // байты из туннеля в приложения / из приложений в туннель; первыми в структуре: 64-битные атомарные операции на 32-битных ARM требуют выравнивания
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
	once    sync.Once
	soft    bool

	// статистика работы (под mu)
	nConnect, nFailover, nLost int
	upSince                    time.Time
	lastFail                   string
	lastFailAt                 time.Time
	probesTotal, probesLost    int
	active                     atomic.Value // *attemptDev: карта, через которую сейчас идёт трафик
	testFail                   chan struct{}
	tried                      map[string]time.Time // когда стратегию последний раз пробовали
	inOutage, outageLogged     bool
	wlLast                     time.Time
	badColo                    map[string]time.Time
	badColoHits map[string]int // сколько раз colo «провалился» до бана // дата-центры, через которые не доходит Telegram

	// Патч 4: время до подключения + ротации резерва
	lastConnDur time.Duration
	sumConnDur  time.Duration
	nConnDur    int
	nRotate     int

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
		tried:    map[string]time.Time{},
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
			if r := buildICMPv6Unreach(buf[:n]); r != nil {
				e.tun.Write(r) // приложение сразу получит отказ и перейдёт на IPv4
			}
			continue
		}
		if r := dnsOverrideReply(buf[:n]); r != nil {
			e.tun.Write(r) // ответ на DNS-запрос из карты Гидры, в туннель такой запрос не уходит
			continue
		}
		if r := dotResetReply(buf[:n]); r != nil {
			e.tun.Write(r) // DoT к любому серверу сбрасываем: система вернётся к обычному DNS, где работает подмена
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
	tcpMu   sync.Mutex    // одновременно идёт одна TCP-проба
	tcpSt   atomic.Value  // tcpProbeState
}

type tcpProbeState struct {
	dst          net.IP
	dport, sport uint16
	seq          uint32
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
	if id, res, ok := ParseAReply(pkt, d.port+1); ok {
		d.e.deliver(id, res)
		return nil
	}
	if st, _ := d.tcpSt.Load().(tcpProbeState); st.dst != nil && ParseTCPSynAckFrom(pkt, st.dst, st.dport, st.sport, st.seq+1) {
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
	return d.tcpProbeTo(ctx, probeDst, 443, timeout)
}

// tcpProbeTo: SYN на любой адрес и порт через эту карту. Каждая проба берёт новый порт, а SYN
// повторяется один раз на полпути: единичная потеря пакета не должна считаться отказом.
func (d *attemptDev) tcpProbeTo(ctx context.Context, dst net.IP, dport uint16, timeout time.Duration) (time.Duration, error) {
	d.tcpMu.Lock()
	defer d.tcpMu.Unlock()
	e := d.e
	sport := uint16(41000 + rand.Intn(20000))
	seq := rand.Uint32()
	d.tcpSt.Store(tcpProbeState{dst: dst, dport: dport, sport: sport, seq: seq})
	select {
	case <-d.tcpAck:
	default:
	}
	send := func() error {
		id := uint16(atomic.AddUint32(&e.nextID, 1))
		syn := BuildTCPSynTo(e.cfg.LocalIP, dst, sport, dport, seq, id)
		if syn == nil {
			return errors.New("нет IPv4-адреса туннеля")
		}
		select {
		case d.probeQ <- syn:
			return nil
		default:
			return errors.New("очередь проб переполнена")
		}
	}
	t0 := time.Now()
	if err := send(); err != nil {
		return 0, err
	}
	retry := time.After(timeout / 2)
	deadline := time.After(timeout)
	for {
		select {
		case <-d.tcpAck:
			rtt := time.Since(t0)
			if rst := BuildTCPRstTo(e.cfg.LocalIP, dst, sport, dport, seq+1, uint16(atomic.AddUint32(&e.nextID, 1))); rst != nil {
				select {
				case d.probeQ <- rst:
				default:
				}
			}
			return rtt, nil
		case <-retry:
			retry = nil
			_ = send()
		case <-deadline:
			return 0, errors.New("нет SYN-ACK")
		case <-ctx.Done():
			return 0, ctx.Err()
		}
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
	e.cfg.Mem.RecordGenes(nk, s, false)
	e.cfg.Mem.NoteReason(nk, poolFamily(s), classifyFail(msg))
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
	e.active.Store(dev)
	errc := make(chan error, 1)
	go func() { errc <- e.cfg.Runner(actx, dev, s) }()

	timeout := e.cfg.UpTimeout
	if e.cfg.Mem.Worked(nk, s.ID) {
		timeout = timeout * 3 / 2 // уже работала: чуть больше (до ~3 с), но без 5–6 с ожидания
	} else if e.cfg.Mem.Doomed(nk, s.ID) {
		timeout = timeout * 2 / 3 // не раз подводила: не тратим на неё время
	}
	if timeout < 1200*time.Millisecond {
		timeout = 1200 * time.Millisecond
	}
	if timeout > 3500*time.Millisecond {
		timeout = 3500 * time.Millisecond // жёсткий потолок: не ждём amnezia-retry 5 с
	}
	if fl := e.slowFloor(nk); timeout < fl { // медленная сеть: путь живой, но отвечает за 0,5–2 с
		timeout = fl
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
		Logf("   ✘ дата-центр %s запрещён настройками — отбрасываю этот туннель (конфиг запомнил: он рабочий)", colo)
		e.cfg.Mem.NoteHall(nk, s, colo, rtt, true) // это не поломка стратегии: сбой не записываем
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
	e.cfg.Mem.NoteHall(nk, s, colo, rtt, false)
	msg := ""
	if e.soft {
		msg = "режим «всё равно»: другого дата-центра нет"
		Logf("   ⚠ %s", msg)
	}
	e.setStatus(Status{State: "up", Strategy: s.ID, Colo: colo, RTT: rtt, Message: msg})
	e.emit("connected", s.ID, colo)
	Logf("✔ подключено за %.1f с: %s, дата-центр %s, пинг %d мс", time.Since(start).Seconds(), s.ID, colo, rtt.Milliseconds())

	// Автоматическая проверка сервисов сразу после state: up (классический путь).
	gateCh := make(chan string, 1)
	if e.cfg.ServiceGate || e.cfg.YouTubeGate {
		go e.serviceGateDev(ctx, nk, dev, actx, s.ID, colo, gateCh)
	}

	bad, ticks := 0, 0
	tk := time.NewTicker(e.cfg.ProbeEvery)
	defer tk.Stop()
	for {
		select {
		case reason := <-gateCh:
			if reason != "" {
				Logf("✘ %s", reason)
				e.noteBadColo(nk, colo)
				e.cfg.Mem.Record(nk, s.ID, false, 0)
				return outcome{wasUp: true, coloBlocked: colo, reason: reason}
			}
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
					e.cfg.Mem.NoteHall(nk, s, c, 0, true)
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
		// сеть: есть ли вообще зарубежный интернет (режим белых списков, обрыв)
		var wlExtra []Strategy
		if st := e.netState(); st != "ok" {
			extra, wait := e.outageStep(ctx, st)
			if wait {
				continue
			}
			wlExtra = extra
		} else if e.inOutage {
			e.inOutage, e.outageLogged = false, false
			e.cfg.Mem.Rehabilitate(nk)
			Logf("♻ ограничения сняты — зарубежный интернет снова доступен")
		}
		cands := e.cfg.Mem.Rank(nk, e.allStrategies(nk))
		if len(wlExtra) > 0 {
			cands = append(append([]Strategy(nil), wlExtra...), cands...)
		}
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
			if until, ok := blockedFor(blocked, epKey); ep != "" && ok && time.Now().Before(until) {
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
				blocked[prefix24(epKey)] = time.Now().Add(10 * time.Minute)
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
			e.clearBadColos("")
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
			e.clearBadColos(nk)
			msg = "⛔ рабочие маршруты ведут только в запрещённые дата-центры — сбрасываю запреты и пробую снова"
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

// ErrRunnerBusy: клиент туннеля сейчас занят (например, единственный аккаунт WireGuard уже держит сессию).
var ErrRunnerBusy = errors.New("клиент туннеля занят")

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
	// счётчики трафика — с момента текущего up (иначе 0B после ротации выглядит как «пустой» туннель)
	atomic.StoreUint64(&e.rx, 0)
	atomic.StoreUint64(&e.tx, 0)
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
