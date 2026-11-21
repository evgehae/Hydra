package hydra

import (
	"context"
	"fmt"
	"net"
	"strings"
	"time"
)

// SpeedTest — лёгкая оценка качества туннеля: несколько TCP-проб и замер RTT.
func (e *Engine) SpeedTest(ctx context.Context) string {
	d, _ := e.active.Load().(*attemptDev)
	st := e.Status()
	if d == nil || st.State != "up" {
		return "туннель сейчас не подключён"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Стратегия: %s · ДЦ: %s · текущий пинг: %d мс\n", st.Strategy, st.Colo, st.RTT.Milliseconds())

	targets := []struct {
		name string
		ip   string
		port uint16
	}{
		{"Cloudflare", "1.1.1.1", 443},
		{"Google DNS", "8.8.8.8", 443},
		{"Telegram", "149.154.167.51", 443},
	}
	var sum time.Duration
	ok := 0
	for _, t := range targets {
		if ctx.Err() != nil {
			break
		}
		start := time.Now()
		_, err := d.tcpProbeTo(ctx, net.ParseIP(t.ip).To4(), t.port, 4*time.Second)
		rtt := time.Since(start)
		if err != nil {
			fmt.Fprintf(&b, "✘ %s (%s:%d): %v\n", t.name, t.ip, t.port, err)
			continue
		}
		ok++
		sum += rtt
		fmt.Fprintf(&b, "✔ %s: %d мс\n", t.name, rtt.Milliseconds())
	}
	if ok > 0 {
		avg := sum / time.Duration(ok)
		fmt.Fprintf(&b, "\nСредний RTT: %d мс · успешных проб: %d/%d\n", avg.Milliseconds(), ok, len(targets))
		switch {
		case avg < 80*time.Millisecond:
			b.WriteString("Оценка: отлично\n")
		case avg < 150*time.Millisecond:
			b.WriteString("Оценка: хорошо\n")
		case avg < 300*time.Millisecond:
			b.WriteString("Оценка: приемлемо\n")
		default:
			b.WriteString("Оценка: медленно\n")
		}
	} else {
		b.WriteString("\nНе удалось достучаться до тестовых адресов через туннель.\n")
	}
	return b.String()
}
