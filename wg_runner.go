//go:build usque

package hydra

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
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

	// Подмена адреса: сервер WARP принимает от аккаунта WireGuard только пакеты с его собственным
	// адресом. Если трафик из TUN идёт с другого адреса (адрес MASQUE-аккаунта), подменяем его
	// на выходе и возвращаем на входе.
	wgAddr []byte
	mu     sync.Mutex
	orig   []byte
}

// fixSum — инкрементальное обновление контрольной суммы (RFC 1624) при замене двух 16-битных слов.
func fixSum(sum uint16, oldW, newW [2]uint16) uint16 {
	s := uint32(^sum) & 0xffff
	for i := 0; i < 2; i++ {
		s += uint32(^oldW[i]) & 0xffff
		s += uint32(newW[i])
	}
	for s>>16 != 0 {
		s = (s & 0xffff) + (s >> 16)
	}
	return ^uint16(s)
}

// rewriteIPv4 заменяет адрес в IPv4-пакете (off 12 — источник, 16 — получатель) и правит контрольные суммы.
func rewriteIPv4(p []byte, off int, na []byte) {
	ihl := int(p[0]&0x0f) * 4
	if ihl < 20 || len(p) < ihl || len(na) != 4 {
		return
	}
	oldW := [2]uint16{binary.BigEndian.Uint16(p[off:]), binary.BigEndian.Uint16(p[off+2:])}
	newW := [2]uint16{binary.BigEndian.Uint16(na), binary.BigEndian.Uint16(na[2:])}
	binary.BigEndian.PutUint16(p[10:], fixSum(binary.BigEndian.Uint16(p[10:]), oldW, newW))
	copy(p[off:off+4], na)
	if binary.BigEndian.Uint16(p[6:])&0x1fff != 0 {
		return // не первый фрагмент: заголовка L4 нет
	}
	switch p[9] {
	case 6: // TCP
		if len(p) >= ihl+18 {
			o := ihl + 16
			binary.BigEndian.PutUint16(p[o:], fixSum(binary.BigEndian.Uint16(p[o:]), oldW, newW))
		}
	case 17: // UDP (контрольная сумма 0 — «не считалась»)
		if len(p) >= ihl+8 {
			o := ihl + 6
			if c := binary.BigEndian.Uint16(p[o:]); c != 0 {
				v := fixSum(c, oldW, newW)
				if v == 0 {
					v = 0xffff
				}
				binary.BigEndian.PutUint16(p[o:], v)
			}
		}
	}
}

func (m *memTun) natOut(p []byte) {
	if m.wgAddr == nil || len(p) < 20 || p[0]>>4 != 4 || bytes.Equal(p[12:16], m.wgAddr) {
		return
	}
	m.mu.Lock()
	if m.orig == nil {
		m.orig = append([]byte(nil), p[12:16]...)
		Logf("   адрес в аккаунте WireGuard %d.%d.%d.%d, а трафик идёт с %d.%d.%d.%d — подменяю",
			m.wgAddr[0], m.wgAddr[1], m.wgAddr[2], m.wgAddr[3], p[12], p[13], p[14], p[15])
	}
	same := bytes.Equal(p[12:16], m.orig)
	m.mu.Unlock()
	if same {
		rewriteIPv4(p, 12, m.wgAddr)
	}
}

func (m *memTun) natIn(p []byte) {
	if m.wgAddr == nil || len(p) < 20 || p[0]>>4 != 4 || !bytes.Equal(p[16:20], m.wgAddr) {
		return
	}
	m.mu.Lock()
	o := m.orig
	m.mu.Unlock()
	if o != nil {
		rewriteIPv4(p, 16, o)
	}
}

func (m *memTun) File() *os.File { return nil }

func (m *memTun) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	n, err := m.dev.ReadPacket(bufs[0][offset:])
	if err != nil {
		return 0, err
	}
	m.natOut(bufs[0][offset : offset+n])
	sizes[0] = n
	return 1, nil
}

