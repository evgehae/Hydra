package hydra

import (
	"context"
	"fmt"
	"net"
	"strings"
	"time"
)

var serviceTargets = []struct {
	name, ip string
	port     uint16
}{
	{"Telegram DC2", "149.154.167.51", 443},
	{"Telegram DC1/3", "149.154.175.50", 443},
	{"Telegram DC4", "149.154.167.91", 443},
	{"Telegram DC5", "91.108.56.130", 443},
	{"Google", "8.8.8.8", 443},
	{"Cloudflare", "1.1.1.1", 443},
	{"GitHub", "140.82.121.4", 443},
}

// Сервисы, у которых нет постоянных адресов: адрес берём по имени.
var serviceNames = []struct{ name, host string }{
	{"YouTube", "www.youtube.com"},
	{"Видео YouTube (googlevideo)", "redirector.googlevideo.com"},
	{"WhatsApp", "web.whatsapp.com"},
	{"Instagram", "www.instagram.com"},
	{"Discord", "discord.com"},
}

// resolveV4 возвращает первый IPv4-адрес имени.
// Сначала пробует настоящий DoH (не зависит от DNS оператора), потом обычный резолвер.
func resolveV4(ctx context.Context, host string) (net.IP, error) {
	return ResolveA(ctx, host)
}

// ServiceCheck проверяет через действующий туннель, проходит ли TCP до популярных сервисов
// (SYN-ACK от самого сервиса). Помогает отличить «туннель не пускает» от «сервис режет этот дата-центр».
// Важно: это проверка достижимости адреса, а не качества. Замедление по имени сайта (SNI) она не видит.
func (e *Engine) ServiceCheck(ctx context.Context) string {
	d, _ := e.active.Load().(*attemptDev)
	st := e.Status()
	if d == nil || st.State != "up" {
		return "туннель сейчас не подключён: проверять нечего\n"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Через туннель %s (дата-центр %s):\n", st.Strategy, st.Colo)
	okN, total := 0, 0
	for _, t := range serviceTargets {
		total++
		rtt, err := d.tcpProbeTo(ctx, net.ParseIP(t.ip).To4(), t.port, 3*time.Second)
		if err == nil {
			okN++
			fmt.Fprintf(&b, "  ✔ %s (%s:%d) %d мс\n", t.name, t.ip, t.port, rtt.Milliseconds())
		} else {
			fmt.Fprintf(&b, "  ✘ %s (%s:%d): %v\n", t.name, t.ip, t.port, err)
		}
	}
	b.WriteString("По именам (адрес узнан DNS-запросом внутри туннеля, поэтому блокировка имён на DNS оператора не мешает):\n")
	for _, t := range serviceNames {
		total++
		tip, terr := d.resolveA(ctx, t.host, 3*time.Second)
		if terr != nil {
			fmt.Fprintf(&b, "  ✘ %s (%s): %v\n", t.name, t.host, terr)
			continue
		}
		if _, oerr := resolveV4(ctx, t.host); oerr != nil {
			fmt.Fprintf(&b, "  ℹ %s: DNS оператора не отдаёт адрес (%v), через туннель адрес есть: имя блокируется на DNS оператора, внутри VPN это не мешает\n", t.name, oerr)
		}
		rtt, err := d.tcpProbeTo(ctx, tip, 443, 2500*time.Millisecond)
		if err == nil {
			okN++
			fmt.Fprintf(&b, "  ✔ %s (%s → %s) %d мс\n", t.name, t.host, tip.String(), rtt.Milliseconds())
		} else {
			fmt.Fprintf(&b, "  ✘ %s (%s → %s): %v\n", t.name, t.host, tip.String(), err)
		}
	}
	fmt.Fprintf(&b, "Доступно %d из %d.\n", okN, total)
	if total >= 8 && okN == 0 {
		e.markActiveDead(st, total)
	}
	return b.String()
}
