import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Tailscale node as a page of its own: what it is signed in as, the
/// machines the tailnet holds, and which of them carries this device's traffic.
///
/// Everything here writes app settings rather than a profile. The node reaches
/// the running config through the injection the setup applies, so no profile
/// has to mention Tailscale and a new subscription keeps working.
class TailscaleView extends ConsumerStatefulWidget {
  const TailscaleView({super.key});

  @override
  ConsumerState<TailscaleView> createState() => _TailscaleViewState();
}

class _TailscaleViewState extends ConsumerState<TailscaleView> {
  Timer? _poll;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    // The core starts the node and pushes what changes, but a page that opens
    // during those first seconds would otherwise sit on a stale "starting"
    // until the next change. Poll while the node is not settled and stop as
    // soon as it is.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _read());
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    if (!ref.read(tailscaleSettingProvider).inject) {
      _settle();
      return;
    }
    if (_reading) {
      return;
    }
    _reading = true;
    try {
      await ref.read(tailscalesProvider.notifier).readAll();
    } catch (_) {
      // A read that fails leaves the last state on screen; the next tick tries
      // again, and the page is not worth an error dialog for it.
    } finally {
      _reading = false;
    }
    final status = ref.read(tailscaleStatusProvider);
    if (status != null && (status.isRunning || status.needsLogin)) {
      _settle();
    }
  }

  /// A node that is running or waiting for a login reports its own changes, so
  /// polling is what carries the first seconds only.
  void _settle() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final props = ref.watch(tailscaleSettingProvider);
    final status = ref.watch(tailscaleStatusProvider);
    return CommonScaffold(
      title: appLocalizations.tailscale,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.contentTopPadding,
          bottom: 20 + context.bottomInset,
        ),
        children: [
          _StatusCard(props: props, status: status),
          if (props.inject) ...[
            const SizedBox(height: 16),
            _buildNodeSection(context, ref, props, status),
            const SizedBox(height: 16),
            _buildMachinesSection(context, ref, status),
            const SizedBox(height: 16),
            // Nothing to route through a node that is not signed in, and the
            // switch that decides where traffic goes belongs after the list it
            // picks from.
            _buildSettingsSection(context, ref, props, status),
          ],
        ],
      ),
    );
  }

  Widget _buildNodeSection(
    BuildContext context,
    WidgetRef ref,
    TailscaleProps props,
    TailscaleStatus? status,
  ) {
    final appLocalizations = context.appLocalizations;
    final signedInWithBrowser = status?.signedInWithBrowser ?? false;
    return generateSection(
      title: appLocalizations.tailscaleAccount,
      items: [
        ConfigTextItem(
          leading: const GlyphIcon(AppGlyphs.key),
          selector: tailscaleSettingProvider.select((state) => state.authKey),
          title: (l) => l.tailscaleAuthKey,
          maxLength: TextInputLimits.password,
          allowEmpty: true,
          onChanged: (ref, value) {
            ref
                .read(tailscaleSettingProvider.notifier)
                .update((state) => state.copyWith(authKey: value));
          },
        ),
        ListItem(
          leading: const GlyphIcon(AppGlyphs.openExternal),
          title: Text(appLocalizations.tailscaleLogin),
          subtitle: Text(
            signedInWithBrowser
                ? appLocalizations.tailscaleLoginDone
                : appLocalizations.tailscaleLoginTip,
          ),
          // A browser login only reports back once control has signed the node
          // in, so the row says which of the two is true rather than repeating
          // that the page can be opened.
          trailing: signedInWithBrowser
              ? GlyphIcon(AppGlyphs.check, color: context.colorScheme.primary)
              : null,
          // The node is started and control asked for a URL on tap: the one in
          // the status is only there while a login is already pending, so
          // reading it first is what made this do nothing once signed in.
          onTap: () => _handleLogin(context, ref),
        ),
        ConfigTextItem(
          leading: const GlyphIcon(AppGlyphs.devices),
          selector: tailscaleSettingProvider.select((state) => state.hostname),
          title: (l) => l.hostname,
          maxLength: TextInputLimits.name,
          allowEmpty: true,
          onChanged: (ref, value) {
            ref
                .read(tailscaleSettingProvider.notifier)
                .update((state) => state.copyWith(hostname: value));
          },
        ),
        if (status != null)
          ListItem(
            leading: const GlyphIcon(AppGlyphs.delete),
            title: Text(appLocalizations.tailscaleLogout),
            onTap: () => _handleLogout(context, ref),
          ),
      ],
    );
  }

  Widget _buildMachinesSection(
    BuildContext context,
    WidgetRef ref,
    TailscaleStatus? status,
  ) {
    final appLocalizations = context.appLocalizations;
    final peers = status?.peers ?? const <TailscalePeer>[];
    if (peers.isEmpty) {
      return generateSection(
        title: appLocalizations.tailscaleMachines,
        items: [
          ListItem(
            title: Text(appLocalizations.tailscaleNoMachines),
            subtitle: Text(appLocalizations.tailscaleNoMachinesTip),
          ),
        ],
      );
    }
    return generateSection(
      title: appLocalizations.tailscaleMachines,
      items: [for (final peer in peers) _MachineItem(peer: peer)],
    );
  }

  Widget _buildSettingsSection(
    BuildContext context,
    WidgetRef ref,
    TailscaleProps props,
    TailscaleStatus? status,
  ) {
    final appLocalizations = context.appLocalizations;
    final exitNodes = [
      for (final peer in status?.peers ?? const <TailscalePeer>[])
        if (peer.exitNodeOption) peer,
    ];
    return generateSection(
      title: appLocalizations.settings,
      items: [
        ConfigToggleItem(
          selector: tailscaleSettingProvider.select(
            (state) => state.acceptRoutes,
          ),
          title: (l) => l.acceptRoutes,
          onChanged: (ref, value) {
            ref
                .read(tailscaleSettingProvider.notifier)
                .update((state) => state.copyWith(acceptRoutes: value));
          },
        ),
        ConfigToggleItem(
          selector: tailscaleSettingProvider.select((state) => state.udp),
          title: (l) => 'UDP',
          onChanged: (ref, value) {
            ref
                .read(tailscaleSettingProvider.notifier)
                .update((state) => state.copyWith(udp: value));
          },
        ),
        if (exitNodes.isNotEmpty) ...[
          ConfigOptionsItem<String>(
            selector: tailscaleSettingProvider.select(
              (state) => state.exitNode,
            ),
            title: (l) => l.exitNodes,
            options: ['', for (final peer in exitNodes) peer.machineName],
            textBuilder: (value) => value.isEmpty
                ? appLocalizations.none
                : exitNodes
                      .firstWhere((peer) => peer.machineName == value)
                      .machineName,
            onChanged: (ref, value) {
              ref
                  .read(tailscaleSettingProvider.notifier)
                  .update((state) => state.copyWith(exitNode: value));
            },
          ),
          if (props.exitNode.isNotEmpty)
            ConfigToggleItem(
              selector: tailscaleSettingProvider.select(
                (state) => state.exitNodeAllowLanAccess,
              ),
              title: (l) => l.exitNodeAllowLanAccess,
              onChanged: (ref, value) {
                ref
                    .read(tailscaleSettingProvider.notifier)
                    .update(
                      (state) => state.copyWith(exitNodeAllowLanAccess: value),
                    );
              },
            ),
        ],
      ],
    );
  }

  Future<void> _handleLogin(BuildContext context, WidgetRef ref) async {
    final appLocalizations = context.appLocalizations;
    final notifier = ref.read(tailscalesProvider.notifier);
    String url;
    try {
      url = await notifier.loginUrl();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      await dialogs.showAlert(message: TextSpan(text: compactError(error)));
      return;
    }
    if (!context.mounted) {
      return;
    }
    if (url.isEmpty) {
      // A node that is signed in has nothing to finish, and one that never
      // started has nothing to continue; both say so instead of opening a
      // page that would not be about this device.
      await dialogs.showAlert(
        message: TextSpan(text: appLocalizations.tailscaleLoginUnavailable),
      );
      return;
    }
    await dialogs.openUrl(url);
  }

  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    final appLocalizations = context.appLocalizations;
    final confirmed = await dialogs.showMessage(
      title: appLocalizations.tailscaleLogout,
      message: TextSpan(text: appLocalizations.tailscaleLogoutTip),
      destructive: true,
      confirmText: appLocalizations.confirm,
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(tailscalesProvider.notifier).logout();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      await dialogs.showAlert(message: TextSpan(text: compactError(error)));
    }
  }
}

