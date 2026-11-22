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
	"time"

	hydra "hydra/core"
)

var (
	vpnMu     sync.Mutex
	vpnEngine *hydra.Engine
	vpnMem    *hydra.Memory
	vpnWG     *hydra.WGPool
	journalOnce sync.Once
	vpnCancel context.CancelFunc
)

// StartTunnel запускает Гидру на TUN-интерфейсе, который создал Android (tunFd).
// Пустая строка — успех, иначе текст ошибки.
func StartTunnel(dir string, tunFd int) string {
	vpnMu.Lock()
	defer vpnMu.Unlock()
	journalOnce.Do(func() { hydra.SetJournalFile(filepath.Join(dir, "journal.log")) })
	if vpnEngine != nil {
		return "уже запущено"
	}
	macc, _ := hydra.LoadAccount(accountPath(dir))
	wacc, _ := hydra.LoadAccount(wgPath(dir))
	wacc2, _ := hydra.LoadAccount(wg2Path(dir))
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
	var wgp *hydra.WGPool
	if wacc != nil {
		accs := []*hydra.Account{wacc}
		if wacc2 != nil && wacc2.Kind == "wg" {
			accs = append(accs, wacc2) // второй ключ: резерв WireGuard не мешает основной сессии
		}
		wgp = hydra.NewWGPool(accs...)
		r, err := hydra.NewWGPoolRunner(wgp)
		if err != nil {
			return err.Error()
		}
		runners["wg"] = r
	}
	vpnWG = wgp
	var mS, wS []hydra.Strategy
	if macc != nil {
		mS = hydra.MasqueStrategies(macc)
		sni, cep := currentCustom()
		if cep != "" {
			mS = append(hydra.CustomEndpointStrategies(cep), mS...) // свой адрес — первым
		}
		if sni != "" {
			// свой SNI добавляется как дополнительные стратегии (первыми), а не подменяет все: так
			// остальное многообразие параметров, которым Гидра учится, не пропадает
			n := 8
			if n > len(mS) {
				n = len(mS)
			}
			var extra []hydra.Strategy
			for _, s0 := range mS[:n] {
				q := map[string]string{}
				for k, v := range s0.Params {
					q[k] = v
				}
				q["sni"] = sni
				extra = append(extra, hydra.Strategy{ID: s0.ID + "@" + sni, Transport: s0.Transport, Params: q})
			}
			mS = append(extra, mS...)
		}
	}
	if wacc != nil {
		wS = hydra.WGStrategies(wacc)
	}
	onlyMasque := currentProtocol() == "masque" && len(mS) > 0
	onlyWG := currentProtocol() == "wg" && len(wS) > 0
	allow := func(s hydra.Strategy) bool {
		return !(onlyMasque && s.Transport != "masque") && !(onlyWG && s.Transport != "wg")
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
	if mem != nil {
		mem.SetBandit(true)
	}
	// общая база подсказок (priors.json), если приложение её скачало
	if b, err := os.ReadFile(filepath.Join(dir, "priors.json")); err == nil {
		_ = hydra.SetRemotePriors(b)
	}

	cfg := hydra.DefaultEngineConfig()
	cfg.LocalIP = ip
	cfg.Strategies = strategies
	cfg.Runner = runner
	cfg.Policy = currentPolicy()
	cfg.Mem = mem
	cfg.NetKey = currentNetKey
	cfg.NetChanged = netEvents
	cfg.SoftFallback = currentFallback()
	cfg.DropV6 = stripMask(acc.AddrV6) == "" || !currentIPv6()
	cfg.Rotate = true
	cfg.ServiceGate = currentGate()
	cfg.UpTimeout = time.Duration(currentUpTimeout()) * time.Millisecond
	cfg.NetAlive = realNetAlive
	cfg.Allow = allow
	cfg.NetState = realNetState
	cfg.WLScan = realWLScan
	cfg.CanRun = func(s hydra.Strategy) bool { return wgp.CanRun(s) } // wgp может быть nil: метод это учитывает
	cfg.Parallel = currentParallel()

	e := hydra.NewEngine(os.NewFile(uintptr(tunFd), "tun"), cfg)
	ctx, cancel := context.WithCancel(context.Background())
	vpnEngine, vpnCancel = e, cancel
	go func() {
		defer func() {
			if r := recover(); r != nil { // паника движка не должна ронять приложение: служба поднимет его заново
				hydra.Logf("💥 паника движка: %v", r)
			}
			mem.Save()
			vpnMu.Lock()
			if vpnEngine == e {
				vpnEngine, vpnCancel = nil, nil
			}
			vpnMu.Unlock()
		}()
		e.Run(ctx)
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
	polMu.Lock()
	nk := netKey
	polMu.Unlock()
	if e := vpnEngine; e != nil {
		out += e.Stats()
		out += e.PoolSummary(nk)
		out += vpnWG.Info()
		out += vpnMem.Reasons(nk)
	} else {
		out += "движок не запущен\n"
	}
	out += netStateInfo()
	if m := vpnMem; m != nil {
		out += m.Summary(nk, 15)
		out += m.FlowInfo(nk)
		out += "вердикт по сети: " + m.Verdict(nk) + "\n"
		out += "🧠 что Гидра знает об этой сети (" + nk + "): какие сервисы доходят через какие стратегии\n" + m.ServiceMatrix(nk)
		if e := vpnEngine; e != nil {
			if bl := e.BadColoList(nk); len(bl) > 0 {
				out += "  плохие дата-центры (Telegram не доходит): " + strings.Join(bl, ", ") + "\n"
			}
		}
	}
	return out
}

// TestFailover имитирует отказ основного туннеля, чтобы проверить переход на горячий резерв.
func TestFailover() {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e != nil {
		e.TestFailover()
	}
}

// ServiceCheck проверяет через действующий туннель доступность Telegram и других сервисов.
func ServiceCheck() string {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e == nil {
		return "Гидра не запущена\n"
	}
	res := e.ServiceCheck(context.Background())
	if strings.Contains(res, "✘") {
		hydra.Logf("🔎 проверка сервисов через туннель:\n%s", res)
	} else { // всё доступно: одна строка вместо 14, чтобы журнал не забивался и хватало на часы
		lines := strings.Split(strings.TrimSpace(res), "\n")
		hydra.Logf("🔎 сервисы через туннель: %s", lines[len(lines)-1])
	}
	return res
}

// GetJournalFull возвращает журнал из файла (с прошлыми запусками); если файла нет — из памяти.
func GetJournalFull(n int) string {
	if s := hydra.JournalFileTail(n); s != "" {
		return s
	}
	return hydra.JournalText(n)
}


// SpeedTest — оценка качества через поднятый туннель.
func SpeedTest() string {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e == nil {
		return "туннель не подключён"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	return e.SpeedTest(ctx)
}

// ForgetCurrentNet стирает память Гидры о текущей сети (стратегии, придуманное, дата-центры, «карантин»).
// dir — папка приложения. true — память стёрта.
func ForgetCurrentNet(dir string) bool {
	polMu.Lock()
	nk := netKey
	polMu.Unlock()
	if nk == "" {
		return false
	}
	vpnMu.Lock()
	m := vpnMem
	vpnMu.Unlock()
	if m == nil {
		var err error
		m, err = hydra.LoadMemory(filepath.Join(dir, "memory.json"))
		if err != nil || m == nil {
			return false
		}
	}
	m.ForgetNet(nk)
	m.Save()
	return true
}

// NetVerdict — короткий вывод о текущей сети простыми словами (для главного экрана).
func NetVerdict() string {
	polMu.Lock()
	nk := netKey
	polMu.Unlock()
	vpnMu.Lock()
	m := vpnMem
	vpnMu.Unlock()
	if m == nil || nk == "" {
		return ""
	}
	return m.Verdict(nk)
}
