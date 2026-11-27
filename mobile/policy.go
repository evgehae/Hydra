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
	polV6    = false // IPv6 через туннель (по умолчанию выключен: IPv4 надёжнее, приложения сразу переходят на него)
	polGate  = true  // проверять Telegram после подключения
	polPar   = 3  // сколько стратегий пробовать одновременно (0/1 — по очереди)
	polSNI   = "" // свой SNI для туннеля MASQUE ("" — по умолчанию)
	polEP    = "" // свой адрес сервера "IP" или "IP:порт" ("" — не задан)
	polStab  = false // режим максимальной стабильности
	polTV    = false // профиль ТВ
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

// SetParallel включает параллельную гонку стратегий и горячий резерв: n — сколько стратегий
// пробовать одновременно (0 или 1 — по очереди, как раньше).
func SetParallel(n int) {
	polMu.Lock()
	polPar = n
	polMu.Unlock()
}

func currentParallel() int {
	polMu.Lock()
	defer polMu.Unlock()
	return polPar
}

// LogLine дописывает строку в журнал Гидры (для результатов диагностики из приложения).
func LogLine(s string) { hydra.Logf("%s", s) }

// SetIPv6 включает или выключает IPv6 через туннель (выключен — приложения сразу получают отказ и идут по IPv4).
func SetIPv6(on bool) {
	polMu.Lock()
	polV6 = on
	polMu.Unlock()
}

func currentIPv6() bool {
	polMu.Lock()
	defer polMu.Unlock()
	return polV6
}

// SetServiceGate: после подключения проверять, доходит ли Telegram, и обходить дата-центры, где он недоступен.
func SetServiceGate(on bool) {
	polMu.Lock()
	polGate = on
	polMu.Unlock()
}

func currentGate() bool {
	polMu.Lock()
	defer polMu.Unlock()
	return polGate
}

// SetStabilityMode: меньше параллелизма, приоритет стабильных WG-стратегий.
func SetStabilityMode(on bool) {
	polMu.Lock()
	polStab = on
	if on && polPar > 2 {
		polPar = 2
	}
	polMu.Unlock()
}

// SetTVProfile: профиль для Android TV / приставок.
func SetTVProfile(on bool) {
	polMu.Lock()
	polTV = on
	if on {
		if polPar > 2 {
			polPar = 2
		}
		polStab = true
	}
	polMu.Unlock()
}

func currentStability() bool {
	polMu.Lock()
	defer polMu.Unlock()
	return polStab
}

func currentTV() bool {
	polMu.Lock()
	defer polMu.Unlock()
	return polTV
}

// SetWGJunk передаёт Jc/Jmin/Jmax из UI в ядро (0 = авто из стратегии).
func SetWGJunk(jc, jmin, jmax int) {
	hydra.SetUserJunk(jc, jmin, jmax)
}

// SetUpTimeoutMs — жёсткий timeout рукопожатия в миллисекундах (1200–3500).
var polUpMs = 2000

func SetUpTimeoutMs(ms int) {
	if ms < 1200 {
		ms = 1200
	}
	if ms > 5000 {
		ms = 5000
	}
	polMu.Lock()
	polUpMs = ms
	polMu.Unlock()
}

func currentUpTimeout() int {
	polMu.Lock()
	defer polMu.Unlock()
	return polUpMs
}

// SetDnsOverrides задаёт карту подмены DNS: строки «домен=ip1,ip2», «*.домен» — с поддоменами.
// Пустая строка выключает подмену. Возвращает число записей.
func SetDnsOverrides(text string) int { return hydra.SetDNSOverrides(text) }

// SetIpMode задаёт семейство адресов для поиска пути: "auto", "v4", "v6", "both".
func SetIpMode(mode string) { hydra.SetIPMode(mode) }

// SetPriors подключает общую базу подсказок (priors.json). Пустая строка — ошибка разбора вернётся текстом.
func SetPriors(data string) string {
	if err := hydra.SetRemotePriors([]byte(data)); err != nil {
		return err.Error()
	}
	return ""
}

// ExportPriors — накопленный опыт этого устройства в формате priors.json (для общей базы).
func ExportPriors() string {
	if vpnMem == nil {
		return "{}"
	}
	return vpnMem.ExportPriors()
}


// SetYouTubeGate: после подключения проверять YouTube (для Android ТВ, где Telegram нет).
func SetYouTubeGate(on bool) {
	polMu.Lock()
	polYTGate = on
	polMu.Unlock()
}

var polYTGate bool

func currentYTGate() bool {
	polMu.Lock()
	defer polMu.Unlock()
	return polYTGate
}
