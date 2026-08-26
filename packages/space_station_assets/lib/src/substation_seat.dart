/// The COMPOSED SEAT (space-47t) — the tg-1fa2 composition model adopted for
/// space's substations.
///
/// The old `SpaceDelegate.seat(...)` helper was the helper-method-returns-widget
/// anti-pattern: no identity in reconcile, no scope for providers, an override
/// point by convention rather than by type. It is replaced by EXACTLY ONE
/// composed seat class — [SubstationSeat], a `StatelessSeed` carrying VALUE
/// config — plus the local [GitGridAssets] and imported
/// `github.GitHubGridAssets` seat-stack assets. They OBSERVE collaborators via
/// the tree (`the_grid/docs/STYLE.md` rules 3–4).
///
/// **Per-seat identity is COMPOSITION, never lookup**: there is no
/// `deliveryFor(name)`, no stringy seat registry of any kind. A seat's delivery
/// posture is what its OWN subtree mounts. A [GitHubAppConfig] value selects
/// App-authenticated delivery on a live seat; no value preserves the nearest
/// ambient opener. Polling is independently and explicitly selected by the
/// seat's reconciler config.
///
/// **The `GitServices` bundle is SPLIT** (STYLE rule 4: no provider is
/// universal): the assets watch `StationGitService` and `GitOps` individually,
/// so a non-git seat composes a stack without either — unavailability is a
/// designed posture, projected into the tree, never an error.
///
/// The GitHub binding and reconciler lifecycle belong to `github_grid_assets`.
/// This library composes those imported extensions but exports only
/// [SubstationSeat] and [GitHubAppConfig] downstream.
library;

import 'package:beads_dart/beads_dart.dart' show ProcessBdRunner;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart' as github;
import 'package:grid_assets/grid_assets.dart'
    show GitSourceControl, MountEligibilityAssets;
import 'package:grid_engine/grid_engine.dart' show ServiceBundle;
import 'package:grid_runtime/grid_runtime.dart'
    show GitOps, RootCheckout, StationGitService;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_sdk/grid_sdk.dart' show Provider, ProviderTreeContext;

/// A GitHub App DELIVERY IDENTITY — config identity ONLY, a plain value type.
///
/// Carries the non-secret identifiers a live seat uses to select
/// `github.GitHubAppPrOpener`. The injected authenticated client owns secrets
/// and resolves them at effect time; this value deliberately has nowhere to
/// store one. A null seat identity preserves ambient-opener behavior.
class GitHubAppConfig {
  /// Creates the identity value.
  const GitHubAppConfig({
    required this.appId,
    required this.installationId,
    required this.privateKeyVar,
  });

  /// The GitHub App identifier used by App-authenticated PR delivery.
  final String appId;

  /// The installation whose access tokens delivery acts under.
  final String installationId;

  /// The configured NAME for the App private key.
  ///
  /// This library does not read the environment. The injected authenticated
  /// client owns secret resolution at effect time.
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
/// `Substation[Nest[GitGridAssets → optional reconciler provider → imported
/// GitHubGridAssets] → SubstationWork]`. A non-null [githubPoll] is the only
/// polling opt-in: coordinates are never inferred from a remote or station
/// default. The imported provider constructs a runtime only for a live arm.
/// A live [app] selects App-authenticated PR delivery; null preserves the
/// nearest ambient opener unchanged. Dry and offline arms create neither a
/// seat-scoped opener nor a reconciler runtime.
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
    this.githubPoll,
    this.landingPolicy,
    this.githubAppCredentialLoader = const github.GitHubAppCredentialLoader(),
    this.githubTransportFactory = github.createGitHubHttpTransport,
    Key? key,
  }) : super(key: key ?? ValueKey<String>('seat:$name'));

  /// The substation's name (its tree identity).
  final String name;

  /// The substation's ONE root — absolute, or relative to the ambient
  /// `GridRoot` (resolved by the SDK's own `Substation` build, tg-32r).
  final String root;

  /// The work store's issue-id prefix; null ⇒ the name (the SDK default).
  final String? prefix;

  /// The seat's delivery identity. On a live seat, non-null selects the
  /// App-authenticated opener; null preserves ambient-opener behavior.
  final GitHubAppConfig? app;

  /// Explicit polling values for this seat; null keeps reconciliation absent.
  ///
  /// The owner and repository are consumed exactly as authored. They are never
  /// inferred from [root], a git remote, the environment, or station defaults.
  final github.GitHubReconcilerConfig? githubPoll;

  /// The seat's explicitly selected GitHub landing posture.
  ///
  /// Null preserves `github.GitHubGridAssets`' default
  /// `github.PrNoMergePolicy`: open or reuse a PR and leave it unmerged.
  final github.GitHubDeliveryPolicy? landingPolicy;

  /// Loads this seat's App private key; injectable for deterministic tests.
  final github.GitHubAppCredentialLoader githubAppCredentialLoader;

  /// Creates this seat's GitHub transport; injectable for deterministic tests.
  final github.GitHubHttpTransportFactory githubTransportFactory;

  @override
  Seed build(TreeContext context) {
    final githubPoll = this.githubPoll;
    final landingPolicy = this.landingPolicy;
    final children = <SingleChildSeed>[
      const GitGridAssets(),
      if (githubPoll != null &&
          githubPoll.arm == github.GitHubReconcilerArm.live)
        _SeatGitHubReconcilerBindingAssets(config: githubPoll),
      if (githubPoll != null) github.GitHubReconcilerAssets(config: githubPoll),
      github.GitHubGridAssets(policy: landingPolicy),
      const MountEligibilityAssets(),
    ];
    final substation = sdk.Substation(
      name,
      root,
      prefix: prefix,
      assets: [
        Nest(
          // MountEligibilityAssets is INNERMOST on purpose: GitGridAssets
          // builds a FRESH ServiceBundle and preserves nothing from ambient,
          // so a gate mounted above it would be silently clobbered and the
          // predicate would never reach SubstationWork. This seed derives FROM
          // the ambient bundle — it copies sourceControl/delivery/escalation/
          // trust/transport forward and adds the predicate.
          children: children,
          child: const sdk.SubstationWork(),
        ),
      ],
    );
    final identity = app;
    if (identity == null) return substation;
    final ops = context.watch<GitOps>();
    final pollAllowsEffects =
        githubPoll == null || githubPoll.arm == github.GitHubReconcilerArm.live;
    final openerWired = ops == null || !pollAllowsEffects
        ? substation
        : github.GitHubPrOpenerAssets(
            config: github.GitHubAppConfig(
              appId: identity.appId,
              installationId: int.parse(identity.installationId),
            ),
            owner: githubPoll?.owner,
            repository: githubPoll?.repository,
            child: substation,
          );
    final clientWired = !pollAllowsEffects
        ? openerWired
        : github.GitHubAppClientAssets(
            config: github.GitHubAppConfig(
              appId: identity.appId,
              installationId: int.parse(identity.installationId),
            ),
            privateKeyVar: identity.privateKeyVar,
            credentialLoader: githubAppCredentialLoader,
            transportFactory: githubTransportFactory,
            child: openerWired,
          );
    return Provider<GitHubAppConfig>.value(identity, child: clientWired);
  }
}

