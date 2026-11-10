package mobile

import (
	"net"
	"time"
)

// realNetAlive: есть ли интернет мимо туннеля (приложение исключено из VPN, поэтому проверка честная).
// Достаточно, чтобы ответил любой из нескольких известных адресов.
func realNetAlive() bool {
	targets := []string{"1.1.1.1:443", "8.8.8.8:443", "77.88.8.8:443", "9.9.9.9:443"}
	ch := make(chan bool, len(targets))
	for _, t := range targets {
		go func(t string) {
			c, err := net.DialTimeout("tcp", t, 2500*time.Millisecond)
			if err == nil {
				c.Close()
			}
			ch <- err == nil
		}(t)
	}
	for range targets {
		if <-ch {
			return true
		}
	}
	return false
}
