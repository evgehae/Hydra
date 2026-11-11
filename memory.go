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
	return m, nil
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
			return m.priorLocked(net, s.ID)
		}
		rate := float64(st.OK+1) / float64(st.OK+st.Fail+2)
		pen := math.Min(st.EWMAms/5000, 0.3)
		bonus := 0.0
		if time.Since(st.LastOK) < 24*time.Hour {
			bonus = 0.1
		}
		return rate - pen + bonus
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
