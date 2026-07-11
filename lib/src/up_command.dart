/// `space up` — RS-5b (`the_grid/docs/SCRATCH-resident-station.md` D-R1/D-C3),
/// re-seated onto the C/D-era pieces (Track G-space / H2, tg-r81).
///
/// `up` authors a [SpaceDelegate] — space_station as a Seed (the v3 §2 tree) —
/// from its OWN flag surface ([addSpaceStationFlags] / [spaceStationConfigFrom],
/// in `space_delegate.dart`), and **drives it with `runGrid`**. The old boot
/// path — `grid_cli`'s `StationArgs` → `discoverWorkspaces` → `buildControllers`
/// → `buildLiveWiring` → `composeStation` → `driveStation` station-runner
/// pipeline — is GONE (DoD#6): nothing here imports the kill-list surface. The
/// pieces, in order:
///
///  1. boot-eager `AgentHarnessRegistry` validation (a misconfigured MACHINE
///     fails loud before any tree mounts);
///  2. space's OWN config (`--substation <name>=<root>` pairs + `--grid-home`),
///     v3 stores-at-roots — no `StationArgs`, no `RootSpec`, no `--workspace`
///     axis;
///  3. **stores at roots** (grid_sdk `StoreLocator`): each substation's `.beads/`
///     work store must exist at its exact root (the `discoverWorkspaces`
///     replacement — exact-at-root, LOUD refusal, no walk-up);
///  4. `runGrid(SpaceDelegate())` — mount the §2 tree (the C/D-era pieces);
///  5. the RS-2 station lock (`StationLockService`) + the RS-4 read-only control
///     surface (`StationControl`) around it — the resident lock/control/drain
///     contract, orchestrated over the RS-2/RS-4 SURVIVORS (not the deleted
///     `driveStation`); parked on the SIGINT/SIGTERM graceful path (D-R2).
///
/// **Track J: the work binding is IN.** `up` assembles the off-tree machinery
/// with `grid_sdk.buildStationWork` (controllers over the stores at their
/// roots → the freshness barrier → the restart reconciler → the join bridge —
/// the pinned ordering, ADR-0007 §4) and mounts the ARMED tree
/// (`runGrid(delegate, onFlushed: work.afterFlush)`): each substation's
/// `SubstationWork` establishes its `WorkList`, and the ready frontier
/// reconciles (mount = spawn). Under `--dry-run` (the SAFE DEFAULT) every
/// seam is inert — no spawn, no store write, no git — while the counts and
/// the control surface are REAL. The first LIVE arm (`--no-dry-run`) stays
/// the human gate. `up` stays foreground-resident: no self-daemonization, no
/// double-fork — the supervisor (launchd, RS-6) owns backgrounding.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentConfig,
        ModelTarget,
        OpenAiCompatible,
        ProviderManaged,
        SwiftInfer,
        buildAgentHarnessRegistry;
// RS-2/RS-4 SURVIVORS (station_lock.dart / station_control.dart) — NOT the
// station-runner kill-list. `up` orchestrates them itself now that the
// `driveStation` boot path is gone (DoD#6).
import 'package:grid_cli/grid_cli.dart'
    show
        StationControl,
        StationLockHandle,
        StationLockService,
        StationStatus,
        mintControlToken;
import 'package:grid_assets/grid_assets.dart'
    show buildCodeRegistry, kCodeCircuit;
import 'package:grid_runtime/grid_runtime.dart'
    show SystemProcessGroupController;
import 'package:grid_sdk/grid_sdk.dart'
    show
        CircuitResolver,
        GridHandle,
        GridStateStore,
        StationWorkRuntime,
        StoreLocator,
        StoreRefusal,
        SubstationWorkSpec,
        buildLandOps,
        buildStationWork,
        runGrid;
import 'package:path/path.dart' as p;

import 'space_delegate.dart';

