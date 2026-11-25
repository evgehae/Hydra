package hydra

import (
	"encoding/binary"
	"net"
	"strings"
	"sync/atomic"
)

// Подмена DNS-ответов внутри ядра.
//
// Зачем: «умные» DNS для ИИ и игр отвечают по-разному на разные домены, а часть серверов вообще
// доступна только по DoH (их нельзя прописать в Android как обычный DNS). Приложение Гидры само
// спрашивает нужный сервер (по UDP, DoH или DoT), собирает карту «домен → адреса» и передаёт её сюда.
// Ядро видит DNS-запрос приложения в TUN и отвечает из карты; всё остальное идёт в туннель как раньше.
// IPv6-запросы (AAAA) к именам из карты получают пустой ответ, чтобы приложение сразу пошло по IPv4.

type dnsOvMap struct {
	exact  map[string][]net.IP
	suffix map[string][]net.IP
}

var dnsOv atomic.Value // *dnsOvMap

// SetDNSOverrides принимает карту строками «домен=ip1,ip2». Домен «*.x.com» покрывает x.com и все его
// поддомены. Пустая строка отключает подмену. Возвращает число записей.
func SetDNSOverrides(text string) int {
	m := &dnsOvMap{exact: map[string][]net.IP{}, suffix: map[string][]net.IP{}}
	n := 0
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq := strings.IndexByte(line, '=')
		if eq <= 0 {
			continue
		}
		name := strings.ToLower(strings.TrimSuffix(strings.TrimSpace(line[:eq]), "."))
		var ips []net.IP
		for _, s := range strings.Split(line[eq+1:], ",") {
			if ip := net.ParseIP(strings.TrimSpace(s)); ip != nil && ip.To4() != nil {
				ips = append(ips, ip.To4())
			}
		}
		if name == "" || len(ips) == 0 {
			continue
		}
		if strings.HasPrefix(name, "*.") {
			m.suffix[name[2:]] = ips
		} else {
			m.exact[name] = ips
		}
		n++
	}
	dnsOv.Store(m)
	return n
}

func (m *dnsOvMap) lookup(name string) []net.IP {
	if ips, ok := m.exact[name]; ok {
		return ips
	}
	for n := name; n != ""; {
		if ips, ok := m.suffix[n]; ok {
			return ips
		}
		i := strings.IndexByte(n, '.')
		if i < 0 {
			break
		}
		n = n[i+1:]
	}
	return nil
}

func dnsReadName(dns []byte, off int) (string, int, bool) {
	var sb strings.Builder
	for {
		if off >= len(dns) {
			return "", 0, false
		}
		l := int(dns[off])
		off++
		if l == 0 {
			break
		}
		if l&0xC0 != 0 || off+l > len(dns) { // в вопросе сжатие не бывает
			return "", 0, false
		}
		if sb.Len() > 0 {
			sb.WriteByte('.')
		}
		sb.Write(dns[off : off+l])
		off += l
	}
	return strings.ToLower(sb.String()), off, true
}

