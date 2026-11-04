package hydra

import (
	"net"
	"testing"
	"time"
)

func TestUDPRelayForwardsAndSendsFakesFirst(t *testing.T) {
	srv, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Close()
	got := make(chan string, 16)
	go func() {
		buf := make([]byte, 2048)
		for {
			n, a, err := srv.ReadFromUDP(buf)
			if err != nil {
				return
			}
			got <- string(buf[:n])
			srv.WriteToUDP([]byte("pong"), a)
		}
	}()

	r, err := StartUDPRelay(srv.LocalAddr().(*net.UDPAddr), FakeSpec{
		Payloads: [][]byte{[]byte("FAKE-A"), []byte("FAKE-B")},
		TTL:      5,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()

	c, err := net.DialUDP("udp", nil, r.Addr())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.Write([]byte("REAL-1"))

	for _, want := range []string{"FAKE-A", "FAKE-B", "REAL-1"} {
		select {
		case p := <-got:
			if p != want {
				t.Fatalf("порядок пакетов: ждали %q, пришло %q", want, p)
			}
		case <-time.After(2 * time.Second):
			t.Fatalf("не дождались %q", want)
		}
	}

	// ответ сервера доходит до клиента
	c.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 64)
	n, err := c.Read(buf)
	if err != nil || string(buf[:n]) != "pong" {
		t.Fatalf("ответ сервера не дошёл: %q %v", buf[:n], err)
	}

	// второй пакет идёт уже без новых фейков
	c.Write([]byte("REAL-2"))
	select {
	case p := <-got:
		if p != "REAL-2" {
			t.Fatalf("после первого пакета фейков быть не должно, пришло %q", p)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("REAL-2 не дошёл")
	}
}

func TestJournal(t *testing.T) {
	JournalClear()
	Logf("привет %d", 1)
	Logf("второй")
	txt := JournalText(0)
	if !(len(txt) > 0) || JournalText(1) == txt {
		t.Fatalf("журнал: %q", txt)
	}
	JournalClear()
	if JournalText(0) != "" {
		t.Fatal("журнал не очистился")
	}
}
