/// The station's AGENT ARMING — which NAMED inference environment each rung of
/// the agent-config ladder runs on, authored as committed Dart (power_station
/// `docs/adr/ADR-0002-agent-environment-layer.md` D2 DART-FIRST, D5 the
/// per-substation rung).
///
/// The ladder is: station default -> substation seat -> bead (`grid.agent`) ->
/// step (`StepArgs.params`). This library owns the top TWO rungs as pure
/// VALUES ("config = VALUES in the tree; impls are DI"): [AgentArming.underlay]
/// applies the STATION rung UNDER a boot config, [AgentArming.applyTo] applies
/// a SEAT rung OVER the ambient one. There is no operator-flag rung (ADR-0002
/// D4) and NO endpoint url anywhere in this file: WHERE an environment runs is
/// its own `InferenceTarget`, bound on the box by the machine-local site
/// binding (ADR-0002 D3).
library;

import 'package:grid_assets/grid_assets.dart'
    show
        AgentConfig,
        AgentEnvironment,
        AgentRole,
        BaseScope,
        EnvBaseRef,
        EnvironmentRegistry,
        EnvironmentRegistryError,
        kBuiltinEnvironments;

/// memento's NAMED environments — the station's own SEMANTIC names layered
/// over the first-party builtins via `base` (`builtin:claude` / `builtin:codex`).
///
/// A name is a PORTABLE promise ("build strong", "grade mid"): a bead or a seat
/// names `frontier`, and the STATION decides what that means on this box. Every
/// entry here resolves to a `providerManaged` target, so none needs a site
/// binding and every one validates at boot with no machine facts. An
/// openAiCompatible or swiftInfer name (`local-cheap`) joins only once the site
/// binding is mounted at the composition root — its endpoint is a machine fact
/// and never enters this file (ADR-0002 D3).
const Map<String, AgentEnvironment> kMementoEnvironments = {
  /// Build strong: claude at the frontier tier.
  'frontier': AgentEnvironment(
    base: EnvBaseRef('claude', scope: BaseScope.builtin),
    model: 'opus',
  ),

  /// Grade: claude at the mid tier.
  'mid': AgentEnvironment(
    base: EnvBaseRef('claude', scope: BaseScope.builtin),
    model: 'sonnet',
  ),

  /// Gather: claude at the cheap tier.
  'cheap': AgentEnvironment(
    base: EnvBaseRef('claude', scope: BaseScope.builtin),
    model: 'haiku',
  ),

  /// The org's BUILD environment: codex on its own native pin (inherited from
  /// the builtin, which pins `gpt-5.6-sol` — a claude tier name 400s on codex).
  'codex-frontier': AgentEnvironment(
    base: EnvBaseRef('codex', scope: BaseScope.builtin),
  ),
};

/// The station's environment REGISTRY: [kMementoEnvironments] as `custom`, the
/// five first-party environments as `builtins` (so `claude`/`codex`/`pi`/
/// `copilot`/`opencode` stay addressable by tool name too).
EnvironmentRegistry buildMementoEnvironmentRegistry() =>
    const EnvironmentRegistry(
      custom: kMementoEnvironments,
      builtins: kBuiltinEnvironments,
    );

/// One ARMING of the agent-config ladder — a station's or a seat's say in which
/// NAMED environment runs. A pure VALUE; it carries no behavior and reaches no
/// service.
class AgentArming {
  /// Creates an arming over an optional ambient [environment] name and a
  /// (possibly empty) role -> environment-name map.
  const AgentArming({this.environment, this.roleEnvironments = const {}});

  /// The ambient environment NAME for every role this arming does not name
  /// explicitly; null leaves the ambient rung alone.
  final String? environment;

  /// role -> environment NAME (the ladder's role rung, `AgentConfig.roleEnvironments`).
  final Map<AgentRole, String> roleEnvironments;

