package core

import (
	"fmt"
	"strings"

	"go.yaml.in/yaml/v3"
)

// The names the injected node goes by. A profile that already uses either one
// keeps its own: the app must not shadow a proxy or a group the user can see.
// The outbound and its group cannot share a name: mihomo reads a member of the
// same name as the group and refuses the whole config as a loop. The node keeps
// the product's name, which is the one the DNS server also refers to, and the
// group takes the network's.
const (
	tailscaleProxyName = "Tailscale"
	tailscaleGroupName = "Tailnet"
)

// The ranges a tailnet reaches, and the MagicDNS suffix when the node reports
// one. 100.64.0.0/10 is Tailscale's own CGNAT block and fd7a:115c:a1e0::/48
// its IPv6 one; an exit node routes everything else through the node already.
const (
	tailscaleIPv4Range = "100.64.0.0/10"
	tailscaleIPv6Range = "fd7a:115c:a1e0::/48"
)

// What the app keeps in every profile: one Tailscale outbound, a group holding
// it and DIRECT, the tailnet's ranges pointed at that group, and the DNS server
// that resolves its names. It runs after the base is merged because an
// overlay's proxies replace that section instead of extending it, so this is
// the only point where both the profile's own proxies and the node are known.
//
// Nothing is written when the node is off or when the profile already names
// something Tailscale, which leaves a hand-written setup exactly as it was.
func injectTailscale(root *yaml.Node, node *TailscaleInject) error {
	if node == nil || root == nil {
		return nil
	}
	proxy, err := tailscaleProxyValue(node)
	if err != nil {
		return err
	}
	proxies := mappingValue(root, "proxies")
	if hasProxyNamed(proxies, tailscaleProxyName) {
		return nil
	}
	groups := mappingValue(root, "proxy-groups")
	if hasProxyNamed(groups, tailscaleGroupName) {
		return nil
	}

	setMappingValue(root, "proxies", appendToSequence(proxies, proxy))
	group := mappingOf(
		"name", tailscaleGroupName,
		"type", "select",
		"proxies", sequenceOf(tailscaleProxyName, "DIRECT"),
	)
	setMappingValue(root, "proxy-groups", appendToSequence(groups, group))
	rules := tailscaleRules(node.MagicDNSSuffix)
	setMappingValue(root, "rules", insertBeforeMatch(mappingValue(root, "rules"), rules))
	injectTailscaleDns(root, node.Name)
	return nil
}

func tailscaleProxyValue(node *TailscaleInject) (*yaml.Node, error) {
	fields := []keyValue{
		{"name", tailscaleProxyName},
		{"type", "tailscale"},
	}
	if node.Hostname != "" {
		fields = append(fields, keyValue{"hostname", node.Hostname})
	}
	if node.AuthKey != "" {
		fields = append(fields, keyValue{"auth-key", node.AuthKey})
	}
	if node.ControlURL != "" {
		fields = append(fields, keyValue{"control-url", node.ControlURL})
	}
	if node.StateDir != "" {
		fields = append(fields, keyValue{"state-dir", node.StateDir})
	}
	if node.Ephemeral {
		fields = append(fields, keyValue{"ephemeral", true})
	}
	if node.UDP {
		fields = append(fields, keyValue{"udp", true})
	}
	if node.AcceptRoutes {
		fields = append(fields, keyValue{"accept-routes", true})
	}
	if node.ExitNode != "" {
		fields = append(fields, keyValue{"exit-node", node.ExitNode})
	}
	if node.ExitNodeAllowLANAccess {
		fields = append(fields, keyValue{"exit-node-allow-lan-access", true})
	}
	return mappingOfFields(fields), nil
}

func tailscaleRules(magicDNSSuffix string) []*yaml.Node {
	rules := []*yaml.Node{
		scalarNode("IP-CIDR," + tailscaleIPv4Range + "," + tailscaleGroupName + ",no-resolve"),
		scalarNode("IP-CIDR6," + tailscaleIPv6Range + "," + tailscaleGroupName + ",no-resolve"),
	}
	// The suffix names the tailnet's own machines; without it a MagicDNS name
	// falls through to whatever the profile matches next, which is a remote
	// resolver that knows nothing about it.
	if suffix := strings.Trim(strings.TrimSpace(magicDNSSuffix), "."); suffix != "" {
		rules = append(rules, scalarNode("DOMAIN-SUFFIX,"+suffix+","+tailscaleGroupName))
	}
	return rules
}

// A `ts://` nameserver is what mihomo resolves tailnet names through, and it
// names the outbound by the same name the proxy has.
func injectTailscaleDns(root *yaml.Node, proxyName string) {
	if proxyName == "" {
		return
	}
	dns := mappingValue(root, "dns")
	if dns == nil || dns.Kind != yaml.MappingNode {
		dns = mappingOf()
		setMappingValue(root, "dns", dns)
	}
	server := scalarNode("ts://" + tailscaleProxyName)
	nameserver := appendUnique(mappingValue(dns, "nameserver"), server)
	setMappingValue(dns, "nameserver", nameserver)
}

