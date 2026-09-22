import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart' as engine;
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show Lifecycle, RuntimeConfig, RuntimeEvent, SessionStarted;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

final class _GenerationCapability extends engine.ProcessCapability {
  const _GenerationCapability(this.generation, this.executions);

  final int generation;
  final List<String> executions;

  @override
  RuntimeConfig spawn(sdk.TreeContext context, engine.StepArgs args) {
    final circuitGeneration = args.params['generation'];
    if (circuitGeneration != 'generation-$generation') {
      throw StateError(
        'generation-$generation registry received $circuitGeneration circuit',
      );
    }
    executions.add('generation-$generation:${args.beadId}');
    return RuntimeConfig(
      workDir: context
          .getInheritedSeedOfExactType<engine.Workspace>()!
          .workspaceDir,
      command: 'sh',
      args: const ['-c', 'echo'],
      lifecycle: Lifecycle.oneTurn,
    );
  }

  @override
  engine.StepSignal interpretEvent(RuntimeEvent event) =>
      engine.StepSignal.none;
}

engine.Circuit _circuit(int generation) => engine.Circuit(
  id: 'generation-$generation',
  terminalStepId: 'agent',
  steps: [
    engine.CapabilityStep(
      stepId: 'agent',
      capabilityId: 'agent',
      params: {'generation': 'generation-$generation'},
    ),
  ],
);

final class _GenerationDelegate extends SpaceDelegate {
  _GenerationDelegate({
    required this.generation,
    required this.executions,
    required super.wiring,
    this.bootGate,
    this.onDisposed,
  }) : super(gridRoot: '/grid/home');

  final int generation;
  final List<String> executions;
  final Future<void>? bootGate;
  final void Function()? onDisposed;

  @override
  engine.Circuit? circuitOverrideFor(Bead bead) => _circuit(generation);

  @override
  engine.CapabilityRegistry buildWorkRegistry(
    NoteAppender appendNote,
    sdk.SpecifyAuthoredSpecWriter writeSpecifyAuthoredSpec,
  ) => engine.DefaultCapabilityRegistry(
    capabilities: {'agent': _GenerationCapability(generation, executions)},
    clock: () => DateTime(2026),
  );

  @override
  List<sdk.Seed> substations(
    sdk.TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    sdk.Substation(
      'power_station',
      '/work/power_station',
      prefix: 'pow',
      assets: const [sdk.SubstationWork()],
    ),
  ];

  @override
  Future<void> boot(sdk.GridConfiguration configuration) async {
    await bootGate;
  }

  @override
  void dispose() {
    onDisposed?.call();
    super.dispose();
  }
}

DelegateWorkPolicy _policyFor(_GenerationDelegate delegate) =>
    DelegateWorkPolicy(
      resolver: engine.CircuitResolver(
        (bead) => delegate.circuitOverrideFor(bead)!,
      ),
      registry: delegate.buildWorkRegistry(
        (_, _) async {},
        (_, {required design, required acceptanceCriteria}) async {},
      ),
    );

sdk.StationWorkWiring _ordinaryWiring(
  engine.StationJoinBridge bridge,
  Fakes fakes,
  _GenerationDelegate delegate,
) {
  final policy = _policyFor(delegate);
  return sdk.StationWorkWiring(
    notifier: bridge.notifier,
    services: fakes.ctx,
    resolver: policy.resolver,
    registry: policy.registry,
  );
}

typedef _Rig = ({
  sdk.GridHandle grid,
  FakeSnapshotSource work,
  FakeSnapshotSource state,
  Fakes fakes,
  List<String> executions,
  List<Bead> workBeads,
  List<Bead> stateBeads,
});

GraphSnapshot _graph(List<Bead> beads, Set<String> ready) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime(2026),
    );

