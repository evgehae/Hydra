package hydra

import (
	"context"
	"net"
	"strings"
	"time"
)

var tgTargets = []struct {
	ip   string
	port uint16
}{
	{"149.154.167.51", 443}, {"149.154.175.50", 443}, {"149.154.167.91", 443}, {"91.108.56.130", 443},
}

const badColoFor = 6 * time.Hour

// coloAllowed: разрешён ли дата-центр настройками и не «плохой» ли он (Telegram не доходит).
func (e *Engine) coloAllowed(nk, colo string) bool {
	if !e.policy().Allows(colo) {
		return false
	}
	if e.soft {
		return true
	}
	return !e.isBadColo(nk, colo)
}

func (e *Engine) isBadColo(nk, colo string) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	t, ok := e.badColo[nk+"|"+colo]
	return ok && time.Since(t) < badColoFor
}

func (e *Engine) noteBadColo(nk, colo string) {
	e.mu.Lock()
	if e.badColo == nil {
		e.badColo = map[string]time.Time{}
	}
	e.badColo[nk+"|"+colo] = time.Now()
	e.mu.Unlock()
}

func (e *Engine) badColoCount(nk string) int {
	e.mu.Lock()
	defer e.mu.Unlock()
	n := 0
	for k, t := range e.badColo {
		if strings.HasPrefix(k, nk+"|") && time.Since(t) < badColoFor {
			n++
		}
	}
	return n
}

// knownBlocked: по памяти известно, что адрес этой стратегии в этой сети попадает в запрещённый дата-центр.
func (e *Engine) knownBlocked(nk string, s Strategy) bool {
	ep := s.Params["endpoint"]
	if ep == "" {
		return false
	}
	kc := e.cfg.Mem.KnownColo(nk, ep)
	return kc != "" && !e.coloAllowed(nk, kc)
}

// Сервисы «мягкой» проверки: у них нет постоянных адресов, адрес берётся DNS-запросом внутри туннеля. Результат
// идёт в память (влияет на порядок стратегий и запускает придумывание новых), но дата-центр из-за них не банится:
// запрет дата-центров без запасных оставил бы VPN без выхода.
var svcSoft = []struct{ name, host string }{
	{"YouTube", "redirector.googlevideo.com"},
	{"WhatsApp", "web.whatsapp.com"},
}

// serviceGate проверяет через только что поднятый туннель, доходят ли Telegram, YouTube и WhatsApp.
// Если интернет работает, а ни один сервер Telegram не отвечает, — дата-центр помечается плохим, и Гидра
// ищет другой путь. Больше трёх плохих дата-центров в одной сети не набираем: значит, дело не в них.
// Результаты по всем сервисам запоминаются: стратегии, через которые доходит всё, получают приоритет.
func (e *Engine) serviceGate(ctx context.Context, nk string, a *attempt, out chan<- string) {
	e.serviceGateDev(ctx, nk, a.dev, a.ctx, a.s.ID, a.colo, out)
}

// serviceGateDev — та же проверка, но работает и в классическом (не race) режиме.
// Жёсткие правила (чтобы не было «up, а YouTube/Telegram молчат»):
//  1) Telegram недоступен → сразу смена пути (если ещё не слишком много плохих ДЦ).
//  2) Telegram ок, но YouTube и WhatsApp оба недоступны → тоже смена пути.
//  3) Только один soft-сервис упал → запоминаем, генерируем варианты, путь не рвём.
func (e *Engine) serviceGateDev(ctx context.Context, nk string, dev *attemptDev, actx context.Context, sid, colo string, out chan<- string) {
	hard := e.badColoCount(nk) < 3
	select {
	case <-ctx.Done():
		return
	case <-actx.Done():
		return
	case <-time.After(400 * time.Millisecond): // быстрее отсекаем «up без интернета»
	}
	base := false
	for _, ip := range []string{"1.1.1.1", "8.8.8.8"} {
		if _, err := dev.tcpProbeTo(actx, net.ParseIP(ip).To4(), 443, 1200*time.Millisecond); err == nil {
			base = true
			break
		}
		if actx.Err() != nil {
			return
		}
	}
	if !base {
		// Базовый интернет через туннель не отвечает — путь мёртвый (всегда меняем).
		Logf("✘ через %s (%s) нет ответа до 1.1.1.1/8.8.8.8 — путь мёртвый", sid, colo)
		select {
		case out <- "через туннель нет ответа даже до 1.1.1.1/8.8.8.8 — ищу другой путь":
		default:
		}
		return
	}
	tgOK := false
	for _, t := range tgTargets {
		if _, err := dev.tcpProbeTo(actx, net.ParseIP(t.ip).To4(), t.port, 2*time.Second); err == nil {
			tgOK = true
			break
		}
		if actx.Err() != nil {
			return
		}
	}
	e.cfg.Mem.RecordService(nk, sid, "Telegram", tgOK)
	if tgOK {
		Logf("✔ Telegram через %s (дата-центр %s) достижим", sid, colo)
	} else {
		Logf("✘ Telegram через %s (дата-центр %s) не достижим", sid, colo)
		if hard {
			select {
			case out <- "Telegram не доходит через дата-центр " + colo + " (остальной интернет работает) — ищу другой путь":
			default:
			}
			return
		}
	}
	failed := 0
	softTotal := 0
	dnsFail := 0
	for _, t := range svcSoft {
		if actx.Err() != nil || ctx.Err() != nil {
			return
		}
		ip, err := dev.resolveA(actx, t.host, 2*time.Second)
		if err != nil {
			dnsFail++
			softTotal++
			failed++
			Logf("✘ %s: DNS через туннель не ответил (%v)", t.name, err)
			e.cfg.Mem.RecordService(nk, sid, t.name, false)
			continue
		}
		softTotal++
		_, err = dev.tcpProbeTo(actx, ip, 443, 2*time.Second)
		if actx.Err() != nil {
			return
		}
		e.cfg.Mem.RecordService(nk, sid, t.name, err == nil)
		if err == nil {
			Logf("✔ %s через %s достижим", t.name, sid)
		} else {
			failed++
			Logf("✘ %s через %s (дата-центр %s) не достижим: %v", t.name, sid, colo, err)
		}
	}
	// DNS в туннеле мёртв → путь бесполезен для приложений (YouTube и т.д.)
	if hard && dnsFail >= 2 {
		select {
		case out <- "DNS через туннель не отвечает (" + colo + ") — ищу другой путь":
		default:
		}
		return
	}
	// Все soft-сервисы лежат — путь плохой, даже если Telegram «ок» по IP.
	if hard && softTotal >= 2 && failed >= softTotal {
		select {
		case out <- "YouTube/WhatsApp не доходят через " + colo + " при живом Telegram — ищу другой путь":
		default:
		}
		return
	}
	if failed > 0 {
		e.svcGrow(nk)
	}
}
