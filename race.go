package hydra

import (
	"context"
	"sync/atomic"
	"time"
)

// Параллельный режим: несколько стратегий поднимаются одновременно (со сдвигом), побеждает
// первая рабочая, вторая рабочая остаётся горячим резервом. При сбое основного туннеля трафик
// мгновенно переходит на резерв, без нового подключения. Пока всё хорошо, свободный слот резерва
// используется для проверки других стратегий: так Гидра учится прямо во время работы.

const (
	raceStagger  = 700 * time.Millisecond // пауза перед запуском следующей стратегии в гонке
	standbyEvery = 45 * time.Second       // как часто пробовать новый резерв
	standbyRetry = 10 * time.Minute       // не пробовать одну и ту же стратегию в резерве чаще
)

// attempt — одна запущенная стратегия.
type attempt struct {
	s      Strategy
	dev    *attemptDev
	ctx    context.Context
	cancel context.CancelFunc
	errc   chan error
	start  time.Time
	colo   string
	rtt    time.Duration
}

type verdict struct {
	a  *attempt
	ok bool
	o  outcome
}

func (e *Engine) startAttempt(ctx context.Context, s Strategy, active bool) *attempt {
	actx, cancel := context.WithCancel(ctx)
	a := &attempt{
		s:      s,
		dev:    newAttemptDev(e, actx.Done(), active),
		ctx:    actx,
		cancel: cancel,
		errc:   make(chan error, 1),
		start:  time.Now(),
	}
	Logf("▶ стратегия %s", s.ID)
	Logf("   %s", describeStrategy(s))
	go func() { a.errc <- e.cfg.Runner(actx, a.dev, s) }()
	return a
}

// verify ждёт, пока попытка поднимется, и проверяет её: ответ туннеля, дата-центр, реальный TCP.
func (e *Engine) verify(nk string, a *attempt) (bool, outcome) {
	s := a.s
	timeout := e.cfg.UpTimeout
	if e.cfg.Mem.Worked(nk, s.ID) {
		timeout = timeout * 5 / 3
	} else if e.cfg.Mem.Doomed(nk, s.ID) {
		timeout = timeout * 2 / 3
	}
	up := false
	var colo string
	var rtt time.Duration
	for !up && time.Since(a.start) < timeout {
		select {
		case err := <-a.errc:
			msg := "туннель не поднялся"
			if err != nil {
				msg = err.Error()
			}
			Logf("   ✘ %s: клиент остановился: %s", s.ID, msg)
			return false, e.fail(nk, s, msg)
		case <-a.ctx.Done():
			return false, outcome{reason: "остановка"}
		default:
		}
		r, c, err := a.dev.probe(a.ctx, 1500*time.Millisecond)
		if err == nil {
			up, colo, rtt = true, c, r
		} else {
			select {
			case <-a.ctx.Done():
				return false, outcome{reason: "остановка"}
			case <-time.After(200 * time.Millisecond):
			}
		}
	}
	if !up {
		sent, recv := int(atomic.LoadInt32(&a.dev.sent)), int(atomic.LoadInt32(&a.dev.recv))
		hint := ""
		switch {
		case recv > 0:
			hint = " — пакеты из туннеля приходят, но проба без ответа: сервер принял туннель, но не пропускает трафик"
		case s.Transport == "wg":
			hint = " — WireGuard: рукопожатие могло пройти, но данные из туннеля не возвращаются"
		case s.Params["h2"] == "1":
			hint = " — из туннеля не пришло ни одного пакета (HTTP/2 к этому адресу)"
		default:
			hint = " — из туннеля не пришло ни одного пакета: похоже, QUIC к этому адресу режется"
		}
		msg := "нет ответа от туннеля за " + itoa(int(timeout.Seconds())) + " с (в туннель ушло пакетов: " + itoa(sent) + ", пришло из туннеля: " + itoa(recv) + ")" + hint
		Logf("   ✘ %s: %s", s.ID, msg)
		return false, e.fail(nk, s, msg)
	}
	Logf("   %s: туннель ответил за %d мс, дата-центр Cloudflare: %s", s.ID, rtt.Milliseconds(), colo)
	if !e.policy().Allows(colo) {
		Logf("   ✘ %s: дата-центр %s запрещён настройками", s.ID, colo)
		e.cfg.Mem.Record(nk, s.ID, false, 0)
		e.emit("colo_blocked", s.ID, colo)
		return false, outcome{coloBlocked: colo, reason: "дата-центр " + colo + " запрещён"}
	}
	if e.cfg.TCPCheck {
		var terr error
		for i := 0; i < 3; i++ {
			if _, terr = a.dev.tcpProbe(a.ctx, e.cfg.TCPTimeout); terr == nil {
				break
			}
			if a.ctx.Err() != nil {
				return false, outcome{reason: "остановка"}
			}
		}
		if terr != nil {
			msg := "UDP через туннель идёт, а TCP — нет (туннель не пропускает интернет)"
			Logf("   ✘ %s: %s", s.ID, msg)
			return false, e.fail(nk, s, msg)
		}
	}
	e.cfg.Mem.Record(nk, s.ID, true, time.Since(a.start))
	a.colo, a.rtt = colo, rtt
	return true, outcome{}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}

