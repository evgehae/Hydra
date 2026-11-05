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

// WGStrategies — способы подключиться по WireGuard: адрес × порт × «мусор».
func WGStrategies(acc *Account) []Strategy {
	if acc == nil || acc.Kind != "wg" {
		return nil
	}
	mk := func(ep string, jc, jmin, jmax int, alias string) Strategy {
		p := map[string]string{"endpoint": ep}
		if jc > 0 {
			p["jc"] = strconv.Itoa(jc)
			p["jmin"] = strconv.Itoa(jmin)
			p["jmax"] = strconv.Itoa(jmax)
		}
		return Strategy{ID: fmt.Sprintf("wg/%s/%s", ep, alias), Transport: "wg", Params: p}
	}
	var out []Strategy
	if acc.Custom {
		// своя конфигурация: сначала ровно как написано, потом тот же адрес с «мусором» и без
		out = append(out, mk(acc.EndpointV4, acc.Jc, acc.Jmin, acc.Jmax, "cfg"))
		if acc.Jc == 0 {
			out = append(out, mk(acc.EndpointV4, 4, 40, 70, "j4"))
		} else {
			out = append(out, mk(acc.EndpointV4, 0, 0, 0, "plain"))
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
	add(hostOnly(acc.EndpointV4))
	for _, h := range []string{"162.159.192.1", "162.159.193.1", "162.159.195.1",
		"188.114.96.1", "188.114.97.1", "188.114.98.1", "188.114.99.1"} {
		add(h)
	}
	for _, h := range hosts {
		out = append(out, mk(net.JoinHostPort(h, "2408"), 4, 40, 70, "j4"))
	}
	for _, h := range hosts {
		out = append(out, mk(net.JoinHostPort(h, "2408"), 0, 0, 0, "plain"))
	}
	for _, port := range []string{"500", "4500", "1701"} {
		for _, h := range hosts[:2] {
			out = append(out, mk(net.JoinHostPort(h, port), 4, 40, 70, "j4"))
		}
	}
	return out
}
