package hydra

import (
	"context"
	"net"
	"time"
)

// Strategy — одна конкретная схема подключения (транспорт + параметры).
// ID должен быть стабильным: по нему Память Гидры копит статистику.
type Strategy struct {
	ID        string
	Transport string
	Params    map[string]string
}

// Quality — результат одной пробы туннеля.
type Quality struct {
	RTT  time.Duration
	Loss float64 // 0..1
}

// Tunnel — живое соединение. Время жизни туннеля НЕ привязано к ctx из Dial:
// ctx ограничивает только установку соединения.
type Tunnel interface {
	Probe(ctx context.Context) (Quality, error)
	// DialContext открывает TCP-соединение к addr через туннель (для SOCKS-входа).
	DialContext(ctx context.Context, network, addr string) (net.Conn, error)
	Done() <-chan struct{} // закрывается, когда туннель умер
	Close() error
}

// Transport — бэкенд (WARP/MASQUE, AmneziaWG, позже свой сервер).
type Transport interface {
	Name() string
	Strategies() []Strategy
	Dial(ctx context.Context, s Strategy) (Tunnel, error)
}