/// One substation `up` armed — a name, its resolved ABSOLUTE root, and its
/// work store's issue-id prefix. The off-tree work machinery (the store
/// guard, `buildStationWork`'s specs, the `/status` view) runs BEFORE the
/// tree mounts (the pinned ordering, ADR-0007 §4), so it carries the roster
/// as plain values; the tree itself is authored independently, literally, in
/// `SpaceDelegate.build` (space-6ds Fork A).
typedef _ArmedSubstation = ({String name, String root, String prefix});

/// `space up`: boots the resident station.
class UpCommand extends Command<int> {
  /// Creates the up command (space's own station flags MINUS `--bead`, plus the
  /// agent scope's).
  UpCommand() {
    addSpaceStationFlags(argParser);
    argParser
      ..addOption(
        'harness',
        defaultsTo: 'claude',
        allowed: ['claude', 'copilot', 'pi', 'opencode'],
        help:
            'The agentic harness coding work runs on (the station default; a '
            'bead may override via its grid.agent envelope, a step via '
            'params).',
      )
      ..addOption(
        'model',
        help:
            'The model a managed tool selects (claude/copilot) or an '
            'endpoint harness requests — rides AgentConfig.params, not the '
            'target.',
      )
      ..addOption(
        'openai-base',
        help:
            'An OpenAI-compatible inference endpoint (e.g. a llama.cpp '
            'server) — sets the model target for pi/opencode.',
      )
      ..addOption(
        'swift-base',
        help: 'A swift-infer server endpoint — sets the model target for pi.',
      )
      ..addFlag(
        'land',
        defaultsTo: false,
        help:
            'Arm PR-opening (land) on a LIVE run (ADR-0006 D3): the land ops '
            'flow into each substation\'s GitHub asset. Refused with '
            '--dry-run (a contradiction the operator must see, not a silent '
            'no-op). Off = the commit-only arm.',
      )
      ..addOption(
        'max-agents',
        defaultsTo: '4',
        help:
            'The station-wide concurrency ceiling (tg-42f): the most work '
            'beads mounted (agents live) at once across every substation.',
      );
  }

  @override
  final String name = 'up';

  @override
  final String description =
      'Boot the resident station (RS-5b), authored as a SpaceDelegate and '
      'driven with runGrid: validated harness scope, substations resolved at '
      'their roots (v3 stores-at-roots), and the code asset\'s per-substation '
      'git — ALWAYS resident: the ready frontier of the owned substation IS the '
      'drive set (no --bead, ever), guarded by the ONE-supervisor-per-store '
      'lock (RS-2) and observable over the read-only StationControl surface '
      '(RS-4). Foreground-resident (a supervisor owns backgrounding). Defaults '
      'to --dry-run (armed over INERT seams — no spawn, no write); the first '
      'LIVE arm (--no-dry-run) is the human gate.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final out = _out;
    final err = _err;

    // --- the station-default agent scope (D-C rung 1) + boot-eager
    // validation (OQ-c moment 1: a misconfigured MACHINE fails loud before
    // any tree mounts; a misconfigured BEAD fails per-work at resolution).
    final openaiBase = results.option('openai-base');
    final swiftBase = results.option('swift-base');
    if (openaiBase != null && swiftBase != null) {
      err('space up: pass --openai-base OR --swift-base, not both.');
      return 64;
    }
    final ModelTarget target;
    try {
      target = openaiBase != null
          ? OpenAiCompatible(_parseBase(openaiBase, '--openai-base'))
          : swiftBase != null
          ? SwiftInfer(_parseBase(swiftBase, '--swift-base'))
          : const ProviderManaged();
    } on FormatException catch (e) {
      err('space up: ${e.message}');
      return 64;
    }
    // Pin an EXPLICIT model — never inherit the `claude` CLI default. The
    // default resolved to opus, then silently fell back to fable once the
    // weekly opus limit blew (the grid spawns ~10 agents/bead; it obliterates a
    // limit fast), eating fable quota nobody asked for. An explicit model gives
    // every agent — the coding agent AND the committee critics, which ride the
    // same base config — a known tier with no fallback surprise. Sonnet is the
    // station default (graders don't need a frontier model and neither do most
    // builds); override station-wide with --model.
    final model = results.option('model') ?? 'sonnet';
    final agentConfig = AgentConfig(
      harness: results.option('harness') ?? 'claude',
      target: target,
      params: {'model': model},
    );
    final harnesses = buildAgentHarnessRegistry();
    final invalid = harnesses.validate(agentConfig);
    if (invalid != null) {
      err('space up: $invalid');
      return 64;
    }

