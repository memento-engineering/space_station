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
    show AgentConfig, AgentRole, EnvironmentRegistry, resolveAgentConfig;
// RS-2/RS-4 SURVIVORS (station_lock.dart / station_control.dart) — NOT the
// station-runner kill-list. `up` orchestrates them itself now that the
// `driveStation` boot path is gone (DoD#6).
import 'package:grid_cli/grid_cli.dart' show StationDiagnosticsReporter;
// ignore: implementation_imports
import 'package:grid_cli/src/station_control.dart'
    show StationControl, StationStatus, mintControlToken;
// ignore: implementation_imports
import 'package:grid_cli/src/station_lock.dart'
    show StationLockHandle, StationLockService;
import 'package:grid_assets/grid_assets.dart'
    show CodeCircuitResolver, kCodeCircuit;
// The RUN-MODE probe: this process's own VM-service URI (JIT) or null (AOT) —
// the WHOLE dev-mode gate.
import 'package:grid_exploration/grid_exploration.dart'
    show stationVmServiceUri;
import 'package:github_grid_assets/github_grid_assets.dart' as github;
import 'package:grid_sdk/grid_sdk.dart'
    show
        GridHandle,
        GridStateStore,
        StationWorkRuntime,
        StoreLocator,
        StoreRefusal,
        SubstationWorkSpec,
        assembleStationWork,
        runGrid;
import 'package:path/path.dart' as p;

import 'agent_arming.dart';
import 'dev_mode.dart';
import 'space_delegate.dart';

/// Runs the `gh` login probe used to construct station-global GitHub trust.
typedef GitHubLoginProcess =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Resolves station-global SELF trust from the authenticated `gh` CLI login.
///
/// When [githubPollingConfigured] is false no process is started. A missing
/// executable, non-zero exit, blank stdout, or timeout is the absent-trust
/// posture; timeout is reported through [writeDiagnostic], and login case is
/// preserved for GitHubSelfTrust's exact comparison.
Future<github.GitHubSelfTrust?> resolveGitHubSelfTrustFromGh({
  required String workingDirectory,
  required bool githubPollingConfigured,
  required void Function(String message) writeDiagnostic,
  Duration timeout = const Duration(seconds: 5),
  GitHubLoginProcess run = Process.run,
}) async {
  if (!githubPollingConfigured) return null;

  final timeoutSignal = Completer<ProcessResult?>();
  final timer = Timer(timeout, () => timeoutSignal.complete());
  try {
    Future<ProcessResult?> invokeGh() async {
      return await run('gh', const [
        'api',
        'user',
        '-q',
        '.login',
      ], workingDirectory: workingDirectory);
    }

    final result = await Future.any<ProcessResult?>([
      invokeGh(),
      timeoutSignal.future,
    ]);
    if (result == null) {
      writeDiagnostic(
        'space up: gh api user login probe timed out after '
        '${timeout.inMilliseconds}ms; continuing without GitHub self trust — '
        'polling intake remains inert.',
      );
      return null;
    }
    if (result.exitCode != 0) return null;
    final githubUser = '${result.stdout}'.trim();
    if (githubUser.isEmpty) return null;
    return github.GitHubSelfTrust(githubUser: githubUser);
  } on ProcessException {
    return null;
  } finally {
    timer.cancel();
  }
}

/// One substation `up` armed — a name, its resolved ABSOLUTE root, and its
/// work store's issue-id prefix. The off-tree work machinery (the store
/// guard, `buildStationWork`'s specs, the `/status` view) runs BEFORE the
/// tree mounts (the pinned ordering, ADR-0007 §4), so it carries the roster
/// as plain values — read off an OFFLINE MOUNT of the same delegate class
/// the armed tree builds (space-6ds, evolved), so they cannot diverge.
typedef _ArmedSubstation = ({String name, String root, String prefix});

