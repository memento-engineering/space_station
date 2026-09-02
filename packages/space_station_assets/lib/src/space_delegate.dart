/// `SpaceDelegate` — **space_station authored as a Seed** (Track G-space,
/// `the_grid/docs/GRID-SDK-BUILD-ORDER.md`; the v3 code-as-config model,
/// `the_grid/docs/SCRATCH-station-config-model.md` §2/§4).
///
/// `space` is a [sdk.GridDelegate] subclass whose master [build] authors the
/// canonical §2 tree —
/// `RawAssetGrid → Station → HarnessProvider → Substations → Substation`, with
/// each substation's per-project git a **substation-scoped asset**
/// ([GitGridAssets] plus the imported GitHub extension, Track F) rather than a
/// runner-built
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
/// ## space-6ds — the roster is CODE: the [SpaceDelegate.substations] hook
///
/// space_station IS memento's grid instance
/// (`the_grid/docs/SCRATCH-memento-composition.md`, Nico 2026-07-10): the six
/// org substations — genesis, the_grid, power_station, space_station, lenny,
/// decisions — are authored as literal seats in [SpaceDelegate.substations], the ONE
/// definition both [SpaceDelegate.build] and `space up`'s off-tree machinery
/// consume (the old hand-kept mirror in `up_command.dart` is gone — the
/// divergence it risked silently un-owned beads). A seat roots at its
/// umbrella sibling (the SDK resolves a relative root against the ambient
/// `GridRoot` — tg-32r) or at an ABSOLUTE root. NO overriding by config
/// (round 3): a `--substation` flag APPENDS a new substation after the
/// roster; changing the roster is a CODE change — space edits [substations]
/// here, and a DOWNSTREAM station (extend-don't-fork) SUBCLASSES the delegate
/// and overrides it. No-flag `space up` arms the org.
library;

import 'package:args/args.dart';
import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentConfig,
        AvailableEnvironments,
        BuildAgentEnvironment,
        CriticAgentEnvironment,
        EnvironmentRegistry,
        GatherAgentEnvironment,
        HarnessProvider,
        MountEligibilityAssets,
        ProcessEnvironmentProbe,
        SpecAgentEnvironment,
        buildCodeRegistry,
        mountedValueOf,
        mountedValuesOf;
import 'package:grid_runtime/grid_runtime.dart'
    show GhPrOpener, GitOps, PrOpener, StationGitService, SystemGitRunner;
import 'package:github_grid_assets/github_grid_assets.dart' as github;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_sdk/grid_sdk.dart' show Provider;
import 'package:path/path.dart' as p;

import 'agent_arming.dart';
import 'substation_seed.dart';

/// The factory signature the runner compositions construct a station's
/// delegate through — [SpaceDelegate.new] satisfies it, and so does a
/// downstream subclass's tear-off (`LunarDelegate.new`) whose constructor
/// mirrors the base via super-parameters. This is the ONE seam the composed
/// commands (`up`/`search`/`assets`) receive: WHICH delegate class a station
/// authors is the station's choice; WHEN and with what boot state it is
/// constructed is the command's.
typedef SpaceDelegateFactory =
    SpaceDelegate Function({
      required String gridRoot,
      AgentConfig? agentConfig,
      List<sdk.Substation> appended,
      EnvironmentRegistry? harnesses,
      sdk.StationWorkWiring? wiring,
      StationGitService? provisioner,
      github.GitHubSelfTrust? githubSelfTrust,
      bool live,
    });

/// Appends one resident capability log [line] to [beadId]'s notes through the
/// station-owned write chokepoint.
typedef NoteAppender = Future<void> Function(String beadId, String line);

/// The memento org's ONE GitHub App delivery identity — the `grid-assets` App
/// installed on `memento-engineering` (`repository_selection: all`), carried as
/// a VALUE by each of the six org seats [SpaceDelegate.substations] authors.
///
/// PER SUBSTATION, never per station (pow-1rn): this is a shared value, not a
/// station-level identity and not a name-keyed map. Nothing mounts it above the
/// substation fan-out; a seat delivering under a DIFFERENT App simply passes a
/// different [GitHubAppConfig], which is how a downstream station's private
/// seats keep their own App while inheriting these six through `super`.
///
/// ONE STATION OWNS DELIVERY FOR THESE REPOS. Whichever station runs resident
/// carries this identity; two resident stations over the same umbrella would
/// deliver twice, which the one-grid-per-machine rule already fences.
///
/// [GitHubAppConfig] holds non-secret identifiers only.
/// [GitHubAppConfig.privateKeyVar] is the NAME of an environment variable whose
/// VALUE is a path to the PEM key; this library never reads the environment —
/// the injected `github.GitHubAppClientAssets` resolves it at effect time. With
/// `GRID_GITHUB_APP_KEY_MEMENTO` unset the seat composes INERT and the ambient
/// opener stands: a missing key is a posture, never a boot error.
const kMementoOrgApp = GitHubAppConfig(
  appId: '4529262',
  installationId: '152260260',
  privateKeyVar: 'GRID_GITHUB_APP_KEY_MEMENTO',
);

