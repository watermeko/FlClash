import 'dart:io';

import 'package:test/test.dart';

/// A `-keep class some.package.**` rule protects nothing once that package is
/// renamed, and the build still succeeds: the classes are simply obfuscated, and
/// only a minified release fails, at whatever reflection reaches them first.
/// `icu.watermeko.clash.service.models` was kept under its previous name for one
/// release, which is how `VpnOptions` reached a phone as `lk1` and Gson answered
/// "Invalid shared state".
final _keepRule = RegExp(r'^\s*-keep\s+class\s+([\w.]+)\.\*\*');

/// gomobile writes these, so no source declares them: `go` is its runtime, and
/// the rest is whatever `-javapkg` names, read from the build that generates it.
final _javaPkg = RegExp(r'"-javapkg=([\w.]+)"');

void main() {
  test('every proguard keep rule names a package the sources still have', () {
    final rules = <String, List<String>>{};
    for (final file in _ruleFiles()) {
      for (final line in file.readAsLinesSync()) {
        final match = _keepRule.firstMatch(line);
        if (match != null) {
          rules.putIfAbsent(match.group(1)!, () => []).add(file.path);
        }
      }
    }

    expect(rules, isNotEmpty, reason: 'no -keep class rules were found');

    // `-javapkg` is a prefix: gobind appends the Go package name to it, so
    // `com.follow.clash.core` yields `com.follow.clash.core.mobile`.
    final generated = {'go', ...?_generatedPackages()};
    bool covers(Set<String> prefixes, String package) =>
        prefixes.any((p) => package == p || package.startsWith('$p.'));
    final packages = _sourcePackages();
    final stale = <String>[
      for (final entry in rules.entries)
        if (!covers(packages, entry.key) && !covers(generated, entry.key))
          '${entry.value.join(', ')}: no source declares package '
              '${entry.key}; a rule for a package that moved protects '
              'nothing',
    ];

    expect(stale, isEmpty, reason: stale.join('\n'));
  });
}

/// The package gomobile's generated classes land in, as the Core's build names
/// it to gobind.
Set<String>? _generatedPackages() {
  final packages = <String>{};
  for (final entity in Directory('android').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.kts')) continue;
    for (final match in _javaPkg.allMatches(entity.readAsStringSync())) {
      packages.add(match.group(1)!);
    }
  }
  return packages;
}

List<File> _ruleFiles() => [
  for (final entity in Directory('android').listSync(recursive: true))
    if (entity is File &&
        (entity.path.endsWith('proguard-rules.pro') ||
            entity.path.endsWith('consumer-rules.pro') ||
            entity.path.endsWith('proguard-rules.txt')))
      entity,
];

/// Every package a Kotlin or Java file under `android/` declares.
Set<String> _sourcePackages() {
  final pattern = RegExp(r'^\s*package\s+([\w.]+)');
  final packages = <String>{};
  for (final entity in Directory('android').listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path;
    if (!path.endsWith('.kt') && !path.endsWith('.java')) continue;
    for (final line in entity.readAsLinesSync()) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        packages.add(match.group(1)!);
        break;
      }
    }
  }
  return packages;
}
