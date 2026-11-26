package hydra

import "sync/atomic"

// Семейство адресов, по которым Гидра ищет путь до Cloudflare:
//   auto — как раньше: пробуем всё, IPv6 пропускаем, если его нет;
//   v4   — только IPv4;
//   v6   — только IPv6 (если рабочих IPv6-путей нет совсем, откатываемся на IPv4, чтобы не остаться без VPN);
//   both — IPv4 и IPv6 вместе, IPv6 пробуем первым.
var ipMode atomic.Value // string

// SetIPMode задаёт режим: "auto", "v4", "v6", "both".
func SetIPMode(m string) {
	switch m {
	case "v4", "v6", "both":
		ipMode.Store(m)
	default:
		ipMode.Store("auto")
	}
}

func curIPMode() string {
	m, _ := ipMode.Load().(string)
	if m == "" {
		return "auto"
	}
	return m
}

// ipModeFilter оставляет стратегии нужного семейства. Никогда не возвращает пустой список, если на входе он не пуст.
func ipModeFilter(list []Strategy) []Strategy {
	mode := curIPMode()
	if mode != "v4" && mode != "v6" {
		return list
	}
	want6 := mode == "v6"
	var out []Strategy
	for _, s := range list {
		if isV6Strategy(s) == want6 {
			out = append(out, s)
		}
	}
	if len(out) == 0 { // нужного семейства нет совсем — лучше работать по другому, чем остаться без VPN
		return list
	}
	return out
}

// ipModeBonus сдвигает порядок: в режимах v6 и both IPv6-пути идут первыми.
func ipModeBonus(s Strategy) float64 {
	switch curIPMode() {
	case "v6":
		if isV6Strategy(s) {
			return 0.4
		}
	case "both":
		if isV6Strategy(s) {
			return 0.15
		}
	}
	return 0
}