/// Enumerates the CODED roster plus its GitHub-polling seat names from one
/// shared offline mount of the station [factory] authors.
///
/// The mount lifecycle and tree walk are owned by `grid_assets`'
/// `mountedValuesOf`; this package projects the [MountedSubstationSeed] values
/// authored by its seed class and disposes the delegate it constructed.
///
/// [gridRoot] defaults to `'/'` — a deterministic ABSOLUTE placeholder
/// (v3 §0: the tree refuses a relative root) for reads that only need
/// names/prefixes (seat names are grid-home-independent); pass the real home
/// when the resolved roots matter (they arrive resolved by the SDK's own
/// seat build).
({List<sdk.SubstationScope> scopes, Set<String> githubPollingSeatNames})
codedRosterSnapshotOf(SpaceDelegateFactory factory, {String gridRoot = '/'}) {
  final delegate = factory(gridRoot: gridRoot);
  try {
    final seats = mountedValuesOf<MountedSubstationSeed>(delegate);
    return (
      scopes: List<sdk.SubstationScope>.unmodifiable(
        seats.map((seat) => seat.scope),
      ),
      githubPollingSeatNames: Set<String>.unmodifiable({
        for (final seat in seats)
          if (seat.githubPollingConfigured) seat.scope.name,
      }),
    );
  } finally {
    delegate.dispose();
  }
}

/// Enumerates the CODED roster of the station [factory] authors.
List<sdk.SubstationScope> codedRosterOf(
  SpaceDelegateFactory factory, {
  String gridRoot = '/',
}) => codedRosterSnapshotOf(factory, gridRoot: gridRoot).scopes;

/// The station [factory]'s CODED arming and NAMED environments, read from ONE
/// owned instance (construct → read → dispose — a delegate is a `StateNotifier`,
/// never a throwaway value).
///
/// The [codedRosterOf] precedent, at the same deterministic ABSOLUTE placeholder
/// home (`'/'`): both are CLASS-level policy and independent of the grid home,
/// and neither mounts a tree.
({AgentArming arming, EnvironmentRegistry environments}) codedArmingOf(
  SpaceDelegateFactory factory,
) {
  final delegate = factory(gridRoot: '/');
  try {
    return (arming: delegate.arming, environments: delegate.environments);
  } finally {
    delegate.dispose();
  }
}

/// The station [factory]'s CODED typed resolution, read from ONE owned offline
/// mount (construct → mount → dispose — the [codedArmingOf] precedent) at the
/// deterministic ABSOLUTE placeholder home `'/'`.
///
/// The mount is OFFLINE (`live: false`), so presence is the registry's
/// boot-validated set rather than a live probe pass: this is the CODED
/// resolution the banner reports, not a machine reading.
SeatEnvironments? codedSeatEnvironmentsOf(SpaceDelegateFactory factory) {
  final delegate = factory(gridRoot: '/');
  try {
    return mountedValueOf<SeatEnvironments>(delegate);
  } finally {
    delegate.dispose();
  }
}

