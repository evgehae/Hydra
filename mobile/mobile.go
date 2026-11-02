// Package mobile — тонкая обвязка для gomobile: то, что видно из Kotlin.
package mobile

import (
	"fmt"

	hydra "hydra/core"
)

const version = "0.1.0"

// Version проверяет, что Go-ядро собрано и вызывается из Android.
func Version() string {
	cfg := hydra.DefaultConfig()
	return fmt.Sprintf("hydra-core %s (probe %s)", version, cfg.ProbeEvery)
}
