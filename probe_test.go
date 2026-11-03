package hydra

import (
	"encoding/binary"
	"net"
	"testing"
)

// buildColoReply — «сервер» для тестов: отвечает на пробу кодом дата-центра.
func buildColoReply(probe []byte, colo string) []byte {
	ihl := int(probe[0]&0x0f) * 4
	srcIP := probe[12:16]
	udp := probe[ihl:]
	sport := binary.BigEndian.Uint16(udp[0:])
	q := udp[8:]
	id := binary.BigEndian.Uint16(q[0:])

	dns := []byte{byte(id >> 8), byte(id), 0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0}
	dns = append(dns, q[12:]...) // вопрос как есть
	dns = append(dns, 0xC0, 0x0C, 0, 16, 0, 3, 0, 0, 0, 0, 0, byte(len(colo)+1), byte(len(colo)))
	dns = append(dns, colo...)

	total := 20 + 8 + len(dns)
	p := make([]byte, total)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], uint16(total))
	p[8] = 64
	p[9] = 17
	copy(p[12:16], probeDst)
	copy(p[16:20], srcIP)
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))
	binary.BigEndian.PutUint16(p[20:], 53)
	binary.BigEndian.PutUint16(p[22:], sport)
	binary.BigEndian.PutUint16(p[24:], uint16(8+len(dns)))
	copy(p[28:], dns)
	return p
}

func TestProbeRoundTrip(t *testing.T) {
	probe := BuildColoProbe(net.ParseIP("172.16.0.2"), 40000, 7)
	if probe == nil || len(probe) < 40 {
		t.Fatal("проба не построена")
	}
	if ipChecksum(probe[:20]) != 0 {
		t.Fatal("контрольная сумма IP неверна")
	}
	reply := buildColoReply(probe, "HEL")
	id, colo, ok := ParseColoReply(reply, 40000)
	if !ok || id != 7 || colo != "HEL" {
		t.Fatalf("разбор ответа: %v %q %v", id, colo, ok)
	}
	if _, _, ok := ParseColoReply(reply, 40001); ok {
		t.Fatal("ответ на чужой порт должен игнорироваться")
	}
	if _, _, ok := ParseColoReply(probe, 40000); ok {
		t.Fatal("сам запрос не должен приниматься за ответ")
	}
	if BuildColoProbe(net.ParseIP("2001:db8::1"), 1, 1) != nil {
		t.Fatal("для IPv6-адреса пробы нет")
	}
}

func TestNormProbeColo(t *testing.T) {
	for in, want := range map[string]string{"HEL": "HEL", `"ams"`: "AMS", "fra1": "FRA", "DME": "DME"} {
		if got := normProbeColo(in); got != want {
			t.Fatalf("%q -> %q, ждали %q", in, got, want)
		}
	}
}