func (m *memTun) Write(bufs [][]byte, offset int) (int, error) {
	for i, b := range bufs {
		m.natIn(b[offset:])
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
// WGPool — аккаунты WireGuard. Сервер WARP помнит одну сессию на ключ: второе рукопожатие с тем же ключом
// «уводит» ответы к новому клиенту, и первый туннель замолкает. Поэтому каждый аккаунт держит не более
// одной сессии одновременно; для горячего резерва нужен второй аккаунт.
type WGPool struct {
	mu   sync.Mutex
	accs []*Account
	busy []bool
}

func NewWGPool(accs ...*Account) *WGPool {
	p := &WGPool{}
	for _, a := range accs {
		if a != nil && a.Kind == "wg" {
			p.accs = append(p.accs, a)
		}
	}
	p.busy = make([]bool, len(p.accs))
	return p
}

func (p *WGPool) acquire() (int, *Account, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for i, b := range p.busy {
		if !b {
			p.busy[i] = true
			return i, p.accs[i], true
		}
	}
	return 0, nil, false
}

func (p *WGPool) release(i int) {
	p.mu.Lock()
	p.busy[i] = false
	p.mu.Unlock()
}

// CanRun: для WireGuard — есть ли свободный аккаунт; остальные стратегии ограничений не имеют.
func (p *WGPool) CanRun(s Strategy) bool {
	if p == nil || s.Transport != "wg" {
		return true
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, b := range p.busy {
		if !b {
			return true
		}
	}
	return false
}

// Info — сводка для диагностики.
func (p *WGPool) Info() string {
	if p == nil {
		return ""
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	busy := 0
	for _, b := range p.busy {
		if b {
			busy++
		}
	}
	return fmt.Sprintf("аккаунтов WireGuard: %d, занято сессиями: %d\n", len(p.accs), busy)
}

// NewWGRunner — раннер WireGuard с одним аккаунтом.
func NewWGRunner(acc *Account) (Runner, error) {
	return NewWGPoolRunner(NewWGPool(acc))
}

// NewWGPoolRunner — раннер WireGuard, который берёт свободный аккаунт из пула на время работы сессии.
func NewWGPoolRunner(p *WGPool) (Runner, error) {
	if p == nil || len(p.accs) == 0 {
		return nil, errors.New("нет конфигурации WireGuard")
	}
	if _, err := WGUAPI(p.accs[0], "127.0.0.1:1"); err != nil {
		return nil, err
	}
	return func(ctx context.Context, dev PacketDevice, s Strategy) error {
		ai, acc, got := p.acquire()
		if !got {
			return ErrRunnerBusy
		}
		defer p.release(ai) // выполнится последним: сессия закрыта полностью
		Logf("   аккаунт WireGuard №%d из %d", ai+1, len(p.accs))
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
		if s.Params["rsv"] == "1" {
			rb, derr := base64.StdEncoding.DecodeString(strings.TrimSpace(acc.ClientID))
			if derr != nil || len(rb) != 3 {
				return errors.New("для этой стратегии нужен client_id аккаунта (reserved-байты)")
			}
			fk.UseReserved = true
			copy(fk.Reserved[:], rb)
			Logf("   reserved-байты аккаунта: %v", rb)
		}
		fk.CountWG = true
		relay, err := StartUDPRelay(remote, fk)
		if err != nil {
			return err
		}
		defer relay.Close()

		uapi, err := WGUAPI(acc, relay.Addr().String())
		if err != nil {
			return err
		}
		if st, ok := dev.(interface{ SetStats(func() string) }); ok {
			st.SetStats(relay.Stats) // счётчики сообщений WG попадут в причину сбоя
		}
		mt := &memTun{dev: dev, mtu: 1280, events: make(chan tun.Event, 4)}
		if a4 := net.ParseIP(strings.Split(acc.AddrV4, "/")[0]).To4(); a4 != nil {
			mt.wgAddr = []byte(a4)
		}
		logger := &device.Logger{
			Verbosef: func(format string, args ...any) {
				if l := fmt.Sprintf(format, args...); strings.Contains(l, "andshake") && !strings.Contains(l, "Routine:") {
					Logf("   wg: %s", l)
				}
			},
			Errorf: func(format string, args ...any) {
				l := fmt.Sprintf(format, args...)
				if strings.Contains(l, "TUN device: EOF") {
					return // обычное закрытие сессии, не ошибка
				}
				Logf("   wg ✘ %s", l)
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