/// What the node is doing, in the one place a glance reads it.
class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.props, required this.status});

  final TailscaleProps props;
  final TailscaleStatus? status;

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
                const GlyphIcon(AppGlyphs.tailscale),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appLocalizations.tailscale,
                    style: AppTextStyle.title2.of(context),
                  ),
                ),
                CommonSwitch(
                  value: on,
                  onChanged: (value) {
                    ref
                        .read(tailscaleSettingProvider.notifier)
                        .update((state) => state.copyWith(inject: value));
                  },
                ),
              ],
            ),
            if (on) ...[
              const SizedBox(height: 8),
              Text(
                _stateLabel(appLocalizations, status),
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(
                      color: status?.isRunning == true
                          ? context.colorScheme.primary
                          : context.colorScheme.onSurfaceVariant,
                    ),
              ),
              if (_authLabel(appLocalizations, status) case final method?) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    GlyphIcon(
                      status?.signedInWithKey == true
                          ? AppGlyphs.key
                          : AppGlyphs.openExternal,
                      size: 14,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      method,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ],
              if (status?.ips.isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                SelectableText(
                  status!.ips.join('  '),
                  style: AppTextStyle.footnote.of(context),
                ),
              ],
              for (final problem in status?.health ?? const <String>[]) ...[
                const SizedBox(height: 4),
                Text(
                  problem,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.error),
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              Text(
                appLocalizations.tailscaleOffTip,
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

  /// Which of the two ways signed the node in, and nothing while it has no key
  /// to explain: control cannot tell them apart, so the outbound reports it.
  String? _authLabel(AppLocalizations l, TailscaleStatus? status) {
    if (status == null) {
      return null;
    }
    if (status.signedInWithKey) {
      return l.tailscaleAuthKey;
    }
    if (status.signedInWithBrowser) {
      return l.tailscaleLogin;
    }
    return null;
  }

  String _stateLabel(AppLocalizations l, TailscaleStatus? status) {
    if (!props.inject) {
      return l.tailscaleOff;
    }
    if (status == null) {
      return l.tailscaleStarting;
    }
    if (status.needsLogin) {
      return l.tailscaleNeedsLogin;
    }
    if (status.isRunning) {
      return l.tailscaleRunning;
    }
    return status.backendState;
  }
}

/// One machine in the tailnet, with the path it is reached over.
class _MachineItem extends StatelessWidget {
  const _MachineItem({required this.peer});

  final TailscalePeer peer;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final details = [
      if (peer.os.isNotEmpty) peer.os,
      if (peer.ips.isNotEmpty) peer.ips.first,
      if (peer.exitNode) appLocalizations.tailscaleExitNodeInUse,
    ].join(' · ');
    return ListItem(
      leading: GlyphIcon(
        AppGlyphs.checkCircle,
        color: peer.online
            ? context.colorScheme.primary
            : context.colorScheme.outline,
      ),
      title: Text(peer.hostname.isEmpty ? peer.dnsName : peer.hostname),
      subtitle: Text(details),
    );
  }
}

extension on TailscalePeer {
  /// The name an exit-node choice travels by: the proxy reads a hostname or an
  /// address, and the machine's own name is the stable one.
  String get machineName => hostname.isEmpty ? (primaryIp ?? '') : hostname;

  String? get primaryIp => ips.isEmpty ? null : ips.first;
}
