package hydra

import (
	"fmt"
	"time"
)

// Пул стратегий: Гидра сама следит, чтобы в запасе всегда было достаточно РАБОЧИХ стратегий каждого
// семейства. В фоне (пока основной туннель здоров) она проверяет непроверенные и давно не
// проверявшиеся стратегии отдельной короткой попыткой, неработающие отправляет в карантин,
// придуманные неработающие удаляет, а нехватку пополняет новыми вариантами.

var poolTargets = map[string]int{"h3": 6, "h2": 2, "wg": 2}
var poolFams = []string{"h3", "h2", "wg"}

const (
	testRetry     = 30 * time.Minute // одну стратегию не проверять чаще
	staleAfter    = 2 * time.Hour    // рабочая стратегия без успехов дольше этого — пора перепроверить
	testFast      = 90 * time.Second // период проверок, пока в пуле нехватка
	testSlow      = 20 * time.Minute // период проверок, когда пул в норме
	quarantineFor = 12 * time.Hour
)

func poolFamily(s Strategy) string {
	switch {
	case s.Transport == "wg":
		return "wg"
	case s.Params["h2"] == "1":
		return "h2"
	}
	return "h3"
}

func healthyStat(ok, fail int) bool { return ok > 0 && float64(ok)/float64(ok+fail) >= 0.4 }

// poolCounts считает по семействам: рабочие, непроверенные, в карантине.
func (e *Engine) poolCounts(nk string) (healthy, untested, dead map[string]int) {
	healthy, untested, dead = map[string]int{}, map[string]int{}, map[string]int{}
	for _, s := range e.allStrategies(nk) {
		f := poolFamily(s)
		ok, fail, _, lf, found := e.cfg.Mem.Stat(nk, s.ID)
		switch {
		case !found || ok+fail == 0:
			untested[f]++
		case healthyStat(ok, fail):
			healthy[f]++
		case ok == 0 && fail >= 3 && time.Since(lf) < quarantineFor:
			dead[f]++
		}
	}
	return
}

// hasDeficit: в каком-то семействе рабочих меньше цели, и есть что проверять.
func (e *Engine) hasDeficit(nk string) bool {
	h, u, _ := e.poolCounts(nk)
	for _, f := range poolFams {
		if h[f] < poolTargets[f] && u[f] > 0 {
			return true
		}
	}
	return false
}

// PoolSummary — состояние пула для журнала и отчёта.
func (e *Engine) PoolSummary(nk string) string {
	h, u, d := e.poolCounts(nk)
	s := "пул стратегий (рабочих/цель):"
	for _, f := range poolFams {
		s += fmt.Sprintf(" %s %d/%d", f, h[f], poolTargets[f])
	}
	s += fmt.Sprintf("; не проверено: h3 %d, h2 %d, wg %d; в карантине: h3 %d, h2 %d, wg %d; придуманных: %d\n",
		u["h3"], u["h2"], u["wg"], d["h3"], d["h2"], d["wg"], len(e.cfg.Mem.Generated(nk)))
	return s
}

// pickTest выбирает, что проверить в фоне: сначала непроверенные из семейства с нехваткой,
// затем самую «давнюю» рабочую, затем стратегию, отсидевшую карантин.
func (e *Engine) pickTest(nk string, exclude map[string]bool, blocked map[string]time.Time, tested map[string]time.Time) (Strategy, string, bool) {
	healthy, untested, _ := e.poolCounts(nk)
	all := e.cfg.Mem.Rank(nk, e.allStrategies(nk))
	elig := func(s Strategy) bool {
		if exclude[s.ID] {
			return false
		}
		if t, ok := tested[s.ID]; ok && time.Since(t) < testRetry {
			return false
		}
		if e.recentlyTried(s.ID, testRetry) || e.cfg.Mem.EndpointDead(nk, s.ID) || (e.cfg.CanRun != nil && !e.cfg.CanRun(s)) {
			return false
		}
		ep := s.Params["endpoint"]
		if until, ok := blocked[hostOnly(ep)]; ep != "" && ok && time.Now().Before(until) {
			return false
		}
		return !e.cfg.Mem.Doomed(nk, s.ID)
	}
	// 1) нехватка: пробуем непроверенные из самого обделённого семейства
	best, bestDef := "", 0.0
	for _, f := range []string{"wg", "h2", "h3"} {
		t := poolTargets[f]
		if def := float64(t-healthy[f]) / float64(t); def > bestDef && untested[f] > 0 {
			best, bestDef = f, def
		}
	}
	if best != "" {
		for _, s := range all {
			ok, fail, _, _, found := e.cfg.Mem.Stat(nk, s.ID)
			if poolFamily(s) == best && elig(s) && (!found || ok+fail == 0) {
				return s, "нехватка " + best, true
			}
		}
	}
	// 2) пул в норме: перепроверяем самую давнюю рабочую
	var stale Strategy
	var staleAt time.Time
	haveStale := false
	for _, s := range all {
		ok, fail, lastOK, _, found := e.cfg.Mem.Stat(nk, s.ID)
		if !found || !healthyStat(ok, fail) || !elig(s) || time.Since(lastOK) < staleAfter {
			continue
		}
		if !haveStale || lastOK.Before(staleAt) {
			stale, staleAt, haveStale = s, lastOK, true
		}
	}
	if haveStale {
		return stale, "перепроверка рабочей", true
	}
	// 3) вышедшие из карантина получают второй шанс
	for _, s := range all {
		ok, fail, _, lf, found := e.cfg.Mem.Stat(nk, s.ID)
		if found && ok == 0 && fail >= 3 && time.Since(lf) >= quarantineFor && elig(s) {
			return s, "после карантина", true
		}
	}
	return Strategy{}, "", false
}

// familyPresent — какие семейства стратегий вообще есть в списке (например, при протоколе «MASQUE» WireGuard нет).
func (e *Engine) familyPresent(nk string) map[string]bool {
	out := map[string]bool{}
	for _, s := range e.allStrategies(nk) {
		out[poolFamily(s)] = true
	}
	return out
}
