package hydra

import (
	"fmt"
	"net"
	"strconv"
	"strings"
)

const defaultMasqueSNI = "consumer-masque.cloudflareclient.com"

func hostOnly(ep string) string {
	h, _, err := net.SplitHostPort(ep)
	if err != nil {
		return strings.Trim(ep, "[]")
	}
	return strings.Trim(h, "[]")
}

func atoiDefault(s string, def int) int {
	if n, err := strconv.Atoi(strings.TrimSpace(s)); err == nil {
		return n
	}
	return def
}

type fakeVariant struct {
	alias string
	sni   string
	ttl   int
	count int
	size  int // размер каждого фейкового пакета, байт
}

// Фейковые QUIC-пакеты перед рукопожатием (см. UDPRelay). По журналам Zarp:
// «google ×3» (3 пакета по 1200 байт) — основная стратегия, «VK ×6» (по 1357 байт) — запасная.
var fakeVariants = []fakeVariant{
	{"g3", "www.google.com", 5, 3, 1200},
	{"vk5x6", "vk.com", 5, 6, 1357},
	{"g6", "www.google.com", 5, 6, 1200},
	{"vk4x6", "vk.com", 4, 6, 1357},
	{"vk6x6", "vk.com", 6, 6, 1357},
	{"ya5x6", "ya.ru", 5, 6, 1357},
	{"plain", "", 0, 0, 0},
}

// MasqueStrategies — способы подключиться к WARP по MASQUE: адрес сервера ×
// фейковые пакеты × имя в TLS (SNI) × HTTP/3 (UDP) или HTTP/2 (TCP, если режут QUIC).
// Порядок — «самое вероятное первым»; дальше его уточняет память по сетям.
// Разные группы адресов нужны ещё и чтобы уйти от нежелательного дата-центра:
// у разных префиксов Cloudflare маршруты бывают разные.
func MasqueStrategies(acc *Account) []Strategy {
	var eps []string
	seen := map[string]bool{}
	add := func(h string) {
		h = strings.TrimSpace(h)
		if h == "" || net.ParseIP(h) == nil || seen[h] {
			return
		}
		seen[h] = true
		eps = append(eps, h)
	}
	add("162.159.198.2")
	if acc != nil {
		add(hostOnly(acc.EndpointV4))
	}
	// Только настоящие серверы MASQUE. Адреса WireGuard (162.159.192/193/195.x,
	// 188.114.96/97.x) отвечают на QUIC, но на рукопожатии получают TLS handshake failure.
	for _, h := range []string{
		"162.159.198.1",
		"2606:4700:103::2", "2606:4700:103::1",
	} {
		add(h)
	}

	mk := func(proto, ep, alias, sni string, fv *fakeVariant) Strategy {
		hostPort := ep
		if _, _, err := net.SplitHostPort(ep); err != nil {
			hostPort = net.JoinHostPort(ep, "443")
		}
		p := map[string]string{
			"endpoint": hostPort,
			"sni":      sni,
			"h2":       "0",
		}
		if proto == "h2" {
			p["h2"] = "1"
		}
		if fv != nil && fv.count > 0 {
			p["fake"] = fv.sni
			p["fttl"] = strconv.Itoa(fv.ttl)
			p["fcount"] = strconv.Itoa(fv.count)
			p["fsize"] = strconv.Itoa(fv.size)
		}
		return Strategy{ID: fmt.Sprintf("%s/%s/%s", proto, ep, alias), Transport: "masque", Params: p}
	}

	var out []Strategy
	for i := range fakeVariants {
		fv := &fakeVariants[i]
		for _, ep := range eps {
			out = append(out, mk("h3", ep, fv.alias, defaultMasqueSNI, fv))
		}
	}
	// другое имя в TLS — только с самыми удачными фейками
	for _, alt := range []struct{ alias, name string }{
		{"speed", "speed.cloudflare.com"},
		{"www", "www.cloudflare.com"},
	} {
		for _, ep := range eps {
			out = append(out, mk("h3", ep, fakeVariants[0].alias+"+"+alt.alias, alt.name, &fakeVariants[0]))
		}
	}
	// другие порты: некоторые провайдеры режут именно UDP 443 (у Zarp рабочими бывали 500 и др.)
	for _, port := range []string{"500", "1701", "4500"} {
		for _, ep := range []string{"162.159.198.2", "162.159.198.1"} {
			for i := 0; i < 2; i++ {
				fv := &fakeVariants[i]
				out = append(out, mk("h3", net.JoinHostPort(ep, port), fv.alias, defaultMasqueSNI, fv))
			}
		}
	}
	for _, ep := range eps {
		out = append(out, mk("h2", ep, "std", defaultMasqueSNI, nil))
	}
	return out
}

func describeStrategy(s Strategy) string {
	if s.Transport == "wg" {
		out := "WireGuard → " + s.Params["endpoint"]
		if jc := s.Params["jc"]; jc != "" {
			out += fmt.Sprintf(", «мусор» перед рукопожатием: %s × %s–%s байт", jc, s.Params["jmin"], s.Params["jmax"])
		}
		return out
	}
	proto := "HTTP/3 (QUIC)"
	if s.Params["h2"] == "1" {
		proto = "HTTP/2 (TCP)"
	}
	out := fmt.Sprintf("%s → %s, SNI %s", proto, s.Params["endpoint"], s.Params["sni"])
	if f := s.Params["fake"]; f != "" {
		out += fmt.Sprintf(", фейки %s ×%s TTL %s", f, s.Params["fcount"], s.Params["fttl"])
	}
	return out
}
