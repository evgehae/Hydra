package hydra

import (
	"context"
	"strings"
	"time"
)

const wlMessage = "🛑 Белые списки: оператор пропускает только российские сайты, Cloudflare сейчас недоступен. Подключусь сам, когда ограничения снимут"

// netState — доступен ли зарубежный интернет: "ok", "whitelist" (отвечают только российские адреса) или "dead".
func (e *Engine) netState() string {
	if e.cfg.NetState == nil {
		return "ok"
	}
	return e.cfg.NetState()
}

func (e *Engine) sleepOrNet(ctx context.Context, d time.Duration) {
	select {
	case <-ctx.Done():
	case <-e.cfg.NetChanged:
	case <-time.After(d):
	}
}

func (e *Engine) noteTry(id string) {
	e.mu.Lock()
	if e.tried == nil {
		e.tried = map[string]time.Time{}
	}
	e.tried[id] = time.Now()
	e.mu.Unlock()
}

func (e *Engine) recentlyTried(id string, d time.Duration) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	t, ok := e.tried[id]
	return ok && time.Since(t) < d
}

// outageStep обрабатывает «нет зарубежного интернета». wait=true — подключаться сейчас бессмысленно
// (уже подождали, надо перечитать состояние). Иначе возвращает дополнительные стратегии для режима белых списков.
func (e *Engine) outageStep(ctx context.Context, st string) (extra []Strategy, wait bool) {
	e.inOutage = true
	if st == "dead" {
		e.setStatus(Status{State: "reconnecting", Message: "нет интернета — жду сеть"})
		e.waitOnline(ctx)
		return nil, true
	}
	if !e.outageLogged {
		e.outageLogged = true
		Logf("🛑 режим белых списков: российские адреса отвечают, а Cloudflare, Google и другие зарубежные — нет")
	}
	e.setStatus(Status{State: "reconnecting", Message: wlMessage})
	// после попытки обхода даём паузу: чаще раза в минуту не сканируем
	if e.cfg.WLScan != nil && time.Since(e.wlLast) >= time.Minute {
		if pass := e.cfg.WLScan(ctx); len(pass) > 0 {
			e.wlLast = time.Now()
			Logf("🔎 к Cloudflare сквозь белые списки проходят имена (SNI): %s — пробую подключиться с ними", strings.Join(pass, ", "))
			return WhitelistStrategies(pass), false
		}
		e.wlLast = time.Now().Add(-45 * time.Second) // ничего не прошло: следующий скан через ~15 с
	}
	e.sleepOrNet(ctx, 20*time.Second)
	return nil, true
}
