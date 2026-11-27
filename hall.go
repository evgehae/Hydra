package hydra

import (
	"encoding/json"
	"fmt"
	"sort"
	"time"
)

// «Зал славы»: рабочие конфиги, пойманные в этой сети, по дата-центрам. Это память, которую Гидра бережёт:
// сбои, чистки пула и «эксперименты» её не трогают. Если пользователь на время запретил дата-центр
// (например, оставил только HKG) — конфиги, которые туда попали, не считаются сломанными, а записываются
// сюда как «рабочие для этого дата-центра» и возвращаются в пул, как только дата-центр снова разрешён.

type hallRec struct {
	S    Strategy  `json:"s"`
	Colo string    `json:"colo"`
	N    int       `json:"n"`
	Seen bool      `json:"seen,omitempty"` // конфиг доходил до дата-центра, но тогда он был запрещён настройками
	Last time.Time `json:"last"`
	MS   float64   `json:"ms"`
}

const hallPerColo = 15

// NoteHall запоминает конфиг, попавший в дата-центр colo. seen=true — подключение отброшено политикой дата-центров.
func (m *Memory) NoteHall(net string, s Strategy, colo string, rtt time.Duration, seen bool) {
	colo = normColo(colo)
	if net == "" || colo == "" || s.ID == "" {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Hall == nil {
		m.Hall = map[string][]hallRec{}
	}
	list := m.Hall[net]
	ms := float64(rtt.Milliseconds())
	for i := range list {
		if list[i].S.ID == s.ID && list[i].Colo == colo {
			list[i].N++
			list[i].Last = time.Now()
			if !seen {
				list[i].Seen = false
				if list[i].MS == 0 {
					list[i].MS = ms
				} else if ms > 0 {
					list[i].MS = 0.7*list[i].MS + 0.3*ms
				}
			}
			m.Hall[net] = list
			m.saveSoonLocked()
			return
		}
	}
	list = append(list, hallRec{S: s, Colo: colo, N: 1, Seen: seen, Last: time.Now(), MS: ms})
	cnt := 0
	for _, r := range list {
		if r.Colo == colo {
			cnt++
		}
	}
	for cnt > hallPerColo { // на каждый дата-центр держим до 15: вытесняем самые редкие и давние
		worst := -1
		for i, r := range list {
			if r.Colo != colo {
				continue
			}
			if worst < 0 || r.N < list[worst].N || (r.N == list[worst].N && r.Last.Before(list[worst].Last)) {
				worst = i
			}
		}
		if worst < 0 {
			break
		}
		list = append(list[:worst], list[worst+1:]...)
		cnt--
	}
	m.Hall[net] = list
	Logf("🏆 зал славы (%s): %s → %s%s", net, s.ID, colo, map[bool]string{true: " (дата-центр пока запрещён)", false: ""}[seen])
	m.saveSoonLocked()
}

// RestoreHall — конфиги зала славы, которые стоит держать в пуле: подключавшиеся по-настоящему
// и те, чей дата-центр сейчас разрешён.
func (m *Memory) RestoreHall(net string, p *ColoPolicy) []Strategy {
	m.mu.Lock()
	list := append([]hallRec(nil), m.Hall[net]...)
	m.mu.Unlock()
	var out []Strategy
	for _, r := range list {
		if !r.Seen || p == nil || p.Allows(r.Colo) {
			out = append(out, r.S)
		}
	}
	return out
}

// hallBonusLocked — бонус к рейтингу стратегии из зала славы (вызывать под m.mu).
// Патч 25: сильнее тянем проверенные конфиги после обрывов/heal — меньше «угадываний» с нуля.
func (m *Memory) hallBonusLocked(net, id string) float64 {
	b := 0.0
	for _, r := range m.Hall[net] {
		if r.S.ID != id {
			continue
		}
		if !r.Seen {
			// реальное успешное подключение в этом ДЦ
			b = 0.75
			if r.N >= 3 {
				b = 0.95 // многократно подтверждался
			}
			return b
		}
		b = 0.25 // только «видели» ДЦ под политикой
	}
	return b
}

// HallSummary — короткая сводка для отчёта: «HEL:9 HKG:3 DME:1».
func (m *Memory) HallSummary(net string) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	cnt := map[string]int{}
	for _, r := range m.Hall[net] {
		cnt[r.Colo]++
	}
	keys := make([]string, 0, len(cnt))
	for k := range cnt {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return cnt[keys[i]] > cnt[keys[j]] || (cnt[keys[i]] == cnt[keys[j]] && keys[i] < keys[j]) })
	s := ""
	for _, k := range keys {
		s += fmt.Sprintf("%s:%d ", k, cnt[k])
	}
	return s
}

// ExportPriors собирает накопленный опыт в формате priors.json: для сотовых сетей по коду оператора,
// для всех Wi-Fi вместе («wifi:*»; отпечатки домашних сетей наружу не попадают). Ничего личного: только ID стратегий и дата-центры.
func (m *Memory) ExportPriors() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	type outRec struct {
		Seeds []string `json:"seeds"`
		Colos []string `json:"colos,omitempty"`
	}
	res := map[string]*outRec{}
	score := map[string]map[string]int{}
	colos := map[string]map[string]int{}
	add := func(key, id string, w int) {
		if score[key] == nil {
			score[key] = map[string]int{}
		}
		score[key][id] += w
	}
	for net, list := range m.Hall {
		key := net
		if len(net) > 5 && net[:5] == "wifi:" {
			key = "wifi:*"
		} else if len(net) < 5 || net[:5] != "cell:" {
			continue
		}
		for _, r := range list {
			if r.Seen {
				continue
			}
			add(key, r.S.ID, 3+r.N)
			if colos[key] == nil {
				colos[key] = map[string]int{}
			}
			colos[key][r.Colo] += r.N
		}
	}
	for net, sts := range m.Nets {
		key := net
		if len(net) > 5 && net[:5] == "wifi:" {
			key = "wifi:*"
		} else if len(net) < 5 || net[:5] != "cell:" {
			continue
		}
		for id, st := range sts {
			if st.OK >= 2 && st.Fail <= st.OK {
				add(key, id, st.OK)
			}
		}
	}
	top := func(mp map[string]int, n int) []string {
		keys := make([]string, 0, len(mp))
		for k := range mp {
			keys = append(keys, k)
		}
		sort.Slice(keys, func(i, j int) bool { return mp[keys[i]] > mp[keys[j]] || (mp[keys[i]] == mp[keys[j]] && keys[i] < keys[j]) })
		if len(keys) > n {
			keys = keys[:n]
		}
		return keys
	}
	for key, sc := range score {
		res[key] = &outRec{Seeds: top(sc, 25), Colos: top(colos[key], 3)}
	}
	b, err := json.MarshalIndent(res, "", "  ")
	if err != nil {
		return "{}"
	}
	return string(b)
}
