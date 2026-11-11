package hydra

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
)

// WireGuard-транспорт: для обычных конфигураций WARP (как у wgcf) и для своих.
// Адреса WireGuard-серверов Cloudflare (162.159.192/193/195.x, 188.114.96-99.x)
// относятся к другим префиксам, чем MASQUE (162.159.198.x), и многие провайдеры
// маршрутизируют их в другие дата-центры (например, FRA вместо DME).

// IsWGInit: это начало рукопожатия WireGuard (сообщение типа 1, 148 байт)?
func IsWGInit(p []byte) bool {
	return len(p) == 148 && p[0] == 1 && p[1] == 0 && p[2] == 0 && p[3] == 0
}

// GenJunk — «мусорные» пакеты случайной длины, которые отправляются перед
// рукопожатием (как Jc/Jmin/Jmax в AmneziaWG). Настоящий сервер WireGuard их
// просто отбрасывает, а оборудование провайдера теряет сигнатуру WireGuard.
func GenJunk(count, minLen, maxLen int) [][]byte {
	if count <= 0 {
		return nil
	}
	if minLen < 1 {
		minLen = 40
	}
	if maxLen < minLen {
		maxLen = minLen + 30
	}
	out := make([][]byte, count)
	for i := range out {
		r := make([]byte, 1)
		rand.Read(r)
		n := minLen + int(r[0])%(maxLen-minLen+1)
		b := make([]byte, n)
		rand.Read(b)
		if b[0] >= 1 && b[0] <= 4 { // не похоже на сообщения WireGuard
			b[0] = 0xA5
		}
		out[i] = b
	}
	return out
}

func b64ToHex(s string) (string, error) {
	b, err := base64.StdEncoding.DecodeString(strings.TrimSpace(s))
	if err != nil || len(b) != 32 {
		return "", errors.New("ключ WireGuard должен быть 32 байта в base64")
	}
	return hex.EncodeToString(b), nil
}

// WGUAPI строит конфигурацию в формате UAPI wireguard-go; endpoint — адрес
// локального переходника.
func WGUAPI(acc *Account, endpoint string) (string, error) {
	priv, err := b64ToHex(acc.PrivateKey)
	if err != nil {
		return "", fmt.Errorf("PrivateKey: %w", err)
	}
	pub, err := b64ToHex(acc.PeerPublicKey)
	if err != nil {
		return "", fmt.Errorf("PublicKey: %w", err)
	}
	return "private_key=" + priv + "\npublic_key=" + pub + "\nendpoint=" + endpoint +
		"\npersistent_keepalive_interval=25\nallowed_ip=0.0.0.0/0\nallowed_ip=::/0\n", nil
}

func withMask(a string, bits int) string {
	if strings.Contains(a, "/") {
		return a
	}
	return fmt.Sprintf("%s/%d", a, bits)
}

// WGConfig — обычный файл .conf: его можно вставить в любое приложение WireGuard/AmneziaWG.
func (a *Account) WGConfig() string {
	var addrs []string
	if a.AddrV4 != "" {
		addrs = append(addrs, withMask(a.AddrV4, 32))
	}
	if a.AddrV6 != "" {
		addrs = append(addrs, withMask(a.AddrV6, 128))
	}
	var sb strings.Builder
	sb.WriteString("[Interface]\n")
	fmt.Fprintf(&sb, "PrivateKey = %s\n", a.PrivateKey)
	fmt.Fprintf(&sb, "Address = %s\nDNS = 1.1.1.1, 1.0.0.1\nMTU = 1280\n", strings.Join(addrs, ", "))
	if a.Jc > 0 {
		fmt.Fprintf(&sb, "Jc = %d\nJmin = %d\nJmax = %d\nS1 = 0\nS2 = 0\nH1 = 1\nH2 = 2\nH3 = 3\nH4 = 4\n", a.Jc, a.Jmin, a.Jmax)
	}
	sb.WriteString("\n[Peer]\n")
	fmt.Fprintf(&sb, "PublicKey = %s\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = %s\nPersistentKeepalive = 25\n", a.PeerPublicKey, a.EndpointV4)
	return sb.String()
}

