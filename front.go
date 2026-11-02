package hydra

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"strconv"
	"sync"
	"time"
)

// Front — постоянный локальный SOCKS5-вход. Android-часть (hev-socks5-tunnel)
// всегда ходит в один и тот же адрес, а туннель под ним Гидра меняет на лету:
// новые соединения сразу идут через новый туннель.
type Front struct {
	mu          sync.RWMutex
	cur         Tunnel
	ln          net.Listener
	DialTimeout time.Duration
}

func NewFront() *Front { return &Front{DialTimeout: 10 * time.Second} }

// Set подставляет активный туннель (nil — туннеля нет).
func (f *Front) Set(t Tunnel) {
	f.mu.Lock()
	f.cur = t
	f.mu.Unlock()
}

func (f *Front) tunnel() Tunnel {
	f.mu.RLock()
	defer f.mu.RUnlock()
	return f.cur
}

// Listen начинает слушать addr (например "127.0.0.1:0") и возвращает реальный адрес.
func (f *Front) Listen(addr string) (string, error) {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return "", err
	}
	f.ln = ln
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go f.handle(c)
		}
	}()
	return ln.Addr().String(), nil
}

func (f *Front) Close() error {
	if f.ln != nil {
		return f.ln.Close()
	}
	return nil
}

func socksReply(c net.Conn, code byte) error {
	_, err := c.Write([]byte{5, code, 0, 1, 0, 0, 0, 0, 0, 0})
	return err
}

func (f *Front) handle(c net.Conn) {
	defer c.Close()
	c.SetDeadline(time.Now().Add(10 * time.Second))

	var hdr [2]byte
	if _, err := io.ReadFull(c, hdr[:]); err != nil || hdr[0] != 5 {
		return
	}
	if _, err := io.ReadFull(c, make([]byte, hdr[1])); err != nil {
		return
	}
	if _, err := c.Write([]byte{5, 0}); err != nil {
		return
	}

	var req [4]byte
	if _, err := io.ReadFull(c, req[:]); err != nil || req[0] != 5 {
		return
	}
	var host string
	switch req[3] {
	case 1:
		var b [4]byte
		if _, err := io.ReadFull(c, b[:]); err != nil {
			return
		}
		host = net.IP(b[:]).String()
	case 3:
		var l [1]byte
		if _, err := io.ReadFull(c, l[:]); err != nil {
			return
		}
		b := make([]byte, l[0])
		if _, err := io.ReadFull(c, b); err != nil {
			return
		}
		host = string(b)
	case 4:
		var b [16]byte
		if _, err := io.ReadFull(c, b[:]); err != nil {
			return
		}
		host = net.IP(b[:]).String()
	default:
		socksReply(c, 8)
		return
	}
	var pb [2]byte
	if _, err := io.ReadFull(c, pb[:]); err != nil {
		return
	}
	port := binary.BigEndian.Uint16(pb[:])

	if req[1] != 1 { // пока только CONNECT; UDP ASSOCIATE — следующим шагом
		socksReply(c, 7)
		return
	}
	t := f.tunnel()
	if t == nil {
		socksReply(c, 3) // network unreachable
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), f.DialTimeout)
	up, err := t.DialContext(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(int(port))))
	cancel()
	if err != nil {
		socksReply(c, 5)
		return
	}
	defer up.Close()
	c.SetDeadline(time.Time{})
	if socksReply(c, 0) != nil {
		return
	}
	pipe(c, up)
}

func pipe(a, b net.Conn) {
	done := make(chan struct{}, 2)
	cp := func(dst, src net.Conn) {
		io.Copy(dst, src)
		if cw, ok := dst.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		} else {
			dst.Close()
		}
		done <- struct{}{}
	}
	go cp(a, b)
	go cp(b, a)
	<-done
	<-done
}
