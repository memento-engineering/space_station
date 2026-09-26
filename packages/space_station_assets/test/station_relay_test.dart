/// The station's OWN relay collaborators (space-8pq), each proved against its
/// real source: a temp worktree on disk, a recording git runner, a recording
/// bd runner speaking bd's JSON envelope, the resident's real diagnostics
/// reporter, and a real `sh` child standing in for a harness.
///
/// The contract under test is `memento-engineering#protect-the-governor`'s
/// failure rule: every reader THROWS when it cannot answer (so the engine
/// escalates), and returns an empty answer only when the source was reached
/// and holds nothing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show BdResult, BdRunner;
import 'package:genesis_tree/genesis_tree.dart' show Seed;
import 'package:grid_assets/grid_assets.dart'
    show AgentBrief, AgentEnvironment, PromptMode;
import 'package:grid_cli/grid_cli.dart' show StationDiagnosticsReporter;
import 'package:grid_engine/grid_engine.dart' as engine;
import 'package:grid_runtime/grid_runtime.dart' show GitRunResult, GitRunner;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

const _sessionId = 'houston-s1';
const _workBead = 'pow-w1';

final _observation = engine.RelayObservation(
  sessionId: _sessionId,
  workBeadId: _workBead,
  deadline: DateTime.utc(2026, 9, 25, 11),
  observedAt: DateTime.utc(2026, 9, 25, 12),
);

final class _Git implements GitRunner {
  _Git(this.result);

  final GitRunResult result;
  final List<String> directories = <String>[];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    directories.add(workingDirectory);
    return result;
  }
}

final class _Bd implements BdRunner {
  _Bd({this.rows = const [], this.exitCode = 0});

  final List<Map<String, Object?>> rows;
  final int exitCode;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(args);
    return BdResult(
      exitCode: exitCode,
      stdout: exitCode == 0
          ? jsonEncode({'schema_version': 1, 'data': rows})
          : '',
      stderr: exitCode == 0 ? '' : 'bd: store unreachable',
    );
  }
}

const _okLog = GitRunResult(
  exitCode: 0,
  output: 'abc1234 feat: halfway\x002026-09-23T10:00:00-05:00\n',
);

/// A temp roster root holding one worktree for [_workBead] under
/// `power_station`, deleted at teardown.
Future<({String root, String worktree})> _worktree() async {
  final home = await Directory.systemTemp.createTemp('station-relay-');
  addTearDown(() => home.delete(recursive: true));
  final root = p.join(home.path, 'power_station');
  final worktree = p.join(
    root,
    '.grid',
    'worktrees',
    'power_station',
    _workBead,
  );
  await Directory(worktree).create(recursive: true);
  return (root: root, worktree: worktree);
}

StationRelayReads _reads({
  required String root,
  GitRunner? git,
  BdRunner? bd,
  StationFlareTail? flares,
  int mtimeLimit = 25,
}) => StationRelayReads(
  worktreeRoots: [(substation: 'power_station', root: root)],
  stateStoreRoot: '/grid/home/.grid',
  flares: flares,
  git: git ?? _Git(_okLog),
  stateStoreBd: bd ?? _Bd(),
  mtimeLimit: mtimeLimit,
);

