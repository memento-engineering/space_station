/// The station's AGENT ARMING — which inference environment each TYPED SEAT
/// runs on, authored as committed Dart (power_station
/// `docs/adr/ADR-0002-agent-environment-layer.md` D2 DART-FIRST, D5 the
/// per-substation rung; `docs/adr/ADR-0006-typed-environment-lookup-selects-by-value.md`
/// D1/D2 the VALUE-keyed typed rung).
///
/// MECHANISM IS VENDED, POSTURE IS NOT. [AgentArming], `TypedEnvironmentProvider`
/// and `SeatEnvironments` are the FRAMEWORK's — grid_assets 0.6.0-rc.9,
/// `lib/src/agent/seat_environments.dart` (power_station bead `pow-lb0`) — and
/// are consumed from there, then re-exported unchanged by
/// `lib/space_station_assets.dart` so a downstream station's `show AgentArming`
/// keeps resolving. What this library owns is memento's POSTURE alone: the four
/// named environments, the four canned ladders, the registry over them, the
/// coded station arming and the boot-eager guard. Recorded at
/// `docs/decisions/2026-09-03-the-typed-seat-arming-mechanism-is-consumed-from-grid-assets.md`.
///
/// The ladder is: station default -> substation seat -> bead (`grid.agent`) ->
/// step (`StepArgs.params`). This library owns the top TWO rungs as pure
/// VALUES ("config = VALUES in the tree; impls are DI"): [kMementoStationArming]
/// is the station's, and a `SubstationSeed`'s own [AgentArming] nests UNDER it.
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

import 'package:grid_assets/grid_assets.dart'
    show
        AgentArming,
        AgentEnvironment,
        AvailableEnvironments,
        BuildAgentEnvironment,
        CriticAgentEnvironment,
        EnvBaseStandalone,
        EnvironmentRegistry,
        GatherAgentEnvironment,
        InferenceTarget,
        ModelPreference,
        PromptMode,
        SeatPrimeMode,
        SpecAgentEnvironment,
        kBuiltinEnvironments;

/// Build strong: claude at the frontier tier. COMPLETE and standalone (see the
/// library doc): the transport fields mirror `kBuiltinEnvironments['claude']`.
const AgentEnvironment kFrontierEnvironment = AgentEnvironment(
  base: EnvBaseStandalone(),
  command: 'claude',
  drivenArgs: ['--dangerously-skip-permissions'],
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
  drivenArgs: ['--dangerously-skip-permissions'],
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
  drivenArgs: ['--dangerously-skip-permissions'],
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
  roleAsset: '.agents/agents/{{seat}}.md',
  primeMode: SeatPrimeMode.prompt,
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
