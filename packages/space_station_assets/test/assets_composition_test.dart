import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// The LAST-MILE composition: `space assets install` is the VENDED `grid_assets`
/// Command group curried with space's resident-station context, so the ROOT it
/// overlays onto and the `{{gridHome}}` it renders into every asset come from
/// [SpaceDelegate]'s own `RawAssetGrid` — never a hardcoded path. The Command's
/// own behaviour is pinned in power_station; this suite pins the WIRING.
void main() {
  late Directory tmp;
  late Directory overlay;
  late Directory seat;

  /// The installed file, at the SAME relative path in the overlay and the seat
  /// (the overlay is path-preserving).
  File skillIn(Directory root) => File(
    p.join(root.path, '.claude', 'skills', 'station-operations', 'SKILL.md'),
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('space-assets-');
    overlay = Directory(p.join(tmp.path, 'station_overlay'));
    seat = Directory(p.join(tmp.path, 'seat'))..createSync(recursive: true);
    skillIn(overlay)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '---\n'
        'name: station-operations\n'
        '---\n'
        '\n'
        'Boot: `{{runner}} up --grid-home {{gridHome}}`.\n',
      );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  ({CommandRunner<int> runner, StringBuffer out, StringBuffer err}) harness() {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = CommandRunner<int>('space', "memento's grid station")
      ..addCommand(
        buildSpaceAssetsCommand(
          gridHomeDefault: () => seat.path,
          roots: (_) async => [overlay.path],
          sourceRef: (_) => 'deadbee',
          out: out,
          err: err,
        ),
      );
    return (runner: runner, out: out, err: err);
  }

  test('`assets install` overlays onto the root SpaceDelegate authors, binds '
      '{{runner}} to `dart run space:space` and {{gridHome}} to that root, '
      'and stamps the provenance header on line 2', () async {
    final h = harness();
    expect(await h.runner.run(['assets', 'install', '--no-diff']), 0);

    final body = skillIn(seat).readAsStringSync();
    expect(
      body.split('\n')[1],
      '# generated from grid_assets@deadbee — do not edit; run '
      '`dart run space:space assets install`',
      reason: 'the YAML stamp lands UNDER the frontmatter opener (A26(1))',
    );
    expect(
      body,
      contains('`dart run space:space up --grid-home ${seat.path}`'),
    );
    expect(body, isNot(contains('{{')), reason: 'no hole survives the render');
  });

  test('`assets install --check` is CURRENT on a freshly installed tree (0) '
      'and LOUD on an out-of-band edit (1) — the no-drift enforcement that '
      'lets the tree be COMMITTED', () async {
    expect(await harness().runner.run(['assets', 'install', '--no-diff']), 0);
    expect(
      await harness().runner.run(['assets', 'install', '--check', '--no-diff']),
      0,
    );

    skillIn(
      seat,
    ).writeAsStringSync('\nan out-of-band edit\n', mode: FileMode.append);
    final drifted = harness();
    expect(
      await drifted.runner.run(['assets', 'install', '--check', '--no-diff']),
      1,
    );
    expect(drifted.out.toString(), contains('DRIFTED'));
  });

  test('a HAND-AUTHORED file at a vended path is BLOCKED and left intact '
      '(exit 1) — retiring the pre-install copies is a PRECONDITION of the '
      'install, never a consequence of it', () async {
    skillIn(seat)
      ..createSync(recursive: true)
      ..writeAsStringSync('---\nname: station-operations\n---\nmine\n');

    final h = harness();
    expect(await h.runner.run(['assets', 'install', '--no-diff']), 1);
    expect(h.out.toString(), contains('BLOCKED'));
    expect(
      skillIn(seat).readAsStringSync(),
      contains('mine'),
      reason: 'never clobber a file this tooling did not generate',
    );
  });

  test('a RELATIVE --grid-home is refused LOUD (UsageException → exit 64 '
      'out of the composed Command), never a raw ArgumentError from the mount and '
      'never a relative path baked into the committed manual', () async {
    await expectLater(
      harness().runner.run(['assets', 'install', '--grid-home', 'rel/home']),
      throwsA(isA<UsageException>()),
    );
  });
}
