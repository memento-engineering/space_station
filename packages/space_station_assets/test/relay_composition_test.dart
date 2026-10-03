/// The station's PROTECTIVE RELAY, proved in the real tree (space-8pq).
///
/// `SpaceDelegate.build` composes grid_assets' vended `RelayAssets` immediately
/// below whichever `StationWork` it mounts — the refreshable
/// `_PolicyBoundStationWork` branch AND the plain `sdk.StationWork` branch —
/// over the STATION'S OWN collaborators (`StationRelayReads` and the posture's
/// inference seam) unless a test overrides them. Presence is the downstream
/// station's own exact `RelayAgentEnvironment.provider()` above the roster
/// (lunar's station-wide relay); arming is this seed, composed on every armed
/// build. So:
///
///  * AC-1 — with lunar-shaped presence, EACH branch registers exactly ONE
///    `RelayAgentObserver` at the seat's ceiling on the registrar `StationWork`
///    provides — with injected Fakes AND with nothing injected at all (the
///    production constructor shape every `up` uses); with no exact presence,
///    NEITHER registers anything.
///  * AC-2 — an already-expired live session driven through the REAL
///    `WorkSessionLiveness` reaches the mounted relay once, persists one UTC
///    next-observation horizon, closes no session and emits no `relay.absent`
///    flare — the exact signal the unmounted station escalated every epoch —
///    including through the station's own readers over a real worktree.
///
/// Fakes, not mocks: a recording registrar, recording readers, a canned-answer
/// runner, a recording transport, recording git/bd runners and the engine's
/// own `buildFakes()` services. Only the station-reader AC-2 case touches the
/// filesystem (a temp worktree it deletes). Every tree owner, relay
/// registration, liveness coordinator, notifier and delegate is disposed
/// exactly once.
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart'
    show BdResult, BdRunner, GraphSnapshot;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentBrief,
        AgentEnvironment,
        RelayAgentEnvironment,
        RelayAgentObserver,
        RelayAssets,
        RelayFlareRecord,
        RelayGateRecord,
        RelayInferenceRunner,
        RelayReadTools,
        RelayTelemetryRecord,
        RelayWorktreeSnapshot,
        kRelayToolAllowList;
import 'package:grid_engine/grid_engine.dart' as engine;
import 'package:grid_engine/testing.dart' show Fakes, buildFakes;
import 'package:grid_runtime/grid_runtime.dart' show GitRunResult, GitRunner;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// lunar's station-wide relay, restated by VALUE: the cheap ladder, the
/// paused-and-expired mission, the exact vended tool set, ceiling 1.
const RelayAgentEnvironment kLunarShapedRelay = RelayAgentEnvironment(
  kCheapLadder,
  mission: 'Observe paused and expired sessions.',
  tools: kRelayToolAllowList,
  ceiling: 1,
);

/// The two station-work branches `SpaceDelegate.build` dispatches between.
enum _WiringShape { ordinary, refreshable }

// ── Fakes ────────────────────────────────────────────────────────────────────

final class _RecordingRegistration implements engine.RelayRegistration {
  _RecordingRegistration({required this.observer, required this.ceiling});

  final engine.RelayObserver observer;
  final int ceiling;
  int disposals = 0;

  @override
  void dispose() => disposals++;
}

/// Records every mount and keeps each registration's disposal count, so a
/// test can assert BOTH "exactly one live" and "released exactly once".
final class _RecordingRegistrar implements engine.RelayRegistrar {
  final List<_RecordingRegistration> mounted = <_RecordingRegistration>[];

  Iterable<_RecordingRegistration> get live =>
      mounted.where((registration) => registration.disposals == 0);

  @override
  engine.RelayRegistration mountRelay({
    required engine.RelayObserver observer,
    required int ceiling,
  }) {
    final registration = _RecordingRegistration(
      observer: observer,
      ceiling: ceiling,
    );
    mounted.add(registration);
    return registration;
  }
}

/// The four read tools as recording Fakes over canned evidence.
final class _RecordingReads {
  final List<engine.RelayObservation> observed = <engine.RelayObservation>[];

