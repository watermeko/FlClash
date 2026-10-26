package core

import (
	"strings"

	"go.yaml.in/yaml/v3"
)

// The names the injected overlay goes by. A profile that already uses either
// one keeps its own: the app must not shadow a proxy or a group the user can
// see. The outbound and its group cannot share a name, because mihomo reads a
// member of the same name as the group and refuses the config as a loop.
const (
	easyTierProxyName = "EasyTier"
	easyTierGroupName = "Mesh"
)

// EasyTier hands out addresses from 10.126.126.0/24 unless the network chose
// another range, so the range the node reports is what the rules point at.
const easyTierDefaultIPv4Range = "10.126.126.0/24"

// What the app keeps in every profile: one EasyTier outbound, a group holding
// it and DIRECT, the overlay's range pointed at that group, and the DNS server
// that resolves its names. It runs after the base is merged for the same
// reason the Tailscale one does: an overlay's proxies replace that section
// rather than extend it, so this is the only point where both the profile's
// own proxies and the node are known.
//
// Nothing is written when the node is off or when the profile already names
// something the app would add, which leaves a hand-written setup as it was.
func injectEasyTier(root *yaml.Node, node *EasyTierInject) error {
	if node == nil || root == nil {
		return nil
	}
	proxy, err := easyTierProxyValue(node)
	if err != nil {
		return err
	}
	proxies := mappingValue(root, "proxies")
	if hasProxyNamed(proxies, easyTierProxyName) {
		return nil
	}
	groups := mappingValue(root, "proxy-groups")
	if hasProxyNamed(groups, easyTierGroupName) {
		return nil
	}

	setMappingValue(root, "proxies", appendToSequence(proxies, proxy))
	group := mappingOf(
		"name", easyTierGroupName,
		"type", "select",
		"proxies", sequenceOf(easyTierProxyName, "DIRECT"),
	)
	setMappingValue(root, "proxy-groups", appendToSequence(groups, group))
	rules := easyTierRules(node.IPv4Range)
	setMappingValue(root, "rules", insertBeforeMatch(mappingValue(root, "rules"), rules))
	injectEasyTierDns(root, node.Name)
	return nil
}

func easyTierProxyValue(node *EasyTierInject) (*yaml.Node, error) {
	fields := []keyValue{
		{"name", easyTierProxyName},
		{"type", "easytier"},
		{"network-name", node.NetworkName},
		{"network-secret", node.NetworkSecret},
	}
	if node.Hostname != "" {
		fields = append(fields, keyValue{"hostname", node.Hostname})
	}
	if node.IPv4 != "" {
		fields = append(fields, keyValue{"ipv4", node.IPv4})
	}
	if node.DHCP {
		fields = append(fields, keyValue{"dhcp", true})
	}
	if len(node.Peers) > 0 {
		fields = append(fields, keyValue{"peers", sequenceOfStrings(node.Peers)})
	}
	if len(node.Listeners) > 0 {
		fields = append(fields, keyValue{"listeners", sequenceOfStrings(node.Listeners)})
	}
	if node.NoListener {
		fields = append(fields, keyValue{"no-listener", true})
	}
	if node.StateDir != "" {
		fields = append(fields, keyValue{"state-dir", node.StateDir})
	}
	if node.UDP {
		fields = append(fields, keyValue{"udp", true})
	}
	return mappingOfFields(fields), nil
}

func sequenceOfStrings(values []string) *yaml.Node {
	items := make([]any, 0, len(values))
	for _, value := range values {
		items = append(items, value)
	}
	return sequenceOf(items...)
}

func easyTierRules(ipv4Range string) []*yaml.Node {
	cidr := strings.TrimSpace(ipv4Range)
	if cidr == "" {
		cidr = easyTierDefaultIPv4Range
	}
	return []*yaml.Node{
		scalarNode("IP-CIDR," + cidr + "," + easyTierGroupName + ",no-resolve"),
	}
}

// An `easytier://` nameserver is what mihomo resolves overlay names through,
// and it names the outbound by the same name the proxy has.
func injectEasyTierDns(root *yaml.Node, proxyName string) {
	if proxyName == "" {
		return
	}
	dns := mappingValue(root, "dns")
	if dns == nil || dns.Kind != yaml.MappingNode {
		dns = mappingOf()
		setMappingValue(root, "dns", dns)
	}
	// enable is what mihomo reads before it uses any of the rest.
	if mappingValue(dns, "enable") == nil {
		setMappingValue(dns, "enable", scalarNode("true"))
	}
	server := scalarNode("easytier://" + proxyName)
	nameserver := mappingValue(dns, "nameserver")
	if nameserver == nil {
		setMappingValue(dns, "nameserver", sequenceOf(server))
		return
	}
	for _, existing := range nameserver.Content {
		if existing.Value == server.Value {
			return
		}
	}
	setMappingValue(dns, "nameserver", appendToSequence(nameserver, server))
}

// The mesh is one overlay or the other, never both: two nodes over one profile
// would each claim the addresses the other routes, and the app writes what the
// user chose. This keeps a stale half of a half-switched state out of the yaml.
func injectOverlay(root *yaml.Node, tailscale *TailscaleInject, easyTier *EasyTierInject) error {
	if root == nil {
		return nil
	}
	if easyTier != nil && easyTier.NetworkName != "" {
		return injectEasyTier(root, easyTier)
	}
	return injectTailscale(root, tailscale)
}
