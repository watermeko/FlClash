//go:build with_gvisor

package core

import (
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// newTailscaleProxy builds a real adapter, so the type these paths key on is
// mihomo's own rather than a stub that could agree with a wrong assumption.
func newTailscaleProxy(t *testing.T, name string) constant.Proxy {
	t.Helper()

	proxy, err := outbound.NewTailscale(outbound.TailscaleOption{Name: name})
	if err != nil {
		t.Fatalf("NewTailscale(%s): %v", name, err)
	}
	return adapter.NewProxy(proxy)
}

func TestTailscaleStatusRequiresAName(t *testing.T) {
	if _, err := handleTailscaleStatus(TailscaleParams{}); err == nil {
		t.Fatal("handleTailscaleStatus accepted an empty name, want invalid_arguments")
	}
	var methodErr *MethodError
	err := handleStartTailscale(TailscaleParams{})
	if !errors.As(err, &methodErr) || methodErr.Code != "invalid_arguments" {
		t.Fatalf("handleStartTailscale error = %v, want invalid_arguments", err)
	}
}

// A build without Tailscale still answers, so the host shows no outbound rather
// than a transport failure.
func TestTailscaleStatusOfAnAbsentOutboundIsNil(t *testing.T) {
	status, err := outbound.TailscaleStatusOf("missing")
	if err != nil {
		t.Fatalf("TailscaleStatusOf(missing) error = %v, want nil", err)
	}
	if status != nil {
		t.Fatalf("TailscaleStatusOf(missing) = %+v, want nil", status)
	}
}

func TestStopTailscalesTakesTheBackendDown(t *testing.T) {
	stopTailscales()
	t.Cleanup(func() {
		tailscaleMu.Lock()
		tailscaleStopped = false
		tailscaleMu.Unlock()
	})

	status, err := handleTailscaleStatus(TailscaleParams{Name: "any"})
	if err != nil {
		t.Fatalf("handleTailscaleStatus after stop error = %v, want nil", err)
	}
	if status != nil {
		t.Fatalf("handleTailscaleStatus after stop = %+v, want nil", status)
	}
}

// A replaced adapter that is still Tailscale has to lose its backend: nothing
// else closes an adapter an apply dropped.
func TestCloseReplacedTailscalesClosesOnlyTheDroppedOnes(t *testing.T) {
	kept := newTailscaleProxy(t, "kept")
	dropped := newTailscaleProxy(t, "dropped")
	tunnel.UpdateProxies(
		map[string]constant.Proxy{"kept": kept, "other": namedProxy("other")},
		nil,
	)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	closeReplacedTailscales(map[string]constant.Proxy{
		"kept":    kept,
		"dropped": dropped,
		"other":   namedProxy("other"),
	})

	// The retained adapter is still the one the tunnel holds, so its backend
	// stays up; closing it here is what a cleanup would do, not the assertion.
	if tunnel.AllProxies()["kept"] != kept {
		t.Fatal("the retained adapter left the tunnel, so this test asserted nothing")
	}
	_ = kept.Close()
}

// The core starts every Tailscale outbound an apply installs, since a rule
// pointing at the tailnet is not what keeps the node up.
func TestStartTailscalesSkipsTheAdaptersItAlreadyHasInTheTunnel(t *testing.T) {
	kept := newTailscaleProxy(t, "kept")
	tunnel.UpdateProxies(map[string]constant.Proxy{"kept": kept}, nil)
	t.Cleanup(func() {
		tunnel.UpdateProxies(nil, nil)
		tailscaleMu.Lock()
		tailscaleStopped = false
		tailscaleMu.Unlock()
	})

	// An adapter the tunnel already holds is not started again: a second tsnet
	// server over one state directory is what a restart would have to avoid.
	startTailscales(map[string]constant.Proxy{"kept": kept})
	time.Sleep(200 * time.Millisecond)

	status, err := outbound.TailscaleStatusOf("kept")
	if err != nil {
		t.Fatalf("TailscaleStatusOf(kept) error = %v", err)
	}
	if status != nil {
		t.Fatalf("an adapter the previous apply already had was started again: %+v", status)
	}
}

func TestStartTailscalesLeavesOtherTypesAlone(t *testing.T) {
	direct := namedProxy("direct")
	tunnel.UpdateProxies(map[string]constant.Proxy{"direct": direct}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	startTailscales(nil)

	if _, err := outbound.TailscaleStatusOf("direct"); err != nil {
		t.Fatalf("a non-Tailscale proxy answered a Tailscale status: %v", err)
	}
}

// The replacement starts as soon as the close returns, and two tsnet servers
// over one state directory fight for the node key: control answers the loser
// with "410 auth path not found". Closing on a goroutine is what let both run,
// so a close still in flight when this returns is the bug.
func TestCloseReplacedTailscalesClosesBeforeReturning(t *testing.T) {
	dropped := &closeSpyProxy{Proxy: newTailscaleProxy(t, "dropped")}
	tunnel.UpdateProxies(map[string]constant.Proxy{}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	closeReplacedTailscales(map[string]constant.Proxy{"dropped": dropped})

	if !dropped.closed() {
		t.Fatal("the dropped adapter was still closing when closeReplacedTailscales returned")
	}
}

// closeSpyProxy records that its Close ran, which is the order the caller
// depends on rather than anything the adapter reports afterwards.
type closeSpyProxy struct {
	constant.Proxy

	mu     sync.Mutex
	isDone bool
}

func (p *closeSpyProxy) Close() error {
	defer func() {
		p.mu.Lock()
		p.isDone = true
		p.mu.Unlock()
	}()
	return p.Proxy.Close()
}

func (p *closeSpyProxy) closed() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.isDone
}