/// `space up`: boots the resident station.
class UpCommand extends Command<int> {
  /// Creates the up command (space's own station flags MINUS `--bead`, plus
  /// the agent scope's). [delegateFactory] is the ONE downstream seam: which
  /// [SpaceDelegate] subclass authors this station (its identity, roster and
  /// seat stacks live on the CLASS as override points). The coded roster is
  /// read by MOUNTING the delegate's tree offline (`mountedValuesOf` through
  /// [codedRosterSnapshotOf] — the same enumeration `search` uses) for the
  /// help text, the refusal set, and the store guard — the tree stays the
  /// single source.
  UpCommand({SpaceDelegateFactory delegateFactory = SpaceDelegate.new})
    : _delegateFactory = delegateFactory {
    addSpaceStationFlags(
      argParser,
      // One owned enumeration (constructed, mounted, DISPOSED — a delegate
      // is a StateNotifier, never a throwaway value) at a placeholder home:
      // seat NAMES are grid-home-independent, and only names render into the
      // help. The real mounts (guard + tree) happen in [run].
      codedNames: [for (final s in codedRosterOf(delegateFactory)) s.name],
    );
    // The allowed set of --env is the ARMED REGISTRY, read from the delegate
    // CLASS (the codedRosterOf precedent above: construct -> read -> dispose)
    // — never an argparse literal. A hardcoded allowlist is the exact bug
    // ADR-0002 D4 deletes: it blocked `codex` at the operator surface while
    // the registry had it armed. It renders into the HELP here; the LOUD
    // legality check runs in [run] against the boot registry.
    final armedEnvironments = codedArmingOf(
      delegateFactory,
    ).environments.names.join(', ');
    argParser
      ..addOption(
        'env',
        help:
            'The station-default NAMED environment — the AMBIENT rung of the '
            'agent-config ladder (ADR-0002 D1): a bead overrides it via its '
            'grid.agent envelope, a step via params, and the per-role posture '
            'is CODED on the delegate (SpaceDelegate.arming), never a flag '
            '(D4). Selected from the ARMED registry, resolved at run time — '
            'armed here: $armedEnvironments. Absent: the station default '
            '(claude).',
      )
      ..addOption(
        'max-agents',
        defaultsTo: '4',
        help:
            'The station-wide concurrency ceiling (tg-42f): the most work '
            'beads mounted (agents live) at once across every substation.',
      );
  }

  final SpaceDelegateFactory _delegateFactory;

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
      'to --dry-run (armed over INERT seams — no spawn, no write, no delivery '
      'bound); a LIVE arm (--no-dry-run) also BINDS each coded substation\'s '
      'GitHub delivery — it pushes and opens PRs — and stays the human gate.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final out = _out;
    final err = _err;