  late final RelayReadTools tools = RelayReadTools(
    readWorktree: (observation) async {
      observed.add(observation);
      return RelayWorktreeSnapshot(
        mtimes: {'lib/a.dart': DateTime.utc(2026, 9, 25, 11)},
        lastCommit: 'feat: stale',
        lastCommitAt: DateTime.utc(2026, 9, 25, 10),
      );
    },
    readFlareTail: (_) async => const <RelayFlareRecord>[],
    readTelemetry: (_) async => const <RelayTelemetryRecord>[],
    readGate: (_) async => null as RelayGateRecord?,
  );
}

/// Answers every brief with one canned verdict and records what it was asked.
final class _CannedRelayRunner implements RelayInferenceRunner {
  _CannedRelayRunner(this.answer);

  final String answer;
  final List<AgentBrief> briefs = <AgentBrief>[];
  final List<AgentEnvironment> environments = <AgentEnvironment>[];

  @override
  Future<String> run({
    required AgentEnvironment environment,
    required AgentBrief brief,
  }) async {
    environments.add(environment);
    briefs.add(brief);
    return answer;
  }
}

final class _RecordingTransport implements engine.ExplorationTransport {
  final List<(String, Map<String, String>)> flares =
      <(String, Map<String, String>)>[];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name, Map<String, String>.of(data)));
}

/// Answers `git log -1` with one canned commit record and records the calls.
final class _CannedGit implements GitRunner {
  final List<({String workingDirectory, List<String> args})> calls =
      <({String workingDirectory, List<String> args})>[];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add((workingDirectory: workingDirectory, args: args));
    return const GitRunResult(
      exitCode: 0,
      output: 'abc1234 feat: halfway\x002026-09-23T10:00:00-05:00\n',
    );
  }
}

/// Answers every bd call with one enveloped list and records the argv.
final class _CannedBd implements BdRunner {
  _CannedBd(this.rows);

  final List<Map<String, Object?>> rows;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(args);
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode({'schema_version': 1, 'data': rows}),
      stderr: '',
    );
  }
}

// ── The delegate fixture ─────────────────────────────────────────────────────

/// The real `SpaceDelegate` with lunar's presence declaration either mounted
/// above the roster (as `LunarDelegate.seatSeeds` does) or omitted, over a
/// one-substation roster so the fan-out below the relay is real and offline.
final class _RelayDelegate extends SpaceDelegate {
  _RelayDelegate({
    required this.relayPresence,
    required super.wiring,
    super.relayTools,
    super.relayRunner,
  }) : super(gridRoot: '/grid/home');

  // `live` stays false (the dry-run default): an offline mount probes no
  // machine, so the seat's environment resolves from the boot registry.

  final bool relayPresence;

  @override
  List<SingleChildSeed> seatSeeds(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    ...super.seatSeeds(context, configuration),
    if (relayPresence) kLunarShapedRelay.provider(),
  ];

  @override
  List<Seed> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    sdk.Substation(
      'power_station',
      '/work/power_station',
      prefix: 'pow',
      assets: const [sdk.SubstationWork()],
    ),
  ];
}

/// Calls `SpaceDelegate.build` with a live [TreeContext] during mount — the
/// offline stand-in for runGrid's delegate root.
final class _Author extends StatelessSeed {
  const _Author(this.delegate);

  final SpaceDelegate delegate;

  @override
  Seed build(TreeContext context) =>
      delegate.build(context, const sdk.GridConfiguration());
}

/// No work mounts in this suite, so the policy's resolver is never reached.
DelegateWorkPolicy _policy() => DelegateWorkPolicy(
  resolver: engine.CircuitResolver(
    (bead) => throw StateError('no work bead mounts in this suite: $bead'),
  ),
  registry: engine.DefaultCapabilityRegistry(),
);

/// One armed rig: the wiring in the requested [shape] over shared offline
/// resources, plus the delegate built over it. Everything is released at
/// teardown exactly once, in reverse mount order.
typedef _Rig = ({
  _RelayDelegate delegate,
  TreeOwner owner,
  Branch root,
  Fakes fakes,
});

