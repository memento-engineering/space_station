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
/// [build], never a `ServiceBundle` map fed to `composeStation`.
///
/// ## Track J — the work binding is IN (tg-yl8 / space-6nj)
///
/// The engine's `WorkList` mounts INSIDE this tree: `space up` assembles the
/// off-tree machinery (`grid_sdk.buildStationWork`) and threads its
/// [sdk.StationWorkWiring] into this delegate; [build] mounts `StationWork`
/// above the fan-out and each substation's `SubstationWork` seat establishes
/// its `WorkList` (v3 §3). A delegate built WITHOUT wiring (offline tests,
/// fixtures) keeps H2's authoring-only shape — the tree stands, drives no
/// work. `--dry-run` (the default) arms the tree over INERT seams.
///
/// ## space-6ds — the roster is CODE, defaulting to the memento org
///
/// space_station IS memento's grid instance
/// (`the_grid/docs/SCRATCH-memento-composition.md`, Nico 2026-07-10): the five
/// org substations — genesis, the_grid, power_station, space_station, lenny —
/// are authored in Dart as [mementoRoster], the ONE definition both this
/// delegate's [build] and `space up`'s off-tree machinery consume (the old
/// hand-kept mirror in `up_command.dart` is gone — the divergence it risked
/// silently un-owned beads). A seat roots at its umbrella sibling `../<repo>`
/// (the SDK resolves a relative root against the ambient `GridRoot` — tg-32r)
/// or at an ABSOLUTE root. NO overriding by config (round 3): a `--substation`
/// flag APPENDS a new substation after the roster; changing the roster is a
/// CODE change — space edits [mementoRoster], and a DOWNSTREAM station
/// (extend-don't-fork) passes its OWN [SubstationSpec] list instead.
/// No-flag `space up` arms the org.
library;

import 'package:args/args.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentConfig,
        EnvironmentRegistry,
        GitGridAssets,
        GitHubGridAssets,
        GitServices,
        HarnessProvider,
        buildBuiltinEnvironmentRegistry;
import 'package:grid_runtime/grid_runtime.dart'
    show GitOps, PrOpener, StationGitService;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

/// One substation seat, AS DATA: its [name], its [root] — relative (resolved
/// against the grid home / the tree's ambient `GridRoot`, tg-32r) or ABSOLUTE
/// (used as-is; how a downstream station seats repos outside its umbrella) —
/// and the work store's issue-id [prefix] (defaults to the name).
///
/// The spec is the ONE roster currency: [SpaceDelegate.build] folds each spec
/// into its literal [sdk.Substation] seat (the standard
/// `Nest[GitGridAssets → GitHubGridAssets] → SubstationWork` stack, delivery
/// threaded), and `space up`'s off-tree machinery (the store guard,
/// `buildStationWork`'s specs, the `/status` view) reads the SAME list — so
/// the tree and the machinery cannot diverge.
class SubstationSpec {
  /// Creates a spec. [prefix] names the store's issue-id prefix when it
  /// differs from [name] (names ≠ prefixes — e.g. the_grid's store mints
  /// `tg-`).
  const SubstationSpec(this.name, this.root, {String? prefix})
    : _prefix = prefix;

  /// The substation's name.
  final String name;

  /// The substation's ONE root (v3 §0) — its `.beads/` work store lives at
  /// `<root>/.beads/`. Relative ⇒ resolved against the grid home; absolute ⇒
  /// used as-is.
  final String root;

  final String? _prefix;

  /// The work store's issue-id prefix ([name] unless overridden).
  String get prefix => _prefix ?? name;
}

