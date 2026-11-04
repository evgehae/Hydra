package hydra

import (
	"encoding/binary"
	"net"
	"strings"
)

// Проба дата-центра без всякого TCP/IP-стека: сами строим UDP-пакет с DNS-запросом
// «CHAOS TXT id.server» к 1.1.1.1. Резолвер Cloudflare отвечает кодом дата-центра
// (HEL, FRA, DME...). Пакет уходит в туннель, ответ приходит из туннеля — так мы
// заодно измеряем задержку и проверяем, что туннель вообще живой.

var probeDst = net.IPv4(1, 1, 1, 1).To4()

func ipChecksum(h []byte) uint16 {
	var sum uint32
	for i := 0; i+1 < len(h); i += 2 {
		sum += uint32(h[i])<<8 | uint32(h[i+1])
	}
	for sum>>16 != 0 {
		sum = sum&0xffff + sum>>16
	}
	return ^uint16(sum)
}

// BuildColoProbe строит IPv4-пакет с запросом id.server. nil, если src не IPv4.
func BuildColoProbe(src net.IP, srcPort, id uint16) []byte {
	s4 := src.To4()
	if s4 == nil {
		return nil
	}
	dns := []byte{byte(id >> 8), byte(id), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0}
	dns = append(dns, 2, 'i', 'd', 6, 's', 'e', 'r', 'v', 'e', 'r', 0, 0, 16, 0, 3) // TXT, класс CH
	total := 20 + 8 + len(dns)
	p := make([]byte, total)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], uint16(total))
	binary.BigEndian.PutUint16(p[4:], id)
	binary.BigEndian.PutUint16(p[6:], 0x4000) // DF
	p[8] = 64
	p[9] = 17
	copy(p[12:16], s4)
	copy(p[16:20], probeDst)
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))
	binary.BigEndian.PutUint16(p[20:], srcPort)
	binary.BigEndian.PutUint16(p[22:], 53)
	binary.BigEndian.PutUint16(p[24:], uint16(8+len(dns)))
	// контрольная сумма UDP = 0: для IPv4 это допустимо
	copy(p[28:], dns)
	return p
}

func skipName(b []byte, off int) int {
	for off < len(b) {
		c := int(b[off])
		switch {
		case c == 0:
			return off + 1
		case c&0xC0 == 0xC0:
			return off + 2
		default:
			off += c + 1
		}
	}
	return -1
}

// normProbeColo: из ответа берём код аэропорта (первые три буквы, заглавными).
func normProbeColo(s string) string {
	s = strings.ToUpper(strings.Trim(strings.TrimSpace(s), `"`))
	if len(s) > 3 {
		ok := true
		for _, r := range s[:3] {
			if r < 'A' || r > 'Z' {
				ok = false
			}
		}
		if ok {
			return s[:3]
		}
	}
	return s
}

// ParseColoReply разбирает ответ на пробу, пришедший на порт dstPort.
func ParseColoReply(pkt []byte, dstPort uint16) (id uint16, colo string, ok bool) {
	if len(pkt) < 28 || pkt[0]>>4 != 4 {
		return
	}
	ihl := int(pkt[0]&0x0f) * 4
	if ihl < 20 || len(pkt) < ihl+8+12 || pkt[9] != 17 {
		return
	}
	if !net.IP(pkt[12:16]).Equal(probeDst) {
		return
	}
	udp := pkt[ihl:]
	if binary.BigEndian.Uint16(udp[0:]) != 53 || binary.BigEndian.Uint16(udp[2:]) != dstPort {
		return
	}
	dns := udp[8:]
	if ulen := int(binary.BigEndian.Uint16(udp[4:])); ulen >= 8 && ulen-8 <= len(dns) {
		dns = dns[:ulen-8]
	}
	if len(dns) < 12 || dns[2]&0x80 == 0 || dns[3]&0x0f != 0 {
		return
	}
	id = binary.BigEndian.Uint16(dns[0:])
	qd := int(binary.BigEndian.Uint16(dns[4:]))
	an := int(binary.BigEndian.Uint16(dns[6:]))
	if an < 1 {
		return
	}
	off := 12
	for i := 0; i < qd; i++ {
		off = skipName(dns, off)
		if off < 0 || off+4 > len(dns) {
			return
		}
		off += 4
	}
	off = skipName(dns, off)
	if off < 0 || off+10 > len(dns) {
		return
	}
	typ := binary.BigEndian.Uint16(dns[off:])
	rdlen := int(binary.BigEndian.Uint16(dns[off+8:]))
	off += 10
	if typ != 16 || rdlen < 1 || off+rdlen > len(dns) {
		return
	}
	n := int(dns[off])
	if n+1 > rdlen {
		return
	}
	colo = normProbeColo(string(dns[off+1 : off+1+n]))
	return id, colo, colo != ""
}

