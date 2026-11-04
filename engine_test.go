package hydra

import (
	"context"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type fakeTun struct {
	rd   chan []byte
	wr   chan []byte
	done chan struct{}
	once sync.Once
}

func newFakeTun() *fakeTun {
	return &fakeTun{rd: make(chan []byte, 16), wr: make(chan []byte, 64), done: make(chan struct{})}
}
func (f *fakeTun) Read(p []byte) (int, error) {
	select {
	case b := <-f.rd:
		return copy(p, b), nil
	case <-f.done:
		return 0, io.EOF
	}
}
func (f *fakeTun) Write(p []byte) (int, error) {
	select {
	case f.wr <- append([]byte(nil), p...):
	default:
	}
	return len(p), nil
}
func (f *fakeTun) Close() error { f.once.Do(func() { close(f.done) }); return nil }

// fakeRunner изображает туннель: отвечает на пробы кодом дата-центра из
// параметров стратегии; "dieAfter" — через сколько мс перестать отвечать;
// "dead" — не отвечать вовсе.
func fakeRunner(started *int32) Runner {
	return func(ctx context.Context, dev PacketDevice, s Strategy) error {
		atomic.AddInt32(started, 1)
		t0 := time.Now()
		buf := make([]byte, 2048)
		for {
			n, err := dev.ReadPacket(buf)
			if err != nil {
				return nil
			}
			if s.Params["dead"] == "1" {
				continue
			}
			if d := s.Params["dieAfter"]; d != "" {
				ms := 0
				for _, c := range d {
					ms = ms*10 + int(c-'0')
				}
				if time.Since(t0) > time.Duration(ms)*time.Millisecond {
					continue
				}
			}
			switch buf[9] {
			case 17: // UDP — проба дата-центра
				dev.WritePacket(buildColoReply(append([]byte(nil), buf[:n]...), s.Params["colo"]))
			case 6: // TCP — проба SYN (RST и прочее игнорируем)
				if s.Params["notcp"] != "1" && buf[ihlOf(buf)+13] == 0x02 {
					dev.WritePacket(buildSynAck(append([]byte(nil), buf[:n]...)))
				}
			}
		}
	}
}

func ihlOf(b []byte) int { return int(b[0]&0x0f) * 4 }

func testEngine(t *testing.T, ss []Strategy, policy *ColoPolicy, tcpCheck bool) (*Engine, context.CancelFunc, *int32) {
	var started int32
	cfg := DefaultEngineConfig()
	cfg.LocalIP = net.ParseIP("172.16.0.2")
	cfg.Strategies = ss
	cfg.Runner = fakeRunner(&started)
	cfg.Policy = policy
	cfg.ProbeEvery = 40 * time.Millisecond
	cfg.UpTimeout = 600 * time.Millisecond
	cfg.BadProbes = 2
	cfg.TCPCheck = tcpCheck
	cfg.TCPTimeout = 150 * time.Millisecond
	e := NewEngine(newFakeTun(), cfg)
	ctx, cancel := context.WithCancel(context.Background())
	go e.Run(ctx)
	return e, cancel, &started
}

func waitStatus(t *testing.T, e *Engine, what string, ok func(Status) bool) Status {
	t.Helper()
	deadline := time.Now().Add(6 * time.Second)
	for time.Now().Before(deadline) {
		if st := e.Status(); ok(st) {
			return st
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("не дождались: %s; статус %+v", what, e.Status())
	return Status{}
}

func TestEngineSkipsBlockedColo(t *testing.T) {
	ss := []Strategy{
		{ID: "moscow", Transport: "masque", Params: map[string]string{"colo": "DME"}},
		{ID: "helsinki", Transport: "masque", Params: map[string]string{"colo": "HEL"}},
	}
	e, cancel, _ := testEngine(t, ss, DefaultColoPolicy(), false)
	defer cancel()
	st := waitStatus(t, e, "up через HEL", func(s Status) bool { return s.State == "up" && s.Colo == "HEL" })
	if st.Strategy != "helsinki" {
		t.Fatalf("ждали стратегию helsinki, получили %q", st.Strategy)
	}
}

func TestEngineFailsOverWhenTunnelDies(t *testing.T) {
	ss := []Strategy{
		{ID: "a", Transport: "masque", Params: map[string]string{"colo": "HEL", "dieAfter": "250"}},
		{ID: "b", Transport: "masque", Params: map[string]string{"colo": "FRA"}},
	}
	e, cancel, started := testEngine(t, ss, DefaultColoPolicy(), false)
	defer cancel()
	waitStatus(t, e, "up через a", func(s Status) bool { return s.State == "up" && s.Strategy == "a" })
	st := waitStatus(t, e, "переход на b", func(s Status) bool { return s.State == "up" && s.Strategy == "b" })
	if st.Colo != "FRA" || atomic.LoadInt32(started) < 2 {
		t.Fatalf("неверное состояние после сбоя: %+v", st)
	}
}

func TestEngineReportsFailureWhenEverythingBlocked(t *testing.T) {
	ss := []Strategy{
		{ID: "a", Transport: "masque", Params: map[string]string{"colo": "DME"}},
		{ID: "b", Transport: "masque", Params: map[string]string{"dead": "1"}},
	}
	e, cancel, _ := testEngine(t, ss, DefaultColoPolicy(), false)
	defer cancel()
	waitStatus(t, e, "state=failed", func(s Status) bool { return s.State == "failed" })
}

func TestEngineRequiresRealTCP(t *testing.T) {
	ss := []Strategy{
		{ID: "udp-only", Transport: "masque", Params: map[string]string{"colo": "HEL", "notcp": "1"}},
		{ID: "full", Transport: "masque", Params: map[string]string{"colo": "FRA"}},
	}
	e, cancel, _ := testEngine(t, ss, DefaultColoPolicy(), true)
	defer cancel()
	st := waitStatus(t, e, "up через full", func(s Status) bool { return s.State == "up" && s.Strategy == "full" })
	if st.Colo != "FRA" {
		t.Fatalf("неверный дата-центр: %+v", st)
	}
}

func TestEngineReactsToNetworkChange(t *testing.T) {
	ss := []Strategy{
		{ID: "a", Transport: "masque", Params: map[string]string{"colo": "HEL"}},
		{ID: "b", Transport: "masque", Params: map[string]string{"colo": "FRA"}},
	}
	var started int32
	cfg := DefaultEngineConfig()
	cfg.LocalIP = net.ParseIP("172.16.0.2")
	cfg.Strategies = ss
	cfg.Runner = fakeRunner(&started)
	cfg.Policy = DefaultColoPolicy()
	cfg.ProbeEvery = time.Hour // сам не заметит — только по сигналу
	cfg.UpTimeout = 600 * time.Millisecond
	cfg.TCPCheck = false
	changed := make(chan struct{}, 1)
	cfg.NetChanged = changed
	e := NewEngine(newFakeTun(), cfg)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go e.Run(ctx)

	waitStatus(t, e, "up", func(s Status) bool { return s.State == "up" })
	before := atomic.LoadInt32(&started)
	changed <- struct{}{}
	deadline := time.Now().Add(3 * time.Second)
	for atomic.LoadInt32(&started) <= before && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if atomic.LoadInt32(&started) <= before {
		t.Fatal("после смены сети переподключения не произошло")
	}
}
