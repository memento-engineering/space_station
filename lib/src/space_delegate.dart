/// `SpaceDelegate` — **space_station authored as a Seed** (Track G-space,
/// `the_grid/docs/GRID-SDK-BUILD-ORDER.md`; the v3 code-as-config model,
/// `the_grid/docs/SCRATCH-station-config-model.md` §2/§4).
///
/// This is the birth of the delegation seat for memento's station: `space`
/// stops being a hand-assembled bag of station-runner flags and BECOMES a
/// [sdk.GridDelegate] subclass whose master [build] authors the canonical §2
/// tree —
/// `RawAssetGrid → Station → HarnessProvider → Substations → Substation`, with
/// each substation's per-project git as a **substation-scoped asset**
/// ([GitGridAssets] / [GitHubGridAssets], Track F) rather than a runner-built
/// `ServiceBundle` map. The station's shape is authored in Dart, as a tree
/// (v3 §1: "the tree IS the configuration"); the verbs re-seat over it.
///
/// ## The transitional seam (honest scope, read this)
///
/// The v3 end-state is `up` driving the station by `runGrid(SpaceDelegate())`
/// — mounting THIS tree and letting the reactive loop drive. That last step
/// needs the composition tree bound to the engine's live driving (the
/// `StationKernel` / `WorkList` / lock / signal-park), which Track F itself
/// defers to "Track G's runner work" and which lives in `grid_sdk` /
/// `grid_engine` (the private engine, ADR-0008 D2). Until that bridge lands,
/// `space up` still DRIVES through `grid_cli`'s station-runner primitives
/// (`composeStation` / `driveStation`) — but now sourced from THIS delegate:
/// the delegate owns space's **asset seam** ([circuitResolver] / [codeRegistry]
/// / [wrapRoot] / [serviceBundleMapFor]) and space's **own CLI**
/// ([addSpaceStationFlags] / [spaceStationArgsFrom]). The hand-mirrored
/// `_addResidentStationFlags` / `_residentStationArgsFrom` (a by-hand byte-copy
/// of `grid_cli`'s `addStationFlags` / `StationArgs.from`, kept in lockstep
/// forever — absorbs tg-da7) are GONE: space owns its flag surface here.
///
/// The flags remain arg-COMPATIBLE with `grid_cli`'s `StationArgs` only because
/// `up` still feeds them into `grid_cli`'s primitives; they gain full
/// independence the day `up` drives through `runGrid(this)` (the [build] tree
/// below is already that tree — it is exercised offline by
/// `test/space_delegate_test.dart` and is ready for the day the engine bridge
/// exists).
library;

import 'package:args/args.dart';
import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentConfig,
        AgentHarnessRegistry,
        GitGridAssets,
        GitHubGridAssets,
        GitSourceControl,
        HarnessProvider,
        buildAgentHarnessRegistry,
        buildCodeRegistry,
        kCodeCircuit;
import 'package:grid_cli/grid_cli.dart'
    show RootSpec, RuntimeProviderKind, StationArgs;
import 'package:grid_engine/grid_engine.dart'
    show
        CapabilityRegistry,
        Circuit,
        CircuitResolver,
        ServiceBundle,
        SourceControl;
import 'package:grid_runtime/grid_runtime.dart'
    show GitOps, PrOpener, RootCheckout, StationGitService;
import 'package:grid_sdk/grid_sdk.dart' as sdk;

/// The bead→circuit policy for the `code` asset: every coding bead roots the
/// `code` circuit (the ONE circuit space's substations run). Space's own — the
/// asset owns the "use" (ADR-0011 D3).
Circuit _codeCircuit(Bead bead) => kCodeCircuit;

/// One authored project in space's station — a name and its ONE root (v3 §0: a
/// substation is a name and ONE root, never a set). The [build] tree fans these
/// out as `Substation`s; the primitive drive registers their roots.
class SpaceSubstation {
  /// A project named [name] rooted at [root] (an absolute [RootCheckout]).
  const SpaceSubstation({required this.name, required this.root});

  /// The project's name (its substation id / ownership token).
  final String name;

  /// The project's single root checkout (absolute path + branch/remote).
  final RootCheckout root;
}

