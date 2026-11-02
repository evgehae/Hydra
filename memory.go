package hydra

import (
	"encoding/json"
	"math"
	"os"
	"sort"
	"sync"
	"time"
)

type stat struct {
	OK     int       `json:"ok"`
	Fail   int       `json:"fail"`
	EWMAms float64   `json:"ewma_ms"`
	LastOK time.Time `json:"last_ok"`
}

// Memory — «память Гидры»: что работало в какой сети.
// Ключ сети (net) выдаёт Android-часть: например "wifi:<hash>" или "cell:25001".
type Memory struct {
	mu   sync.Mutex
	path string
	Nets map[string]map[string]*stat `json:"nets"`
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
	}
	if s.OK+s.Fail > 20 { // забываем старое: DPI меняется
		s.OK /= 2
		s.Fail /= 2
	}
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
			return 0.5
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
