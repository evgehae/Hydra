package hydra

import (
	"context"
	"io"
	"net"
	"strconv"
	"sync/atomic"
	"testing"
	"time"
)

func (t *fakeTunnel) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	atomic.AddInt32(&t.dials, 1)
	var d net.Dialer
	return d.DialContext(ctx, network, addr)
}

func echoServer(t *testing.T) string {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() { io.Copy(c, c); c.Close() }()
		}
	}()
	return ln.Addr().String()
}

// socksConnect делает рукопожатие SOCKS5 и возвращает соединение и код ответа.
func socksConnect(t *testing.T, proxy, target string) (net.Conn, byte) {
	c, err := net.DialTimeout("tcp", proxy, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	c.SetDeadline(time.Now().Add(2 * time.Second))
	c.Write([]byte{5, 1, 0})
	var r [2]byte
	if _, err := io.ReadFull(c, r[:]); err != nil || r[0] != 5 || r[1] != 0 {
		t.Fatalf("рукопожатие: %v %v", r, err)
	}
	host, ps, _ := net.SplitHostPort(target)
	port, _ := strconv.Atoi(ps)
	req := []byte{5, 1, 0, 1}
	req = append(req, net.ParseIP(host).To4()...)
	req = append(req, byte(port>>8), byte(port))
	c.Write(req)
	var rep [10]byte
	if _, err := io.ReadFull(c, rep[:]); err != nil {
		t.Fatalf("ответ: %v", err)
	}
	return c, rep[1]
}

func TestFrontSwapsTunnels(t *testing.T) {
	echo := echoServer(t)
	front := NewFront()
	addr, err := front.Listen("127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { front.Close() })

	t1, t2 := newFakeTunnel(0), newFakeTunnel(0)

	front.Set(t1)
	c, code := socksConnect(t, addr, echo)
	if code != 0 {
		t.Fatalf("код %d", code)
	}
	c.Write([]byte("ping"))
	buf := make([]byte, 4)
	if _, err := io.ReadFull(c, buf); err != nil || string(buf) != "ping" {
		t.Fatalf("эхо: %q %v", buf, err)
	}
	if atomic.LoadInt32(&t1.dials) != 1 {
		t.Fatal("соединение должно идти через t1")
	}

	front.Set(t2) // «горячая» подмена
	if _, code := socksConnect(t, addr, echo); code != 0 {
		t.Fatalf("код %d", code)
	}
	if atomic.LoadInt32(&t2.dials) != 1 || atomic.LoadInt32(&t1.dials) != 1 {
		t.Fatal("новое соединение должно идти через t2")
	}

	front.Set(nil)
	if _, code := socksConnect(t, addr, echo); code != 3 {
		t.Fatalf("без туннеля ждали код 3, получили %d", code)
	}
}
