package hydra

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

type fakeTunnel struct {
	done  chan struct{}
	once  sync.Once
	dials int32
}

func newFakeTunnel(dieAfter time.Duration) *fakeTunnel {
	t := &fakeTunnel{done: make(chan struct{})}
	if dieAfter > 0 {
		time.AfterFunc(dieAfter, func() { t.Close() })
	}
	return t
}
func (t *fakeTunnel) Probe(context.Context) (Quality, error) { return Quality{RTT: 10 * time.Millisecond}, nil }
func (t *fakeTunnel) Done() <-chan struct{}                  { return t.done }
func (t *fakeTunnel) Close() error                           { t.once.Do(func() { close(t.done) }); return nil }

type fakeTransport struct {
	strategies []Strategy
	dial       func(ctx context.Context, s Strategy) (Tunnel, error)
}

func (f *fakeTransport) Name() string                { return "fake" }
func (f *fakeTransport) Strategies() []Strategy      { return f.strategies }
func (f *fakeTransport) Dial(ctx context.Context, s Strategy) (Tunnel, error) { return f.dial(ctx, s) }

func fastCfg() Config {
	c := DefaultConfig()
	c.Stagger = 50 * time.Millisecond
	c.ProbeEvery = 20 * time.Millisecond
	return c
}

func TestRaceWinnerAndMemory(t *testing.T) {
	ft := &fakeTransport{
		strategies: []Strategy{{ID: "bad", Transport: "fake"}, {ID: "slow", Transport: "fake"}, {ID: "good", Transport: "fake"}},
		dial: func(ctx context.Context, s Strategy) (Tunnel, error) {
			switch s.ID {
			case "bad":
				return nil, errors.New("blocked")
			case "slow":
				select {
				case <-time.After(2 * time.Second):
					return newFakeTunnel(0), nil
				case <-ctx.Done():
					return nil, ctx.Err()
				}
			}
			time.Sleep(50 * time.Millisecond)
			return newFakeTunnel(0), nil
		},
	}
	mem, _ := LoadMemory("")
	o := New(fastCfg(), mem, []Transport{ft}, nil)

	t0 := time.Now()
	tun, s, err := o.race(context.Background(), "wifi:home", "")
	if err != nil || s.ID != "good" || time.Since(t0) > time.Second {
		t.Fatalf("ожидали good быстро, получили %v %v %v", s.ID, err, time.Since(t0))
	}
	tun.Close()

	// второй раз память должна поставить good первым
	if first := o.candidates("wifi:home", "")[0].ID; first != "good" {
		t.Fatalf("память не подняла good, первый: %s", first)
	}
	// в другой сети порядок исходный
	if first := o.candidates("cell:other", "")[0].ID; first != "bad" {
		t.Fatalf("в чужой сети память не должна влиять, первый: %s", first)
	}
}

func TestFailoverToStandby(t *testing.T) {
	ft := &fakeTransport{
		strategies: []Strategy{{ID: "A", Transport: "fake"}, {ID: "B", Transport: "fake"}},
		dial: func(ctx context.Context, s Strategy) (Tunnel, error) {
			if s.ID == "A" {
				return newFakeTunnel(150 * time.Millisecond), nil // A умирает
			}
			return newFakeTunnel(0), nil
		},
	}
	mem, _ := LoadMemory("")
	o := New(fastCfg(), mem, []Transport{ft}, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	go o.Run(ctx, func() string { return "wifi:home" })

	var got []string
	for {
		select {
		case e := <-o.Events():
			got = append(got, e.Kind+":"+e.Strategy)
			if e.Kind == "failover" {
				if e.Strategy != "B" {
					t.Fatalf("резерв должен быть B, события: %v", got)
				}
				return
			}
		case <-ctx.Done():
			t.Fatalf("failover не случился, события: %v", got)
		}
	}
}
