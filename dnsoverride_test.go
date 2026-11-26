package hydra

import (
	"encoding/binary"
	"net"
	"testing"
)

func buildDNSQueryPkt(name string, qtype uint16) []byte {
	dns := []byte{0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0}
	for _, l := range splitDotsT(name) {
		dns = append(dns, byte(len(l)))
		dns = append(dns, l...)
	}
	dns = append(dns, 0, byte(qtype>>8), byte(qtype), 0, 1)
	total := 20 + 8 + len(dns)
	p := make([]byte, total)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], uint16(total))
	p[8] = 64
	p[9] = 17
	copy(p[12:16], net.IPv4(172, 16, 0, 2).To4())
	copy(p[16:20], net.IPv4(1, 1, 1, 1).To4())
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))
	binary.BigEndian.PutUint16(p[20:], 40000)
	binary.BigEndian.PutUint16(p[22:], 53)
	binary.BigEndian.PutUint16(p[24:], uint16(8+len(dns)))
	copy(p[28:], dns)
	return p
}

func splitDotsT(s string) []string {
	var out []string
	cur := ""
	for _, c := range s {
		if c == '.' {
			out = append(out, cur)
			cur = ""
			continue
		}
		cur += string(c)
	}
	return append(out, cur)
}

func TestDNSOverride(t *testing.T) {
	if n := SetDNSOverrides("chatgpt.com=1.2.3.4,5.6.7.8\n*.supercell.com=9.9.9.9\n"); n != 2 {
		t.Fatalf("записей %d", n)
	}
	r := dnsOverrideReply(buildDNSQueryPkt("chatgpt.com", 1))
	if r == nil || ipChecksum(r[:20]) != 0 {
		t.Fatal("нет ответа или плохая сумма")
	}
	if binary.BigEndian.Uint16(r[28:]) != 0x1234 {
		t.Fatal("id не сохранён")
	}
	if got := binary.BigEndian.Uint16(r[28+6:]); got != 2 {
		t.Fatalf("ответов %d", got)
	}
	if dnsOverrideReply(buildDNSQueryPkt("example.com", 1)) != nil {
		t.Fatal("чужое имя не должно подменяться")
	}
	if dnsOverrideReply(buildDNSQueryPkt("id.supercell.com", 1)) == nil {
		t.Fatal("поддомен должен подменяться")
	}
	if r := dnsOverrideReply(buildDNSQueryPkt("chatgpt.com", 28)); r == nil || binary.BigEndian.Uint16(r[28+6:]) != 0 {
		t.Fatal("AAAA должен получить пустой ответ")
	}
	SetDNSOverrides("")
	if dnsOverrideReply(buildDNSQueryPkt("chatgpt.com", 1)) != nil {
		t.Fatal("после очистки подмены быть не должно")
	}
}

func TestDoTReset(t *testing.T) {
	SetDNSOverrides("chatgpt.com=1.2.3.4\n")
	syn := make([]byte, 40)
	syn[0] = 0x45
	binary.BigEndian.PutUint16(syn[2:], 40)
	syn[8] = 64
	syn[9] = 6
	copy(syn[12:16], net.IPv4(172, 16, 0, 2).To4())
	copy(syn[16:20], net.IPv4(1, 1, 1, 1).To4())
	binary.BigEndian.PutUint16(syn[20:], 50000)
	binary.BigEndian.PutUint16(syn[22:], 853)
	binary.BigEndian.PutUint32(syn[24:], 1000)
	syn[32] = 5 << 4
	syn[33] = 0x02
	r := dotResetReply(syn)
	if r == nil || ipChecksum(r[:20]) != 0 || r[33] != 0x14 || binary.BigEndian.Uint32(r[28:]) != 1001 {
		t.Fatal("RST на DoT собран неверно")
	}
	syn[22], syn[23] = 0, 80
	if dotResetReply(syn) != nil {
		t.Fatal("чужие порты не трогаем")
	}
	SetDNSOverrides("")
}
