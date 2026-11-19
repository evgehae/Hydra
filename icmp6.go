package hydra

import "encoding/binary"

// buildICMPv6Unreach строит ответ «адресат недостижим» на исходящий IPv6-пакет. Когда IPv6 через туннель
// выключен, приложение получает отказ мгновенно и сразу идёт по IPv4, а не ждёт таймаута.
func buildICMPv6Unreach(orig []byte) []byte {
	if len(orig) < 40 || orig[0]>>4 != 6 {
		return nil
	}
	inv := orig
	if len(inv) > 1232 {
		inv = inv[:1232]
	}
	plen := 8 + len(inv)
	p := make([]byte, 40+plen)
	p[0] = 0x60
	binary.BigEndian.PutUint16(p[4:], uint16(plen))
	p[6] = 58 // ICMPv6
	p[7] = 64
	copy(p[8:24], orig[24:40])  // отправитель ответа — прежний адресат
	copy(p[24:40], orig[8:24])  // получатель ответа — прежний отправитель
	p[40], p[41] = 1, 0         // destination unreachable, no route
	copy(p[48:], inv)
	var sum uint32
	add := func(b []byte) {
		for i := 0; i+1 < len(b); i += 2 {
			sum += uint32(b[i])<<8 | uint32(b[i+1])
		}
		if len(b)%2 == 1 {
			sum += uint32(b[len(b)-1]) << 8
		}
	}
	add(p[8:24])
	add(p[24:40])
	sum += uint32(plen) + 58
	add(p[40:])
	for sum>>16 != 0 {
		sum = (sum & 0xffff) + (sum >> 16)
	}
	binary.BigEndian.PutUint16(p[42:], ^uint16(sum))
	return p
}
