package hydra

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ColoPolicy — политика выбора дата-центра Cloudflare (по коду аэропорта).
// Block — запрещённые коды; Allow — если не пусто, разрешены только они.
type ColoPolicy struct {
	Block []string
	Allow []string
}

// DefaultColoPolicy: по умолчанию запрещена только Москва (DME); остальные точки можно добавить в настройках.
func DefaultColoPolicy() *ColoPolicy {
	return &ColoPolicy{Block: []string{"DME"}}
}

func normColo(s string) string { return strings.ToUpper(strings.TrimSpace(s)) }

// Allows: nil-политика и неизвестный дата-центр (пустой код) не блокируются.
func (p *ColoPolicy) Allows(colo string) bool {
	if p == nil {
		return true
	}
	c := normColo(colo)
	if c == "" {
		return true
	}
	for _, b := range p.Block {
		if normColo(b) == c {
			return false
		}
	}
	if len(p.Allow) > 0 {
		for _, a := range p.Allow {
			if normColo(a) == c {
				return true
			}
		}
		return false
	}
	return true
}

// ParseColoList разбирает "dme, LED;fra" в ["DME","LED","FRA"] без повторов.
func ParseColoList(s string) []string {
	seen := map[string]bool{}
	var out []string
	split := func(r rune) bool { return r == ',' || r == ';' || r == ' ' || r == '\n' || r == '\t' }
	for _, f := range strings.FieldsFunc(s, split) {
		c := normColo(f)
		if c != "" && !seen[c] {
			seen[c] = true
			out = append(out, c)
		}
	}
	return out
}

// ColoError — туннель поднялся, но попал в запрещённый дата-центр.
type ColoError struct{ Colo string }

func (e *ColoError) Error() string {
	return fmt.Sprintf("дата-центр %s запрещён политикой", e.Colo)
}

// ColoReporter — необязательный интерфейс туннеля: сказать, через какой
// дата-центр он идёт. Туннели без него пропускаются без проверки.
type ColoReporter interface {
	Colo(ctx context.Context) (string, error)
}

// ParseTrace разбирает ответ https://cloudflare.com/cdn-cgi/trace в map.
func ParseTrace(body string) map[string]string {
	m := map[string]string{}
	sc := bufio.NewScanner(strings.NewReader(body))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		if k, v, ok := strings.Cut(line, "="); ok {
			m[strings.TrimSpace(k)] = strings.TrimSpace(v)
		}
	}
	return m
}

// TraceInfo — стабильный разбор cdn-cgi/trace для диагностики и UI.
type TraceInfo struct {
	IP       string // публичный IP
	Colo     string // код дата-центра (FRA, HEL, …)
	Loc      string // страна (DE, FI, …)
	Warp     string // "on" / "off" / ""
	Gateway  string
	HttpProtocol string
	TlsVersion   string
	Raw      map[string]string
}

// ParseTraceInfo — надёжный парсер: нормализует ключи, colo в верхний регистр.
func ParseTraceInfo(body string) TraceInfo {
	m := ParseTrace(body)
	ti := TraceInfo{
		IP:           m["ip"],
		Colo:         normColo(m["colo"]),
		Loc:          strings.ToUpper(strings.TrimSpace(m["loc"])),
		Warp:         strings.ToLower(strings.TrimSpace(m["warp"])),
		Gateway:      m["gateway"],
		HttpProtocol: m["http"],
		TlsVersion:   m["tls"],
		Raw:          m,
	}
	return ti
}

// String — короткая строка для UI: "FRA · DE · warp=on · 1.2.3.4"
func (t TraceInfo) String() string {
	parts := []string{}
	if t.Colo != "" {
		parts = append(parts, t.Colo)
	}
	if t.Loc != "" {
		parts = append(parts, t.Loc)
	}
	if t.Warp != "" {
		parts = append(parts, "warp="+t.Warp)
	}
	if t.IP != "" {
		parts = append(parts, t.IP)
	}
	return strings.Join(parts, " · ")
}

// TraceColo — стандартный способ узнать дата-центр: запрос trace через туннель.
func TraceColo(ctx context.Context, t Tunnel) (string, error) {
	ti, err := TraceFull(ctx, t)
	if err != nil {
		return "", err
	}
	if ti.Colo == "" {
		return "", errors.New("в ответе trace нет colo")
	}
	return ti.Colo, nil
}

// TraceFull — полный разбор cdn-cgi/trace через туннель (IP, colo, loc, warp).
func TraceFull(ctx context.Context, t Tunnel) (TraceInfo, error) {
	tr := &http.Transport{
		DialContext:         t.DialContext,
		DisableKeepAlives:   true,
		TLSHandshakeTimeout: 5 * time.Second,
	}
	cl := &http.Client{Transport: tr, Timeout: 8 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "GET", "https://cloudflare.com/cdn-cgi/trace", nil)
	if err != nil {
		return TraceInfo{}, err
	}
	resp, err := cl.Do(req)
	if err != nil {
		return TraceInfo{}, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	ti := ParseTraceInfo(string(body))
	if ti.Colo == "" && ti.IP == "" {
		return ti, errors.New("пустой ответ trace")
	}
	return ti, nil
}
