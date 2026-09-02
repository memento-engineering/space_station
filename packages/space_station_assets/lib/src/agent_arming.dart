/// The station's AGENT ARMING — which inference environment each TYPED SEAT
/// runs on, authored as committed Dart (power_station
/// `docs/adr/ADR-0002-agent-environment-layer.md` D2 DART-FIRST, D5 the
/// per-substation rung; `docs/adr/ADR-0006-typed-environment-lookup-selects-by-value.md`
/// D1/D2 the VALUE-keyed typed rung).
///
/// The ladder is: station default -> substation seat -> bead (`grid.agent`) ->
/// step (`StepArgs.params`). This library owns the top TWO rungs as pure
/// VALUES ("config = VALUES in the tree; impls are DI"): [kMementoStationArming]
/// is the station's, and a [SubstationSeed]'s own [AgentArming] nests UNDER it.
/// Selection is by TYPE and VALUE — there is no role map, no name key and no
/// operator-flag rung (ADR-0002 D4). NO endpoint url appears in this file:
/// WHERE an environment runs is its own `InferenceTarget`, bound on the box by
/// the machine-local site binding (ADR-0002 D3).
///
/// ## Why every environment here is a COMPLETE, standalone `const`
///
/// ADR-0006 D1 requires the canned preference sets to be "const Dart declared
/// beside the environments". `AvailableEnvironments.contains` and
/// `EnvironmentRegistry.nameOf` compare in the `AgentEnvironment.flattened`
/// normal form, which reconciles `base` but does NOT fill in fields a layer
/// never declared — so a layer that INHERITS its transport from a builtin is
/// not equal to the registry's resolution of itself, and a const preference
/// over such a layer resolves to nothing. Each environment is therefore
/// declared ONCE, complete, with `base: EnvBaseStandalone()`, and that same
/// value is both the registry's `custom` entry and the preference entry.
/// Transport drift against `kBuiltinEnvironments` is fenced by the parity test
/// in `test/agent_arming_test.dart` (it goes RED on a deliberate grid_assets
/// bump) and by [preferenceArmingRefusal] at boot. Recorded at
/// `docs/decisions/2026-09-02-memento-s-named-environments-are-complete-const-values.md`.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentEnvironment,
        AvailableEnvironments,
        BuildAgentEnvironment,
        CriticAgentEnvironment,
        CriticEnvironmentSeed,
        EnvBaseStandalone,
        EnvironmentRegistry,
        GatherAgentEnvironment,
        InferenceTarget,
        ModelPreference,
        PromptMode,
        SpecAgentEnvironment,
        kBuiltinEnvironments,
        resolveEnvironment;

/// Build strong: claude at the frontier tier. COMPLETE and standalone (see the
/// library doc): the transport fields mirror `kBuiltinEnvironments['claude']`.
const AgentEnvironment kFrontierEnvironment = AgentEnvironment(
  base: EnvBaseStandalone(),
  command: 'claude',
  args: ['--dangerously-skip-permissions'],
  promptMode: PromptMode.flag,
  promptFlag: '-p',
  target: InferenceTarget.providerManaged,
  usageJsonArgs: ['--output-format', 'json'],
  resumeFlag: '--resume',
  model: 'opus',
);

/// Grade: claude at the mid tier.
const AgentEnvironment kMidEnvironment = AgentEnvironment(
  base: EnvBaseStandalone(),
  command: 'claude',
  args: ['--dangerously-skip-permissions'],
  promptMode: PromptMode.flag,
  promptFlag: '-p',
  target: InferenceTarget.providerManaged,
  usageJsonArgs: ['--output-format', 'json'],
  resumeFlag: '--resume',
  model: 'sonnet',
);

/// Gather: claude at the cheap tier.
const AgentEnvironment kCheapEnvironment = AgentEnvironment(
  base: EnvBaseStandalone(),
  command: 'claude',
  args: ['--dangerously-skip-permissions'],
  promptMode: PromptMode.flag,
  promptFlag: '-p',
  target: InferenceTarget.providerManaged,
  usageJsonArgs: ['--output-format', 'json'],
  resumeFlag: '--resume',
  model: 'haiku',
);

/// The org's BUILD environment: codex on its own native pin (a claude tier name
/// 400s on codex), driven through the ACP adapter.
const AgentEnvironment kCodexFrontierEnvironment = AgentEnvironment(
  base: EnvBaseStandalone(),
  command: 'npx',
  args: ['-y', '@agentclientprotocol/codex-acp@1.6.2'],
  env: {'INITIAL_AGENT_MODE': 'agent-full-access'},
  promptMode: PromptMode.none,
  target: InferenceTarget.providerManaged,
  model: 'gpt-5.6-sol',
  sessionAdapter: 'acp',
);

