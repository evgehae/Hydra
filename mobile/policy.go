package mobile

import (
	"strings"
	"sync"

	hydra "hydra/core"
)

var (
	polMu    sync.Mutex
	polBlock = ""
	polAllow = ""
	polSoft  = false
	polProto = "auto"
	netKey   = "default"
	polSNI   = "" // свой SNI для туннеля MASQUE ("" — по умолчанию)
	polEP    = "" // свой адрес сервера "IP" или "IP:порт" ("" — не задан)
	// netEvents — «сеть сменилась»: движок реагирует сразу, не ожидая очередной пробы.
	netEvents = make(chan struct{}, 1)
)

// SetColoPolicy задаёт запрещённые и (необязательно) единственно разрешённые
// дата-центры Cloudflare: "DME,LED" и "HEL,FRA".
func SetColoPolicy(block, allow string) {
	polMu.Lock()
	polBlock, polAllow = block, allow
	polMu.Unlock()
}

// SetFallback: если все адреса ведут в запрещённый дата-центр — всё равно подключиться.
func SetFallback(on bool) {
	polMu.Lock()
	polSoft = on
	polMu.Unlock()
}

// SetProtocol выбирает протокол: "auto" (оба, запасной подхватывает), "masque" или "wg".
func SetProtocol(p string) {
	polMu.Lock()
	polProto = strings.TrimSpace(p)
	polMu.Unlock()
}

func currentProtocol() string {
	polMu.Lock()
	defer polMu.Unlock()
	return polProto
}

// SetNetKey сообщает ядру, в какой сети телефон ("wifi", "cell"). Смена ключа
// сразу будит движок.
func SetNetKey(k string) {
	k = strings.TrimSpace(k)
	polMu.Lock()
	changed := k != netKey
	netKey = k
	polMu.Unlock()
	if changed {
		select {
		case netEvents <- struct{}{}:
		default:
		}
	}
}

func currentNetKey() string {
	polMu.Lock()
	defer polMu.Unlock()
	return netKey
}

func currentFallback() bool {
	polMu.Lock()
	defer polMu.Unlock()
	return polSoft
}

func currentPolicy() *hydra.ColoPolicy {
	polMu.Lock()
	defer polMu.Unlock()
	return &hydra.ColoPolicy{Block: hydra.ParseColoList(polBlock), Allow: hydra.ParseColoList(polAllow)}
}

// SetCustomSNI переопределяет SNI в TLS-рукопожатии туннеля MASQUE ("" — сброс).
func SetCustomSNI(s string) {
	polMu.Lock()
	polSNI = strings.TrimSpace(s)
	polMu.Unlock()
}

// SetCustomEndpoint задаёт свой адрес сервера MASQUE ("IP" или "IP:порт"): он пробуется первым.
func SetCustomEndpoint(s string) {
	polMu.Lock()
	polEP = strings.TrimSpace(s)
	polMu.Unlock()
}

func currentCustom() (sni, ep string) {
	polMu.Lock()
	defer polMu.Unlock()
	return polSNI, polEP
}
