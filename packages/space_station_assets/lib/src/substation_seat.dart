/// The COMPOSED SEAT (space-47t) — the tg-1fa2 composition model adopted for
/// space's substations.
///
/// The old `SpaceDelegate.seat(...)` helper was the helper-method-returns-widget
/// anti-pattern: no identity in reconcile, no scope for providers, an override
/// point by convention rather than by type. It is replaced by EXACTLY ONE
/// composed seat class — [SubstationSeat], a `StatelessSeed` carrying VALUE
/// config — plus the seat-stack assets it composes ([GitGridAssets] /
/// [GitHubGridAssets]), which are `const` and OBSERVE their collaborators via
/// `context.watch` (`the_grid/docs/STYLE.md` rules 3–4) instead of receiving
/// them through constructor threading.
///
/// **Per-seat identity is COMPOSITION, never lookup**: there is no
/// `deliveryFor(name)`, no stringy seat registry of any kind. A seat's delivery
/// posture is what its OWN subtree mounts — a [GitHubAppConfig] value mounts a
/// `Provider<PrOpener>` over the seat; no value mounts NO provider, and the
/// commit-only posture is that ABSENCE (never a null-valued provider).
///
/// **The `GitServices` bundle is SPLIT** (STYLE rule 4: no provider is
/// universal): the assets watch `StationGitService` and `GitOps` individually,
/// so a non-git seat composes a stack without either — unavailability is a
/// designed posture, projected into the tree, never an error.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show GitHubPrDelivery, GitSourceControl, PrComposition;
import 'package:grid_engine/grid_engine.dart' show ServiceBundle;
import 'package:grid_runtime/grid_runtime.dart'
    show GhPrOpener, GitOps, PrOpener, RootCheckout, StationGitService;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_sdk/grid_sdk.dart' show Provider, ProviderTreeContext;

/// A GitHub App DELIVERY IDENTITY — config identity ONLY, a plain value type.
///
/// Carries the non-secret identifiers a seat's delivery acts as: the app id,
/// the installation id, and the NAME of the environment variable the private
/// key resolves from. Secrets resolve from the environment at EFFECT time —
/// they are never stored in config, beads, or argv, and this type deliberately
/// has nowhere to put one.
class GitHubAppConfig {
  /// Creates the identity value.
  const GitHubAppConfig({
    required this.appId,
    required this.installationId,
    required this.privateKeyVar,
  });

  /// The GitHub App identifier (the JWT issuer of the future authenticated
  /// exchange — `github_grid_assets`' token provider).
  final String appId;

  /// The installation whose access tokens delivery acts under.
  final String installationId;

  /// The NAME of the environment variable holding the app's private key — the
  /// name is config; the VALUE is read from the environment at effect time,
  /// never here.
  final String privateKeyVar;

  @override
  bool operator ==(Object other) =>
      other is GitHubAppConfig &&
      other.appId == appId &&
      other.installationId == installationId &&
      other.privateKeyVar == privateKeyVar;

  @override
  int get hashCode => Object.hash(appId, installationId, privateKeyVar);

  @override
  String toString() =>
      'GitHubAppConfig(appId: $appId, installationId: $installationId, '
      'privateKeyVar: $privateKeyVar)';
}