/// memento's NAMED environments — the station's own SEMANTIC names. A name is
/// a PORTABLE promise ("build strong", "grade mid") a bead or a step may still
/// use; the typed rung above it needs no name at all.
const Map<String, AgentEnvironment> kMementoEnvironments = {
  'frontier': kFrontierEnvironment,
  'mid': kMidEnvironment,
  'cheap': kCheapEnvironment,
  'codex-frontier': kCodexFrontierEnvironment,
};

/// The station's environment REGISTRY: [kMementoEnvironments] as `custom`, the
/// five first-party environments as `builtins`.
EnvironmentRegistry buildMementoEnvironmentRegistry() =>
    const EnvironmentRegistry(
      custom: kMementoEnvironments,
      builtins: kBuiltinEnvironments,
    );

/// Build strong, fall back to mid — the canned FRONTIER ladder (ADR-0006 D1:
/// an ordered preference over complete environment VALUES, most-preferred
/// first).
const List<AgentEnvironment> kFrontierLadder = [
  kFrontierEnvironment,
  kMidEnvironment,
];

/// Grade mid, fall back to cheap.
const List<AgentEnvironment> kMidLadder = [kMidEnvironment, kCheapEnvironment];

/// Gather cheap, fall back to mid.
const List<AgentEnvironment> kCheapLadder = [
  kCheapEnvironment,
  kMidEnvironment,
];

/// Build on codex, fall back to claude at the frontier tier when codex is not
/// present on this box.
const List<AgentEnvironment> kCodexLadder = [
  kCodexFrontierEnvironment,
  kFrontierEnvironment,
];

/// One ARMING of the TYPED environment seats — a station's or a seat's say in
/// which environment each capability runs on. A pure VALUE; it carries no
/// behavior and reaches no service. A null field leaves that seat to the
/// nearest ancestor's arming (ADR-0006 D2: the TYPE is the scope).
class AgentArming {
  /// Creates an arming over the seats it names; every field is optional.
  const AgentArming({this.build, this.spec, this.critic, this.gather});

  /// The BUILD seat (the coding agent).
  final BuildAgentEnvironment? build;

  /// The SPEC seat (the architect / specify stage).
  final SpecAgentEnvironment? spec;

  /// The CRITIC seat (every committee lane), with optional per-lane overrides.
  final CriticAgentEnvironment? critic;

  /// The GATHER seat (the read-only discovery explorers).
  final GatherAgentEnvironment? gather;

  /// Whether this arming says nothing at all.
  bool get isEmpty =>
      build == null && spec == null && critic == null && gather == null;

  /// The armed seats, BUILD first — the order [preferenceArmingRefusal] walks.
  Iterable<ModelPreference> get seats => [
    if (build != null) build!,
    if (spec != null) spec!,
    if (critic != null) critic!,
    if (gather != null) gather!,
  ];

  @override
  bool operator ==(Object other) =>
      other is AgentArming &&
      other.build == build &&
      other.spec == spec &&
      other.critic == critic &&
      other.gather == gather;

  @override
  int get hashCode => Object.hash(build, spec, critic, gather);

  @override
  String toString() =>
      'AgentArming(build: $build, spec: $spec, critic: $critic, '
      'gather: $gather)';
}

/// Provides an [arming]'s TYPED seats over its subtree — the ONE seed both the
/// station rung and the per-substation rung mount (ADR-0002 D5, ADR-0006 D2).
///
/// A NESTED instance shadows only the types it arms: an unarmed seat keeps
/// resolving through the enclosing provider, because `resolveEnvironment`
/// reads by EXACT type and finds the nearest ancestor of that type.
final class TypedEnvironmentProvider extends SingleChildStatelessSeed {
  /// Provides [arming]'s seats over [child].
  const TypedEnvironmentProvider({
    required this.arming,
    super.child,
    super.key,
  });

  /// The seats this provider mounts.
  final AgentArming arming;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    var below = child;
    final gather = arming.gather;
    if (gather != null) {
      below = InheritedSeed<GatherAgentEnvironment>(
        value: gather,
        child: below,
      );
    }
    final critic = arming.critic;
    if (critic != null) {
      // CriticEnvironmentSeed, not a plain InheritedSeed: a BUILD-time
      // dependent may scope its invalidation to ONE CriticLane. Spawn edges
      // read the same value with the effect verb and pay nothing for it.
      below = CriticEnvironmentSeed(value: critic, child: below);
    }
    final spec = arming.spec;
    if (spec != null) {
      below = InheritedSeed<SpecAgentEnvironment>(value: spec, child: below);
    }
    final build = arming.build;
    if (build != null) {
      below = InheritedSeed<BuildAgentEnvironment>(value: build, child: below);
    }
    return below;
  }
}

/// The four typed lookups RESOLVED at one point in the tree — the offline
/// projection the `up` banner prints and the suites assert. A pure VALUE.
final class SeatEnvironments {
  /// Creates the projection over its four resolved environments.
  const SeatEnvironments({this.build, this.spec, this.critic, this.gather});

