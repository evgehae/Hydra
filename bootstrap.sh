#!/usr/bin/env bash
# WARP CLAUDE (Гидра) — обновление v22.3: «мозг» (память сервисов по сетям, живая проверка YouTube/WhatsApp
# прямо через туннель, замер скорости, мгновенная смена пути при мёртвом сервисе, самостоятельное придумывание
# вариантов) + «Доктор» и профиль сети в отчёте. Накопительный: включает наборы 13 и 14.
# Заменяет файлы один раз (при смене номера набора), дальше их можно править руками.
set -e

STAMP=.hydra_bootstrap
OLD="$(cat "$STAMP" 2>/dev/null || echo 0)"
NEW=15
putv() {
  f="$1"
  mkdir -p "$(dirname "$f")"
  if [ ! -e "$f" ] || [ "$OLD" -lt "$NEW" ]; then cat > "$f"; else cat > /dev/null; fi
}

GODIR="$(dirname "$(find . -name go.mod -not -path './app/*' | head -1)")"

putv "$GODIR/services.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"fmt"
	"net"
	"strings"
	"time"
)

var serviceTargets = []struct {
	name, ip string
	port     uint16
}{
	{"Telegram DC2", "149.154.167.51", 443},
	{"Telegram DC1/3", "149.154.175.50", 443},
	{"Telegram DC4", "149.154.167.91", 443},
	{"Telegram DC5", "91.108.56.130", 443},
	{"Google", "8.8.8.8", 443},
	{"Cloudflare", "1.1.1.1", 443},
	{"GitHub", "140.82.121.4", 443},
}

// Сервисы, у которых нет постоянных адресов: адрес берём по имени.
var serviceNames = []struct{ name, host string }{
	{"YouTube", "www.youtube.com"},
	{"Видео YouTube (googlevideo)", "redirector.googlevideo.com"},
	{"WhatsApp", "web.whatsapp.com"},
	{"Instagram", "www.instagram.com"},
	{"Discord", "discord.com"},
}

// resolveV4 возвращает первый IPv4-адрес имени. Запрос идёт обычным DNS вне туннеля.
func resolveV4(ctx context.Context, host string) (net.IP, error) {
	cctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	addrs, err := net.DefaultResolver.LookupIPAddr(cctx, host)
	if err != nil {
		return nil, err
	}
	for _, a := range addrs {
		if ip4 := a.IP.To4(); ip4 != nil {
			return ip4, nil
		}
	}
	return nil, fmt.Errorf("в ответе нет адреса IPv4")
}

// ServiceCheck проверяет через действующий туннель, проходит ли TCP до популярных сервисов
// (SYN-ACK от самого сервиса). Помогает отличить «туннель не пускает» от «сервис режет этот дата-центр».
// Важно: это проверка достижимости адреса, а не качества. Замедление по имени сайта (SNI) она не видит.
func (e *Engine) ServiceCheck(ctx context.Context) string {
	d, _ := e.active.Load().(*attemptDev)
	st := e.Status()
	if d == nil || st.State != "up" {
		return "туннель сейчас не подключён: проверять нечего\n"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Через туннель %s (дата-центр %s):\n", st.Strategy, st.Colo)
	okN, total := 0, 0
	for _, t := range serviceTargets {
		total++
		rtt, err := d.tcpProbeTo(ctx, net.ParseIP(t.ip).To4(), t.port, 3*time.Second)
		if err == nil {
			okN++
			fmt.Fprintf(&b, "  ✔ %s (%s:%d) %d мс\n", t.name, t.ip, t.port, rtt.Milliseconds())
		} else {
			fmt.Fprintf(&b, "  ✘ %s (%s:%d): %v\n", t.name, t.ip, t.port, err)
		}
	}
	b.WriteString("По именам (адрес получен обычным DNS вне туннеля, провайдер мог подменить ответ):\n")
	for _, t := range serviceNames {
		total++
		ip, err := resolveV4(ctx, t.host)
		if err != nil {
			fmt.Fprintf(&b, "  ✘ %s (%s): DNS не дал адрес: %v\n", t.name, t.host, err)
			continue
		}
		rtt, err := d.tcpProbeTo(ctx, ip, 443, 2500*time.Millisecond)
		if err == nil {
			okN++
			fmt.Fprintf(&b, "  ✔ %s (%s → %s) %d мс\n", t.name, t.host, ip.String(), rtt.Milliseconds())
		} else {
			fmt.Fprintf(&b, "  ✘ %s (%s → %s): %v\n", t.name, t.host, ip.String(), err)
		}
	}
	fmt.Fprintf(&b, "Доступно %d из %d.\n", okN, total)
	return b.String()
}
HYDRA_EOF

putv "$GODIR/brain.go" <<'HYDRA_EOF'
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
HYDRA_EOF

putv "$GODIR/gate.go" <<'HYDRA_EOF'
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

// Сервисы «мягкой» проверки: у них нет постоянных адресов, адрес берётся по имени. Результат идёт в память
// (влияет на порядок стратегий и запускает придумывание новых), но дата-центр из-за них не банится:
// ответ DNS мог быть подменён провайдером.
var svcSoft = []struct{ name, host string }{
	{"YouTube", "redirector.googlevideo.com"},
	{"WhatsApp", "web.whatsapp.com"},
}

// serviceGate проверяет через только что поднятый туннель, доходят ли Telegram, YouTube и WhatsApp.
// Если интернет работает, а ни один сервер Telegram не отвечает, — дата-центр помечается плохим, и Гидра
// ищет другой путь. Больше трёх плохих дата-центров в одной сети не набираем: значит, дело не в них.
// Результаты по всем сервисам запоминаются: стратегии, через которые доходит всё, получают приоритет.
func (e *Engine) serviceGate(ctx context.Context, nk string, a *attempt, out chan<- string) {
	hard := e.badColoCount(nk) < 3
	select {
	case <-ctx.Done():
		return
	case <-a.ctx.Done():
		return
	case <-time.After(2500 * time.Millisecond):
	}
	base := false
	for _, ip := range []string{"8.8.8.8", "1.1.1.1"} {
		if _, err := a.dev.tcpProbeTo(a.ctx, net.ParseIP(ip).To4(), 443, 3*time.Second); err == nil {
			base = true
			break
		}
		if a.ctx.Err() != nil {
			return
		}
	}
	if !base {
		return // сеть шатается: вывод был бы ненадёжным
	}
	tgOK := false
	for _, t := range tgTargets {
		if _, err := a.dev.tcpProbeTo(a.ctx, net.ParseIP(t.ip).To4(), t.port, 3*time.Second); err == nil {
			tgOK = true
			break
		}
		if a.ctx.Err() != nil {
			return
		}
	}
	e.cfg.Mem.RecordService(nk, a.s.ID, "Telegram", tgOK)
	if tgOK {
		Logf("✔ Telegram через %s (дата-центр %s) достижим", a.s.ID, a.colo)
	} else {
		Logf("✘ Telegram через %s (дата-центр %s) не достижим", a.s.ID, a.colo)
		if hard {
			select {
			case out <- "Telegram не доходит через дата-центр " + a.colo + " (остальной интернет работает) — ищу другой путь":
			default:
			}
			return
		}
	}
	failed := 0
	for _, t := range svcSoft {
		if a.ctx.Err() != nil || ctx.Err() != nil {
			return
		}
		ip, err := resolveV4(a.ctx, t.host)
		if err != nil {
			Logf("   ? %s: адрес не получен (%v), в память не записываю", t.name, err)
			continue
		}
		_, err = a.dev.tcpProbeTo(a.ctx, ip, 443, 2500*time.Millisecond)
		if a.ctx.Err() != nil {
			return
		}
		e.cfg.Mem.RecordService(nk, a.s.ID, t.name, err == nil)
		if err == nil {
			Logf("✔ %s через %s достижим", t.name, a.s.ID)
		} else {
			failed++
			Logf("✘ %s через %s (дата-центр %s) не достижим: %v", t.name, a.s.ID, a.colo, err)
		}
	}
	if failed > 0 {
		e.svcGrow(nk)
	}
}
HYDRA_EOF

putv "$GODIR/memory.go" <<'HYDRA_EOF'
package hydra

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

type stat struct {
	OK     int       `json:"ok"`
	Fail   int       `json:"fail"`
	EWMAms float64   `json:"ewma_ms"`
	LastOK time.Time `json:"last_ok"`
	LastFail time.Time `json:"last_fail"`
}

// Memory — «память Гидры»: что работало в какой сети.
// Ключ сети (net) выдаёт Android-часть: например "wifi:<hash>" или "cell:25001".
type Memory struct {
	mu      sync.Mutex
	path    string
	pending bool // отложенное сохранение уже запланировано
	Nets map[string]map[string]*stat `json:"nets"`
	// Gen — стратегии, которые Гидра придумала сама, по сетям.
	Gen map[string][]Strategy `json:"gen"`
	EPColo map[string]coloRec `json:"epcolo"` // в какой дата-центр попадает адрес в этой сети
	Genes map[string]*stat `json:"genes"` // как срабатывали значения параметров стратегий по сетям
	Why   map[string]int   `json:"why"`   // причины сбоев по сетям и семействам
	Svc map[string]*stat `json:"svc"` // дошли ли сервисы (Telegram, YouTube, WhatsApp) через стратегию: сеть|стратегия|сервис
	Ver int                   `json:"ver"` // версия формата: <2 — в памяти могли быть сбои из-за белых списков
}

func LoadMemory(path string) (*Memory, error) {
	m := &Memory{path: path, Nets: map[string]map[string]*stat{}}
	if path == "" {
		return m, nil
	}
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return m, nil
	}
	if err != nil {
		return m, err
	}
	if err := json.Unmarshal(b, m); err != nil {
		m.Nets = map[string]map[string]*stat{}
		return m, err
	}
	if m.Nets == nil {
		m.Nets = map[string]map[string]*stat{}
	}
	if m.Ver < 2 {
		// прежние версии записывали провалы стратегий и тогда, когда виноват был режим белых списков
		for k := range m.Nets {
			m.rehabLocked(k)
		}
		m.Ver = 2
	}
	return m, nil
}

func (m *Memory) rehabLocked(net string) {
	for _, st := range m.Nets[net] {
		if st.OK > 0 {
			if st.Fail > st.OK {
				st.Fail = st.OK
			}
		} else if st.Fail > 1 {
			st.Fail = 1
		}
		st.LastFail = time.Time{}
	}
}

// Rehabilitate прощает сбои, накопленные в период без интернета или режима белых списков.
func (m *Memory) Rehabilitate(net string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.rehabLocked(net)
	m.saveSoonLocked()
}

// EndpointDead: все стратегии с этим адресом (и протоколом) в этой сети подряд не работали, ни разу не сработав.
// Такие адреса на время (12 часов после последнего сбоя) исключаются из фоновых проверок и мутаций.
func (m *Memory) EndpointDead(net, id string) bool {
	parts := strings.SplitN(id, "/", 3)
	if len(parts) < 3 {
		return false
	}
	key := parts[0] + "/" + parts[1] + "/"
	m.mu.Lock()
	defer m.mu.Unlock()
	ok, fail := 0, 0
	var last time.Time
	for sid, st := range m.Nets[net] {
		if !strings.HasPrefix(sid, key) {
			continue
		}
		ok += st.OK
		fail += st.Fail
		if st.LastFail.After(last) {
			last = st.LastFail
		}
	}
	return ok == 0 && fail >= 3 && time.Since(last) < quarantineFor
}