// ---------- TCP-проба: проходит ли через туннель настоящий TCP ----------
// Шлём SYN на 1.1.1.1:443 и ждём SYN-ACK: так мы убеждаемся, что туннель не
// просто «подключён», а реально пропускает TCP (а на нём — весь интернет).

func tcpChecksum(src, dst net.IP, seg []byte) uint16 {
	pseudo := make([]byte, 0, 12+len(seg))
	pseudo = append(pseudo, src.To4()...)
	pseudo = append(pseudo, dst.To4()...)
	pseudo = append(pseudo, 0, 6, byte(len(seg)>>8), byte(len(seg)))
	pseudo = append(pseudo, seg...)
	if len(pseudo)%2 == 1 {
		pseudo = append(pseudo, 0)
	}
	var sum uint32
	for i := 0; i+1 < len(pseudo); i += 2 {
		sum += uint32(pseudo[i])<<8 | uint32(pseudo[i+1])
	}
	for sum>>16 != 0 {
		sum = sum&0xffff + sum>>16
	}
	return ^uint16(sum)
}

func buildTCP(src net.IP, sport uint16, seq, ack uint32, flags byte, id uint16, withMSS bool) []byte {
	s4 := src.To4()
	if s4 == nil {
		return nil
	}
	tcpLen := 20
	if withMSS {
		tcpLen = 24
	}
	total := 20 + tcpLen
	p := make([]byte, total)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], uint16(total))
	binary.BigEndian.PutUint16(p[4:], id)
	binary.BigEndian.PutUint16(p[6:], 0x4000)
	p[8] = 64
	p[9] = 6
	copy(p[12:16], s4)
	copy(p[16:20], probeDst)
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))

	t := p[20:]
	binary.BigEndian.PutUint16(t[0:], sport)
	binary.BigEndian.PutUint16(t[2:], 443)
	binary.BigEndian.PutUint32(t[4:], seq)
	binary.BigEndian.PutUint32(t[8:], ack)
	t[12] = byte(tcpLen/4) << 4
	t[13] = flags
	binary.BigEndian.PutUint16(t[14:], 65535)
	if withMSS {
		t[20], t[21], t[22], t[23] = 2, 4, 0x04, 0xD8 // MSS 1240
	}
	binary.BigEndian.PutUint16(t[16:], tcpChecksum(s4, probeDst, t))
	return p
}

// BuildTCPSyn строит SYN к 1.1.1.1:443.
func BuildTCPSyn(src net.IP, sport uint16, seq uint32, id uint16) []byte {
	return buildTCP(src, sport, seq, 0, 0x02, id, true)
}

// BuildTCPRst строит RST — закрыть «полуоткрытое» соединение после пробы.
func BuildTCPRst(src net.IP, sport uint16, seq uint32, id uint16) []byte {
	return buildTCP(src, sport, seq, 0, 0x04, id, false)
}

// ParseTCPSynAck: это SYN-ACK от 1.1.1.1:443 на наш порт с ожидаемым ack?
func ParseTCPSynAck(pkt []byte, dport uint16, wantAck uint32) bool {
	if len(pkt) < 40 || pkt[0]>>4 != 4 || pkt[9] != 6 {
		return false
	}
	ihl := int(pkt[0]&0x0f) * 4
	if ihl < 20 || len(pkt) < ihl+20 || !net.IP(pkt[12:16]).Equal(probeDst) {
		return false
	}
	t := pkt[ihl:]
	if binary.BigEndian.Uint16(t[0:]) != 443 || binary.BigEndian.Uint16(t[2:]) != dport {
		return false
	}
	if t[13]&0x12 != 0x12 { // SYN+ACK
		return false
	}
	return binary.BigEndian.Uint32(t[8:]) == wantAck
}
