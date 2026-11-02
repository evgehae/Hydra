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

// DefaultColoPolicy: никакой Москвы (DME) и остальных российских точек Cloudflare.
func DefaultColoPolicy() *ColoPolicy {
	return &ColoPolicy{Block: []string{"DME", "LED", "SVX", "KJA", "OVB", "KHV", "VVO", "KZN"}}
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

// ParseTrace разбирает ответ https://cloudflare.com/cdn-cgi/trace.
func ParseTrace(body string) map[string]string {
	m := map[string]string{}
	sc := bufio.NewScanner(strings.NewReader(body))
	for sc.Scan() {
		if k, v, ok := strings.Cut(sc.Text(), "="); ok {
			m[strings.TrimSpace(k)] = strings.TrimSpace(v)
		}
	}
	return m
}

// TraceColo — стандартный способ узнать дата-центр: запрос trace через туннель.
func TraceColo(ctx context.Context, t Tunnel) (string, error) {
	tr := &http.Transport{
		DialContext:         t.DialContext,
		DisableKeepAlives:   true,
		TLSHandshakeTimeout: 8 * time.Second,
	}
	cl := &http.Client{Transport: tr, Timeout: 10 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "GET", "https://cloudflare.com/cdn-cgi/trace", nil)
	if err != nil {
		return "", err
	}
	resp, err := cl.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	colo := normColo(ParseTrace(string(body))["colo"])
	if colo == "" {
		return "", errors.New("в ответе trace нет colo")
	}
	return colo, nil
}