    // --- the station-default agent scope (D-C rung 1) + boot-eager
    // validation (OQ-c moment 1: a misconfigured MACHINE fails loud before
    // any tree mounts; a misconfigured BEAD fails per-work at resolution).
    //
    // ONE knob (ADR-0002 D4). WHERE inference runs is the named environment's
    // own `target` (D1) and its endpoint is the machine-local site binding's
    // (D3) — never argv, so this line is byte-identical on every box. WHICH
    // model each role rides is the environment's too (D2: arming in committed
    // Dart), and the per-role posture is the delegate's coded `arming`, never
    // an operator override.
    //
    // Absent, the ambient rung stays the pack default ('claude'); the CODED
    // per-role arming still underlays it below.
    final env = results.option('env');
    final flagConfig = env == null
        ? const AgentConfig()
        : AgentConfig(harness: env);
    // The station's posture is CODED on the delegate CLASS, never in an
    // argparse default: `underlay` fills only the role rungs the operator left
    // unarmed, and the delegate's own registry supplies the named environments
    // those rungs resolve against.
    final codedArming = codedArmingOf(_delegateFactory);
    final agentConfig = codedArming.arming.underlay(flagConfig);
    final EnvironmentRegistry harnesses = codedArming.environments;
    // Boot-eager (OQ-c moment 1): the STATION-DEFAULT environment must name an
    // armed, self-consistent environment — a misconfigured MACHINE fails loud
    // before any tree mounts (a misconfigured BEAD fails per-work at
    // resolution). We validate the default environment ALONE, not the whole
    // builtin set: `pi` carries an openAiCompatible target whose endpoint is a
    // site-binding machine-fact (ADR-0002 D3), and the site-binding mount is
    // not wired yet (bead pow-ebf.6/pow-2eg) — a whole-registry validate would
    // refuse every `up` on pi's unbound endpoint. The default (claude) is
    // providerManaged and needs no endpoint.
    if (!harnesses.names.contains(agentConfig.harness)) {
      // Naming --env is exact: the only other source of this value is the
      // pack default 'claude', which is a builtin and so always armed.
      err(
        'space up: --env "${agentConfig.harness}" names no armed environment '
        '(armed: ${harnesses.names.join(', ')}).',
      );
      return 64;
    }
    final selfCheck = harnesses.resolve(agentConfig.harness).validate();
    if (selfCheck != null) {
      err(
        'space up: environment "${agentConfig.harness}" is misconfigured: '
        '$selfCheck',
      );
      return 64;
    }
    // Boot-eager, over EVERY armed role rung — the coded posture's included, so
    // a delegate that arms a role at an unarmed environment fails LOUD here
    // rather than per-spawn.
    final roleRefusal = roleArmingRefusal(agentConfig, harnesses);
    if (roleRefusal != null) {
      err('space up: $roleRefusal (armed: ${harnesses.names.join(', ')}).');
      return 64;
    }