func (m *Memory) Save() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.path == "" {
		return nil
	}
	b, err := json.Marshal(m)
	if err != nil {
		return err
	}
	tmp := m.path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, m.path)
}

func (m *Memory) Record(net, id string, ok bool, d time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	n := m.Nets[net]
	if n == nil {
		n = map[string]*stat{}
		m.Nets[net] = n
	}
	s := n[id]
	if s == nil {
		s = &stat{}
		n[id] = s
	}
	if ok {
		s.OK++
		s.LastOK = time.Now()
		ms := float64(d.Milliseconds())
		if s.EWMAms == 0 {
			s.EWMAms = ms
		} else {
			s.EWMAms = 0.7*s.EWMAms + 0.3*ms
		}
	} else {
		s.Fail++
		s.LastFail = time.Now()
	}
	if s.OK+s.Fail > 20 { // забываем старое: DPI меняется
		s.OK /= 2
		s.Fail /= 2
	}
	m.saveSoonLocked()
}

// saveSoonLocked планирует сохранение через 2 с (вызывать под m.mu): если систему убьёт процесс,
// накопленный опыт не пропадёт, а на диск пишем не на каждый чих.
func (m *Memory) saveSoonLocked() {
	if m.path == "" || m.pending {
		return
	}
	m.pending = true
	time.AfterFunc(2*time.Second, func() {
		m.mu.Lock()
		m.pending = false
		m.mu.Unlock()
		_ = m.Save()
	})
}

const maxGenerated = 24

// Generated — придуманные Гидрой стратегии для этой сети.
func (m *Memory) Generated(net string) []Strategy {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]Strategy(nil), m.Gen[net]...)
}

// AddGenerated запоминает новые стратегии; при переполнении выбрасывает самые старые, не имевшие побед.
func (m *Memory) AddGenerated(net string, list []Strategy) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Gen == nil {
		m.Gen = map[string][]Strategy{}
	}
	have := map[string]bool{}
	for _, s := range m.Gen[net] {
		have[s.ID] = true
	}
	for _, s := range list {
		if !have[s.ID] {
			m.Gen[net] = append(m.Gen[net], s)
			have[s.ID] = true
		}
	}
	over := len(m.Gen[net]) - maxGenerated
	if over > 0 {
		var kept []Strategy
		for _, s := range m.Gen[net] {
			st := m.Nets[net][s.ID]
			if over > 0 && (st == nil || st.OK == 0) {
				over--
				delete(m.Nets[net], s.ID)
				continue
			}
			kept = append(kept, s)
		}
		m.Gen[net] = kept
	}
	m.saveSoonLocked()
}

// Prune удаляет придуманные стратегии, которые в этой сети не работают. Возвращает, сколько удалено.
func (m *Memory) Prune(net string) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	removed := 0
	var kept []Strategy
	for _, s := range m.Gen[net] {
		st := m.Nets[net][s.ID]
		dead := st != nil && ((st.OK == 0 && st.Fail >= 3) ||
			(st.Fail >= 8 && float64(st.OK)/float64(st.OK+st.Fail) < 0.15))
		if dead {
			delete(m.Nets[net], s.ID)
			removed++
			continue
		}
		kept = append(kept, s)
	}
	if removed > 0 {
		m.Gen[net] = kept
		m.saveSoonLocked()
	}
	return removed
}

// Doomed: стратегия в этой сети уже не раз подводила и ни разу не работала.
func (m *Memory) Doomed(net, id string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	st := m.Nets[net][id]
	// карантин на 12 часов после последнего сбоя: потом стратегии дают второй шанс (DPI меняется)
	return st != nil && st.OK == 0 && st.Fail >= 3 && time.Since(st.LastFail) < 12*time.Hour
}

// Stat — опыт стратегии в этой сети.
func (m *Memory) Stat(net, id string) (ok, fail int, lastOK, lastFail time.Time, found bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	st := m.Nets[net][id]
	if st == nil {
		return 0, 0, time.Time{}, time.Time{}, false
	}
	return st.OK, st.Fail, st.LastOK, st.LastFail, true
}

// priorLocked — оценка стратегии для сети без истории: опыт в других сетях того же класса
// (все "wifi:*" или все "cell:*") с пониженным доверием. Вызывать под m.mu.
func (m *Memory) priorLocked(net, id string) float64 {
	class := net
	if i := strings.Index(net, ":"); i > 0 {
		class = net[:i]
	}
	ok, fail := 0, 0
	for k, ns := range m.Nets {
		if k == net || !strings.HasPrefix(k, class+":") {
			continue
		}
		if st := ns[id]; st != nil {
			ok += st.OK
			fail += st.Fail
		}
	}
	if ok+fail == 0 {
		return 0.5
	}
	rate := float64(ok+1) / float64(ok+fail+2)
	return 0.5 + (rate-0.5)*0.6
}

// Worked: стратегия уже хотя бы раз подключалась в этой сети.
func (m *Memory) Worked(net, id string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	st := m.Nets[net][id]
	return st != nil && st.OK > 0
}

// Rank сортирует стратегии: лучшие для этой сети — первыми.
// Неизвестные получают нейтральный балл и пробуются после проверенных.
func (m *Memory) Rank(net string, all []Strategy) []Strategy {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := append([]Strategy(nil), all...)
	score := func(s Strategy) float64 {
		st := m.Nets[net][s.ID]
		if st == nil {
			return m.priorLocked(net, s.ID) + m.svcBonusLocked(net, s.ID)
		}
		rate := float64(st.OK+1) / float64(st.OK+st.Fail+2)
		pen := math.Min(st.EWMAms/5000, 0.3)
		bonus := 0.0
		if time.Since(st.LastOK) < 24*time.Hour {
			bonus = 0.1
		}
		return rate - pen + bonus + m.svcBonusLocked(net, s.ID)
	}
	sort.SliceStable(out, func(i, j int) bool { return score(out[i]) > score(out[j]) })
	return out
}

// Summary — читаемая сводка памяти для диагностики: лучшие стратегии в этой сети и счётчики.
func (m *Memory) Summary(net string, n int) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	ns := m.Nets[net]
	type row struct {
		id string
		st *stat
	}
	rows := make([]row, 0, len(ns))
	for id, st := range ns {
		rows = append(rows, row{id, st})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].st.OK != rows[j].st.OK {
			return rows[i].st.OK > rows[j].st.OK
		}
		return rows[i].st.Fail < rows[j].st.Fail
	})
	out := fmt.Sprintf("память: сетей %d; в этой сети (%s) стратегий с опытом %d, придуманных %d\n", len(m.Nets), net, len(ns), len(m.Gen[net]))
	for i, r := range rows {
		if i >= n {
			break
		}
		last := "—"
		if !r.st.LastOK.IsZero() {
			last = r.st.LastOK.Format("01-02 15:04")
		}
		out += fmt.Sprintf("  %s: успехов %d, сбоев %d, ~%.0f мс, последний успех %s\n", r.id, r.st.OK, r.st.Fail, r.st.EWMAms, last)
	}
	return out
}

type coloRec struct {
	Colo string    `json:"c"`
	At   time.Time `json:"t"`
}

// NoteColo запоминает, в какой дата-центр попал адрес.
func (m *Memory) NoteColo(nk, ep, colo string) {
	if ep == "" || colo == "" {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.EPColo == nil {
		m.EPColo = map[string]coloRec{}
	}
	m.EPColo[nk+"|"+ep] = coloRec{colo, time.Now()}
	m.saveSoonLocked()
}

// KnownColo — дата-центр, в который адрес попадал в этой сети в последние 6 часов ("" — неизвестно).
func (m *Memory) KnownColo(nk, ep string) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.EPColo[nk+"|"+ep]
	if !ok || time.Since(r.At) > 6*time.Hour {
		return ""
	}
	return r.Colo
}
HYDRA_EOF

putv "$GODIR/engine.go" <<'HYDRA_EOF'
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
	active                     atomic.Value // *attemptDev: карта, через которую сейчас идёт трафик
	testFail                   chan struct{}
	svcBad chan string // «живая» проверка сервиса не прошла: сменить путь
	tried                      map[string]time.Time // когда стратегию последний раз пробовали
	inOutage, outageLogged     bool
	wlLast                     time.Time
	badColo                    map[string]time.Time // дата-центры, через которые не доходит Telegram

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
		svcBad:   make(chan string, 1),
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
HYDRA_EOF

putv "$GODIR/race.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"errors"
	"fmt"
	"strings"
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
	tester bool // короткая фоновая проверка, а не резерв
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
	go func() {
		defer func() {
			if r := recover(); r != nil { // сбой клиента туннеля не должен ронять приложение
				Logf("💥 паника в клиенте туннеля %s: %v", s.ID, r)
				a.errc <- fmt.Errorf("паника: %v", r)
			}
		}()
		a.errc <- e.cfg.Runner(actx, a.dev, s)
	}()
	return a
}

