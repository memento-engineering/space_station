import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'station_fixtures.dart';

/// A PROCESS-LEVEL smoke over the REAL `space` CLI (`bin/space.dart`): the
/// front-door verbs must actually RUN, over the REAL read path. The fixture
/// mirrors `search_cli_smoke_test.dart`'s fabricated umbrella — the grid home
/// is an umbrella member whose SIBLINGS are the coded `../<repo>` roots, and
/// only the `genesis` seat gets a real store. No live station, no lock.
void main() {
  test('`space filing --json <id>` runs from the CLI: the id PREFIX picks the '
      'sibling seat store, four passing rows, exit 0', () async {
    final umbrella = Directory(
      (await Directory.systemTemp.createTemp(
        'space-filing-umbrella-',
      )).resolveSymbolicLinksSync(),
    );
    addTearDown(() => umbrella.delete(recursive: true));
    final gridHome = Directory('${umbrella.path}/space_station')..createSync();
    final genesisRoot = Directory('${umbrella.path}/genesis')..createSync();
    await runBd(genesisRoot.path, const ['init']);
    await runBd(genesisRoot.path, const [
      'create',
      'zzfiling the keyed reconcile',
      '--id',
      'genesis-zzfiling',
      '--type',
      'task',
      '--acceptance',
      '- [ ] the four rows pass',
      '--metadata',
      '{"validation_plan":"dart test"}',
      '--actor',
      'space-filing-smoke',
    ]);

    final run = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'filing',
      '--grid-home',
      gridHome.path,
      '--json',
      'genesis-zzfiling',
    ], workingDirectory: Directory.current.path);

    expect(
      run.exitCode,
      0,
      reason: 'stdout: ${run.stdout}\nstderr: ${run.stderr}',
    );
    final report = jsonDecode('${run.stdout}') as Map<String, dynamic>;
    expect(report['id'], 'genesis-zzfiling');
    expect(report['passed'], isTrue);
    expect(
      [
        for (final row in report['requirements']! as List)
          (row as Map<String, dynamic>)['requirement'],
      ],
      [
        'driveable_type',
        'validation_plan',
        'acceptance_criteria',
        'dependencies',
      ],
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('`space approve` is vended too: a missing --actor is a usage refusal '
      '(exit 64) that reads no store', () async {
    final run = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'approve',
      'genesis-zzfiling',
    ], workingDirectory: Directory.current.path);

    expect(run.exitCode, 64, reason: 'stdout: ${run.stdout}');
    expect('${run.stderr}', contains('--actor'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
