package hydra

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
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

// resolveA узнаёт IPv4-адрес имени запросом DNS ВНУТРИ туннеля (к 1.1.1.1). Оператор такой запрос не видит,
// поэтому подмена или блокировка имён на его DNS не мешает, как не мешает она и приложениям внутри VPN.
func (d *attemptDev) resolveA(ctx context.Context, host string, timeout time.Duration) (net.IP, error) {
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
	pkt := BuildDNSQueryA(e.cfg.LocalIP, d.port+1, id, host)
	if pkt == nil {
		return nil, errors.New("не удалось построить DNS-запрос")
	}
	select {
	case d.probeQ <- pkt:
	default:
		return nil, errors.New("очередь проб переполнена")
	}
	select {
	case res := <-ch:
		if ip := net.ParseIP(res); ip != nil {
			if ip4 := ip.To4(); ip4 != nil {
				return ip4, nil
			}
		}
		if res == "rcode=nxdomain" {
			return nil, errors.New("DNS через туннель: такого имени нет")
		}
		return nil, errors.New("DNS через туннель: " + res)
	case <-time.After(timeout):
		return nil, errors.New("DNS через туннель не ответил")
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

// ---------- обучение по классам стратегий ----------
// Результат одной стратегии говорит и о её «родне»: о других адресах того же варианта и о соседях по подсети.
// Если вариант j4 заработал на 162.159.192.3, то j4 на 162.159.192.4 надо пробовать сразу. Если десять адресов
// подряд не ответили на один вариант, одиннадцатый тоже не ответит: время тратится на другие.

type clsStat struct{ ok, fail int }

// stratKeys возвращает семейство ("wg"), вариант ("wg/j4") и подсеть адреса ("wg/162.159.192").
func stratKeys(id string) (fam, variant, subnet string) {
	parts := strings.Split(id, "/")
	fam = parts[0]
	if len(parts) < 3 {
		return
	}
	variant = fam + "/" + parts[len(parts)-1]
	host := parts[1]
	if i := strings.LastIndex(host, ":"); i > 0 && strings.Count(host, ":") == 1 {
		host = host[:i]
	}
	if p := strings.Split(host, "."); len(p) == 4 {
		subnet = fam + "/" + p[0] + "." + p[1] + "." + p[2]
	}
	return
}

// classAggLocked суммирует успехи и сбои по классам для сети net. Вызывать под m.mu.
func (m *Memory) classAggLocked(net string) map[string]*clsStat {
	agg := map[string]*clsStat{}
	add := func(k string, st *stat) {
		c := agg[k]
		if c == nil {
			c = &clsStat{}
			agg[k] = c
		}
		c.ok += st.OK
		c.fail += st.Fail
	}
	for id, st := range m.Nets[net] {
		fam, variant, subnet := stratKeys(id)
		add("f|"+fam, st)
		if variant != "" {
			add("v|"+variant, st)
		}
		if subnet != "" {
			add("s|"+subnet, st)
		}
	}
	return agg
}

// classAdj — поправка к оценке стратегии по опыту её класса (без учёта собственной статистики self).
func classAdj(agg map[string]*clsStat, id string, self *stat) float64 {
	fam, variant, subnet := stratKeys(id)
	adj := 0.0
	one := func(k string, wOK, wBad float64, minFail int) {
		c := agg[k]
		if c == nil {
			return
		}
		ok, fail := c.ok, c.fail
		if self != nil {
			ok -= self.OK
			fail -= self.Fail
		}
		if ok > 0 && ok*4 >= fail {
			adj += wOK
		} else if ok == 0 && fail >= minFail {
			adj -= wBad
		}
	}
	one("f|"+fam, 0, 0.15, 12)
	if variant != "" {
		one("v|"+variant, 0.2, 0.25, 6)
	}
	if subnet != "" {
		one("s|"+subnet, 0.2, 0.25, 4)
	}
	return adj
}

// netSeeds — начальные наблюдения по операторам (обновлено 2026-11-21). Мягкие priors:
// реальные результаты в памяти всегда важнее, стратегия с 3 сбоями подряд теряет бонус.
// Ключ — "cell:MCCMNC".
var netSeeds = map[string][]string{
	// Билайн (25099): MASQUE часто уходит в DME/LED или молчит. Лучше работает WireGuard
	// на подсети 162.159.192.x с разными сигнатурами (j4, q3, v4, s3).
	"cell:25099": {
		"wg/162.159.192.6:2408/h3", "wg/162.159.192.4:2408/h3", "wg/162.159.192.3:2408/h3",
		"wg/162.159.192.4:2408/j4", "wg/162.159.192.3:2408/j4",
		"wg/162.159.192.4:2408/q3", "wg/162.159.192.4:2408/q3r",
		"wg/162.159.192.4:2408/v4", "wg/162.159.192.3:2408/v4",
		"wg/162.159.192.4:2408/s3", "wg/162.159.192.3:2408/s3",
		"wg/188.114.96.41:2408/s3", "wg/188.114.96.41:2408/v4r",
	},
	// МТС (25001): MASQUE через 162.159.198.x хорошо доходит до HEL/FRA.
	"cell:25001": {
		"h3/162.159.198.1/vk4x6", "h3/162.159.198.2/g3+speed",
		"h3/162.159.198.1/vk6x6", "h3/162.159.198.1/g3",
		"wg/162.159.192.4:2408/s3", "wg/162.159.192.3:2408/s3",
	},
	// МегаФон (25002): обычно ближе к МТС, MASQUE + WG на HEL/FRA.
	"cell:25002": {
		"h3/162.159.198.1/vk4x6", "h3/162.159.198.2/g3+speed",
		"wg/162.159.192.4:2408/s3", "wg/162.159.192.3:2408/s3",
		"wg/188.114.96.41:2408/s3",
	},
	// Tele2 (25020): часто жёстче Билайна по QUIC. Предпочитаем WG с stun/quic сигнатурами
	// и европейские ДЦ. Избегаем чистого MASQUE без фейков.
	"cell:25020": {
		"wg/162.159.192.4:2408/s3", "wg/162.159.192.3:2408/s3",
		"wg/162.159.192.4:2408/q3", "wg/162.159.192.4:2408/q3r",
		"wg/162.159.192.4:2408/v4", "wg/188.114.96.41:2408/s3",
		"wg/188.114.96.41:2408/v4r", "wg/162.159.192.3:2408/j4",
	},
}

func seedBonus(net, id string) float64 {
	for _, s := range netSeeds[net] {
		if s == id {
			return 0.35
		}
	}
	// remote priors (priors.json / SetRemotePriors) — патч 4
	for _, s := range remoteSeeds(net) {
		if s == id {
			return 0.35
		}
	}
	return 0
}

// prefix24 — ключ подсети /24 для адреса вида 162.159.192.3 (с портом или без): весь блок Cloudflare обычно
// маршрутизируется одинаково, поэтому если один адрес ведёт в запрещённый дата-центр, соседи ведут туда же.
func prefix24(host string) string {
	p := strings.Split(host, ".")
	if len(p) == 4 {
		return p[0] + "." + p[1] + "." + p[2] + ".*"
	}
	return host
}

// blockedFor — до какого времени запрещён адрес: по нему самому или по его подсети /24.
func blockedFor(blocked map[string]time.Time, host string) (time.Time, bool) {
	t1, ok1 := blocked[host]
	t2, ok2 := blocked[prefix24(host)]
	switch {
	case ok1 && ok2:
		if t2.After(t1) {
			return t2, true
		}
		return t1, true
	case ok1:
		return t1, true
	case ok2:
		return t2, true
	}
	return time.Time{}, false
}