// verify ждёт, пока попытка поднимется, и проверяет её: ответ туннеля, дата-центр, реальный TCP.
func (e *Engine) verify(nk string, a *attempt) (bool, outcome) {
	s := a.s
	e.noteTry(s.ID)
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
			if errors.Is(err, ErrRunnerBusy) {
				return false, outcome{reason: "остановка"} // не провал стратегии: клиент просто был занят
			}
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
		if x := a.dev.extra(); x != "" {
			msg += " [" + x + "]"
		}
		Logf("   ✘ %s: %s", s.ID, msg)
		return false, e.fail(nk, s, msg)
	}
	Logf("   %s: туннель ответил за %d мс, дата-центр Cloudflare: %s", s.ID, rtt.Milliseconds(), colo)
	e.cfg.Mem.NoteColo(nk, s.Params["endpoint"], colo)
	if !e.coloAllowed(nk, colo) {
		Logf("   ✘ %s: дата-центр %s запрещён (настройками или потому, что через него не доходит Telegram)", s.ID, colo)
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
	e.cfg.Mem.RecordGenes(nk, s, true)
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
			if e.recentlyTried(s.ID, standbyRetry) || (e.cfg.CanRun != nil && !e.cfg.CanRun(s)) || e.knownBlocked(nk, s) {
				continue
			}
			ep := s.Params["endpoint"]
			if until, ok := blocked[hostOnly(ep)]; ep != "" && ok && time.Now().Before(until) {
				continue
			}
			if e.cfg.Mem.Doomed(nk, s.ID) || e.cfg.Mem.EndpointDead(nk, s.ID) {
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
	taken := make([]bool, len(cands))
	res := make(chan verdict, 64)
	live := 0
	var all []*attempt
	defer func() {
		for _, a := range all {
			a.cancel()
		}
	}()

	// remaining — остались ли непробованные кандидаты (даже те, которые пока нельзя запускать)
	remaining := func() bool {
		for _, t := range taken {
			if !t {
				return true
			}
		}
		return false
	}
	nextCand := func() (Strategy, bool) {
		for i, s := range cands {
			if taken[i] {
				continue
			}
			if s.ID == skip {
				taken[i] = true
				continue
			}
			ep := s.Params["endpoint"]
			if until, ok := blocked[hostOnly(ep)]; ep != "" && ok && time.Now().Before(until) {
				taken[i] = true
				skipped++
				continue
			}
			if e.knownBlocked(nk, s) {
				taken[i] = true // этот адрес в этой сети попадает в запрещённый дата-центр: не тратим время
				skipped++
				sawBlocked = true
				continue
			}
			if e.cfg.CanRun != nil && !e.cfg.CanRun(s) {
				continue // например, единственный аккаунт WireGuard занят: попробуем позже
			}
			taken[i] = true
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
				} else if !remaining() {
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
				} else if !remaining() {
					return
				}
			}
		}
	}

	// ---- победитель ----
	p.dev.promote()
	e.active.Store(p.dev)
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
	bad, sbBad, ticks, tcpBad := 0, 0, 0, 0
	nextSb := time.Now().Add(3 * time.Second)
	lastLearn := time.Time{}
	lastBeat := time.Now()
	gateCh := make(chan string, 1)
	if e.cfg.ServiceGate {
		go e.serviceGate(ctx, nk, p, gateCh)
	}
	testing := 0
	testedAt := map[string]time.Time{}
	lastTest := time.Now().Add(-time.Hour)
	lastGen := time.Time{}
	lastPrune := time.Now()
	launchTester := func(s Strategy) {
		a := e.startAttempt(ctx, s, false)
		a.tester = true
		all = append(all, a)
		testing++
		go func() {
			ok, o := e.verify(nk, a)
			res <- verdict{a, ok, o}
		}()
	}

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
		e.active.Store(p.dev)
		colo = p.colo
		e.setStatus(Status{State: "up", Strategy: p.s.ID, Colo: colo, RTT: p.rtt, Message: msg})
		e.emit("connected", p.s.ID, colo)
		if e.cfg.ServiceGate {
			go e.serviceGate(ctx, nk, p, gateCh)
		}
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
		case why := <-gateCh:
			Logf("🚫 %s", why)
			e.noteBadColo(nk, p.colo)
			if sb != nil && sb.colo != p.colo && failover(why) {
				continue
			}
			lose(why)
			return
		case why := <-e.svcBad:
			Logf("🚫 %s", why)
			e.noteBadColo(nk, p.colo)
			if sb != nil && sb.colo != p.colo && failover(why) {
				continue
			}
			lose(why)
			return
		case <-e.testFail:
			Logf("🧪 тест: имитирую отказ основного туннеля %s", p.s.ID)
			if sb == nil {
				Logf("🧪 резерва сейчас нет — переключаться некуда (резерв поднимается в течение минуты после подключения)")
				continue
			}
			t0 := time.Now()
			if failover("тест переключения") {
				Logf("🧪 переключение выполнено за %d мс", time.Since(t0).Milliseconds())
			}
		case v := <-res:
			if v.a.tester {
				testing--
				v.a.cancel()
				if v.ok {
					Logf("🔬 %s: работает (дата-центр %s, %d мс)", v.a.s.ID, v.a.colo, v.a.rtt.Milliseconds())
				} else if v.o.reason != "остановка" {
					Logf("🔬 %s: не работает — %s", v.a.s.ID, v.o.reason)
					if v.o.coloBlocked != "" {
						noteFail(v)
					}
				}
				Logf("🔬 %s", strings.TrimSpace(e.PoolSummary(nk)))
				continue
			}
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
			e.noteProbe(err == nil)
			if err != nil && p.ctx.Err() == nil {
				// единичная потеря UDP — ещё не отказ: сразу повторяем пробу
				r, c, err = p.dev.probe(p.ctx, 1500*time.Millisecond)
				e.noteProbe(err == nil)
			}
			if err == nil && e.cfg.TCPCheck && ticks%5 == 0 {
				// одна неудачная TCP-проба при живой UDP-пробе — не отказ; считаем только две подряд
				if _, terr := p.dev.tcpProbe(p.ctx, e.cfg.TCPTimeout); terr != nil {
					tcpBad++
					if tcpBad >= 2 {
						err = terr
					}
				} else {
					tcpBad = 0
				}
			}
			limit := e.cfg.BadProbes
			if sb != nil && limit > 2 {
				limit = 2 // резерв готов — переходим на него быстрее
			}
			if err != nil {
				bad++
				Logf("   проба без ответа (%d из %d, в туннель ушло %d пакетов, пришло %d): %v", bad, limit,
					atomic.LoadInt32(&p.dev.sent), atomic.LoadInt32(&p.dev.recv), err)
				if bad >= limit {
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
					if !e.coloAllowed(nk, c) {
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
				_, _, perr := sb.dev.probe(sb.ctx, 3*time.Second)
				if perr != nil && sb.ctx.Err() == nil {
					_, _, perr = sb.dev.probe(sb.ctx, 3*time.Second) // на мобильной сети пробы к резерву бывают медленными
				}
				if perr != nil {
					sbBad++
					Logf("   резерв %s не ответил на пробу (%d из %d)", sb.s.ID, sbBad, e.cfg.BadProbes)
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
			if time.Since(lastBeat) > 10*time.Minute {
				lastBeat = time.Now()
				sbName := "нет"
				if sb != nil {
					sbName = sb.s.ID
				}
				total, lost := e.probeStats()
				Logf("💓 в порядке: основной %s, дата-центр %s, пинг %d мс, резерв: %s, проб потеряно %d из %d",
					p.s.ID, colo, r.Milliseconds(), sbName, lost, total)
				Logf("💓 %s", strings.TrimSpace(e.PoolSummary(nk)))
			}
			if time.Since(lastPrune) > 10*time.Minute {
				lastPrune = time.Now()
				if n := e.cfg.Mem.Prune(nk); n > 0 {
					Logf("🧹 убрал %d придуманных способов, которые не работают", n)
				}
			}
			// обслуживание пула: фоновая проверка запасных стратегий и пополнение нехватки
			if testing == 0 && bad == 0 && time.Since(p.start) > 20*time.Second {
				every := testSlow
				if e.hasDeficit(nk) {
					every = testFast
				}
				if time.Since(lastTest) >= every {
					excl := map[string]bool{p.s.ID: true}
					if sb != nil {
						excl[sb.s.ID] = true
					}
					if s, why, ok := e.pickTest(nk, excl, blocked, testedAt); ok {
						lastTest = time.Now()
						testedAt[s.ID] = lastTest
						Logf("🔬 проверяю запасную стратегию (%s): %s", why, s.ID)
						launchTester(s)
					} else if time.Since(lastGen) > 5*time.Minute {
						lastGen = time.Now()
						h, u, _ := e.poolCounts(nk)
						present := e.familyPresent(nk)
						for _, f := range poolFams {
							if present[f] && h[f] < poolTargets[f] && u[f] == 0 {
								e.grow(nk)
								break
							}
						}
					}
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
HYDRA_EOF

putv "$GODIR/mobile/vpn_usque.go" <<'HYDRA_EOF'
//go:build usque

package mobile

import (
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"

	hydra "hydra/core"
)

var (
	vpnMu     sync.Mutex
	vpnEngine *hydra.Engine
	vpnMem    *hydra.Memory
	vpnWG     *hydra.WGPool
	journalOnce sync.Once
	vpnCancel context.CancelFunc
)

// StartTunnel запускает Гидру на TUN-интерфейсе, который создал Android (tunFd).
// Пустая строка — успех, иначе текст ошибки.
func StartTunnel(dir string, tunFd int) string {
	vpnMu.Lock()
	defer vpnMu.Unlock()
	journalOnce.Do(func() { hydra.SetJournalFile(filepath.Join(dir, "journal.log")) })
	if vpnEngine != nil {
		return "уже запущено"
	}
	macc, _ := hydra.LoadAccount(accountPath(dir))
	wacc, _ := hydra.LoadAccount(wgPath(dir))
	wacc2, _ := hydra.LoadAccount(wg2Path(dir))
	if macc == nil && wacc == nil {
		return "нет аккаунта WARP"
	}
	runners := map[string]hydra.Runner{}
	var strategies []hydra.Strategy
	if macc != nil {
		r, err := hydra.NewMasqueRunner(macc)
		if err != nil {
			return err.Error()
		}
		runners["masque"] = r
	}
	var wgp *hydra.WGPool
	if wacc != nil {
		accs := []*hydra.Account{wacc}
		if wacc2 != nil && wacc2.Kind == "wg" {
			accs = append(accs, wacc2) // второй ключ: резерв WireGuard не мешает основной сессии
		}
		wgp = hydra.NewWGPool(accs...)
		r, err := hydra.NewWGPoolRunner(wgp)
		if err != nil {
			return err.Error()
		}
		runners["wg"] = r
	}
	vpnWG = wgp
	var mS, wS []hydra.Strategy
	if macc != nil {
		mS = hydra.MasqueStrategies(macc)
		sni, cep := currentCustom()
		if cep != "" {
			mS = append(hydra.CustomEndpointStrategies(cep), mS...) // свой адрес — первым
		}
		if sni != "" {
			// свой SNI добавляется как дополнительные стратегии (первыми), а не подменяет все: так
			// остальное многообразие параметров, которым Гидра учится, не пропадает
			n := 8
			if n > len(mS) {
				n = len(mS)
			}
			var extra []hydra.Strategy
			for _, s0 := range mS[:n] {
				q := map[string]string{}
				for k, v := range s0.Params {
					q[k] = v
				}
				q["sni"] = sni
				extra = append(extra, hydra.Strategy{ID: s0.ID + "@" + sni, Transport: s0.Transport, Params: q})
			}
			mS = append(extra, mS...)
		}
	}
	if wacc != nil {
		wS = hydra.WGStrategies(wacc)
	}
	onlyMasque := currentProtocol() == "masque" && len(mS) > 0
	onlyWG := currentProtocol() == "wg" && len(wS) > 0
	allow := func(s hydra.Strategy) bool {
		return !(onlyMasque && s.Transport != "masque") && !(onlyWG && s.Transport != "wg")
	}
	switch currentProtocol() {
	case "masque":
		if len(mS) > 0 {
			wS = nil
		}
	case "wg":
		if len(wS) > 0 {
			mS = nil
		}
	}
	strategies = hydra.Interleave(mS, wS, 3)
	runner := func(ctx context.Context, d hydra.PacketDevice, s hydra.Strategy) error {
		r := runners[s.Transport]
		if r == nil {
			return fmt.Errorf("нет транспорта %q", s.Transport)
		}
		return r(ctx, d, s)
	}
	acc := primaryAccount(dir)
	ip := net.ParseIP(strings.Split(acc.AddrV4, "/")[0])
	if ip == nil {
		return "в аккаунте нет IPv4-адреса"
	}
	mem, _ := hydra.LoadMemory(filepath.Join(dir, "memory.json"))
	vpnMem = mem

	cfg := hydra.DefaultEngineConfig()
	cfg.LocalIP = ip
	cfg.Strategies = strategies
	cfg.Runner = runner
	cfg.Policy = currentPolicy()
	cfg.Mem = mem
	cfg.NetKey = currentNetKey
	cfg.NetChanged = netEvents
	cfg.SoftFallback = currentFallback()
	cfg.DropV6 = stripMask(acc.AddrV6) == "" || !currentIPv6()
	cfg.ServiceGate = currentGate()
	cfg.NetAlive = realNetAlive
	cfg.Allow = allow
	cfg.NetState = realNetState
	cfg.WLScan = realWLScan
	cfg.CanRun = func(s hydra.Strategy) bool { return wgp.CanRun(s) } // wgp может быть nil: метод это учитывает
	cfg.Parallel = currentParallel()

	e := hydra.NewEngine(os.NewFile(uintptr(tunFd), "tun"), cfg)
	ctx, cancel := context.WithCancel(context.Background())
	vpnEngine, vpnCancel = e, cancel
	go func() {
		defer func() {
			if r := recover(); r != nil { // паника движка не должна ронять приложение: служба поднимет его заново
				hydra.Logf("💥 паника движка: %v", r)
			}
			mem.Save()
			vpnMu.Lock()
			if vpnEngine == e {
				vpnEngine, vpnCancel = nil, nil
			}
			vpnMu.Unlock()
		}()
		e.Run(ctx)
	}()
	return ""
}

// StopTunnel останавливает Гидру и закрывает TUN.
func StopTunnel() {
	vpnMu.Lock()
	c, e := vpnCancel, vpnEngine
	vpnMu.Unlock()
	if c != nil {
		c()
	}
	if e != nil {
		e.Close()
	}
}

// EngineStatus: "состояние|стратегия|дата-центр|задержка_мс|сообщение".
// Состояния: off, connecting, up, reconnecting, failed.
func EngineStatus() string {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e == nil {
		return "off||||"
	}
	st := e.Status()
	rx, tx := e.Traffic()
	return fmt.Sprintf("%s|%s|%s|%d|%s|%d|%d", st.State, st.Strategy, st.Colo,
		st.RTT.Milliseconds(), strings.ReplaceAll(st.Message, "|", "/"), rx, tx)
}

// Diagnostics — сводка движка и памяти стратегий для отчёта.
func Diagnostics() string {
	out := ""
	polMu.Lock()
	nk := netKey
	polMu.Unlock()
	if e := vpnEngine; e != nil {
		out += e.Stats()
		out += e.PoolSummary(nk)
		out += vpnWG.Info()
		out += vpnMem.Reasons(nk)
	} else {
		out += "движок не запущен\n"
	}
	out += netStateInfo()
	if m := vpnMem; m != nil {
		out += m.Summary(nk, 15)
		out += "🧠 что Гидра знает об этой сети (" + nk + "): какие сервисы доходят через какие стратегии\n" + m.ServiceMatrix(nk)
		if e := vpnEngine; e != nil {
			if bl := e.BadColoList(nk); len(bl) > 0 {
				out += "  плохие дата-центры (Telegram не доходит): " + strings.Join(bl, ", ") + "\n"
			}
		}
	}
	return out
}

// TestFailover имитирует отказ основного туннеля, чтобы проверить переход на горячий резерв.
func TestFailover() {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e != nil {
		e.TestFailover()
	}
}

// ServiceCheck проверяет через действующий туннель доступность Telegram и других сервисов.
func ServiceCheck() string {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e == nil {
		return "Гидра не запущена\n"
	}
	res := e.ServiceCheck(context.Background())
	hydra.Logf("🔎 проверка сервисов через туннель:\n%s", res)
	return res
}

// GetJournalFull возвращает журнал из файла (с прошлыми запусками); если файла нет — из памяти.
func GetJournalFull(n int) string {
	if s := hydra.JournalFileTail(n); s != "" {
		return s
	}
	return hydra.JournalText(n)
}

// ReportService: приложение сообщает итог «живой» проверки сервиса через туннель (state: "ok" или "dead").
func ReportService(name, state, detail string) {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e != nil {
		e.ReportService(name, state == "ok", detail)
	}
}

// ReportSpeed: приложение сообщает измеренную через туннель скорость, кбит/с.
func ReportSpeed(kbps int64) {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e != nil {
		e.ReportSpeed(kbps)
	}
}
HYDRA_EOF

putv "app/src/main/java/app/hydra/Diagnostics.kt" <<'HYDRA_EOF'
package app.hydra

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL

data class DiagResult(
    val dnsOk: Boolean,
    val dnsMs: Long,
    val httpsOk: Boolean,
    val httpsMs: Long,
    val ip: String,
    val loc: String,
    val colo: String,
    val warp: String
)

/** DNS + HTTPS до Cloudflare; trace показывает дата-центр и идёт ли трафик через WARP. */
suspend fun runDiagnostics(): DiagResult = withContext(Dispatchers.IO) {
    var dnsOk = false
    var t = System.currentTimeMillis()
    try {
        InetAddress.getByName("cloudflare.com")
        dnsOk = true
    } catch (e: Exception) {
    }
    val dnsMs = System.currentTimeMillis() - t

    var httpsOk = false
    var kv: Map<String, String> = emptyMap()
    t = System.currentTimeMillis()
    try {
        val c = URL("https://cloudflare.com/cdn-cgi/trace").openConnection() as HttpURLConnection
        c.connectTimeout = 5000
        c.readTimeout = 5000
        val body = c.inputStream.bufferedReader().use { it.readText() }
        c.disconnect()
        kv = body.lines()
            .mapNotNull { l -> l.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
            .toMap()
        httpsOk = true
    } catch (e: Exception) {
    }
    val httpsMs = System.currentTimeMillis() - t

    DiagResult(
        dnsOk, dnsMs, httpsOk, httpsMs,
        kv["ip"].orEmpty(), kv["loc"].orEmpty(),
        (kv["colo"] ?: "").uppercase(), kv["warp"].orEmpty()
    )
}

// ---------- Полная диагностика и отчёт ----------

data class DiagCheck(val name: String, val ok: Boolean, val detail: String)

private fun tcpCheck(host: String, port: Int): Pair<Boolean, String> {
    val t = System.currentTimeMillis()
    return try {
        java.net.Socket().use { s -> s.connect(java.net.InetSocketAddress(host, port), 4000) }
        true to ((System.currentTimeMillis() - t).toString() + " ms")
    } catch (e: Exception) {
        false to (e.message ?: e.javaClass.simpleName)
    }
}

/** Набор проверок «мимо VPN»: DNS, HTTPS, API регистрации, сервер MASQUE, IPv6, обычный сайт. */
suspend fun runFullDiagnostics(ctx: android.content.Context): List<DiagCheck> = withContext(Dispatchers.IO) {
    val out = mutableListOf<DiagCheck>()
    val base = runDiagnostics()
    out += DiagCheck(ctx.getString(R.string.chk_dns), base.dnsOk, if (base.dnsOk) "${base.dnsMs} ms" else ctx.getString(R.string.diag_fail))
    val httpsDetail = if (base.httpsOk) "${base.httpsMs} ms" + (if (base.colo.isNotEmpty()) " · ${base.colo}" else "") else ctx.getString(R.string.diag_fail)
    out += DiagCheck(ctx.getString(R.string.chk_https), base.httpsOk, httpsDetail)
    val api = tcpCheck("api.cloudflareclient.com", 443)
    out += DiagCheck(ctx.getString(R.string.chk_api), api.first, api.second)
    val ms = tcpCheck("162.159.198.2", 443)
    out += DiagCheck(ctx.getString(R.string.chk_masque), ms.first, ms.second)
    val v6 = tcpCheck("2606:4700:4700::1111", 443)
    out += DiagCheck(ctx.getString(R.string.chk_v6), v6.first, v6.second)
    val web = tcpCheck("www.google.com", 443)
    out += DiagCheck(ctx.getString(R.string.chk_web), web.first, web.second)
    // кто провайдер этой сети: имя узла публичного IP (справочная строка, всегда «ОК»)
    out += try {
        if (base.ip.isNotEmpty()) {
            val host = InetAddress.getByName(base.ip).canonicalHostName
            DiagCheck("Провайдер сети (имя узла публичного IP)", true, base.ip + " → " + host)
        } else {
            DiagCheck("Провайдер сети (имя узла публичного IP)", true, "публичный IP не получен")
        }
    } catch (e: Exception) {
        DiagCheck("Провайдер сети (имя узла публичного IP)", true, "не определён: " + (e.message ?: e.javaClass.simpleName))
    }
    // результаты попадают и в журнал, чтобы они были в отчёте
    try {
        mobile.Mobile.logLine("🔎 полная диагностика (мимо VPN):")
        out.forEach { mobile.Mobile.logLine("   " + (if (it.ok) "✔ " else "✘ ") + it.name + ": " + it.detail) }
        if (base.ip.isNotEmpty()) mobile.Mobile.logLine("   публичный IP: " + base.ip)
    } catch (t: Throwable) { }
    out
}

/** Тип текущей сети (без самого VPN). */
fun networkType(ctx: android.content.Context): String = try {
    val cm = ctx.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
    var wifi = false
    var cell = false
    for (n in cm.allNetworks) {
        val c = cm.getNetworkCapabilities(n) ?: continue
        if (c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN)) continue
        if (c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)) wifi = true
        if (c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR)) cell = true
    }
    when {
        wifi -> ctx.getString(R.string.net_wifi)
        cell -> ctx.getString(R.string.net_cell)
        else -> "—"
    }
} catch (t: Throwable) {
    "—"
}

fun fmtBytes(n: Long): String {
    if (n < 1024) return "$n B"
    val u = arrayOf("KB", "MB", "GB", "TB")
    var v = n.toDouble()
    var i = -1
    while (v >= 1024 && i < u.size - 1) { v /= 1024; i++ }
    return String.format(java.util.Locale.US, "%.1f %s", v, u[i])
}

/** Строки журнала с ошибками и предупреждениями. */
fun journalErrors(): List<String> = try {
    mobile.Mobile.getJournal(0).lines().filter { it.contains("✘") || it.contains("⚠") || it.contains("⛔") || it.contains("ошибк", true) }
} catch (t: Throwable) { emptyList() }

/** Полный отчёт: система, настройки, состояние движка и память, проверки, журнал. Ключи и токены не включаются. */
fun buildReport(ctx: android.content.Context, prefs: Prefs, vpn: VpnController, account: AccountController, checks: List<DiagCheck>): String {
    val sb = StringBuilder()
    sb.append("Hydra report ").append(java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date())).append('\n')
    sb.append("core: ").append(try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" }).append('\n')
    sb.append(try { buildDoctor(ctx, prefs, vpn, checks) } catch (t: Throwable) { "\n=== ДИАГНОЗ: сбой разбора (" + t + ") ===\n" })
    sb.append("\n--- состояние ---\n")
    sb.append("state: ").append(vpn.state).append(", strategy: ").append(vpn.strategy).append(", colo: ").append(vpn.colo)
        .append(", rtt: ").append(vpn.rttMs).append(" ms, rx/tx: ").append(fmtBytes(vpn.rxBytes)).append(" / ").append(fmtBytes(vpn.txBytes)).append('\n')
    if (vpn.message.isNotEmpty()) sb.append("message: ").append(vpn.message).append('\n')
    sb.append("account: masque=").append(account.id.take(8)).append(" wg=").append(account.wgId.take(8)).append('\n')
    sb.append("settings: protocol=").append(prefs.protocol).append(", channel=").append(prefs.channel)
        .append(", blockedColos=").append(prefs.blockedColos).append(", allowColos=").append(prefs.allowColos)
        .append(", fallbackAny=").append(prefs.fallbackAny).append(", parallel=").append(prefs.parallel)
        .append(", autostart=").append(prefs.autoStart)
        .append(", customSni=").append(prefs.customSni).append(", customEndpoint=").append(prefs.customEndpoint)
        .append(", customDns=").append(if (prefs.customDnsOn) prefs.customDns else "off")
        .append(", excludedRoutes=").append(prefs.excludedRoutes.split(',').size)
        .append(", splitOnlySelected=").append(prefs.splitOnlySelected).append(", splitApps=").append(prefs.splitApps.size).append('\n')
    sb.append("selected apps: ").append(prefs.splitApps.sorted().joinToString(", ").ifEmpty { "—" }).append('\n')
    sb.append("telegram selected: ").append(prefs.splitApps.any { it.contains("telegram", true) }).append('\n')
    sb.append("\n--- движок и память ---\n")
    sb.append(try { mobile.Mobile.diagnostics() } catch (t: Throwable) { "н/д\n" })
    sb.append("\n--- система ---\n")
    sb.append(try { systemReport(ctx) } catch (t: Throwable) { "н/д\n" })
    if (checks.isNotEmpty()) {
        sb.append("\n--- проверки (мимо VPN) ---\n")
        checks.forEach { sb.append(if (it.ok) "OK   " else "FAIL ").append(it.name).append(": ").append(it.detail).append('\n') }
    }
    sb.append("\n--- журнал ---\n")
    sb.append(try { mobile.Mobile.getJournalFull(4000) } catch (t: Throwable) { try { mobile.Mobile.getJournal(1500) } catch (t2: Throwable) { "" } })
    return sb.toString()
}

/** Отправляет отчёт файлом .txt (так его принимают мессенджеры и почта); если не вышло — текстом. */
fun shareReport(ctx: android.content.Context, text: String) {
    try {
        val dir = java.io.File(ctx.cacheDir, "reports")
        dir.mkdirs()
        dir.listFiles()?.forEach { if (it.name.startsWith("hydra-report")) it.delete() }
        val name = "hydra-report-" + java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.US).format(java.util.Date()) + ".txt"
        val f = java.io.File(dir, name)
        f.writeText(text)
        val uri = androidx.core.content.FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", f)
        val i = android.content.Intent(android.content.Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(android.content.Intent.EXTRA_STREAM, uri)
            .putExtra(android.content.Intent.EXTRA_SUBJECT, name)
            .addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
        i.clipData = android.content.ClipData.newRawUri(name, uri)
        ctx.startActivity(android.content.Intent.createChooser(i, null).addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION))
    } catch (t: Throwable) {
        try {
            val i = android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain")
                .putExtra(android.content.Intent.EXTRA_TEXT, text.takeLast(200_000))
            ctx.startActivity(android.content.Intent.createChooser(i, null))
        } catch (t2: Throwable) { }
    }
}
HYDRA_EOF

putv "app/src/main/java/app/hydra/Doctor.kt" <<'HYDRA_EOF'
package app.hydra

import android.content.Context
import android.os.PowerManager
import android.provider.Settings

/** Одна найденная проблема: что видно, почему так, что сделать человеку и что чинить в коде. */
data class Finding(
    val id: String,
    val level: Int, // 3 — критично, 2 — важно, 1 — замечание
    val title: String,
    val seen: String,
    val why: String,
    val fix: String,
    val dev: String
)

private fun validEndpoint(s: String): Boolean {
    val t = s.trim()
    if (t.startsWith("[")) return true
    val parts = t.split(":")
    if (parts.size > 2) return t.contains("::")
    val ip = parts[0].split(".")
    if (ip.size != 4) return false
    for (o in ip) {
        val n = o.toIntOrNull() ?: return false
        if (n !in 0..255) return false
    }
    if (parts.size == 2) {
        val p = parts[1].toIntOrNull() ?: return false
        if (p !in 1..65535) return false
    }
    return true
}

/** Строки с ✘ из последней проверки сервисов через туннель (если её запускали). */
private fun lastServiceFailures(journal: String): List<String>? {
    val i = journal.lastIndexOf("проверка сервисов через туннель")
    if (i < 0) return null
    val block = journal.substring(i).lines().take(30)
    val end = block.indexOfFirst { it.contains("Доступно") }
    val part = if (end >= 0) block.take(end) else block.take(15)
    return part.filter { it.contains("✘") }.map { it.trim() }
}

private fun operatorName(code: String): String = when (code) {
    "25001" -> "МТС"
    "25002" -> "МегаФон"
    "25020" -> "Tele2"
    "25099" -> "Билайн"
    "25011" -> "Yota"
    "25035" -> "МОТИВ"
    "" -> "нет данных"
    else -> "оператор $code"
}

/** Раздел «профиль сети»: какая сеть сейчас, кто оператор и что Гидра успела о ней узнать. */
private fun networkProfile(ctx: Context, checks: List<DiagCheck>, engine: String): String {
    val sb = StringBuilder()
    sb.append("\n--- профиль сети ---\n")
    sb.append("Тип сети сейчас: ").append(networkType(ctx)).append('\n')
    try {
        val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager
        val net = tm.networkOperator.orEmpty()
        val sim = tm.simOperator.orEmpty()
        sb.append("Оператор сети: ").append(operatorName(net)).append(" (").append(net).append(")\n")
        sb.append("Оператор SIM: ").append(operatorName(sim)).append(" (").append(sim).append(")\n")
    } catch (t: Throwable) {
        sb.append("Оператор: не определён\n")
    }
    val prov = checks.lastOrNull { it.name.startsWith("Провайдер сети") }
    if (prov != null) sb.append("Провайдер по публичному IP: ").append(prov.detail).append('\n')
    val brain = engine.substringAfter("🧠 что Гидра знает", "")
    if (brain.isNotEmpty()) {
        sb.append("Что Гидра знает об этой сети (сервисы по стратегиям, плохие дата-центры):\n")
        sb.append("🧠 что Гидра знает").append(brain)
        if (!brain.endsWith("\n")) sb.append('\n')
    } else {
        sb.append("Что Гидра знает об этой сети: данных пока нет (нужно подключение и несколько секунд).\n")
    }
    return sb.toString()
}

fun diagnose(
    ctx: Context, prefs: Prefs, vpn: VpnController,
    checks: List<DiagCheck>, engine: String, journal: String
): List<Finding> {
    val out = mutableListOf<Finding>()
    fun add(id: String, level: Int, title: String, seen: String, why: String, fix: String, dev: String) {
        out += Finding(id, level, title, seen, why, fix, dev)
    }

    // ---- проверки мимо VPN ----
    val dns = checks.getOrNull(0)
    val https = checks.getOrNull(1)
    val api = checks.getOrNull(2)
    val web = checks.getOrNull(5)
    if (dns != null && !dns.ok) {
        add("D01", 3, "Не работает DNS",
            "проверка DNS: ${dns.detail}",
            "Телефон не может превратить имя сайта в адрес. Сети нет, либо DNS провайдера не отвечает.",
            "1) Выключи и включи Wi-Fi или мобильную сеть. 2) Попробуй другую сеть. 3) Нажми «Диагностика» ещё раз.",
            "Diagnostics.kt: runDiagnostics (InetAddress.getByName); dns.go: SetSystemDNS")
    } else if (https != null && !https.ok) {
        add("D02", 3, "Нет HTTPS до Cloudflare",
            "DNS работает, а HTTPS к cloudflare.com не проходит: ${https.detail}",
            "Провайдер или сеть режут соединения к Cloudflare. Это бывает при «белых списках».",
            "Подключись к другой сети (Wi-Fi вместо мобильной или наоборот) и повтори диагностику.",
            "mobile/netalive.go: realNetState/classify; learn.go: sniPool (российские имена)")
    }
    if (api != null && !api.ok) {
        add("D03", 2, "Не открывается сервер регистрации WARP",
            "api.cloudflareclient.com:443: ${api.detail}",
            "Без него нельзя получить или обновить ключи WARP. Уже подключённый туннель при этом может работать.",
            "Если ключей ещё нет: подключись по другой сети, зарегистрируйся, потом возвращайся. Если есть, ничего делать не нужно.",
            "register.go: гонка маршрутов регистрации (api.devices.cloudflare.com запасной)")
    }
    if (web != null && !web.ok && dns?.ok == true && https?.ok == true) {
        add("D04", 1, "Обычный сайт (google.com) не открывается напрямую",
            "tcp www.google.com:443: ${web.detail}",
            "Прямой доступ к Google закрыт у этой сети. Для VPN это нормально, важно, что он открывается через туннель.",
            "Ничего, если через включённый VPN сайты открываются.",
            "Diagnostics.kt: runFullDiagnostics")
    }

    // ---- состояние туннеля ----
    val st = vpn.state
    if (st == "failed") {
        add("D10", 3, "Туннель не поднимается",
            "состояние: failed. ${vpn.message}",
            "Все стратегии из списка не сработали в этой сети.",
            "1) Подожди 1–2 минуты: Гидра пробует новые варианты сама. 2) Если не помогло, смени сеть. 3) Отправь этот отчёт целиком.",
            "engine.go: Run/runStrategy; learn.go: мутации; memory.go: Rank")
    } else if (st == "reconnecting") {
        add("D11", 2, "Туннель переподключается",
            "состояние: reconnecting. ${vpn.message}",
            "Связь пропала, Гидра ищет другой путь.",
            "Подожди минуту. Если так повторяется часто, отправь отчёт.",
            "engine.go: noteLoss; race.go: горячий резерв")
    }
    if (st == "up" && vpn.rttMs > 700) {
        add("D12", 2, "Очень большая задержка",
            "задержка ${vpn.rttMs} мс (норма до 400)",
            "Путь до дата-центра плохой или канал перегружен.",
            "Попробуй другой дата-центр: Дополнительно → Дата-центры → разрешить HEL, FRA, AMS.",
            "colo.go; engine.go: политика дата-центров")
    }
    val blocked = prefs.blockedColos.split(",").map { it.trim().uppercase() }.filter { it.isNotEmpty() }
    if (st == "up" && vpn.colo.isNotEmpty() && blocked.contains(vpn.colo.uppercase())) {
        add("D13", 2, "Подключились к запрещённому дата-центру",
            "дата-центр ${vpn.colo} есть в списке запрещённых",
            "Включена настройка «всё равно подключаться», когда других нет.",
            "Если нужно строго без этого дата-центра: Дополнительно → отключи «подключаться к любому».",
            "mobile/policy.go: SetFallback; gate.go: coloAllowed")
    }

    // ---- настройки, которые ломают работу ----
    if (prefs.splitOnlySelected && prefs.splitApps.isEmpty()) {
        add("D20", 3, "VPN включён, но ни одно приложение не пускается в туннель",
            "режим «только выбранные приложения», выбрано 0",
            "Весь трафик идёт мимо VPN, поэтому кажется, что VPN «не работает».",
            "Меню → Приложения: отметь нужные (Telegram, YouTube, WhatsApp) или выключи режим «только выбранные».",
            "AppsScreen.kt; HydraVpnService.kt (addAllowedApplication)")
    }
    if (!prefs.parallel) {
        add("D21", 2, "Выключен горячий резерв и гонка стратегий",
            "параллельный режим: выкл",
            "Стратегии пробуются по одной, а при обрыве связь пропадает на время переподключения.",
            "Включи параллельный режим в «Дополнительно».",
            "mobile/policy.go: SetParallel; race.go")
    }
    if (!prefs.autoStart) {
        add("D22", 1, "Нет автозапуска после перезагрузки",
            "автозапуск: выкл",
            "После перезагрузки телефона VPN сам не включится («включил и забыл» не работает).",
            "Дополнительно → Постоянная работа → включи автозапуск.",
            "BootReceiver.kt")
    }
    if (prefs.customEndpoint.isNotBlank() && !validEndpoint(prefs.customEndpoint)) {
        add("D23", 2, "Свой адрес сервера записан неверно",
            "значение: «${prefs.customEndpoint}»",
            "Нужен IP или IP:порт, например 162.159.198.2 или 162.159.198.2:443. Имя сайта не подойдёт.",
            "Дополнительно → Свой адрес сервера → введи IP или нажми «Сбросить».",
            "mobile/vpn_usque.go (currentCustom); custom.go: CustomEndpointStrategies")
    }
    if (prefs.customDnsOn && prefs.customDns.isBlank()) {
        add("D24", 1, "Свой DNS включён, но сервер не указан",
            "customDnsOn=true, customDns пусто",
            "Используется DNS по умолчанию, настройка ничего не меняет.",
            "Параметры DNS → укажи сервер (например 1.1.1.1) или выключи переключатель.",
            "AdvancedScreens.kt: DnsScreen; AccountController.kt: dnsProvider")
    }
    try {
        val mode = Settings.Global.getString(ctx.contentResolver, "private_dns_mode")
        if (mode == "hostname") {
            add("D25", 2, "В Android включён строгий частный DNS",
                "private_dns_mode=hostname (${Settings.Global.getString(ctx.contentResolver, "private_dns_specifier") ?: ""})",
                "Строгий частный DNS (DoT) часто не работает через VPN: сайты и Telegram не открываются.",
                "Настройки Android → Подключение → Частный DNS → «Автоматически» или «Отключено».",
                "HomeScreen.kt (предупреждение); HydraVpnService.kt")
        }
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(ctx.packageName)) {
            add("D26", 2, "Система может убить VPN в фоне",
                "приложение не исключено из оптимизации батареи",
                "Xiaomi/HyperOS агрессивно закрывает фоновые приложения, и VPN отваливается.",
                "Дополнительно → «Разрешить работу в фоне», затем «Автозапуск (Xiaomi)».",
                "SystemInfo.kt; BootReceiver.kt")
        }
    } catch (t: Throwable) { }

    // ---- по журналу и движку ----
    val lost = Regex("потерь без резерва: (\\d+)").find(engine)?.groupValues?.get(1)?.toIntOrNull() ?: 0
    if (lost > 0) {
        add("D30", 2, "Были обрывы без резерва",
            "потерь без резерва: $lost",
            "В момент обрыва не было готового запасного туннеля.",
            "Включи параллельный режим и протокол «Авто». Если уже включены, отправь отчёт.",
            "engine.go: noteLoss; race.go: горячий резерв")
    }
    if (engine.contains("состояние сети: whitelist")) {
        add("D31", 3, "Сеть в режиме «белых списков»",
            "доступны только российские адреса, зарубежные закрыты",
            "Оператор ограничил интернет списком разрешённых сайтов. Обычный WARP в этом режиме недоступен.",
            "Переключись на Wi-Fi или подожди: Гидра сама пробует имена из белых списков (SNI) и вернётся, когда режим снимут.",
            "mobile/netalive.go: realWLScan/WhitelistCheck; learn.go: sniPool")
    } else if (engine.contains("состояние сети: dead")) {
        add("D32", 3, "Нет интернета вообще",
            "ни зарубежные, ни российские адреса не отвечают",
            "Нет сигнала сети, режим «в самолёте» или сеть отключена.",
            "Проверь сигнал и режим «в самолёте», переключи сеть.",
            "mobile/netalive.go: classify")
    }
    if (journal.contains("Telegram не доходит")) {
        add("D33", 2, "Telegram не доходит через выбранный дата-центр",
            "в журнале: «Telegram не доходит через дата-центр …»",
            "Интернет работает, а сервера Telegram режутся на этом маршруте.",
            "Гидра ищет другой дата-центр сама. Можно ускорить: Дополнительно → Дата-центры → разрешить только HEL, FRA, AMS.",
            "gate.go: serviceGate/noteBadColo")
    }
    val hs = journal.lines().takeLast(400).count { it.contains("TLS handshake failure") }
    if (hs >= 5) {
        add("D34", 1, "Много отказов TLS при рукопожатии",
            "$hs строк «TLS handshake failure» в свежем журнале",
            "Пробуются адреса, которые не являются серверами MASQUE (адреса WireGuard).",
            "Ничего делать не нужно, если туннель в итоге поднялся. Иначе отправь отчёт.",
            "strategies.go: MasqueStrategies (список адресов); learn.go: генерация адресов")
    }
    val live = journal.lines().lastOrNull { it.contains("🌐 живая проверка") }
    if (live != null) {
        if (live.contains("недоступна")) {
            add("D43", 1, "Живая проверка через туннель не смогла работать",
                live.trim(),
                "Приложение не смогло отправить запрос через свой же туннель (контроль warp=on не прошёл).",
                "Ничего делать не нужно: работает проверка по адресам. Отправь отчёт, и я поменяю способ живой проверки.",
                "ServiceProber.kt (Network.openConnection); HydraVpnService.kt (исключение приложения из VPN)")
        } else if (live.contains("✘")) {
            add("D42", 2, "Живая проверка: сервис не открывается через туннель",
                live.trim(),
                "Туннель работает, но настоящий HTTPS-запрос к сервису не проходит или не отвечает дважды подряд.",
                "Гидра сама меняет дата-центр и придумывает новые варианты. Если за 5 минут не помогло, отправь отчёт.",
                "ServiceProber.kt; brain.go: ReportService; race.go: svcBad")
        }
    }
    val svc = lastServiceFailures(journal)
    if (svc == null && st == "up") {
        add("D40", 1, "Проверка сервисов через туннель ещё не запускалась",
            "в журнале нет результата проверки",
            "Без неё неизвестно, доходят ли YouTube, WhatsApp и Telegram.",
            "Диагностика → «Проверить сервисы» (при включённом VPN), затем снова собери отчёт.",
            "services.go: ServiceCheck; DiagnosticsScreen.kt")
    } else if (svc != null && svc.isNotEmpty()) {
        add("D41", 2, "Часть сервисов не доходит через туннель",
            svc.joinToString("\n         "),
            "Туннель есть, но до этих адресов TCP не проходит. Если не отвечают только они, их режут по маршруту или адресу.",
            "Гидра подбирает другой дата-центр и стратегию сама. Если не прошло за 5 минут, отправь отчёт.",
            "services.go; gate.go; learn.go (адаптация под сервис — план v22.2)")
    }
    return out
}

/** Раздел отчёта «ДИАГНОЗ»: читается первым, написан простым языком, у каждой проблемы есть шаги. */
fun buildDoctor(ctx: Context, prefs: Prefs, vpn: VpnController, checks: List<DiagCheck>): String {
    val engine = try { mobile.Mobile.diagnostics() } catch (t: Throwable) { "" }
    val journal = try { mobile.Mobile.getJournalFull(4000) } catch (t: Throwable) { "" }
    val list = diagnose(ctx, prefs, vpn, checks, engine, journal).sortedByDescending { it.level }
    val sb = StringBuilder()
    sb.append("\n=== ДИАГНОЗ (читать первым) ===\n")
    val crit = list.count { it.level >= 3 }
    if (list.isEmpty()) {
        sb.append("Итог: правила Доктора проблем не нашли.\n")
        sb.append("Если что-то всё равно не работает, опиши словами, что именно и в какой сети, и отправь этот отчёт.\n")
    } else {
        sb.append("Итог: найдено проблем ").append(list.size).append(", критичных ").append(crit).append(".\n")
        sb.append("Что делать: иди сверху вниз и выполняй пункт «Что сделать». Не помогло, отправь этот файл Claude целиком.\n\n")
        for (f in list) {
            val tag = when (f.level) { 3 -> "КРИТИЧНО"; 2 -> "ВАЖНО"; else -> "ЗАМЕЧАНИЕ" }
            sb.append('[').append(f.id).append("] ").append(tag).append(": ").append(f.title).append('\n')
            sb.append("  Что видно:     ").append(f.seen).append('\n')
            sb.append("  Почему так:    ").append(f.why).append('\n')
            sb.append("  Что сделать:   ").append(f.fix).append('\n')
            sb.append("  Код (для Claude): ").append(f.dev).append("\n\n")
        }
    }
    sb.append(networkProfile(ctx, checks, engine))
    sb.append("--- реестр возможностей (честный статус) ---\n")
    sb.append("✔ Свой адрес сервера: добавляется первым в список стратегий.\n")
    sb.append("✔ Свой SNI: добавляется как дополнительные стратегии, остальные не пропадают.\n")
    sb.append("✔ Память по сетям: Wi-Fi различается отпечатком (шлюз + DNS), мобильная сеть кодом оператора.\n")
    sb.append("✔ Самообучение: мутации TTL, числа и размера фейков, SNI, портов, адресов; мёртвые отбрасываются.\n")
    sb.append("✔ Параллельная гонка стратегий и горячий резерв (включается настройкой).\n")
    sb.append("✔ Проверка Telegram, YouTube, WhatsApp, Instagram, Discord через туннель (достижимость адреса по TCP).\n")
    sb.append("✔ Живая проверка: настоящие HTTPS-запросы к YouTube, видео YouTube и WhatsApp через туннель каждые 5 минут и после смены пути. Видит подмену DNS и обрыв TLS.\n")
    sb.append("✔ Если сервис мёртв при исправном остальном, Гидра сразу уходит на другой дата-центр (не чаще раза в 5 минут на сервис, не более трёх плохих дата-центров на сеть).\n")
    sb.append("✔ Скорость туннеля измеряется и влияет на выбор: быстрые стратегии идут первыми.\n")
    sb.append("⚠ Замедление одного YouTube по имени сайта отдельно не измеряется: видна общая скорость туннеля, а не скорость видео.\n")
    sb.append("⚠ Свой DNS: обычный DNS внутри туннеля. DoH и DoT не поддерживаются.\n")
    sb.append("✘ Системный частный DNS не настраивается приложением, только определяется.\n")
    sb.append("✔ Память сервисов по сетям: какие из Telegram, YouTube, WhatsApp доходили через какую стратегию. Она влияет на порядок перебора, а при сбое сервиса Гидра сама придумывает новые варианты.\n")
    sb.append("⚠ Знания об ограничениях операторов не вшиты: Гидра выучивает их сама по каждой сети (оператор SIM или Wi-Fi). Заранее известных «правил МТС/Билайна» нет, и выдумывать их я не буду.\n")
    sb.append("=== конец диагноза ===\n")
    return sb.toString()
}
HYDRA_EOF

putv "app/src/main/java/app/hydra/ServiceProber.kt" <<'HYDRA_EOF'
package app.hydra

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.net.HttpURLConnection
import java.net.URL

/**
 * «Живая» проверка: настоящие HTTPS-запросы к YouTube и WhatsApp прямо через туннель и замер скорости.
 * В отличие от проверки по адресам (SYN-ACK) она видит и подмену DNS, и обрыв TLS, и медленный туннель.
 * Запросы идут через сеть VPN с её DNS, поэтому ответ DNS провайдера ни на что не влияет.
 * Результат уходит в ядро: оно запоминает его по сети и стратегии и при мёртвом сервисе меняет путь.
 *
 * Защита от ложных срабатываний: перед проверкой контрольный запрос к Cloudflare должен показать warp=on.
 * Если приложение не может ходить через свой туннель, проверка честно пишет «недоступна» и ничего не меняет.
 */
object ServiceProber {
    private class Target(val name: String, val url: String)

    private val targets = listOf(
        Target("YouTube", "https://www.youtube.com/generate_204"),
        Target("YouTube-видео", "https://redirector.googlevideo.com/generate_204"),
        Target("WhatsApp", "https://web.whatsapp.com/")
    )

    private const val UA = "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36"
    private const val PERIOD_MS = 5 * 60_000L

    @Volatile private var running = false
    private var lastKey = ""
    private var lastAt = 0L

    /** Вызывать из цикла службы, пока туннель поднят. key = стратегия@дата-центр. */
    fun tick(ctx: Context, key: String) {
        val now = System.currentTimeMillis()
        if (running) return
        if (key == lastKey && now - lastAt < PERIOD_MS) return
        lastKey = key
        lastAt = now
        running = true
        val app = ctx.applicationContext
        Thread {
            try {
                Thread.sleep(7000) // дать туннелю прогреться
                if (mobile.Mobile.engineStatus().startsWith("up")) runProbe(app)
            } catch (t: Throwable) {
            } finally {
                running = false
            }
        }.start()
    }

    /** Туннель не поднят: следующая проверка пройдёт сразу после подключения. */
    fun reset() {
        lastKey = ""
    }

    private fun log(s: String) {
        try { mobile.Mobile.logLine(s) } catch (t: Throwable) { }
    }

    private fun vpnNetwork(ctx: Context): Network? {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        for (n in cm.allNetworks) {
            val c = cm.getNetworkCapabilities(n) ?: continue
            if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return n
        }
        return null
    }

    /** Контроль: запрос к Cloudflare через туннель должен вернуть warp=on. */
    private fun control(net: Network): Pair<Boolean, String> = try {
        val c = net.openConnection(URL("https://cloudflare.com/cdn-cgi/trace")) as HttpURLConnection
        c.connectTimeout = 6000
        c.readTimeout = 6000
        val body = c.inputStream.bufferedReader().use { it.readText() }
        c.disconnect()
        val warp = body.lines().firstOrNull { it.startsWith("warp=") }?.substringAfter("=") ?: "нет"
        Pair(warp == "on" || warp == "plus", "warp=$warp")
    } catch (e: Exception) {
        Pair(false, e.javaClass.simpleName + (e.message?.let { ": " + it.take(60) } ?: ""))
    }

    private class Res(val ok: Boolean, val ms: Long, val note: String)

    /** Любой ответ HTTP (даже 404) значит: имя нашлось, TLS прошёл, сервис отвечает. */
    private fun probe(net: Network, url: String): Res {
        val t = System.currentTimeMillis()
        return try {
            val c = net.openConnection(URL(url)) as HttpURLConnection
            c.connectTimeout = 5000
            c.readTimeout = 6000
            c.instanceFollowRedirects = false
            c.setRequestProperty("User-Agent", UA)
            val code = c.responseCode
            c.disconnect()
            Res(true, System.currentTimeMillis() - t, "HTTP $code")
        } catch (e: Exception) {
            Res(false, System.currentTimeMillis() - t, e.javaClass.simpleName + (e.message?.let { ": " + it.take(60) } ?: ""))
        }
    }

    /** Скорость скачивания через туннель, кбит/с (до 4 секунд); -1 — не измерена. */
    private fun speedKbps(net: Network): Long = try {
        val c = net.openConnection(URL("https://speed.cloudflare.com/__down?bytes=1500000")) as HttpURLConnection
        c.connectTimeout = 5000
        c.readTimeout = 5000
        val t = System.currentTimeMillis()
        var total = 0L
        c.inputStream.use { ins ->
            val buf = ByteArray(16384)
            while (System.currentTimeMillis() - t < 4000) {
                val n = ins.read(buf)
                if (n < 0) break
                total += n
            }
        }
        c.disconnect()
        val ms = maxOf(1L, System.currentTimeMillis() - t)
        total * 8 / ms
    } catch (e: Exception) {
        -1L
    }

    private fun runProbe(ctx: Context) {
        val net = vpnNetwork(ctx)
        if (net == null) {
            log("🌐 живая проверка недоступна: сеть VPN не видна приложению")
            return
        }
        val ctl = control(net)
        if (!ctl.first) {
            log("🌐 живая проверка недоступна: контрольный запрос не идёт через туннель (" + ctl.second + ")")
            return
        }
        val parts = mutableListOf<String>()
        for (t in targets) {
            var r = probe(net, t.url)
            if (!r.ok) {
                Thread.sleep(2000)
                r = probe(net, t.url) // второй шанс: одиночный сбой сервис не хоронит
            }
            parts.add(t.name + (if (r.ok) " ✔ " + r.ms + " мс" else " ✘ " + r.note))
            try { mobile.Mobile.reportService(t.name, if (r.ok) "ok" else "dead", r.note) } catch (e: Throwable) { }
        }
        val sp = speedKbps(net)
        parts.add("скорость " + (if (sp >= 0) "~" + sp + " кбит/с" else "не измерена"))
        if (sp >= 0) {
            try { mobile.Mobile.reportSpeed(sp) } catch (e: Throwable) { }
        }
        log("🌐 живая проверка через туннель: " + parts.joinToString("; "))
    }
}
HYDRA_EOF

putv "app/src/main/java/app/hydra/HydraVpnService.kt" <<'HYDRA_EOF'
package app.hydra

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.net.ConnectivityManager
import android.net.Network
import android.os.ParcelFileDescriptor
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager
import android.util.Log

/**
 * Системный VPN-сервис: создаёт TUN-интерфейс и отдаёт его Go-ядру, которое
 * гонит пакеты через туннель WARP. Раздельное туннелирование — средствами Android:
 * в списке приложений либо «только эти», либо «все, кроме этих».
 * Само приложение всегда исключено из VPN, иначе его собственное QUIC-соединение
 * с Cloudflare пошло бы внутрь туннеля.
 * Сеть (Wi-Fi/мобильная) отслеживается через системные уведомления: при смене
 * ядро узнаёт об этом сразу и переподключается.
 */
class HydraVpnService : VpnService() {

    companion object {
        const val ACTION_START = "app.hydra.action.START"
        const val ACTION_STOP = "app.hydra.action.STOP"
        private const val TAG = "Hydra"
        private const val CHANNEL = "hydra_status"
        private const val NOTIF_ID = 1
    }

    private val handler = Handler(Looper.getMainLooper())
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var cellCallback: ConnectivityManager.NetworkCallback? = null
    private var forceCell = false

    /** TUN живёт в службе: при перезапуске ядра интерфейс не пропадает, и трафик не уходит мимо VPN. */
    private var tunPfd: ParcelFileDescriptor? = null
    private var restartFails = 0
    private var nextRestartAt = 0L

    private fun closeTun() {
        try { tunPfd?.close() } catch (t: Throwable) { }
        tunPfd = null
    }

    private fun jlog(s: String) { try { mobile.Mobile.logLine(s) } catch (t: Throwable) { } }

    private fun describeNet(n: Network): String = try {
        val c = cm().getNetworkCapabilities(n)
        val t = when {
            c == null -> "?"
            c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "сотовая"
            c.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            else -> "другая"
        }
        t + (if (c?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true) ", проверена" else ", не проверена")
    } catch (t: Throwable) { "?" }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        jlog("служба: команда " + (intent?.action ?: "перезапуск системой / запуск"))
        goForeground(getString(R.string.notif_connecting))
        val prefs = Prefs(this)
        if (intent?.action == ACTION_STOP) {
            stopVpn()
            return START_NOT_STICKY
        }
        // перезапуск системой (intent == null) — только если пользователь хотел VPN
        if (intent == null && !(prefs.wantConnected || prefs.autoStart)) {
            stopVpn()
            return START_NOT_STICKY
        }
        startVpn()
        return START_STICKY
    }

    private fun buildNotification(text: String): Notification {
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    /** Постоянное уведомление держит сервис на переднем плане: система его не убивает. */
    private fun goForeground(text: String) {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Hydra", NotificationManager.IMPORTANCE_LOW)
            )
            val n = buildNotification(text)
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIF_ID, n)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "передний план: " + t.message)
        }
    }

    /** Раз в 3 секунды: обновляет уведомление и, если ядро остановилось, а VPN нужен, поднимает заново. */
    private val statusUpdater = object : Runnable {
        override fun run() {
            try {
                val raw = mobile.Mobile.engineStatus()
                val p = raw.split("|")
                val text = when (p.getOrElse(0) { "off" }) {
                    "up" -> getString(R.string.notif_up, p.getOrElse(2) { "" }, p.getOrElse(3) { "0" }.toIntOrNull() ?: 0)
                    "reconnecting" -> getString(R.string.notif_reconnecting)
                    "failed" -> getString(R.string.notif_failed)
                    else -> getString(R.string.notif_connecting)
                }
                getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification(text))
                if (raw.startsWith("up")) restartFails = 0
                if (raw.startsWith("up")) {
                    ServiceProber.tick(this@HydraVpnService, p.getOrElse(1) { "" } + "@" + p.getOrElse(2) { "" })
                } else {
                    ServiceProber.reset()
                }
                // Wi-Fi ведёт в запрещённый дата-центр: туннель автоматически идёт через мобильную сеть
                val prefsNow = Prefs(this@HydraVpnService)
                if (p.getOrElse(4) { "" }.startsWith("⛔") && prefsNow.channel == "auto" && !forceCell) {
                    val wp = curWifiPrint()
                    if (wp.isNotEmpty() && hasCellNet()) {
                        enableAutoCell(wp)
                        return
                    }
                }
                val now = System.currentTimeMillis()
                if (raw.startsWith("off") && Prefs(this@HydraVpnService).wantConnected && now >= nextRestartAt) {
                    restartFails++
                    nextRestartAt = now + minOf(60_000L, 3_000L shl minOf(restartFails, 5))
                    jlog("служба: ядро остановлено — поднимаю заново (попытка $restartFails)")
                    startVpn()
                }
            } catch (t: Throwable) {
            }
            handler.postDelayed(this, 3000)
        }
    }

    private fun cm() = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager

    /** Отпечаток текущего Wi-Fi или "" (если Wi-Fi нет). */
    private fun curWifiPrint(): String = try {
        var r = ""
        for (n in cm().allNetworks) {
            val c = cm().getNetworkCapabilities(n) ?: continue
            if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) r = wifiPrint(n)
        }
        r
    } catch (t: Throwable) { "" }

    private fun hasCellNet(): Boolean = try {
        cm().allNetworks.any {
            val c = cm().getNetworkCapabilities(it)
            c != null && !c.hasTransport(NetworkCapabilities.TRANSPORT_VPN) && c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
        }
    } catch (t: Throwable) { false }

    private fun enableAutoCell(wp: String) {
        Prefs(this).addCellWifi(wp)
        jlog("📡 Этот Wi-Fi ведёт в запрещённый дата-центр: туннель переключается на мобильную сеть (на 12 часов для этого Wi-Fi)")
        handler.removeCallbacks(statusUpdater)
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        closeTun()
        handler.postDelayed({ startVpn() }, 1200)
    }

    private fun startVpn() {
        val running = try { !mobile.Mobile.engineStatus().startsWith("off") } catch (t: Throwable) { false }
        if (running) return

        handler.removeCallbacks(statusUpdater)
        handler.postDelayed(statusUpdater, 3000)
        val prefs = Prefs(this)
        prefs.migrate()
        forceCell = prefs.channel == "cell" || (prefs.channel == "auto" && prefs.cellWifiActive(curWifiPrint()))
        try {
            mobile.Mobile.setColoPolicy(prefs.blockedColos, prefs.allowColos)
            mobile.Mobile.setFallback(prefs.fallbackAny)
            mobile.Mobile.setProtocol(prefs.protocol)
            mobile.Mobile.setCustomSNI(prefs.customSni)
            mobile.Mobile.setParallel(if (prefs.parallel) 3L else 1L)
            mobile.Mobile.setIPv6(prefs.ipv6)
            mobile.Mobile.setServiceGate(prefs.tgGate)
            jlog("настройки: протокол=${prefs.protocol}, канал=${prefs.channel}, параллельно=${prefs.parallel}, свой DNS=${if (prefs.customDnsOn) prefs.customDns else "нет"}")
            mobile.Mobile.setCustomEndpoint(prefs.customEndpoint)
            mobile.Mobile.setDNS(systemDns(this))
            mobile.Mobile.setNetKey(currentNetKey())
        } catch (t: Throwable) {
            Log.e(TAG, "настройки ядра: " + t.message)
        }

        if (forceCell) {
            // «Мобильная сеть»: привязываем процесс к мобильной сети — сокеты Гидры
            // (она сама исключена из VPN) пойдут через неё, даже если подключён Wi-Fi.
            val req = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            var started = false
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    handler.post {
                        if (started) return@post
                        started = true
                        try { cm().bindProcessToNetwork(network) } catch (t: Throwable) { }
                        establishAndRun()
                    }
                }
            }
            cellCallback = cb
            try {
                cm().requestNetwork(req, cb)
            } catch (t: Throwable) {
                Log.e(TAG, "мобильная сеть: " + t.message)
                stopSelf()
                return
            }
            handler.postDelayed({
                if (!started) {
                    Log.e(TAG, "мобильная сеть недоступна")
                    stopVpn()
                }
            }, 10000)
        } else {
            establishAndRun()
        }
    }

    private fun establishAndRun() {
        val dir = filesDir.absolutePath
        val prefs = Prefs(this)

        val v4 = try { mobile.Mobile.accountAddr4(dir) } catch (t: Throwable) { "" }
        val v6 = try { mobile.Mobile.accountAddr6(dir) } catch (t: Throwable) { "" }
        if (v4.isEmpty()) {
            // аккаунта ещё нет (приложение само пробует зарегистрироваться): ждём и повторяем, VPN не бросаем
            jlog("служба: нет аккаунта WARP — повторю позже")
            return
        }

        val b = Builder()
            .setSession("Hydra")
            .setMtu(1280)
            .addAddress(v4, 32)
            .addRoute("0.0.0.0", 0)

        // свой DNS (внутри туннеля) или по умолчанию Cloudflare
        var dnsAdded = 0
        if (prefs.customDnsOn) {
            for (raw in prefs.customDns.split(',', ';', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }) {
                // принимаем IP, имя хоста, tls://host и https://host/path: имя превращаем в IP-адреса
                val host = raw.substringAfter("://").substringBefore("/").substringBefore(":")
                val ips = if (host.matches(Regex("[0-9a-fA-F:.]+"))) listOf(raw.substringAfter("://").substringBefore("/"))
                          else resolveHost(host)
                for (d in ips.take(2)) {
                    try { b.addDnsServer(d); dnsAdded++ } catch (e: Exception) { }
                }
            }
        }
        if (dnsAdded == 0) {
            b.addDnsServer("1.1.1.1")
            b.addDnsServer("1.0.0.1")
        }

        // подсети, которые идут напрямую, мимо VPN (Android 13+)
        if (Build.VERSION.SDK_INT >= 33) {
            for (r in prefs.excludedRoutes.split(',', ';', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }) {
                try {
                    val parts = r.split("/")
                    if (!parts[0].matches(Regex("[0-9a-fA-F:.]+"))) continue
                    val len = parts.getOrNull(1)?.toIntOrNull() ?: if (parts[0].contains(":")) 128 else 32
                    b.excludeRoute(android.net.IpPrefix(java.net.InetAddress.getByName(parts[0]), len))
                } catch (e: Exception) { }
            }
        }
        if (v6.isNotEmpty() && prefs.ipv6) {
            b.addAddress(v6, 128)
            b.addRoute("::", 0)
            b.addDnsServer("2606:4700:4700::1111")
        } else {
            // IPv6 в аккаунте нет: всё равно забираем ::/0 в TUN, ядро его отбросит —
            // иначе IPv6-трафик пошёл бы мимо VPN
            b.addAddress("fd00:7a7a::2", 128)
            b.addRoute("::", 0)
        }

        val apps = prefs.splitApps
        if (prefs.splitOnlySelected) {
            var any = false
            for (p in apps) {
                try {
                    b.addAllowedApplication(p)
                    any = true
                } catch (e: Exception) {
                }
            }
            if (!any) {
                stopVpn()
                return
            }
        } else {
            for (p in apps) {
                try {
                    b.addDisallowedApplication(p)
                } catch (e: Exception) {
                }
            }
            try {
                b.addDisallowedApplication(packageName)
            } catch (e: Exception) {
            }
        }

        val pfd = tunPfd ?: (try { b.establish() } catch (e: Exception) { null })
        if (pfd == null) {
            Log.e(TAG, "не удалось создать TUN")
            jlog("служба: не удалось создать TUN (нет разрешения VPN?) — остановка")
            stopVpn()
            return
        }
        tunPfd = pfd
        // ядру отдаём копию дескриптора: когда оно закроет её, сам интерфейс остаётся у службы
        val coreFd = try { ParcelFileDescriptor.dup(pfd.fileDescriptor) } catch (e: Exception) { null }
        if (coreFd == null) {
            jlog("служба: не удалось продублировать TUN — пересоздаю")
            closeTun()
            return
        }
        val err = try {
            mobile.Mobile.startTunnel(dir, coreFd.detachFd().toLong())
        } catch (t: Throwable) {
            t.message ?: "ошибка ядра"
        }
        if (err.isNotEmpty()) {
            Log.e(TAG, err)
            jlog("служба: ядро не запустилось: $err — повторю")
            return
        }
        watchNetwork()
        handler.removeCallbacks(statusUpdater)
        handler.postDelayed(statusUpdater, 3000)
    }

    /** Имя хоста в IP-адреса (в отдельном потоке с таймаутом: на главном потоке сеть запрещена). */
    private fun resolveHost(host: String): List<String> {
        var res: List<String> = emptyList()
        val t = Thread {
            res = try {
                java.net.InetAddress.getAllByName(host).mapNotNull { it.hostAddress }.filter { !it.contains("%") }
            } catch (e: Exception) { emptyList() }
        }
        t.start()
        t.join(4000)
        return res
    }

    /** Оператор сотовой сети (MCC+MNC, без разрешений): у разных операторов разный DPI. */
    private fun cellOperator(): String = try {
        (getSystemService(TELEPHONY_SERVICE) as TelephonyManager).networkOperator.orEmpty()
    } catch (t: Throwable) { "" }

    /** Отпечаток Wi-Fi: шлюз + DNS (SSID без разрешения на геолокацию недоступен). */
    private fun wifiPrint(n: Network): String = try {
        val lp = cm().getLinkProperties(n)
        val gw = lp?.routes?.firstOrNull { it.isDefaultRoute }?.gateway?.hostAddress.orEmpty()
        val dns = lp?.dnsServers?.joinToString(",") { it.hostAddress.orEmpty() }.orEmpty()
        Integer.toHexString((gw + "|" + dns).hashCode())
    } catch (t: Throwable) { "" }

    /**
     * Ключ сети для памяти стратегий: "wifi:<отпечаток>", "cell:<MCC+MNC>" или "default".
     * Сам VPN не считается. При принудительном канале — всегда сотовая.
     */
    private fun currentNetKey(): String {
        val op = cellOperator()
        if (forceCell) return "cell:$op"
        return try {
            var wifi: String? = null
            var cell = false
            for (n in cm().allNetworks) {
                val c = cm().getNetworkCapabilities(n) ?: continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) wifi = wifiPrint(n)
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) cell = true
            }
            when {
                wifi != null -> "wifi:$wifi"
                cell -> "cell:$op"
                else -> "default"
            }
        } catch (t: Throwable) {
            "default"
        }
    }

    /** Системные уведомления о сетях: смена Wi-Fi ↔ мобильная доходит до ядра сразу. */
    private fun watchNetwork() {
        if (netCallback != null) return
        val req = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            private fun push() {
                handler.postDelayed({
                    try { mobile.Mobile.setNetKey(currentNetKey()) } catch (t: Throwable) { }
                }, 300)
            }
            override fun onAvailable(network: Network) { jlog("📶 сеть появилась: " + describeNet(network)); push() }
            override fun onLost(network: Network) { jlog("📶 сеть пропала"); push() }
        }
        netCallback = cb
        try {
            cm().registerNetworkCallback(req, cb)
        } catch (t: Throwable) {
            Log.e(TAG, "слежение за сетью: " + t.message)
        }
    }

    private fun stopVpn() {
        jlog("служба: остановка")
        Prefs(this).wantConnected = false
        try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (t: Throwable) { }
        try { netCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        netCallback = null
        try { cellCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        cellCallback = null
        try { cm().bindProcessToNetwork(null) } catch (t: Throwable) { }
        handler.removeCallbacksAndMessages(null)
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        closeTun()
        stopSelf()
    }

    override fun onRevoke() {
        jlog("система отозвала VPN (включён другой VPN или VPN выключен в настройках)")
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        jlog("служба: уничтожена")
        handler.removeCallbacksAndMessages(null)
        try { netCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        try { cellCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        try { cm().bindProcessToNetwork(null) } catch (t: Throwable) { }
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        closeTun()
        super.onDestroy()
    }
}
HYDRA_EOF

echo "$NEW" > "$STAMP"
