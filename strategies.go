package hydra

import (
	"fmt"
	"net"
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

// MasqueStrategies — набор способов подключиться к WARP по MASQUE: адрес сервера
// × имя в TLS (SNI) × HTTP/3 (UDP) или HTTP/2 (TCP, если режут QUIC).
// Порядок — «самое вероятное первым»; дальше его уточняет память по сетям.
// Разные группы адресов нужны ещё и для того, чтобы уйти от нежелательного
// дата-центра: у разных префиксов Cloudflare маршруты бывают разные.
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
	if acc != nil {
		add(hostOnly(acc.EndpointV4))
	}
	for _, h := range []string{
		"162.159.198.1", "162.159.198.2",
		"162.159.192.1", "162.159.193.1", "162.159.195.1",
		"188.114.96.1", "188.114.97.1",
	} {
		add(h)
	}
	snis := []struct{ alias, name string }{
		{"std", defaultMasqueSNI},
		{"speed", "speed.cloudflare.com"},
		{"www", "www.cloudflare.com"},
	}
	var out []Strategy
	for _, h2 := range []bool{false, true} {
		proto, flag := "h3", "0"
		if h2 {
			proto, flag = "h2", "1"
		}
		for _, sni := range snis {
			for _, ep := range eps {
				out = append(out, Strategy{
					ID:        fmt.Sprintf("%s/%s/%s", proto, ep, sni.alias),
					Transport: "masque",
					Params: map[string]string{
						"endpoint": net.JoinHostPort(ep, "443"),
						"sni":      sni.name,
						"h2":       flag,
					},
				})
			}
		}
	}
	return out
}
