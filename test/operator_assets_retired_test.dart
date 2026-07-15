import 'dart:io';

import 'package:test/test.dart';

/// The hand-authored operator-asset copies are RETIRED.
///
/// This repo used to carry its OWN copies of the operator manual —
/// `extension/skills/*/SKILL.md` + `extension/agents/governor.md`, adopted into
/// the harness's load paths as `.claude/` SYMLINKS and declared in an
/// `extension/mcp/config.yaml` manifest as if this repo VENDED them. It does
/// not: `grid_assets` is the ONE authored home, and this repo is a COMPOSITION
/// that INSTALLS the vended `station_overlay` (`space assets install`) —
/// generated files, each carrying the provenance stamp that makes `--check` able
/// to catch an out-of-band edit.
///
/// The symlink case is not incidental: the installer BLOCKS a symlinked target
/// (writing through it would mutate a file OUTSIDE the target root) and never
/// clobbers a file it did not generate. If a link — or a hand-authored copy —
/// comes back, the install it would block, and the drift the stamp exists to
/// prevent, come back with it.
void main() {
  const installed = <String>[
    '.claude/agents/governor.md',
    '.claude/settings.json',
    '.claude/skills/discover/SKILL.md',
    '.claude/skills/gate-medicine/SKILL.md',
    '.claude/skills/harvest-review/SKILL.md',
    '.claude/skills/intake-grooming/SKILL.md',
    '.claude/skills/release/SKILL.md',
    '.claude/skills/station-operations/SKILL.md',
  ];

  test('this repo vends NO operator assets of its own — extension/ is gone', () {
    expect(
      Directory('extension').existsSync(),
      isFalse,
      reason:
          'the hand-authored asset pack (four skills, the governor agent-def, '
          'the extension/mcp manifest) is retired: grid_assets is the authored '
          'home, and this repo installs what it vends',
    );
  });

  test('nothing under .claude/ is a SYMLINK — the installed assets are real, '
      'generated files (the installer BLOCKS a link)', () {
    final links = Directory('.claude')
        .listSync(recursive: true, followLinks: false)
        .whereType<Link>()
        .map((link) => link.path)
        .toList();
    expect(links, isEmpty, reason: 'symlinked assets:\n  ${links.join('\n  ')}');
  });

  test('every installed operator asset is present and PROVENANCE-STAMPED', () {
    for (final relative in installed) {
      final file = File(relative);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            '$relative is missing — run `dart run bin/space.dart assets install`',
      );
      expect(
        file.readAsStringSync(),
        contains('generated from grid_assets@'),
        reason:
            '$relative is not a generated file — a hand-authored copy has '
            'shadowed the vended one',
      );
    }
  });
}
