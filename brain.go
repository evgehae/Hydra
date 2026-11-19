package hydra

import (
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"
)

// «Мозг»: Гидра помнит не только «подключилось / нет», но и какие сервисы (Telegram, YouTube,
// WhatsApp) реально доходили через каждую стратегию в каждой сети. Эти данные влияют на порядок
// перебора и запускают придумывание новых вариантов, если сервис не дошёл.

const maxSvcEntries = 400

// RecordService запоминает, дошёл ли сервис svc через стратегию sid в сети nk.
func (m *Memory) RecordService(nk, sid, svc string, ok bool) {
	if m == nil {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Svc == nil {
		m.Svc = map[string]*stat{}
	}
	key := nk + "|" + sid + "|" + svc
	s := m.Svc[key]
	if s == nil {
		s = &stat{}
		m.Svc[key] = s
	}
	if ok {
		s.OK++
		s.LastOK = time.Now()
	} else {
		s.Fail++
		s.LastFail = time.Now()
	}
	if s.OK+s.Fail > 12 { // забываем старое: сети и блокировки меняются
		s.OK /= 2
		s.Fail /= 2
	}
	if len(m.Svc) > maxSvcEntries {
		for k, v := range m.Svc {
			last := v.LastOK
			if v.LastFail.After(last) {
				last = v.LastFail
			}
			if time.Since(last) > 30*24*time.Hour {
				delete(m.Svc, k)
			}
		}
	}
	m.saveSoonLocked()
}

// svcBonusLocked — поправка к оценке стратегии по тому, как через неё доходили сервисы
// (от −0.15 до +0.15; нет данных — 0). Вызывать под m.mu.
func (m *Memory) svcBonusLocked(nk, sid string) float64 {
	if len(m.Svc) == 0 {
		return 0
	}
	prefix := nk + "|" + sid + "|"
	sum, n := 0.0, 0
	for k, st := range m.Svc {
		if !strings.HasPrefix(k, prefix) {
			continue
		}
		sum += float64(st.OK+1) / float64(st.OK+st.Fail+2)
		n++
	}
	if n == 0 {
		return 0
	}
	return (sum/float64(n) - 0.5) * 0.3
}

// ServiceMatrix — читаемая таблица «стратегия → сервисы» для этой сети (для отчёта).
func (m *Memory) ServiceMatrix(nk string) string {
	if m == nil {
		return "  нет памяти\n"
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	byS := map[string]map[string]*stat{}
	for k, st := range m.Svc {
		p := strings.SplitN(k, "|", 3)
		if len(p) != 3 || p[0] != nk {
			continue
		}
		if byS[p[1]] == nil {
			byS[p[1]] = map[string]*stat{}
		}
		byS[p[1]][p[2]] = st
	}
	if len(byS) == 0 {
		return "  пока нет данных: проверка сервисов идёт через несколько секунд после подключения\n"
	}
	ids := make([]string, 0, len(byS))
	for id := range byS {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	if len(ids) > 12 {
		ids = ids[:12]
	}
	var b strings.Builder
	for _, id := range ids {
		names := make([]string, 0, len(byS[id]))
		for n := range byS[id] {
			names = append(names, n)
		}
		sort.Strings(names)
		fmt.Fprintf(&b, "  %s:", id)
		for _, n := range names {
			st := byS[id][n]
			fmt.Fprintf(&b, " %s ✔%d/✘%d;", n, st.OK, st.Fail)
		}
		b.WriteString("\n")
	}
	return b.String()
}

// BadColoList — дата-центры, через которые в этой сети не дошёл Telegram (пока действует запрет).
func (e *Engine) BadColoList(nk string) []string {
	e.mu.Lock()
	defer e.mu.Unlock()
	var out []string
	for k, t := range e.badColo {
		if strings.HasPrefix(k, nk+"|") && time.Since(t) < badColoFor {
			out = append(out, strings.TrimPrefix(k, nk+"|"))
		}
	}
	sort.Strings(out)
	return out
}

var (
	svcGrowMu sync.Mutex
	svcGrowAt = map[string]time.Time{}
	svcHardAt = map[string]time.Time{}
)

// svcGrow: сервис не дошёл — придумываем новые варианты под эту сеть (не чаще раза в 10 минут).
func (e *Engine) svcGrow(nk string) {
	svcGrowMu.Lock()
	if t, ok := svcGrowAt[nk]; ok && time.Since(t) < 10*time.Minute {
		svcGrowMu.Unlock()
		return
	}
	svcGrowAt[nk] = time.Now()
	svcGrowMu.Unlock()
	Logf("🧠 часть сервисов не дошла — придумываю новые варианты под сеть %s", nk)
	e.grow(nk)
}

// ReportService принимает результат «живой» проверки из приложения: настоящий HTTPS-запрос к сервису
// через туннель (с DNS внутри туннеля, поэтому подмена DNS провайдером не мешает). ok=false означает, что
// запрос не прошёл дважды подряд. Это самый надёжный сигнал: он запоминается и, если сервис мёртв,
// заставляет сразу уйти на другой дата-центр. Не чаще раза в 5 минут на сервис и не более трёх плохих
// дата-центров на сеть (если режут везде, значит, дело не в маршруте).
func (e *Engine) ReportService(name string, ok bool, detail string) {
	st := e.Status()
	if st.State != "up" || st.Strategy == "" {
		return
	}
	nk := e.cfg.NetKey()
	e.cfg.Mem.RecordService(nk, st.Strategy, name+"/live", ok)
	if ok {
		Logf("🌐 %s через %s: живая проверка прошла (%s)", name, st.Strategy, detail)
		return
	}
	Logf("🌐 ✘ %s через %s (дата-центр %s): %s", name, st.Strategy, st.Colo, detail)
	e.svcGrow(nk)
	if e.badColoCount(nk) >= 3 {
		return
	}
	svcGrowMu.Lock()
	t, seen := svcHardAt[nk+"|"+name]
	if seen && time.Since(t) < 5*time.Minute {
		svcGrowMu.Unlock()
		return
	}
	svcHardAt[nk+"|"+name] = time.Now()
	svcGrowMu.Unlock()
	select {
	case e.svcBad <- name + " не доходит через дата-центр " + st.Colo + " (проверено вживую, остальное работает) — ищу другой путь":
	default:
	}
}

// ReportSpeed запоминает скорость туннеля (кбит/с): быстрые стратегии получают приоритет, медленные
// опускаются. Порог 1500 кбит/с — ниже этого видео и мессенджеры уже мучаются.
func (e *Engine) ReportSpeed(kbps int64) {
	st := e.Status()
	if st.State != "up" || st.Strategy == "" {
		return
	}
	nk := e.cfg.NetKey()
	e.cfg.Mem.RecordService(nk, st.Strategy, "Скорость", kbps >= 1500)
	Logf("🌐 скорость через %s (дата-центр %s): ~%d кбит/с", st.Strategy, st.Colo, kbps)
}
