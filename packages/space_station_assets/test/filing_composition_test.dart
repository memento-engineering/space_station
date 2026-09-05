import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdResult, BdRunner;
import 'package:genesis_tree/genesis_tree.dart' show Seed, TreeContext;
import 'package:grid_assets/grid_assets.dart'
    show
        ApproveService,
        CrossLinkBlockerSource,
        ExactSubstationBeadSource,
        FilingService;
import 'package:grid_runtime/grid_runtime.dart' show GitRunResult, GitRunner;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
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

/// A downstream roster whose seats include a HYPHENATED prefix AND the strict
/// prefix it extends (space-fvg): `swift-infer-…` must resolve to
/// `swift-infer`, and `swift-…` to `swift`. The coded memento seats are
/// COMPOSED, never replaced, so the `pow-…` cases keep their meaning.
class _HyphenatedRosterDelegate extends SpaceDelegate {
  _HyphenatedRosterDelegate({
    required super.gridRoot,
    super.agentConfig,
    super.appended,
    super.harnesses,
    super.wiring,
    super.provisioner,
    super.githubSelfTrust,
    super.live,
  });

  @override
  List<Seed> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    ...super.substations(context, configuration),
    SubstationSeed(name: 'swift', root: '../swift'),
    SubstationSeed(name: 'swift-infer', root: '../swift-infer'),
  ];
}

const String _sha = '9f1c2d3e4b5a69788899aabbccddeeff00112233';
late Directory _fixture;
late String _umbrella;
late String _gridHome;

String _beadReply(String description, {String id = 'pow-child'}) => jsonEncode({
  'schema_version': 1,
  'data': [
    {
      'id': id,
      'title': 'child',
      'issue_type': 'task',
      'description': description,
      'acceptance_criteria': '- [ ] checked',
      'metadata': {'validation_plan': 'dart test'},
    },
  ],
});

String _depReply(List<String> blockers, {String id = 'pow-child'}) =>
    jsonEncode({
      'schema_version': 1,
      'data': [
        for (final blocker in blockers)
          {'issue_id': id, 'depends_on_id': blocker, 'type': 'blocks'},
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
_harness(
  _ScriptedBdRunner bd, {
  String? home,
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
}) {
  final gridHome = home ?? _gridHome;
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
    gridHomeDefault: () => gridHome,
    delegateFactory: delegateFactory,
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
  setUp(() {
    _fixture = Directory.systemTemp.createTempSync('space-filing-');
    _umbrella = _fixture.path;
    _gridHome = p.join(_umbrella, 'space_station');
    Directory(p.join(_gridHome, '.grid', '.beads')).createSync(recursive: true);
  });

  tearDown(() => _fixture.deleteSync(recursive: true));

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
      // grid_assets rc.8: the stamp IS approval — the verb adds no label.
      expect(argv, isNot(contains('--add-label')));
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

  test('a HYPHENATED seat prefix is reachable end to end: `filing --json '
      'swift-infer-zfor` reads the swift-infer seat, never the `swift` seat '
      'and never a refusal (space-fvg)', () async {
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply('No local ordering.', id: 'swift-infer-zfor'),
        'dep': _depReply(const [], id: 'swift-infer-zfor'),
      }),
      delegateFactory: _HyphenatedRosterDelegate.new,
    );

    expect(
      await h.runner.run(['filing', '--json', 'swift-infer-zfor']),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(h.storeRoots, isNotEmpty);
    expect(h.storeRoots, everyElement('$_umbrella/swift-infer'));
    final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    expect(report['id'], 'swift-infer-zfor');
    expect(report['passed'], isTrue);
  });

  test('`approve` STAMPS a bead minted by a HYPHENATED seat against THAT '
      "seat's store — the longest coded prefix wins (space-fvg)", () async {
    final bd = _ScriptedBdRunner({
      'query': _beadReply('No local ordering.', id: 'swift-infer-zfor'),
      'dep': _depReply(const [], id: 'swift-infer-zfor'),
    });
    final h = _harness(bd, delegateFactory: _HyphenatedRosterDelegate.new);

    expect(
      await h.runner.run([
        'approve',
        '--json',
        '--actor',
        'governor',
        'swift-infer-zfor',
      ]),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(h.git.workingDirectories, ['$_umbrella/swift-infer']);
    expect(bd.updates, hasLength(1));
    expect(bd.updates.single.take(2), ['update', 'swift-infer-zfor']);
    expect(h.storeRoots, contains('$_umbrella/swift-infer'));
    expect(h.storeRoots, isNot(contains('$_umbrella/swift')));
  });

  test('storeRootForBead matches the LONGEST coded prefix at a complete '
      '`<prefix>-` boundary, and refuses every id no seat mints', () {
    String rootFor(String beadId) => storeRootForBead(
      verb: 'filing',
      beadId: beadId,
      gridHome: _gridHome,
      delegateFactory: _HyphenatedRosterDelegate.new,
    );

    expect(rootFor('swift-infer-zfor'), '$_umbrella/swift-infer');
    expect(rootFor('swift-9k'), '$_umbrella/swift');
    expect(rootFor('pow-child'), '$_umbrella/power_station');
    for (final unminted in const ['zzz-1', 'pow-', 'space']) {
      expect(
        () => rootFor(unminted),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('no seat in the CODED roster mints'),
              contains('power_station@pow'),
            ),
          ),
        ),
        reason: '"$unminted" is minted by no coded seat',
      );
    }
  });
}
