import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/tailscale.dart' show maskSecret;
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The EasyTier node as a page of its own: the network it joins, the machines
/// it reached, and the settings that decide both.
///
/// EasyTier has no account and no login, which is what the page shows instead
/// of one: a network name and secret are the whole of what identifies a
/// network, and the peers are where a node goes to find it. Nothing here
/// replaces a key, so there is no sign-in and nothing to sign out of.
class EasyTierView extends ConsumerStatefulWidget {
  const EasyTierView({super.key});

  @override
  ConsumerState<EasyTierView> createState() => _EasyTierViewState();
}

class _EasyTierViewState extends ConsumerState<EasyTierView> {
  Timer? _poll;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    // The core starts the node on the first dial and pushes nothing about it,
    // so a page that opens early would otherwise sit on a stale view until the
    // next apply. Poll while the node is not settled and stop when it is.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _read());
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    if (!ref.read(easyTierSettingProvider).inject) {
      _settle();
      return;
    }
    if (_reading) {
      return;
    }
    _reading = true;
    try {
      await ref.read(easyTiersProvider.notifier).readAll();
    } catch (_) {
      // A read that fails leaves the page as it was and the next tick tries
      // again, so a node that is still coming up is not worth a dialog.
    } finally {
      _reading = false;
    }
    final status = ref.read(easyTierStatusProvider);
    if (status != null && status.connected) {
      _settle();
    }
  }

  /// A node that has reached its peers reports nothing further on its own, so
  /// polling is what carries the first seconds only.
  void _settle() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final props = ref.watch(easyTierSettingProvider);
    final status = ref.watch(easyTierStatusProvider);
    final on = props.inject;
    return CommonScaffold(
      title: appLocalizations.easyTier,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.contentTopPadding,
          bottom: 20 + context.bottomInset,
        ),
        children: [
          _StatusCard(props: props, status: status),
          if (on) ...[
            const SizedBox(height: 16),
            ..._buildNetworkSection(context, ref, props),
            const SizedBox(height: 16),
            ..._buildNodeSection(context, ref, props),
            if (status != null && status.peers.isNotEmpty) ...[
              const SizedBox(height: 16),
              ..._buildPeersSection(context, status),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _buildNetworkSection(
    BuildContext context,
    WidgetRef ref,
    EasyTierProps props,
  ) {
    final appLocalizations = context.appLocalizations;
    return [
      ChipTitle(title: appLocalizations.easyTierNetwork),
      CommonCard(
        child: Column(
          children: [
            ConfigTextItem(
              leading: const GlyphIcon(AppGlyphs.layers),
              selector: easyTierSettingProvider.select(
                (state) => state.networkName,
              ),
              title: (l) => l.easyTierNetworkName,
              maxLength: TextInputLimits.name,
              onChanged: (ref, value) {
                ref
                    .read(easyTierSettingProvider.notifier)
                    .update((state) => state.copyWith(networkName: value));
              },
            ),
            ConfigTextItem(
              leading: const GlyphIcon(AppGlyphs.key),
              selector: easyTierSettingProvider.select(
                (state) => state.networkSecret,
              ),
              title: (l) => l.easyTierNetworkSecret,
              maxLength: TextInputLimits.name,
              obscureText: true,
              // The dialog hides what is typed; the row hides what is kept, so
              // a secret on screen is never the secret itself.
              valueText: maskSecret,
              onChanged: (ref, value) {
                ref
                    .read(easyTierSettingProvider.notifier)
                    .update((state) => state.copyWith(networkSecret: value));
              },
            ),
            ConfigTextItem(
              leading: const GlyphIcon(AppGlyphs.devices),
              selector: easyTierSettingProvider.select(
                (state) => state.hostname,
              ),
              title: (l) => l.hostname,
              maxLength: TextInputLimits.name,
              allowEmpty: true,
              onChanged: (ref, value) {
                ref
                    .read(easyTierSettingProvider.notifier)
                    .update((state) => state.copyWith(hostname: value));
              },
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildNodeSection(
    BuildContext context,
    WidgetRef ref,
    EasyTierProps props,
  ) {
    final appLocalizations = context.appLocalizations;
    return [
      ChipTitle(title: appLocalizations.easyTierPeers),
      CommonCard(
        child: Column(
          children: [
            ConfigTextItem(
              leading: const GlyphIcon(AppGlyphs.connections),
              selector: easyTierSettingProvider.select(
                (state) => state.peers.join('\n'),
              ),
              title: (l) => l.easyTierPeerList,
              maxLength: TextInputLimits.url,
              allowEmpty: true,
              valueText: (value) => value.replaceAll('\n', ', '),
              onChanged: (ref, value) {
                ref
                    .read(easyTierSettingProvider.notifier)
                    .update(
                      (state) => state.copyWith(
                        peers: value
                            .split('\n')
                            .map((peer) => peer.trim())
                            .where((peer) => peer.isNotEmpty)
                            .toList(),
                      ),
                    );
              },
            ),
            ConfigToggleItem(
              leading: const GlyphIcon(AppGlyphs.devices),
              selector: easyTierSettingProvider.select(
                (state) => state.noListener,
              ),
              title: (l) => l.easyTierNoListener,
              onChanged: (ref, value) {
                ref
                    .read(easyTierSettingProvider.notifier)
                    .update((state) => state.copyWith(noListener: value));
              },
            ),
            ConfigToggleItem(
              leading: const GlyphIcon(AppGlyphs.bolt),
              selector: easyTierSettingProvider.select((state) => state.udp),
              title: (l) => l.easyTierUdp,
              onChanged: (ref, value) {
                ref
                    .read(easyTierSettingProvider.notifier)
                    .update((state) => state.copyWith(udp: value));
              },
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildPeersSection(BuildContext context, EasyTierStatus status) {
    final appLocalizations = context.appLocalizations;
    return [
      ChipTitle(
        title: appLocalizations.tailscaleMachinesCount(status.peers.length),
      ),
      CommonCard(
        child: Column(
          children: [
            for (final peer in status.peers)
              _MachineItem(key: ValueKey(peer.ipv4), peer: peer),
          ],
        ),
      ),
    ];
  }
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.props, required this.status});

  final EasyTierProps props;
  final EasyTierStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final on = props.inject;
    return CommonCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const GlyphIcon(AppGlyphs.easytier),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appLocalizations.easyTier,
                    style: AppTextStyle.title2.of(context),
                  ),
                ),
                CommonSwitch(
                  value: on,
                  onChanged: (value) {
                    ref
                        .read(easyTierSettingProvider.notifier)
                        .update((state) => state.copyWith(inject: value));
                  },
                ),
              ],
            ),
            if (on) ...[
              const SizedBox(height: 8),
              Text(
                _stateLabel(appLocalizations, status, ref),
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(
                      color: status?.connected == true
                          ? context.colorScheme.primary
                          : context.colorScheme.onSurfaceVariant,
                    ),
              ),
              if (status?.ipv4.isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                SelectableText(
                  status!.ipv4,
                  style: AppTextStyle.footnote.of(context),
                ),
              ],
              if (status?.error.isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                Text(
                  status!.error,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.error),
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              Text(
                appLocalizations.easyTierOffTip,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _stateLabel(
    AppLocalizations l,
    EasyTierStatus? status,
    WidgetRef ref,
  ) {
    if (!props.inject) {
      return l.tailscaleOff;
    }
    if (props.networkName.trim().isEmpty) {
      // A node with no network name is one that would join nothing, so it is
      // not starting: it is waiting for the user.
      return l.easyTierNeedsNetwork;
    }
    if (status == null) {
      // Nothing to show is not the same as a node coming up: with no core
      // there is nothing that would answer.
      return ref.watch(coreStatusProvider) == CoreStatus.connected
          ? l.tailscaleStarting
          : l.tailscaleNotStarted;
    }
    if (status.connected) {
      return l.easyTierConnected;
    }
    return switch (status.state) {
      'running' => l.easyTierConnecting,
      '' || 'created' => l.tailscaleNotStarted,
      _ => status.state,
    };
  }
}

/// One machine the overlay reached, with the path it is reached over.
class _MachineItem extends StatelessWidget {
  const _MachineItem({super.key, required this.peer});

  final EasyTierPeer peer;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final details = [
      if (peer.ipv4.isNotEmpty) peer.ipv4,
      // A direct peer is the one worth naming the transport for; a relayed
      // path says so by its length instead.
      if (peer.tunnel.isNotEmpty) peer.tunnel,
      if (peer.pathLen > 1) appLocalizations.easyTierRelayed(peer.pathLen),
      if (peer.latencyMs > 0) '${peer.latencyMs} ms',
    ];
    return ListItem(
      leading: const GlyphIcon(AppGlyphs.devices),
      title: Text(
        peer.hostname.isEmpty ? (peer.ipv4) : peer.hostname,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
    );
  }
}
