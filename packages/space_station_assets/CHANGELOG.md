## 0.4.0-rc.3

- Fixed: `status` handles `AttachResult.DeadPid`, the case grid_cli added in
  0.5.0-rc.22. A sealed-type addition breaks an exhaustive switch, so the
  package did not compile against that grid_cli at all. It renders as a STALE
  LOCK rather than folding into `Down`: the lock names a pid no live process
  answers to, a fresh `up` steals it automatically, and saying so is the
  difference between an operator clearing a lock by hand and leaving it alone
  (tg-qwsx).
- Floors `grid_cli` to `^0.5.0-rc.23`, the first grid_cli that itself resolves
  against a published grid_engine.

# Changelog

## 0.4.0-rc.2

- Fixed: the runner composes `SuccessionCommand` (the `succession` verb the
  vended handoff skill teaches) and lists it among the paired commands
  (space_station#97, space-t9t).

## 0.4.0-rc.1

- Breaking: coordinated widening (A) changes
  `SpaceDelegate.buildWorkRegistry` to accept `NoteAppender` and
  `SpecifyAuthoredSpecWriter` as two required positional parameters. Downstream
  overrides must adopt the two-parameter signature and forward the writer;
  Lunar adopts it separately. Requires `grid_assets ^0.6.0-rc.24` and
  `grid_sdk ^0.3.0-rc.22`.

## 0.3.0-rc.12

- Added: `SpaceDelegate.assetRegistry` — the station-asset-registry override
  point. It defaults to space's own generated registrant
  (`lib/station_asset_registry.dart`, rendered by
  `tool/generate_station_asset_registry.dart` from the resolved package closure)
  and is threaded as ONE object into `buildCodeRegistry` (the worktree overlay
  every mounted session receives) and the `assets` command's install
  resolution. A downstream station overrides it with its own generated
  registrant so its packs' skills install and materialize (space-ot8, #92).

## 0.3.0-rc.11

- Added: `memento-engineering` — the org decisions repository — is the seventh
  coded org substation, at bead prefix `org`, carrying the memento org App and
  a live `githubPoll` like the other six. It is distinct from the `decisions`
  substation, which holds that repository's FORMAT and its implementation
  (`memento-engineering#org-decisions-live-in-the-org-register`). A downstream
  station inherits it through `super.substations(...)`.
- Changed: `codedRosterSnapshotOf` now exposes
  `githubPollingSubstationNames`; `githubPollingSeatNames` remains a deprecated
  compatibility getter for one minor cycle with the replacement message
  `Use githubPollingSubstationNames instead.`.

## 0.3.0-rc.10

- Added: every live boot emits the resolved dual-read posture (`off`, `observe`
  or `primary`) as a `trajectory.dualReadPosture` flare and a log line, and a
  SET but unrecognized `GRID_DUAL_READ` value emits its own flare naming the
  value and the `off` posture it armed — the wave-1 soak had run with the
  comparator silently off (space-7dz, #86).
- Added: `up --control-bind lan` opts the StationControl door onto the LAN
  (loopback stays the default) (#85).

## 0.3.0-rc.9

- Fixed: `SpaceDelegate.maintainsStateStoreOnBoot` directly projects `live`,
  enabling `runGrid`'s pre-boot state-store maintenance on live arms while
  keeping it disabled for dry probes.
- Changed: adopts the grid wave-16 floors: `grid_engine ^0.3.0-rc.23`,
  `grid_sdk ^0.3.0-rc.20`, `grid_cli ^0.5.0-rc.20`, and
  `grid_runtime ^0.2.0-rc.16`.

## 0.3.0-rc.8

- Breaking: `SpaceStationStatus.trajectory` is now grid_cli's inherited
  `Map<String, Object?>` wire field. Constructor callers continue to pass the
  typed `trajectory:` input unchanged; typed consumers migrate to
  `StationWorkRuntime.trajectory.status`. `trajectoryStatusJson` remains the
  single serializer. This release floors `grid_cli ^0.5.0-rc.19`,
  `grid_engine ^0.3.0-rc.22`, `grid_sdk ^0.3.0-rc.19`,
  `grid_runtime ^0.2.0-rc.16`, and `grid_assets ^0.6.0-rc.20` for the complete
  grid wave-15 shape.
- Added: the live status snapshot publishes the ordered resolved substation
  roster under `station.roster`, and attached status renders it. Older payloads
  without roster entries remain compatible.
- Fixed: the assets command resolves an omitted grid-home override from the
  mounted delegate's tree position, preserving downstream station roots while
  still refusing relative overrides.

## 0.3.0-rc.7

- Fixed: `space status` names `SlowUp` — grid_cli 0.5.0-rc.16 (tg-k5hl, the_grid#337) split a slow-but-alive resident door out of `Up`, and the exhaustive `AttachResult` switch made every downstream station that resolved cli rc.16+ fail to compile (lunar held `grid_cli` at rc.15 for exactly this). A slow door renders as UP plus one `door: SLOW` line carrying the elapsed seconds, exit 0. Floors `grid_cli ^0.5.0-rc.17` (the first cli that compiles against grid_trajectory 0.2.0-rc.5's `ShadowCompare` surface), `grid_sdk ^0.3.0-rc.17` and `grid_runtime ^0.2.0-rc.14`, so a resolved pair is coherent with the_grid rc wave 13.

## 0.3.0-rc.6

- Fixed: `space status` consumes the lock's DECLARED lifecycle phase — the `AttachResult` switch names `Starting` and `Unreachable` (cli rc.15 split them out of `Stale`; the `Unreachable` branch keeps the prior wording and exit code, `Starting` is additive). Floors `grid_cli ^0.5.0-rc.15` and `grid_diagnostics_contract ^0.2.1`; a downstream station that resolves cli rc.15 compiled against rc.5's switch no longer breaks (space-b8u, #76).
- Added: `SubstationSeed.assetRoster` carries a `GridAssetRosterOverride` through to `MountedSubstationSeed.assetRoster` (the coded EXCEPTION half of derived-by-default asset selection); `codedRosterSnapshotOf` projects an immutable substation-keyed `assetRosters` map; `GridAssetRosterOverride` and `AssetKey` are re-exported for override authoring. `MountedSubstationSeed.assetRoster` is a required constructor field — no downstream constructs the type directly. Floors `grid_sdk ^0.3.0-rc.15` (space-kwv, #75).
- Added: `buildRunnerComposition()` returns the command runner together with the unmodifiable set of paired operator command names and the baseline asset registry, so a downstream station can teach its own skill/command pairs against the composed surface (space-eqh, #74).

## 0.3.0-rc.5

- Breaking: `buildSpaceAssetsCommand` drops `roots:` (the retired
  `StationOverlaySource` walk) for the rc.13 registry seams — `registry`,
  `rosterOverride`, `factsRepository` (defaulting to the generated registry,
  no override, and `FileSystemSubstationFactsRepository`). Migration: a
  downstream caller passing `roots:` passes a `GridAssetRosterOverride` /
  facts repository instead; none is known outside this repo (space-31x, #72).
- Added: `buildRunner` composes the vended `PrimeCommand` and `SeatCommand`
  bare, so the station overlay's SessionStart hook (`{{runner}} prime
  --hook-json`) and the operator-seat launcher resolve on every station that
  extends this runner; the three named claude environments carry
  `--dangerously-skip-permissions` in `drivenArgs` (driven launches only),
  and `kCodexFrontierEnvironment` mirrors the vended codex builtin's
  `roleAsset` / `primeMode`. Floor: `grid_assets ^0.6.0-rc.13` (space-31x, #72).
- Fixed: cross-store link beads are authored and closed in the DELEGATE's state
  partition (`lunar link` mints `tranquility-*`), with the houston default
  preserved (#71).
- Fixed: worktree overlays render the delegate's runner and source ref instead
  of the default runner and unknown provenance — the resident code registry
  now carries station identity (#70).

## 0.3.0-rc.4

- Breaking: none new in this candidate — it continues the 0.3.0 line; the
  migration notes under 0.3.0-rc.1 still apply.
- Changed: the typed-seat arming MECHANISM is the framework's. `AgentArming`,
  `TypedEnvironmentProvider` and `SeatEnvironments` are no longer declared here
  — they are consumed from `grid_assets` 0.6.0-rc.9 (power_station bead
  `pow-lb0`) and RE-EXPORTED under the same names, so a downstream station's
  `show AgentArming` import is unchanged. memento's POSTURE stays in this
  package: the four named environments, the four canned ladders,
  `buildMementoEnvironmentRegistry`, `kMementoStationArming` and
  `preferenceArmingRefusal` (space-9c9).
- Changed: requires `grid_assets` ^0.6.0-rc.9 and `github_grid_assets`
  ^0.1.0-rc.9. That train carries `grid_cli` 0.5.0-rc.11, `grid_engine`
  0.3.0-rc.11, `grid_runtime` 0.2.0-rc.9, `grid_sdk` 0.3.0-rc.9 and
  `beads_dart` 0.2.0-rc.7 with it; rc.11's deleted `StationKernel` has no
  caller in this repo.
- Unchanged: `SubstationSeed`, `GitHubAppConfig` and `MountedSubstationSeed`
  stay this package's own. github_grid_assets 0.1.0-rc.9 also vends a composed
  `SubstationSeed`, but its `SubstationAppIdentity` carries an `int`
  `installationId` where this package's `GitHubAppConfig` carries a `String`,
  so adopting it is a migration of every substation authoring site rather than a
  re-export — that is bead `space-ovd`'s scope.

## 0.3.0-rc.3

- Breaking: none new in this candidate — it continues the 0.3.0 line; the
  migration notes under 0.3.0-rc.1 still apply.
- Added: the memento org GitHub App identity (`kMementoOrgApp`) is authored and
  exported, and every coded org substation carries it as its `app:` delivery
  identity (space-u8q).
- Added: every coded org substation carries a `githubPoll` reconciler value under the
  org App installation, so the resident station polls the six org repositories
  for issue intake. The defaults stand (1-minute interval, 5-second spacing,
  live arm); one station owns intake for these repos (space-3ds).
- Fix: `filing` and `approve` resolve a bead's substation by the longest coded prefix
  at a complete identifier boundary, so roster prefixes may contain hyphens and
  overlapping prefixes route to the right store (space-fvg).
- Changed: requires `grid_assets` 0.6.0-rc.8. Approval is the `grid.approved_*`
  stamp alone: the label clause is gone from the mount gate and `approve` adds
  no label.

## 0.3.0-rc.2

- Breaking: none new in this candidate — it continues the 0.3.0 line; the
  migration notes under 0.3.0-rc.1 still apply.
- Fix: `up`'s boot banner and both dev-mode lines are rendered from the station
  composition instead of hardcoded to space. A downstream station now prints its
  own name and its real reload command (`lunar reload`, not `space reload`).
  `buildRunner` threads its `name` and `runnerInvocation` into `UpCommand`; the
  station name comes from the mounted delegate. Existing embedders keep working
  unchanged, since both default to space's prior values.
- Added `station_banner.dart` (the pure banner renderers) to the public surface.

## 0.3.0-rc.1

- Breaking: the station's agent posture is expressed as TYPED SEAT VALUES, not
  a role map. `AgentArming` names the build, spec, critic and gather seats over
  complete const environment values, `SpaceDelegate.arming` is the override
  point a downstream station authors its posture in, and the role-keyed
  `AgentRole`/`roleEnvironments` path is gone. Migration: replace a
  `roleEnvironments` map with an `AgentArming` of the four seat types over the
  canned ladders (`kCodexLadder`, `kFrontierLadder`, `kMidLadder`,
  `kCheapLadder`) and override `arming` instead of pre-merging an `AgentConfig`.
  The generic `--env` scope survives as the last rung, under every armed seat.
- Breaking: `buildRunner` and `UpCommand` take the process `environment` as an
  argument. An entrypoint passes it in; nothing under `lib/` reads it ambiently,
  which the assembly's own guard test enforces. An unfed runner arms the default
  posture, so existing embedders keep working without change.
- Added the Stage-1 trajectory runner surface: `up` carries a tri-state
  trajectory flag (absent arms when the home is provisioned, on makes a
  degradation loud, off disables the harness), and the banner and status render
  the harness posture, epoch and counters. The dual-read posture is fed through
  the injected environment.
- Added the `filing` and `approve` verbs, and the typed seat projections
  (`SeatEnvironments`, `TypedEnvironmentProvider`, `codedSeatEnvironmentsOf`,
  `preferenceArmingRefusal`).
- Requires the release train this candidate was cut against: `grid_assets`
  ^0.6.0-rc.7, `grid_sdk` ^0.3.0-rc.8, `grid_engine` ^0.3.0-rc.10, `grid_cli`
  ^0.5.0-rc.10, `grid_runtime` ^0.2.0-rc.8, `grid_exploration` ^0.3.0-rc.4,
  `beads_dart` ^0.2.0-rc.5, `github_grid_assets` ^0.1.0-rc.7,
  `federated_grid_assets` ^0.3.0-rc.2, `dart_grid_assets` ^0.1.1.

## 0.2.0

API additions since 0.1.0:

- Added the `SpaceDelegate.buildWorkRegistry` and
  `SpaceDelegate.circuitOverrideFor` delegate work-policy hooks for downstream
  stations.
- Added `githubSelfTrust` forwarding through `SpaceDelegateFactory` and
  `SpaceDelegate`, providing the station-global GitHub trust value to polling
  substations.
