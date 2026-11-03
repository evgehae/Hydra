package hydra

import "testing"

func TestMasqueStrategies(t *testing.T) {
	acc := &Account{EndpointV4: "162.159.198.3:0"}
	ss := MasqueStrategies(acc)
	if len(ss) < 20 {
		t.Fatalf("мало стратегий: %d", len(ss))
	}
	if ss[0].Params["endpoint"] != "162.159.198.3:443" || ss[0].Params["h2"] != "0" {
		t.Fatalf("первой должна идти стратегия с адресом из аккаунта по HTTP/3: %+v", ss[0])
	}
	ids := map[string]bool{}
	sawH2 := false
	for _, s := range ss {
		if ids[s.ID] {
			t.Fatalf("повтор ID %s", s.ID)
		}
		ids[s.ID] = true
		if s.Params["h2"] == "1" {
			sawH2 = true
		}
	}
	if !sawH2 {
		t.Fatal("нет запасных стратегий по HTTP/2")
	}
}