Bead _workBead(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

List<Bead> _sessionState(String workBeadId, int generation) {
  final sessionId = 'tgdog-session-$workBeadId';
  return [
    Bead(
      id: sessionId,
      issueType: engine.GridIssueTypes.session,
      status: BeadStatus.open,
      metadata: {
        engine.SessionBeadKeys.workBead: workBeadId,
        engine.SessionBeadKeys.model: engine.kSessionModelMolecule,
      },
    ),
    Bead(
      id: 'tgdog-molecule-$workBeadId',
      issueType: engine.GridIssueTypes.molecule,
      status: BeadStatus.open,
      metadata: {
        engine.MoleculeCircuitKeys.formula: 'generation-$generation',
        engine.MoleculeCircuitKeys.session: sessionId,
      },
    ),
    Bead(
      id: 'tgdog-step-$workBeadId-agent',
      issueType: engine.GridIssueTypes.step,
      status: BeadStatus.open,
      metadata: {
        'grid.step.id': 'agent',
        'grid.step.capability': 'agent',
        'grid.step.kind': engine.StepKind.job.name,
        'grid.step.path': '$workBeadId/agent',
        'grid.step.session': sessionId,
      },
    ),
  ];
}

Future<void> _pumpUntil(
  bool Function() condition, {
  int maxTries = 2000,
}) async {
  for (var i = 0; i < maxTries && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue, reason: 'condition did not settle');
}

Future<void> _mountWork(_Rig rig, String beadId, int generation) async {
  rig.stateBeads.addAll(_sessionState(beadId, generation));
  rig.state.push(_graph(rig.stateBeads, const {}));
  rig.workBeads.add(_workBead(beadId));
  rig.work.push(
    _graph(rig.workBeads, rig.workBeads.map((bead) => bead.id).toSet()),
  );
  final expectedStarts = rig.workBeads.length;
  await _pumpUntil(() => rig.fakes.provider.started.length == expectedStarts);
  final sessionName = rig.fakes.provider.started.last.name;
  rig.fakes.provider.emit(
    SessionStarted(
      name: sessionName,
      pid: expectedStarts,
      pgid: expectedStarts,
    ),
  );
  await Future<void>.delayed(Duration.zero);
}

Future<_Rig> _armFrozen() async {
  final executions = <String>[];
  final work = FakeSnapshotSource();
  final state = FakeSnapshotSource();
  final bridge = engine.StationJoinBridge(work: work, state: state)..start();
  final fakes = buildFakes();
  final policyDelegate = _GenerationDelegate(
    generation: 0,
    executions: executions,
    wiring: null,
  );
  final wiring = _ordinaryWiring(bridge, fakes, policyDelegate);
  var generation = 0;
  _GenerationDelegate build() => _GenerationDelegate(
    generation: generation++,
    executions: executions,
    wiring: wiring,
  );
  final grid = await sdk.runGrid(build(), delegateFactory: build);
  return (
    grid: grid,
    work: work,
    state: state,
    fakes: fakes,
    executions: executions,
    workBeads: <Bead>[],
    stateBeads: <Bead>[],
  );
}

Future<_Rig> _armRefreshable() async {
  final executions = <String>[];
  final work = FakeSnapshotSource();
  final state = FakeSnapshotSource();
  final bridge = engine.StationJoinBridge(work: work, state: state)..start();
  final fakes = buildFakes();
  final assemblyDelegate = _GenerationDelegate(
    generation: 0,
    executions: executions,
    wiring: null,
  );
  final runtimeWiring = _ordinaryWiring(bridge, fakes, assemblyDelegate);
  final wiring = RefreshableStationWorkWiring.fromRuntime(
    runtimeWiring,
    policyBuilder: (delegate) => _policyFor(delegate as _GenerationDelegate),
  );
  var generation = 0;
  _GenerationDelegate build() => _GenerationDelegate(
    generation: generation++,
    executions: executions,
    wiring: wiring,
  );
  final grid = await sdk.runGrid(build(), delegateFactory: build);
  return (
    grid: grid,
    work: work,
    state: state,
    fakes: fakes,
    executions: executions,
    workBeads: <Bead>[],
    stateBeads: <Bead>[],
  );
}

void main() {
  test('frozen wiring characterizes the pre-fix generation policy', () async {
    // Offline characterization of the statically identified composition. It
    // does not claim that a live station failure was observed.
    final rig = await _armFrozen();
    await _mountWork(rig, 'pow-1', 0);
    await rig.grid.hotRestart();
    await _mountWork(rig, 'pow-2', 0);

    expect(rig.executions, ['generation-0:pow-1', 'generation-0:pow-2']);
    await rig.grid.teardown();
  });

  test(
    'hot restart refreshes policy for new work and adopts active work',
    () async {
      final rig = await _armRefreshable();
      await _mountWork(rig, 'pow-1', 0);
      expect(rig.fakes.provider.started, hasLength(1));

      await rig.grid.hotRestart();
      expect(rig.fakes.provider.stopped, isEmpty);
      expect(rig.fakes.provider.started, hasLength(1));

      await _mountWork(rig, 'pow-2', 1);
      expect(rig.executions, ['generation-0:pow-1', 'generation-1:pow-2']);
      expect(rig.fakes.provider.started, hasLength(2));
      expect(rig.fakes.provider.stopped, isEmpty);

      await rig.grid.teardown();
      await _pumpUntil(() => rig.fakes.provider.stopped.length == 2);
      expect(rig.fakes.provider.stopped.toSet(), hasLength(2));
    },
  );

  test(
    'teardown during restart boot does not derive or swap fresh policy',
    () async {
      final executions = <String>[];
      final work = FakeSnapshotSource();
      final state = FakeSnapshotSource();
      final bridge = engine.StationJoinBridge(work: work, state: state)
        ..start();
      final fakes = buildFakes();
      final assemblyDelegate = _GenerationDelegate(
        generation: 0,
        executions: executions,
        wiring: null,
      );
      final runtimeWiring = _ordinaryWiring(bridge, fakes, assemblyDelegate);
      var policyBuilds = 0;
      final wiring = RefreshableStationWorkWiring.fromRuntime(
        runtimeWiring,
        policyBuilder: (delegate) {
          policyBuilds++;
          return _policyFor(delegate as _GenerationDelegate);
        },
      );
      var liveDisposals = 0;
      final live = _GenerationDelegate(
        generation: 0,
        executions: executions,
        wiring: wiring,
        onDisposed: () => liveDisposals++,
      );
      final bootGate = Completer<void>();
      var freshDisposals = 0;
      final swaps = <sdk.GridDelegate>[];
      final grid = await sdk.runGrid(
        live,
        delegateFactory: () => _GenerationDelegate(
          generation: 1,
          executions: executions,
          wiring: wiring,
          bootGate: bootGate.future,
          onDisposed: () => freshDisposals++,
        ),
        onDelegateSwapped: swaps.add,
      );
      expect(policyBuilds, 1);

      final restart = grid.hotRestart();
      await Future<void>.delayed(Duration.zero);
      await grid.teardown();
      bootGate.complete();
      await expectLater(
        restart,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('tore down during the restart boot'),
          ),
        ),
      );

      expect(swaps, isEmpty);
      expect(policyBuilds, 1, reason: 'no post-teardown policy was derived');
      expect(liveDisposals, 1);
      expect(freshDisposals, 1);
    },
  );
}