    // --- space's OWN resident-station config (v3 stores-at-roots). The coded
    // roster is authored in the delegate's substations() (space-6ds); flags
    // only APPEND new substations, so only a missing --grid-home is a LOUD
    // arming refusal (never a `''` sentinel — v3 kills those). A malformed,
    // duplicate, or coded-name --substation is an uncaught FormatException (a
    // config defect the operator sees immediately).
    // The coded roster, read off the REAL tree: one owned offline authoring
    // mount at the real grid home ([codedRosterSnapshotOf] — no wiring, no
    // effects, enumeration delegate disposed). Scopes arrive with their roots
    // RESOLVED by the SDK itself (relative against the ambient GridRoot,
    // absolute as-is), so the off-tree machinery and the armed tree agree by
    // construction — the hand-kept mirror this replaced could diverge (a
    // prefix divergence silently un-owned every `space-` bead).
    // A missing or RELATIVE home falls back to the placeholder mount: only
    // seat NAMES are read before the home guards below refuse (exit 64), and
    // names are home-independent. The resolved ROOTS are only consumed after
    // those guards pass — i.e. always from a real absolute home.
    final homeFlag =
        (results.option('grid-home') ?? results.option('state-workspace'))
            ?.trim();
    final codedRoster = codedRosterSnapshotOf(
      _delegateFactory,
      gridRoot:
          (homeFlag == null || homeFlag.isEmpty || !p.isAbsolute(homeFlag))
          ? '/'
          : homeFlag,
    );
    final codedScopes = codedRoster.scopes;
    final config = spaceStationConfigFrom(
      results,
      codedNames: {for (final s in codedScopes) s.name},
    );
    if (config == null) {
      err(
        'space up: --grid-home (the state store / RS-2 lock home) is required '
        'to ARM — v3 §0: there is no default grid home.',
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
    // The coded roster, restated as OFF-TREE specs: the work machinery (the
    // controllers `buildStationWork` builds, this guard, the /status view)
    // runs BEFORE the armed tree mounts, so it reads the OFFLINE mount above
    // ([codedScopes]) — roots already resolved by the SDK's own seat build,
    // byte-identical with what the armed tree will resolve.
    final coded = <_ArmedSubstation>[
      for (final s in codedScopes)
        (name: s.name, root: s.root, prefix: s.prefix),
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
    final githubPollingArmed = armed.any(
      (seat) => codedRoster.githubPollingSeatNames.contains(seat.name),
    );

    // --- RS-2 the station lock (D-A1): ONE supervisor per station state store.
    // Acquired before anything stateful; a LIVE holder is a LOUD refusal (exit
    // 64). Caught generically so `up` never imports the kill-list refusal type.
    final bootTime = DateTime.now();
    final StationLockHandle stationLock;
    try {
      stationLock = await StationLockService(
        log: out,
      ).acquire(stateWorkspaceDir: config.gridHome, pid: pid, now: bootTime);
    } on Object catch (e) {
      err('$e');
      return 64;
    }

    // --- the off-tree work machinery (Track J, the runGrid→engine bridge):
    // controllers over the REAL stores at their roots, the join bridge, the
    // bd chokepoint (a recording no-op under --dry-run), the restart
    // reconciler. The code circuit + its capabilities are the grid_assets
    // OPINION, injected here (the engine stays opinion-free).
    //
    // The resolver is the MIGRATION-AWARE one: it roots the frozen circuit
    // SHAPE each session was MINTED under, so a pre-fold session surviving a
    // station BOUNCE never re-enters the spec phase and spawns a spurious
    // architect over a bead already mid-review. `kCodeCircuit` arrives as a
    // constructor VALUE, not a hard import of it (config = VALUES in the tree,
    // impls = DI). RETIREMENT is named in grid_assets' `circuit_migration.dart`:
    // once no OPEN session carries a pre-fold cursor, this reverts to the plain
    // shape-agnostic resolver and that file is deleted. This is scaffolding
    // with an expiry, not a permanent seam.
    final live = !config.dryRun;
    final githubSelfTrust = live
        ? await resolveGitHubSelfTrustFromGh(
            workingDirectory: config.gridHome,
            githubPollingConfigured: githubPollingArmed,
            writeDiagnostic: err,
          )
        : null;
    // ASSEMBLY-ONLY and deliberately DRY (live omitted ⇒ false): this
    // delegate exists for its policy hooks (circuitOverrideFor /
    // buildWorkRegistry) and its build never runs — but if it were ever
    // mounted for an enumeration (the codedRosterSnapshotOf pattern), a
    // live-postured instance would author the GitOps/PrOpener effect providers
    // into an offline tree, the exact boot-leak class space-47t removed. The
    // armed tree's delegate (buildDelegate below) is the ONE that carries
    // `live`.
    final workPolicyDelegate = _delegateFactory(
      gridRoot: config.gridHome,
      appended: config.appended,
      agentConfig: agentConfig,
      harnesses: harnesses,
    );
    // ONE diagnostics reporter across all three rails (the ratified reporter,
    // now armed in space's own composition): engine flares emit as JSON lines
    // on stderr, and the SAME projector feeds every completed flush to the
    // authenticated /stream route. Constructed before the work assembly so
    // the flare sink exists from the first store read.
    final diagnostics = StationDiagnosticsReporter(writeLine: stderr.writeln);
    final StationWorkRuntime workRuntime;
    try {
      workRuntime = await assembleStationWork(
        stateStore: GridStateStore.forGridRoot(config.gridHome),
        substations: [
          for (final s in armed)
            SubstationWorkSpec(name: s.name, root: s.root, prefix: s.prefix),
        ],
        resolver: CodeCircuitResolver(
          kCodeCircuit,
          overrideFor: workPolicyDelegate.circuitOverrideFor,
        ),
        registryBuilder: (appendNote) =>
            workPolicyDelegate.buildWorkRegistry(appendNote),
        dryRun: config.dryRun,
        maxConcurrentWork: maxAgents,
        transport: diagnostics,
      );
    } on Object catch (e) {
      diagnostics.dispose();
      workPolicyDelegate.dispose();
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
      workPolicyDelegate.dispose();
      await stationLock.release();
      err('space up: $e');
      return 1;
    }

    // --- space_station AS A SEED: author the delegate, ARMED with the work
    // wiring. The coded org is hardcoded in its build; only the operator's
    // appended seats ride in.
    //
    // DELIVERY IS A BINDING, NOT AN ARM (the_grid ADR-0000 A51). A substation
    // BINDS a `DeliveryMethod` on its `ServiceBundle`, and binding NONE is the
    // commit-only posture — a real posture, not an unarmed one. space's coded
    // seats compose github_grid_assets' `GitHubGridAssets`, which binds
    // a `GitHubPrDelivery` iff it OBSERVES both halves (commit/push `GitOps` +
    // a `PrOpener`) from the tree. ADR-0006 D3 is preserved: the bound method
    // pushes and opens a PR from the per-bead branch, and nothing auto-merges.
    //
    // The runner's only say is the DRY/LIVE posture VALUE it already owns
    // (space-47t: no effect instance passes through boot — space-00g
    // subsumed). A LIVE arm has the delegate author the effect providers
    // IN-TREE; `--dry-run` authors NEITHER — no `git`, no `gh` — so the tree
    // binds no delivery and the dry run stays inert by provider ABSENCE.
    // The RUN MODE is the WHOLE dev-mode gate: a JIT station launched with
    // `--enable-vm-service` reports a VM service; an AOT binary reports none.
    // No hostname allowlist, no env var, no flag, no config — and no filesystem
    // watcher: `space reload` is the EXPLICIT trigger.
    final vmServiceUri = await stationVmServiceUri();

    // Authored through a FACTORY so a hot-RESTART can re-run it on a fresh
    // delegate. `runGrid`'s own contract: a JIT station passes a factory, an AOT
    // station omits it and `hotRestart` then refuses LOUD — so the factory is
    // armed on the SAME gate, and nothing else.
    SpaceDelegate buildDelegate() => _delegateFactory(
      gridRoot: config.gridHome,
      appended: config.appended,
      agentConfig: agentConfig,
      harnesses: harnesses,
      wiring: workRuntime.wiring,
      provisioner: workRuntime.git,
      githubSelfTrust: githubSelfTrust,
      live: live,
    );

    // --- mount the tree: runGrid over the SpaceDelegate. The armed WorkLists
    // see the bridge's baseline and reconcile the ready frontier (mount =
    // spawn — inert under --dry-run). A mount-time refusal unwinds everything.
    final GridHandle grid;
    try {
      grid = await runGrid(
        buildDelegate(),
        onFlushed: workRuntime.afterFlush,
        treeProjector: diagnostics.treeProjector,
        delegateFactory: vmServiceUri == null ? null : buildDelegate,
      );
    } on Object catch (e) {
      await workRuntime.shutdown();
      workPolicyDelegate.dispose();
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
        treeProjector: diagnostics.treeProjector,
        // The fenced POST /command route (ADR-0014 D-C4, the_grid #106):
        // operator commands execute IN this resident via the work runtime's
        // vended handler (#104 seam).
        commandHandler: workRuntime.commands,
      );
    } on Object catch (e) {
      await grid.teardown();
      await workRuntime.shutdown();
      workPolicyDelegate.dispose();
      await stationLock.release();
      err('space up: $e');
      return 1;
    }
    await stationLock.updateControl(controlUrl: control.url, token: token);

    // --- the DEV-MODE host, JIT only: the exploration host — the SOLE registrar
    // — carrying the OPTIONAL ReassembleTool, so `ext.exploration.grid.reload`
    // exists and `space reload` re-composes THIS running station (no second
    // process). The lock then advertises the VM-service URI so the client can
    // find it; the lock is 0600 because that URI carries the service auth code.
    // No VM service ⇒ no host, no tool, no advertisement, and `space reload`
    // refuses LOUD.
    final DevModeHost? devMode;
    try {
      devMode = await armDevMode(
        vmServiceUri: vmServiceUri,
        grid: grid,
        latest: () => workRuntime.latest.graph,
        readPath: () => workRuntime.readPathName,
      );
    } on Object catch (e) {
      await control.dispose();
      await grid.teardown();
      await workRuntime.shutdown();
      workPolicyDelegate.dispose();
      await stationLock.release();
      err('space up: $e');
      return 1;
    }
    if (devMode != null) {
      devMode.register();
      await stationLock.updateVmService(devMode.vmServiceUri);
    }

    out('space up — space_station as a Seed (runGrid)');
    out(
      'mode: ${config.dryRun ? 'DRY-RUN (observe-only)' : 'LIVE'}  ·  '
      'substations: {${armed.map((s) => s.name).join(', ')}}  '
      '·  work-driving: ARMED (${config.dryRun ? 'inert seams' : 'live'})  '
      '·  delivery: ${live ? 'BOUND (GitHub PR)' : 'none (commit-only)'}',
    );
    // Report each role's EFFECTIVE model through the SAME resolver the spawners
    // use, so environment-native pins and the fallback ladder cannot drift.
    final buildModel = resolveAgentConfig(
      role: AgentRole.build,
      ambient: agentConfig,
      beadMetadata: const <String, dynamic>{},
      stepParams: const <String, String>{},
      registry: harnesses,
    ).params['model']!;
    final gradeModel = resolveAgentConfig(
      role: AgentRole.grade,
      ambient: agentConfig,
      beadMetadata: const <String, dynamic>{},
      stepParams: const <String, String>{},
      registry: harnesses,
    ).params['model']!;
    out(
      'agent scope: environment ${agentConfig.harness} '
      '(${harnesses.resolve(agentConfig.harness).target})'
      '  ·  build model $buildModel  ·  grader model $gradeModel',
    );
    out(
      'stores: read-path {${workRuntime.readPathName}}  ·  state partition: '
      '${workRuntime.stateSubstation}',
    );
    out('control: ${control.url}  ·  token: (see ${stationLock.path}, 0600)');
    out(
      devMode == null
          ? 'dev mode: OFF (no VM service) — `space reload` is unavailable; arm '
                'it JIT: `dart run --enable-vm-service space:space up …`'
          : 'dev mode: JIT — VM service ${devMode.vmServiceUri}  ·  '
                '`space reload` ARMED (ext.exploration.grid.reload registered)',
    );

    // Dispose the control surface BEFORE releasing the lock (RS-4 scope fence —
    // a released lock naming a dead endpoint would mislead `space status`),
    // then tear the tree down (unmount → effects kill), THEN the off-tree
    // machinery (the bridge outlives the tree, never the reverse), then
    // release LAST.
    Future<void> shutdown() async {
      // The dev-mode host stops answering the wire FIRST — it re-composes the
      // tree, so it must not outlive it.
      await devMode?.dispose();
      await control.dispose();
      await grid.teardown();
      // Sockets and the mounted tree are down — NOW the shared projection
      // stream can close (the reporter owns the projector's lifecycle).
      diagnostics.dispose();
      await workRuntime.shutdown();
      workPolicyDelegate.dispose();
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
      sync: <String, Object?>{
        'stats': <String, Object?>{
          for (final e in workRuntime.syncStats.entries)
            e.key: <String, Object?>{
              'signalCounts': <String, Object?>{
                for (final c in e.value.signalCounts.entries)
                  c.key.name: c.value,
              },
              'refreshCount': e.value.refreshCount,
              'lastRefreshMs': e.value.lastRefresh?.inMilliseconds,
              'lastReactionMs': e.value.lastReaction?.inMilliseconds,
              'refreshing': e.value.refreshing,
              'pendingFollowUp': e.value.pendingFollowUp,
            },
        },
        'freshness': <String, Object?>{
          for (final e in workRuntime.workFreshness.entries)
            e.key: <String, Object?>{
              'capturedAt': e.value.capturedAt?.toIso8601String(),
              'stale': e.value.stale,
            },
        },
      },
    );
  }

  void _out(String message) => stdout.writeln(message);
  void _err(String message) => stderr.writeln(message);
}