/// The delegate seat memento's `space` verbs re-seat over — space_station
/// authored as a Seed.
///
/// Constructed from space's resolved station config (its [gridRoot] home, the
/// operator's [appended] flag seats, the station-default [agentConfig], the
/// work-runtime machinery ([wiring] / [provisioner]), and the [live] posture
/// VALUE). The master [build] authors the v3 §2 tree; `space up` mounts it
/// with `runGrid(this)`.
///
/// ## The extension seam: SUBCLASS and override (extend, never fork)
///
/// A downstream station (an IC's private station) extends this delegate and
/// overrides the designed hooks — the template-method pattern the whole
/// substrate is built on. [substations] is a BUILD METHOD (it carries the
/// master [build]'s context, like any decomposed build), while [stationName]
/// and [umbrella] are identity accessors:
///
///  * [stationName] — the station's identity;
///  * [umbrella] — where the coded org resolves, relative to the grid home;
///  * [environments] — the station's named inference environments;
///  * [arming] — the station's coded typed-environment posture;
///  * [circuitOverrideFor] — bead-scoped non-code routing; null retains the
///    migration-aware code policy;
///  * [buildWorkRegistry] — the resident capability composition, built over
///    the station-owned note appender;
///  * [substations] — THE roster hook: the coded drive set as authored
///    [SubstationSeed] values. Compose, don't replace.
///
/// The per-substation stack is [SubstationSeed] — EXACTLY ONE composed seed class
/// (space-47t; the old `seat(...)` build helper died with it — the
/// helper-method-returns-widget anti-pattern). Stations differ only in the
/// VALUES their [substations] passes (name, root, prefix, an optional
/// [GitHubAppConfig] delivery identity); a different seed class enters only
/// when a substation's STACK genuinely differs — none does yet, so none ships.
///
/// ```dart
/// class LunarDelegate extends SpaceDelegate {
///   LunarDelegate({required super.gridRoot, super.agentConfig, ...});
///   @override
///   String get stationName => 'lunar';
///   @override
///   String get umbrella => '../../engineering.memento';
///   @override
///   List<Seed> substations(
///     TreeContext context,
///     sdk.GridConfiguration configuration,
///   ) => [
///     ...super.substations(context, configuration),
///     SubstationSeed(name: 'butane_flutter', root: '../butane_flutter'),
///   ];
/// }
/// ```
///
/// The subclass's constructor mirrors the base via super-parameters so its
/// tear-off satisfies [SpaceDelegateFactory] — the seam `buildRunner`
/// threads into the composed commands. The off-tree machinery reads the
/// roster by mounting the tree offline (`mountedValuesOf` finds the
/// [MountedSubstationSeed] values UNDER the seed wrappers through
/// [codedRosterSnapshotOf]), so overriding [substations] is the WHOLE change —
/// guard, help, refusal set and specs all follow.
class SpaceDelegate extends sdk.GridDelegate {
  /// Creates the delegate over space's resolved station config.
  /// [agentConfig] defaults to the station's coded [arming] over a claude
  /// ambient scope (what offline mounts — `search`, `assets`, roster
  /// enumeration — need; a live `up` passes its resolved boot value).
  /// [harnesses] defaults to the station's coded [environments]. [provisioner]
  /// is the work runtime's worktree machinery (null ⇒ provisioning no-ops —
  /// the offline authoring, where the worktree layout still resolves — Track
  /// F). [live] is the boot's ONE remaining posture say (space-47t): false —
  /// the default — authors NO effect providers (the inert dry-run tree,
  /// declared by ABSENCE); true has [build] author the commit/push and
  /// PR-opening providers IN-TREE. No effect instance passes through this
  /// constructor.
  SpaceDelegate({
    required this.gridRoot,
    AgentConfig? agentConfig,
    this.appended = const [],
    EnvironmentRegistry? harnesses,
    this.wiring,
    this.provisioner,
    this.githubSelfTrust,
    this.live = false,
  }) : _bootAgentConfig = agentConfig,
       _bootHarnesses = harnesses;

  /// The boot's agent config, as supplied (null ⇒ the coded arming alone).
  final AgentConfig? _bootAgentConfig;

  /// The boot's environment registry, as supplied (null ⇒ [environments]).
  final EnvironmentRegistry? _bootHarnesses;

  /// The station's home (absolute): the `RawAssetGrid` root the [build] tree
  /// roots at; the grid's state store lives under `<gridRoot>/.grid/` (Q5a).
  /// Surfaced through the overridden [root] getter below.
  final String gridRoot;

  /// The station's identity (the `Station` seat's name). OVERRIDE POINT: a
  /// downstream station names itself here.
  String get stationName => 'space';

  /// Where the coded org roster resolves, relative to the grid home (or
  /// absolute). OVERRIDE POINT: space's grid home IS an umbrella member, so
  /// the org repos are its `../` siblings; a downstream station whose grid
  /// home lives elsewhere points this at the umbrella (e.g.
  /// `'../../engineering.memento'`).
  String get umbrella => '..';

