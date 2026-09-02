import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdResult, BdRunner;
import 'package:grid_assets/grid_assets.dart'
    show
        ApproveService,
        CrossLinkBlockerSource,
        ExactSubstationBeadSource,
        FilingService;
import 'package:grid_runtime/grid_runtime.dart' show GitRunResult, GitRunner;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// The LAST-MILE composition: `space filing` / `space approve` are the VENDED
/// `grid_assets` Commands curried with space's resident-station context, so the
/// store each one reads (and, for approve, WRITES) is the seat the bead id's
/// PREFIX names in the coded roster (`SpaceDelegate.substations`) — never the
/// CWD's store. The Commands' own behaviour is pinned in power_station; this
/// suite pins the WIRING. Offline: a scripted `bd` runner + a fake git runner +
/// captured sinks.
final class _ScriptedBdRunner implements BdRunner {
  _ScriptedBdRunner(this.replies);

  final Map<String, String> replies;
  final List<List<String>> argvs = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(args);
    return BdResult(
      exitCode: 0,
      stdout: replies[args.first] ?? '{"schema_version":1,"data":[]}',
      stderr: '',
    );
  }

  List<List<String>> get updates =>
      argvs.where((argv) => argv.first == 'update').toList();
}

final class _FakeGitRunner implements GitRunner {
  _FakeGitRunner(this.result);

  final GitRunResult result;
  final List<String> workingDirectories = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    workingDirectories.add(workingDirectory);
    return result;
  }
}

const String _umbrella = '/home/memento';
const String _gridHome = '$_umbrella/space_station';
const String _sha = '9f1c2d3e4b5a69788899aabbccddeeff00112233';

String _beadReply(String description) => jsonEncode({
  'schema_version': 1,
  'data': [
    {
      'id': 'pow-child',
      'title': 'child',
      'issue_type': 'task',
      'description': description,
      'acceptance_criteria': '- [ ] checked',
      'metadata': {'validation_plan': 'dart test'},
    },
  ],
});

String _depReply(List<String> blockers) => jsonEncode({
  'schema_version': 1,
  'data': [
    for (final blocker in blockers)
      {'issue_id': 'pow-child', 'depends_on_id': blocker, 'type': 'blocks'},
  ],
});

Map<String, String> _metadataOf(List<String> argv) {
  final metadata = <String, String>{};
  for (var i = 0; i < argv.length - 1; i++) {
    if (argv[i] != '--set-metadata') continue;
    final pair = argv[i + 1];
    final eq = pair.indexOf('=');
    metadata[pair.substring(0, eq)] = pair.substring(eq + 1);
  }
  return metadata;
}

({
  CommandRunner<int> runner,
  StringBuffer out,
  StringBuffer err,
  List<String> storeRoots,
  _FakeGitRunner git,
})
_harness(_ScriptedBdRunner bd, {String home = _gridHome}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final storeRoots = <String>[];
  final git = _FakeGitRunner(
    const GitRunResult(exitCode: 0, output: '$_sha\n'),
  );
  BdRunner runnerFor(String storeRoot) {
    storeRoots.add(storeRoot);
    return bd;
  }

  final commands = buildSpaceFilingCommands(
    gridHomeDefault: () => home,
    filing: FilingService(
      source: ExactSubstationBeadSource(runnerFor: runnerFor),
      links: CrossLinkBlockerSource(runnerFor: runnerFor),
    ),
    approve: ApproveService(
      runnerFor: runnerFor,
      git: git,
      now: () => DateTime.utc(2026, 9, 2, 14, 30),
    ),
    out: out,
    err: err,
  );
  return (
    runner: CommandRunner<int>('space', "memento's grid station")
      ..addCommand(commands.filing)
      ..addCommand(commands.approve),
    out: out,
    err: err,
    storeRoots: storeRoots,
    git: git,
  );
}

