import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app keeps two overlays but writes at most one, so what `easyTierInjectOf`
/// decides is the whole of whether a node exists. Getting it wrong either
/// writes a node that cannot work or drops one that could.
void main() {
  const props = EasyTierProps(
    inject: true,
    networkName: 'watermeko-easytier',
    networkSecret: 'secret',
    hostname: 'phone',
  );

  test('a node the user turned on is written with its network', () {
    final node = easyTierInjectOf(props);

    expect(node, isNotNull);
    expect(node!.name, kEasyTierProxyName);
    expect(node.networkName, 'watermeko-easytier');
    expect(node.networkSecret, 'secret');
    expect(node.hostname, 'phone');
    expect(node.stateDir, kEasyTierStateDir);
  });

  test('a node the user turned off is not written at all', () {
    expect(easyTierInjectOf(props.copyWith(inject: false)), isNull);
  });

  // A node with no network name would join nothing and hold no address, so the
  // app writes none rather than one that cannot work.
  test('a node with no network name is no node', () {
    expect(easyTierInjectOf(props.copyWith(networkName: '')), isNull);
    expect(easyTierInjectOf(props.copyWith(networkName: '   ')), isNull);
  });

  // An address the user did not pin is one the network hands out, which is what
  // a phone that only connects out wants.
  test('a node with no address of its own asks the network for one', () {
    expect(easyTierInjectOf(props.copyWith(ipv4: ''))?.dhcp, isTrue);
    expect(
      easyTierInjectOf(props.copyWith(ipv4: '10.126.126.9', dhcp: false))?.dhcp,
      isFalse,
    );
  });

  // Empty rows are what a list editor leaves behind, and a peer of "" is a
  // connection to nothing.
  test('empty peers are dropped rather than written', () {
    final node = easyTierInjectOf(
      props.copyWith(peers: ['tcp://relay.test:11010', '', '  ']),
    );

    expect(node!.peers, ['tcp://relay.test:11010']);
  });

  test(
    'the network name is trimmed so a stray space cannot split a network',
    () {
      final node = easyTierInjectOf(props.copyWith(networkName: ' mesh '));

      expect(node!.networkName, 'mesh');
    },
  );

  test('a choice of EasyTier is read back as a choice of EasyTier', () {
    expect(MeshKind.fromJson('easyTier'), MeshKind.easyTier);
    expect(MeshKind.fromJson('tailscale'), MeshKind.tailscale);
    // An older config has no key at all, and one that says something unknown
    // is a config from a build that knows more.
    expect(MeshKind.fromJson(null), MeshKind.tailscale);
    expect(MeshKind.fromJson('nonsense'), MeshKind.tailscale);
  });

  group('the two overlays keep their own settings', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('turning one on does not clear the other', () {
      container
          .read(easyTierSettingProvider.notifier)
          .update((state) => state.copyWith(inject: true, networkName: 'mesh'));
      container
          .read(tailscaleSettingProvider.notifier)
          .update((state) => state.copyWith(inject: true, hostname: 'phone'));

      expect(container.read(easyTierSettingProvider).networkName, 'mesh');
      expect(container.read(tailscaleSettingProvider).hostname, 'phone');
    });

    test('the default choice is the one the app shipped with', () {
      expect(container.read(meshKindSettingProvider), MeshKind.tailscale);
    });
  });
}