_Rig _arm({
  required _WiringShape shape,
  required bool relayPresence,
  required engine.RelayRegistrar registrar,
  RelayReadTools? tools,
  RelayInferenceRunner? runner,
}) {
  final fakes = buildFakes();
  final notifier = engine.JoinedSnapshotNotifier(engine.JoinedSnapshot.empty());
  addTearDown(notifier.dispose);
  final policy = _policy();
  final ordinary = sdk.StationWorkWiring(
    notifier: notifier,
    services: fakes.ctx,
    resolver: policy.resolver,
    registry: policy.registry,
    relayRegistrar: registrar,
  );
  final wiring = switch (shape) {
    _WiringShape.ordinary => ordinary,
    _WiringShape.refreshable => RefreshableStationWorkWiring.fromRuntime(
      ordinary,
      policyBuilder: (_) => _policy(),
    ),
  };
  final delegate = _RelayDelegate(
    relayPresence: relayPresence,
    wiring: wiring,
    relayTools: tools,
    relayRunner: runner,
  );
  final owner = TreeOwner();
  final root = owner.mountRoot(_Author(delegate));
  owner.flush();
  addTearDown(delegate.dispose);
  return (delegate: delegate, owner: owner, root: root, fakes: fakes);
}

/// Every branch whose seed is a [T], each paired with its ancestor chain
/// (root first) — the structural read the placement assertions walk.
List<({Branch branch, List<Branch> ancestors})> _branchesOf<T extends Seed>(
  Branch root,
) {
  final found = <({Branch branch, List<Branch> ancestors})>[];
  void walk(Branch branch, List<Branch> ancestors) {
    if (branch.seed is T) {
      found.add((branch: branch, ancestors: List<Branch>.of(ancestors)));
    }
    final below = [...ancestors, branch];
    branch.visitChildren((child) => walk(child, below));
  }

  walk(root, const []);
  return found;
}

