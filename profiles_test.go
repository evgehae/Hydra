package hydra

import (
	"strings"
	"testing"
	"time"
)

func TestFlowLifeMedianAndForget(t *testing.T) {
	m := &Memory{}
	if m.FlowTTL("cell:1") != 0 {
		t.Fatal("без замеров TTL должен быть 0")
	}
	m.RecordFlowLife("cell:1", 10*time.Second)  // слишком коротко: не замер
	m.RecordFlowLife("cell:1", 30*time.Second) // <45 с — тоже не замер (патч 24)
	for _, s := range []int{100, 200, 300} {
		m.RecordFlowLife("cell:1", time.Duration(s)*time.Second)
	}
	if got := m.FlowTTL("cell:1"); got != 200*time.Second {
		t.Fatalf("медиана: %v", got)
	}
	// ротационный TTL не короче 10 мин
	if got := m.FlowTTLRotate("cell:1"); got < 10*time.Minute {
		t.Fatalf("FlowTTLRotate floor: %v", got)
	}
	m.ForgetNet("cell:1")
	if m.FlowTTL("cell:1") != 0 {
		t.Fatal("после ForgetNet замеров быть не должно")
	}
	// без замеров Rotate всё равно даёт пол
	if got := m.FlowTTLRotate("cell:2"); got != 10*time.Minute {
		t.Fatalf("пустая сеть Rotate floor: %v", got)
	}
}

func TestSlowNetAndFloor(t *testing.T) {
	m := &Memory{Nets: map[string]map[string]*stat{"n": {"a": {OK: 2, EWMAms: 520}}}}
	if !m.SlowNet("n") {
		t.Fatal("520 мс — медленная сеть")
	}
	m.Nets["n"]["b"] = &stat{OK: 1, EWMAms: 120}
	if m.SlowNet("n") {
		t.Fatal("есть быстрый путь — сеть не медленная")
	}
}

func TestRemotePriorsAndVerdict(t *testing.T) {
	if err := SetRemotePriors([]byte(`{"cell:9":{"seeds":["wg/1.1.1.1:2408/s3"],"floor_ms":4000,"genes":{"wg.sig=h3":[2,0]}}}`)); err != nil {
		t.Fatal(err)
	}
	defer SetRemotePriors([]byte(`{}`))
	if seedBonus("cell:9", "wg/1.1.1.1:2408/s3") == 0 {
		t.Fatal("seed из priors.json не подхвачен")
	}
	if profileFor("cell:9").UpFloor != 4*time.Second {
		t.Fatal("floor_ms не подхвачен")
	}
	if v, ok := geneSeed("cell:9", "wg.sig=h3"); !ok || v[0] != 2 {
		t.Fatal("ген не подхвачен")
	}
	m := &Memory{Nets: map[string]map[string]*stat{"n": {"wg/1.1.1.1:2408/s3": {OK: 3, EWMAms: 200}}}}
	if v := m.Verdict("n"); !strings.Contains(v, "STUN") {
		t.Fatalf("вердикт: %s", v)
	}
}

func TestSbBackoff(t *testing.T) {
	cases := map[int]time.Duration{0: 0, 2: 0, 3: 2 * time.Minute, 6: 10 * time.Minute, 10: 30 * time.Minute, 50: 30 * time.Minute}
	for n, want := range cases {
		if got := sbBackoff(n); got != want {
			t.Fatalf("sbBackoff(%d)=%v, ждали %v", n, got, want)
		}
	}
}
