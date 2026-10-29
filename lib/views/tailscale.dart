import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'tailscale_login.dart';
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

class _TailscaleViewState extends ConsumerState<TailscaleView>
    with WidgetsBindingObserver {
  Timer? _poll;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The core starts the node and pushes what changes, but a page that opens
    // during those first seconds would otherwise sit on a stale "starting"
    // until the next change. Poll while the node is not settled and stop as
    // soon as it is.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _read());
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  /// A login finishes in a browser, which takes this page off screen and stops
  /// its timer. The node is signed in by the time it comes back, so the read
  /// that reports it has to happen on return rather than on the next tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    _poll ??= Timer.periodic(const Duration(seconds: 3), (_) => _read());
    _read();
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
    if (status != null && status.isRunning) {
      _settle();
    }
  }

  /// A node that is running reports its own changes from then on, so polling is
  /// what carries the first seconds only. A node still waiting for a login is
  /// not settled: the browser finishes it out of sight of this timer.
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

  var _refreshing = false;

  Future<void> _refresh(WidgetRef ref) async {
    setState(() => _refreshing = true);
    try {
      await ref.read(tailscalesProvider.notifier).readAll();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Widget _buildNodeSection(
    BuildContext context,
    WidgetRef ref,
    TailscaleProps props,
    TailscaleStatus? status,
  ) {
    final appLocalizations = context.appLocalizations;
    final signedInWithBrowser = status?.signedInWithBrowser ?? false;
    final signedInWithKey = status?.signedInWithKey ?? false;
    return generateSection(
      title: appLocalizations.tailscaleAccount,
      items: [
        // The two ways of signing in are alternatives, not switches: each one
        // replaces whoever holds the node now, so a row that would drop that
        // asks first.
        ConfigTextItem(
          leading: const GlyphIcon(AppGlyphs.key),
          selector: tailscaleSettingProvider.select((state) => state.authKey),
          title: (l) => l.tailscaleAuthKey,
          maxLength: TextInputLimits.password,
          allowEmpty: true,
          obscureText: true,
          valueText: maskSecret,
          confirm: (value) =>
              _confirmReplacement(context, ref, value, signedInWithBrowser),
          onChanged: (ref, value) {
            ref
                .read(tailscaleSettingProvider.notifier)
                .update((state) => state.copyWith(authKey: value));
            // A key only signs a node in on the apply that installs it, and the
            // page has already said what that costs, so the node is brought up
            // rather than left waiting for the next unrelated change.
            if (value.isNotEmpty) {
              ref.read(coreHandlerProvider).startTailscale(kTailscaleProxyName);
            }
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
          onTap: () => _handleLogin(context, ref, signedInWithKey),
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
      // The list is what a user opens the page to read, and the numbers in it
      // only move when somebody asks: the refresh reads the node's own view of
      // its peers rather than waiting for the next push.
      actions: [
        IconButtonData(
          glyph: AppGlyphs.sync,
          onPressed: _refreshing ? null : () => _refresh(ref),
          tooltip: appLocalizations.tailscaleRefresh,
          isLoading: _refreshing,
        ),
      ],
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

  Future<void> _handleLogin(
    BuildContext context,
    WidgetRef ref,
    bool signedInWithKey,
  ) async {
    final appLocalizations = context.appLocalizations;
    // A browser login replaces whatever signed the node in, so the two stay
    // alternatives rather than one quietly winning over the other. A node that
    // is signed in will not ask control for a page at all, so replacing the key
    // means signing out first.
    if (signedInWithKey && !await _confirmSignInWithBrowser(context)) {
      return;
    }
    final notifier = ref.read(tailscalesProvider.notifier);
    if (signedInWithKey) {
      try {
        await notifier.logout();
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
    }
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
      // A node that is signed in has nothing to finish, and one the Core has not
      // reported yet has not started; only the first of those may claim the
      // node is already signed in.
      final known = ref.read(
        tailscalesProvider.select((state) => state[kTailscaleProxyName]),
      );
      await dialogs.showAlert(
        message: TextSpan(
          text: known == null
              ? appLocalizations.tailscaleStarting
              : appLocalizations.tailscaleLoginUnavailable,
        ),
      );
      return;
    }
    // The key signed the node in that the login just dropped, so it goes rather
    // than staying in the config to claim the login afterwards.
    if (signedInWithKey) {
      ref
          .read(tailscaleSettingProvider.notifier)
          .update((state) => state.copyWith(authKey: ''));
      await ref.read(coreHandlerProvider).startTailscale(kTailscaleProxyName);
    }
    // A phone keeps the page in the app: an external browser leaves the app,
    // and the node's waiting registration is only answered while the app runs.
    if (system.isAndroid || Platform.isIOS) {
      if (!context.mounted) {
        return;
      }
      final navigatorContext = context;
      final signedIn = await BaseNavigator.push<bool>(
        navigatorContext,
        TailscaleLoginView(url: url),
      );
      if (signedIn == true) {
        await notifier.readAll();
      }
      return;
    }
    await dialogs.openUrl(url);
  }

  /// A key and a browser login both hold the node, so setting one drops the
  /// other. This is what asks before that happens.
  Future<bool> _confirmReplacement(
    BuildContext context,
    WidgetRef ref,
    String value,
    bool signedInWithBrowser,
  ) async {
    if (value.isEmpty || !signedInWithBrowser) {
      return true;
    }
    final appLocalizations = context.appLocalizations;
    final confirmed = await dialogs.showMessage(
      title: appLocalizations.tailscaleAuthKey,
      message: TextSpan(text: appLocalizations.tailscaleReplaceBrowserLoginTip),
      confirmText: appLocalizations.confirm,
    );
    if (confirmed != true) {
      return false;
    }
    // Signing out is what drops the key the browser login left behind, so the
    // new key signs the node in on the apply that follows.
    try {
      await ref.read(tailscalesProvider.notifier).logout();
    } catch (_) {
      // A node that was not signed in has nothing to drop, which is not worth
      // stopping the key from being saved.
    }
    return true;
  }

  Future<bool> _confirmSignInWithBrowser(BuildContext context) async {
    final appLocalizations = context.appLocalizations;
    final confirmed = await dialogs.showMessage(
      title: appLocalizations.tailscaleLogin,
      message: TextSpan(text: appLocalizations.tailscaleReplaceAuthKeyTip),
      confirmText: appLocalizations.confirm,
    );
    return confirmed == true;
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

/// A secret shown only by its last few characters, enough to tell two keys
/// apart without putting either on screen.
String maskSecret(String value) {
  if (value.length <= 4) {
    return '•' * value.length;
  }
  return '${'•' * 8}${value.substring(value.length - 4)}';
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
    // The path is what the list is for: a peer reached through a relay is slow
    // for a reason a direct one is not, so the relay's region and the round trip
    // are what say which this is.
    final path = peer.curAddr.isNotEmpty
        ? appLocalizations.tailscaleDirect
        : peer.relay.isEmpty
        ? appLocalizations.tailscaleUnknown
        : appLocalizations.tailscaleRelayPath(peer.relay);
    final details = [
      if (peer.ips.isNotEmpty) peer.ips.first,
      if (peer.os.isNotEmpty) peer.os,
      path,
      if (peer.latencyMs > 0) '${peer.latencyMs} ms',
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
