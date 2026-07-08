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
/// **The live work-driving arm is HELD for the human gate (Track J).** The
/// engine's `WorkList`/kernel binding into this tree is the pending
/// `runGrid`→kernel bridge; until it lands, `up` mounts the tree and guards the
/// store, but spawns NO work — the control surface reports zero counts. `up`
/// stays foreground-resident: no self-daemonization, no double-fork — the
/// supervisor (launchd, RS-6) owns backgrounding.
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
import 'package:grid_runtime/grid_runtime.dart' show SystemProcessGroupController;
import 'package:grid_sdk/grid_sdk.dart'
    show GridHandle, GridStateStore, StoreLocator, StoreRefusal, runGrid;

import 'space_delegate.dart';

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
      'to --dry-run (observe-only); the LIVE work-driving arm is held for the '
      'human gate (Track J).';

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
    final model = results.option('model');
    final agentConfig = AgentConfig(
      harness: results.option('harness') ?? 'claude',
      target: target,
      params: {if (model != null) 'model': model},
    );
    final harnesses = buildAgentHarnessRegistry();
    final invalid = harnesses.validate(agentConfig);
    if (invalid != null) {
      err('space up: $invalid');
      return 64;
    }

    // --- space's OWN resident-station config (v3 stores-at-roots). A missing
    // --grid-home or an empty substation set is a LOUD arming refusal (never a
    // `''` sentinel — v3 kills those); a malformed/duplicate --substation is an
    // uncaught FormatException (a config defect the operator sees immediately).
    final config = spaceStationConfigFrom(results);
    if (config == null) {
      err(
        'space up: --grid-home (the state store / RS-2 lock home) AND at least '
        'one --substation <name>=<root> are required to ARM — v3 §0: there is '
        'no default root and no default substation.',
      );
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
    // Each substation's `.beads/` work store is looked for at its EXACT root,
    // no walk-up (grid_sdk StoreLocator). Absent ⇒ a LOUD boot refusal.
    final locator = StoreLocator();
    for (final s in config.substations) {
      try {
        locator.locateWorkStore(root: s.root.path, substationName: s.name);
      } on ArgumentError catch (e) {
        err('space up: ${e.message}');
        return 64;
      } on StoreRefusal catch (e) {
        err('space up: ${e.message}');
        return 1;
      }
    }

    // --- space_station AS A SEED: author the delegate. H2 is offline authoring
    // — the live git machinery (provisioner / gitOps / prOpener) is held for
    // the human gate (Track J); all null ⇒ the dry authoring the tree still
    // mounts over (Track F).
    final delegate = SpaceDelegate(
      gridRoot: config.gridHome,
      stationName: 'space',
      substations: config.substations,
      agentConfig: agentConfig,
      harnesses: harnesses,
    );

    // --- RS-2 the station lock (D-A1): ONE supervisor per station state store.
    // Acquired before the tree mounts; a LIVE holder is a LOUD refusal (exit
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

    // --- mount the tree: runGrid over the SpaceDelegate (the C/D-era pieces).
    // A mount-time refusal (a malformed composition) unwinds the lock.
    final GridHandle grid;
    try {
      grid = runGrid(delegate);
    } on Object catch (e) {
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
        view: () => _status(config, bootTime),
      );
    } on Object catch (e) {
      grid.teardown();
      await stationLock.release();
      err('space up: $e');
      return 1;
    }
    await stationLock.updateControl(controlUrl: control.url, token: token);

    out('space up — space_station as a Seed (runGrid)');
    out(
      'mode: ${config.dryRun ? 'DRY-RUN (observe-only)' : 'LIVE'}  ·  '
      'substations: {${config.substations.map((s) => s.name).join(', ')}}  ·  '
      'work-driving: HELD (the runGrid→kernel bridge is the human gate, '
      'Track J)',
    );
    out(
      'agent scope: harness ${agentConfig.harness} → ${agentConfig.target}'
      '${model != null ? '  ·  model $model' : ''}',
    );
    out('control: ${control.url}  ·  token: (see ${stationLock.path}, 0600)');

    // Dispose the control surface BEFORE releasing the lock (RS-4 scope fence —
    // a released lock naming a dead endpoint would mislead `space status`),
    // then tear the tree down, then release LAST.
    Future<void> shutdown() async {
      await control.dispose();
      grid.teardown();
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

  /// space's `/status` view (RS-4) — built directly (not `grid_cli`'s
  /// `buildStationStatus`, which reads a live kernel's join bridge). H2 drives
  /// no work: `ready`/`mounted`/`liveSessions` are 0 and there is no work
  /// snapshot yet — they light up when the runGrid→kernel bridge lands.
  StationStatus _status(SpaceStationConfig config, DateTime startedAt) =>
      StationStatus(
        substation: config.substations.map((s) => s.name).join(','),
        stateStore: config.gridHome,
        workRoot: config.substations
            .map((s) => '${s.name}=${s.root.path}')
            .join(', '),
        dryRun: config.dryRun,
        pid: pid,
        startedAt: startedAt,
        version: Platform.version,
        ready: 0,
        mounted: 0,
        liveSessions: 0,
        lastSyncAt: null,
      );

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
