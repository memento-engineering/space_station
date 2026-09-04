import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A PROCESS-LEVEL smoke over the REAL `space` CLI: `space assets install`
/// resolves the REAL vended `station_overlay` from the generated registry and
/// the throwaway root's package facts, then materializes the whole operator
/// manual there. Root-parametric by design (power_station ADR-0000 A26(1)), so
/// this test never touches the repo's own installed tree —
/// `operator_assets_retired_test.dart` guards that.
void main() {
  const vended = <String>[
    '.claude/agents/governor.md',
    '.claude/settings.json',
    '.claude/skills/discover/SKILL.md',
    '.claude/skills/gate-medicine/SKILL.md',
    '.claude/skills/harvest-review/SKILL.md',
    '.claude/skills/intake-refinement/SKILL.md',
    '.claude/skills/release/SKILL.md',
    '.claude/skills/station-operations/SKILL.md',
  ];

  // The WORKSPACE root (the repo, ../../ from this app package): its package
  // config is what names the vended packs, and it is the grid home.
  final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));

  Future<ProcessResult> install(String seat, {bool check = false}) =>
      Process.run(Platform.resolvedExecutable, [
        'bin/space.dart',
        'assets',
        'install',
        if (check) '--check',
        '--no-diff',
        '--grid-home', repoRoot,
        '--root', seat,
        // A FIXED ref — no `git rev-parse` subprocess, and a stable stamp.
        '--source-ref', 'testref',
      ], workingDirectory: Directory.current.path);

  test('`space assets install --root <seat>` materializes the REAL vended '
      'station_overlay — six operator skills, the governor agent-def and the '
      'harness settings, each provenance-stamped; --check is then CURRENT (0) '
      'and LOUD on drift (1)', () async {
    final seat = Directory.systemTemp.createTempSync('space-assets-seat-');
    addTearDown(() => seat.deleteSync(recursive: true));
    final packageConfig = File(
      p.join(seat.path, '.dart_tool', 'package_config.json'),
    )..createSync(recursive: true);
    File(
      p.join(repoRoot, '.dart_tool', 'package_config.json'),
    ).copySync(packageConfig.path);

    final run = await install(seat.path);
    expect(
      run.exitCode,
      0,
      reason: 'stdout: ${run.stdout}\nstderr: ${run.stderr}',
    );
    for (final relative in vended) {
      final file = File(p.join(seat.path, relative));
      expect(file.existsSync(), isTrue, reason: '$relative was not installed');
      expect(
        file.readAsStringSync(),
        contains('generated from grid_assets@testref'),
        reason: '$relative carries no provenance stamp',
      );
    }

    expect((await install(seat.path, check: true)).exitCode, 0);

    File(
      p.join(seat.path, '.claude', 'skills', 'discover', 'SKILL.md'),
    ).writeAsStringSync('\nan out-of-band edit\n', mode: FileMode.append);
    final drifted = await install(seat.path, check: true);
    expect(drifted.exitCode, 1);
    expect('${drifted.stdout}', contains('DRIFTED'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
