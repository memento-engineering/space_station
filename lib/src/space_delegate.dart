/// `SpaceDelegate` — **space_station authored as a Seed** (Track G-space,
/// `the_grid/docs/GRID-SDK-BUILD-ORDER.md`; the v3 code-as-config model,
/// `the_grid/docs/SCRATCH-station-config-model.md` §2/§4).
///
/// `space` is a [sdk.GridDelegate] subclass whose master [build] authors the
/// canonical §2 tree —
/// `RawAssetGrid → Station → HarnessProvider → Substations → Substation`, with
/// each substation's per-project git a **substation-scoped asset**
/// ([GitGridAssets] / [GitHubGridAssets], Track F) rather than a runner-built
/// `ServiceBundle` map. The station's shape is authored in Dart, as a tree
/// (v3 §1: "the tree IS the configuration"); the verbs re-seat over it.
///
/// ## H2 — the old boot path is GONE (tg-r81, DoD#6)
///
/// tg-33n made `space` a delegate but the delegate WRAPPED `grid_cli`'s
/// station-runner primitives (`RootSpec` / `StationArgs` / `serviceBundleMapFor`
/// / `ServiceBundle` / the circuit-resolver + capability-registry asset seam) —
/// it drove them, it did not replace them. H2 cuts that wrapper: nothing here
/// imports the kill-list surface anymore. `space up` now drives the **C/D-era
/// pieces** — `runGrid(SpaceDelegate())` over composition Seeds + stores at
/// roots (`grid_sdk`) — and the per-substation git is authored as an asset in
/// [build], never a `ServiceBundle` map fed to `composeStation`. The asset-seam
/// members (`circuitResolver` / `codeRegistry` / `wrapRoot`) and
/// `serviceBundleMapFor` are DELETED with the old boot path they served.
///
/// The live work-driving (the engine's `WorkList` / kernel binding into this
/// tree) is the pending `runGrid`→kernel bridge — held for the human gate
/// (Track J). H2 is offline authoring: this tree mounts over resolved stores
/// (exercised by `test/space_delegate_test.dart`); `space up` guards the state
/// store (RS-2) and binds the read-only control surface (RS-4) around it, but
/// spawns no work. The first LIVE arm stays the human gate.
library;

import 'package:args/args.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentConfig,
        AgentHarnessRegistry,
        GitGridAssets,
        GitHubGridAssets,
        HarnessProvider,
        buildAgentHarnessRegistry;
import 'package:grid_runtime/grid_runtime.dart'
    show GitOps, PrOpener, RootCheckout, StationGitService;
import 'package:grid_sdk/grid_sdk.dart' as sdk;

/// One authored project in space's station — a name and its ONE root (v3 §0: a
/// substation is a name and ONE root, never a set). The [build] tree fans these
/// out as `Substation`s; each substation's work store lives at `<root>/.beads/`.
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
/// master [build] authors the v3 §2 tree; `space up` mounts it with
/// `runGrid(this)`.
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
  /// Surfaced through the overridden [root] getter below.
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

  /// The `RawAssetGrid` root — the grid's home (v3 §3). `space` overrides the
  /// base's throwing [sdk.GridDelegate.root] so the default-build machinery and
  /// this wholesale [build] agree on one home.
  @override
  String get root => gridRoot;

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
  /// Mounted by `runGrid(this)` (`space up`) and exercised offline by
  /// `test/space_delegate_test.dart`. Each substation's `Nest` child is
  /// [_WorkListMount] — the seat the engine's `WorkList` binds into once the
  /// `runGrid`→kernel bridge lands (the pending live-drive work, Track J).
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
// v3 stores-at-roots (tg-r81): a substation is a name AND its ONE root, paired
// in ONE `--substation <name>=<root>` flag — no `defaultSubstation`, no
// `substations.first` privilege, no separate `--root`/`--workspace` axes, no
// `RootSpec`/`StationArgs`. The state store (and the RS-2 lock) live under the
// grid home (`--grid-home`).
//
// A resident verb takes NO drive-list, EVER (D-R1/D-R4): the ready frontier of
// the owned substation IS the drive set, so there is no `--bead` on this
// parser — a trigger surface a misbehaving agent or a confused human could pull.
// ─────────────────────────────────────────────────────────────────────────────

/// space's resolved resident-station config — its OWN value type (v3
/// stores-at-roots), NOT `grid_cli`'s `StationArgs`. [gridHome] is the grid's
/// home (the state store + RS-2 lock live under `<gridHome>/.grid/`);
/// [substations] each carry their ONE root; the rest are the resident dials.
class SpaceStationConfig {
  /// Creates the config.
  const SpaceStationConfig({
    required this.gridHome,
    required this.substations,
    this.dryRun = true,
    this.controlPort = 0,
    this.runFor,
  });

  /// The grid's home (absolute): `<gridHome>/.grid/` holds the state store and
  /// the RS-2 station lock (Q5a). Never a default (v3 §0).
  final String gridHome;