// pickStandby выбирает стратегию для резерва: лучшая по памяти того же транспорта, что и основная,
// по возможности с другим адресом; другие транспорты — только если своих кандидатов не осталось.
func (e *Engine) pickStandby(nk string, primary Strategy, blocked map[string]time.Time, tried map[string]time.Time) (Strategy, bool) {
	pep := hostOnly(primary.Params["endpoint"])
	ranked := e.cfg.Mem.Rank(nk, e.allStrategies(nk))
	pass := func(sameTransport bool) (Strategy, bool) {
		var fb Strategy
		haveFB := false
		for _, s := range ranked {
			if s.ID == primary.ID || (s.Transport == primary.Transport) != sameTransport {
				continue
			}
			if t, ok := tried[s.ID]; ok && time.Since(t) < standbyRetry {
				continue
			}
			ep := s.Params["endpoint"]
			if until, ok := blocked[hostOnly(ep)]; ep != "" && ok && time.Now().Before(until) {
				continue
			}
			if e.cfg.Mem.Doomed(nk, s.ID) {
				continue
			}
			if hostOnly(ep) != pep {
				return s, true
			}
			if !haveFB {
				fb, haveFB = s, true
			}
		}
		return fb, haveFB
	}
	if s, ok := pass(true); ok {
		return s, true
	}
	return pass(false)
}

