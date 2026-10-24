import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

/// The node at a glance: whether it is up, which address it holds and how it
/// was signed in. It reads the same status the Tailscale page does, so the two
/// never disagree.
class TailscaleCard extends ConsumerWidget {
  const TailscaleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = DashboardDensityScope.of(context);
    final scale = DashboardDensityScope.scaleOf(context);
    final mobile = !density.isDesktop;
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final inject = ref.watch(
      tailscaleSettingProvider.select((state) => state.inject),
    );
    final status = ref.watch(tailscaleStatusProvider);
    final figure = mobile
        ? (style: AppTextStyle.title1, top: 12.0)
        : density.isCompact
        ? (style: AppTextStyle.title2, top: 8.0)
        : (style: AppTextStyle.title2, top: 10.0);
    final style = DashboardText.figure(
      context,
      figure.style,
    ).copyWith(letterSpacing: 0);
    final state = _stateOf(appLocalizations, inject, status);
    final address = status?.primaryIp;
    return DashboardCard(
      semanticLabel: appLocalizations.tailscale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.tailscale,
            title: appLocalizations.tailscale,
          ),
          SizedBox(height: figure.top),
          SizedBox(
            height: figure.style.leading * scale,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                state.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(
                  color: state.running
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // An address is only worth the room once there is one to show; the
          // state above already says why it is missing.
          if (address != null) ...[
            SizedBox(height: mobile ? 6 : 4),
            Text(
              address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
          if (mobile) const SizedBox(height: 14) else const Spacer(),
          if (status != null && (status.peers.isNotEmpty || !mobile))
            Row(
              children: [
                GlyphIcon(
                  AppGlyphs.devices,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    appLocalizations.tailscaleMachinesCount(
                      status.peers.length,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                if (_authOf(appLocalizations, status) case final auth?)
                  Text(
                    auth,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Which of the two ways signed the node in, and nothing while it has no key
  /// to explain.
  String? _authOf(AppLocalizations l, TailscaleStatus? status) {
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

  ({String label, bool running}) _stateOf(
    AppLocalizations l,
    bool inject,
    TailscaleStatus? status,
  ) {
    if (!inject) {
      return (label: l.tailscaleOff, running: false);
    }
    if (status == null) {
      return (label: l.tailscaleStarting, running: false);
    }
    if (status.needsLogin) {
      return (label: l.tailscaleNeedsLogin, running: false);
    }
    if (status.isRunning) {
      return (label: l.tailscaleRunning, running: true);
    }
    return (label: status.backendState, running: false);
  }
}
