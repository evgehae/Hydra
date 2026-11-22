package hydra

import (
	"encoding/json"
	"fmt"
	"math"
	"math/rand"
	"net"
	"sort"
	"strings"
	"sync"
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

// ---- общая база подсказок (priors.json из репозитория): подхватывается при старте туннеля ----

type remotePrior struct {
	Seeds   []string          `json:"seeds"`    // ID уже существующих стратегий, которым дать бонус
	FloorMs int               `json:"floor_ms"` // минимальное ожидание ответа туннеля
	Colos   []string          `json:"colos"`    // предпочтительные дата-центры по порядку
	Genes   map[string][2]int `json:"genes"`    // стартовые гены: "wg.sig=h3": [успехов, сбоев]
}

var (
	remoteMu sync.RWMutex
	remote   map[string]remotePrior
)

// SetRemotePriors подключает подсказки по сетям (JSON: {"cell:25099": {...}}). Они только сдвигают приоритеты:
// новых стратегий не создают, реальный опыт сети важнее.
func SetRemotePriors(data []byte) error {
	if len(data) > 256*1024 {
		return fmt.Errorf("priors.json слишком большой")
	}
	var m map[string]remotePrior
	if err := json.Unmarshal(data, &m); err != nil {
		return err
	}
	remoteMu.Lock()
	remote = m
	remoteMu.Unlock()
	return nil
}

func remoteFor(nk string) (remotePrior, bool) {
	remoteMu.RLock()
	defer remoteMu.RUnlock()
	r, ok := remote[nk]
	return r, ok
}

func remoteSeeds(nk string) []string {
	r, _ := remoteFor(nk)
	return r.Seeds
}

func profileFor(nk string) netProfile {
	p := netProfiles[nk]
	if r, ok := remoteFor(nk); ok {
		if r.FloorMs > 0 {
			p.UpFloor = time.Duration(r.FloorMs) * time.Millisecond
			if p.UpFloor > 5*time.Second {
				p.UpFloor = 5 * time.Second
			}
		}
		if len(r.Colos) > 0 {
			p.Colos = r.Colos
		}
	}
	return p
}

// geneSeed — стартовый «опыт» гена по оператору: сначала из общей базы, потом встроенный.
func geneSeed(nk, k string) ([2]int, bool) {
	if r, ok := remoteFor(nk); ok {
		if v, has := r.Genes[k]; has {
			return v, true
		}
	}
	v, has := geneSeeds[nk][k]
	return v, has
}

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
	pf := profileFor(nk)
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
	delete(m.Flow, nk)
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

// ---- жизнь потока в сети: основа плановой ротации ----

const (
	flowKeep = 12               // сколько последних замеров помним
	flowMin  = 5 * time.Second  // короткие смерти тоже считаем (иначе при обрывах «замеров нет»)
)

// RecordFlowLife запоминает, сколько прожил поток до гибели в этой сети.
func (m *Memory) RecordFlowLife(nk string, d time.Duration) {
	if m == nil || nk == "" || d < flowMin {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Flow == nil {
		m.Flow = map[string][]int{}
	}
	v := append(m.Flow[nk], int(d/time.Second))
	if len(v) > flowKeep {
		v = v[len(v)-flowKeep:]
	}
	m.Flow[nk] = v
	m.saveSoonLocked()
}

func medianSec(v []int) int {
	s := append([]int(nil), v...)
	sort.Ints(s)
	return s[len(s)/2]
}

// FlowTTL — медиана жизни потока в этой сети; 0, если замеров меньше трёх.
func (m *Memory) FlowTTL(nk string) time.Duration {
	if m == nil {
		return 0
	}
	m.mu.Lock()
	v := append([]int(nil), m.Flow[nk]...)
	m.mu.Unlock()
	if len(v) < 3 {
		return 0
	}
	return time.Duration(medianSec(v)) * time.Second
}

// FlowInfo — строка для отчёта: сколько живут потоки в этой сети.
func (m *Memory) FlowInfo(nk string) string {
	if m == nil {
		return ""
	}
	m.mu.Lock()
	v := append([]int(nil), m.Flow[nk]...)
	m.mu.Unlock()
	if len(v) == 0 {
		return "жизнь потока в этой сети: замеров нет\n"
	}
	last := ""
	for _, x := range v {
		last += fmt.Sprintf(" %d", x)
	}
	return fmt.Sprintf("жизнь потока в этой сети: замеров %d, медиана %d с, последние (с):%s\n", len(v), medianSec(v), last)
}

// ---- «бандит»: Thompson sampling поверх ранжирования ----

func gammaSample(k float64) float64 { // Marsaglia–Tsang, k >= 1
	d := k - 1.0/3
	c := 1 / math.Sqrt(9*d)
	for i := 0; i < 100; i++ {
		x := rand.NormFloat64()
		v := 1 + c*x
		if v <= 0 {
			continue
		}
		v = v * v * v
		u := rand.Float64()
		if u > 0 && math.Log(u) < 0.5*x*x+d-d*v+d*math.Log(v) {
			return d * v
		}
	}
	return d
}

func betaSample(a, b float64) float64 {
	x, y := gammaSample(a), gammaSample(b)
	if x+y == 0 {
		return a / (a + b)
	}
	return x / (x + y)
}

// SetBandit включает «исследование»: порядок стратегий слегка шумит по опыту сети, чтобы не застревать на одном пути.
func (m *Memory) SetBandit(on bool) {
	m.mu.Lock()
	m.bandit = on
	m.mu.Unlock()
}

// banditNoiseLocked — поправка к баллу стратегии: (выборка из Beta(успехи+1, сбои+1) − среднее) × 0.25. Вызывать под m.mu.
func (m *Memory) banditNoiseLocked(nk, id string) float64 {
	if !m.bandit {
		return 0
	}
	st := m.Nets[nk][id]
	if st == nil || st.OK+st.Fail < 2 {
		return 0
	}
	a, b := float64(st.OK+1), float64(st.Fail+1)
	return (betaSample(a, b) - a/(a+b)) * 0.25
}

// ---- время до подключения ----

func (e *Engine) noteConnectTime(d time.Duration) {
	e.mu.Lock()
	e.lastConnDur = d
	e.sumConnDur += d
	e.nConnDur++
	e.mu.Unlock()
}

// ---- вердикт по сети простыми словами ----

func idFamily(id string) string {
	switch {
	case strings.HasPrefix(id, "wg/"):
		return "wg"
	case strings.HasPrefix(id, "h2/"):
		return "h2"
	}
	return "h3"
}

// wgSigOf — тип пролога WG из ID стратегии.
func wgSigOf(id string) string {
	if i := strings.Index(id, "/g:"); i >= 0 {
		rest := id[i+3:]
		if j := strings.IndexAny(rest, "-"); j > 0 {
			rest = rest[:j]
		}
		switch rest {
		case "stun":
			return "STUN"
		case "quic", "qv":
			return "QUIC"
		case "dns":
			return "DNS"
		case "sip":
			return "SIP"
		case "h3":
			return "HTTP/3"
		}
		return "без пролога"
	}
	tag := id[strings.LastIndex(id, "/")+1:]
	switch {
	case strings.HasPrefix(tag, "s"):
		return "STUN"
	case strings.HasPrefix(tag, "q"), strings.HasPrefix(tag, "v"):
		return "QUIC"
	case strings.HasPrefix(tag, "d"):
		return "DNS"
	case strings.HasPrefix(tag, "p3"):
		return "SIP"
	case strings.HasPrefix(tag, "h"):
		return "HTTP/3"
	}
	return "без пролога"
}

func describeID(id string) string {
	switch idFamily(id) {
	case "wg":
		return "WireGuard с прологом " + wgSigOf(id)
	case "h2":
		return "MASQUE по HTTP/2"
	}
	return "MASQUE по QUIC"
}

// Verdict — короткий вывод о сети по накопленному опыту: что работает и что режется.
func (m *Memory) Verdict(nk string) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	okFam, failFam := map[string]int{}, map[string]int{}
	sigOK, sigFail := map[string]int{}, map[string]int{}
	bestID, bestOK, bestMs := "", 0, 0.0
	for id, st := range m.Nets[nk] {
		if st == nil {
			continue
		}
		f := idFamily(id)
		okFam[f] += st.OK
		failFam[f] += st.Fail
		if f == "wg" {
			s := wgSigOf(id)
			sigOK[s] += st.OK
			sigFail[s] += st.Fail
		}
		if st.OK > bestOK {
			bestID, bestOK, bestMs = id, st.OK, st.EWMAms
		}
	}
	why := func(fam, cls string) int { return m.Why[nk+"|"+fam+"|"+cls] }
	var parts []string
	if bestID != "" {
		parts = append(parts, "Работает: "+describeID(bestID))
	}
	var cuts []string
	if okFam["h3"] == 0 && failFam["h3"] >= 3 {
		cuts = append(cuts, "QUIC к MASQUE режется")
	}
	if okFam["h2"] == 0 && failFam["h2"] >= 3 {
		cuts = append(cuts, "HTTP/2 к MASQUE не проходит")
	}
	if okFam["wg"] == 0 && why("wg", "рукопожатие есть, данных нет") >= 3 {
		cuts = append(cuts, "WG: рукопожатие проходит, а данные режутся")
	}
	for _, s := range []string{"QUIC", "STUN", "HTTP/3"} {
		if sigOK[s] == 0 && sigFail[s] >= 3 && bestID != "" {
			cuts = append(cuts, "WG с прологом "+s+" режется")
		}
	}
	if len(cuts) > 0 {
		parts = append(parts, strings.Join(cuts, "; "))
	}
	if bestID != "" && bestMs >= float64(slowNetRTT/time.Millisecond) {
		parts = append(parts, "сеть медленная, туннелю даю больше времени")
	}
	if len(parts) == 0 {
		return "Мало данных об этой сети: Гидра подбирает способ."
	}
	return strings.Join(parts, ". ") + "."
}

// ---- не долбим то, что в этой сети не работает ----

// sbBackoff — пауза перед новым резервом, если резервы подряд умирают за секунды.
func sbBackoff(n int) time.Duration {
	switch {
	case n >= 10:
		return 30 * time.Minute
	case n >= 6:
		return 10 * time.Minute
	case n >= 3:
		return 2 * time.Minute
	}
	return 0
}

// famBackoff — у семейства стратегий нет ни одного успеха при ≥8 сбоях: проверяем его «из-за нехватки» не чаще раза в 30 минут.
func (e *Engine) famBackoff(nk, fam string) bool {
	var ok, fail int
	var last time.Time
	for _, s := range e.allStrategies(nk) {
		if poolFamily(s) != fam {
			continue
		}
		o, f, _, lf, found := e.cfg.Mem.Stat(nk, s.ID)
		if !found {
			continue
		}
		ok += o
		fail += f
		if lf.After(last) {
			last = lf
		}
	}
	return ok == 0 && fail >= 8 && time.Since(last) < 30*time.Minute
}
