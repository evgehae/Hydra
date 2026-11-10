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

// GenerateVariants возвращает до n новых вариантов MASQUE/QUIC на основе лучших известных в сети.
func GenerateVariants(nk string, mem *Memory, all []Strategy, n int, rnd *rand.Rand) []Strategy {
	var parents []Strategy
	for _, s := range mem.Rank(nk, all) {
		if s.Transport != "masque" || s.Params["h2"] == "1" || s.Params["fake"] == "" {
			continue
		}
		parents = append(parents, s)
		if len(parents) >= 4 {
			break
		}
	}
	if len(parents) == 0 {
		return nil
	}
	var eps []string
	seenEP := map[string]bool{}
	for _, s := range all {
		if ep := s.Params["endpoint"]; s.Transport == "masque" && ep != "" && !seenEP[ep] {
			seenEP[ep] = true
			eps = append(eps, ep)
		}
	}
	have := map[string]bool{}
	for _, s := range all {
		have[s.ID] = true
	}
	var out []Strategy
	for tries := 0; tries < n*8 && len(out) < n; tries++ {
		p := parents[rnd.Intn(len(parents))]
		q := map[string]string{}
		for k, v := range p.Params {
			q[k] = v
		}
		ttl := clampInt(atoiDefault(q["fttl"], 5)+rnd.Intn(5)-2, 2, 12)
		cnt := clampInt(atoiDefault(q["fcount"], 4)+rnd.Intn(5)-2, 1, 10)
		size := atoiDefault(q["fsize"], 1200)
		if rnd.Intn(10) < 3 {
			size = fakeSizePool[rnd.Intn(len(fakeSizePool))]
		}
		if rnd.Intn(10) < 3 {
			q["fake"] = fakeSNIPool[rnd.Intn(len(fakeSNIPool))]
		}
		if len(eps) > 1 && rnd.Intn(4) == 0 {
			q["endpoint"] = eps[rnd.Intn(len(eps))]
		}
		q["fttl"] = strconv.Itoa(ttl)
		q["fcount"] = strconv.Itoa(cnt)
		q["fsize"] = strconv.Itoa(size)
		id := fmt.Sprintf("h3/%s/g:%s:%dx%ds%d", q["endpoint"], q["fake"], ttl, cnt, size)
		if have[id] {
			continue
		}
		have[id] = true
		out = append(out, Strategy{ID: id, Transport: "masque", Params: q})
	}
	return out
}

// learn придумывает и запоминает новые способы для этой сети.
func (e *Engine) learn(nk string) {
	if e.cfg.Mem == nil {
		return
	}
	rnd := rand.New(rand.NewSource(time.Now().UnixNano()))
	gen := GenerateVariants(nk, e.cfg.Mem, e.allStrategies(nk), 6, rnd)
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
