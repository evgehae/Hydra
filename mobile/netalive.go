package mobile

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Состояние сети: "ok" — зарубежный интернет доступен; "whitelist" — отвечают только российские адреса
// (режим «белых списков» у оператора); "dead" — не отвечает ничего.

var (
	foreignTargets  = []string{"1.1.1.1:443", "8.8.8.8:443", "9.9.9.9:443", "162.159.198.2:443"}
	domesticTargets = []string{"77.88.8.8:443", "77.88.8.1:443"}

	lastState   atomic.Value // string
	lastStateAt atomic.Int64
)

type dialRes struct {
	addr    string
	foreign bool
	ok      bool
	ms      int64
}

func dialAll(timeout time.Duration) []dialRes {
	type job struct {
		addr    string
		foreign bool
	}
	var jobs []job
	for _, a := range foreignTargets {
		jobs = append(jobs, job{a, true})
	}
	for _, a := range domesticTargets {
		jobs = append(jobs, job{a, false})
	}
	out := make([]dialRes, len(jobs))
	var wg sync.WaitGroup
	for i, j := range jobs {
		wg.Add(1)
		go func(i int, j job) {
			defer wg.Done()
			t0 := time.Now()
			c, err := net.DialTimeout("tcp", j.addr, timeout)
			if err == nil {
				c.Close()
			}
			out[i] = dialRes{j.addr, j.foreign, err == nil, time.Since(t0).Milliseconds()}
		}(i, j)
	}
	wg.Wait()
	return out
}

func classify(rs []dialRes) string {
	dom := false
	for _, r := range rs {
		if r.ok && r.foreign {
			return "ok"
		}
		if r.ok && !r.foreign {
			dom = true
		}
	}
	if dom {
		return "whitelist"
	}
	return "dead"
}

// realNetState: быстрая проверка — как только отвечает любой зарубежный адрес, сеть «ok».
func realNetState() string {
	type r struct {
		foreign, ok bool
	}
	ch := make(chan r, len(foreignTargets)+len(domesticTargets))
	probe := func(addr string, foreign bool) {
		c, err := net.DialTimeout("tcp", addr, 2500*time.Millisecond)
		if err == nil {
			c.Close()
		}
		ch <- r{foreign, err == nil}
	}
	for _, a := range foreignTargets {
		go probe(a, true)
	}
	for _, a := range domesticTargets {
		go probe(a, false)
	}
	dom := false
	st := "dead"
	for i := 0; i < len(foreignTargets)+len(domesticTargets); i++ {
		x := <-ch
		if x.ok && x.foreign {
			st = "ok"
			break
		}
		if x.ok {
			dom = true
		}
	}
	if st != "ok" && dom {
		st = "whitelist"
	}
	lastState.Store(st)
	lastStateAt.Store(time.Now().Unix())
	return st
}

// realNetAlive: есть ли зарубежный интернет (для отказоустойчивых проверок).
func realNetAlive() bool { return realNetState() == "ok" }

// wlSNIs — имена российских сайтов, которые операторы чаще всего пропускают в режиме белых списков.
var wlSNIs = []string{
	"ya.ru", "yandex.ru", "www.yandex.ru", "dzen.ru", "vk.com", "mail.ru", "gosuslugi.ru",
	"www.gosuslugi.ru", "sberbank.ru", "ozon.ru", "wildberries.ru", "avito.ru", "rutube.ru", "kinopoisk.ru",
}

func tlsOK(ctx context.Context, addr, sni string) bool {
	d := &net.Dialer{Timeout: 3 * time.Second}
	conn, err := tls.DialWithDialer(d, "tcp", addr, &tls.Config{ServerName: sni, InsecureSkipVerify: true, MinVersion: tls.VersionTLS12})
	if err != nil {
		return false
	}
	conn.Close()
	return ctx.Err() == nil
}

// realWLScan: с какими именами (SNI) удаётся завершить TLS-рукопожатие с Cloudflare сквозь белые списки.
func realWLScan(ctx context.Context) []string {
	const host = "162.159.198.2:443"
	res := make([]bool, len(wlSNIs))
	var wg sync.WaitGroup
	sem := make(chan struct{}, 5)
	for i, sni := range wlSNIs {
		wg.Add(1)
		sem <- struct{}{}
		go func(i int, sni string) {
			defer wg.Done()
			defer func() { <-sem }()
			res[i] = tlsOK(ctx, host, sni)
		}(i, sni)
	}
	wg.Wait()
	var out []string
	for i, ok := range res {
		if ok {
			out = append(out, wlSNIs[i])
		}
	}
	return out
}

// WhitelistCheck — подробная проверка для экрана диагностики: что доступно, а что нет.
func WhitelistCheck() string {
	rs := dialAll(3 * time.Second)
	st := classify(rs)
	var b strings.Builder
	switch st {
	case "ok":
		b.WriteString("Состояние сети: обычная (зарубежный интернет доступен)\n")
	case "whitelist":
		b.WriteString("Состояние сети: БЕЛЫЕ СПИСКИ (отвечают только российские адреса)\n")
	default:
		b.WriteString("Состояние сети: нет интернета\n")
	}
	b.WriteString("\nTCP-соединения:\n")
	for _, r := range rs {
		kind := "зарубежный"
		if !r.foreign {
			kind = "российский"
		}
		mark := "✘"
		if r.ok {
			mark = "✔"
		}
		b.WriteString(fmt.Sprintf("  %s %s (%s) %d мс\n", mark, r.addr, kind, r.ms))
	}
	ctx := context.Background()
	b.WriteString("\nTLS-рукопожатие с Cloudflare (162.159.198.2:443) под разными именами:\n")
	base := "www.cloudflare.com"
	mark := "✘"
	if tlsOK(ctx, "162.159.198.2:443", base) {
		mark = "✔"
	}
	b.WriteString(fmt.Sprintf("  %s %s (обычное имя)\n", mark, base))
	pass := realWLScan(ctx)
	for _, sni := range wlSNIs {
		m := "✘"
		for _, p := range pass {
			if p == sni {
				m = "✔"
			}
		}
		b.WriteString(fmt.Sprintf("  %s %s\n", m, sni))
	}
	if st == "whitelist" {
		if len(pass) > 0 {
			b.WriteString("\nК Cloudflare проходят имена: " + strings.Join(pass, ", ") + ". Гидра попробует подключиться с ними.\n")
		} else {
			b.WriteString("\nНи одно имя не прошло: фильтр, похоже, работает по IP-адресам. Нужен ретранслятор с адресом из белого списка (см. подсказку).\n")
		}
	}
	return b.String()
}

// netStateInfo — последнее известное состояние без сетевых запросов (для отчёта).
func netStateInfo() string {
	s, _ := lastState.Load().(string)
	if s == "" {
		return "состояние сети: ещё не проверялось\n"
	}
	ago := time.Now().Unix() - lastStateAt.Load()
	return fmt.Sprintf("состояние сети: %s (проверено %d с назад)\n", s, ago)
}
