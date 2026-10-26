//go:build with_gvisor

package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/tunnel"
)

// The profile a subscription brings: it already has proxies, a group and a
// catch-all rule, so the node has to be added around them rather than instead.
const injectProfile = `proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
proxy-groups:
  - {name: PROXY, type: select, proxies: [a]}
rules:
  - DOMAIN,kept.test,PROXY
  - MATCH,PROXY
`

func writeInjectProfile(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "profile.yaml")
	if err := os.WriteFile(path, []byte(injectProfile), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}
	return path
}

func loadWithNode(t *testing.T, path string, node *TailscaleInject) string {
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
		node,
		nil,
	); err != nil {
		t.Fatalf("loadConfigWithBase: %v", err)
	}
	// A profile carries its proxies, so the node reaches the tunnel through
	// the same apply the app uses.
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

func TestInjectTailscaleAddsTheNodeBesideTheProfilesOwn(t *testing.T) {
	written := loadWithNode(t, writeInjectProfile(t), &TailscaleInject{
		Name:           "Tailscale",
		AuthKey:        "tskey-auth-test",
		Hostname:       "phone",
		ExitNode:       "nas",
		MagicDNSSuffix: "tail72614b.ts.net",
	})

	for _, want := range []string{
		"name: a",
		"name: PROXY",
		"type: tailscale",
		"auth-key: tskey-auth-test",
		"hostname: phone",
		"exit-node: nas",
		"ts://Tailscale",
		"DOMAIN-SUFFIX,tail72614b.ts.net,Tailnet",
		"IP-CIDR,100.64.0.0/10,Tailnet,no-resolve",
		"IP-CIDR6,fd7a:115c:a1e0::/48,Tailnet,no-resolve",
		"DOMAIN,kept.test,PROXY",
	} {
		if !strings.Contains(written, want) {
			t.Errorf("config is missing %q:\n%s", want, written)
		}
	}
}

// A tailnet rule after the catch-all would never run, so the node's rules go
// in front of whatever the profile matches last.
func TestInjectTailscalePutsItsRulesBeforeTheCatchAll(t *testing.T) {
	written := loadWithNode(t, writeInjectProfile(t), &TailscaleInject{Name: "Tailscale"})

	match := strings.Index(written, "MATCH,PROXY")
	tailnet := strings.Index(written, "IP-CIDR,100.64.0.0/10")
	if match < 0 || tailnet < 0 {
		t.Fatalf("config is missing a rule this test reads:\n%s", written)
	}
	if tailnet > match {
		t.Errorf("the tailnet rule sits after MATCH,PROXY, so it never matches:\n%s", written)
	}
}

// A MagicDNS suffix is what makes the names resolvable; without it the node's
// rules still work but its machines are reachable by address only.
func TestInjectTailscaleSkipsTheSuffixRuleWithoutOne(t *testing.T) {
	written := loadWithNode(t, writeInjectProfile(t), &TailscaleInject{Name: "Tailscale"})

	if strings.Contains(written, "DOMAIN-SUFFIX") {
		t.Errorf("a suffix rule was written without a suffix:\n%s", written)
	}
}

// A profile that already carries a node is left exactly as it is: the app must
// not shadow something the user wrote by hand.
func TestInjectTailscaleLeavesAProfileThatAlreadyHasOne(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.yaml")
	handWritten := `proxies:
  - {name: Tailscale, type: tailscale, auth-key: mine}
proxy-groups:
  - {name: PROXY, type: select, proxies: [Tailscale]}
rules:
  - MATCH,PROXY
`
	if err := os.WriteFile(path, []byte(handWritten), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}

	written := loadWithNode(t, path, &TailscaleInject{AuthKey: "theirs"})

	if strings.Contains(written, "theirs") {
		t.Errorf("the app's node replaced a hand-written one:\n%s", written)
	}
	if count := strings.Count(written, "type: tailscale"); count != 1 {
		t.Errorf("type: tailscale appears %d times, want the one already there:\n%s", count, written)
	}
}

// A group of the same name would be ambiguous, so the app leaves the profile
// alone rather than writing one that cannot load.
func TestInjectTailscaleLeavesAProfileWithAGroupOfThatName(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.yaml")
	taken := `proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
proxy-groups:
  - {name: Tailnet, type: select, proxies: [a]}
rules:
  - MATCH,Tailnet
`
	if err := os.WriteFile(path, []byte(taken), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}

	written := loadWithNode(t, path, &TailscaleInject{AuthKey: "my-key"})

	if strings.Contains(written, "my-key") {
		t.Errorf("the app injected a node under a group name the profile uses:\n%s", written)
	}
}

// A custom profile has no base, so its own bytes are the whole document and
// take the other path through the same injection.
func TestWithTailscaleAppliesToACustomProfileDocument(t *testing.T) {
	custom := []byte(`proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
rules:
  - MATCH,DIRECT
`)

	written, err := withOverlay(custom, &TailscaleInject{
		Name:           "Tailscale",
		AuthKey:        "tskey-auth-custom",
		MagicDNSSuffix: "tail72614b.ts.net",
	}, nil)

	if err != nil {
		t.Fatalf("withOverlay = %v", err)
	}
	for _, want := range []string{
		"type: tailscale",
		"tskey-auth-custom",
		"IP-CIDR,100.64.0.0/10,Tailnet,no-resolve",
		"DOMAIN-SUFFIX,tail72614b.ts.net,Tailnet",
		"ts://Tailscale",
		"name: a",
	} {
		if !strings.Contains(string(written), want) {
			t.Errorf("custom config is missing %q:\n%s", want, written)
		}
	}
}

// Without a node the app writes nothing, so a user who turns the mesh off gets
// the profile the core would have built on its own.
func TestInjectTailscaleWritesNothingWhenTheNodeIsOff(t *testing.T) {
	written := loadWithNode(t, writeInjectProfile(t), nil)

	if strings.Contains(written, "tailscale") || strings.Contains(written, "ts://") {
		t.Errorf("a config with no node still mentions Tailscale:\n%s", written)
	}
}

// An apply rebuilds the config, but the DNS list can carry a server the app
// already wrote, so the same entry must not be added twice.
func TestInjectTailscaleAddsItsNameserverOnce(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.yaml")
	withDns := `proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
proxy-groups:
  - {name: PROXY, type: select, proxies: [a]}
rules:
  - MATCH,PROXY
dns:
  enable: true
  nameserver:
    - https://doh.pub/dns-query
    - ts://Tailscale
`
	if err := os.WriteFile(path, []byte(withDns), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}

	written := loadWithNode(t, path, &TailscaleInject{Name: "Tailscale"})

	if count := strings.Count(written, "ts://Tailscale"); count != 1 {
		t.Errorf("ts://Tailscale appears %d times, want the one already there:\n%s", count, written)
	}
	if !strings.Contains(written, "https://doh.pub/dns-query") {
		t.Errorf("the profile's own nameserver was dropped:\n%s", written)
	}
}
