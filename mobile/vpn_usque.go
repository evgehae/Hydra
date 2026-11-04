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
	acc, err := hydra.LoadAccount(accountPath(dir))
	if err != nil || acc == nil {
		return "нет аккаунта WARP"
	}
	runner, err := hydra.NewMasqueRunner(acc)
	if err != nil {
		return err.Error()
	}
	ip := net.ParseIP(strings.Split(acc.AddrV4, "/")[0])
	if ip == nil {
		return "в аккаунте нет IPv4-адреса"
	}
	mem, _ := hydra.LoadMemory(filepath.Join(dir, "memory.json"))

	cfg := hydra.DefaultEngineConfig()
	cfg.LocalIP = ip
	cfg.Strategies = hydra.MasqueStrategies(acc)
	cfg.Runner = runner
	cfg.Policy = currentPolicy()
	cfg.Mem = mem
	cfg.NetKey = currentNetKey
	cfg.NetChanged = netEvents
	cfg.SoftFallback = currentFallback()

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
	return fmt.Sprintf("%s|%s|%s|%d|%s", st.State, st.Strategy, st.Colo,
		st.RTT.Milliseconds(), strings.ReplaceAll(st.Message, "|", "/"))
}
