#!/usr/bin/env bash
# WARP CLAUDE (Гидра) — обновление v22.2: «мозг» (память сервисов по сетям, проверка Telegram/YouTube/WhatsApp,
# самостоятельное придумывание вариантов при сбое сервиса) + «Доктор» и профиль сети в отчёте.
# Заменяет файлы один раз (при смене номера набора), дальше их можно править руками.
set -e

STAMP=.hydra_bootstrap
OLD="$(cat "$STAMP" 2>/dev/null || echo 0)"
NEW=14
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
    sb.append("⚠ Замедление по имени сайта (SNI) эта проверка не видит: нужна проверка скоростью.\n")
    sb.append("⚠ Свой DNS: обычный DNS внутри туннеля. DoH и DoT не поддерживаются.\n")
    sb.append("✘ Системный частный DNS не настраивается приложением, только определяется.\n")
    sb.append("✔ Память сервисов по сетям: какие из Telegram, YouTube, WhatsApp доходили через какую стратегию. Она влияет на порядок перебора, а при сбое сервиса Гидра сама придумывает новые варианты.\n")
    sb.append("⚠ Сбой YouTube или WhatsApp пока не заставляет мгновенно менять туннель (только Telegram): адрес берётся по имени, и подмена DNS дала бы ложные срабатывания. Решим по реальным отчётам.\n")
    sb.append("⚠ Знания об ограничениях операторов не вшиты: Гидра выучивает их сама по каждой сети (оператор SIM или Wi-Fi). Заранее известных «правил МТС/Билайна» нет, и выдумывать их я не буду.\n")
    sb.append("=== конец диагноза ===\n")
    return sb.toString()
}
HYDRA_EOF

echo "$NEW" > "$STAMP"
