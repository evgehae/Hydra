package hydra

import "testing"

func TestIPModeFilter(t *testing.T) {
	v4 := Strategy{ID: "h3/162.159.198.1/g3", Params: map[string]string{"endpoint": "162.159.198.1"}}
	v6 := Strategy{ID: "h3/[2606:4700:103::1]/g3", Params: map[string]string{"endpoint": "2606:4700:103::1"}}
	list := []Strategy{v4, v6}
	SetIPMode("v4")
	if got := ipModeFilter(list); len(got) != 1 || got[0].ID != v4.ID {
		t.Fatal("в режиме v4 должен остаться только IPv4")
	}
	SetIPMode("v6")
	if got := ipModeFilter(list); len(got) != 1 || got[0].ID != v6.ID {
		t.Fatal("в режиме v6 должен остаться только IPv6")
	}
	if got := ipModeFilter([]Strategy{v4}); len(got) != 1 {
		t.Fatal("если IPv6-путей нет, откатываемся на IPv4, а не остаёмся без VPN")
	}
	SetIPMode("both")
	if len(ipModeFilter(list)) != 2 || ipModeBonus(v6) <= ipModeBonus(v4) {
		t.Fatal("в режиме both нужны оба семейства, IPv6 первым")
	}
	SetIPMode("auto")
}
