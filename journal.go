package hydra

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"
)

// Журнал Гидры: подробно и по-русски, что происходит и почему.
// Показывается в приложении (вкладка «Проверка»).

type journalBuf struct {
	mu    sync.Mutex
	lines []string
	max   int
}

var jr = &journalBuf{max: 1200}

// Logf добавляет строку в журнал.
func Logf(format string, a ...any) {
	line := time.Now().Format("15:04:05.000") + "  " + fmt.Sprintf(format, a...)
	jr.mu.Lock()
	jr.lines = append(jr.lines, line)
	if len(jr.lines) > jr.max {
		jr.lines = append([]string(nil), jr.lines[len(jr.lines)-jr.max:]...)
	}
	jr.mu.Unlock()
	jfileWrite(line)
}

// Журнал дублируется в файл (до ~3 МБ, затем старая половина уходит в .old): так записи переживают
// перезапуск службы и слёт приложения, а в отчёте есть история за много часов.
var jfile struct {
	mu   sync.Mutex
	f    *os.File
	path string
	size int64
}

const jfileMax = 3 << 20

func jfileWrite(line string) {
	jfile.mu.Lock()
	defer jfile.mu.Unlock()
	if jfile.f == nil {
		return
	}
	n, _ := jfile.f.WriteString(time.Now().Format("01-02 ") + line + "\n")
	jfile.size += int64(n)
	if jfile.size > jfileMax {
		jfile.f.Close()
		os.Rename(jfile.path, jfile.path+".old")
		f, err := os.OpenFile(jfile.path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
		if err != nil {
			jfile.f = nil
			return
		}
		jfile.f, jfile.size = f, 0
	}
}

func lastLineOf(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	ls := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	if len(ls) == 0 {
		return ""
	}
	return ls[len(ls)-1]
}

// SetJournalFile включает запись журнала в файл. Если прошлая сессия оборвалась без записи об остановке
// службы, пишет предупреждение (слёт приложения, убийство процесса системой, перезагрузка).
func SetJournalFile(path string) {
	jfile.mu.Lock()
	if jfile.f != nil {
		jfile.mu.Unlock()
		return
	}
	prev := lastLineOf(path)
	jfile.path = path
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err == nil {
		jfile.f = f
		if st, e := f.Stat(); e == nil {
			jfile.size = st.Size()
		}
	}
	jfile.mu.Unlock()
	if err != nil {
		return
	}
	Logf("──────── запуск приложения ────────")
	if prev != "" && !strings.Contains(prev, "служба: уничтожена") && !strings.Contains(prev, "служба: остановка") {
		if len(prev) > 160 {
			prev = prev[:160]
		}
		Logf("⚠ прошлая сессия оборвалась без остановки службы (слёт приложения, убийство процесса системой или перезагрузка). Последняя запись: %s", prev)
	}
}

// JournalFileTail — последние n строк журнала из файла (включая прошлые запуски); пусто, если файла нет.
func JournalFileTail(n int) string {
	jfile.mu.Lock()
	path := jfile.path
	jfile.mu.Unlock()
	if path == "" {
		return ""
	}
	var all []string
	for _, p := range []string{path + ".old", path} {
		if b, err := os.ReadFile(p); err == nil {
			all = append(all, strings.Split(strings.TrimRight(string(b), "\n"), "\n")...)
		}
	}
	if n > 0 && len(all) > n {
		all = all[len(all)-n:]
	}
	return strings.Join(all, "\n")
}

// JournalText возвращает последние n строк (0 — все), новые в конце.
func JournalText(n int) string {
	jr.mu.Lock()
	defer jr.mu.Unlock()
	ls := jr.lines
	if n > 0 && len(ls) > n {
		ls = ls[len(ls)-n:]
	}
	return strings.Join(ls, "\n")
}

func JournalClear() {
	jr.mu.Lock()
	jr.lines = nil
	jr.mu.Unlock()
}

// JournalWriter — io.Writer для стандартного log: строки клиента MASQUE
// (usque) тоже попадут в журнал.
type JournalWriter struct{}

func (JournalWriter) Write(p []byte) (int, error) {
	for _, l := range strings.Split(strings.TrimRight(string(p), "\r\n"), "\n") {
		l = strings.TrimSpace(l)
		if l == "" || strings.Contains(l, "Hop Limit too small") {
			continue // служебные пакеты с hop limit 1 — не интересны
		}
		Logf("· %s", l)
	}
	return len(p), nil
}
