@Tags(['bd-e2e'])
library;

import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

class _Source implements SnapshotSource {
  _Source(this._current);

  final _controller = StreamController<GraphSnapshot>.broadcast();
  GraphSnapshot? _current;

  @override
  GraphSnapshot? get current => _current;

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  void emit(GraphSnapshot value) {
    _current = value;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();
}

class _FixtureDelegate extends SpaceDelegate {
  _FixtureDelegate({
    required super.gridRoot,
    super.agentConfig,
    super.appended,
    super.harnesses,
    super.wiring,
    super.provisioner,
    super.gitOps,
    super.prOpener,
  });

  static late String alphaRoot;
  static late String betaRoot;

  @override
  List<sdk.Substation> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [seat(context, 'alpha', alphaRoot), seat(context, 'beta', betaRoot)];
}

class _Recorder implements SessionResolver {
  final mounted = <String>[];
  final disposed = <String>[];

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      _Effect(bead.id, this, key: ValueKey('${bead.id}:work'));
}

class _Effect extends StatefulSeed {
  const _Effect(this.beadId, this.recorder, {super.key});

  final String beadId;
  final _Recorder recorder;

  @override
  State<_Effect> createState() => _EffectState();
}

class _EffectState extends State<_Effect> {
  @override
  void initState() => seed.recorder.mounted.add(seed.beadId);

  @override
  void dispose() => seed.recorder.disposed.add(seed.beadId);

  @override
  Seed build(TreeContext context) => const Idle();
}

Future<String> _runBd(String root, List<String> args) async {
  final result = await Process.run('bd', args, workingDirectory: root);
  if (result.exitCode != 0) {
    throw StateError('bd ${args.join(' ')} failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

Future<void> _init(String root, String prefix) async {
  Directory(root).createSync(recursive: true);
  await _runBd(root, [
    'init',
    '--non-interactive',
    '--skip-agents',
    '--skip-hooks',
    '--prefix',
    prefix,
  ]);
}

GraphSnapshot _graph(List<Bead> beads, {int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: beads.where((b) => !b.isClosed).map((b) => b.id),
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
    );

Bead _work(String id, {bool closed = false}) => Bead(
  id: id,
  issueType: IssueType.task,
  status: closed ? BeadStatus.closed : BeadStatus.open,
);

JoinedSnapshot _read(JoinedSnapshotNotifier notifier) {
  late JoinedSnapshot value;
  final remove = notifier.addListener((next) => value = next);
  remove();
  return value;
}

Future<List<Bead>> _stateBeads(String stateRoot) async {
  final workspace = BeadsWorkspace.discover(start: stateRoot)!;
  return (await BdCliService(
    ProcessBdRunner(workspaceRoot: workspace.root),
  ).exportAll()).beads;
}

void main() {
  late Directory fixture;
  late String gridRoot;
  late String stateRoot;

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('space_link_join_');
    gridRoot = fixture.resolveSymbolicLinksSync();
    stateRoot = '$gridRoot/.grid';
    _FixtureDelegate.alphaRoot = '$gridRoot/alpha';
    _FixtureDelegate.betaRoot = '$gridRoot/beta';
    await _init(stateRoot, 'houston');
    await _init(_FixtureDelegate.alphaRoot, 'alpha');
    await _init(_FixtureDelegate.betaRoot, 'beta');
    await _runBd(stateRoot, ['config', 'set', 'types.custom', 'link']);
  });

  tearDown(() async {
    await fixture.delete(recursive: true);
  });

  Future<List<Bead>> author(String to) async {
    final runner = buildRunner(delegateFactory: _FixtureDelegate.new);
    expect(
      await runner.run([
        'link',
        '--grid-root',
        gridRoot,
        '--prefix',
        'houston',
        '--prefix',
        'alpha',
        '--prefix',
        'beta',
        '--blocked-by',
        to,
        '--reason',
        'integration proof',
        '--actor',
        'test',
        'alpha-1',
      ]),
      0,
    );
    return _stateBeads(stateRoot);
  }

  test('authored links govern the joined ready frontier', () async {
    final stateBeads = await author('beta-1');
    final work = _Source(_graph([_work('alpha-1'), _work('beta-1')]));
    final state = _Source(_graph(stateBeads));
    final bridge = StationJoinBridge(work: work, state: state)..start();
    addTearDown(() async {
      bridge.dispose();
      await work.close();
      await state.close();
    });

    expect(_read(bridge.notifier).graph.readyIds, isNot(contains('alpha-1')));
    work.emit(
      _graph([_work('alpha-1'), _work('beta-1', closed: true)], tick: 1),
    );
    await Future<void>.delayed(Duration.zero);
    expect(_read(bridge.notifier).graph.readyIds, contains('alpha-1'));
  });

  test(
    'an authored unobserved target fails closed and reports both ids',
    () async {
      final stateBeads = await author('beta-missing-404');
      final work = _Source(_graph([_work('alpha-1')]));
      final state = _Source(_graph(stateBeads));
      final loud = <String>[];
      final bridge = StationJoinBridge(
        work: work,
        state: state,
        onUnresolvedCrossLink: loud.add,
      )..start();
      addTearDown(() async {
        bridge.dispose();
        await work.close();
        await state.close();
      });

      expect(_read(bridge.notifier).graph.readyIds, isNot(contains('alpha-1')));
      expect(
        loud.last,
        allOf(
          contains('alpha-1'),
          contains('beta-missing-404'),
          contains('fail-closed'),
        ),
      );
    },
  );

  test('a link-driven frontier exit retains already-mounted work', () async {
    final stateBeads = await author('beta-1');
    final work = _Source(_graph([_work('alpha-1'), _work('beta-1')]));
    final state = _Source(_graph(const []));
    final bridge = StationJoinBridge(work: work, state: state)..start();
    final recorder = _Recorder();
    final owner = TreeOwner();
    owner.mountRoot(
      InheritedSeed<JoinedSnapshotNotifier>(
        value: bridge.notifier,
        child: InheritedSeed<SessionResolver>(
          value: recorder,
          child: const WorkList(
            substationConfig: SubstationConfig(
              substationId: 'alpha',
              ownedSubstations: {'alpha'},
            ),
          ),
        ),
      ),
    );
    addTearDown(() async {
      owner.dispose();
      bridge.dispose();
      await work.close();
      await state.close();
    });
    expect(recorder.mounted, contains('alpha-1'));

    state.emit(_graph(stateBeads, tick: 1));
    await Future<void>.delayed(Duration.zero);
    owner.flush();

    expect(_read(bridge.notifier).graph.readyIds, isNot(contains('alpha-1')));
    expect(recorder.mounted, contains('alpha-1'));
    expect(recorder.disposed, isNot(contains('alpha-1')));
  });
}
