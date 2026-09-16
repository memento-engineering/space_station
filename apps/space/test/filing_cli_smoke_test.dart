@Tags(['bd-e2e'])
library;

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
      'sibling seat store, ten passing rows, exit 0', () async {
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
      '- [ ] the ten rows pass',
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
        'validation_plan_syntax',
        'validation_plan_portability',
        'repo_relative_paths',
        'bead_references',
        'release_versions',
        'decision_references',
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

  test(
    'space mount --json reports ten ordered rows for an attached substation',
    () async {
      final umbrella = Directory(
        (await Directory.systemTemp.createTemp(
          'space-mount-umbrella-',
        )).resolveSymbolicLinksSync(),
      );
      addTearDown(() => umbrella.delete(recursive: true));
      final gridHome = Directory('${umbrella.path}/space_station')
        ..createSync();
      final stateRoot = Directory('${gridHome.path}/.grid')..createSync();
      final genesisRoot = Directory('${umbrella.path}/genesis')..createSync();
      await runBd(stateRoot.path, const ['init', '--prefix', 'state']);
      await runBd(stateRoot.path, const [
        'config',
        'set',
        'types.custom',
        'session,molecule,step,mount-attempt',
      ]);
      await runBd(genesisRoot.path, const ['init']);
      await runBd(genesisRoot.path, const [
        'create',
        'zzmount the attached-substation explainer',
        '--id',
        'genesis-zzmount',
        '--type',
        'task',
        '--description',
        'A driveable bead that has not been approved.',
        '--acceptance',
        '- [ ] the ten mount rows explain its admission state',
        '--metadata',
        '{"validation_plan":"dart test"}',
        '--actor',
        'space-mount-smoke',
      ]);

      final workspaceRoot = Directory(
        '../..',
      ).absolute.resolveSymbolicLinksSync();
      final run = await Process.run(Platform.resolvedExecutable, [
        'run',
        'space:space',
        'mount',
        '--grid-home',
        gridHome.path,
        '--json',
        'genesis-zzmount',
      ], workingDirectory: workspaceRoot);

      expect(
        run.exitCode,
        1,
        reason: 'stdout: ${run.stdout}\nstderr: ${run.stderr}',
      );
      final report = jsonDecode('${run.stdout}') as Map<String, dynamic>;
      expect(report['id'], 'genesis-zzmount');
      expect(report['verdict'], 'BLOCKED');
      final rows = (report['preconditions'] as List)
          .cast<Map<String, dynamic>>();
      expect(rows.map((row) => row['precondition']), const [
        'driveable_type',
        'validation_plan',
        'acceptance_criteria',
        'dependencies',
        'approval_stamp',
        'session_occupancy',
        'defer_state',
        'verdict_cap',
        'mount_attempt_cap',
        'live_admission',
      ]);
      expect(
        rows.singleWhere(
          (row) => row['precondition'] == 'approval_stamp',
        )['outcome'],
        'BLOCKED',
      );
      for (final precondition in const [
        'session_occupancy',
        'verdict_cap',
        'mount_attempt_cap',
      ]) {
        expect(
          rows.singleWhere(
            (row) => row['precondition'] == precondition,
          )['outcome'],
          isNot('UNCHECKED'),
          reason:
              '$precondition reads the real .grid state store: ${run.stdout}',
        );
      }
      expect(
        rows.singleWhere(
          (row) => row['precondition'] == 'live_admission',
        )['outcome'],
        'UNCHECKED',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
