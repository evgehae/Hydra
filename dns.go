package hydra

import (
	"context"
	"net"
	"strings"
	"sync/atomic"
	"time"
)

// На Android у Go нет /etc/resolv.conf, поэтому встроенный резолвер идёт на
// localhost:53 — а там никого нет, и любое имя «не находится». Лечим: сами
// задаём DNS-серверы. Системные присылает Android-часть, запасные — ниже.
var fallbackDNS = []string{"8.8.8.8", "1.1.1.1", "77.88.8.8"}

// SetSystemDNS подменяет резолвер процесса: сначала переданные серверы
// (только IP-адреса), потом запасные. Каждая новая попытка идёт на следующий сервер.
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