  /// Selects a non-code root circuit for [bead], or null to retain the
  /// migration-aware code-circuit policy. OVERRIDE POINT: a downstream station
  /// returns a circuit only for work it owns; null preserves code-shape bounce
  /// protection.
  sdk.Circuit? circuitOverrideFor(Bead bead) => null;

  /// Builds this station's resident work capability registry.
  ///
  /// [appendNote] is backed by the assembled runtime's ownership-checked bead
  /// writer. OVERRIDE POINT: downstream registries pass it to capabilities that
  /// persist operational lines; the code registry does not consume it.
  sdk.CapabilityRegistry buildWorkRegistry(NoteAppender appendNote) =>
      buildCodeRegistry();

  /// The operator's `--substation` flags, parsed into ready [sdk.Substation]
  /// seats — the APPEND layer (Fork B, round 3): they spread AFTER the coded
  /// roster in [build], in flag order. Never a merge, never an override — the
  /// coded roster is changed in code ([substations], the subclass hook).
  final List<sdk.Substation> appended;

  /// The station's NAMED inference environments — memento's semantic names
  /// (`frontier`/`mid`/`cheap`/`codex-frontier`) over the five first-party
  /// builtins. OVERRIDE POINT: a downstream station arms its own set here
  /// (`{...kMementoEnvironments, 'house': ...}`); the NAMES and their meaning
  /// are committed Dart, the machine facts are the site binding's (ADR-0002
  /// D2/D3). No endpoint url appears here.
  EnvironmentRegistry get environments => buildMementoEnvironmentRegistry();

  /// The station's CODED agent arming — the DART rung of the ladder (ADR-0002
  /// D2; ADR-0006 D1/D2): codex builds under a claude committee, expressed as
  /// TYPED preference values. OVERRIDE POINT: a downstream station (lunar)
  /// authors its own posture in code, never through an operator flag (ADR-0002
  /// D4).
  AgentArming get arming => kMementoStationArming;

  /// The station-default agent scope — the GENERIC rung of the agent-config
  /// ladder (`--env`, space-zfg). The station's posture no longer rides this
  /// axis at all: it is expressed as the TYPED seats [arming] mounts, which
  /// out-rank the ambient environment inside `resolveAgentConfig` (ADR-0006
  /// D2/D5). An operator rung is therefore never silently ignored (A20(2)) —
  /// it is simply the LAST rung, under every armed seat.
  late final AgentConfig agentConfig = _bootAgentConfig ?? const AgentConfig();

  /// The station's environment registry, mounted as `HarnessProvider.registry`:
  /// the boot's, else the class's coded [environments].
  late final EnvironmentRegistry harnesses = _bootHarnesses ?? environments;

  /// The station's shared worktree-provisioning service (leased per
  /// substation), built and OWNED by the off-tree work runtime; null ⇒
  /// provisioning no-ops (offline). [build] ADOPTS it over the fan-out as a
  /// `Provider<StationGitService>.value` (STYLE rule 2: `.value` adopts an
  /// instance held by another owner — the runtime — exactly as `StationWork`
  /// adopts the wiring's values); each seat's [GitGridAssets] observes it
  /// individually (the retired `GitServices` bundle's split, space-47t).
  final StationGitService? provisioner;

  /// The station-global SELF-only GitHub trust value.
  ///
  /// Null keeps intake binding absent. The live boot resolves this once through
  /// `gh`; every polling seat observes the same value from the station tree.
  final github.GitHubSelfTrust? githubSelfTrust;