// raceRound — один «раунд» параллельного режима: гонка, затем работа с горячим резервом,
// пока соединение не оборвётся окончательно. Возвращает то же, что собирал бы последовательный перебор.
func (e *Engine) raceRound(ctx context.Context, nk string, cands []Strategy, skip string, blocked map[string]time.Time) (ran, skipped int, lastReason string, sawBlocked, restart bool, newSkip string) {
	newSkip = skip
	n := e.cfg.Parallel
	if n > 4 {
		n = 4
	}
	idx := 0
	res := make(chan verdict, 64)
	live := 0
	var all []*attempt
	defer func() {
		for _, a := range all {
			a.cancel()
		}
	}()

	nextCand := func() (Strategy, bool) {
		for idx < len(cands) {
			s := cands[idx]
			idx++
			if s.ID == skip {
				continue
			}
			ep := s.Params["endpoint"]
			if until, ok := blocked[hostOnly(ep)]; ep != "" && ok && time.Now().Before(until) {
				skipped++
				continue
			}
			return s, true
		}
		return Strategy{}, false
	}
	launch := func(s Strategy) {
		a := e.startAttempt(ctx, s, false)
		all = append(all, a)
		live++
		ran++
		go func() {
			ok, o := e.verify(nk, a)
			res <- verdict{a, ok, o}
		}()
	}
	noteFail := func(v verdict) {
		lastReason = v.o.reason
		if v.o.coloBlocked != "" {
			sawBlocked = true
			if ep := v.a.s.Params["endpoint"]; ep != "" {
				blocked[hostOnly(ep)] = time.Now().Add(10 * time.Minute)
				Logf("   адрес %s ведёт в запрещённый %s — остальные стратегии с ним пропускаю на 10 минут", ep, v.o.coloBlocked)
			}
		}
		v.a.cancel()
	}

	// ---- гонка ----
	var p *attempt
	exhausted := false
	stagger := time.NewTimer(0)
	defer stagger.Stop()
	e.setStatus(Status{State: "connecting"})
	for p == nil {
		select {
		case <-ctx.Done():
			return
		case <-e.cfg.NetChanged:
			Logf("   ↻ сеть сменилась во время подключения — начинаю заново")
			newSkip = ""
			restart = true
			return
		case <-stagger.C:
			if live < n && !exhausted {
				if s, ok := nextCand(); ok {
					launch(s)
				} else {
					exhausted = true
				}
			}
			if live == 0 && exhausted {
				return
			}
			if !exhausted {
				stagger.Reset(raceStagger)
			}
		case v := <-res:
			live--
			if v.ok {
				p = v.a
				continue
			}
			if v.o.offline {
				e.setStatus(Status{State: "reconnecting", Message: "нет интернета — жду сеть"})
				e.waitOnline(ctx)
				newSkip = ""
				restart = true
				return
			}
			noteFail(v)
			if live == 0 {
				if s, ok := nextCand(); ok {
					launch(s)
				} else {
					return
				}
			}
		}
	}

	// ---- победитель ----
	p.dev.promote()
	msg := ""
	if e.soft {
		msg = "режим «всё равно»: другого дата-центра нет"
		Logf("   ⚠ %s", msg)
	}
	colo := p.colo
	e.setStatus(Status{State: "up", Strategy: p.s.ID, Colo: colo, RTT: p.rtt, Message: msg})
	e.emit("connected", p.s.ID, colo)
	Logf("✔ подключено за %.1f с: %s, дата-центр %s, пинг %d мс", time.Since(p.start).Seconds(), p.s.ID, colo, p.rtt.Milliseconds())
	e.noteConnect()

	var sb *attempt
	tried := map[string]time.Time{}
	bad, sbBad, ticks := 0, 0, 0
	nextSb := time.Now().Add(3 * time.Second)
	lastLearn := time.Time{}

	// мгновенный переход на резерв; false — резерва нет
	failover := func(reason string) bool {
		if sb == nil {
			return false
		}
		old := p
		old.dev.demote()
		old.cancel()
		p = sb
		sb = nil
		sbBad, bad = 0, 0
		p.dev.promote()
		colo = p.colo
		e.setStatus(Status{State: "up", Strategy: p.s.ID, Colo: colo, RTT: p.rtt, Message: msg})
		e.emit("connected", p.s.ID, colo)
		Logf("⚡ резерв принял нагрузку без разрыва: %s → %s (%s)", old.s.ID, p.s.ID, reason)
		e.noteLoss(reason, true)
		nextSb = time.Now().Add(5 * time.Second)
		return true
	}
	lose := func(reason string) {
		e.noteLoss(reason, false)
		e.setStatus(Status{State: "reconnecting", Message: reason})
		newSkip = p.s.ID
		restart = true
	}

	// ---- работа ----
	tk := time.NewTicker(e.cfg.ProbeEvery)
	defer tk.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-e.cfg.NetChanged:
			Logf("↻ сеть сменилась — переподключаюсь")
			newSkip = ""
			restart = true
			return
		case v := <-res:
			live--
			if v.ok {
				if sb == nil {
					sb = v.a
					sbBad = 0
					Logf("🛡 резерв готов: %s, дата-центр %s", sb.s.ID, sb.colo)
				} else {
					v.a.cancel()
				}
			} else {
				noteFail(v)
			}
		case err := <-p.errc:
			reason := "туннель закрылся"
			if err != nil {
				reason = err.Error()
			}
			Logf("✘ %s", reason)
			e.blame(nk, p.s.ID)
			if failover(reason) {
				continue
			}
			lose(reason)
			return
		case <-tk.C:
			if e.cfg.NetKey() != nk {
				Logf("↻ сеть сменилась (%s → %s) — переподключаюсь", nk, e.cfg.NetKey())
				newSkip = ""
				restart = true
				return
			}
			ticks++
			r, c, err := p.dev.probe(p.ctx, e.cfg.ProbeEvery)
			if err == nil && e.cfg.TCPCheck && ticks%5 == 0 {
				_, err = p.dev.tcpProbe(p.ctx, e.cfg.TCPTimeout)
			}
			if err != nil {
				bad++
				Logf("   проба без ответа (%d из %d): %v", bad, e.cfg.BadProbes, err)
				if bad >= e.cfg.BadProbes {
					e.blame(nk, p.s.ID)
					e.emit("degraded", p.s.ID, "туннель перестал отвечать")
					Logf("✘ туннель перестал отвечать")
					if failover("туннель перестал отвечать") {
						continue
					}
					lose("туннель перестал отвечать")
					return
				}
			} else {
				bad = 0
				if c != colo {
					Logf("   дата-центр сменился: %s → %s", colo, c)
					colo = c
					if !e.policy().Allows(c) {
						e.cfg.Mem.Record(nk, p.s.ID, false, 0)
						e.emit("colo_blocked", p.s.ID, c)
						Logf("✘ дата-центр %s запрещён", c)
						sawBlocked = true
						if ep := p.s.Params["endpoint"]; ep != "" {
							blocked[hostOnly(ep)] = time.Now().Add(10 * time.Minute)
						}
						if failover("дата-центр " + c + " запрещён") {
							continue
						}
						lose("дата-центр " + c + " запрещён")
						return
					}
				}
				e.setStatus(Status{State: "up", Strategy: p.s.ID, Colo: colo, RTT: r, Message: msg})
			}

			// здоровье резерва
			if sb != nil {
				select {
				case serr := <-sb.errc:
					Logf("   резерв %s остановился: %v", sb.s.ID, serr)
					sb.cancel()
					sb = nil
				default:
				}
			}
			if sb != nil {
				if _, _, perr := sb.dev.probe(sb.ctx, 1500*time.Millisecond); perr != nil {
					sbBad++
					if sbBad >= e.cfg.BadProbes {
						Logf("   резерв %s не отвечает — убираю", sb.s.ID)
						sb.cancel()
						sb = nil
						sbBad = 0
					}
				} else {
					sbBad = 0
				}
			}
			// новый резерв или проверка другой стратегии «на лету»
			if sb == nil && live == 0 && time.Now().After(nextSb) {
				nextSb = time.Now().Add(standbyEvery)
				if s, ok := e.pickStandby(nk, p.s, blocked, tried); ok {
					tried[s.ID] = time.Now()
					Logf("🛡 готовлю резерв: %s", s.ID)
					launch(s)
				} else if time.Since(lastLearn) > 10*time.Minute {
					lastLearn = time.Now()
					e.learn(nk)
				}
			}
		}
	}
}
