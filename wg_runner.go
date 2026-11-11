//go:build usque

package hydra

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

// Транспорт WireGuard на wireguard-go. «Сетевая карта» (tun.Device) — в памяти:
// пакеты берутся из PacketDevice движка и туда же возвращаются, поэтому
// проверки дата-центра и TCP работают точно так же, как для MASQUE.

type memTun struct {
	dev    PacketDevice
	mtu    int
	events chan tun.Event
	once   sync.Once
}

func (m *memTun) File() *os.File { return nil }

func (m *memTun) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	n, err := m.dev.ReadPacket(bufs[0][offset:])
	if err != nil {
		return 0, err
	}
	sizes[0] = n
	return 1, nil
}

func (m *memTun) Write(bufs [][]byte, offset int) (int, error) {
	for i, b := range bufs {
		if err := m.dev.WritePacket(b[offset:]); err != nil {
			return i, err
		}
	}
	return len(bufs), nil
}

func (m *memTun) MTU() (int, error)        { return m.mtu, nil }
func (m *memTun) Name() (string, error)    { return "hydra0", nil }
func (m *memTun) Events() <-chan tun.Event { return m.events }
func (m *memTun) BatchSize() int           { return 1 }
func (m *memTun) Close() error {
	m.once.Do(func() { close(m.events) })
	return nil
}

// NewWGRunner создаёт Runner, который держит туннель WireGuard по конфигурации acc.
func NewWGRunner(acc *Account) (Runner, error) {
	if acc == nil || acc.Kind != "wg" {
		return nil, errors.New("нет конфигурации WireGuard")
	}
	if _, err := WGUAPI(acc, "127.0.0.1:1"); err != nil {
		return nil, err
	}
	return func(ctx context.Context, dev PacketDevice, s Strategy) error {
		remote, err := net.ResolveUDPAddr("udp", s.Params["endpoint"])
		if err != nil {
			return fmt.Errorf("адрес %s: %w", s.Params["endpoint"], err)
		}
		// быстрая проверка маршрута
		if c, derr := net.DialUDP("udp", nil, remote); derr != nil {
			Logf("   ✘ нет маршрута до %s: %v", remote, derr)
			return fmt.Errorf("нет маршрута до %s", remote)
		} else {
			c.Close()
		}

		var fk FakeSpec
		sig := s.Params["sig"]
		jc := atoiDefault(s.Params["jc"], 0)
		jmin, jmax := atoiDefault(s.Params["jmin"], 40), atoiDefault(s.Params["jmax"], 70)
		if sig != "" || jc > 0 {
			fk.PerInit = func() [][]byte { return WGPrefix(sig, jc, jmin, jmax) }
			Logf("   пролог перед рукопожатием: сигнатура %q + мусор %d × %d–%d байт", sig, jc, jmin, jmax)
		}
		relay, err := StartUDPRelay(remote, fk)
		if err != nil {
			return err
		}
		defer relay.Close()

		uapi, err := WGUAPI(acc, relay.Addr().String())
		if err != nil {
			return err
		}
		mt := &memTun{dev: dev, mtu: 1280, events: make(chan tun.Event, 4)}
		logger := &device.Logger{
			Verbosef: func(format string, args ...any) {
				if l := fmt.Sprintf(format, args...); strings.Contains(l, "andshake") && !strings.Contains(l, "Routine:") {
					Logf("   wg: %s", l)
				}
			},
			Errorf: func(format string, args ...any) {
				Logf("   wg ✘ %s", fmt.Sprintf(format, args...))
			},
		}
		d := device.NewDevice(mt, conn.NewDefaultBind(), logger)
		defer d.Close()
		if err := d.IpcSet(uapi); err != nil {
			return err
		}
		if err := d.Up(); err != nil {
			return err
		}
		Logf("   WireGuard запущен, жду рукопожатие…")
		<-ctx.Done()
		return ctx.Err()
	}, nil
}
