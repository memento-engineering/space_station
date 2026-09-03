---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: memento-s-named-environments-are-complete-const-values
  surfaces:
    - "packages/space_station_assets/lib/src/agent_arming.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: ["the-typed-seat-arming-mechanism-is-consumed-from-grid-assets"]
  bead: space-rz6
  legacy-id: null
---
## memento's named environments are COMPLETE const values, declared once and used as both registry entries and preference entries

**Decision (AI; MECHANISM only).** The POLICY is Nico's, ratified as
power_station `docs/adr/ADR-0006-typed-environment-lookup-selects-by-value.md`
D1: "Canned sets are const Dart declared beside the environments in the
station's arming. No strings at the composition layer." What this entry records
is HOW space_station satisfies it. `kMementoEnvironments`' four values stop
LAYERING on the first-party builtins (`base: EnvBaseRef('claude', scope:
BaseScope.builtin)`) and become COMPLETE, standalone `const AgentEnvironment`
declarations (`base: EnvBaseStandalone()`), each spelled once at the top of
`agent_arming.dart` and referenced BOTH by the registry's `custom` map AND by
the canned preference ladders `kFrontierLadder` / `kMidLadder` /
`kCheapLadder` / `kCodexLadder`.

**Why.** power_station A35(2) and `AgentEnvironment.flattened` reconcile the
`base` field between a canned layer and the registry's resolution of the same
environment — "they differ only in `base`". They do NOT fill in fields a layer
never declared. A layer that inherits its transport from a builtin flattens to a
value whose `command`, `args`, `promptMode`, `promptFlag`, `target`,
`usageJsonArgs` and `resumeFlag` are all null, so
`AvailableEnvironments.contains` rejects it and a const preference built from it
resolves to NOTHING — measured in this worktree against grid_assets
0.6.0-rc.7: `frontier raw-contains=false / resolved-contains=true`. Making each
value complete is what lets the preference stay `const` and stay declared beside
the environments, exactly as D1 requires: there is no `late final` preference,
no `EnvironmentRegistry.resolve` at the composition layer, and no second
declaration to keep in sync. Const CAN match the registry; it matches once the
value is its own normal form.

**The cost, and how it is fenced.** The transport fields of the claude and codex
builtins (including the `@agentclientprotocol/codex-acp` pin) are now spelled in
this repo as well as in grid_assets. Two guards make that drift LOUD rather than
silent: (1) a parity test in `packages/space_station_assets/test/agent_arming_test.dart`
compares each value against `kBuiltinEnvironments` and goes RED on the
constraint bump that changes a builtin — which is the deliberate-adoption moment
ADR-0003 D1 already reserves for reviewing producer changes; and (2)
`preferenceArmingRefusal` refuses the boot LOUD (naming the seat TYPE) if an
armed preference entry is not in the registry's boot-validated presence set
(ADR-0000 A8, guards LOUD or GONE).

**Affects:** `packages/space_station_assets/lib/src/agent_arming.dart`
(`kFrontierEnvironment`, `kMidEnvironment`, `kCheapEnvironment`,
`kCodexFrontierEnvironment`, `kMementoEnvironments`, `kFrontierLadder`,
`kMidLadder`, `kCheapLadder`, `kCodexLadder`, `AgentArming`,
`TypedEnvironmentProvider`, `SeatEnvironments`, `kMementoStationArming`,
`preferenceArmingRefusal`), `lib/src/space_delegate.dart`,
`lib/src/substation_seed.dart`, `lib/src/up_command.dart`; tests
`test/agent_arming_test.dart`, `test/seat_arming_test.dart`,
`apps/space/test/up_agent_scope_test.dart`.
