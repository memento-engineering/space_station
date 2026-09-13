import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdResult, BdRunner;
import 'package:genesis_tree/genesis_tree.dart' show Seed, TreeContext;
import 'package:grid_assets/grid_assets.dart'
    show
        ApproveCommand,
        ApproveService,
        CrossLinkBlockerSource,
        ExactSubstationBeadSource,
        FilingCommand,
        FilingService,
        ParkCommand,
        ParkService,
        ShowCommand,
        ShowService,
        UnparkCommand,
        UnparkService;
import 'package:grid_cli/grid_cli.dart' show PauseCommand, ResumeCommand;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// The LAST-MILE composition: `space filing` / `space approve` are the VENDED
/// `grid_assets` Commands curried with space's resident-station context, so the
/// store each one reads (and, for approve, WRITES) is the substation the bead
/// id's
/// PREFIX names in the coded roster (`SpaceDelegate.substations`) — never the
/// CWD's store. The Commands' own behaviour is pinned in power_station; this
/// suite pins the WIRING. Offline: a scripted `bd` runner + captured sinks.
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

/// A downstream roster whose substations include a HYPHENATED prefix AND the strict
/// prefix it extends (space-fvg): `swift-infer-…` must resolve to
/// `swift-infer`, and `swift-…` to `swift`. The coded memento substations are
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
      'status': 'open',
      'priority': 2,
      'description': description,
      'design': 'compose the vended command',
      'acceptance_criteria': '- [ ] checked',
      'notes': 'reachable from the station runner',
      'updated_at': '2026-09-12T12:00:00.000Z',
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
  SpaceFilingCommands commands,
})
_harness(
  _ScriptedBdRunner bd, {
  String? home,
  String runnerName = 'space',
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
}) {
  final gridHome = home ?? _gridHome;
  final out = StringBuffer();
  final err = StringBuffer();
  final storeRoots = <String>[];
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
      now: () => DateTime.utc(2026, 9, 2, 14, 30),
    ),
    park: ParkService(runnerFor: runnerFor),
    unpark: UnparkService(
      approve: ApproveService(
        runnerFor: runnerFor,
        now: () => DateTime.utc(2026, 9, 2, 14, 30),
      ),
      runnerFor: runnerFor,
    ),
    show: ShowService(runnerFor: runnerFor),
    out: out,
    err: err,
  );
  return (
    runner: buildRunner(name: runnerName, filingCommands: commands),
    out: out,
    err: err,
    storeRoots: storeRoots,
    commands: commands,
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

  test(
    'composed runner resolves park unpark show pause and resume by name',
    () {
      final h = _harness(_ScriptedBdRunner(const {}));

      expect(h.runner.commands['park'], isA<ParkCommand>());
      expect(h.runner.commands['unpark'], isA<UnparkCommand>());
      expect(h.runner.commands['show'], isA<ShowCommand>());
      expect(h.runner.commands['pause'], isA<PauseCommand>());
      expect(h.runner.commands['resume'], isA<ResumeCommand>());
    },
  );

  test(
    'all roster-aware filing verbs share grid-home and vended command types',
    () async {
      final commands = _harness(_ScriptedBdRunner(const {})).commands;
      expect(commands.filing, isA<FilingCommand>());
      expect(commands.approve, isA<ApproveCommand>());
      expect(commands.park, isA<ParkCommand>());
      expect(commands.unpark, isA<UnparkCommand>());
      expect(commands.show, isA<ShowCommand>());

      final help = <String?>{
        for (final command in <Command<int>>[
          commands.filing,
          commands.approve,
          commands.park,
          commands.unpark,
          commands.show,
        ])
          command.argParser.options['grid-home']?.help,
      };
      expect(help, hasLength(1));
      expect(help.single, contains("bead id's prefix"));

      final park = _harness(
        _ScriptedBdRunner({
          'query': _beadReply('No local ordering.'),
          'dep': _depReply(const []),
        }),
      );
      expect(
        await park.runner.run([
          'park',
          '--actor',
          'governor',
          '--reason',
          'stalled',
          '--until',
          '2026-09-13',
          'pow-child',
        ]),
        1,
      );
      expect(
        park.storeRoots.toSet(),
        containsAll(<String>{'$_umbrella/power_station', '$_gridHome/.grid'}),
      );

      final unpark = _harness(
        _ScriptedBdRunner({
          'query': _beadReply('Depends on tg-89y8.'),
          'dep': _depReply(const []),
        }),
      );
      expect(
        await unpark.runner.run(['unpark', '--actor', 'governor', 'pow-child']),
        1,
      );
      expect(
        unpark.storeRoots.toSet(),
        containsAll(<String>{'$_umbrella/power_station', '$_gridHome/.grid'}),
      );

      final homeWithoutState = p.join(_umbrella, 'alternate_station');
      final showWithoutState = _harness(
        _ScriptedBdRunner({
          'query': _beadReply('The foreign-store bead.'),
          'dep': _depReply(const []),
        }),
        home: homeWithoutState,
      );
      expect(
        await showWithoutState.runner.run(['show', '--json', 'pow-child']),
        1,
      );
      expect(showWithoutState.storeRoots, isEmpty);

      final showWithOverride = _harness(
        _ScriptedBdRunner({
          'query': _beadReply('The foreign-store bead.'),
          'dep': _depReply(const []),
        }),
        home: homeWithoutState,
      );
      expect(
        await showWithOverride.runner.run([
          'show',
          '--json',
          '--state-root',
          _gridHome,
          'pow-child',
        ]),
        0,
      );
      expect(showWithOverride.storeRoots.toSet(), {'$_umbrella/power_station'});
    },
  );

  test(
    'composed show renders a power_station bead from the foreign work store',
    () async {
      final h = _harness(
        _ScriptedBdRunner({
          'query': _beadReply('The foreign-store bead.'),
          'dep': _depReply(const []),
        }),
      );

      expect(
        await h.runner.run(['show', '--json', 'pow-child']),
        0,
        reason: '${h.out}${h.err}',
      );
      final shown = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      expect(shown['id'], 'pow-child');
      expect(shown['shown'], isTrue);
      expect(h.storeRoots.toSet(), {'$_umbrella/power_station'});
      expect(h.storeRoots, isNot(contains(_gridHome)));
    },
  );

  test(
    'downstream-named runner inherits the same verbs without delegate wiring',
    () {
      final h = _harness(_ScriptedBdRunner(const {}), runnerName: 'lunar');

      expect(h.runner.executableName, 'lunar');
      expect(h.runner.commands['park'], same(h.commands.park));
      expect(h.runner.commands['unpark'], same(h.commands.unpark));
      expect(h.runner.commands['show'], same(h.commands.show));
      expect(h.runner.commands['pause'], isA<PauseCommand>());
      expect(h.runner.commands['resume'], isA<ResumeCommand>());
    },
  );

  test(
    '`filing --json <id>` reads the substation the id PREFIX names in the CODED '
    'roster — `pow-…` is power_station at ../power_station, never the CWD '
    'store — and returns the four rows',
    () async {
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
    },
  );

  test('a bead id NO coded substation mints is refused LOUD: exit 1, the '
      'substations '
      'named, nothing read', () async {
    final h = _harness(_ScriptedBdRunner(const {}));

    expect(await h.runner.run(['filing', '--json', 'zzz-1']), 1);
    expect(
      h.err.toString(),
      contains('no substation in the CODED roster mints'),
    );
    expect(h.err.toString(), contains('power_station@pow'));
    expect(h.storeRoots, isEmpty);
    expect(h.out.toString(), isEmpty);
  });

  test(
    '`approve` REFUSES an unwired named blocker: exit 1, nothing written',
    () async {
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
    },
  );

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
      expect(bd.updates, hasLength(1));
      final argv = bd.updates.single;
      expect(argv.take(2), ['update', 'pow-child']);
      expect(argv, containsAllInOrder(['--actor', 'governor']));
      // grid_assets rc.8: the stamp IS approval — the verb adds no label.
      expect(argv, isNot(contains('--add-label')));
      final metadata = _metadataOf(argv);
      expect(
        metadata.keys,
        unorderedEquals(const [
          'grid.approved_by',
          'grid.approved_at',
          'grid.approved_rev',
        ]),
      );
      expect(metadata['grid.approved_by'], 'governor');
      expect(metadata['grid.approved_at'], '2026-09-02T14:30:00.000Z');
      final approvedRev = metadata['grid.approved_rev'];
      expect(approvedRev, matches(RegExp(r'^filing:v1:sha256:[0-9a-f]{64}$')));
      expect(
        h.storeRoots,
        contains('$_umbrella/power_station'),
        reason:
            'the preflight and the stamp ride the roster-resolved substation',
      );
      expect(
        h.storeRoots,
        contains('$_gridHome/.grid'),
        reason: 'the cross-store link lookup rides the grid state store',
      );
      final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      expect(report['approved'], isTrue);
      expect(report['rev'], approvedRev);
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

  test('a HYPHENATED substation prefix is reachable end to end: `filing --json '
      'swift-infer-zfor` reads the swift-infer substation, never the `swift` '
      'substation '
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

  test(
    '`approve` STAMPS a bead minted by a HYPHENATED substation against '
    "THAT substation's store — the longest coded prefix wins (space-fvg)",
    () async {
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
      expect(bd.updates, hasLength(1));
      expect(bd.updates.single.take(2), ['update', 'swift-infer-zfor']);
      expect(h.storeRoots, contains('$_umbrella/swift-infer'));
      expect(h.storeRoots, isNot(contains('$_umbrella/swift')));
    },
  );

  test('storeRootForBead matches the LONGEST coded prefix at a complete '
      '`<prefix>-` boundary, and refuses every id no substation mints', () {
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
              contains('no substation in the CODED roster mints'),
              contains('power_station@pow'),
            ),
          ),
        ),
        reason: '"$unminted" is minted by no coded substation',
      );
    }
  });
}
