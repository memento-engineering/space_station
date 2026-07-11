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
/// ## Track J — the work binding is IN (tg-yl8 / space-6nj)
///
/// The engine's `WorkList` now mounts INSIDE this tree: `space up` assembles
/// the off-tree machinery (`grid_sdk.buildStationWork` — controllers over the
/// stores at their roots, the join bridge, the bd chokepoint, the restart
/// reconciler) and threads its [sdk.StationWorkWiring] into this delegate;
/// [build] mounts `StationWork` above the fan-out and each substation's
/// `SubstationWork` seat establishes its `WorkList` (v3 §3). A delegate built
/// WITHOUT wiring (offline tests, fixtures) keeps H2's authoring-only shape —
/// the tree stands, drives no work. `--dry-run` (the default) arms the tree
/// over INERT seams (no spawn, no store write, no git). The first LIVE arm
/// (`--no-dry-run`) stays the human gate.
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
import 'package:path/path.dart' as p;

/// One authored project in space's station — a name and its ONE root (v3 §0: a
/// substation is a name and ONE root, never a set). The [build] tree fans these
/// out as `Substation`s; each substation's work store lives at `<root>/.beads/`.
class SpaceSubstation {
  /// A project named [name] rooted at [root] (an absolute [RootCheckout]).
  /// [prefix] is the work store's issue-id prefix — a SEPARATE axis from the
  /// name (Nico, 2026-07-08; `SUBSTATION-INIT.md` §2): `the_grid` (name) mints
  /// `tg-…` (prefix). Defaults to the name.
  const SpaceSubstation({
    required this.name,
    required this.root,
    String? prefix,
  }) : _prefix = prefix;

  /// The project's name (its substation id / ownership token).
  final String name;

  /// The project's single root checkout (absolute path + branch/remote).
  final RootCheckout root;

  final String? _prefix;

  /// The work store's issue-id prefix (ownership's primary axis).
  String get prefix => _prefix ?? name;

  /// The prefix the caller EXPLICITLY set (via `@<prefix>`), or null when it
  /// defaulted to the name. [mergeRoster] reads this so a flag rebinding a coded
  /// root WITHOUT a prefix keeps the coded prefix (`the_grid` stays `tg`), rather
  /// than silently overwriting it with the name.
  String? get explicitPrefix => _prefix;
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
    this.wiring,
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

  /// The EFFECTIVE roster VALUES (Fork B): the coded base with the operator's
  /// `--substation` flags merged on, as `space up` resolved it. [build] routes
  /// these into its LITERAL coded seats by name — an override rebinds a seat's
  /// root/prefix in place, a new name appends after the org — it never authors
  /// the roster from them.
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

  /// The station's work-axis wiring (Track J, tg-yl8/space-6nj): the DI'd
  /// ambient values `runGrid`'s tree provides through `StationWork` so each
  /// substation's `SubstationWork` mounts the engine's `WorkList` — the
  /// runGrid→engine bridge, assembled off-tree by `buildStationWork` in
  /// `space up`. Null ⇒ the UNARMED authoring-only mount (H2's shape: the tree
  /// stands, drives no work — offline tests, `space status` fixtures).
  final sdk.StationWorkWiring? wiring;

  /// The `RawAssetGrid` root — the grid's home (v3 §3). `space` overrides the
  /// base's throwing [sdk.GridDelegate.root] so the default-build machinery and
  /// this wholesale [build] agree on one home.
  @override
  String get root => gridRoot;