// dnsOverrideReply: если pkt — IPv4/UDP-запрос DNS к имени из карты, возвращает готовый IP-пакет с ответом, иначе nil.
func dnsOverrideReply(pkt []byte) []byte {
	m, _ := dnsOv.Load().(*dnsOvMap)
	if m == nil || len(m.exact)+len(m.suffix) == 0 {
		return nil
	}
	if len(pkt) < 20+8+12 || pkt[0]>>4 != 4 || pkt[9] != 17 {
		return nil
	}
	ihl := int(pkt[0]&0x0f) * 4
	if ihl < 20 || len(pkt) < ihl+8+12 {
		return nil
	}
	if binary.BigEndian.Uint16(pkt[6:8])&0x3fff != 0 { // фрагменты не трогаем
		return nil
	}
	if binary.BigEndian.Uint16(pkt[ihl+2:]) != 53 {
		return nil
	}
	udpLen := int(binary.BigEndian.Uint16(pkt[ihl+4:]))
	if udpLen < 8+12 || ihl+udpLen > len(pkt) {
		return nil
	}
	dns := pkt[ihl+8 : ihl+udpLen]
	flags := binary.BigEndian.Uint16(dns[2:])
	if flags&0x8000 != 0 || flags&0x7800 != 0 { // ответ или не стандартный запрос
		return nil
	}
	if binary.BigEndian.Uint16(dns[4:]) != 1 {
		return nil
	}
	name, off, ok := dnsReadName(dns, 12)
	if !ok || off+4 > len(dns) {
		return nil
	}
	qtype := binary.BigEndian.Uint16(dns[off:])
	if binary.BigEndian.Uint16(dns[off+2:]) != 1 || (qtype != 1 && qtype != 28) {
		return nil
	}
	ips := m.lookup(name)
	if ips == nil {
		return nil
	}
	qEnd := off + 4
	var ans []byte
	count := 0
	if qtype == 1 {
		for _, ip := range ips {
			ans = append(ans, 0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, ip[0], ip[1], ip[2], ip[3])
			count++
		}
	}
	resp := make([]byte, 0, qEnd+len(ans))
	resp = append(resp, dns[0], dns[1], 0x81, 0x80, 0, 1, byte(count>>8), byte(count), 0, 0, 0, 0)
	resp = append(resp, dns[12:qEnd]...)
	resp = append(resp, ans...)

	total := 20 + 8 + len(resp)
	p := make([]byte, total)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], uint16(total))
	binary.BigEndian.PutUint16(p[6:], 0x4000)
	p[8] = 64
	p[9] = 17
	copy(p[12:16], pkt[16:20]) // отправитель ответа — тот DNS, которому слали запрос
	copy(p[16:20], pkt[12:16])
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))
	binary.BigEndian.PutUint16(p[20:], 53)
	copy(p[22:24], pkt[ihl:ihl+2]) // порт отправителя запроса
	binary.BigEndian.PutUint16(p[24:], uint16(8+len(resp)))
	copy(p[28:], resp) // контрольная сумма UDP = 0: для IPv4 допустимо
	return p
}

// dotResetReply: пока подмена DNS включена, на попытку Android открыть DNS-over-TLS (TCP 853) отвечаем RST.
// Иначе «автоматический» частный DNS уводит запросы в шифрованный канал мимо подмены, а так система сразу
// возвращается к обычному DNS, который мы и видим.
func dotResetReply(pkt []byte) []byte {
	m, _ := dnsOv.Load().(*dnsOvMap)
	if m == nil || len(m.exact)+len(m.suffix) == 0 {
		return nil
	}
	if len(pkt) < 40 || pkt[0]>>4 != 4 || pkt[9] != 6 {
		return nil
	}
	ihl := int(pkt[0]&0x0f) * 4
	if ihl < 20 || len(pkt) < ihl+20 {
		return nil
	}
	if binary.BigEndian.Uint16(pkt[6:8])&0x3fff != 0 {
		return nil
	}
	t := pkt[ihl:]
	if binary.BigEndian.Uint16(t[2:]) != 853 || t[13]&0x02 == 0 || t[13]&0x10 != 0 { // только чистый SYN
		return nil
	}
	seq := binary.BigEndian.Uint32(t[4:])
	p := make([]byte, 40)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], 40)
	binary.BigEndian.PutUint16(p[6:], 0x4000)
	p[8] = 64
	p[9] = 6
	copy(p[12:16], pkt[16:20])
	copy(p[16:20], pkt[12:16])
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))
	r := p[20:]
	binary.BigEndian.PutUint16(r[0:], 853)
	copy(r[2:4], t[0:2])
	binary.BigEndian.PutUint32(r[8:], seq+1)
	r[12] = 5 << 4
	r[13] = 0x14 // RST|ACK
	binary.BigEndian.PutUint16(r[16:], tcpChecksum(net.IP(pkt[16:20]), net.IP(pkt[12:16]), r))
	return p
}
