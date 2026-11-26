package hydra

import (
	"testing"
	"time"
)

func TestHallKeepsConfigsPerColo(t *testing.T) {
	m := &Memory{Nets: map[string]map[string]*stat{}}
	for i := 0; i < 20; i++ {
		s := Strategy{ID: "wg/1.1.1." + itoa(i) + ":2408/q3"}
		m.NoteHall("cell:1", s, "hkg", 100*time.Millisecond, false)
	}
	n := 0
	for _, r := range m.Hall["cell:1"] {
		if r.Colo == "HKG" {
			n++
		}
	}
	if n != hallPerColo {
		t.Fatalf("на дата-центр должно остаться %d, а осталось %d", hallPerColo, n)
	}
	// конфиг, попавший в запрещённый дата-центр, возвращается в пул только когда дата-центр разрешён
	m.NoteHall("cell:1", Strategy{ID: "h3/9.9.9.9/g3"}, "FRA", 0, true)
	p := &ColoPolicy{Block: []string{"FRA"}}
	for _, s := range m.RestoreHall("cell:1", p) {
		if s.ID == "h3/9.9.9.9/g3" {
			t.Fatal("конфиг запрещённого дата-центра не должен возвращаться в пул")
		}
	}
	found := false
	for _, s := range m.RestoreHall("cell:1", DefaultColoPolicy()) {
		if s.ID == "h3/9.9.9.9/g3" {
			found = true
		}
	}
	if !found {
		t.Fatal("после разрешения дата-центра конфиг должен вернуться в пул")
	}
	if m.HallSummary("cell:1") == "" {
		t.Fatal("сводка пустая")
	}
}