  /// Resolves all four seats at [context] through the VENDED resolvers (one
  /// availability walk each). These are effect-boundary reads
  /// (`getInheritedSeedOfExactType`), so a caller that runs this inside a
  /// `build` subscribes to the same values FIRST with `dependOn*` — the D-H
  /// doctrine (ADR-0008 D3; power_station ADR-0000 A8(3)/A35(6)).
  factory SeatEnvironments.of(TreeContext context) => SeatEnvironments(
    build: resolveEnvironment<BuildAgentEnvironment>(context),
    spec: resolveEnvironment<SpecAgentEnvironment>(context),
    critic: CriticAgentEnvironment.of(context),
    gather: resolveEnvironment<GatherAgentEnvironment>(context),
  );

  /// The BUILD seat's resolved environment; null when nothing is armed or
  /// nothing preferred is present (the caller falls to the ambient rung).
  final AgentEnvironment? build;

  /// The SPEC seat's resolved environment.
  final AgentEnvironment? spec;

  /// The CRITIC seat's resolved environment (the shared, laneless preference).
  final AgentEnvironment? critic;

  /// The GATHER seat's resolved environment.
  final AgentEnvironment? gather;

  /// This projection rendered with [registry]'s NAMES — the banner line. The
  /// name is restored at the boundary exactly as `resolveAgentConfig` does it
  /// (`EnvironmentRegistry.nameOf`; power_station ADR-0000 A35(2)).
  String describe(EnvironmentRegistry registry) {
    String named(AgentEnvironment? environment) =>
        environment == null ? '<ambient>' : registry.nameOf(environment);
    return 'build ${named(build)}  ·  spec ${named(spec)}  ·  '
        'critic ${named(critic)}  ·  gather ${named(gather)}';
  }

  @override
  bool operator ==(Object other) =>
      other is SeatEnvironments &&
      other.build == build &&
      other.spec == spec &&
      other.critic == critic &&
      other.gather == gather;

  @override
  int get hashCode => Object.hash(build, spec, critic, gather);

  @override
  String toString() =>
      'SeatEnvironments(build: $build, spec: $spec, critic: $critic, '
      'gather: $gather)';
}

/// memento's CODED station posture: codex BUILDS under a claude committee.
///
/// Every seat is armed, so every invocation is assignable and none silently
/// rides the ambient rung. A seat overrides ONE type by nesting its own
/// [AgentArming]; `--env` selects only the GENERIC default below all four.
const AgentArming kMementoStationArming = AgentArming(
  build: BuildAgentEnvironment(kCodexLadder),
  spec: SpecAgentEnvironment(kFrontierLadder),
  critic: CriticAgentEnvironment(kMidLadder),
  gather: GatherAgentEnvironment(kCheapLadder),
);

/// The FIRST boot-eager refusal across [arming]'s TYPED seats, or null when
/// every armed seat prefers only environments PRESENT in [registry]'s
/// boot-validated set.
///
/// The successor to the deleted role-map guard, and the runtime half of the
/// normal-form fence: a preference entry that is not its own normal form —
/// a layer that inherits its transport from a builtin — is not in the presence
/// set and would silently resolve to NOTHING. It refuses LOUD instead, naming
/// the SEAT TYPE, the value and the fix (ADR-0000 A8, guards LOUD or GONE). An
/// EMPTY armed preference is refused for the same reason.
///
/// It deliberately does NOT run `EnvironmentRegistry.validate` over the whole
/// armed set: a builtin with an openAiCompatible target (`pi`) carries an
/// endpoint that is a site-binding machine fact, and a whole-registry validate
/// would refuse every boot on it.
String? preferenceArmingRefusal(
  AgentArming arming,
  EnvironmentRegistry registry,
) {
  final present = AvailableEnvironments.fromRegistry(registry);
  for (final seat in arming.seats) {
    final entries = _armedEntries(seat).toList();
    if (entries.isEmpty) {
      return '${seat.runtimeType} arms an EMPTY preference — it would resolve '
          'to nothing and silently fall to the ambient environment; give it at '
          'least one of the station\'s const environment values';
    }
    for (final entry in entries) {
      if (!present.contains(entry)) {
        return '${seat.runtimeType} prefers an environment no armed name '
            'resolves to ($entry) — arm it in the environment registry, or '
            'build the preference from the station\'s COMPLETE const '
            'environment values (a layer that inherits its transport from a '
            'builtin is not its own normal form and never matches)';
      }
    }
  }
  return null;
}

/// Every environment [preference] can select: its own entries plus, for the
/// critic seat, each lane override (`ModelPreference` is not a sealed union,
/// so this is an `is` test, not a switch).
Iterable<AgentEnvironment> _armedEntries(ModelPreference preference) sync* {
  yield* preference.entries;
  if (preference is CriticAgentEnvironment) {
    for (final lane in preference.lanes.values) {
      yield* lane;
    }
  }
}