  /// The master build (v3 §2/§4): space's station as a tree —
  /// `RawAssetGrid(gridRoot) → Station(stationName) → HarnessProvider →
  /// Substations → Substation(Nest[GitGridAssets, GitHubGridAssets?])`.
  ///
  /// **The memento-engineering roster is authored HERE, literal and verbose**
  /// (`the_grid/docs/SCRATCH-memento-composition.md` §3, Fork A): space_station
  /// IS memento's grid instance, so its five org repos — genesis, the_grid,
  /// power_station, space_station, lenny — are written out below as direct
  /// [sdk.Substation] calls, each rooted at its umbrella sibling `../<repo>`
  /// (resolved absolute against the grid home) and each carrying its OWN
  /// `assets:` slot to hang per-substation assets on. NOT a manifest, NOT a
  /// for-loop, NOT filesystem discovery — the org is the tree.
  ///
  /// `--substation` flags (and, later, TOML) MERGE onto this base by name —
  /// never replace it (Fork B): space `up` folds the flags onto the coded base
  /// ([mergeRoster]) and hands the delegate the effective VALUES as
  /// [substations]; each coded seat below reads its merged root/prefix from
  /// there, so an override rebinds a coded seat IN PLACE and a NEW name
  /// APPENDS after the org. A coded sibling `up` dropped (no work store in
  /// this checkout) keeps its seat at the coded `../<repo>` root — the
  /// authored org stands; with no store controller feeding it, that seat
  /// drives no work.
  ///
  /// Each substation's git is a SUBSTATION-SCOPED asset (Track F: this is where
  /// `ServiceBundle` dissolves) resolved by tree position (bead → substation →
  /// root), never a string-keyed map; each seat's `Nest` child is
  /// [sdk.SubstationWork] — the seat the engine's `WorkList` binds into when
  /// the station is armed (Track J, tg-yl8/space-6nj). FOLLOW-ON (space-7uc):
  /// the committee's rubric/extension asset root belongs in these `assets:`
  /// slots too, so the critic resolves `grid_assets/extension` from the
  /// DECLARED path rather than a cwd walk-up — that asset is authored in
  /// `grid_assets` (power_station), so it lands with 7uc's change, not here.
  /// The harness registry + station-default [AgentConfig] mount STATION-scoped
  /// via [HarnessProvider], above the fan-out so every substation's work
  /// inherits them.
  ///
  /// Mounted by `runGrid(this)` (`space up`) and exercised offline by
  /// `test/space_delegate_test.dart` / `test/memento_roster_test.dart`.
  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) {
    final armedWiring = wiring;
    final opener = prOpener;
    // Fork B ROUTING, not roster authorship (the roster is the literal seats
    // below): pluck each coded seat's effective value — the coded base with
    // the operator's flags merged on, minus any sibling `up` dropped — out of
    // [substations] by name; whatever is left is the append layer.
    SpaceSubstation? genesis;
    SpaceSubstation? theGrid;
    SpaceSubstation? powerStation;
    SpaceSubstation? spaceStation;
    SpaceSubstation? lenny;
    final appended = <SpaceSubstation>[];
    for (final s in substations) {
      switch (s.name) {
        case 'genesis':
          genesis = s;
        case 'the_grid':
          theGrid = s;
        case 'power_station':
          powerStation = s;
        case 'space_station':
          spaceStation = s;
        case 'lenny':
          lenny = s;
        default:
          appended.add(s);
      }
    }
    final substationFanOut = sdk.Substations(
      substations: [
        // ── The memento-engineering org, HARDCODED (Fork A): five literal
        // seats, one per repo, side-by-side umbrella siblings of the grid
        // home. Assets hang on each seat individually. ──
        sdk.Substation(
          name: 'genesis',
          root:
              genesis?.root.path ?? p.normalize(p.join(gridRoot, '../genesis')),
          prefix: genesis?.prefix ?? 'genesis',
          assets: [
            Nest(
              children: [
                GitGridAssets(
                  provisioner: provisioner,
                  gitOps: gitOps,
                  defaultBranch: genesis?.root.defaultBranch ?? 'main',
                  remote: genesis?.root.remote ?? 'origin',
                ),
                if (opener != null) GitHubGridAssets(prOpener: opener),
              ],
              child: const sdk.SubstationWork(),
            ),
          ],
        ),
        sdk.Substation(
          name: 'the_grid',
          root:
              theGrid?.root.path ??
              p.normalize(p.join(gridRoot, '../the_grid')),
          prefix: theGrid?.prefix ?? 'tg',
          assets: [
            Nest(
              children: [
                GitGridAssets(
                  provisioner: provisioner,
                  gitOps: gitOps,
                  defaultBranch: theGrid?.root.defaultBranch ?? 'main',
                  remote: theGrid?.root.remote ?? 'origin',
                ),
                if (opener != null) GitHubGridAssets(prOpener: opener),
              ],
              child: const sdk.SubstationWork(),
            ),
          ],
        ),
        sdk.Substation(
          name: 'power_station',
          root:
              powerStation?.root.path ??
              p.normalize(p.join(gridRoot, '../power_station')),
          prefix: powerStation?.prefix ?? 'pow',
          assets: [
            Nest(
              children: [
                GitGridAssets(
                  provisioner: provisioner,
                  gitOps: gitOps,
                  defaultBranch: powerStation?.root.defaultBranch ?? 'main',
                  remote: powerStation?.root.remote ?? 'origin',
                ),
                if (opener != null) GitHubGridAssets(prOpener: opener),
              ],
              child: const sdk.SubstationWork(),
            ),
          ],
        ),
        sdk.Substation(
          name: 'space_station',
          root:
              spaceStation?.root.path ??
              p.normalize(p.join(gridRoot, '../space_station')),
          prefix: spaceStation?.prefix ?? 'space',
          assets: [
            Nest(
              children: [
                GitGridAssets(
                  provisioner: provisioner,
                  gitOps: gitOps,
                  defaultBranch: spaceStation?.root.defaultBranch ?? 'main',
                  remote: spaceStation?.root.remote ?? 'origin',
                ),
                if (opener != null) GitHubGridAssets(prOpener: opener),
              ],
              child: const sdk.SubstationWork(),
            ),
          ],
        ),
        sdk.Substation(
          name: 'lenny',
          root: lenny?.root.path ?? p.normalize(p.join(gridRoot, '../lenny')),
          prefix: lenny?.prefix ?? 'lenny',
          assets: [
            Nest(
              children: [
                GitGridAssets(
                  provisioner: provisioner,
                  gitOps: gitOps,
                  defaultBranch: lenny?.root.defaultBranch ?? 'main',
                  remote: lenny?.root.remote ?? 'origin',
                ),
                if (opener != null) GitHubGridAssets(prOpener: opener),
              ],
              child: const sdk.SubstationWork(),
            ),
          ],
        ),
        // ── Fork B's append layer: `--substation`/TOML names beyond the
        // coded org fan out AFTER it, in flag order. ──
        for (final s in appended)
          sdk.Substation(
            name: s.name,
            root: s.root.path,
            prefix: s.prefix,
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
                child: const sdk.SubstationWork(),
              ),
            ],
          ),
      ],
    );
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
              // ARMED: StationWork provides the engine's ambient work-axis
              // stack above the fan-out (the runGrid→engine bridge, tg-yl8);
              // UNARMED (wiring null): H2's authoring-only shape.
              child: armedWiring != null
                  ? sdk.StationWork(
                      wiring: armedWiring,
                      child: substationFanOut,
                    )
                  : substationFanOut,
            ),
          ],
        ),
      ],
    );
  }
}

