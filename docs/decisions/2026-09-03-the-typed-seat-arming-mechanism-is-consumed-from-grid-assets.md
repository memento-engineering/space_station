---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-typed-seat-arming-mechanism-is-consumed-from-grid-assets
  surfaces:
    - "packages/space_station_assets/lib/src/agent_arming.dart"
    - "packages/space_station_assets/lib/space_station_assets.dart"
    - "packages/space_station_assets/lib/src/space_delegate.dart"
    - "packages/space_station_assets/lib/src/substation_seed.dart"
  obsoletes: []
  updates: ["memento-s-named-environments-are-complete-const-values"]
  obsoleted-by: null
  updated-by: []
  bead: space-9c9
  legacy-id: null
---
## The typed-seat arming MECHANISM is consumed from grid_assets and re-exported; only memento's POSTURE stays in space

**Decision (AI; MECHANISM placement only).** `AgentArming`,
`TypedEnvironmentProvider` and `SeatEnvironments` are deleted from
`packages/space_station_assets/lib/src/agent_arming.dart` and consumed from
`grid_assets` 0.6.0-rc.9 (`lib/src/agent/seat_environments.dart`, power_station
bead `pow-lb0`). `packages/space_station_assets/lib/space_station_assets.dart`
RE-EXPORTS the three under the same names, so every current importer — lunar
included, whose `show AgentArming` is unchanged — keeps compiling. What stays in
space is the POSTURE: `kFrontierEnvironment`, `kMidEnvironment`,
`kCheapEnvironment`, `kCodexFrontierEnvironment`, `kMementoEnvironments`, the
four ladders, `buildMementoEnvironmentRegistry`, `kMementoStationArming` and
`preferenceArmingRefusal`.

**Why.** The two copies were textually the same class. grid_assets' CHANGELOG
for 0.6.0-rc.9 states the split as a rule — "A composing station keeps its own
named environments and ladders: mechanism is vended, posture is not" — and
`github_grid_assets` 0.1.0-rc.9 already consumes the vended `AgentArming` in its
own composed seed, so a fork here would mean two `AgentArming` types meeting at
the same seat. Re-exporting rather than re-spelling keeps the extend-don't-fork
seam (space_station `CLAUDE.md`): a downstream station composes on
`space_station_assets` and never learns that the declaration moved.

**What this UPDATES.** `memento-s-named-environments-are-complete-const-values`
listed `AgentArming`, `TypedEnvironmentProvider` and `SeatEnvironments` in its
**Affects** line, alongside the named environments. That entry's SUBSTANCE — the
four environments are COMPLETE, standalone `const` values, declared once and
used as both registry entries and preference entries — is untouched and still
binds; only the three mechanism symbols leave its surface. Both of its guards
survive intact: the parity test in
`packages/space_station_assets/test/agent_arming_test.dart` still compares each
value against `kBuiltinEnvironments` and still goes RED on the grid_assets bump
that changes a builtin (this bump does not), and `preferenceArmingRefusal` still
refuses the boot LOUD naming the seat TYPE. The `const` preference entries the
entry defends are memento's own values either way; which package DECLARES the
`AgentArming` that carries them does not touch normal-form equality.

**What this does NOT do.** `github_grid_assets` 0.1.0-rc.9 also vends a composed
`SubstationSeed` plus `SubstationAppIdentity`. It is NOT adopted here and space's
own `SubstationSeed` is unchanged: the vended seed's `app:` takes a
`SubstationAppIdentity` whose `installationId` is an `int`, where space's takes a
`GitHubAppConfig` whose `installationId` is a `String`, and it provides
`Provider<SubstationAppIdentity>` where space provides
`Provider<GitHubAppConfig>`. A re-export would therefore change what the name
`app:` MEANS at every authoring site (`kMementoOrgApp`, all five coded seats, the
downstream fixture in `test/memento_roster_test.dart`) and delete the mount-time
`FormatException` case `test/substation_seed_test.dart` asserts — that is a
migration, not a re-export. Bead `space-ovd` ("Canonicalize Git substation
composition in grid_assets instead of copying it in Space") already owns exactly
that work and is now unblocked by rc.9.

**Affects:** `packages/space_station_assets/lib/src/agent_arming.dart`,
`lib/space_station_assets.dart`, `lib/src/space_delegate.dart`,
`lib/src/substation_seed.dart`; tests `test/vended_arming_test.dart`,
`test/agent_arming_test.dart`, `test/seat_arming_test.dart`.