final class _SeatGitHubReconcilerBindingAssets
    extends SingleChildStatelessSeed {
  const _SeatGitHubReconcilerBindingAssets({
    required this.config,
    // Nest supplies this fold child; direct call sites deliberately omit it.
    // ignore: unused_element_parameter
    super.child,
  });

  final github.GitHubReconcilerConfig config;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final trust = context.watch<github.GitHubSelfTrust>();
    if (trust == null) return child;
    final scope = sdk.SubstationScope.of(context);
    return github.GitHubReconcilerBindingAssets(
      config: config,
      runner: ProcessBdRunner(workspaceRoot: scope.root),
      trust: trust,
      child: child,
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
    return _DerivedBundleSeed(
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
      derivedFrom: [provisioner, scope.root, scope.name, defaultBranch, remote],
      child: child,
    );
  }
}

/// An `InheritedSeed<ServiceBundle>` that notifies on its DERIVATION INPUTS,
/// not on bundle instance identity.
///
/// The watch-based assets re-DERIVE a fresh [ServiceBundle] on every rebuild
/// (that re-derivation is the whole point of space-47t: a later provider
/// mount must flip the bundle live), but `ServiceBundle` has no value
/// equality, so the plain `InheritedSeed.updateShouldNotify`
/// (`value != oldSeed.value`) would notify every dependent on every no-op
/// re-description — and `grid_engine`'s `WorkList` documents its ambient
/// bundle as a config-axis dependency that never notifies once mounted
/// (derailment-invariant 1). The bundle's own collaborators hide their
/// constructor inputs behind private fields, so equality cannot be computed
/// on the VALUE from here; instead each construction site passes the exact
/// inputs the bundle was derived from ([derivedFrom], compared element-wise
/// with `==` — identity for services, value equality for strings/knobs), and
/// an input-equal re-derivation does NOT notify. A REAL flip (a provider
/// mounting or unmounting, a root change) changes an input and notifies as
/// before.
///
/// NOTE for the engine follow-on: `WorkList`'s "fixed-at-mount, never
/// notifies" invariant text predates the watch-based assets; value equality
/// on `ServiceBundle` itself (grid_engine) would let this wrapper retire.
class _DerivedBundleSeed extends InheritedSeed<ServiceBundle> {
  const _DerivedBundleSeed({
    required super.value,
    required this.derivedFrom,
    required super.child,
  });

  /// The inputs [value] was derived from, in a fixed site-specific order.
  final List<Object?> derivedFrom;

  @override
  bool updateShouldNotify(InheritedSeed<ServiceBundle> oldSeed) {
    if (oldSeed is! _DerivedBundleSeed) return true;
    final old = oldSeed.derivedFrom;
    if (old.length != derivedFrom.length) return true;
    for (var i = 0; i < derivedFrom.length; i++) {
      if (derivedFrom[i] != old[i]) return true;
    }
    return false;
  }
}
