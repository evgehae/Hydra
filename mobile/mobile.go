// Package mobile — тонкая обвязка для gomobile: то, что видно из Kotlin.
// Только простые типы (строки), чтобы привязка собиралась без сюрпризов.
package mobile

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	hydra "hydra/core"
)

const version = "0.6.0"

// Version проверяет, что Go-ядро собрано и вызывается из Android.
func Version() string {
	cfg := hydra.DefaultConfig()
	return fmt.Sprintf("hydra-core %s (probe %s)", version, cfg.ProbeEvery)
}

// DefaultBlockedColos — запрещённые по умолчанию дата-центры ("DME,LED,...").
func DefaultBlockedColos() string {
	return strings.Join(hydra.DefaultColoPolicy().Block, ",")
}

// NormalizeColos приводит ввод пользователя к виду "DME,LED,FRA".
func NormalizeColos(s string) string {
	return strings.Join(hydra.ParseColoList(s), ",")
}

func init() {
	// Без этого Go на Android не умеет разрешать имена (нет resolv.conf).
	hydra.SetSystemDNS(nil)
	// Строки клиента MASQUE (usque) тоже попадают в журнал приложения.
	log.SetFlags(0)
	log.SetOutput(hydra.JournalWriter{})
}

// GetJournal возвращает последние n строк журнала (0 — все), новые в конце.
func GetJournal(n int) string { return hydra.JournalText(n) }

// ClearJournal очищает журнал.
func ClearJournal() { hydra.JournalClear() }

// SetDNS принимает DNS-серверы текущей сети от Android ("ip1,ip2,...").
func SetDNS(csv string) {
	hydra.SetSystemDNS(strings.Split(csv, ","))
}

func accountPath(dir string) string { return filepath.Join(dir, "account.json") }
func wgPath(dir string) string      { return filepath.Join(dir, "wg.json") }

// AccountID возвращает ID сохранённого аккаунта или "".
func AccountID(dir string) string {
	a, err := hydra.LoadAccount(accountPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return a.ID
}

// RegisterReport регистрирует аккаунт WARP для MASQUE (если его ещё нет). Первая строка
// отчёта: "OK" или "FAIL <вид>", вид: rate_limited | blocked | dns | api | storage.
func RegisterReport(dir string) string { return registerReport(accountPath(dir), false) }

// RegisterWireguardReport создаёт обычную конфигурацию WARP (WireGuard), как wgcf.
func RegisterWireguardReport(dir string) string { return registerReport(wgPath(dir), true) }

func registerReport(path string, wg bool) string {
	if a, err := hydra.LoadAccount(path); err == nil && a != nil {
		return "OK\nуже есть: " + a.ID
	}
	var sb strings.Builder
	r := hydra.NewRegistrar()
	r.WG = wg
	r.Log = func(s string) {
		sb.WriteString(s + "\n")
		hydra.Logf("регистрация: %s", s)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	acc, err := r.Register(ctx)
	if err != nil {
		kind := "blocked"
		var re *hydra.RegError
		if errors.As(err, &re) {
			kind = re.Kind
		}
		return fmt.Sprintf("FAIL %s\n%s%v", kind, sb.String(), err)
	}
	if err := acc.Save(path); err != nil {
		return "FAIL storage\n" + err.Error()
	}
	return "OK\n" + sb.String() + "id: " + acc.ID
}

// DeleteAccount удаляет аккаунт MASQUE (для «Сбросить ключи»).
func DeleteAccount(dir string) { os.Remove(accountPath(dir)) }

// ExportAccount возвращает строку для переноса аккаунта или "".
func ExportAccount(dir string) string {
	a, err := hydra.LoadAccount(accountPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return a.Export()
}

// ImportAccount сохраняет аккаунт из строки; пустой ответ — успех.
func ImportAccount(dir, text string) string {
	a, err := hydra.ImportAccount(text)
	if err != nil {
		return err.Error()
	}
	if err := a.Save(accountPath(dir)); err != nil {
		return err.Error()
	}
	return ""
}

func stripMask(a string) string { return strings.TrimSpace(strings.Split(a, "/")[0]) }

// AccountAddr4 — IPv4-адрес устройства внутри туннеля ("" если аккаунта нет).
func AccountAddr4(dir string) string {
	a := primaryAccount(dir)
	if a == nil {
		return ""
	}
	return stripMask(a.AddrV4)
}

// primaryAccount: аккаунт MASQUE, а если его нет — конфигурация WireGuard.
func primaryAccount(dir string) *hydra.Account {
	if a, err := hydra.LoadAccount(accountPath(dir)); err == nil && a != nil {
		return a
	}
	if a, err := hydra.LoadAccount(wgPath(dir)); err == nil && a != nil {
		return a
	}
	return nil
}

// AccountAddr6 — IPv6-адрес устройства внутри туннеля.
func AccountAddr6(dir string) string {
	a := primaryAccount(dir)
	if a == nil {
		return ""
	}
	return stripMask(a.AddrV6)
}

// WireguardAccountID — ID конфигурации WireGuard ("custom" для импортированной) или "".
func WireguardAccountID(dir string) string {
	a, err := hydra.LoadAccount(wgPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return a.ID
}

// ExportWireguardConfig — текст .conf для других приложений (WireGuard/AmneziaWG) или "".
func ExportWireguardConfig(dir string) string {
	a, err := hydra.LoadAccount(wgPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return a.WGConfig()
}

// ImportWireguardConfig сохраняет свою конфигурацию (.conf); пустой ответ — успех.
func ImportWireguardConfig(dir, text string) string {
	a, err := hydra.ParseWGConfig(text)
	if err != nil {
		return err.Error()
	}
	if err := a.Save(wgPath(dir)); err != nil {
		return err.Error()
	}
	return ""
}

// DeleteWireguardConfig удаляет сохранённую конфигурацию WireGuard.
func DeleteWireguardConfig(dir string) { os.Remove(wgPath(dir)) }