    // --- space's OWN resident-station config (v3 stores-at-roots). The coded
    // memento roster is HARDCODED in SpaceDelegate.build (space-6ds); flags
    // only APPEND new substations, so only a missing --grid-home is a LOUD
    // arming refusal (never a `''` sentinel — v3 kills those). A malformed,
    // duplicate, or coded-name --substation is an uncaught FormatException (a
    // config defect the operator sees immediately).
    final config = spaceStationConfigFrom(results);
    if (config == null) {
      err(
        'space up: --grid-home (the state store / RS-2 lock home) is required '
        'to ARM — v3 §0: there is no default grid home.',
      );
      return 64;
    }
    final landArmed = results.flag('land');
    if (landArmed && config.dryRun) {
      err(
        'space up: --land contradicts --dry-run — a dry run opens no PRs. '
        'Drop --land, or arm live with --no-dry-run.',
      );
      return 64;
    }
    final int maxAgents;
    try {
      maxAgents = int.parse(results.option('max-agents')!);
    } on FormatException {
      err('space up: --max-agents must be an integer.');
      return 64;
    }

    // --- stores at roots (the discoverWorkspaces replacement). The grid state
    // store lives under `<grid-home>/.grid/`; a cwd-relative home re-imports
    // the ambience v3 kills (StoreRefusal/ArgumentError, exact-at-root). Its
    // `.beads/` is seeded on first boot (absence is not a refusal — Q5a), so
    // only the absolute-root guard runs here.
    try {
      GridStateStore.forGridRoot(config.gridHome);
    } on ArgumentError catch (e) {
      err('space up: ${e.message}');
      return 64;
    }
    // Each substation's `.beads/` work store is looked for at its EXACT root, no
    // walk-up (grid_sdk StoreLocator). Provenance splits the guard (space-6ds
    // Fork A/B): an APPENDED substation (a `--substation` flag) whose store is
    // absent is a LOUD refusal — the operator's error; a CODED-roster substation
    // not present in THIS checkout (a sibling not yet cloned/relocated — e.g.
    // lenny) is skipped LOUD so the rest of the org still arms. `space up` arms
    // exactly what resolves a store; nothing resolving is itself a LOUD refusal.
    //
    // The coded org, restated as OFF-TREE specs: the work machinery (the
    // controllers `buildStationWork` builds, this guard, the /status view)
    // runs BEFORE the tree mounts, so it cannot read the tree's seats — each
    // `../<repo>` sibling is resolved against the grid home here exactly as
    // the tree's literal seats resolve against the ambient GridRoot (tg-32r).
    // Same five seats, same order, same prefixes as SpaceDelegate.build.
    final coded = <_ArmedSubstation>[
      (
        name: 'genesis',
        root: p.normalize(p.join(config.gridHome, '../genesis')),
        prefix: 'genesis',
      ),
      (
        name: 'the_grid',
        root: p.normalize(p.join(config.gridHome, '../the_grid')),
        prefix: 'tg',
      ),
      (
        name: 'power_station',
        root: p.normalize(p.join(config.gridHome, '../power_station')),
        prefix: 'pow',
      ),
      (
        name: 'space_station',
        root: p.normalize(p.join(config.gridHome, '../space_station')),
        prefix: 'space_station',
      ),
      (
        name: 'lenny',
        root: p.normalize(p.join(config.gridHome, '../lenny')),
        prefix: 'lenny',
      ),
    ];
    final locator = StoreLocator();
    final armed = <_ArmedSubstation>[];
    for (final s in coded) {
      try {
        locator.locateWorkStore(root: s.root, substationName: s.name);
        armed.add(s);
      } on StoreRefusal {
        out(
          'space up: skipping coded substation "${s.name}" — no work store at '
          '${s.root} (not present in this checkout).',
        );
      }
    }
    for (final s in config.appended) {
      try {
        locator.locateWorkStore(root: s.root, substationName: s.name);
        armed.add((name: s.name, root: s.root, prefix: s.prefix));
      } on ArgumentError catch (e) {
        err('space up: ${e.message}');
        return 64;
      } on StoreRefusal catch (e) {
        err('space up: ${e.message}');
        return 1;
      }
    }
    if (armed.isEmpty) {
      err(
        'space up: no substation resolved a work store at its root — nothing to '
        'arm. The coded roster resolves siblings of the grid home; run from the '
        'memento umbrella or pass --substation <name>=<root>.',
      );
      return 1;
    }

