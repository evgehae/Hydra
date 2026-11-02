package hydra

import (
	"context"
	"time"
)

// Cause — почему сломалось. Нужен для понятного статуса и точечного лечения.
type Cause int

const (
	CauseUnknown Cause = iota
	CauseNetwork       // сети нет вообще
	CauseDNS
	CauseDPI      // сеть есть, но наш трафик режут
	CauseEndpoint // сеть и DNS в порядке, сервер не отвечает
)

func (c Cause) String() string {
	switch c {
	case CauseNetwork:
		return "нет сети"
	case CauseDNS:
		return "сломан DNS"
	case CauseDPI:
		return "оператор режет трафик (DPI)"
	case CauseEndpoint:
		return "сервер не отвечает"
	}
	return "неизвестно"
}

// Diagnoser определяет причину сбоя (реальная реализация — позже).
type Diagnoser interface {
	Diagnose(ctx context.Context) Cause
}

type nopDiagnoser struct{}

func (nopDiagnoser) Diagnose(context.Context) Cause { return CauseUnknown }

// Event — то, что UI показывает человеку.
type Event struct {
	Kind     string // connecting | connected | degraded | failover | failed
	Strategy string
	Cause    Cause
	Msg      string
	At       time.Time
}
