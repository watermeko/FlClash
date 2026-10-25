import 'dart:io';

import 'package:fl_clash/ui/icons/icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the lattice draws the published Tailscale path', () {
    final svg = File('assets/images/services/tailscale.svg').readAsStringSync();
    final published = RegExp(r'\sd="([^"]+)"').firstMatch(svg)!.group(1)!;

    expect(GlyphLattice.path, published);
  });
}