    // --- RS-2 the station lock (D-A1): ONE supervisor per station state store.
    // Acquired before anything stateful; a LIVE holder is a LOUD refusal (exit
    // 64). Caught generically so `up` never imports the kill-list refusal type.
    final bootTime = DateTime.now();
    final StationLockHandle stationLock;
    try {
      stationLock = await StationLockService(log: out).acquire(
        stateWorkspaceDir: config.gridHome,
        pid: pid,
        pgid: SystemProcessGroupController().currentGroupId(),
        now: bootTime,
      );
    } on Object catch (e) {
      err('$e');
      return 64;
    }

    // --- the off-tree work machinery (Track J, the runGrid→engine bridge):
    // controllers over the REAL stores at their roots, the join bridge, the
    // bd chokepoint (a recording no-op under --dry-run), the restart
    // reconciler. The code circuit + its capabilities are the grid_assets
    // OPINION, injected here (the engine stays opinion-free).
    final StationWorkRuntime workRuntime;
    try {
      workRuntime = await buildStationWork(
        stateStore: GridStateStore.forGridRoot(config.gridHome),
        substations: [
          for (final s in armed)
            SubstationWorkSpec(name: s.name, root: s.root, prefix: s.prefix),
        ],
        resolver: CircuitResolver((_) => kCodeCircuit),
        registry: buildCodeRegistry(),
        dryRun: config.dryRun,
        maxConcurrentWork: maxAgents,
      );
    } on Object catch (e) {
      await stationLock.release();
      err('space up: $e');
      return 1;
    }

    // The pinned start ordering (ADR-0007 §4): controllers → freshness barrier
    // → restart-reconcile the survivors → the bridge follows — all BEFORE the
    // tree mounts, so nothing blindly respawns.
    try {
      await workRuntime.start();
    } on Object catch (e) {
      await workRuntime.shutdown();
      await stationLock.release();
      err('space up: $e');
      return 1;
    }

    // --- space_station AS A SEED: author the delegate, ARMED with the work
    // wiring. The coded org is hardcoded in its build; only the operator's
    // appended seats ride in. The land ops flow into the substations' GitHub
    // assets only when --land armed a live run (ADR-0006 D3) — never through
    // station services.
    final land = buildLandOps(armed: landArmed && !config.dryRun);
    final delegate = SpaceDelegate(
      gridRoot: config.gridHome,
      stationName: 'space',
      appended: config.appended,
      agentConfig: agentConfig,
      harnesses: harnesses,
      wiring: workRuntime.wiring,
      provisioner: workRuntime.git,
      gitOps: land.gitOps,
      prOpener: land.prOpener,
    );

    // --- mount the tree: runGrid over the SpaceDelegate. The armed WorkLists
    // see the bridge's baseline and reconcile the ready frontier (mount =
    // spawn — inert under --dry-run). A mount-time refusal unwinds everything.
    final GridHandle grid;
    try {
      grid = runGrid(delegate, onFlushed: workRuntime.afterFlush);
    } on Object catch (e) {
      await workRuntime.shutdown();
      await stationLock.release();
      err('space up: $e');
      return 64;
    }