  /// The owned substations, each a name + its ONE absolute root.
  final List<SpaceSubstation> substations;

  /// Observe-only (the SAFE DEFAULT). H2 is offline authoring regardless — the
  /// live work-driving arm is held for the human gate (Track J); this flag
  /// rides the status projection and the boot banner.
  final bool dryRun;

  /// The StationControl loopback port (RS-4). 0 = ephemeral (default).
  final int controlPort;

  /// Run for a fixed number of seconds then exit (scripted / CI), else run
  /// resident until the first termination signal.
  final Duration? runFor;
}

/// Adds space's resident-station flags to [parser] (the station surface MINUS
/// `--bead`). Space's own design; there is deliberately no `--bead`.
void addSpaceStationFlags(ArgParser parser) {
  parser
    ..addMultiOption(
      'substation',
      abbr: 'r',
      help:
          'An OWNED substation and its ONE root, paired: '
          '`--substation <name>=<root>` (repeatable, absolute root). A '
          'substation is a name and ONE root (v3 §0) — its `.beads/` work '
          'store lives at `<root>/.beads/`. At least one is required. The '
          'dogfood substation is `tgdog`.',
    )
    ..addOption(
      'grid-home',
      abbr: 'g',
      help:
          "The grid's HOME (absolute): the state store and the RS-2 station "
          'lock live under `<grid-home>/.grid/`. Required to ARM (never a '
          'default — v3 §0). Aliased by --state-workspace for continuity with '
          '`space down`/`space status`, which attach to the SAME lock.',
    )
    ..addOption(
      'state-workspace',
      help:
          'Alias for --grid-home (the state store / RS-2 lock home). The name '
          '`space down`/`space status` use to attach to the SAME lock.',
    )
    ..addFlag(
      'dry-run',
      defaultsTo: true,
      help:
          'Observe-only: NO writes, NO spawns (the SAFE DEFAULT). H2 mounts the '
          'delegate tree offline regardless — the live work-driving arm is held '
          'for the human gate (Track J).',
    )
    ..addOption(
      'for-seconds',
      help: 'Run for a fixed number of seconds then exit (scripted / CI).',
    )
    ..addOption(
      'control-port',
      defaultsTo: '0',
      help: 'The StationControl loopback port (RS-4). 0 = ephemeral (default).',
    );
}

/// Parses one `--substation <name>=<root>` value into a [SpaceSubstation] over
/// an absolute [RootCheckout]. Throws [FormatException] on a malformed pairing
/// (no `=`, empty name, or empty root) — a config defect the operator sees
/// immediately. The root's branch defaults to `main` (dry authoring never
/// probes `origin/HEAD`; the live git arm — held — assigns the probed default).
SpaceSubstation _parseSubstation(String raw) {
  final eq = raw.indexOf('=');
  if (eq < 0) {
    throw FormatException(
      'space up: --substation "$raw" must pair a name with its ONE root — '
      '`--substation <name>=<root>` (v3 §0: a substation is a name AND a root)',
    );
  }
  final name = raw.substring(0, eq).trim();
  final rootPath = raw.substring(eq + 1).trim();
  if (name.isEmpty) {
    throw FormatException(
      'space up: --substation "$raw" has an empty name before "="',
    );
  }
  if (rootPath.isEmpty) {
    throw FormatException(
      'space up: --substation "$raw" has an empty root after "="',
    );
  }
  return SpaceSubstation(
    name: name,
    root: RootCheckout(path: rootPath, defaultBranch: 'main', substation: name),
  );
}

/// Builds [SpaceStationConfig] from space's own flags ([addSpaceStationFlags]).
/// A duplicate substation name is a loud [FormatException] (a config defect the
/// operator sees immediately, never a silent overwrite); a missing --grid-home
/// or an empty substation set is a null return, which the verb renders as a
/// LOUD arming refusal (never a `''` sentinel — v3 kills those).
SpaceStationConfig? spaceStationConfigFrom(ArgResults args) {
  final gridHome = (args.option('grid-home') ?? args.option('state-workspace'))
      ?.trim();
  if (gridHome == null || gridHome.isEmpty) return null;

  final substations = <SpaceSubstation>[];
  final seen = <String>{};
  for (final raw in args.multiOption('substation')) {
    if (raw.trim().isEmpty) continue;
    final s = _parseSubstation(raw);
    if (!seen.add(s.name)) {
      throw FormatException(
        'space up: --substation "$raw" registers name "${s.name}" more than '
        'once',
      );
    }
    substations.add(s);
  }
  if (substations.isEmpty) return null;

  final seconds = args.option('for-seconds');
  return SpaceStationConfig(
    gridHome: gridHome,
    substations: substations,
    dryRun: args.flag('dry-run'),
    controlPort: int.parse(args.option('control-port')!),
    runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
  );
}