/// The delegate seat memento's `space` verbs re-seat over — space_station
/// authored as a Seed.
///
/// Constructed from space's resolved station config (its [gridRoot] home, the
/// [substations] it drives, the station-default [agentConfig], and — when a
/// live run armed them — the git [provisioner] / [gitOps] / [prOpener]). The
/// master [build] authors the v3 §2 tree; the asset-seam members
/// ([circuitResolver] / [codeRegistry] / [wrapRoot]) are what `space up` feeds
/// into `grid_cli`'s `composeStation` until the runGrid driving bridge lands.
class SpaceDelegate extends sdk.GridDelegate {
  /// Creates the delegate over space's resolved station config. [harnesses]
  /// defaults to the first-party claude/copilot/pi/opencode set. [provisioner]
  /// / [gitOps] / [prOpener] are the live git machinery (all null ⇒ the
  /// offline / dry-run authoring, where provisioning + land no-op but the
  /// worktree layout still resolves — Track F).
  SpaceDelegate({
    required this.gridRoot,
    required this.stationName,
    required this.substations,
    required this.agentConfig,
    AgentHarnessRegistry? harnesses,
    this.provisioner,
    this.gitOps,
    this.prOpener,
  }) : harnesses = harnesses ?? buildAgentHarnessRegistry();

  /// The station's home (absolute): the `RawAssetGrid` root the [build] tree
  /// roots at; the grid's state store lives under `<gridRoot>/.grid/` (Q5a).
  final String gridRoot;

  /// The machine's name (the `Station` name — e.g. the host).
  final String stationName;

  /// The projects space drives, fanned out as `Substation`s.
  final List<SpaceSubstation> substations;

  /// The station-default agent scope (harness / model / target) — the ambient
  /// rung of the agent-config ladder (ADR-0008 D10).
  final AgentConfig agentConfig;

  /// The station's harness DI registry (which coding harnesses the machine can
  /// run).
  final AgentHarnessRegistry harnesses;

  /// The station's shared worktree-provisioning service (leased per
  /// substation); null ⇒ provisioning no-ops (offline / dry-run).
  final StationGitService? provisioner;

  /// Commit/push ops; null ⇒ land no-ops (the commit-only arm).
  final GitOps? gitOps;

  /// The PR-opening seam; null ⇒ no land added (the commit-only arm). Non-null
  /// mounts [GitHubGridAssets] under each substation (canLand true).
  final PrOpener? prOpener;

