package hydra

import "testing"

func TestMasqueStrategies(t *testing.T) {
	acc := &Account{EndpointV4: "162.159.198.3:0"}
	ss := MasqueStrategies(acc)
	if len(ss) < 30 {
		t.Fatalf("мало стратегий: %d", len(ss))
	}
	first := ss[0]
	if first.ID != "h3/162.159.198.2/g3" || first.Params["fake"] != "www.google.com" ||
		first.Params["fcount"] != "3" || first.Params["fsize"] != "1200" {
		t.Fatalf("первой должна идти основная стратегия Zarp «google ×3»: %+v", first)
	}
	sawPort500 := false
	for _, s := range ss {
		if s.Params["endpoint"] == "162.159.198.2:500" {
			sawPort500 = true
		}
	}
	if !sawPort500 {
		t.Fatal("нет стратегий с портом 500")
	}
	if ss[1].Params["endpoint"] != "162.159.198.3:443" {
		t.Fatalf("вторым должен идти адрес из аккаунта: %+v", ss[1])
	}
	ids := map[string]bool{}
	sawH2, sawPlain, sawV6 := false, false, false
	for _, s := range ss {
		if ids[s.ID] {
			t.Fatalf("повтор ID %s", s.ID)
		}
		ids[s.ID] = true
		if s.Params["h2"] == "1" {
			sawH2 = true
		}
		if s.Params["fake"] == "" && s.Params["h2"] == "0" {
			sawPlain = true
		}
		if hostOnly(s.Params["endpoint"]) == "2606:4700:103::2" {
			sawV6 = true
		}
	}
	if !sawH2 || !sawPlain || !sawV6 {
		t.Fatalf("не хватает видов стратегий: h2=%v plain=%v v6=%v", sawH2, sawPlain, sawV6)
	}
}