/// THE composed seat — one substation of the composing station, authored as a
/// value-configured `StatelessSeed` (space-47t; ADR-0008 D2: a seed that
/// BUILDS a `Substation`, never subclasses it).
///
/// One class, deliberately without an org/personal split: a type distinction
/// with no behavioral contrast is the `Resident*` mistake again (tg-at3r). Org
/// and personal stations differ only in the VALUES their `substations()`
/// passes. A SUBCLASS (or sibling seat class) enters only when a seat's STACK
/// genuinely differs — none exists yet, so none ships.
///
/// [build] mounts the standard stack —
/// `Substation[Nest[GitGridAssets → GitHubGridAssets] → SubstationWork]` — and,
/// when [app] is non-null, a `Provider<PrOpener>` OVER it: constructed IN-TREE
/// via `create:` (tree-owned — STYLE rule 2), scoped to THIS seat, shadowing
/// any station-level opener. When [app] is null NO provider mounts: the
/// commit-only posture is declared by ABSENCE in the tree, visible in the
/// projection. Per-seat delivery therefore never passes through boot
/// (space-00g, subsumed).
class SubstationSeat extends StatelessSeed {
  /// Creates the seat over its VALUE config. [prefix] defaults to [name]
  /// downstream (the `sdk.Substation` default); [app] is the seat's delivery
  /// identity — null ⇒ commit-only by absence.
  ///
  /// Carries an intrinsic identity key (`ValueKey('seat:<name>')`) unless
  /// [key] overrides it, mirroring `sdk.Substation`'s own name-keyed
  /// reconcile: sibling seats reconcile by NAME, never by position.
  SubstationSeat({
    required this.name,
    required this.root,
    this.prefix,
    this.app,
    Key? key,
  }) : super(key: key ?? ValueKey<String>('seat:$name'));

  /// The substation's name (its tree identity).
  final String name;

  /// The substation's ONE root — absolute, or relative to the ambient
  /// `GridRoot` (resolved by the SDK's own `Substation` build, tg-32r).
  final String root;

  /// The work store's issue-id prefix; null ⇒ the name (the SDK default).
  final String? prefix;

  /// The seat's delivery identity. Non-null mounts a seat-scoped
  /// `Provider<PrOpener>`; null mounts NOTHING (commit-only by absence).
  final GitHubAppConfig? app;

  @override
  Seed build(TreeContext context) {
    final substation = sdk.Substation(
      name,
      root,
      prefix: prefix,
      assets: const [
        Nest(
          children: [GitGridAssets(), GitHubGridAssets()],
          child: sdk.SubstationWork(),
        ),
      ],
    );
    final delivery = app;
    // Commit-only by ABSENCE: no identity value ⇒ no provider node at all —
    // the inert posture is structural, not a null-valued provider.
    if (delivery == null) return substation;
    return Provider<PrOpener>(
      // Constructed IN-TREE, tree-owned (never a pre-built instance through
      // create: — STYLE rule 2). The opener shells `gh`, whose credentials
      // resolve from the ENVIRONMENT at effect time; [delivery] is the seat's
      // declared app identity — the value the authenticated GitHub App client
      // (`github_grid_assets`, pow #104) consumes when its token exchange is
      // composed into the opener seam. Identity in config; secrets at effect.
      create: (context) => GhPrOpener(sdk.ghRunner),
      child: substation,
    );
  }
}

/// **GitGridAssets** — the substation-scoped SOURCE-CONTROL asset (v3 §3),
/// `const` and WATCHING (space-47t).
///
/// Mounted under the `Substation` it serves, it reads that substation's
/// ambient [sdk.SubstationScope] (name + ONE root), OBSERVES the station's
/// worktree-provisioning machinery individually — `watch<StationGitService>()`,
/// the split of the retired `GitServices` bundle — and provides the git
/// [ServiceBundle] to the work subtree. A null observation is the offline /
/// dry-run posture: provisioning no-ops while `workspaceFor`/`branchFor`/
/// `baseBranch` still resolve from the root (the layout is deterministic and
/// pure). A provider mounting later rebuilds this node through the
/// availability registry (STYLE rule 3), re-deriving the source control over
/// the live machinery.
///
/// It PROVISIONS but binds NO delivery: the provided bundle carries a null
/// `delivery` (commit-only) until [GitHubGridAssets] below binds one.
class GitGridAssets extends SingleChildStatelessSeed {
  /// Creates the git asset for the enclosing substation's root; [child] is
  /// supplied by an enclosing [Nest] (or set for standalone use).
  const GitGridAssets({
    this.defaultBranch = 'main',
    this.remote = 'origin',
    super.child,
    super.key,
  });

  /// The base branch per-bead worktrees rebase/PR against. A live
  /// `StationGitService.registerRootCheckout` PROBES this from `origin/HEAD`;
  /// an offline asset authors it (defaulting to `main`).
  final String defaultBranch;