void main() {
  test('`filing --json <id>` reads the seat the id PREFIX names in the CODED '
      'roster — `pow-…` is power_station at ../power_station, never the CWD '
      'store — and returns the four rows', () async {
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply('No local ordering.'),
        'dep': _depReply(const []),
      }),
    );

    expect(
      await h.runner.run(['filing', '--json', 'pow-child']),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(h.storeRoots, isNotEmpty);
    expect(h.storeRoots, everyElement('$_umbrella/power_station'));
    final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    expect(report['id'], 'pow-child');
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
  });

  test('a bead id NO coded seat mints is refused LOUD: exit 1, the seats '
      'named, nothing read', () async {
    final h = _harness(_ScriptedBdRunner(const {}));

    expect(await h.runner.run(['filing', '--json', 'zzz-1']), 1);
    expect(h.err.toString(), contains('no seat in the CODED roster mints'));
    expect(h.err.toString(), contains('power_station@pow'));
    expect(h.storeRoots, isEmpty);
    expect(h.out.toString(), isEmpty);
  });

  test('`approve` REFUSES an unwired named blocker: exit 1, nothing written, '
      'no revision read', () async {
    final bd = _ScriptedBdRunner({
      'query': _beadReply('Child 2 of epic pow-n6n. Depends on pow-n6n.1.'),
      'dep': _depReply(const []),
    });
    final h = _harness(bd);

    expect(
      await h.runner.run(['approve', '--actor', 'governor', 'pow-child']),
      1,
    );
    expect(h.out.toString(), contains('REFUSED pow-child'));
    expect(h.out.toString(), contains('pow-n6n.1'));
    expect(bd.updates, isEmpty);
    expect(h.git.workingDirectories, isEmpty);
  });

  test(
    '`approve` STAMPS a wired bead in ONE bd update against the '
    'ROSTER-resolved store, with the state root defaulted to <home>/.grid',
    () async {
      final bd = _ScriptedBdRunner({
        'query': _beadReply('Child 2 of epic pow-n6n. Depends on pow-n6n.1.'),
        'dep': _depReply(const ['pow-n6n.1']),
      });
      final h = _harness(bd);

      expect(
        await h.runner.run([
          'approve',
          '--json',
          '--actor',
          'governor',
          'pow-child',
        ]),
        0,
        reason: '${h.out}${h.err}',
      );
      expect(h.git.workingDirectories, ['$_umbrella/power_station']);
      expect(bd.updates, hasLength(1));
      final argv = bd.updates.single;
      expect(argv.take(2), ['update', 'pow-child']);
      expect(argv, containsAllInOrder(['--actor', 'governor']));
      expect(argv, containsAllInOrder(['--add-label', 'grid.approved']));
      expect(_metadataOf(argv), {
        'grid.approved_by': 'governor',
        'grid.approved_at': '2026-09-02T14:30:00.000Z',
        'grid.approved_rev': _sha,
      });
      expect(
        h.storeRoots,
        contains('$_umbrella/power_station'),
        reason: 'the preflight and the stamp ride the roster-resolved seat',
      );
      expect(
        h.storeRoots,
        contains('$_gridHome/.grid'),
        reason: 'the cross-store link lookup rides the grid state store',
      );
      final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      expect(report['approved'], isTrue);
      expect(report['rev'], _sha);
    },
  );

  test('a RELATIVE --grid-home is refused LOUD by BOTH verbs: exit 1, nothing '
      'read, nothing written', () async {
    final filing = _harness(_ScriptedBdRunner(const {}));
    expect(
      await filing.runner.run([
        'filing',
        '--grid-home',
        'rel/home',
        'pow-child',
      ]),
      1,
    );
    expect(filing.err.toString(), contains('must be an ABSOLUTE path'));
    expect(filing.storeRoots, isEmpty);

    final bd = _ScriptedBdRunner(const {});
    final approve = _harness(bd);
    expect(
      await approve.runner.run([
        'approve',
        '--actor',
        'governor',
        '--grid-home',
        'rel/home',
        'pow-child',
      ]),
      1,
    );
    expect(approve.err.toString(), contains('must be an ABSOLUTE path'));
    expect(bd.updates, isEmpty);
    expect(approve.storeRoots, isEmpty);
  });
}