type keyValue struct {
	key   string
	value any
}

func mappingOfFields(fields []keyValue) *yaml.Node {
	mapping := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}
	for _, field := range fields {
		mapping.Content = append(
			mapping.Content,
			scalarNode(field.key),
			valueNode(field.value),
		)
	}
	return mapping
}

// mappingOf builds a mapping from alternating keys and values, the shape
// setMappingValue and mappingValue read.
func mappingOf(pairs ...any) *yaml.Node {
	mapping := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}
	for i := 0; i+1 < len(pairs); i += 2 {
		key, _ := pairs[i].(string)
		mapping.Content = append(
			mapping.Content,
			scalarNode(key),
			valueNode(pairs[i+1]),
		)
	}
	return mapping
}

func sequenceOf(values ...any) *yaml.Node {
	sequence := &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq"}
	for _, value := range values {
		sequence.Content = append(sequence.Content, valueNode(value))
	}
	return sequence
}

func scalarNode(value string) *yaml.Node {
	return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: value}
}

func valueNode(value any) *yaml.Node {
	switch typed := value.(type) {
	case *yaml.Node:
		return typed
	case bool:
		literal := "false"
		if typed {
			literal = "true"
		}
		return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!bool", Value: literal}
	case string:
		return scalarNode(typed)
	default:
		return scalarNode(fmt.Sprint(value))
	}
}

// A missing section starts as an empty list, and one that is not a list is left
// alone: a profile that wrote something else there has a problem the core
// should report rather than one this hides.
func appendToSequence(sequence *yaml.Node, value *yaml.Node) *yaml.Node {
	sequence = resolveAlias(sequence)
	if sequence == nil || isNull(sequence) || sequence.Kind != yaml.SequenceNode {
		if sequence != nil && !isNull(sequence) && sequence.Kind != yaml.SequenceNode {
			return sequence
		}
		return sequenceOf(value)
	}
	content := make([]*yaml.Node, 0, len(sequence.Content)+1)
	content = append(append(content, sequence.Content...), value)
	return &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq", Content: content}
}

// The tailnet rules go in front of whatever catches everything, so a profile
// that ends in MATCH,PROXY still sends 100.64.0.0/10 to the node.
func insertBeforeMatch(rules *yaml.Node, added []*yaml.Node) *yaml.Node {
	if len(added) == 0 {
		return rules
	}
	rules = resolveAlias(rules)
	if rules == nil || isNull(rules) || rules.Kind != yaml.SequenceNode {
		if rules != nil && !isNull(rules) && rules.Kind != yaml.SequenceNode {
			return rules
		}
		return &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq", Content: added}
	}
	content := make([]*yaml.Node, 0, len(rules.Content)+len(added))
	inserted := false
	for _, rule := range rules.Content {
		if !inserted && catchesEverything(rule) {
			content = append(content, added...)
			inserted = true
		}
		content = append(content, rule)
	}
	if !inserted {
		content = append(content, added...)
	}
	return &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq", Content: content}
}

func catchesEverything(rule *yaml.Node) bool {
	rule = resolveAlias(rule)
	if rule == nil || rule.Kind != yaml.ScalarNode {
		return false
	}
	head, _, found := strings.Cut(rule.Value, ",")
	return found && strings.EqualFold(strings.TrimSpace(head), "MATCH")
}

// A config is rebuilt on every apply and a DNS list can outlive the section
// that carried it, so a value already there is left as the one entry it was.
func appendUnique(sequence *yaml.Node, value *yaml.Node) *yaml.Node {
	sequence = resolveAlias(sequence)
	if sequence != nil && sequence.Kind == yaml.SequenceNode {
		for _, item := range sequence.Content {
			item = resolveAlias(item)
			if item != nil && item.Kind == value.Kind && item.Value == value.Value {
				return sequence
			}
		}
	}
	return appendToSequence(sequence, value)
}

func hasProxyNamed(section *yaml.Node, name string) bool {
	section = resolveAlias(section)
	if section == nil || section.Kind != yaml.SequenceNode {
		return false
	}
	for _, item := range section.Content {
		item = resolveAlias(item)
		if item == nil || item.Kind != yaml.MappingNode {
			continue
		}
		if value := mappingValue(item, "name"); value != nil && value.Value == name {
			return true
		}
	}
	return false
}

// withTailscale applies the node to a config that arrives as bytes, which is
// the path a custom profile takes: it has no base to merge, so its own yaml is
// the whole document the tunnel is built from.
func withTailscale(buf []byte, node *TailscaleInject) ([]byte, error) {
	var document yaml.Node
	if err := yaml.Unmarshal(buf, &document); err != nil {
		return nil, err
	}
	root, err := documentMapping(&document)
	if err != nil {
		return nil, err
	}
	if err := injectTailscale(root, node); err != nil {
		return nil, err
	}
	return yaml.Marshal(&yaml.Node{Kind: yaml.DocumentNode, Content: []*yaml.Node{root}})
}
