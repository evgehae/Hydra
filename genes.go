package hydra

import (
	"fmt"
	"math/rand"
	"net"
	"sort"
	"strings"
)

// «Гены» стратегии — её параметры (SNI, порт, TTL фейков, keepalive и т. д.). Гидра считает, с какими
// значениями параметров в этой сети чаще удаётся подключиться, и при придумывании новых вариантов
// чаще выбирает удачные значения (но 1 раз из 4 пробует случайное, чтобы не застрять).

func geneKeys(s Strategy) []string {
	fam := poolFamily(s)
	var ks []string
	add := func(name, v string) {
		if v != "" {
			ks = append(ks, fam+"."+name+"="+v)
		}
	}
	add("sni", s.Params["sni"])
	add("fake", s.Params["fake"])
	add("ttl", s.Params["fttl"])
	add("cnt", s.Params["fcount"])
	add("size", s.Params["fsize"])
	add("keep", s.Params["keep"])
	add("noise", s.Params["noise"])
	add("jc", s.Params["jc"])
	if _, port, err := net.SplitHostPort(s.Params["endpoint"]); err == nil {
		add("port", port)
	}
	return ks
}

// RecordGenes запоминает, как сработали значения параметров этой стратегии.
func (m *Memory) RecordGenes(nk string, s Strategy, ok bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Genes == nil {
		m.Genes = map[string]*stat{}
	}
	for _, k := range geneKeys(s) {
		key := nk + "|" + k
		st := m.Genes[key]
		if st == nil {
			st = &stat{}
			m.Genes[key] = st
		}
		if ok {
			st.OK++
		} else {
			st.Fail++
		}
		if st.OK+st.Fail > 40 { // старое забываем
			st.OK /= 2
			st.Fail /= 2
		}
	}
	m.saveSoonLocked()
}

// PickGene выбирает значение параметра: чаще те, что в этой сети срабатывали лучше.
func (m *Memory) PickGene(nk, key string, opts []string, rnd *rand.Rand) string {
	if len(opts) == 0 {
		return ""
	}
	if rnd.Intn(100) < 25 {
		return opts[rnd.Intn(len(opts))]
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	w := make([]float64, len(opts))
	sum := 0.0
	for i, o := range opts {
		ok, fail := 0, 0
		if st := m.Genes[nk+"|"+key+"="+o]; st != nil {
			ok, fail = st.OK, st.Fail
		}
		if sd, has := geneSeeds[nk][key+"="+o]; has { // начальная подсказка по оператору
			ok += sd[0]
			fail += sd[1]
		}
		r := (float64(ok) + 1) / (float64(ok+fail) + 2)
		w[i] = r*r + 0.05
		sum += w[i]
	}
	x := rnd.Float64() * sum
	for i := range opts {
		x -= w[i]
		if x <= 0 {
			return opts[i]
		}
	}
	return opts[len(opts)-1]
}

// NoteReason считает причины сбоев по семействам стратегий.
func (m *Memory) NoteReason(nk, fam, class string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Why == nil {
		m.Why = map[string]int{}
	}
	m.Why[nk+"|"+fam+"|"+class]++
	m.saveSoonLocked()
}

// Reasons — сводка причин сбоев в этой сети (для отчёта).
func (m *Memory) Reasons(nk string) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	type kv struct {
		k string
		n int
	}
	var rows []kv
	for k, n := range m.Why {
		if strings.HasPrefix(k, nk+"|") {
			rows = append(rows, kv{strings.TrimPrefix(k, nk+"|"), n})
		}
	}
	if len(rows) == 0 {
		return ""
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].n > rows[j].n })
	out := "причины сбоев в этой сети (семейство|причина):\n"
	for i, r := range rows {
		if i >= 10 {
			break
		}
		out += fmt.Sprintf("  %s ×%d\n", strings.Replace(r.k, "|", ": ", 1), r.n)
	}
	return out
}

// classifyFail приводит текст причины к короткому классу.
func classifyFail(msg string) string {
	switch {
	case strings.Contains(msg, "рукопожатие могло пройти"):
		return "рукопожатие есть, данных нет"
	case strings.Contains(msg, "ни одного пакета"):
		return "ничего не пришло из туннеля"
	case strings.Contains(msg, "TCP — нет"):
		return "UDP идёт, TCP нет"
	case strings.Contains(msg, "пакеты из туннеля приходят"):
		return "туннель принят, трафик не идёт"
	case strings.Contains(msg, "запрещён"):
		return "запрещённый дата-центр"
	case strings.Contains(msg, "клиент остановился"), strings.Contains(msg, "нет маршрута"):
		return "ошибка клиента"
	}
	return "прочее"
}
