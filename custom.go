package hydra

import (
	"net"
	"strconv"
	"strings"
)

// CustomEndpointStrategies — стратегии MASQUE для адреса, который задал пользователь
// ("IP" или "IP:порт"). Они пробуются раньше остальных. Неверный адрес даёт nil.
func CustomEndpointStrategies(ep string) []Strategy {
	ep = strings.TrimSpace(ep)
	if ep == "" {
		return nil
	}
	host := hostOnly(ep)
	if net.ParseIP(host) == nil {
		return nil
	}
	hostPort := ep
	if _, _, err := net.SplitHostPort(ep); err != nil {
		hostPort = net.JoinHostPort(host, "443")
	}
	mk := func(proto, alias string, fv *fakeVariant) Strategy {
		p := map[string]string{"endpoint": hostPort, "sni": defaultMasqueSNI, "h2": "0"}
		if proto == "h2" {
			p["h2"] = "1"
		}
		if fv != nil && fv.count > 0 {
			p["fake"] = fv.sni
			p["fttl"] = strconv.Itoa(fv.ttl)
			p["fcount"] = strconv.Itoa(fv.count)
			p["fsize"] = strconv.Itoa(fv.size)
		}
		return Strategy{ID: proto + "/" + hostPort + "/" + alias, Transport: "masque", Params: p}
	}
	var out []Strategy
	for i := 0; i < 3 && i < len(fakeVariants); i++ {
		out = append(out, mk("h3", fakeVariants[i].alias, &fakeVariants[i]))
	}
	return append(out, mk("h2", "std", nil))
}

// WhitelistStrategies — стратегии для режима белых списков: настоящий SNI подменяется на имя, которое
// оператор пропускает (российский сайт). HTTP/2 по TCP идёт первым: проход TLS к Cloudflare проверен заранее.
func WhitelistStrategies(snis []string) []Strategy {
	if len(snis) > 3 {
		snis = snis[:3]
	}
	var out []Strategy
	for _, sni := range snis {
		for _, h := range []string{"162.159.198.2", "162.159.198.1"} {
			hp := net.JoinHostPort(h, "443")
			out = append(out, Strategy{ID: "h2/" + hp + "/wl:" + sni, Transport: "masque",
				Params: map[string]string{"endpoint": hp, "sni": sni, "h2": "1"}})
		}
		hp := net.JoinHostPort("162.159.198.2", "443")
		out = append(out, Strategy{ID: "h3/" + hp + "/wl:" + sni, Transport: "masque",
			Params: map[string]string{"endpoint": hp, "sni": sni, "h2": "0"}})
	}
	return out
}
