package hydra

import (
	"net"
	"strings"
	"sync/atomic"
	"time"
)

// Профили операторов: мягкие «привычки» сети, которые подсказывают Гидре, с чего начать.
// Реальные результаты в памяти всегда важнее: профиль только сдвигает порядок и таймауты.

type netProfile struct {
	UpFloor time.Duration // минимальное ожидание ответа туннеля (медленные сети, где живой путь отвечает за 0,5–2 с)
	Colos   []string      // предпочтительные дата-центры по порядку (небольшой бонус адресам, которые туда ведут)
}

// Ключ — "cell:MCCMNC".
var netProfiles = map[string]netProfile{
	"cell:25099": {UpFloor: 3500 * time.Millisecond, Colos: []string{"AMS", "HEL", "FRA"}}, // Билайн: долгий путь, QUIC к MASQUE молчит
	"cell:25020": {UpFloor: 3000 * time.Millisecond, Colos: []string{"HEL", "FRA", "AMS"}}, // Tele2
	"cell:25001": {Colos: []string{"HEL", "FRA", "AMS"}},                                   // МТС
	"cell:25002": {Colos: []string{"HEL", "FRA", "AMS"}},                                   // МегаФон
}

func profileFor(nk string) netProfile { return netProfiles[nk] }

// Начальные «опыты» для генов по операторам: [успехов, сбоев]. Сеть быстро переучивает их своими результатами.
var geneSeeds = map[string]map[string][2]int{
	"cell:25099": {"wg.sig=h3": {2, 0}, "wg.sig=stun": {1, 0}, "wg.sig=quic": {0, 2}},
	"cell:25020": {"wg.sig=stun": {2, 0}, "wg.sig=quic": {1, 0}},
	"cell:25001": {"wg.sig=stun": {2, 0}},
	"cell:25002": {"wg.sig=stun": {2, 0}},
}

const (
	slowNetRTT   = 400 * time.Millisecond  // если лучший успех в сети медленнее — сеть «медленная»
	slowNetFloor = 3500 * time.Millisecond // минимум ожидания ответа туннеля в медленной сети
)

// SlowNet — в этой сети даже лучшая рабочая стратегия поднимается дольше slowNetRTT.
func (m *Memory) SlowNet(nk string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	best, found := 0.0, false
	for _, st := range m.Nets[nk] {
		if st == nil || st.OK <= 0 || st.EWMAms <= 0 {
			continue
		}
		if !found || st.EWMAms < best {
			best, found = st.EWMAms, true
		}
	}
	return found && best >= float64(slowNetRTT/time.Millisecond)
}

// slowFloor — нижняя граница ожидания ответа туннеля для этой сети (0 — без ограничения).
func (e *Engine) slowFloor(nk string) time.Duration {
	fl := profileFor(nk).UpFloor
	if e.cfg.Mem != nil && e.cfg.Mem.SlowNet(nk) && fl < slowNetFloor {
		fl = slowNetFloor
	}
	return fl
}

// coloBonusLocked — небольшой бонус адресам, которые в этой сети попадают в предпочтительный дата-центр.
// Вызывать под m.mu.
func (m *Memory) coloBonusLocked(nk string, s Strategy) float64 {
	pf := netProfiles[nk]
	if len(pf.Colos) == 0 {
		return 0
	}
	r, ok := m.EPColo[nk+"|"+s.Params["endpoint"]]
	if !ok || time.Since(r.At) > 6*time.Hour {
		return 0
	}
	for i, c := range pf.Colos {
		if c == r.Colo {
			return 0.12 - 0.03*float64(i)
		}
	}
	return 0
}

// ForgetNet стирает всё, что Гидра знает об одной сети (стратегии, придуманное, дата-центры, гены, сервисы).
func (m *Memory) ForgetNet(nk string) {
	if nk == "" {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.Nets, nk)
	delete(m.Gen, nk)
	pre := nk + "|"
	for k := range m.EPColo {
		if strings.HasPrefix(k, pre) {
			delete(m.EPColo, k)
		}
	}
	for k := range m.Genes {
		if strings.HasPrefix(k, pre) {
			delete(m.Genes, k)
		}
	}
	for k := range m.Why {
		if strings.HasPrefix(k, pre) {
			delete(m.Why, k)
		}
	}
	for k := range m.Svc {
		if strings.HasPrefix(k, pre) {
			delete(m.Svc, k)
		}
	}
	m.saveSoonLocked()
}

// IPv6: если на этой сети до v6-адреса нет маршрута, на 5 минут не тратим попытки на v6-стратегии.
var v6DeadAt int64 // unix-наносекунды последнего «network is unreachable» для v6

func markV6Dead(ip net.IP) {
	if ip != nil && ip.To4() == nil {
		atomic.StoreInt64(&v6DeadAt, time.Now().UnixNano())
	}
}

func v6Dead() bool {
	t := atomic.LoadInt64(&v6DeadAt)
	return t != 0 && time.Since(time.Unix(0, t)) < 5*time.Minute
}

func isV6Strategy(s Strategy) bool {
	ip := net.ParseIP(hostOnly(s.Params["endpoint"]))
	return ip != nil && ip.To4() == nil
}