  /// The master build (v3 §2/§4): space's station as a tree —
  /// `RawAssetGrid(gridRoot) → Station(stationName) → HarnessProvider →
  /// Substations → Substation(Nest[GitGridAssets, GitHubGridAssets?])`.
  ///
  /// Each substation's git is a SUBSTATION-SCOPED asset (Track F: this is where
  /// `ServiceBundle` dissolves) resolved by tree position (bead → substation →
  /// root), never a string-keyed map. The harness registry + station-default
  /// [AgentConfig] mount STATION-scoped via [HarnessProvider], above the fan-out
  /// so every substation's work inherits them.
  ///
  /// Not yet driven at runtime (the runGrid → kernel bridge is the pending
  /// engine work); exercised offline by `test/space_delegate_test.dart`. Each
  /// substation's `Nest` child is [_WorkListMount] — the seat the engine's
  /// `WorkList` binds into once the bridge exists.
  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) {
    final opener = prOpener;
    return sdk.RawAssetGrid(
      root: gridRoot,
      assets: [
        sdk.Station(
          name: stationName,
          root: gridRoot,
          assets: [
            HarnessProvider(
              registry: harnesses,
              config: agentConfig,
              child: sdk.Substations(
                substations: [
                  for (final s in substations)
                    sdk.Substation(
                      name: s.name,
                      root: s.root.path,
                      assets: [
                        Nest(
                          children: [
                            GitGridAssets(
                              provisioner: provisioner,
                              gitOps: gitOps,
                              defaultBranch: s.root.defaultBranch,
                              remote: s.root.remote,
                            ),
                            if (opener != null) GitHubGridAssets(prOpener: opener),
                          ],
                          child: const _WorkListMount(),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── the asset seam `space up` feeds into grid_cli's composeStation ──────────
  // (until `up` drives through runGrid(this); ADR-0008 D1: resolver + registry
  // + services + wrapRoot are the asset's contribution, now OWNED here.)

  /// Space's bead→circuit policy for `composeStation(resolver:)` — every bead
  /// roots the `code` circuit.
  CircuitResolver get circuitResolver => const CircuitResolver(_codeCircuit);

  /// Space's capability registry for `composeStation(registry:)`, rooted at
  /// [devRoot] (the workRoot the code asset provisions against).
  CapabilityRegistry codeRegistry(String devRoot) =>
      buildCodeRegistry(devRoot: devRoot);

  /// Space's `composeStation(wrapRoot:)` hook: mounts the station-default
  /// [agentConfig] + [harnesses] as ancestors of the whole tree (D-C rung 1;
  /// the primitive-drive analogue of [HarnessProvider] in [build]).
  Seed Function(Seed root) get wrapRoot => (root) => InheritedSeed<AgentConfig>(
    value: agentConfig,
    child: InheritedSeed<AgentHarnessRegistry>(value: harnesses, child: root),
  );
}

/// The seat the engine's `WorkList` binds into once the runGrid → kernel bridge
/// exists — a terminal leaf today (the [SpaceDelegate.build] tree is authored
/// but not yet driven).
class _WorkListMount extends MultiChildSeed {
  const _WorkListMount() : super(children: const []);
}

// ─────────────────────────────────────────────────────────────────────────────
// space's OWN CLI surface — the seat the resident verbs re-seat over.
//
// These REPLACE `up_command.dart`'s `_addResidentStationFlags` /
// `_residentStationArgsFrom` (a by-hand byte-copy of `grid_cli`'s
// `addStationFlags` / `StationArgs.from` — the hand-mirror tg-da7 audited).
// They are SPACE'S OWN now: space designs its flag surface. They stay
// arg-compatible with `StationArgs` only while `up` drives through `grid_cli`'s
// primitives; that constraint lifts the day `up` drives through
// `runGrid(SpaceDelegate)`.
//
// A resident verb takes NO drive-list, EVER (D-R1/D-R4): the ready frontier of
// the owned substation IS the drive set, so there is no `--bead` on this
// parser — a trigger surface a misbehaving agent or a confused human could pull.
// ─────────────────────────────────────────────────────────────────────────────

/// Adds space's resident-station flags to [parser] (the station surface MINUS
/// `--bead`). Space's own design; there is deliberately no `--bead`.
void addSpaceStationFlags(ArgParser parser) {
  parser
    ..addMultiOption(
      'substation',
      abbr: 'r',
      help:
          'An OWNED substation / ownership token (repeatable) — the SINGLE '
          'allow-set feeding both the ownership gate and the dispatch '
          'predicate. The dogfood substation is `tgdog`.',
    )
    ..addMultiOption(
      'owner',
      help: 'Alias for --substation; merged into one shared allow-set.',
    )
    ..addOption(
      'provider',
      allowed: ['subprocess', 'tmux'],
      defaultsTo: 'subprocess',
      help: 'The runtime provider for agent spawns.',
    )
    ..addMultiOption(
      'root',
      help:
          'A registered worktree root checkout (repeatable): '
          '`--root <name>=<path>[@head]` registers <path> under <name> — a '
          'name equal to an owned --substation becomes that substation\'s '
          'root; any OTHER name is a project a bead opts into via its '
          'substation. Bare `--root <path>` (no `=`) is the single-root '
          'shorthand: registers under the first --substation. At least one is '
          'required to ARM a non-dry run; never created by the runner.',
    )
    ..addOption(
      'head',
      help:
          'ASSIGN the base branch per-bead worktrees cut from, overriding the '
          'probed origin/HEAD. Omit to probe.',
    )
    ..addOption(
      'workspace',
      abbr: 'w',
      help:
          'The beads workspace to read ready work from (a dir at or above a '
          '`.beads/`). Defaults to discovery from the cwd; read-only under '
          '--dry-run.',
    )
    ..addOption(
      'state-workspace',
      help:
          'A SEPARATE the_grid-owned beads workspace for its own session/'
          'lifecycle beads (A36/A37), so the --workspace source stays '
          'read-only. Omit to write sessions into --workspace.',
    )
    ..addOption(
      'state-substation',
      defaultsTo: 'tgdog',
      help:
          "the_grid's OWNED session partition (the --state-workspace prefix), "
          'unioned into the allow-set. Only used with --state-workspace.',
    )
    ..addFlag(
      'dry-run',
      defaultsTo: true,
      help:
          'Observe-only: NO writes, NO spawns (the SAFE DEFAULT). Pass '
          '--no-dry-run to ARM the live writing arm (requires --root).',
    )
    ..addFlag(
      'land',
      defaultsTo: false,
      negatable: false,
      help:
          'ARM the land step (ADR-0006 D3): on step-complete, commit → push → '
          'open a PR (never auto-merges). OPT-IN, OFF by default; requires '
          '--no-dry-run.',
    )
    ..addOption(
      'for-seconds',
      help: 'Run for a fixed number of seconds then exit (scripted / CI).',
    )
    ..addFlag(
      'no-sql',
      negatable: false,
      help:
          'Force the bd-CLI read path even when pooled Dolt SQL is available.',
    )
    ..addOption(
      'control-port',
      defaultsTo: '0',
      help: 'The StationControl loopback port (RS-4). 0 = ephemeral (default).',
    );
}

/// Builds [StationArgs] from space's own flags ([addSpaceStationFlags]) —
/// [StationArgs.resident] is ALWAYS true and [StationArgs.targetBeads] is
/// ALWAYS empty (no `--bead` on this parser). Parses `--root <name>=<path>[@head]`
/// into [StationArgs.roots]; a duplicate root name is a loud [FormatException]
/// (a config defect the operator sees immediately, never a silent overwrite).
StationArgs spaceStationArgsFrom(ArgResults args) {
  final seconds = args.option('for-seconds');
  final substations = <String>{
    ...args.multiOption('substation'),
    ...args.multiOption('owner'),
  }..removeWhere((r) => r.trim().isEmpty);
  final roots = <String, RootSpec>{};
  for (final raw in args.multiOption('root')) {
    if (raw.trim().isEmpty) continue;
    final entry = RootSpec.parse(
      raw,
      defaultName: substations.isNotEmpty ? substations.first : '',
    );
    if (roots.containsKey(entry.key)) {
      throw FormatException(
        'space up: --root "$raw" registers name "${entry.key}" more than once',
      );
    }
    roots[entry.key] = entry.value;
  }
  return StationArgs(
    substations: substations,
    provider: RuntimeProviderKind.parse(args.option('provider')),
    roots: roots,
    head: args.option('head'),
    workspacePath: args.option('workspace'),
    stateWorkspacePath: args.option('state-workspace'),
    stateSubstation: args.option('state-workspace') == null
        ? null
        : args.option('state-substation'),
    dryRun: args.flag('dry-run'),
    land: args.flag('land'),
    noSql: args.flag('no-sql'),
    runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
    resident: true,
    controlPort: int.parse(args.option('control-port')!),
  );
}

/// Builds `composeStation`'s `services` map for the ONE substation `space up`
/// composes: [defaultSubstation]'s entry carries a [GitSourceControl] over
/// [workRoot] as its DEFAULT `sourceControl`, plus one EXTRA [GitSourceControl]
/// per OTHER [roots] entry under `sourceControlsByRoot`. [gitOps] / [prOpener]
/// ride every constructed [GitSourceControl] (non-null only when `--land` armed
/// a live run; null ⇒ canLand false ⇒ commit-only). Pure construction, no I/O.
///
/// Space's own (previously `up_command.dart`'s `serviceBundleMapFor`) — the
/// primitive-drive equivalent of [SpaceDelegate.build]'s per-substation
/// [GitGridAssets], kept until `up` drives through `runGrid`.
Map<String, ServiceBundle> serviceBundleMapFor({
  required String defaultSubstation,
  required RootCheckout workRoot,
  required Map<String, RootCheckout> roots,
  required StationGitService provisioner,
  GitOps? gitOps,
  PrOpener? prOpener,
}) {
  final sourceControlsByRoot = <String, SourceControl>{
    for (final entry in roots.entries)
      if (entry.key != defaultSubstation)
        entry.key: GitSourceControl(
          gitOps: gitOps,
          prOpener: prOpener,
          provisioner: provisioner,
          root: entry.value,
        ),
  };
  return {
    defaultSubstation: ServiceBundle(
      sourceControl: GitSourceControl(
        gitOps: gitOps,
        prOpener: prOpener,
        provisioner: provisioner,
        root: workRoot,
      ),
      sourceControlsByRoot: sourceControlsByRoot,
    ),
  };
}
