import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/easytier.dart';
import 'package:fl_clash/views/tailscale.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one page both overlays live on. The user picks which one, and the page
/// follows: the navigation entry keeps its place and its label, so switching
/// does not move the mesh somewhere else in the sidebar.
///
/// Keyed by the choice so a switch rebuilds the page rather than handing one
/// overlay's state to the other's widget.
class MeshView extends ConsumerWidget {
  const MeshView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meshKind = ref.watch(meshKindSettingProvider);
    return switch (meshKind) {
      MeshKind.tailscale => const TailscaleView(key: ValueKey('tailscale')),
      MeshKind.easyTier => const EasyTierView(key: ValueKey('easytier')),
    };
  }
}
