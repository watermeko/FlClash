part of '../state.dart';

/// How the core names an EasyTier outbound in a proxy's `type`.
const _easyTierType = 'easytier';

/// The outbound the app injects. Its group takes a different name, because
/// mihomo reads a member of the group's own name as a loop.
const kEasyTierProxyName = 'EasyTier';

/// The policy group the app injects, the one the overlay's range points at.
const kEasyTierGroupName = 'Mesh';

/// Where the node keeps the identity it joins a network with. One directory for
/// the injected node, so a reset is a single decision rather than one per
/// profile.
const kEasyTierStateDir = 'easytier';

/// The node the app keeps in every profile, or null when the user left this
/// overlay off. This is the only place that decides both, so the page and the
/// config it drives cannot disagree about whether a node exists.
///
/// A node with no network name is no node at all: it would join nothing and
/// hold no address, so the app writes none rather than one that cannot work.
EasyTierInject? easyTierInjectOf(EasyTierProps props) {
  if (!props.inject || props.networkName.trim().isEmpty) {
    return null;
  }
  return EasyTierInject(
    name: kEasyTierProxyName,
    networkName: props.networkName.trim(),
    networkSecret: props.networkSecret,
    hostname: props.hostname,
    ipv4: props.ipv4,
    // A node that holds no address of its own asks the network for one, which
    // is what a phone that only ever connects out wants.
    dhcp: props.dhcp || props.ipv4.trim().isEmpty,
    peers: props.peers.where((peer) => peer.trim().isNotEmpty).toList(),
    noListener: props.noListener,
    stateDir: kEasyTierStateDir,
    udp: props.udp,
  );
}

/// The overlay state of the injected node, if the core has reported one.
@Riverpod(retry: _noRetry)
EasyTierStatus? easyTierStatus(Ref ref) =>
    ref.watch(easyTiersProvider.select((state) => state[kEasyTierProxyName]));

/// Whether an EasyTier outbound exists in the running config at all, which is
/// what a page has to know before it can say anything about the node.
@Riverpod(retry: _noRetry)
bool easyTierPresent(Ref ref) {
  final groups = ref
      .watch(groupsProvider.select((state) => SelectValue(state)))
      .value;
  return groups.any(
    (group) =>
        group.all.any((proxy) => proxy.type.toLowerCase() == _easyTierType),
  );
}

/// Every EasyTier state the core has reported, by proxy name.
///
/// Unlike Tailscale there is nothing pushed: EasyTier reports no events of its
/// own to the host, so a page reads what it wants rather than waiting for a
/// change to arrive.
@Riverpod(retry: _noRetry)
class EasyTiers extends _$EasyTiers {
  @override
  Map<String, EasyTierStatus> build() {
    ref.listen(coreStatusProvider, (_, next) {
      if (next == CoreStatus.connected) {
        readAll().ignore();
      } else {
        state = const {};
      }
    });
    return const {};
  }

  void setStatus(EasyTierStatus status) {
    state = {...state, status.name: status};
  }

  /// Drops what the core no longer knows about: an overlay that went away has
  /// no peers left to list, and keeping the last answer would show machines
  /// that are not there.
  void clearStatus(String name) {
    if (!state.containsKey(name)) {
      return;
    }
    state = {...state}..remove(name);
  }

  /// Reads the node the app injects. The first read can land while the node is
  /// still starting, so a page that wants a live state polls what it cannot
  /// wait for.
  Future<void> readAll() async {
    const names = [kEasyTierProxyName];
    for (final name in names) {
      try {
        final status = await ref.read(coreHandlerProvider).easyTierStatus(name);
        if (!ref.mounted) {
          return;
        }
        if (status != null) {
          setStatus(status);
        } else {
          clearStatus(name);
        }
      } catch (error) {
        commonPrint.log('Unable to read the EasyTier status of $name: $error');
      }
    }
  }
}