/// The coded org as VALUES — the same five substations [SpaceDelegate.build]
/// authors as literal seats, mirrored for the machinery a tree cannot feed:
/// [mergeRoster]'s base, `space up`'s store guard, and `buildStationWork`'s
/// work specs all need the roster off-tree, as data. Literal entries (Fork A:
/// NOT a map, NOT a for-loop); each root is the umbrella sibling `../<repo>`,
/// [p.normalize]d absolute against [gridHome] — the side-by-side opinion. The
/// prefix is a SEPARATE axis from the name (`the_grid` mints `tg-…`); the
/// branch defaults to `main` (dry authoring never probes `origin/HEAD`; the
/// live git arm assigns the probed default at root registration).
/// `memento_roster_test.dart` pins this mirror and the built tree together so
/// they cannot drift. Adding a repo to the org (e.g. `decisions`/`expression`
/// once they gain a bead store) is a literal entry here plus its literal seat
/// in [SpaceDelegate.build].
List<SpaceSubstation> mementoCodedRoster(String gridHome) => [
  // the substrate — driven directly (worktrees isolate under .grid/worktrees)
  SpaceSubstation(
    name: 'genesis',
    root: RootCheckout(
      path: p.normalize(p.join(gridHome, '../genesis')),
      defaultBranch: 'main',
      substation: 'genesis',
    ),
  ),
  // the framework — self-host; `tg` is the shared Dolt server (gc coexists)
  SpaceSubstation(
    name: 'the_grid',
    prefix: 'tg',
    root: RootCheckout(
      path: p.normalize(p.join(gridHome, '../the_grid')),
      defaultBranch: 'main',
      substation: 'the_grid',
    ),
  ),
  // the asset packs — self-host
  SpaceSubstation(
    name: 'power_station',
    prefix: 'pow',
    root: RootCheckout(
      path: p.normalize(p.join(gridHome, '../power_station')),
      defaultBranch: 'main',
      substation: 'power_station',
    ),
  ),
  // the runner — self-host; this IS the grid home
  SpaceSubstation(
    name: 'space_station',
    prefix: 'space',
    root: RootCheckout(
      path: p.normalize(p.join(gridHome, '../space_station')),
      defaultBranch: 'main',
      substation: 'space_station',
    ),
  ),
  // the debug harness (memento-engineering/lenny)
  SpaceSubstation(
    name: 'lenny',
    root: RootCheckout(
      path: p.normalize(p.join(gridHome, '../lenny')),
      defaultBranch: 'main',
      substation: 'lenny',
    ),
  ),
];