  /// Whether this arming says nothing at all.
  bool get isEmpty => environment == null && roleEnvironments.isEmpty;

  /// Applies this arming ON TOP of [base] — the SEAT rung (ADR-0002 D5). A
  /// seat's arming is committed Dart and deliberately SHADOWS the ambient one,
  /// on both axes.
  AgentConfig applyTo(AgentConfig base) => base.merge(
    harness: environment,
    roleEnvironments: roleEnvironments.isEmpty ? null : roleEnvironments,
  );

  /// Applies this arming UNDER [base] — the STATION rung: it fills ONLY the
  /// role rungs [base] leaves unarmed and never touches [AgentConfig.harness].
  ///
  /// UNDER, not over, on purpose: the boot config carries whatever the operator
  /// typed, and an explicit operator rung must never be SILENTLY ignored
  /// (ADR-0000 A20(2)'s no-wedge rule). The ambient axis is left alone because
  /// `AgentConfig.harness` has a non-null default ('claude') and so cannot be
  /// told apart from an operator-set value — the station speaks the ROLE axis.
  AgentConfig underlay(AgentConfig base) {
    final fill = <AgentRole, String>{
      for (final entry in roleEnvironments.entries)
        if (!base.roleEnvironments.containsKey(entry.key))
          entry.key: entry.value,
    };
    return fill.isEmpty ? base : base.merge(roleEnvironments: fill);
  }

  @override
  bool operator ==(Object other) =>
      other is AgentArming &&
      other.environment == environment &&
      _sameRoles(other.roleEnvironments, roleEnvironments);

  @override
  int get hashCode => Object.hash(
    environment,
    Object.hashAllUnordered(
      roleEnvironments.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'AgentArming(${environment ?? '<ambient>'}, roles: $roleEnvironments)';

  static bool _sameRoles(Map<AgentRole, String> a, Map<AgentRole, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// memento's CODED station posture: codex BUILDS under a claude committee.
///
/// The grade and gather rungs are deliberately UNARMED so they ride the ambient
/// environment and the tier ladder — arming `grade` to a model-pinning
/// environment would out-rank the station's own grade-tier arming.
///
/// `AgentRole.architect` (power_station `pow-t1w`) is NOT in the resolved
/// `grid_assets 0.6.0-rc.5` enum (build / grade / gather). The claude half of
/// the `{build: codex, architect: claude}` posture is therefore expressed today
/// by leaving the spec author on the ambient claude environment; architect
/// becomes ONE more entry in this map once a grid_assets release carrying
/// `pow-t1w` is adopted by bumping the hosted constraint.
const AgentArming kMementoStationArming = AgentArming(
  roleEnvironments: {AgentRole.build: 'codex-frontier'},
);

/// The FIRST boot-eager refusal across [config]'s armed ROLE rungs, or null when
/// every one names an armed, self-consistent environment in [registry].
///
/// The targeted half of `EnvironmentRegistry.validate`'s moment 1: the station
/// deliberately does NOT validate the whole armed set, because a builtin with an
/// openAiCompatible target (`pi`) carries an endpoint that is a site-binding
/// machine fact, and a whole-registry validate would refuse every boot on it.
/// The message names the role, the environment and the fix (ADR-0000 A8, guards
/// LOUD or GONE).
String? roleArmingRefusal(AgentConfig config, EnvironmentRegistry registry) {
  for (final entry in config.roleEnvironments.entries) {
    final name = entry.value;
    final AgentEnvironment environment;
    try {
      environment = registry.resolve(name);
    } on EnvironmentRegistryError catch (e) {
      return 'role "${entry.key.name}" names environment "$name": ${e.message}';
    }
    final selfCheck = environment.validate();
    if (selfCheck != null) {
      return 'role "${entry.key.name}" names environment "$name" but it is '
          'misconfigured: $selfCheck — fix "$name" or point the role at an '
          'armed environment';
    }
  }
  return null;
}