    // --- RS-4 the read-only control surface (D-C2): bound after the lock so it
    // always has a lock file to advertise controlUrl/token through. space
    // builds its OWN StationStatus — H2 drives no work, so ready/mounted/live
    // sessions are 0 (the counts return with the runGrid→kernel bridge).
    final token = mintControlToken();
    final StationControl control;
    try {
      control = await StationControl.start(
        port: config.controlPort,
        token: token,
        view: () => _status(config, armed, bootTime, workRuntime),
      );
    } on Object catch (e) {
      grid.teardown();
      await workRuntime.shutdown();
      await stationLock.release();
      err('space up: $e');
      return 1;
    }
    await stationLock.updateControl(controlUrl: control.url, token: token);

    out('space up — space_station as a Seed (runGrid)');
    out(
      'mode: ${config.dryRun ? 'DRY-RUN (observe-only)' : 'LIVE'}  ·  '
      'substations: {${armed.map((s) => s.name).join(', ')}}  '
      '·  work-driving: ARMED (${config.dryRun ? 'inert seams' : 'live'})  '
      '·  land: ${land.prOpener != null ? 'armed' : 'off'}',
    );
    out(
      'agent scope: harness ${agentConfig.harness} → ${agentConfig.target}'
      '  ·  model $model',
    );
    out(
      'stores: read-path {${workRuntime.readPathName}}  ·  state partition: '
      '${workRuntime.stateSubstation}',
    );
    out('control: ${control.url}  ·  token: (see ${stationLock.path}, 0600)');

    // Dispose the control surface BEFORE releasing the lock (RS-4 scope fence —
    // a released lock naming a dead endpoint would mislead `space status`),
    // then tear the tree down (unmount → effects kill), THEN the off-tree
    // machinery (the bridge outlives the tree, never the reverse), then
    // release LAST.
    Future<void> shutdown() async {
      await control.dispose();
      grid.teardown();
      await workRuntime.shutdown();
      await stationLock.release();
    }

    final runFor = config.runFor;
    if (runFor != null) {
      await Future<void>.delayed(runFor);
      await shutdown();
      return 0;
    }

    // Park until the FIRST termination signal (SIGINT / SIGTERM — D-R2's
    // graceful path; a supervisor's `kill`/`launchctl stop` sends SIGTERM). The
    // subscriptions attach here and cancel after shutdown so the VM can exit.
    final interrupt = Completer<void>();
    final signals = <StreamSubscription<ProcessSignal>>[];
    for (final signal in const [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signals.add(
        signal.watch().listen((_) {
          if (!interrupt.isCompleted) interrupt.complete();
        }),
      );
    }
    await interrupt.future;
    out('\nspace up: shutting down…');
    await shutdown();
    for (final s in signals) {
      await s.cancel();
    }
    return 0;
  }

  /// space's `/status` view (RS-4): the counts read the work runtime's
  /// PRODUCER-side latest join (what the bridge last pushed — never the
  /// notifier's reactive state, D-H rule 2). `mounted` reports the live
  /// (non-terminal) session count — post-A40 a live session ⇔ a mounted work
  /// branch.
  StationStatus _status(
    SpaceStationConfig config,
    List<_ArmedSubstation> armed,
    DateTime startedAt,
    StationWorkRuntime workRuntime,
  ) {
    final latest = workRuntime.latest;
    final live = latest.sessionsByWorkBead.values
        .where((s) => !s.isTerminal)
        .length;
    final capturedAt = latest.graph.capturedAt;
    return StationStatus(
      substation: armed.map((s) => s.name).join(','),
      stateStore: config.gridHome,
      workRoot: armed.map((s) => '${s.name}=${s.root}').join(', '),
      dryRun: config.dryRun,
      pid: pid,
      startedAt: startedAt,
      version: Platform.version,
      ready: latest.graph.readyIds.length,
      mounted: live,
      liveSessions: live,
      lastSyncAt: capturedAt.millisecondsSinceEpoch == 0 ? null : capturedAt,
    );
  }

  void _out(String message) => stdout.writeln(message);
  void _err(String message) => stderr.writeln(message);
}

Uri _parseBase(String raw, String flag) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) {
    throw FormatException('$flag is not an absolute url: "$raw"');
  }
  return uri;
}
