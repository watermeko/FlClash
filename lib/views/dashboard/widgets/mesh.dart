import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'easytier.dart';
import 'tailscale.dart';

/// The mesh card, whichever overlay the user chose. The two share a column and
/// a row on the dashboard, so the card keeps its place and only what it says
/// follows the choice.
class MeshCard extends ConsumerWidget {
  const MeshCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meshKind = ref.watch(meshKindSettingProvider);
    return switch (meshKind) {
      MeshKind.tailscale => const TailscaleCard(key: ValueKey('tailscale')),
      MeshKind.easyTier => const EasyTierCard(key: ValueKey('easytier')),
    };
  }
}