void main() {
  const absorbInAnHour = '{"verdict":"absorb","nextHorizonSeconds":3600}';

  group('AC-1 both station-work branches register one relay', () {
    for (final shape in _WiringShape.values) {
      test('${shape.name} wiring: lunar-shaped presence registers exactly one '
          'RelayAgentObserver at ceiling 1', () {
        final registrar = _RecordingRegistrar();
        final reads = _RecordingReads();
        final runner = _CannedRelayRunner(absorbInAnHour);
        final rig = _arm(
          shape: shape,
          relayPresence: true,
          registrar: registrar,
          tools: reads.tools,
          runner: runner,
        );

        // Exactly one live registration, and it is the vended observer over
        // the exact seat, at the SEAT's ceiling — the relay population's own
        // bound, not the work-slot pool's.
        expect(registrar.mounted, hasLength(1));
        final registration = registrar.live.single;
        expect(registration.ceiling, 1);
        final observer = registration.observer;
        expect(observer, isA<RelayAgentObserver>());
        observer as RelayAgentObserver;
        expect(observer.seat, kLunarShapedRelay);
        expect(observer.environment, kCheapEnvironment);
        expect(observer.tools, same(reads.tools));
        expect(observer.runner, same(runner));

        // Placement: the ONE RelayAssets branch sits BELOW the StationWork
        // branch (so it watches the registrar that seed provides) and ABOVE
        // the substation fan-out (so every substation inherits the armed
        // relay — a TREE seed, nearest ancestor wins).
        final stationWork = _branchesOf<sdk.StationWork>(rig.root).single;
        final relay = _branchesOf<RelayAssets>(rig.root).single;
        expect(
          relay.ancestors,
          contains(same(stationWork.branch)),
          reason: 'RelayAssets is mounted below StationWork',
        );
        final fanOut = _branchesOf<sdk.Substations>(rig.root).single;
        expect(
          fanOut.ancestors,
          contains(same(relay.branch)),
          reason: 'the substation fan-out is below the relay',
        );
        expect(
          relay.ancestors,
          isNot(contains(same(fanOut.branch))),
          reason: 'the relay is never inside one substation here',
        );

        // Nothing observed anything: presence + arming mount, they do not
        // spawn. The reads and the runner stay untouched until a session is
        // due.
        expect(reads.observed, isEmpty);
        expect(runner.briefs, isEmpty);

        // Unmounting releases the registration exactly once.
        rig.owner.dispose();
        expect(registration.disposals, 1);
        expect(registrar.live, isEmpty);
      });

      test('${shape.name} wiring: no exact presence registers nothing and '
          'mounts no observer', () {
        final registrar = _RecordingRegistrar();
        final reads = _RecordingReads();
        final runner = _CannedRelayRunner(absorbInAnHour);
        final rig = _arm(
          shape: shape,
          relayPresence: false,
          registrar: registrar,
          tools: reads.tools,
          runner: runner,
        );

        // The seed is composed (arming is the station's) but with no exact
        // RelayAgentEnvironment above it, it mounts NOTHING — the engine's
        // relay.absent path stays armed for a station that declared no relay.
        expect(_branchesOf<RelayAssets>(rig.root), hasLength(1));
        expect(_branchesOf<sdk.StationWork>(rig.root), hasLength(1));
        expect(registrar.mounted, isEmpty);
        expect(reads.observed, isEmpty);
        expect(runner.briefs, isEmpty);

        rig.owner.dispose();
        expect(registrar.mounted, isEmpty);
      });
    }

    for (final shape in _WiringShape.values) {
      test(
        '${shape.name} wiring: a delegate built with NO injected relay '
        'collaborators (the production constructor shape) still registers '
        'exactly one RelayAgentObserver from the station\'s own services',
        () {
          // This is the shape `up` builds through SpaceDelegateFactory: no
          // relayTools, no relayRunner. Presence alone must arm the relay.
          final registrar = _RecordingRegistrar();
          final rig = _arm(
            shape: shape,
            relayPresence: true,
            registrar: registrar,
          );

          expect(_branchesOf<RelayAssets>(rig.root), hasLength(1));
          expect(registrar.mounted, hasLength(1));
          final registration = registrar.live.single;
          expect(registration.ceiling, 1);
          final observer = registration.observer;
          expect(observer, isA<RelayAgentObserver>());
          observer as RelayAgentObserver;
          expect(observer.seat, kLunarShapedRelay);
          expect(observer.environment, kCheapEnvironment);
          // The station's own seams: a dry-run delegate (live: false) spawns no
          // inference, so its relay answers by REFUSING (relay.error), never by
          // an absent relay (relay.absent).
          expect(observer.runner, isA<DryRunRelayInference>());

          rig.owner.dispose();
          expect(registration.disposals, 1);
        },
      );

      test('${shape.name} wiring: with NO injected collaborators and no '
          'presence, nothing registers', () {
        final registrar = _RecordingRegistrar();
        final rig = _arm(
          shape: shape,
          relayPresence: false,
          registrar: registrar,
        );

        expect(_branchesOf<RelayAssets>(rig.root), hasLength(1));
        expect(registrar.mounted, isEmpty);
        rig.owner.dispose();
      });
    }

    test('the station\'s own readers keep ONE identity across builds, so a '
        'rebuild never churns the mounted observer', () {
      final fakes = buildFakes();
      final notifier = engine.JoinedSnapshotNotifier(
        engine.JoinedSnapshot.empty(),
      );
      addTearDown(notifier.dispose);
      final policy = _policy();
      final registrar = _RecordingRegistrar();
      final delegate = _RelayDelegate(
        relayPresence: true,
        wiring: sdk.StationWorkWiring(
          notifier: notifier,
          services: fakes.ctx,
          resolver: policy.resolver,
          registry: policy.registry,
          relayRegistrar: registrar,
        ),
      );
      addTearDown(delegate.dispose);
      final first = TreeOwner();
      addTearDown(first.dispose);
      first.mountRoot(_Author(delegate));
      first.flush();
      final second = TreeOwner();
      addTearDown(second.dispose);
      second.mountRoot(_Author(delegate));
      second.flush();

      expect(registrar.mounted, hasLength(2));
      final a = registrar.mounted[0].observer as RelayAgentObserver;
      final b = registrar.mounted[1].observer as RelayAgentObserver;
      expect(b.tools, same(a.tools));
      expect(b.runner, same(a.runner));
    });
  });

  group('AC-2 an expired session reaches the mounted relay', () {
    final clock = DateTime.utc(2026, 9, 25, 12);
    const sessionId = 'houston-expired';
    const workBeadId = 'pow-expired';

    engine.JoinedSnapshot expiredSession() => engine.JoinedSnapshot(
      graph: GraphSnapshot.fromParts(
        beads: const [],
        dependencies: const [],
        readyIds: const <String>{},
        capturedAt: clock,
      ),
      stateCapturedAt: clock,
      sessionsByWorkBead: {
        workBeadId: engine.SessionProjection(
          workBeadId: workBeadId,
          sessionId: sessionId,
          startedAt: clock.subtract(const Duration(days: 2)),
          // The DURABLE horizon already passed: this session is due NOW.
          relayNextObservationAt: clock.subtract(const Duration(hours: 1)),
        ),
      },
    );

    Future<void> drain() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    for (final shape in _WiringShape.values) {
      test('${shape.name} wiring: one inference, one UTC horizon write, no '
          'close, no relay.absent flare', () async {
        final transport = _RecordingTransport();
        final horizons = <(String, DateTime)>[];
        final liveness = engine.WorkSessionLiveness(
          writeHorizon: (id, at) async => horizons.add((id, at)),
          transport: transport,
          clock: () => clock,
        );
        addTearDown(liveness.dispose);
        final reads = _RecordingReads();
        final runner = _CannedRelayRunner(absorbInAnHour);
        final rig = _arm(
          shape: shape,
          relayPresence: true,
          registrar: liveness,
          tools: reads.tools,
          runner: runner,
        );

        liveness.refresh(expiredSession());
        liveness.activate();
        liveness.onFencedTick();
        await drain();

        // The mounted relay observed the due session exactly once ...
        expect(reads.observed, hasLength(1));
        expect(reads.observed.single.sessionId, sessionId);
        expect(reads.observed.single.workBeadId, workBeadId);
        expect(runner.briefs, hasLength(1));
        expect(runner.environments.single, kCheapEnvironment);
        expect(
          runner.briefs.single.task,
          contains('Observe paused and expired sessions.'),
          reason: 'the brief carries the armed seat\'s own mission',
        );
        // ... its absorb persisted ONE UTC horizon, clock + 1h, for that
        // session ...
        expect(horizons, hasLength(1));
        expect(horizons.single.$1, sessionId);
        expect(horizons.single.$2, clock.add(const Duration(hours: 1)));
        expect(horizons.single.$2.isUtc, isTrue);
        // ... no flare fired — in particular not the relay.absent the
        // unmounted station escalated every epoch — ...
        expect(transport.flares, isEmpty);
        expect(
          transport.flares.map((flare) => flare.$1),
          isNot(contains(engine.kRelayAbsentFlare)),
        );
        // ... and nothing closed a session: a relay is never the breaker, and
        // the bd chokepoint saw no call at all.
        expect(rig.fakes.runner.calls, isEmpty);

        // A second tick inside the new horizon observes nothing more.
        liveness.onFencedTick();
        await drain();
        expect(runner.briefs, hasLength(1));
        expect(horizons, hasLength(1));

        rig.owner.dispose();
      });
    }

    test('station readers: an expired session is inspected through the '
        'station\'s own worktree, flare, telemetry and gate reads, and its '
        'absorb persists one horizon with no relay.absent flare', () async {
      final home = await Directory.systemTemp.createTemp('relay-ac2-');
      addTearDown(() => home.delete(recursive: true));
      final worktree = p.join(
        home.path,
        'power_station',
        '.grid',
        'worktrees',
        'power_station',
        workBeadId,
      );
      await File(p.join(worktree, 'lib', 'a.dart')).create(recursive: true);
      final git = _CannedGit();
      final bd = _CannedBd([
        {
          'id': 'houston-gate1',
          'title': 'grid gate $sessionId@$workBeadId/review/route',
          'status': 'open',
          'priority': 2,
          'issue_type': 'gate',
          'metadata': {'blocks': sessionId, 'reason': 'a critic returned F'},
        },
      ]);
      final tail = StationFlareTail(clock: () => clock);
      tail.flare('step.gated', {'nodePath': '$workBeadId/review/route'});
      tail.flare('step.gated', {'nodePath': 'pow-other/review/route'});
      final reads = StationRelayReads(
        worktreeRoots: [
          (
            substation: 'power_station',
            root: p.join(home.path, 'power_station'),
          ),
        ],
        stateStoreRoot: p.join(home.path, '.grid'),
        flares: tail,
        git: git,
        stateStoreBd: bd,
      );

      final transport = _RecordingTransport();
      final horizons = <(String, DateTime)>[];
      final liveness = engine.WorkSessionLiveness(
        writeHorizon: (id, at) async => horizons.add((id, at)),
        transport: transport,
        clock: () => clock,
      );
      addTearDown(liveness.dispose);
      final runner = _CannedRelayRunner(absorbInAnHour);
      final rig = _arm(
        shape: _WiringShape.refreshable,
        relayPresence: true,
        registrar: liveness,
        tools: reads.tools,
        runner: runner,
      );

      liveness.refresh(expiredSession());
      liveness.activate();
      liveness.onFencedTick();
      for (var i = 0; i < 20 && runner.briefs.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await drain();

      // Every station read ran against the real sources ...
      expect(git.calls.single.workingDirectory, worktree);
      expect(bd.calls.single, containsAllInOrder(['list', '-t', 'gate']));
      expect(bd.calls.single, contains('blocks=$sessionId'));
      // ... and their evidence reached the ONE inference the relay made.
      expect(runner.briefs, hasLength(1));
      final brief = runner.briefs.single.task;
      expect(brief, contains('lib/a.dart'));
      expect(brief, contains('abc1234 feat: halfway'));
      expect(brief, contains('houston-gate1'));
      expect(brief, contains('$workBeadId/review/route'));
      expect(brief, isNot(contains('pow-other')));
      // One UTC horizon, no flare, no bd write through the engine chokepoint.
      expect(horizons, [(sessionId, clock.add(const Duration(hours: 1)))]);
      expect(transport.flares, isEmpty);
      expect(rig.fakes.runner.calls, isEmpty);

      rig.owner.dispose();
    });

    test(
      'control: the same rig with no presence escalates relay.absent',
      () async {
        // Proves the AC-2 rig is not vacuous: strip the presence declaration
        // and the identical expired session hits the engine's absent path.
        final transport = _RecordingTransport();
        final horizons = <(String, DateTime)>[];
        final liveness = engine.WorkSessionLiveness(
          writeHorizon: (id, at) async => horizons.add((id, at)),
          transport: transport,
          clock: () => clock,
        );
        addTearDown(liveness.dispose);
        final reads = _RecordingReads();
        final runner = _CannedRelayRunner(absorbInAnHour);
        final rig = _arm(
          shape: _WiringShape.refreshable,
          relayPresence: false,
          registrar: liveness,
          tools: reads.tools,
          runner: runner,
        );

        liveness.refresh(expiredSession());
        liveness.activate();
        liveness.onFencedTick();
        await drain();

        expect(reads.observed, isEmpty);
        expect(runner.briefs, isEmpty);
        expect(horizons, isEmpty);
        expect(transport.flares, hasLength(1));
        expect(transport.flares.single.$1, engine.kRelayAbsentFlare);
        expect(transport.flares.single.$2['sessionId'], sessionId);
        expect(transport.flares.single.$2['reason'], 'no relay is mounted');

        rig.owner.dispose();
      },
    );
  });
}
