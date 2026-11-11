package hydra

import (
	"context"
	"fmt"
	"math/rand"
	"strconv"
	"time"
)

// Самообучение: когда все известные способы подвели, Гидра придумывает новые — мутирует лучшие
// (TTL и число фейковых пакетов, их размер, SNI, адрес), запоминает и выбрасывает те, что не работают.

var fakeSNIPool = []string{"www.google.com", "vk.com", "ya.ru", "yandex.ru", "mail.ru", "www.microsoft.com", "cloudflare.com", "dzen.ru"}
var fakeSizePool = []int{64, 100, 128, 200, 256, 400, 600, 900, 1200}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// allStrategies — встроенные стратегии плюс придуманные для этой сети.
func (e *Engine) allStrategies(nk string) []Strategy {
	out := append([]Strategy(nil), e.cfg.Strategies...)
	return append(out, e.cfg.Mem.Generated(nk)...)
}

// sniPool — SNI, которые принимает сервер MASQUE Cloudflare (сертификат проверяется по ключу, а не по имени).
var sniPool = []string{
	"consumer-masque.cloudflareclient.com", "cdnjs.cloudflare.com", "www.cloudflare.com",
	"one.one.one.one", "developers.cloudflare.com", "dash.cloudflare.com",
}

func family(s Strategy) string {
	switch {
	case s.Transport == "masque" && s.Params["h2"] == "1":
		return "h2"
	case s.Transport == "masque" && s.Params["fake"] != "":
		return "h3"
	case s.Transport == "wg" && s.Params["jc"] != "":
		return "wg"
	}
	return ""
}

// GenerateVariants возвращает до n новых вариантов на основе лучших известных в этой сети:
// QUIC с фейковыми пакетами (h3), HTTP/2 (h2) и WireGuard с «мусорным» прологом (wg).
func GenerateVariants(nk string, mem *Memory, all []Strategy, n int, rnd *rand.Rand, needOK bool) []Strategy {
	parents := map[string][]Strategy{}
	for _, s := range mem.Rank(nk, all) {
		f := family(s)
		if f == "" || len(parents[f]) >= 3 {
			continue
		}
		if needOK && !mem.Worked(nk, s.ID) {
			continue // для пополнения пула берём «родителями» только то, что уже работало
		}
		parents[f] = append(parents[f], s)
	}
	var fams []string
	for _, f := range []string{"h3", "h3", "h2", "wg"} { // QUIC — вдвое чаще остальных
		if len(parents[f]) > 0 {
			fams = append(fams, f)
		}
	}
	if len(fams) == 0 {
		return nil
	}
	eps := map[string][]string{}
	seenEP := map[string]bool{}
	for _, s := range all {
		f := family(s)
		ep := s.Params["endpoint"]
		if f == "" || ep == "" || seenEP[f+ep] {
			continue
		}
		seenEP[f+ep] = true
		eps[f] = append(eps[f], ep)
	}
	have := map[string]bool{}
	for _, s := range all {
		have[s.ID] = true
	}
	var out []Strategy
	for tries := 0; tries < n*8 && len(out) < n; tries++ {
		f := fams[rnd.Intn(len(fams))]
		ps := parents[f]
		p := ps[rnd.Intn(len(ps))]
		q := map[string]string{}
		for k, v := range p.Params {
			q[k] = v
		}
		if len(eps[f]) > 1 && rnd.Intn(4) == 0 {
			q["endpoint"] = eps[f][rnd.Intn(len(eps[f]))]
		}
		var id string
		switch f {
		case "h3":
			ttl := clampInt(atoiDefault(q["fttl"], 5)+rnd.Intn(5)-2, 2, 12)
			cnt := clampInt(atoiDefault(q["fcount"], 4)+rnd.Intn(5)-2, 1, 10)
			size := atoiDefault(q["fsize"], 1200)
			if rnd.Intn(10) < 3 {
				size = fakeSizePool[rnd.Intn(len(fakeSizePool))]
			}
			if rnd.Intn(10) < 3 {
				q["fake"] = fakeSNIPool[rnd.Intn(len(fakeSNIPool))]
			}
			if rnd.Intn(4) == 0 { // настоящий SNI в QUIC Initial — то, что читает DPI
				q["sni"] = sniPool[rnd.Intn(len(sniPool))]
			}
			q["fttl"] = strconv.Itoa(ttl)
			q["fcount"] = strconv.Itoa(cnt)
			q["fsize"] = strconv.Itoa(size)
			id = fmt.Sprintf("h3/%s/g:%s:%s:%dx%ds%d", q["endpoint"], q["sni"], q["fake"], ttl, cnt, size)
		case "h2":
			q["sni"] = sniPool[rnd.Intn(len(sniPool))]
			id = fmt.Sprintf("h2/%s/g:%s", q["endpoint"], q["sni"])
		case "wg":
			jc := clampInt(atoiDefault(q["jc"], 4)+rnd.Intn(5)-2, 1, 16)
			jmin := clampInt(atoiDefault(q["jmin"], 40)+rnd.Intn(21)-10, 5, 100)
			jmax := clampInt(atoiDefault(q["jmax"], 70)+rnd.Intn(61)-30, jmin+10, 300)
			q["jc"], q["jmin"], q["jmax"] = strconv.Itoa(jc), strconv.Itoa(jmin), strconv.Itoa(jmax)
			sfx := ""
			if q["rsv"] == "1" {
				sfx = "r"
			}
			id = fmt.Sprintf("wg/%s/g:%d-%d-%d%s", q["endpoint"], jc, jmin, jmax, sfx)
		}
		if id == "" || have[id] {
			continue
		}
		have[id] = true
		out = append(out, Strategy{ID: id, Transport: p.Transport, Params: q})
	}
	return out
}

// learn придумывает и запоминает новые способы для этой сети.
func (e *Engine) learn(nk string) {
	if e.cfg.Mem == nil {
		return
	}
	rnd := rand.New(rand.NewSource(time.Now().UnixNano()))
	gen := GenerateVariants(nk, e.cfg.Mem, e.allStrategies(nk), 6, rnd, false)
	if len(gen) == 0 {
		return
	}
	e.cfg.Mem.AddGenerated(nk, gen)
	Logf("🧬 все известные способы не сработали — придумал %d новых вариантов обхода для сети %s", len(gen), nk)
}

// blame записывает провал стратегии, но только если интернет вообще есть: иначе виновата сеть, а не стратегия.
func (e *Engine) blame(nk, id string) bool {
	if e.cfg.NetAlive != nil && !e.cfg.NetAlive() {
		Logf("   ⚠ интернета нет совсем — стратегию не виню")
		return false
	}
	e.cfg.Mem.Record(nk, id, false, 0)
	return true
}

// waitOnline ждёт, пока интернет снова появится (проверка раз в 3 с или по сигналу о смене сети).
func (e *Engine) waitOnline(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-e.cfg.NetChanged:
		case <-time.After(3 * time.Second):
		}
		if e.cfg.NetAlive == nil || e.cfg.NetAlive() {
			return
		}
	}
}

// grow пополняет пул: придумывает новые варианты на основе стратегий, которые уже работали.
func (e *Engine) grow(nk string) {
	if e.cfg.Mem == nil {
		return
	}
	rnd := rand.New(rand.NewSource(time.Now().UnixNano()))
	gen := GenerateVariants(nk, e.cfg.Mem, e.allStrategies(nk), 6, rnd, true)
	if len(gen) == 0 {
		return
	}
	e.cfg.Mem.AddGenerated(nk, gen)
	Logf("🧬 пополняю пул: придумал %d новых вариантов на основе работающих", len(gen))
}
