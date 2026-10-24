package core

import (
	"context"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// A backend that is still logging in answers no status until control does, so
// a read gives up on its own rather than hold a method goroutine for that long.
const tailscaleStatusTimeout = 30 * time.Second

var (
	tailscaleMu      sync.Mutex
	tailscaleStopped bool
)

// A backend reports the states it reaches, including the first Running after a
// login the host never watched for, so a page follows a node without polling.
func init() {
	outbound.TailscaleStatusHook = func(status *outbound.TailscaleStatus) {
		sendMessage(TailscaleMessage, status)
	}
}

func handleTailscaleStatus(params TailscaleParams) (*outbound.TailscaleStatus, error) {
	if params.Name == "" {
		return nil, &MethodError{Code: "invalid_arguments", Message: "tailscaleStatus needs a proxy name"}
	}
	if stopped := func() bool {
		tailscaleMu.Lock()
		defer tailscaleMu.Unlock()
		return tailscaleStopped
	}(); stopped {
		return nil, nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), tailscaleStatusTimeout)
	defer cancel()
	type answer struct {
		status *outbound.TailscaleStatus
		err    error
	}
	done := make(chan answer, 1)
	safeGo("tailscaleStatus", func() {
		status, err := outbound.TailscaleStatusOf(params.Name)
		done <- answer{status: status, err: err}
	})
	select {
	case result := <-done:
		return result.status, result.err
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

func handleStartTailscale(params TailscaleParams) error {
	if params.Name == "" {
		return &MethodError{Code: "invalid_arguments", Message: "startTailscale needs a proxy name"}
	}
	return outbound.StartTailscale(params.Name)
}

// The URL a browser has to open to finish a login, empty when the node is
// already signed in or has no login to finish.
func handleLoginTailscale(params TailscaleParams) (string, error) {
	if params.Name == "" {
		return "", &MethodError{Code: "invalid_arguments", Message: "loginTailscale needs a proxy name"}
	}
	return outbound.LoginTailscale(params.Name)
}

// Signing out drops the node key the state directory holds, which is what a
// user needs before handing the node to another account.
func handleLogoutTailscale(params TailscaleParams) error {
	if params.Name == "" {
		return &MethodError{Code: "invalid_arguments", Message: "logoutTailscale needs a proxy name"}
	}
	return outbound.LogoutTailscale(params.Name)
}

// Tailscale is the one outbound with a backend of its own to bring up, and a
// rule pointing at the tailnet is not the only reason to want it: the host
// shows the node, so it should exist before the first packet needs it.
// Starting every one after an apply keeps that true however the profile routes.
func startTailscales(previous map[string]constant.Proxy) {
	tailscaleMu.Lock()
	tailscaleStopped = false
	tailscaleMu.Unlock()
	for name, proxy := range tunnel.AllProxies() {
		if proxy.Type() != constant.Tailscale {
			continue
		}
		if previousAdapter, existed := previous[name]; existed && previousAdapter == proxy {
			continue
		}

		started := name
		safeGo("startTailscale", func() {
			if err := outbound.StartTailscale(started); err != nil {
				logError("tailscale %s did not start: %v", started, err)
			}
		})
	}
}

// Nothing else closes an adapter an apply replaced, which for Tailscale would
// leave a tsnet backend running against a node key no outbound owns any more.
func closeReplacedTailscales(previous map[string]constant.Proxy) {
	current := tunnel.AllProxies()
	for name, old := range previous {
		if old.Type() != constant.Tailscale || old == current[name] {
			continue
		}
		closing, closingName := old, name
		safeGo("closeTailscale", func() {
			if err := closing.Close(); err != nil {
				logError("tailscale %s did not close: %v", closingName, err)
			}
		})
	}
}

// Shutting the core down takes its backends with it, and a start already on
// its way out must not bring one back afterwards.
func stopTailscales() {
	tailscaleMu.Lock()
	tailscaleStopped = true
	tailscaleMu.Unlock()
	for name, proxy := range tunnel.AllProxies() {
		if proxy.Type() != constant.Tailscale {
			continue
		}
		closing, closingName := proxy, name
		safeGo("closeTailscale", func() {
			if err := closing.Close(); err != nil {
				logError("tailscale %s did not close: %v", closingName, err)
			}
		})
	}
}
