//go:build usque

package mobile

import (
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"

	hydra "hydra/core"
)

var (
	vpnMu     sync.Mutex
	vpnEngine *hydra.Engine
	vpnMem    *hydra.Memory
	vpnCancel context.CancelFunc
)

// StartTunnel запускает Гидру на TUN-интерфейсе, который создал Android (tunFd).
// Пустая строка — успех, иначе текст ошибки.
func StartTunnel(dir string, tunFd int) string {
	vpnMu.Lock()
	defer vpnMu.Unlock()
	if vpnEngine != nil {
		return "уже запущено"
	}
	macc, _ := hydra.LoadAccount(accountPath(dir))
	wacc, _ := hydra.LoadAccount(wgPath(dir))
	if macc == nil && wacc == nil {
		return "нет аккаунта WARP"
	}
	runners := map[string]hydra.Runner{}
	var strategies []hydra.Strategy
	if macc != nil {
		r, err := hydra.NewMasqueRunner(macc)
		if err != nil {
			return err.Error()
		}
		runners["masque"] = r
	}
	if wacc != nil {
		r, err := hydra.NewWGRunner(wacc)
		if err != nil {
			return err.Error()
		}
		runners["wg"] = r
	}
	var mS, wS []hydra.Strategy
	if macc != nil {
		mS = hydra.MasqueStrategies(macc)
		sni, cep := currentCustom()
		if cep != "" {
			mS = append(hydra.CustomEndpointStrategies(cep), mS...) // свой адрес — первым
		}
		if sni != "" {
			for i := range mS {
				mS[i].Params["sni"] = sni
			}
		}
	}
	if wacc != nil {
		wS = hydra.WGStrategies(wacc)
	}
	switch currentProtocol() {
	case "masque":
		if len(mS) > 0 {
			wS = nil
		}
	case "wg":
		if len(wS) > 0 {
			mS = nil
		}
	}
	strategies = hydra.Interleave(mS, wS, 3)
	runner := func(ctx context.Context, d hydra.PacketDevice, s hydra.Strategy) error {
		r := runners[s.Transport]
		if r == nil {
			return fmt.Errorf("нет транспорта %q", s.Transport)
		}
		return r(ctx, d, s)
	}
	acc := primaryAccount(dir)
	ip := net.ParseIP(strings.Split(acc.AddrV4, "/")[0])
	if ip == nil {
		return "в аккаунте нет IPv4-адреса"
	}
	mem, _ := hydra.LoadMemory(filepath.Join(dir, "memory.json"))
	vpnMem = mem

	cfg := hydra.DefaultEngineConfig()
	cfg.LocalIP = ip
	cfg.Strategies = strategies
	cfg.Runner = runner
	cfg.Policy = currentPolicy()
	cfg.Mem = mem
	cfg.NetKey = currentNetKey
	cfg.NetChanged = netEvents
	cfg.SoftFallback = currentFallback()
	cfg.DropV6 = stripMask(acc.AddrV6) == ""
	cfg.NetAlive = realNetAlive
	cfg.Parallel = currentParallel()

	e := hydra.NewEngine(os.NewFile(uintptr(tunFd), "tun"), cfg)
	ctx, cancel := context.WithCancel(context.Background())
	vpnEngine, vpnCancel = e, cancel
	go func() {
		e.Run(ctx)
		mem.Save()
		vpnMu.Lock()
		if vpnEngine == e {
			vpnEngine, vpnCancel = nil, nil
		}
		vpnMu.Unlock()
	}()
	return ""
}

// StopTunnel останавливает Гидру и закрывает TUN.
func StopTunnel() {
	vpnMu.Lock()
	c, e := vpnCancel, vpnEngine
	vpnMu.Unlock()
	if c != nil {
		c()
	}
	if e != nil {
		e.Close()
	}
}

// EngineStatus: "состояние|стратегия|дата-центр|задержка_мс|сообщение".
// Состояния: off, connecting, up, reconnecting, failed.
func EngineStatus() string {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e == nil {
		return "off||||"
	}
	st := e.Status()
	rx, tx := e.Traffic()
	return fmt.Sprintf("%s|%s|%s|%d|%s|%d|%d", st.State, st.Strategy, st.Colo,
		st.RTT.Milliseconds(), strings.ReplaceAll(st.Message, "|", "/"), rx, tx)
}

// Diagnostics — сводка движка и памяти стратегий для отчёта.
func Diagnostics() string {
	out := ""
	if e := vpnEngine; e != nil {
		out += e.Stats()
	} else {
		out += "движок не запущен\n"
	}
	polMu.Lock()
	nk := netKey
	polMu.Unlock()
	if m := vpnMem; m != nil {
		out += m.Summary(nk, 15)
	}
	return out
}
