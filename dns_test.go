package hydra

import (
	"context"
	"net"
	"testing"
)

func TestSetSystemDNSRotatesServers(t *testing.T) {
	old := net.DefaultResolver
	defer func() { net.DefaultResolver = old }()

	SetSystemDNS([]string{"127.0.0.1", "мусор", "127.0.0.2", "127.0.0.1"})
	r := net.DefaultResolver
	if !r.PreferGo || r.Dial == nil {
		t.Fatal("резолвер не подменён")
	}
	var got []string
	for i := 0; i < 2; i++ {
		c, err := r.Dial(context.Background(), "udp", "ignored:53")
		if err != nil {
			t.Fatal(err)
		}
		got = append(got, c.RemoteAddr().String())
		c.Close()
	}
	if got[0] != "127.0.0.1:53" || got[1] != "127.0.0.2:53" {
		t.Fatalf("серверы по кругу: %v", got)
	}
}