// ParseWGConfig разбирает .conf (WireGuard или AmneziaWG). Из обфускации
// AmneziaWG поддерживаются «мусорные» пакеты Jc/Jmin/Jmax; изменение формата
// пакетов (S1/S2/H1–H4) требует отдельной библиотеки и отвергается.
func ParseWGConfig(text string) (*Account, error) {
	acc := &Account{Kind: "wg", Custom: true, ID: "custom"}
	section := ""
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if i := strings.IndexAny(line, "#;"); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "[") {
			section = strings.ToLower(strings.Trim(line, "[]"))
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k = strings.ToLower(strings.TrimSpace(k))
		v = strings.TrimSpace(v)
		switch section {
		case "interface":
			switch k {
			case "privatekey":
				acc.PrivateKey = v
			case "address":
				for _, a := range strings.Split(v, ",") {
					a = strings.TrimSpace(a)
					ip := strings.Split(a, "/")[0]
					if p := net.ParseIP(ip); p != nil {
						if p.To4() != nil && acc.AddrV4 == "" {
							acc.AddrV4 = ip
						} else if p.To4() == nil && acc.AddrV6 == "" {
							acc.AddrV6 = ip
						}
					}
				}
			case "jc":
				acc.Jc, _ = strconv.Atoi(v)
			case "jmin":
				acc.Jmin, _ = strconv.Atoi(v)
			case "jmax":
				acc.Jmax, _ = strconv.Atoi(v)
			case "s1", "s2":
				if n, _ := strconv.Atoi(v); n != 0 {
					return nil, errors.New("конфигурация меняет формат пакетов AmneziaWG (S1/S2) — это пока не поддерживается; поддерживаются Jc/Jmin/Jmax")
				}
			case "h1", "h2", "h3", "h4":
				if n, _ := strconv.Atoi(v); n != 0 && strconv.Itoa(n) != string(k[1]) {
					return nil, errors.New("конфигурация меняет формат пакетов AmneziaWG (H1–H4) — это пока не поддерживается; поддерживаются Jc/Jmin/Jmax")
				}
			}
		case "peer":
			switch k {
			case "publickey":
				acc.PeerPublicKey = v
			case "endpoint":
				acc.EndpointV4 = v
			}
		}
	}
	if _, err := b64ToHex(acc.PrivateKey); err != nil {
		return nil, errors.New("в [Interface] нет корректного PrivateKey")
	}
	if _, err := b64ToHex(acc.PeerPublicKey); err != nil {
		return nil, errors.New("в [Peer] нет корректного PublicKey")
	}
	if _, _, err := net.SplitHostPort(acc.EndpointV4); err != nil {
		return nil, errors.New("в [Peer] нет корректного Endpoint (хост:порт)")
	}
	if acc.AddrV4 == "" {
		acc.AddrV4 = "172.16.0.2"
	}
	return acc, nil
}

// BuildQUICLike — пакет, похожий на заголовок QUIC Initial (108 байт), как первый
// пакет Варвары в её захвате: длинный заголовок, версия 1, DCID 8 байт, длина 90.
func BuildQUICLike() []byte {
	b := make([]byte, 108)
	rand.Read(b)
	b[0] = 0xC0
	b[1], b[2], b[3], b[4] = 0, 0, 0, 1
	b[5] = 8
	b[14], b[15] = 0, 0
	b[16], b[17] = 0x40, 90
	return b
}

// BuildSTUNLike — пакет, похожий на запрос STUN Binding (20 байт, magic cookie 2112A442).
func BuildSTUNLike() []byte {
	b := make([]byte, 20)
	rand.Read(b)
	b[0], b[1], b[2], b[3] = 0, 1, 0, 0
	b[4], b[5], b[6], b[7] = 0x21, 0x12, 0xA4, 0x42
	return b
}

// WGPrefix — «пролог» перед каждым рукопожатием WireGuard. По захвату Варвары:
// сначала пакет, похожий на QUIC (или STUN), затем несколько пакетов случайной
// длины, затем настоящее рукопожатие. Сервер Cloudflare всё лишнее отбрасывает.
func WGPrefix(sig string, jc, jmin, jmax int) [][]byte {
	var out [][]byte
	switch sig {
	case "quic":
		out = append(out, BuildQUICLike())
	case "stun":
		out = append(out, BuildSTUNLike())
	}
	if sig != "" {
		out = append(out, GenJunk(4, 80, 120)...)
	}
	return append(out, GenJunk(jc, jmin, jmax)...)
}

// Подсети WireGuard-серверов Cloudflare (по данным Варвары). Разные подсети
// по-разному маршрутизируются провайдерами: на одном Wi-Fi 162.159.192.x ведёт в HEL,
// а 188.114.x — во FRA, тогда как MASQUE (162.159.198.x) — в DME.
var wgSubnets = []string{
	"162.159.192", "188.114.97", "188.114.96", "162.159.193", "162.159.195",
	"188.114.98", "188.114.99", "8.34.70", "8.34.146", "8.35.211",
	"8.39.125", "8.39.204", "8.39.214", "8.47.69", "8.6.112",
}