/// The memento-engineering org roster — the CODED default drive set
/// (space-6ds): the five org substations, each an umbrella sibling of the
/// grid home. With no [umbrella], roots are the `../<repo>` siblings (space's
/// own posture: the grid home IS inside the umbrella); a downstream station
/// whose grid home lives ELSEWHERE passes the umbrella's absolute path and
/// gets absolute-rooted seats.
List<SubstationSpec> mementoRoster({String? umbrella}) {
  String at(String repo) =>
      umbrella == null ? '../$repo' : p.join(umbrella, repo);
  return [
    // the substrate — driven directly (worktrees isolate under
    // .grid/worktrees; main untouched)
    SubstationSpec('genesis', at('genesis')),
    // the framework — self-host; `tg` is the shared Dolt server (gc coexists:
    // read tg's frontier, write sessions to houston — A37)
    SubstationSpec('the_grid', at('the_grid'), prefix: 'tg'),
    // the asset packs — self-host
    SubstationSpec('power_station', at('power_station'), prefix: 'pow'),
    // the runner — self-host; for space this IS the grid home. Its store
    // mints `space-` (NOT `space_station-`), so the prefix MUST be set
    // explicitly — the default (prefix ?? name) would own `space_station`
    // and drive nothing (ownership matches name OR prefix).
    SubstationSpec('space_station', at('space_station'), prefix: 'space'),
    // the debug harness (memento-engineering/lenny)
    SubstationSpec('lenny', at('lenny')),
  ];
}

/// The delegate seat memento's `space` verbs re-seat over — space_station
/// authored as a Seed.
///
/// Constructed from space's resolved station config (its [gridRoot] home, the
/// coded [roster] — [mementoRoster] unless a downstream station passed its
/// own — the operator's [appended] flag seats, the station-default
/// [agentConfig], and — when a live run armed them — the git [provisioner] /
/// [gitOps] / [prOpener]). The master [build] authors the v3 §2 tree by
/// folding the roster into literal seats; `space up` mounts it with
/// `runGrid(this)`.
class SpaceDelegate extends sdk.GridDelegate {
  /// Creates the delegate over space's resolved station config. [roster]
  /// defaults to the memento org ([mementoRoster]) — a downstream station
  /// passes its own. [harnesses] defaults to the first-party
  /// claude/copilot/pi/opencode set. [provisioner] / [gitOps] / [prOpener]
  /// are the live git machinery (all null ⇒ the offline / dry-run authoring,
  /// where provisioning + land no-op but the worktree layout still resolves —
  /// Track F).
  SpaceDelegate({
    required this.gridRoot,
    required this.stationName,
    required this.agentConfig,
    List<SubstationSpec>? roster,
    this.appended = const [],
    EnvironmentRegistry? harnesses,
    this.wiring,
    this.provisioner,
    this.gitOps,
    this.prOpener,
  }) : roster = roster ?? mementoRoster(),
       harnesses = harnesses ?? buildBuiltinEnvironmentRegistry();

  /// The station's home (absolute): the `RawAssetGrid` root the [build] tree
  /// roots at; the grid's state store lives under `<gridRoot>/.grid/` (Q5a).
  /// Surfaced through the overridden [root] getter below.
  final String gridRoot;

  /// The machine's name (the `Station` name — e.g. the host).
  final String stationName;

  /// The CODED roster — the station's default drive set, authored in Dart
  /// (space-6ds; [mementoRoster] unless a downstream station passed its own).
  /// [build] folds each spec into its literal [sdk.Substation] seat, BEFORE
  /// the [appended] layer.
  final List<SubstationSpec> roster;

  /// The operator's `--substation` flags, parsed into ready [sdk.Substation]
  /// seats — the APPEND layer (Fork B, round 3): they spread AFTER the coded
  /// org in [build], in flag order. Never a merge, never an override — the
  /// coded roster is changed by forking [build], not by config.
  final List<sdk.Substation> appended;

  /// The station-default agent scope (harness / model / target) — the ambient
  /// rung of the agent-config ladder (ADR-0008 D10).
  final AgentConfig agentConfig;

  /// The station's environment registry (which named inference environments —
  /// claude/copilot/pi/opencode/codex — the machine can run). Passed as the
  /// `HarnessProvider.registry`.
  final EnvironmentRegistry harnesses;

  /// The station's shared worktree-provisioning service (leased per
  /// substation); null ⇒ provisioning no-ops (offline / dry-run). Provided to
  /// every seat's bare [GitGridAssets] through the ambient [GitServices]
  /// carrier [build] mounts once above the fan-out (pow-72b).
  final StationGitService? provisioner;

