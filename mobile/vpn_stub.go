//go:build !usque

package mobile

// Сборка без клиента MASQUE (без тега usque): подключение недоступно.

func StartTunnel(dir string, tunFd int) string {
	return "сборка без движка MASQUE (нет тега usque)"
}

func StopTunnel() {}

func EngineStatus() string { return "off||||" }