  /// The push remote (default `origin`).
  final String remote;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    // bead → substation → root: the substation's ambient scope names its ONE
    // root. `.of` refuses LOUD when no `Substation` encloses — an asset
    // mounted outside a substation is an authoring error, not a default.
    final scope = sdk.SubstationScope.of(context);
    // The SPLIT observation (STYLE rules 3–4): the provisioning half alone,
    // nullable always — absence is the offline posture, and a later provider
    // mount flips this node live through the pending-registry rebuild.
    final provisioner = context.watch<StationGitService>();
    return InheritedSeed<ServiceBundle>(
      // ONE source control, resolved by TREE POSITION (never a name keyed
      // into a map). No delivery bound — GitHubGridAssets binds it below.
      value: ServiceBundle(
        sourceControl: GitSourceControl(
          provisioner: provisioner,
          root: RootCheckout(
            path: scope.root,
            substation: scope.name,
            defaultBranch: defaultBranch,
            remote: remote,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// **GitHubGridAssets** — the substation-scoped asset that BINDS the GitHub
/// DELIVERY METHOD onto the substation's git bundle (v3 §3), `const` and
/// WATCHING (space-47t): the `prOpener`/`gitOps` constructor params are GONE.
///
/// Authored BELOW [GitGridAssets] in the seat's `Nest`. It OBSERVES the
/// ambient [ServiceBundle] the git asset provided, and the two delivery
/// halves INDIVIDUALLY — `watch<PrOpener>()` and `watch<GitOps>()` (the
/// `GitServices` split). Null opener = the commit-only posture; a value =
/// delivery-bound. A provider mounting later flips the posture live through
/// the availability registry's pending rebuild (grid_engine
/// Provider/ProviderScope semantics); an unmounting one flips it back.
///
/// Fail-safe: delivery binds only when BOTH halves are observed — GitHub can
/// only ADD delivery to a checkout it can commit from, never conjure one.
/// With either absent the ambient bundle passes through unchanged.
class GitHubGridAssets extends SingleChildStatelessSeed {
  /// Creates the GitHub asset over the optional [composition] PR-shaping
  /// value; [child] is supplied by an enclosing [Nest].
  const GitHubGridAssets({this.composition, super.child, super.key});

  /// The substation's PR title/body composition knob (pow-8dx) — a VALUE,
  /// mounted as `InheritedSeed<PrComposition>` independently of the delivery
  /// binding. Null ⇒ nothing mounted; consumers fall back to
  /// `const PrComposition()`.
  final PrComposition? composition;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    // OBSERVE the ambient bundle (a non-subscribing get would re-provide a
    // bundle wrapping a STALE source control after GitGridAssets rebuilds).
    final ambient = context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    // The SPLIT observations — each half individually, nullable always
    // (STYLE rule 3): the seat's own Provider<PrOpener> (a GitHubAppConfig
    // value) is the nearest opener; a station-level one (the live arm's
    // ambient effect providers) reaches here otherwise; none is commit-only.
    final ops = context.watch<GitOps>();
    final opener = context.watch<PrOpener>();
    final knob = composition;

    var wired = child;
    // BOTH halves, or nothing is bound (commit-only).
    if (ops != null && opener != null) {
      wired = InheritedSeed<ServiceBundle>(
        // Carry through EVERY field the bundle declares — silently dropping
        // one here would unbind an unrelated service.
        value: ServiceBundle(
          sourceControl: ambient?.sourceControl,
          delivery: GitHubPrDelivery(
            gitOps: ops,
            prOpener: opener,
            composition: knob ?? const PrComposition(),
          ),
          escalation: ambient?.escalation,
          trust: ambient?.trust,
          transport: ambient?.transport,
        ),
        child: child,
      );
    }
    // The composition knob mounts INDEPENDENTLY of the delivery binding (it
    // is a VALUE, not a service).
    return knob == null
        ? wired
        : InheritedSeed<PrComposition>(value: knob, child: wired);
  }
}
