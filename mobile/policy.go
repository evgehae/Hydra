package mobile

import (
	"strings"
	"sync"

	hydra "hydra/core"
)

var (
	polMu    sync.Mutex
	polBlock = ""
	polAllow = ""
	netKey   = "default"
)

// SetColoPolicy задаёт запрещённые и (необязательно) единственно разрешённые
// дата-центры Cloudflare: "DME,LED" и "HEL,FRA".
func SetColoPolicy(block, allow string) {
	polMu.Lock()
	polBlock, polAllow = block, allow
	polMu.Unlock()
}

// SetNetKey сообщает ядру, в какой сети телефон ("wifi:xxx", "cell:25001"):
// память стратегий копится отдельно для каждой сети.
func SetNetKey(k string) {
	polMu.Lock()
	netKey = strings.TrimSpace(k)
	polMu.Unlock()
}

func currentNetKey() string {
	polMu.Lock()
	defer polMu.Unlock()
	return netKey
}

func currentPolicy() *hydra.ColoPolicy {
	polMu.Lock()
	defer polMu.Unlock()
	return &hydra.ColoPolicy{Block: hydra.ParseColoList(polBlock), Allow: hydra.ParseColoList(polAllow)}
}