// WGStrategies — способы подключиться по WireGuard: адрес × порт × пролог.
func WGStrategies(acc *Account) []Strategy {
	if acc == nil || acc.Kind != "wg" {
		return nil
	}
	mk := func(ep, sig string, jc, jmin, jmax int, alias string) Strategy {
		p := map[string]string{"endpoint": ep}
		if sig != "" {
			p["sig"] = sig
		}
		if jc > 0 {
			p["jc"] = strconv.Itoa(jc)
			p["jmin"] = strconv.Itoa(jmin)
			p["jmax"] = strconv.Itoa(jmax)
		}
		return Strategy{ID: fmt.Sprintf("wg/%s/%s", ep, alias), Transport: "wg", Params: p}
	}
	// близнец стратегии с reserved-байтами из client_id (так подключаются клиенты WARP)
	rsv := acc.ClientID != "" && !acc.Custom
	mkr := func(ep, sig string, jc, jmin, jmax int, alias string) Strategy {
		s := mk(ep, sig, jc, jmin, jmax, alias+"r")
		s.Params["rsv"] = "1"
		return s
	}
	var out []Strategy
	if acc.Custom {
		// своя конфигурация: сначала ровно как написано, потом тот же адрес с прологом или без него
		out = append(out, mk(acc.EndpointV4, "", acc.Jc, acc.Jmin, acc.Jmax, "cfg"))
		if acc.Jc == 0 {
			out = append(out, mk(acc.EndpointV4, "quic", 3, 41, 78, "q3"))
		} else {
			out = append(out, mk(acc.EndpointV4, "", 0, 0, 0, "plain"))
		}
		return out
	}
	hosts := []string{}
	seen := map[string]bool{}
	add := func(h string) {
		if h != "" && net.ParseIP(h) != nil && !seen[h] {
			seen[h] = true
			hosts = append(hosts, h)
		}
	}
	// 1) адрес из аккаунта и проверенный у Варвары 162.159.192.3 — с разными прологами
	first := []string{hostOnly(acc.EndpointV4), "162.159.192.3"}
	for _, h := range first {
		add(h)
	}
	for _, h := range hosts {
		ep := net.JoinHostPort(h, "2408")
		out = append(out, mk(ep, "quic", 3, 41, 78, "q3"))
		if rsv {
			out = append(out, mkr(ep, "quic", 3, 41, 78, "q3"))
		}
		out = append(out, mk(ep, "stun", 3, 41, 78, "s3"))
		out = append(out, mk(ep, "", 4, 40, 70, "j4"))
		out = append(out, mk(ep, "", 0, 0, 0, "plain"))
		if rsv {
			out = append(out, mkr(ep, "", 0, 0, 0, "plain"))
		}
	}
	// 2) по одному адресу из каждой подсети (разные подсети — разные дата-центры)
	for _, host := range []int{3, 1} {
		for _, sub := range wgSubnets {
			h := fmt.Sprintf("%s.%d", sub, host)
			if seen[h] {
				continue
			}
			seen[h] = true
			out = append(out, mk(net.JoinHostPort(h, "2408"), "quic", 3, 41, 78, "q3"))
			if rsv {
				out = append(out, mkr(net.JoinHostPort(h, "2408"), "quic", 3, 41, 78, "q3"))
			}
		}
	}
	// 3) другие порты: некоторые провайдеры режут именно 2408
	for _, port := range []string{"500", "4500", "1701"} {
		out = append(out, mk(net.JoinHostPort("162.159.192.3", port), "quic", 3, 41, 78, "q3"))
	}
	return out
}

// Interleave перемешивает два списка стратегий пачками по chunk: так запасной
// протокол начинает пробоваться сразу, а не после десятков попыток основного.
func Interleave(a, b []Strategy, chunk int) []Strategy {
	if chunk < 1 {
		chunk = 3
	}
	var out []Strategy
	for len(a) > 0 || len(b) > 0 {
		n := chunk
		if n > len(a) {
			n = len(a)
		}
		out = append(out, a[:n]...)
		a = a[n:]
		n = chunk
		if n > len(b) {
			n = len(b)
		}
		out = append(out, b[:n]...)
		b = b[n:]
	}
	return out
}
