package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/tunnel"
)

// The overlay is written after the base is merged, so the profile is what the
// node has to be added around rather than instead of.
func loadWithEasyTier(t *testing.T, path string, node *EasyTierInject) string {
	t.Helper()
	configPath := filepath.Join(t.TempDir(), "config.yaml")
	base, err := handleGetProfileBase(path)
	if err != nil {
		t.Fatalf("handleGetProfileBase: %v", err)
	}
	overlay := overlayOf(t, base, nil, nil)
	if _, err := loadConfigWithBase(
		&SetupBase{Path: path, Overlay: overlay},
		configPath,
		nil,
		node,
	); err != nil {
		t.Fatalf("loadConfigWithBase: %v", err)
	}
	applied, err := loadConfig(configPath, nil, nil)
	if err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	_ = applied
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	return string(data)
}

func minimalEasyTierNode() *EasyTierInject {
	return &EasyTierInject{
		Name:          "EasyTier",
		NetworkName:   "watermeko-easytier",
		NetworkSecret: "secret-value",
		Hostname:      "phone",
		Peers:         []string{"tcp://relay.test:11010"},
		StateDir:      "easytier",
		UDP:           true,
		IPv4Range:     "10.126.126.0/24",
	}
}

// The node has to arrive as an outbound the tunnel can build, with everything
// it needs to join a network and nothing it does not.
func TestEasyTierIsInjectedAsAnOutboundAndAGroup(t *testing.T) {
	written := loadWithEasyTier(t, writeInjectProfile(t), minimalEasyTierNode())

	for _, want := range []string{
		"type: easytier",
		"name: EasyTier",
		"network-name: watermeko-easytier",
		"network-secret: secret-value",
		"hostname: phone",
		"- tcp://relay.test:11010",
		"state-dir: easytier",
		"udp: true",
		// Its own group, and the overlay's range pointed at it, so the mesh is
		// reachable without the user writing a rule.
		"name: Mesh",
		"IP-CIDR,10.126.126.0/24,Mesh,no-resolve",
		"easytier://EasyTier",
	} {
		if !strings.Contains(written, want) {
			t.Errorf("config is missing %q\n%s", want, written)
		}
	}
}

// The profile's own setup is what the user sees in the editor, so the node has
// to sit beside it rather than replace it.
func TestEasyTierLeavesTheProfilesOwnSetupAlone(t *testing.T) {
	written := loadWithEasyTier(t, writeInjectProfile(t), minimalEasyTierNode())

	for _, want := range []string{
		"DOMAIN,kept.test,PROXY",
		"- {name: PROXY, type: select, proxies: [a]}",
		"- {name: a, type: socks5, server: 127.0.0.1, port: 1080}",
	} {
		if !strings.Contains(written, want) {
			t.Errorf("the profile's own %q did not survive\n%s", want, written)
		}
	}
}

// A range the network reports is what the rules have to use: a network that
// chose another subnet would otherwise route nothing.
func TestEasyTierRulesFollowTheRangeTheNetworkUses(t *testing.T) {
	node := minimalEasyTierNode()
	node.IPv4Range = "10.11.11.0/24"

	written := loadWithEasyTier(t, writeInjectProfile(t), node)

	if !strings.Contains(written, "IP-CIDR,10.11.11.0/24,Mesh,no-resolve") {
		t.Errorf("the rules do not follow the reported range\n%s", written)
	}
}

// A profile that already names what the app would add keeps its own, which is
// what stops the injection from shadowing something the user can see.
func TestEasyTierSkipsAProfileThatAlreadyNamesIt(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.yaml")
	own := strings.Replace(injectProfile, "  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}",
		"  - {name: EasyTier, type: socks5, server: 127.0.0.1, port: 1081}", 1)
	own = strings.Replace(own, "proxies: [a]", "proxies: [EasyTier]", 1)
	if err := os.WriteFile(path, []byte(own), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}

	written := loadWithEasyTier(t, path, minimalEasyTierNode())

	if strings.Contains(written, "type: easytier") {
		t.Errorf("the node shadowed a proxy the profile already had\n%s", written)
	}
}

// The two overlays are two ways into one mesh, so only the chosen one is
// written: a stale Tailscale node beside a live EasyTier one would claim the
// ranges the other routes.
func TestChoosingEasyTierLeavesNoTailscaleNodeBehind(t *testing.T) {
	written := loadWithEasyTier(t, writeInjectProfile(t), minimalEasyTierNode())

	for _, unwanted := range []string{"type: tailscale", "Tailnet", "ts://Tailscale"} {
		if strings.Contains(written, unwanted) {
			t.Errorf("the mesh carries %q as well\n%s", unwanted, written)
		}
	}
}

// And the other way round: a Tailscale choice writes no EasyTier node.
func TestChoosingTailscaleWritesNoEasyTierNode(t *testing.T) {
	written := loadWithNode(t, writeInjectProfile(t), &TailscaleInject{
		Name:           "Tailscale",
		AuthKey:        "tskey-auth-test",
		MagicDNSSuffix: "tail72614b.ts.net",
	})

	for _, unwanted := range []string{"type: easytier", "Mesh", "easytier://EasyTier"} {
		if strings.Contains(written, unwanted) {
			t.Errorf("the mesh carries %q as well\n%s", unwanted, written)
		}
	}
}
