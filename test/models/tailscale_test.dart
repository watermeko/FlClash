import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';

TailscaleStatus _running({String magicDns = 'tail72614b.ts.net'}) =>
    TailscaleStatus.fromJson({
      'name': kTailscaleProxyName,
      'backend-state': 'Running',
      'magic-dns': magicDns,
      'hostname': 'phone',
      'online': true,
      'have-node-key': true,
      'ips': ['100.64.0.1'],
    });

void main() {
  group('the node the app injects', () {
    test('is absent while the user has the mesh off', () {
      final inject = tailscaleInjectOf(const TailscaleProps());

      expect(inject, isNull);
    });

    test('carries every setting the core reads, under the keys it reads', () {
      final inject = tailscaleInjectOf(
        const TailscaleProps(
          inject: true,
          authKey: 'tskey-auth-test',
          hostname: 'phone',
          exitNode: 'nas',
          exitNodeAllowLanAccess: true,
          acceptRoutes: true,
          ephemeral: true,
          controlUrl: 'https://controlplane.tailscale.com',
          udp: false,
        ),
        status: _running(),
      );

      expect(inject, isNotNull);
      expect(inject!.name, kTailscaleProxyName);
      expect(inject.authKey, 'tskey-auth-test');
      expect(inject.hostname, 'phone');
      expect(inject.exitNode, 'nas');
      expect(inject.exitNodeAllowLanAccess, isTrue);
      expect(inject.acceptRoutes, isTrue);
      expect(inject.ephemeral, isTrue);
      expect(inject.controlUrl, 'https://controlplane.tailscale.com');
      expect(inject.udp, isFalse);
      expect(inject.stateDir, kTailscaleStateDir);
    });

    test('reaches the core as the json keys it decodes', () {
      final json = tailscaleInjectOf(
        const TailscaleProps(inject: true, exitNode: 'nas'),
        status: _running(),
      )!.toJson();

      expect(json['auth-key'], '');
      expect(json['exit-node'], 'nas');
      expect(json['state-dir'], kTailscaleStateDir);
      expect(json['accept-routes'], isFalse);
      expect(json['magic-dns-suffix'], 'tail72614b.ts.net');
    });

    test('takes the DNS suffix from the node rather than from the settings', () {
      final withoutNode = tailscaleInjectOf(const TailscaleProps(inject: true));
      final running = tailscaleInjectOf(
        const TailscaleProps(inject: true),
        status: _running(),
      );

      // Nothing is known about the tailnet until the node is logged in, and a
      // guessed suffix would point the rule at a domain the node does not own.
      expect(withoutNode!.magicDnsSuffix, isEmpty);
      expect(running!.magicDnsSuffix, 'tail72614b.ts.net');
    });

    test('keeps the group name apart from the outbound name', () {
      expect(
        kTailscaleGroupName,
        isNot(kTailscaleProxyName),
        reason: 'mihomo reads a member of its own group name as a loop',
      );
    });
  });

  group('TailscaleStatus', () {
    test('decodes the envelope the core sends', () {
      final status = TailscaleStatus.fromJson({
        'name': 'Tailscale',
        'backend-state': 'Running',
        'auth-url': '',
        'hostname': 'phone',
        'dns-name': 'phone.tailnet.ts.net.',
        'magic-dns': 'tailnet.ts.net',
        'online': true,
        'have-node-key': true,
        'ips': ['100.64.0.1'],
        'health': <String>[],
        'peers': [
          {
            'hostname': 'nas',
            'dns-name': 'nas.tailnet.ts.net.',
            'os': 'linux',
            'ips': ['100.64.0.2'],
            'online': true,
            'exit-node-option': true,
            'exit-node': false,
            'relay': 'hkg',
            'cur-addr': '203.0.113.7:41641',
            'rx-bytes': 1024,
            'tx-bytes': 2048,
          },
        ],
      });

      expect(status.isRunning, isTrue);
      expect(status.needsLogin, isFalse);
      expect(status.primaryIp, '100.64.0.1');
      expect(status.peers.single.hostname, 'nas');
      expect(status.peers.single.exitNodeOption, isTrue);
      expect(status.peers.single.rxBytes, 1024);
      expect(status.exitNode, isNull);
    });

    test('reads a node that still needs its first sign-in', () {
      final status = TailscaleStatus.fromJson({
        'name': 'Tailscale',
        'backend-state': 'NeedsLogin',
        'auth-url': 'https://login.tailscale.com/a/abc',
        'have-node-key': false,
      });

      expect(status.needsLogin, isTrue);
      expect(status.isRunning, isFalse);
      expect(status.authUrl, 'https://login.tailscale.com/a/abc');
      expect(status.haveNodeKey, isFalse);
      expect(status.ips, isEmpty);
      expect(status.peers, isEmpty);
    });

    test('keeps every field the core omits at a usable default', () {
      final status = TailscaleStatus.fromJson({
        'name': 'Tailscale',
        'backend-state': 'NoState',
      });

      expect(status.backendState, 'NoState');
      expect(status.authUrl, isEmpty);
      expect(status.ips, isEmpty);
      expect(status.health, isEmpty);
      expect(status.exitNode, isNull);
      expect(status.primaryIp, isNull);
    });
  });
}
