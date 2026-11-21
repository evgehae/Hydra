package hydra

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"sync/atomic"
	"time"
)

// ============================================================================
// DNS resolution for Hydra
// ============================================================================
// На Android у Go нет /etc/resolv.conf. Мы даём три уровня:
//   1. DoT  (DNS-over-TLS, порт 853)  — предпочтительно
//   2. DoH  (DNS-over-HTTPS, JSON)     — запасной
//   3. Plain UDP/TCP DNS              — последний шанс
// Все серверы указаны по IP, чтобы не зависеть от системного DNS.

var fallbackDNS = []string{"1.1.1.1", "8.8.8.8", "9.9.9.9", "77.88.8.8"}

// DoT-серверы (IP:порт). SNI нужен для TLS.
var dotServers = []struct {
	addr string // host:port
	sni  string
}{
	{"1.1.1.1:853", "cloudflare-dns.com"},
	{"1.0.0.1:853", "cloudflare-dns.com"},
	{"8.8.8.8:853", "dns.google"},
	{"8.8.4.4:853", "dns.google"},
	{"9.9.9.9:853", "dns.quad9.net"},
	{"149.112.112.112:853", "dns.quad9.net"},
}

// DoH endpoints (по IP)
var dohEndpoints = []string{
	"https://1.1.1.1/dns-query",
	"https://1.0.0.1/dns-query",
	"https://8.8.8.8/dns-query",
	"https://9.9.9.9/dns-query",
	"https://149.112.112.112/dns-query",
}

// SetSystemDNS подменяет резолвер процесса (plain DNS).
func SetSystemDNS(servers []string) {
	var list []string
	seen := map[string]bool{}
	add := func(s string) {
		s = strings.TrimSpace(s)
		if s == "" || net.ParseIP(s) == nil || seen[s] {
			return
		}
		seen[s] = true
		list = append(list, s)
	}
	for _, s := range servers {
		add(s)
	}
	for _, s := range fallbackDNS {
		add(s)
	}
	if len(list) == 0 {
		list = append(list, "1.1.1.1")
	}
	var n uint32
	net.DefaultResolver = &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			i := int(atomic.AddUint32(&n, 1)-1) % len(list)
			d := net.Dialer{Timeout: 3 * time.Second}
			return d.DialContext(ctx, network, net.JoinHostPort(list[i], "53"))
		},
	}
}

// ============================================================================
// Minimal DNS wire format (only what we need for A queries)
// ============================================================================

func packDNSQuery(id uint16, name string) []byte {
	var b []byte
	// Header: ID, flags (RD=1), QDCOUNT=1, ANCOUNT=0, NSCOUNT=0, ARCOUNT=0
	hdr := make([]byte, 12)
	binary.BigEndian.PutUint16(hdr[0:2], id)
	hdr[2] = 0x01 // RD
	binary.BigEndian.PutUint16(hdr[4:6], 1) // QDCOUNT
	b = append(b, hdr...)

	// QNAME
	for _, label := range strings.Split(strings.TrimSuffix(name, "."), ".") {
		if label == "" {
			continue
		}
		b = append(b, byte(len(label)))
		b = append(b, []byte(label)...)
	}
	b = append(b, 0x00) // root

	// QTYPE = A (1), QCLASS = IN (1)
	b = append(b, 0x00, 0x01, 0x00, 0x01)
	return b
}

func parseDNSAnswersA(msg []byte) ([]net.IP, error) {
	if len(msg) < 12 {
		return nil, fmt.Errorf("dns: short message")
	}
	ancount := binary.BigEndian.Uint16(msg[6:8])
	if ancount == 0 {
		return nil, fmt.Errorf("dns: no answers")
	}

	// Skip header + question
	off := 12
	// QNAME
	for off < len(msg) {
		l := int(msg[off])
		if l == 0 {
			off++
			break
		}
		if l >= 0xc0 { // compression
			off += 2
			break
		}
		off += 1 + l
	}
	if off+4 > len(msg) {
		return nil, fmt.Errorf("dns: truncated question")
	}
	off += 4 // QTYPE + QCLASS

	var ips []net.IP
	for i := 0; i < int(ancount) && off < len(msg); i++ {
		// NAME (may be compressed)
		if off >= len(msg) {
			break
		}
		if msg[off]&0xc0 == 0xc0 {
			off += 2
		} else {
			for off < len(msg) {
				l := int(msg[off])
				if l == 0 {
					off++
					break
				}
				if l >= 0xc0 {
					off += 2
					break
				}
				off += 1 + l
			}
		}
		if off+10 > len(msg) {
			break
		}
		typ := binary.BigEndian.Uint16(msg[off : off+2])
		// class := binary.BigEndian.Uint16(msg[off+2 : off+4])
		// ttl ignored
		rdlen := int(binary.BigEndian.Uint16(msg[off+8 : off+10]))
		off += 10
		if off+rdlen > len(msg) {
			break
		}
		if typ == 1 && rdlen == 4 { // A
			ip := net.IPv4(msg[off], msg[off+1], msg[off+2], msg[off+3])
			ips = append(ips, ip.To4())
		}
		off += rdlen
	}
	if len(ips) == 0 {
		return nil, fmt.Errorf("dns: no A records")
	}
	return ips, nil
}

// ============================================================================
// DoT (DNS-over-TLS)
// ============================================================================

