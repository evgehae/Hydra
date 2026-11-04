package hydra

import "testing"

func TestMasqueStrategies(t *testing.T) {
	acc := &Account{EndpointV4: "162.159.198.3:0"}
	ss := MasqueStrategies(acc)
	if len(ss) < 60 {
		t.Fatalf("мало стратегий: %d", len(ss))
	}
	first := ss[0]
	if first.ID != "h3/162.159.198.2/vk5x6" || first.Params["fake"] != "vk.com" ||
		first.Params["fttl"] != "5" || first.Params["fcount"] != "6" {
		t.Fatalf("первой должна идти проверенная «VK ttl=5 ×6»: %+v", first)
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
