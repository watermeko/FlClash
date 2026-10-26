part of '../state.dart';

/// How the core names a Tailscale outbound in a proxy's `type`.
const _tailscaleType = 'tailscale';

/// The outbound the app injects. Its group takes a different name, because
/// mihomo reads a member of the group's own name as a loop.
const kTailscaleProxyName = 'Tailscale';

/// The policy group the app injects, the one the tailnet's ranges point at.
const kTailscaleGroupName = 'Tailnet';

/// Where the node keeps its key. One directory for the injected node, so a
/// reset is a single decision rather than one per profile.
const kTailscaleStateDir = 'tailscale';

/// The node the app keeps in every profile, or null when the user left the
/// mesh off. This is the only place that decides both, so the page and the
/// config it drives cannot disagree about whether a node exists.
TailscaleInject? tailscaleInjectOf(
  TailscaleProps props, {
  TailscaleStatus? status,
}) {
  if (!props.inject) {
    return null;
  }
  return TailscaleInject(
    name: kTailscaleProxyName,
    authKey: props.authKey,
    hostname: props.hostname,
    controlUrl: props.controlUrl,
    stateDir: kTailscaleStateDir,
    ephemeral: props.ephemeral,
    udp: props.udp,
    acceptRoutes: props.acceptRoutes,
    exitNode: props.exitNode,
    exitNodeAllowLanAccess: props.exitNodeAllowLanAccess,
    // The suffix names the tailnet's machines, and only the node knows it: it
    // is empty until the node is logged in, so the rule that uses it waits.
    magicDnsSuffix: status?.magicDns ?? '',
  );
}

/// The status of the injected node, if the core has reported one.
@Riverpod(retry: _noRetry)
TailscaleStatus? tailscaleStatus(Ref ref) =>
    ref.watch(tailscalesProvider.select((state) => state[kTailscaleProxyName]));

/// Whether a Tailscale outbound exists in the running config at all, which is
/// what a page has to know before it can say anything about the node.
@Riverpod(retry: _noRetry)
bool tailscalePresent(Ref ref) {
  final groups = ref
      .watch(groupsProvider.select((state) => SelectValue(state)))
      .value;
  return groups.any(
    (group) =>
        group.all.any((proxy) => proxy.type.toLowerCase() == _tailscaleType),
  );
}

/// Every Tailscale status the core has pushed, by proxy name.
///
/// The core starts a Tailscale backend as soon as an apply installs it and
/// pushes each change after that, so a page opening later reads the ones it
/// missed rather than waiting for the next event.
@Riverpod(retry: _noRetry)
class Tailscales extends _$Tailscales {
  @override
  Map<String, TailscaleStatus> build() {
    ref.listen(coreStatusProvider, (_, next) {
      if (next == CoreStatus.connected) {
        readAll().ignore();
      } else {
        state = const {};
      }
    });
    return const {};
  }

  void setStatus(TailscaleStatus status) {
    state = {...state, status.name: status};
  }

  /// Reads the node the app injects. The core starts it itself after an apply
  /// and pushes each change after that, but the first read can land while the
  /// node is still starting and the apply that follows reports nothing new, so
  /// a page that wants a live state polls what it cannot wait for.
  Future<void> readAll() async {
    const names = [kTailscaleProxyName];
    for (final name in names) {
      try {
        final status = await ref
            .read(coreHandlerProvider)
            .tailscaleStatus(name);
        if (!ref.mounted) {
          return;
        }
        if (status != null) {
          setStatus(status);
        }
      } catch (error) {
        commonPrint.log('Unable to read the Tailscale status of $name: $error');
      }
    }
  }

  /// Starts the backend and reads what it reports, for a node the core has not
  /// brought up because no apply has run since it was turned on.
  Future<void> start() async {
    const name = kTailscaleProxyName;
    await ref.read(coreHandlerProvider).startTailscale(name);
    final status = await ref.read(coreHandlerProvider).tailscaleStatus(name);
    if (ref.mounted && status != null) {
      setStatus(status);
    }
  }

  /// The URL a browser has to open to finish a login. A node that is already
  /// signed in has none, which is why the page has to ask rather than read the
  /// status: the URL control hands out is not kept in it.
  Future<String> loginUrl() async {
    final url = await ref
        .read(coreHandlerProvider)
        .tailscaleLoginUrl(kTailscaleProxyName);
    if (url.isNotEmpty) {
      final status = await ref
          .read(coreHandlerProvider)
          .tailscaleStatus(kTailscaleProxyName);
      if (ref.mounted && status != null) {
        setStatus(status);
      }
    }
    return url;
  }

  /// Signs the node out and forgets what was reported about it, so another
  /// account can claim the state directory the node keeps.
  Future<void> logout() async {
    await ref.read(coreHandlerProvider).logoutTailscale(kTailscaleProxyName);
    state = {...state}..remove(kTailscaleProxyName);
  }
}