  /// The LIVE posture VALUE — the boot's one remaining say on effects
  /// (space-47t; the old `gitOps`/`prOpener` reference params are retired,
  /// space-00g subsumed). False (dry-run, the default): [build] authors NO
  /// effect providers — inertness is declared in the tree as ABSENCE, visible
  /// in the projection. True: [build] authors the station-level commit/push
  /// (`Provider<GitOps>`) and PR-opening (`Provider<PrOpener>`) effect
  /// providers, constructed IN-TREE via `create:` — tree-owned, never a
  /// pre-built instance threaded through boot.
  final bool live;

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
  /// **The roster is authored in [substations]** (space-6ds, evolved): the
  /// coded drive set is the delegate's OWN override point — literal
  /// [sdk.Substation] seats, each with its root (relative resolved against
  /// the ambient `GridRoot`, tg-32r; absolute used as-is) and the standard
  /// asset stack ([seat]). NOT a manifest file, NOT filesystem discovery —
  /// the roster is code, and changing it is a code change: space edits
  /// [substations] here; a downstream station (extend, never fork) SUBCLASSES
  /// and overrides it.
  ///
  /// **Flags APPEND, never override** (Fork B, round 3): the parsed
  /// `--substation` seats ([appended]) spread AFTER the coded roster, in flag
  /// order. No merge, no override-by-name. A coded sibling absent from this
  /// checkout still mounts its seat (root resolution is pure path math); with
  /// no store controller feeding it (`space up` arms controllers only over
  /// stores that resolve), that seat drives no work.
  ///
  /// Each seat's git is substation-scoped (Track F, re-cut by space-47t):
  /// the seat's [GitGridAssets] and imported GitHub extension WATCH the
  /// station machinery individually — `StationGitService` (adopted from the
  /// work runtime), `GitOps` and `PrOpener` (created IN-TREE here, LIVE arms
  /// only) — and a seat-scoped `Provider<PrOpener>` (a [GitHubAppConfig]
  /// value on the seat, mounted only when the seat OBSERVES the station's
  /// `GitOps` — the live structural signal) shadows the station opener
  /// (ADR-0006 D3: land flows into the substations' GitHub assets, never
  /// through station services).
  /// Under dry-run NONE of the effect providers is authored — by this build
  /// or by an app-bearing seat: the inert posture is provider ABSENCE in
  /// the tree, visible in the projection.
  /// Each seat's fold-child is [sdk.SubstationWork] — the seat the
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
    final git = provisioner;
    final selfTrust = githubSelfTrust;
    // The availability registry (tg-1fa2.5): the seat assets OBSERVE their
    // collaborators (`watch<T>()` — nullable always, absence is a posture),
    // and a watch MISS parks a pending registration with the enclosing
    // ProviderScope. runGrid mounts one at the production root; this tree
    // authors its OWN so every mount of the SAME tree — the offline roster
    // enumeration (`mountedValuesOf`), the test mounts — carries the
    // registry too (the nearest scope wins under runGrid, consistently for
    // every provider and watcher authored below).
    //
    // SHIELDING CONSEQUENCE of the inner scope: a watch miss below parks
    // with THIS registry, never the production root's — so a provider
    // mounted ABOVE this delegate's tree (in runGrid's root scope) notifies
    // the OUTER registry and can never drain a registration parked here.
    // Every provider a seat asset watches (StationGitService, GitOps,
    // PrOpener, GitHubAppConfig) MUST therefore be authored INSIDE this
    // delegate's tree — which they all are: this build and the seats author
    // every one. Do not "help" a seat from above the delegate.
    return sdk.ProviderScope(
      child: sdk.RawAssetGrid(
        root: gridRoot,
        assets: [
          sdk.Station(
            name: stationName,
            root: gridRoot,
            assets: [
              HarnessProvider(
                registry: harnesses,
                config: agentConfig,
                // The availability seed (ADR-0006 D3) — LIVE arms only, the
                // same rule the effect providers below follow: an offline
                // mount (roster enumeration, the suites, a dry run) probes no
                // machine and presence stays the boot-validated registry
                // members (power_station ADR-0000 A35(5)).
                probe: live ? const ProcessEnvironmentProbe().call : null,
                child: Nest(
                  children: [
                    // The TYPED seats (ADR-0006 D2), above the fan-out: every
                    // substation inherits them and a seat shadows per TYPE.
                    TypedEnvironmentProvider(arming: arming),
                    // The station's own resolution, projected for the `up`
                    // banner and the offline suites.
                    const _StationSeatEnvironmentsAssets(),
                    // The work runtime's worktree machinery, ADOPTED (STYLE
                    // rule 2: another owner's instance rides Provider.value;
                    // the runner disposes it, never the tree). Absent ⇒ no
                    // provider — the offline posture is absence.
                    if (git != null) Provider<StationGitService>.value(git),
                    // The EFFECT providers — LIVE arms only (space-47t):
                    // constructed IN-TREE, tree-owned. A dry run authors
                    // NEITHER, so the tree binds no delivery and the dry arm
                    // stays inert BY CONSTRUCTION — inertness declared in
                    // the tree, visible in the projection.
                    if (live) ...[
                      Provider<GitOps>(
                        create: (_) => GitOps(SystemGitRunner()),
                      ),
                      Provider<PrOpener>(
                        create: (_) => GhPrOpener(sdk.ghRunner),
                      ),
                      if (selfTrust != null)
                        Provider<github.GitHubSelfTrust>.value(selfTrust),
                    ],
                    // ARMED: StationWork provides the engine's ambient
                    // work-axis stack above the fan-out (the runGrid→engine
                    // bridge, tg-yl8); UNARMED: H2's authoring-only shape.
                    if (armedWiring != null)
                      sdk.StationWork(wiring: armedWiring),
                  ],
                  child: sdk.Substations(
                    substations: [
                      // ── The CODED roster (space-6ds): the [substations]
                      // build hook — memento's six org seats unless a
                      // subclass overrides. ──
                      ...substations(context, configuration),
                      // ── The append layer (Fork B): `--substation` seats
                      // fan out AFTER the roster, in flag order. ──
                      ...appended,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// THE roster hook — a BUILD METHOD, decomposed out of [build] with its
  /// signature (the template-method idiom the substrate is built on): the
  /// station's coded drive set as authored [SubstationSeed] values, spread
  /// into [build] BEFORE the [appended] layer. Base = the
  /// memento-engineering org, six seats at their [umbrella]-relative roots.
  ///
  /// Returns `List<Seed>` (space-47t): a seed is the COMPOSED wrapper, and
  /// the offline enumeration (`mountedValuesOf` / [codedRosterSnapshotOf])
  /// still finds the [MountedSubstationSeed] values UNDER the wrappers — the
  /// tree stays the single source for `up`'s store guard and work specs, the
  /// codedNames refusal set, and the `--substation` help.
  ///
  /// OVERRIDE POINT: a downstream station composes, it does not replace
  /// blindly — `[...super.substations(context, configuration),
  /// SubstationSeed(name: 'mine', root: '../mine')]`. Identity is the
  /// seed's VALUES; there is no name-keyed lookup anywhere (space-47t).
  List<Seed> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    // the substrate — driven directly (worktrees isolate under
    // .grid/worktrees; main untouched)
    SubstationSeed(name: 'genesis', root: p.join(umbrella, 'genesis')),
    // the framework — self-host; `tg` is the shared Dolt server (gc
    // coexists: read tg's frontier, write sessions to houston — A37)
    SubstationSeed(
      name: 'the_grid',
      root: p.join(umbrella, 'the_grid'),
      prefix: 'tg',
    ),
    // the asset packs — self-host, and the org's EVALUATION seat: its BUILD
    // build seat is armed on `frontier` (claude/opus) while every other seat rides
    // the station's coded `codex-frontier`, so the SAME committee grades both
    // and the environments can be compared instead of guessed at (ADR-0002 D5;
    // D5's worked example arms this seat, in the inverse direction). power_station
    // is the seat where the rubrics and the committee itself are authored, so
    // its builds benefit most from being written by the family that grades them.
    SubstationSeed(
      name: 'power_station',
      root: p.join(umbrella, 'power_station'),
      prefix: 'pow',
      arming: const AgentArming(build: BuildAgentEnvironment(kFrontierLadder)),
    ),
    // the runner — self-host; for space this IS the grid home. Its store
    // mints `space-` (NOT `space_station-`), so the prefix MUST be set
    // explicitly — the default (prefix ?? name) would own `space_station`
    // and drive nothing (ownership matches name OR prefix).
    SubstationSeed(
      name: 'space_station',
      root: p.join(umbrella, 'space_station'),
      prefix: 'space',
    ),
    // the debug harness (memento-engineering/lenny)
    SubstationSeed(name: 'lenny', root: p.join(umbrella, 'lenny')),
    // the decision record (memento-engineering/decisions); its store mints
    // `dec-`, so the prefix differs from the repository name.
    SubstationSeed(
      name: 'decisions',
      root: p.join(umbrella, 'decisions'),
      prefix: 'dec',
    ),
  ];
}

/// Projects the STATION's own typed resolution — the value `up`'s banner
/// prints and [codedSeatEnvironmentsOf] reads off an offline mount. Mounted
/// BELOW the station's [TypedEnvironmentProvider] and ABOVE the fan-out, so it
/// reports the station posture, never a seat's.
final class _StationSeatEnvironmentsAssets extends SingleChildStatelessSeed {
  const _StationSeatEnvironmentsAssets({
    // Nest supplies this fold child; direct call sites deliberately omit it.
    // ignore: unused_element_parameter
    super.child,
  });

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    // WATCH the values this projection is derived from (the D-H build verb).
    context.dependOnInheritedSeedOfExactType<BuildAgentEnvironment>();
    context.dependOnInheritedSeedOfExactType<SpecAgentEnvironment>();
    context.dependOnInheritedSeedOfExactType<CriticAgentEnvironment>();
    context.dependOnInheritedSeedOfExactType<GatherAgentEnvironment>();
    context.dependOnInheritedSeedOfExactType<AvailableEnvironments>();
    return InheritedSeed<SeatEnvironments>(
      value: SeatEnvironments.of(context),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// space's OWN CLI surface — the seat the resident verbs re-seat over.
//
// v3 stores-at-roots (tg-r81): a substation is a name AND its ONE root, paired
// in ONE `--substation <name>=<root>` flag. The coded roster is authored in
// Dart (space-6ds: [SpaceDelegate.substations], overridden by a downstream
// subclass) — flags only APPEND new substations onto it; a coded name on a
// flag is a LOUD refusal (round 3: the roster is changed in code, never by
// config). The state store (and the RS-2 lock) live under the grid home
// (`--grid-home`).
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
  /// lives in [SpaceDelegate.substations], never here). Every appended seat is
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
/// [codedNames] are the composing station's coded seats (enumerated off its
/// delegate's [SpaceDelegate.substations]) — rendered into the `--substation`
/// help so a downstream station's operator reads THEIR coded names, not
/// memento's.
void addSpaceStationFlags(
  ArgParser parser, {
  required List<String> codedNames,
}) {
  parser
    ..addMultiOption(
      'substation',
      abbr: 'r',
      help:
          'A NEW substation to APPEND onto the coded roster '
          '(${codedNames.join(', ')}), paired: '
          '`--substation <name>[@<prefix>]=<root>` (repeatable, absolute '
          'root). Append-only: a coded name is refused — the coded roster is '
          "authored in the station delegate's substations() and changed in "
          'code, never by flags. A substation is a name and ONE root (v3 §0) '
          '— its '
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
/// [sdk.Substation] seat carrying the GIT half of the substation stack —
/// `Nest[GitGridAssets] → SubstationWork` (provisioning observed from the
/// ambient `Provider<StationGitService>`). The GitHub delivery node is
/// deliberately ABSENT: PR-opening for an appended substation waits until it
/// is CODED into the roster (round 3: flags append a seat, they do not rewire
/// one), and under the composed assets that policy is authored STRUCTURALLY —
/// no imported GitHub extension node, so no delivery can bind even on
/// a live arm. Throws [FormatException] on a malformed pairing (no `=`, empty
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
        // INNERMOST — see SubstationSeed: GitGridAssets rebuilds the bundle
        // from scratch, so the gate must derive from it, not above it.
        children: [GitGridAssets(), MountEligibilityAssets()],
        child: sdk.SubstationWork(),
      ),
    ],
  );
}

/// Builds [SpaceStationConfig] from space's own flags ([addSpaceStationFlags]).
/// The CODED roster is authored in the station delegate's
/// [SpaceDelegate.substations] and consumed by [SpaceDelegate.build] — it
/// never arrives through here; [codedNames] (the same seats' names,
/// enumerated by the caller) is the refusal set. `--substation` flags parse
/// into APPENDED seats ([SpaceStationConfig.appended]); a flag naming a CODED
/// substation is a loud [FormatException] (round 3: the roster is code, never
/// overridden by config), as is the same name twice. A missing --grid-home is
/// a null return, which the verb renders as a LOUD arming refusal (never a
/// `''` sentinel — v3 kills those); the coded roster is never empty, so the
/// old "no substation ⇒ refuse" gate stays retired.
SpaceStationConfig? spaceStationConfigFrom(
  ArgResults args, {
  required Set<String> codedNames,
}) {
  final gridHome = (args.option('grid-home') ?? args.option('state-workspace'))
      ?.trim();
  if (gridHome == null || gridHome.isEmpty) return null;

  final appended = <sdk.Substation>[];
  final seen = <String>{};
  for (final raw in args.multiOption('substation')) {
    if (raw.trim().isEmpty) continue;
    final s = _parseSubstation(raw);
    if (codedNames.contains(s.name)) {
      throw FormatException(
        'space up: --substation "$raw" names the CODED substation "${s.name}" '
        "— the coded roster is authored in the station delegate's "
        'substations() and never overridden by flags (change the roster in '
        'code); flags APPEND new substations only',
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
