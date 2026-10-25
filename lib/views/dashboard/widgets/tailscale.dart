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
    // How many machines the tailnet holds, short enough to sit at the end of
    // the state line.
    final machines = status != null && (status.peers.isNotEmpty || !mobile)
        ? Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              GlyphIcon(
                AppGlyphs.devices,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              Text(
                appLocalizations.tailscaleMachinesCount(status.peers.length),
                maxLines: 1,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          )
        : null;
    // Which of the two ways signed the node in. It takes a line of its own at
    // the foot of the card: a narrow column cannot hold it beside anything.
    final figures = SizedBox(
      height: figure.style.leading * scale,
      child: Row(
        spacing: 8,
        children: [
          // The state keeps the room it needs; the count gives way, being the
          // one of the two the page repeats elsewhere.
          Expanded(
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
          ?machines,
        ],
      ),
    );
    final auth = _authOf(appLocalizations, status);
    final detail = AppTextStyle.footnote
        .of(context)
        .copyWith(color: colorScheme.onSurfaceVariant);
    return DashboardCard(
      semanticLabel: appLocalizations.tailscale,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On a desktop the card shares its row with the tables, so its height
          // is whatever they need. The lines under the state then give way,
          // least important first, instead of painting past the edge.
          final leading = figure.style.leading * scale;
          // Each detail line is pinned to its leading, so the count below
          // matches what the text actually paints.
          final footnote = AppTextStyle.footnote.leading * scale;
          var used =
              (mobile ? 26.0 : DashboardCardHeader.height) * scale +
              figure.top +
              leading;
          final room = constraints.maxHeight;
          Widget line(String text) => SizedBox(
            height: footnote,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: detail,
            ),
          );
          final details = <Widget>[];
          for (final text in [?address, ?auth]) {
            if (used + 4 + footnote > room) {
              break;
            }
            details
              ..add(const SizedBox(height: 4))
              ..add(line(text));
            used += 4 + footnote;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
            children: [
              DashboardCardHeader(
                glyph: AppGlyphs.tailscale,
                title: appLocalizations.tailscale,
              ),
              SizedBox(height: figure.top),
              figures,
              ...details,
            ],
          );
        },
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
