package hydra

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

const fakeReg = `{"id":"abc","token":"tok","config":{"peers":[{"public_key":"PK","endpoint":{"v4":"162.159.198.1:443","v6":"[2606:4700:103::1]:443","host":"engage.cloudflareclient.com:443"}}],"interface":{"addresses":{"v4":"172.16.0.2","v6":"2606:4700:110::2"}}}}`

func TestRegisterRetriesAcrossRoutes(t *testing.T) {
	var posts int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		switch {
		case req.Method == "POST" && req.URL.Path == "/reg":
			if atomic.AddInt32(&posts, 1) == 1 {
				w.Header().Set("Retry-After", "0")
				http.Error(w, "slow down", http.StatusTooManyRequests)
				return
			}
			w.Write([]byte(fakeReg))
		case req.Method == "PATCH" && req.URL.Path == "/reg/abc":
			if req.Header.Get("Authorization") != "Bearer tok" {
				http.Error(w, "no", http.StatusUnauthorized)
				return
			}
			w.Write([]byte(fakeReg))
		default:
			http.NotFound(w, req)
		}
	}))
	defer srv.Close()

	good := (&net.Dialer{Timeout: time.Second}).DialContext
	bad := func(ctx context.Context, network, addr string) (net.Conn, error) {
		return nil, errors.New("сеть недоступна")
	}
	r := NewRegistrar()
	r.BaseURL = srv.URL
	r.Methods = []string{"direct"}
	r.Dialers = []NamedDialer{{Name: "wifi", Dial: bad}, {Name: "cell", Dial: good}}
	r.Stagger = 10 * time.Millisecond
	r.Backoff = 10 * time.Millisecond
	r.Timeout = 2 * time.Second

	var logs []string
	r.Log = func(s string) { logs = append(logs, s) }

	acc, err := r.Register(context.Background())
	if err != nil {
		t.Fatalf("регистрация не удалась: %v (лог: %v)", err, logs)
	}
	if acc.ID != "abc" || acc.Token != "tok" || acc.EndpointV4 != "162.159.198.1:443" || acc.PrivateKey == "" {
		t.Fatalf("неверный аккаунт: %+v", acc)
	}
	if n := atomic.LoadInt32(&posts); n != 2 {
		t.Fatalf("ждали 2 POST (429, потом успех), получили %d", n)
	}
}

func TestRegisterReportsBlocked(t *testing.T) {
	bad := func(ctx context.Context, network, addr string) (net.Conn, error) {
		return nil, errors.New("connection reset")
	}
	r := NewRegistrar()
	r.BaseURL = "http://127.0.0.1:1"
	r.Methods = []string{"direct"}
	r.Dialers = []NamedDialer{{Name: "wifi", Dial: bad}}
	r.Attempts = 2
	r.Stagger = time.Millisecond
	r.Backoff = time.Millisecond
	_, err := r.Register(context.Background())
	var re *RegError
	if !errors.As(err, &re) || re.Kind != KindBlocked {
		t.Fatalf("ждали ошибку вида blocked, получили %v", err)
	}
}

func TestClassifyKinds(t *testing.T) {
	dnsErr := errors.New("dial tcp: lookup api.cloudflareclient.com on [::1]:53: connection refused")
	if k := classify([]error{dnsErr}).Kind; k != KindDNS {
		t.Fatalf("ждали dns, получили %s", k)
	}
	if k := classify([]error{errors.New("connection reset by peer")}).Kind; k != KindBlocked {
		t.Fatalf("ждали blocked, получили %s", k)
	}
	if k := classify([]error{&protoError{"мусор"}}).Kind; k != KindAPI {
		t.Fatalf("ждали api, получили %s", k)
	}
	re := classify([]error{dnsErr, &httpError{Status: 429, RetryAfter: 3 * time.Second}})
	if re.Kind != KindRateLimited || re.RetryAfter != 3*time.Second {
		t.Fatalf("429 должен перекрывать остальное: %+v", re)
	}
}

func TestAccountExportImportAndStorage(t *testing.T) {
	a := &Account{ID: "id1", Token: "tok1", PrivateKey: "AAAA", EndpointV4: "1.2.3.4:443", Created: time.Unix(1700000000, 0).UTC()}
	got, err := ImportAccount(a.Export())
	if err != nil || got.ID != "id1" || got.Token != "tok1" || got.EndpointV4 != "1.2.3.4:443" {
		t.Fatalf("круг экспорт-импорт: %+v %v", got, err)
	}
	if _, err := ImportAccount("мусор"); err == nil {
		t.Fatal("мусор должен отвергаться")
	}
	if _, err := ImportAccount("hydra1:!!!"); err == nil {
		t.Fatal("повреждённая строка должна отвергаться")
	}

	p := filepath.Join(t.TempDir(), "account.json")
	if acc, err := LoadAccount(p); acc != nil || err != nil {
		t.Fatalf("без файла ждали (nil, nil), получили %v %v", acc, err)
	}
	if err := a.Save(p); err != nil {
		t.Fatal(err)
	}
	back, err := LoadAccount(p)
	if err != nil || back == nil || back.ID != "id1" {
		t.Fatalf("загрузка: %+v %v", back, err)
	}
}

func TestEnsureAccountUsesStored(t *testing.T) {
	p := filepath.Join(t.TempDir(), "account.json")
	if err := (&Account{ID: "x", Token: "y", PrivateKey: "z"}).Save(p); err != nil {
		t.Fatal(err)
	}
	r := NewRegistrar()
	r.Dialers = []NamedDialer{{Name: "none", Dial: func(ctx context.Context, network, addr string) (net.Conn, error) {
		return nil, errors.New("сеть не должна использоваться")
	}}}
	got, err := EnsureAccount(context.Background(), p, r)
	if err != nil || got.ID != "x" {
		t.Fatalf("ждали сохранённый аккаунт, получили %+v %v", got, err)
	}
}

func TestFragConnSplitsFirstWrite(t *testing.T) {
	c1, c2 := net.Pipe()
	defer c1.Close()
	defer c2.Close()
	fc := &fragConn{Conn: c1, at: 3}
	go func() {
		fc.Write([]byte("abcdef"))
		fc.Write([]byte("xyz"))
	}()
	buf := make([]byte, 16)
	var parts []string
	for i := 0; i < 3; i++ {
		n, err := c2.Read(buf)
		if err != nil {
			t.Fatal(err)
		}
		parts = append(parts, string(buf[:n]))
	}
	if parts[0] != "abc" || parts[1] != "def" || parts[2] != "xyz" {
		t.Fatalf("части: %v", parts)
	}
}
