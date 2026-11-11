package hydra

import (
	"fmt"
	"net"
	"sync"
	"sync/atomic"
	"syscall"
)

// UDPRelay — локальный «переходник» для QUIC. Клиент MASQUE шлёт датаграммы на
// 127.0.0.1, а переходник сам общается с сервером Cloudflare: перед первым
// настоящим пакетом он отправляет фейки с малым TTL (как у Zarp), и только
// потом пропускает рукопожатие. Так обходим DPI, не трогая код клиента MASQUE.

// FakeSpec описывает фейковые пакеты: Payloads шлются по очереди с TTL.
type FakeSpec struct {
	Payloads [][]byte
	TTL      int // 0 — отправлять с обычным TTL
	// PerInit — «мусор» перед каждым рукопожатием WireGuard (сообщение типа 1).
	PerInit func() [][]byte
	// UseReserved: в каждом сообщении WireGuard байты 1–3 заменяются на Reserved (как у клиентов WARP,
	// они берутся из client_id аккаунта); от сервера эти байты обнуляются обратно.
	UseReserved bool
	Reserved    [3]byte
	// CountWG: считать сообщения WireGuard по типам (для диагностики).
	CountWG bool
}

type UDPRelay struct {
	local  *net.UDPConn
	remote *net.UDPAddr
	fake   FakeSpec

	mu    sync.Mutex
	peers map[string]*net.UDPConn
	once  sync.Once

	out, in [6]int32 // сообщения WireGuard по типам: 1 init, 2 ответ, 3 cookie, 4 данные, 5 прочее
}

func wgType(p []byte) int {
	if len(p) >= 4 && p[0] >= 1 && p[0] <= 4 && p[1] == 0 && p[2] == 0 && p[3] == 0 {
		return int(p[0])
	}
	return 5
}

// Stats — сколько сообщений WireGuard прошло через переходник (для отчёта).
func (r *UDPRelay) Stats() string {
	g := func(a *[6]int32, i int) int32 { return atomic.LoadInt32(&a[i]) }
	return fmt.Sprintf("к серверу: рукопожатий %d, данных %d; от сервера: ответов %d, данных %d, cookie %d, прочих %d",
		g(&r.out, 1), g(&r.out, 4), g(&r.in, 2), g(&r.in, 4), g(&r.in, 3), g(&r.in, 5))
}

func StartUDPRelay(remote *net.UDPAddr, fake FakeSpec) (*UDPRelay, error) {
	local, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		return nil, err
	}
	r := &UDPRelay{local: local, remote: remote, fake: fake, peers: map[string]*net.UDPConn{}}
	go r.loop()
	return r, nil
}

func (r *UDPRelay) Addr() *net.UDPAddr { return r.local.LocalAddr().(*net.UDPAddr) }

func (r *UDPRelay) Close() {
	r.once.Do(func() {
		r.local.Close()
		r.mu.Lock()
		for _, c := range r.peers {
			c.Close()
		}
		r.mu.Unlock()
	})
}

func (r *UDPRelay) loop() {
	buf := make([]byte, 65535)
	for {
		n, from, err := r.local.ReadFromUDP(buf)
		if err != nil {
			return
		}
		if up := r.peer(from); up != nil {
			pkt := buf[:n]
			if r.fake.PerInit != nil && IsWGInit(pkt) {
				for _, j := range r.fake.PerInit() {
					up.Write(j)
				}
			}
			if r.fake.CountWG {
				atomic.AddInt32(&r.out[wgType(pkt)], 1)
			}
			if r.fake.UseReserved && wgType(pkt) != 5 {
				copy(pkt[1:4], r.fake.Reserved[:])
			}
			up.Write(pkt)
		}
	}
}

// peer возвращает «свой» сокет к серверу для данного клиента (создаёт и
// отправляет фейки при первом обращении).
func (r *UDPRelay) peer(from *net.UDPAddr) *net.UDPConn {
	key := from.String()
	r.mu.Lock()
	defer r.mu.Unlock()
	if c, ok := r.peers[key]; ok {
		return c
	}
	c, err := net.DialUDP("udp", nil, r.remote)
	if err != nil {
		Logf("   ✘ не удалось открыть сокет к %s: %v", r.remote, err)
		return nil
	}
	r.sendFakes(c)
	r.peers[key] = c
	go func() {
		buf := make([]byte, 65535)
		for {
			n, err := c.Read(buf)
			if err != nil {
				return
			}
			pkt := buf[:n]
			if r.fake.UseReserved && len(pkt) >= 4 && pkt[0] >= 1 && pkt[0] <= 4 {
				pkt[1], pkt[2], pkt[3] = 0, 0, 0
			}
			if r.fake.CountWG {
				atomic.AddInt32(&r.in[wgType(pkt)], 1)
			}
			r.local.WriteToUDP(pkt, from)
		}
	}()
	return c
}

func (r *UDPRelay) sendFakes(c *net.UDPConn) {
	if len(r.fake.Payloads) == 0 {
		return
	}
	if r.fake.TTL > 0 {
		if err := setTTL(c, r.fake.TTL); err != nil {
			Logf("   ⚠ не удалось выставить TTL=%d (%v) — фейки не отправляю", r.fake.TTL, err)
			return
		}
	}
	total := 0
	for _, p := range r.fake.Payloads {
		if _, err := c.Write(p); err == nil {
			total += len(p)
		}
	}
	if r.fake.TTL > 0 {
		setTTL(c, 64)
	}
	Logf("   фейковых пакетов: %d, %d байт, TTL=%d → %s", len(r.fake.Payloads), total, r.fake.TTL, r.remote)
}

func setTTL(c *net.UDPConn, ttl int) error {
	rc, err := c.SyscallConn()
	if err != nil {
		return err
	}
	v6 := c.RemoteAddr().(*net.UDPAddr).IP.To4() == nil
	var serr error
	err = rc.Control(func(fd uintptr) {
		if v6 {
			serr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IPV6, syscall.IPV6_UNICAST_HOPS, ttl)
		} else {
			serr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IP, syscall.IP_TTL, ttl)
		}
	})
	if err != nil {
		return err
	}
	return serr
}