void main() {
  group('relayWorktreeRootsOf', () {
    test('reads SubstationSeed and sdk.Substation roots, resolved against the '
        'grid root by the SDK rule, and skips other seeds', () {
      final roots = relayWorktreeRootsOf(<Seed>[
        SubstationSeed(name: 'genesis', root: '../genesis'),
        sdk.Substation('mine', '/abs/mine/'),
        const sdk.SubstationWork(),
      ], gridRoot: '/umbrella/space_station');

      expect(roots, [
        (substation: 'genesis', root: '/umbrella/genesis'),
        (substation: 'mine', root: '/abs/mine'),
      ]);
    });
  });

  group('worktree.read', () {
    test('reports the newest paths (skipping git and tool caches) and the last '
        'commit, in UTC', () async {
      final tree = await _worktree();
      Future<void> touch(String relative, DateTime at) async {
        final file = File(p.join(tree.worktree, relative));
        await file.create(recursive: true);
        await file.setLastModified(at);
      }

      await touch('lib/old.dart', DateTime.utc(2026, 9, 20));
      await touch('lib/new.dart', DateTime.utc(2026, 9, 24));
      await touch('.grid/telemetry/x.usage.json', DateTime.utc(2026, 9, 23));
      await touch('.dart_tool/cache', DateTime.utc(2026, 9, 25));
      await touch('build/out', DateTime.utc(2026, 9, 25));
      final git = _Git(_okLog);

      final snapshot = await _reads(
        root: tree.root,
        git: git,
        mtimeLimit: 2,
      ).readWorktree(_observation);

      expect(snapshot.mtimes.keys.toList(), [
        'lib/new.dart',
        p.join('.grid', 'telemetry', 'x.usage.json'),
      ]);
      expect(snapshot.mtimes['lib/new.dart'], DateTime.utc(2026, 9, 24));
      expect(snapshot.lastCommit, 'abc1234 feat: halfway');
      expect(snapshot.lastCommitAt, DateTime.utc(2026, 9, 23, 15));
      expect(snapshot.lastCommitAt.isUtc, isTrue);
      expect(git.directories, [tree.worktree]);
    });

    test('THROWS when no roster root holds the session worktree', () async {
      final tree = await _worktree();
      final reads = StationRelayReads(
        worktreeRoots: [(substation: 'the_grid', root: tree.root)],
        stateStoreRoot: '/grid/home/.grid',
        git: _Git(_okLog),
        stateStoreBd: _Bd(),
      );

      await expectLater(
        reads.readWorktree(_observation),
        throwsA(isA<StateError>()),
      );
    });

    test('THROWS when git cannot read the last commit', () async {
      final tree = await _worktree();
      final reads = _reads(
        root: tree.root,
        git: _Git(const GitRunResult(exitCode: 128, output: 'fatal: bad')),
      );

      await expectLater(
        reads.readWorktree(_observation),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('telemetry.read', () {
    test(
      'a worktree with no telemetry directory has captured nothing',
      () async {
        final tree = await _worktree();

        expect(
          await _reads(root: tree.root).readTelemetry(_observation),
          isEmpty,
        );
      },
    );

    test('reads every usage envelope by node stem and marks an unreadable one '
        'instead of dropping it', () async {
      final tree = await _worktree();
      final telemetry = p.join(tree.worktree, '.grid', 'telemetry');
      await Directory(telemetry).create(recursive: true);
      await File(p.join(telemetry, 'pow-w1_build.usage.json')).writeAsString(
        jsonEncode({
          'type': 'result',
          'result': 'done',
          'usage': {'input_tokens': 10, 'output_tokens': 5},
          'total_cost_usd': 0.25,
        }),
      );
      await File(
        p.join(telemetry, 'pow-w1_review.usage.json'),
      ).writeAsString('not json');

      final records = await _reads(root: tree.root).readTelemetry(_observation);

      expect(records.map((r) => r.nodePath), ['pow-w1_build', 'pow-w1_review']);
      expect(records.first.usage['tokensIn'], '10');
      expect(records.first.usage['tokensOut'], '5');
      expect(records.last.usage, {'error': 'unreadable usage envelope'});
    });

    test('THROWS when the session worktree cannot be found', () async {
      final tree = await _worktree();
      final reads = StationRelayReads(
        worktreeRoots: [(substation: 'genesis', root: tree.root)],
        stateStoreRoot: '/grid/home/.grid',
        git: _Git(_okLog),
        stateStoreBd: _Bd(),
      );

      await expectLater(
        reads.readTelemetry(_observation),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('flares.read', () {
    test('THROWS when the station has no flare source attached', () async {
      final tree = await _worktree();

      await expectLater(
        _reads(root: tree.root).readFlareTail(_observation),
        throwsA(isA<StateError>()),
      );
    });

    test('the tail keeps the session\'s flares, newest bounded, in emission '
        'order', () async {
      final tail = StationFlareTail(capacity: 4, clock: () => DateTime(2026));
      tail
        ..flare('a', {'sessionId': _sessionId})
        ..flare('b', {'nodePath': '$_workBead/build'})
        ..flare('c', {'sessionId': 'houston-other'})
        ..flare('d', {'beadId': _workBead})
        ..flare('e', {'nodePath': '$_workBead/review'});

      final all = await tail.tailFor(_observation);
      // Capacity 4 dropped the oldest ('a'); 'c' is another session's.
      expect(all.map((r) => r.name), ['b', 'd', 'e']);
      expect(all.first.occurredAt.isUtc, isTrue);
      final newest = await tail.tailFor(_observation, limit: 2);
      expect(newest.map((r) => r.name), ['d', 'e']);
    });

    test('attachedTo taps the resident diagnostics reporter exactly once and '
        'sees what it accepts; any other transport has no tail', () async {
      final lines = <String>[];
      final reporter = StationDiagnosticsReporter(writeLine: lines.add);
      addTearDown(reporter.dispose);

      final tail = StationFlareTail.attachedTo(reporter);
      expect(tail, isNotNull);
      expect(StationFlareTail.attachedTo(reporter), same(tail));

      reporter.flare('step.gated', {'nodePath': '$_workBead/route'});
      expect(lines, hasLength(1), reason: 'the stderr sink still receives it');
      final seen = await tail!.tailFor(_observation);
      expect(seen.single.name, 'step.gated', reason: 'one tail, one record');

      expect(StationFlareTail.attachedTo(null), isNull);
      expect(StationFlareTail.attachedTo(StationFlareTail()), isNull);
    });
  });

  group('gates.read', () {
    test(
      'reads the open gate blocking the session from the state store',
      () async {
        final tree = await _worktree();
        final bd = _Bd(
          rows: [
            {
              'id': 'houston-g1',
              'title': 'grid gate $_sessionId@$_workBead/review/route',
              'status': 'open',
              'priority': 2,
              'issue_type': 'gate',
              'metadata': {
                'blocks': _sessionId,
                'reason': 'a critic returned F',
              },
            },
          ],
        );

        final gate = await _reads(
          root: tree.root,
          bd: bd,
        ).readGate(_observation);

        expect(gate, isNotNull);
        expect(gate!.id, 'houston-g1');
        expect(gate.reason, 'a critic returned F');
        expect(gate.awaitingHuman, isTrue);
        expect(bd.calls.single, [
          'list',
          '-t',
          'gate',
          '--status',
          'open',
          '--metadata-field',
          'blocks=$_sessionId',
          '--json',
          '--limit',
          '0',
        ]);
      },
    );

    test('a session parked at no gate reads null', () async {
      final tree = await _worktree();

      expect(await _reads(root: tree.root).readGate(_observation), isNull);
    });

    test('THROWS when the state store cannot be read', () async {
      final tree = await _worktree();

      await expectLater(
        _reads(root: tree.root, bd: _Bd(exitCode: 1)).readGate(_observation),
        throwsA(anything),
      );
    });
  });

  group('inference', () {
    AgentEnvironment sh(String script) => AgentEnvironment(
      command: 'sh',
      args: ['-c', script],
      promptMode: PromptMode.arg,
    );
    const brief = AgentBrief(task: 'the brief');

    test('returns the harness process\'s trimmed stdout', () async {
      const runner = ProcessRelayInference();

      final answer = await runner.run(
        environment: sh(
          r'''printf '  {"verdict":"absorb","nextHorizonSeconds":60}\n' ''',
        ),
        brief: brief,
      );

      expect(answer, '{"verdict":"absorb","nextHorizonSeconds":60}');
    });

    test('runs in a throwaway directory it removes afterwards', () async {
      const runner = ProcessRelayInference();

      final directory = await runner.run(environment: sh('pwd'), brief: brief);

      expect(p.basename(directory), startsWith('grid-relay-'));
      expect(await Directory(directory).exists(), isFalse);
    });

    test('THROWS on a non-zero exit, an empty answer and a timeout', () async {
      await expectLater(
        const ProcessRelayInference().run(
          environment: sh('echo nope >&2; exit 3'),
          brief: brief,
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        const ProcessRelayInference().run(
          environment: sh('exit 0'),
          brief: brief,
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        const ProcessRelayInference(
          timeout: Duration(milliseconds: 200),
        ).run(environment: sh('sleep 5'), brief: brief),
        throwsA(isA<StateError>()),
      );
    });

    test('the dry-run seam spawns nothing and refuses every brief', () async {
      await expectLater(
        const DryRunRelayInference().run(
          environment: sh('echo should-not-run'),
          brief: brief,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
