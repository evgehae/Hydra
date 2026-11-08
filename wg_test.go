package hydra

import (
	"encoding/base64"
	"strings"
	"testing"
)

func testKey(b byte) string {
	k := make([]byte, 32)
	for i := range k {
		k[i] = b
	}
	return base64.StdEncoding.EncodeToString(k)
}

func TestWGConfigRoundTrip(t *testing.T) {
	a := &Account{Kind: "wg", PrivateKey: testKey(1), PeerPublicKey: testKey(2), EndpointV4: "162.159.192.1:2408",
		AddrV4: "172.16.0.2", AddrV6: "2606:4700:110:8a1c::2", Jc: 4, Jmin: 40, Jmax: 70}
	txt := a.WGConfig()
	for _, want := range []string{"[Interface]", "PrivateKey = " + a.PrivateKey, "172.16.0.2/32", "Jc = 4", "Endpoint = 162.159.192.1:2408"} {
		if !strings.Contains(txt, want) {
			t.Fatalf("в .conf нет %q:\n%s", want, txt)
		}
	}
	b, err := ParseWGConfig(txt)
	if err != nil {
		t.Fatal(err)
	}
	if b.PrivateKey != a.PrivateKey || b.PeerPublicKey != a.PeerPublicKey || b.EndpointV4 != a.EndpointV4 ||
		b.AddrV4 != "172.16.0.2" || b.AddrV6 != "2606:4700:110:8a1c::2" || b.Jc != 4 || b.Jmax != 70 || !b.Custom {
		t.Fatalf("после разбора: %+v", b)
	}
}

func TestParseWGConfigRejectsBadInput(t *testing.T) {
	good := "[Interface]\nPrivateKey = " + testKey(1) + "\nAddress = 172.16.0.2/32\n[Peer]\nPublicKey = " + testKey(2) + "\nEndpoint = 1.2.3.4:51820\n"
	if _, err := ParseWGConfig(good); err != nil {
		t.Fatalf("корректный конфиг отвергнут: %v", err)
	}
	if _, err := ParseWGConfig(strings.Replace(good, "Endpoint = 1.2.3.4:51820", "Endpoint = nowhere", 1)); err == nil {
		t.Fatal("плохой Endpoint должен отвергаться")
	}
	if _, err := ParseWGConfig(strings.Replace(good, "[Peer]", "S1 = 15\n[Peer]", 1)); err == nil {
		t.Fatal("S1 != 0 (изменённый формат пакетов) должен отвергаться")
	}
	if _, err := ParseWGConfig(strings.Replace(good, "[Peer]", "H1 = 1\nH2 = 2\nH3 = 3\nH4 = 4\nJc = 3\nJmin = 20\nJmax = 40\n[Peer]", 1)); err != nil {
		t.Fatalf("стандартные H1–H4 и Jc/Jmin/Jmax должны приниматься: %v", err)
	}
	if _, err := ParseWGConfig("мусор"); err == nil {
		t.Fatal("мусор должен отвергаться")
	}
}

func TestWGUAPIAndJunk(t *testing.T) {
	a := &Account{PrivateKey: testKey(1), PeerPublicKey: testKey(2)}
	u, err := WGUAPI(a, "127.0.0.1:5555")
	if err != nil || !strings.Contains(u, "endpoint=127.0.0.1:5555") || !strings.Contains(u, strings.Repeat("01", 32)) {
		t.Fatalf("UAPI: %q %v", u, err)
	}
	j := GenJunk(4, 40, 70)
	if len(j) != 4 {
		t.Fatalf("нужно 4 пакета, получили %d", len(j))
	}
	for _, p := range j {
		if len(p) < 40 || len(p) > 70 || (p[0] >= 1 && p[0] <= 4) {
			t.Fatalf("плохой «мусорный» пакет: %d байт, первый байт %d", len(p), p[0])
		}
	}
	if !IsWGInit(append([]byte{1, 0, 0, 0}, make([]byte, 144)...)) || IsWGInit(make([]byte, 148)) {
		t.Fatal("IsWGInit определяет рукопожатие неверно")
	}
}

func TestWGStrategies(t *testing.T) {
	a := &Account{Kind: "wg", EndpointV4: "162.159.192.1:2408"}
	ss := WGStrategies(a)
	if len(ss) < 30 || ss[0].Params["sig"] != "quic" || ss[0].Params["jc"] != "3" || ss[0].Transport != "wg" {
		t.Fatalf("стратегии: %d, первая %+v", len(ss), ss[0])
	}
	saw188, saw8 := false, false
	for _, s := range ss {
		h := hostOnly(s.Params["endpoint"])
		if strings.HasPrefix(h, "188.114.") {
			saw188 = true
		}
		if strings.HasPrefix(h, "8.34.") || strings.HasPrefix(h, "8.39.") {
			saw8 = true
		}
	}
	if !saw188 || !saw8 {
		t.Fatalf("не хватает подсетей: 188.114=%v 8.x=%v", saw188, saw8)
	}
	own := &Account{Kind: "wg", Custom: true, EndpointV4: "vpn.example.com:51820"}
	os := WGStrategies(own)
	if len(os) != 2 || os[0].Params["endpoint"] != "vpn.example.com:51820" {
		t.Fatalf("свой конфиг: %+v", os)
	}
}

func TestWGPrefixLooksLikeVarvara(t *testing.T) {
	q := BuildQUICLike()
	if len(q) != 108 || q[0] != 0xC0 || q[4] != 1 || q[5] != 8 || q[16] != 0x40 || q[17] != 90 {
		t.Fatalf("QUIC-подобный пакет: %x", q[:20])
	}
	pre := WGPrefix("quic", 3, 41, 78)
	if len(pre) != 1+4+3 || len(pre[0]) != 108 {
		t.Fatalf("пролог: %d пакетов, первый %d байт", len(pre), len(pre[0]))
	}
	if len(WGPrefix("", 0, 0, 0)) != 0 {
		t.Fatal("без сигнатуры и мусора пролога быть не должно")
	}
	st := BuildSTUNLike()
	if len(st) != 20 || st[4] != 0x21 || st[7] != 0x42 {
		t.Fatalf("STUN-подобный пакет: %x", st)
	}
}

func TestInterleave(t *testing.T) {
	a := []Strategy{{ID: "a1"}, {ID: "a2"}, {ID: "a3"}, {ID: "a4"}}
	b := []Strategy{{ID: "b1"}, {ID: "b2"}}
	var ids []string
	for _, s := range Interleave(a, b, 2) {
		ids = append(ids, s.ID)
	}
	if strings.Join(ids, ",") != "a1,a2,b1,b2,a3,a4" {
		t.Fatalf("порядок: %v", ids)
	}
}
