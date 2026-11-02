package hydra

import (
	"context"
	"strings"
	"testing"
)

type coloTunnel struct {
	*fakeTunnel
	colo string
}

func (c *coloTunnel) Colo(context.Context) (string, error) { return c.colo, nil }

func coloTransport(colos map[string]string, order ...string) *fakeTransport {
	var ss []Strategy
	for _, id := range order {
		ss = append(ss, Strategy{ID: id, Transport: "fake"})
	}
	return &fakeTransport{
		strategies: ss,
		dial: func(ctx context.Context, s Strategy) (Tunnel, error) {
			return &coloTunnel{newFakeTunnel(0), colos[s.ID]}, nil
		},
	}
}

func TestColoPolicy(t *testing.T) {
	p := DefaultColoPolicy()
	for _, c := range []string{"DME", "dme", " LED "} {
		if p.Allows(c) {
			t.Fatalf("%q должен быть запрещён", c)
		}
	}
	for _, c := range []string{"HEL", "FRA", "AMS", "ARN", ""} {
		if !p.Allows(c) {
			t.Fatalf("%q должен быть разрешён", c)
		}
	}
	onlyEU := &ColoPolicy{Allow: []string{"hel", "fra"}}
	if !onlyEU.Allows("HEL") || onlyEU.Allows("AMS") {
		t.Fatal("Allow-список работает неверно")
	}
	var nilp *ColoPolicy
	if !nilp.Allows("DME") {
		t.Fatal("nil-политика ничего не блокирует")
	}
}

func TestParseColoList(t *testing.T) {
	got := strings.Join(ParseColoList("dme, LED;fra  dme"), ",")
	if got != "DME,LED,FRA" {
		t.Fatalf("получили %q", got)
	}
}

func TestParseTrace(t *testing.T) {
	m := ParseTrace("fl=1\nip=1.2.3.4\ncolo=HEL\nwarp=on\n")
	if m["colo"] != "HEL" || m["warp"] != "on" || m["ip"] != "1.2.3.4" {
		t.Fatalf("разбор trace: %v", m)
	}
}

func TestRaceSkipsBlockedColo(t *testing.T) {
	ft := coloTransport(map[string]string{"dme": "DME", "hel": "HEL"}, "dme", "hel")
	mem, _ := LoadMemory("")
	o := New(fastCfg(), mem, []Transport{ft}, nil)
	tun, s, err := o.race(context.Background(), "wifi:home", "")
	if err != nil || s.ID != "hel" {
		t.Fatalf("ждали hel, получили %q %v", s.ID, err)
	}
	tun.Close()
}

func TestRaceAllBlocked(t *testing.T) {
	ft := coloTransport(map[string]string{"a": "DME", "b": "LED"}, "a", "b")
	mem, _ := LoadMemory("")
	o := New(fastCfg(), mem, []Transport{ft}, nil)
	_, _, err := o.race(context.Background(), "wifi:home", "")
	if err == nil || !strings.Contains(err.Error(), "DME") {
		t.Fatalf("ждали ошибку про запрещённые дата-центры, получили %v", err)
	}
}
