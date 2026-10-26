package core

import (
	"context"
	"time"

	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// A status read is a query about a running node, so it gives up on its own
// rather than hold a method goroutine for a node that cannot answer.
const easyTierStatusTimeout = 10 * time.Second

func handleEasyTierStatus(params EasyTierParams) (*outbound.EasyTierStatus, error) {
	if params.Name == "" {
		return nil, &MethodError{Code: "invalid_arguments", Message: "easyTierStatus needs a proxy name"}
	}
	ctx, cancel := context.WithTimeout(context.Background(), easyTierStatusTimeout)
	defer cancel()
	type answer struct {
		status *outbound.EasyTierStatus
		err    error
	}
	done := make(chan answer, 1)
	safeGo("easyTierStatus", func() {
		status, err := outbound.EasyTierStatusOf(params.Name)
		done <- answer{status: status, err: err}
	})
	select {
	case result := <-done:
		return result.status, result.err
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

// EasyTier has no backend of its own to bring up before the first packet: the
// outbound starts its instance on the first dial, and a page that only wants
// to show the node reads through the same call. Nothing here is needed for
// that, but closing is: an overlay left running after its adapter was replaced
// keeps a wasm instance and its sockets alive for a node no profile owns.
func closeReplacedEasyTiers(previous map[string]constant.Proxy) {
	current := tunnel.AllProxies()
	for name, old := range previous {
		if old.Type() != constant.EasyTier || old == current[name] {
			continue
		}
		if err := old.Close(); err != nil {
			logError("easytier %s did not close: %v", name, err)
		}
	}
}

// Shutting the core down takes its overlays with it.
func stopEasyTiers() {
	for name, proxy := range tunnel.AllProxies() {
		if proxy.Type() != constant.EasyTier {
			continue
		}
		closing, closingName := proxy, name
		safeGo("closeEasyTier", func() {
			if err := closing.Close(); err != nil {
				logError("easytier %s did not close: %v", closingName, err)
			}
		})
	}
}
