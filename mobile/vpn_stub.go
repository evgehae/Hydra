//go:build !usque

package mobile

import hydra "hydra/core"

// vpnMem есть и в сборке с движком (там он заполняется), чтобы общий код мог на него ссылаться.
var vpnMem *hydra.Memory

// Сборка без клиента MASQUE (без тега usque): подключение недоступно.

func StartTunnel(dir string, tunFd int) string {
	return "сборка без движка MASQUE (нет тега usque)"
}

func StopTunnel() {}

func EngineStatus() string { return "off||||" }


func SpeedTest() string { return "туннель не подключён" }
