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

/// The EasyTier node at a glance: whether it is up, which address it holds and
/// how many machines it reached. It reads the same status the EasyTier page
/// does, so the two never disagree.
///
/// It mirrors [TailscaleCard] because the two share a column and a row: the
/// same figure, the same lines under it, and the same giving way when the row
/// is short. EasyTier has no auth method, so that line is the network's name
/// instead.
class EasyTierCard extends ConsumerWidget {
  const EasyTierCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = DashboardDensityScope.of(context);
    final scale = DashboardDensityScope.scaleOf(context);
    final mobile = !density.isDesktop;
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final props = ref.watch(easyTierSettingProvider);
    final status = ref.watch(easyTierStatusProvider);
    final figure = mobile
        ? (style: AppTextStyle.title1, top: 12.0)
        : density.isCompact
        ? (style: AppTextStyle.title2, top: 8.0)
        : (style: AppTextStyle.title2, top: 10.0);
    final style = DashboardText.figure(
      context,
      figure.style,
    ).copyWith(letterSpacing: 0);
    final state = _stateOf(appLocalizations, props, status);
    final address = status?.ipv4;
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
    final figures = SizedBox(
      height: figure.style.leading * scale,
      child: Row(
        spacing: 8,
        children: [
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
    // The network's name stands where the Tailscale card puts the way it was
    // signed in: what this node belongs to is the thing worth naming.
    final network = props.networkName.trim();
    final detail = AppTextStyle.footnote
        .of(context)
        .copyWith(color: colorScheme.onSurfaceVariant);
    return DashboardCard(
      semanticLabel: appLocalizations.easyTier,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final leading = figure.style.leading * scale;
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
          for (final text in [
            ?(address?.isEmpty == false ? address : null),
            ?(network.isEmpty ? null : network),
          ]) {
            if (used + 4 + footnote > room) {
              break;
            }
            details.add(const SizedBox(height: 4));
            details.add(line(text));
            used += 4 + footnote;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mobile)
                SizedBox(
                  height: 26 * scale,
                  child: Row(
                    children: [
                      GlyphIcon(
                        AppGlyphs.easytier,
                        size: 14 * scale,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          appLocalizations.easyTier,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashboardText.label(
                            context,
                          ).copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  height: DashboardCardHeader.height * scale,
                  child: DashboardCardHeader(
                    glyph: AppGlyphs.easytier,
                    title: appLocalizations.easyTier,
                  ),
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

  ({String label, bool running}) _stateOf(
    AppLocalizations l,
    EasyTierProps props,
    EasyTierStatus? status,
  ) {
    if (!props.inject) {
      return (label: l.tailscaleOff, running: false);
    }
    if (props.networkName.trim().isEmpty) {
      return (label: l.easyTierNeedsNetwork, running: false);
    }
    if (status == null) {
      return (label: l.tailscaleStarting, running: false);
    }
    if (status.connected) {
      return (label: l.easyTierConnected, running: true);
    }
    return (label: l.easyTierConnecting, running: false);
  }
}