  /// Commit/push ops; null ⇒ land no-ops (the commit-only arm). Rides the
  /// same ambient [GitServices] carrier as [provisioner].
  final GitOps? gitOps;

  /// The PR-opening seam; null ⇒ no land added (the commit-only arm). DI'd
  /// into each coded seat's [GitHubGridAssets] (ADR-0006 D3: the land ops
  /// flow into the substations' GitHub assets, never through station
  /// services).
  final PrOpener? prOpener;

  /// The station's work-axis wiring (Track J, tg-yl8/space-6nj): the DI'd
  /// ambient values `runGrid`'s tree provides through `StationWork` so each
  /// substation's `SubstationWork` mounts the engine's `WorkList`. Null ⇒ the
  /// UNARMED authoring-only mount (H2's shape: the tree stands, drives no
  /// work — offline tests, `space status` fixtures).
  final sdk.StationWorkWiring? wiring;

  /// The `RawAssetGrid` root — the grid's home (v3 §3). `space` overrides the
  /// base's throwing [sdk.GridDelegate.root] so the default-build machinery and
  /// this wholesale [build] agree on one home.
  @override
  String get root => gridRoot;

  /// The master build (v3 §2/§4): space's station as ONE literal tree.
  ///
  /// **The roster is CODE** (space-6ds, evolved): [roster] — [mementoRoster]
  /// unless a downstream station passed its own — folds seat by seat into
  /// literal [sdk.Substation] calls, each with its root (relative resolved
  /// against the ambient `GridRoot`, tg-32r; absolute used as-is) and the
  /// standard asset stack ([_seat]). NOT a manifest file, NOT filesystem
  /// discovery — the roster is authored in Dart, and changing it is a code
  /// change: space edits [mementoRoster]; a downstream station (extend, never
  /// fork) constructs the delegate with its OWN [SubstationSpec] list.
  ///
  /// **Flags APPEND, never override** (Fork B, round 3): the parsed
  /// `--substation` seats ([appended]) spread AFTER the coded roster, in flag
  /// order. No merge, no override-by-name. A coded sibling absent from this
  /// checkout still mounts its seat (root resolution is pure path math); with
  /// no store controller feeding it (`space up` arms controllers only over
  /// stores that resolve), that seat drives no work.
  ///
  /// Each seat's git is substation-scoped (Track F): [GitGridAssets] mounts
  /// BARE and reads the provisioner/gitOps halves from the ambient
  /// [GitServices] this tree provides ONCE above the fan-out (pow-72b);
  /// [GitHubGridAssets] adds land when a live [prOpener] is DI'd (ADR-0006
  /// D3). Each seat's fold-child is [sdk.SubstationWork] — the seat the
  /// engine's `WorkList` binds into when the station is armed (Track J).
  /// FOLLOW-ON (space-7uc): the committee's rubric/extension asset root
  /// belongs in these `assets:` slots too, so the critic resolves
  /// `grid_assets/extension` from the DECLARED path rather than a cwd walk-up
  /// — that asset is authored in `grid_assets` (power_station), so it lands
  /// with 7uc's change, not here.
  ///
  /// Mounted by `runGrid(this)` (`space up`) and exercised offline by
  /// `test/space_delegate_test.dart` / `test/memento_roster_test.dart`.
  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) {
    final armedWiring = wiring;
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
              child: InheritedSeed<GitServices>(
                value: GitServices(provisioner: provisioner, gitOps: gitOps),
                child: Nest(
                  children: [
                    // ARMED: StationWork provides the engine's ambient
                    // work-axis stack above the fan-out (the runGrid→engine
                    // bridge, tg-yl8); UNARMED: H2's authoring-only shape.
                    if (armedWiring != null)
                      sdk.StationWork(wiring: armedWiring),
                  ],
                  child: sdk.Substations(
                    substations: [
                      // ── The CODED roster (space-6ds): the station's
                      // default drive set, authored in Dart — memento's five
                      // org seats unless a downstream station passed its
                      // own. Each spec folds into the standard seat. ──
                      for (final spec in roster) _seat(spec),
                      // ── The append layer (Fork B): `--substation` seats
                      // fan out AFTER the roster, in flag order. ──
                      ...appended,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Folds one [SubstationSpec] into its literal seat: the standard
  /// `Nest[GitGridAssets → GitHubGridAssets] → SubstationWork` stack.
  /// [GitGridAssets] mounts BARE and reads provisioning/commit from the
  /// ambient [GitServices]; [GitHubGridAssets] binds PR delivery iff a live
  /// [prOpener] was DI'd (ADR-0006 D3) — so a downstream roster's seats get
  /// the SAME delivery wiring as the org's.
  sdk.Substation _seat(SubstationSpec spec) => sdk.Substation(
    spec.name,
    spec.root,
    prefix: spec.prefix,
    assets: [
      Nest(
        children: [
          const GitGridAssets(),
          GitHubGridAssets(prOpener: prOpener),
        ],
        child: const sdk.SubstationWork(),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// space's OWN CLI surface — the seat the resident verbs re-seat over.
//
// v3 stores-at-roots (tg-r81): a substation is a name AND its ONE root, paired
// in ONE `--substation <name>=<root>` flag. The coded roster is authored in
// Dart (space-6ds: [mementoRoster], or a downstream station's own
// SubstationSpec list) — flags only APPEND new substations onto it; a coded
// name on a flag is a LOUD refusal (round 3: the roster is changed in code,
// never by config). The state store (and the RS-2 lock) live under the grid
// home (`--grid-home`).
//
// A resident verb takes NO drive-list, EVER (D-R1/D-R4): the ready frontier of
// the owned substation IS the drive set, so there is no `--bead` on this
// parser — a trigger surface a misbehaving agent or a confused human could pull.
// ─────────────────────────────────────────────────────────────────────────────

/// space's resolved resident-station config — its OWN value type (v3
/// stores-at-roots), NOT `grid_cli`'s `StationArgs`. [gridHome] is the grid's
/// home (the state store + RS-2 lock live under `<gridHome>/.grid/`);
/// [appended] is the operator's append layer; the rest are the resident dials.
class SpaceStationConfig {
  /// Creates the config.
  const SpaceStationConfig({
    required this.gridHome,
    this.appended = const [],
    this.dryRun = true,
    this.controlPort = 0,
    this.runFor,
  });

  /// The grid's home (absolute): `<gridHome>/.grid/` holds the state store and
  /// the RS-2 station lock (Q5a). Never a default (v3 §0).
  final String gridHome;

  /// The operator's `--substation` flags, parsed into APPENDED
  /// [sdk.Substation] seats (Fork B, round 3: append-only — the coded roster
  /// lives in [SpaceDelegate.build], never here). Every appended seat is
  /// operator-named: `up`'s store guard refuses LOUD when one resolves no
  /// work store (their error), while an absent CODED sibling is skipped loud
  /// so the rest of the org still arms.
  final List<sdk.Substation> appended;

  /// Observe-only (the SAFE DEFAULT): the tree arms over INERT seams — no
  /// spawn, no store write, no git. The first LIVE arm (`--no-dry-run`) stays
  /// the human gate (Track J).
  final bool dryRun;

  /// The StationControl loopback port (RS-4). 0 = ephemeral (default).
  final int controlPort;

  /// Run for a fixed number of seconds then exit (scripted / CI), else run
  /// resident until the first termination signal.
  final Duration? runFor;
}

/// Adds space's resident-station flags to [parser] (the station surface MINUS
/// `--bead`). Space's own design; there is deliberately no `--bead`.
///
/// [roster] is the composing station's coded drive set ([mementoRoster]
/// absent) — rendered into the `--substation` help so a downstream station's
/// operator reads THEIR coded names, not memento's.
void addSpaceStationFlags(ArgParser parser, {List<SubstationSpec>? roster}) {
  final codedNames = [for (final s in roster ?? mementoRoster()) s.name];
  parser
    ..addMultiOption(
      'substation',
      abbr: 'r',
      help:
          'A NEW substation to APPEND onto the coded roster '
          '(${codedNames.join(', ')}), paired: '
          '`--substation <name>[@<prefix>]=<root>` (repeatable, absolute '
          'root). Append-only: a coded name is refused — the coded roster is '
          'authored in Dart (a SubstationSpec list) and changed in code, '
          'never by flags. A substation is a name and ONE root (v3 §0) — its '
          '`.beads/` work store lives at `<root>/.beads/`. The optional '
          '`@<prefix>` names the store\'s issue-id prefix when it differs '
          'from the name (`tgdog@td=/work/tgdog`). Optional: a no-flag '
          '`up` arms the coded roster.',
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
          'Observe-only: NO writes, NO spawns (the SAFE DEFAULT). The tree '
          'arms over inert seams; the live work-driving arm (--no-dry-run) is '
          'the human gate (Track J).',
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

/// Parses one `--substation <name>[@<prefix>]=<root>` value into an APPENDED
/// [sdk.Substation] seat carrying the standard substation asset stack — the
/// same `Nest[GitGridAssets → GitHubGridAssets] → SubstationWork` fold the
/// coded seats author, all bare: commit/push flows from the ambient
/// [GitServices]; PR-opening for an appended substation waits until it is
/// CODED into the roster (round 3: flags append a seat, they do not rewire
/// one). Throws [FormatException] on a malformed pairing (no `=`, empty
/// name/prefix/root) — a config defect the operator sees immediately. The
/// optional `@<prefix>` names the store's issue-id prefix when it differs
/// from the name (names ≠ prefixes); absent, the prefix IS the name.
sdk.Substation _parseSubstation(String raw) {
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
  return sdk.Substation(
    name,
    rootPath,
    prefix: prefix,
    assets: const [
      Nest(
        children: [GitGridAssets(), GitHubGridAssets()],
        child: sdk.SubstationWork(),
      ),
    ],
  );
}

/// Builds [SpaceStationConfig] from space's own flags ([addSpaceStationFlags]).
/// The CODED roster is authored in Dart ([mementoRoster] / a downstream
/// station's own list) and consumed by [SpaceDelegate.build] — it never
/// arrives through here; [codedNames] (defaulting to the memento five) is the
/// refusal set. `--substation` flags parse into APPENDED seats
/// ([SpaceStationConfig.appended]); a flag naming a CODED substation is a loud
/// [FormatException] (round 3: the roster is code, never overridden by
/// config), as is the same name twice. A missing --grid-home is a null
/// return, which the verb renders as a LOUD arming refusal (never a `''`
/// sentinel — v3 kills those); the coded roster is never empty, so the old
/// "no substation ⇒ refuse" gate stays retired.
SpaceStationConfig? spaceStationConfigFrom(
  ArgResults args, {
  Set<String>? codedNames,
}) {
  final gridHome = (args.option('grid-home') ?? args.option('state-workspace'))
      ?.trim();
  if (gridHome == null || gridHome.isEmpty) return null;

  codedNames ??= {for (final s in mementoRoster()) s.name};
  final appended = <sdk.Substation>[];
  final seen = <String>{};
  for (final raw in args.multiOption('substation')) {
    if (raw.trim().isEmpty) continue;
    final s = _parseSubstation(raw);
    if (codedNames.contains(s.name)) {
      throw FormatException(
        'space up: --substation "$raw" names the CODED substation "${s.name}" '
        '— the coded roster is authored in Dart (mementoRoster / the '
        "station's own SubstationSpec list) and never overridden by flags "
        '(change the roster in code); flags APPEND new substations only',
      );
    }
    if (!seen.add(s.name)) {
      throw FormatException(
        'space up: --substation "$raw" registers name "${s.name}" more than '
        'once',
      );
    }
    appended.add(s);
  }

  final seconds = args.option('for-seconds');
  return SpaceStationConfig(
    gridHome: gridHome,
    appended: appended,
    dryRun: args.flag('dry-run'),
    controlPort: int.parse(args.option('control-port')!),
    runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
  );
}