// ResolveDoT выполняет DNS-запрос по TLS (порт 853) и возвращает первый IPv4.
func ResolveDoT(ctx context.Context, host string) (net.IP, error) {
	host = strings.TrimSpace(host)
	if host == "" {
		return nil, fmt.Errorf("пустое имя")
	}
	if ip := net.ParseIP(host); ip != nil {
		return ip.To4(), nil
	}

	id := uint16(time.Now().UnixNano() & 0xffff)
	query := packDNSQuery(id, host)

	var lastErr error
	for _, s := range dotServers {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		ip, err := doTQuery(ctx, s.addr, s.sni, query)
		if err == nil && ip != nil {
			return ip, nil
		}
		lastErr = err
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("DoT: нет ответа")
	}
	return nil, lastErr
}

func doTQuery(ctx context.Context, addr, sni string, query []byte) (net.IP, error) {
	d := net.Dialer{Timeout: 4 * time.Second}
	raw, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil, err
	}
	defer raw.Close()

	cfg := &tls.Config{
		ServerName:         sni,
		MinVersion:         tls.VersionTLS12,
		InsecureSkipVerify: false,
	}
	conn := tls.Client(raw, cfg)
	if err := conn.HandshakeContext(ctx); err != nil {
		return nil, fmt.Errorf("DoT handshake %s: %w", addr, err)
	}
	defer conn.Close()

	// DNS-over-TLS: 2-byte length prefix
	lenbuf := make([]byte, 2)
	binary.BigEndian.PutUint16(lenbuf, uint16(len(query)))
	if _, err := conn.Write(lenbuf); err != nil {
		return nil, err
	}
	if _, err := conn.Write(query); err != nil {
		return nil, err
	}

	// Read length
	if err := conn.SetReadDeadline(time.Now().Add(5 * time.Second)); err != nil {
		return nil, err
	}
	if _, err := io.ReadFull(conn, lenbuf); err != nil {
		return nil, fmt.Errorf("DoT read len: %w", err)
	}
	n := int(binary.BigEndian.Uint16(lenbuf))
	if n < 12 || n > 4096 {
		return nil, fmt.Errorf("DoT: bad length %d", n)
	}
	resp := make([]byte, n)
	if _, err := io.ReadFull(conn, resp); err != nil {
		return nil, fmt.Errorf("DoT read body: %w", err)
	}

	ips, err := parseDNSAnswersA(resp)
	if err != nil {
		return nil, err
	}
	return ips[0], nil
}

// ============================================================================
// DoH (DNS-over-HTTPS)
// ============================================================================

// ResolveDoH делает DNS-over-HTTPS (JSON) и возвращает IPv4.
func ResolveDoH(ctx context.Context, host string) (net.IP, error) {
	host = strings.TrimSpace(host)
	if host == "" {
		return nil, fmt.Errorf("пустое имя")
	}
	if ip := net.ParseIP(host); ip != nil {
		return ip.To4(), nil
	}

	client := &http.Client{
		Timeout: 5 * time.Second,
		Transport: &http.Transport{
			DisableKeepAlives:   true,
			TLSHandshakeTimeout: 4 * time.Second,
		},
	}

	var lastErr error
	for _, base := range dohEndpoints {
		u := base + "?name=" + host + "&type=A"
		req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
		if err != nil {
			lastErr = err
			continue
		}
		req.Header.Set("Accept", "application/dns-json")
		resp, err := client.Do(req)
		if err != nil {
			lastErr = err
			continue
		}
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
		resp.Body.Close()
		if resp.StatusCode != 200 {
			lastErr = fmt.Errorf("DoH %s: HTTP %d", base, resp.StatusCode)
			continue
		}
		var out struct {
			Answer []struct {
				Type int    `json:"type"`
				Data string `json:"data"`
			} `json:"Answer"`
		}
		if err := json.Unmarshal(body, &out); err != nil {
			lastErr = err
			continue
		}
		for _, a := range out.Answer {
			if a.Type == 1 {
				if ip := net.ParseIP(a.Data); ip != nil {
					if ip4 := ip.To4(); ip4 != nil {
						return ip4, nil
					}
				}
			}
		}
		lastErr = fmt.Errorf("DoH %s: нет A-записи", base)
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("DoH: пустой ответ")
	}
	return nil, lastErr
}

// ============================================================================
// Unified resolver
// ============================================================================

// ResolveA — основной способ получить IPv4.
// Порядок: DoT → DoH → plain DNS.
func ResolveA(ctx context.Context, host string) (net.IP, error) {
	host = strings.TrimSpace(host)
	if host == "" {
		return nil, fmt.Errorf("пустое имя")
	}
	if ip := net.ParseIP(host); ip != nil {
		return ip.To4(), nil
	}

	// 1. DoT
	if ip, err := ResolveDoT(ctx, host); err == nil && ip != nil {
		return ip, nil
	}

	// 2. DoH
	if ip, err := ResolveDoH(ctx, host); err == nil && ip != nil {
		return ip, nil
	}

	// 3. Plain
	cctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	addrs, err := net.DefaultResolver.LookupIPAddr(cctx, host)
	if err != nil {
		return nil, fmt.Errorf("plain DNS: %w", err)
	}
	for _, a := range addrs {
		if ip4 := a.IP.To4(); ip4 != nil {
			return ip4, nil
		}
	}
	return nil, fmt.Errorf("нет IPv4 для %s", host)
}