/// Folds [overrides] (parsed `--substation` flags; later TOML) ONTO [base] (the
/// coded roster) — the Fork B append/merge layer
/// (`the_grid/docs/SCRATCH-memento-composition.md` §3):
///
///  - an override whose name matches a base entry MERGES onto it IN PLACE (the
///    coded slot keeps its mount position; the override's root wins; its prefix
///    wins ONLY when explicitly given — else the coded prefix is preserved, so
///    `--substation power_station=/elsewhere` keeps `pow`, not the name);
///  - an override with a NEW name is APPENDED after the coded roster.
///
/// It never replaces the base wholesale and never subsets it: no-flag `space up`
/// still arms the full coded org. Preserves order — coded slots first (in coded
/// order), appended extras after, in flag order.
List<SpaceSubstation> mergeRoster(
  List<SpaceSubstation> base,
  List<SpaceSubstation> overrides,
) {
  final overrideByName = {for (final s in overrides) s.name: s};
  final baseNames = {for (final b in base) b.name};
  return [
    for (final b in base)
      if (overrideByName[b.name] case final o?)
        SpaceSubstation(
          name: b.name,
          root: o.root,
          prefix: o.explicitPrefix ?? b.prefix,
        )
      else
        b,
    for (final o in overrides)
      if (!baseNames.contains(o.name)) o,
  ];
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
/// [substations] is the EFFECTIVE roster (the coded memento base with any
/// `--substation` flags merged onto it — [mergeRoster]); the rest are the
/// resident dials.
class SpaceStationConfig {
  /// Creates the config.
  const SpaceStationConfig({
    required this.gridHome,
    required this.substations,
    this.operatorNames = const {},
    this.dryRun = true,
    this.controlPort = 0,
    this.runFor,
  });

  /// The grid's home (absolute): `<gridHome>/.grid/` holds the state store and
  /// the RS-2 station lock (Q5a). Never a default (v3 §0).
  final String gridHome;

  /// The EFFECTIVE roster: the coded memento base ([mementoCodedRoster]) with the
  /// operator's `--substation` flags merged on ([mergeRoster]), each a name + its
  /// ONE absolute root.
  final List<SpaceSubstation> substations;

  /// The names the operator NAMED via a `--substation` flag (a SUBSET of
  /// [substations]' names). Provenance for `space up`'s store guard: an
  /// operator-named substation whose store is absent is a LOUD refusal (their
  /// error), while a coded-base substation not present in THIS checkout (a
  /// sibling not yet cloned/relocated — e.g. lenny) is skipped LOUD so the rest
  /// of the org still arms.
  final Set<String> operatorNames;

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
          'A substation and its ONE root, paired: '
          '`--substation <name>[@<prefix>]=<root>` (repeatable, absolute '
          'root). MERGES onto the coded memento roster (genesis, the_grid, '
          'power_station, space_station, lenny): a coded name rebinds that '
          'substation\'s root, a new name appends one — never replaces the base. '
          'A substation is a name and ONE root (v3 §0) — its `.beads/` work '
          'store lives at `<root>/.beads/`. The optional `@<prefix>` names the '
          'store\'s issue-id prefix when it differs from the name '
          '(`the_grid@tg=/work/the_grid`). Optional: no-flag `space up` arms '
          'the coded org.',
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

/// Parses one `--substation <name>[@<prefix>]=<root>` value into a
/// [SpaceSubstation] over an absolute [RootCheckout]. Throws [FormatException]
/// on a malformed pairing (no `=`, empty name/prefix/root) — a config defect
/// the operator sees immediately. The optional `@<prefix>` names the store's
/// issue-id prefix when it differs from the name (names ≠ prefixes:
/// `the_grid@tg=/work/the_grid`); absent, the prefix IS the name. The root's
/// branch defaults to `main` (dry authoring never probes `origin/HEAD`; the
/// live git arm assigns the probed default at root registration).
SpaceSubstation _parseSubstation(String raw) {
  final eq = raw.indexOf('=');
  if (eq < 0) {
    throw FormatException(
      'space up: --substation "$raw" must pair a name with its ONE root — '
      '`--substation <name>[@<prefix>]=<root>` (v3 §0: a substation is a name '
      'AND a root)',
    );
  }
  var name = raw.substring(0, eq).trim();
  final rootPath = raw.substring(eq + 1).trim();
  String? prefix;
  final at = name.indexOf('@');
  if (at >= 0) {
    prefix = name.substring(at + 1).trim();
    name = name.substring(0, at).trim();
    if (prefix.isEmpty) {
      throw FormatException(
        'space up: --substation "$raw" has an empty prefix after "@" — omit '
        'the "@" entirely when the prefix is the name',
      );
    }
  }
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
    prefix: prefix,
    root: RootCheckout(path: rootPath, defaultBranch: 'main', substation: name),
  );
}

/// Builds [SpaceStationConfig] from space's own flags ([addSpaceStationFlags]).
/// The roster is the coded memento base ([mementoCodedRoster]) with the parsed
/// `--substation` flags MERGED on ([mergeRoster]) — Fork B: no-flag `space up`
/// arms the whole coded org, a flag rebinds a coded root or appends a new one.
/// A duplicate `--substation` name (the same name twice on the command line) is
/// a loud [FormatException] — a config defect the operator sees immediately,
/// never a silent overwrite (a flag matching a CODED name is a MERGE, not a
/// duplicate). A missing --grid-home is a null return, which the verb renders as
/// a LOUD arming refusal (never a `''` sentinel — v3 kills those); the roster is
/// never empty, so the old "no substation ⇒ refuse" gate is retired.
SpaceStationConfig? spaceStationConfigFrom(ArgResults args) {
  final gridHome = (args.option('grid-home') ?? args.option('state-workspace'))
      ?.trim();
  if (gridHome == null || gridHome.isEmpty) return null;

  final overrides = <SpaceSubstation>[];
  final operatorNames = <String>{};
  for (final raw in args.multiOption('substation')) {
    if (raw.trim().isEmpty) continue;
    final s = _parseSubstation(raw);
    if (!operatorNames.add(s.name)) {
      throw FormatException(
        'space up: --substation "$raw" registers name "${s.name}" more than '
        'once',
      );
    }
    overrides.add(s);
  }

  final seconds = args.option('for-seconds');
  return SpaceStationConfig(
    gridHome: gridHome,
    substations: mergeRoster(mementoCodedRoster(gridHome), overrides),
    operatorNames: operatorNames,
    dryRun: args.flag('dry-run'),
    controlPort: int.parse(args.option('control-port')!),
    runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
  );
}
