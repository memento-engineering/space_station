# Changelog

## Unreleased

- Added: the shared runner now composes `admission set` for every downstream
  station and raises the `grid_cli` floor to `^0.6.0-dev.4`, the first release
  exporting `AdmissionCommand` and `AdmissionSetCommand`.
- Breaking: `PrimeCommand` now receives the composed `runnerInvocation`, so
  downstream prime pointers render that station's JIT invocation. This raises
  the `grid_assets` floor to `^0.7.0-dev.3`, where the constructor parameter is
  required and default-less.

## 0.5.0-dev.3

- Breaking: the `unlink` verb is REMOVED from the station runner, and
  `buildSpaceLinkCommands` / `SpaceLinkCommands` are replaced by
  `buildSpaceLinkCommand`, which returns the `link` Command alone. grid_cli
  0.6.0-dev.3 (the_grid#447) deleted `UnlinkCommand` with the state-store link
  bead itself, and `LinkCommand` dropped `stateStorePrefix`; `LinkEndpointStore`
  gained a required `name`, which this composition fills from the coded roster
  so an `external:<project>:<capability>` row carries the substation's roster
  name. A HARD CUT, with no shim and no station-local replacement.
  Migration: call `buildSpaceLinkCommand(...)` and drop every `.link` / `.unlink`
  field read; remove a cross-store blocker with
  `bd dep remove <from> external:<project>:<capability>`, or let it lift when the
  target ships (`bd ship <target>` on a CLOSED target). A store still holding the
  retired link beads is converted once with
  `space link migrate --grid-root <home> [--dry-run]`.
- Breaking: `SpaceDelegate` takes `trajectoryConfig` and `SpaceDelegateFactory`
  carries it. `space up` now registers exactly ONE
  `GitHubReconciliationQuery` in the station's
  `TrajectoryConfig.obligationQueryExtensions` and provides the harness's
  resolved config above the substation fan-out, because github_grid_assets
  0.2.0-dev.1 retired the per-seat poll loop (and `GitHubReconcilerConfig
  .interval`) in favour of the fenced service tick: a live reconciler seat under
  a tree offering no registration REFUSES LOUD at build.
  Migration: a downstream delegate subclass adds `super.trajectoryConfig` to its
  constructor so its tear-off still satisfies `SpaceDelegateFactory`, and drops
  `interval:` from every `GitHubReconcilerConfig` it authors.
- Breaking: the composed `filing`, `approve` and `unpark` verbs drop
  `stateRoot:` and thread the station's ARMED substation NAMES instead
  (`armedSubstations`), so an `external:<project>:<capability>` dependency row
  resolves against the CODED roster rather than refusing fail-closed
  (grid_assets 0.7.0-dev.2, pow-f6pc). The new export `armedSubstationNames`
  derives them from the same offline roster mount `storeRootForBead` uses.
  `park` and `show` keep `--state-root`; they are the only verbs that still
  reach the state store.
  Migration: nothing to do on the runner. A standing `grid.approved_rev` taken
  when the retired cross-store link lookup was consulted is STALE and its bead
  needs re-approving, because the basis `dependencies` member changed shape.
- Breaking: `SpaceStationStatus.toJson` takes the base's `governorFlares`
  parameter (grid_cli 0.6.0-dev.3) and forwards it; the roster augmentation it
  owns is unchanged.
  Migration: an override of this method adds the parameter and forwards it to
  `super.toJson(governorFlares: governorFlares)`.
- Changed: the substation stack's `GitGridAssets` watches `StationGitRepository`
  rather than `StationGitService`, and the delegate builds that repository
  IN-TREE over the work runtime's service (`Provider(create:)` + `dispose:`).
  The repository retains each provisioned worktree's base commit, so a committee
  pins its review diff to the exact base the provisioner cut from instead of a
  moving `origin/<base>` (grid_runtime 0.2.1-dev.2, the_grid#436).
- Removed: `test/link_frontier_integration_test.dart`. It proved that authored
  state-store link beads governed the joined ready frontier, and grid_engine
  0.4.0-dev.3 deleted that seam outright (`onUnresolvedCrossLink` with it). The
  cross-store blocker is covered where it now lives: the bd dependency row in
  `test/link_composition_test.dart`, and its roster resolution in
  `test/filing_composition_test.dart`.
- Changed: adopts the 2026-09-13 the_grid dev.3 wave and the matching
  power_station wave, override-free from pub: `beads_dart ^0.3.0-dev.2`,
  `genesis_tree ^0.4.0`, `grid_cli ^0.6.0-dev.3`, `grid_engine ^0.4.0-dev.3`,
  `grid_exploration ^0.3.1-dev.2`, `grid_runtime ^0.2.1-dev.2`,
  `grid_sdk ^0.4.0-dev.3`, `grid_assets ^0.7.0-dev.2`,
  `github_grid_assets ^0.2.0-dev.2`, `federated_grid_assets ^0.3.1-dev.1` and
  `dart_grid_assets ^0.2.1-dev.2`.

- Added: `BeadsCommand` / `BeadsConfigureCommand` and `buildSpaceBeadsCommand`
  vend the offline `beads configure` verb, composed on the shared station
  runner. It projects the station's ARMED coded roster into every armed
  substation store's bd `external_projects` map — `.beads/config.local.yaml`
  only, since the projected roots are one machine's absolute paths — so an
  `external:<substation>:<capability>` dependency names a project bd can place.
  The tracked `config.yaml` is never touched, unrelated local keys, comments
  and formatting survive, an equal map is reported `unchanged` and nothing is
  written, `--dry-run` writes nothing at all, and a substation root with no
  `.beads` store (or no tracked `config.yaml`) is reported and skipped, never
  created. The verb also appends `config.local.yaml` to the store's
  `.beads/.gitignore` when absent, so the machine-local projection cannot be
  committed into a substation's repo.
- Added: `BeadsConfigureService` and `externalProjectsFor` are the projection
  itself, plus the sealed `BeadsConfigureOutcome` family
  (`ExternalProjectsWritten`, `ExternalProjectsUnchanged`, `WorkStoreMissing`,
  `PrimaryConfigMissing`, `LocalConfigRefused`), the `LocalConfigIgnore` report,
  and the `kExternalProjectsKey`, `kLocalConfigFileName`,
  `kPrimaryConfigFileName`, `kStoreIgnoreFileName` and
  `kLocalConfigIgnoreStanza` constants — a downstream station composes the SAME
  verb over ITS delegate rather than authoring a second one.
- Adds `yaml` and `yaml_edit` dependencies: bd's config primitive is YAML, and
  the rewrite is surgical so the operator's file survives it.
- Added: `up --daemon` and `down --daemon`. `up --daemon` renders a launchd
  LaunchAgent for THIS station — label `grid.station.<stationName>`,
  `ProgramArguments` the operator's exact JIT invocation minus `--daemon`,
  `WorkingDirectory` the grid home, `KeepAlive` on crash only, logs under
  `<grid-home>/.grid/logs/` — writes it to `~/Library/LaunchAgents/` and loads
  it with `launchctl bootstrap`, so the resident is launchd's child and no
  seat session owns it. A loaded label is a refusal naming it, never a second
  resident. `down --daemon` boots the agent out and removes the plist, and
  `status` adds `supervised: launchd <label>` when the agent is loaded. macOS
  only; a Linux systemd unit is a separate seam.
- Added: the supervisor fork sits BELOW every arming refusal — the grid-home
  guards, the per-substation work-store guard, the nothing-resolved refusal,
  and a read-only RS-2 holder probe (`StationAttach.status`, never `acquire`,
  which would make the calling shell a session leader). A refusal starts
  nothing: `RunAtLoad` plus `KeepAlive{SuccessfulExit: false}` would otherwise
  turn a one-shot refusal into a job launchd respawns forever and resurrects
  on every login.
- Added: the rendered plist carries an `EnvironmentVariables` block captured
  at ARM time (`supervisedEnvironment`): `PATH`, `HOME`, and every `GRID_*`
  and `BEADS_*` key set in the injected environment. launchd hands a job none
  of the launching shell's environment, so without this capture `gh`/`git`
  would not resolve, the App key paths would be missing, and `GRID_DUAL_READ`
  and its siblings would silently resolve to the default posture under
  supervision (`--dual-read` is not an `up` flag). An explicit allowlist,
  never the whole environment; a key set empty is omitted rather than written
  empty.
- Added: `up --daemon` refuses an invocation that cannot START. Before a byte
  is written it runs `<dart> run <runner> --help`
  (`daemonStartCheckCommand`) from the grid home under exactly the environment
  the plist will carry, through an injected `StartCheck`/`ProcessStartCheck`
  seam, and a non-zero exit is `DaemonUnstartable` — no plist, no bootstrap,
  a refusal naming the command, the directory, the exit code and what the
  runner said.
- Fixed: `down --daemon` reports the two halves of the retirement separately.
  `bootout` now runs only against a label launchd actually holds, and the
  verb no longer claims to have removed a plist that was already gone.
- Added: `codedStationNameOf`, the owned (construct → dispose) read of a
  station factory's `stationName`, and the `launch_agent.dart` surface the
  verbs compose (`LaunchAgentSupervisor`, `Launchctl`/`ProcessLaunchctl`,
  `StartCheck`/`ProcessStartCheck`, `renderLaunchAgentPlist`,
  `daemonProgramArguments`, `daemonStartCheckCommand`,
  `supervisedEnvironment`).
- Added: `UpCommand`, `DownCommand`, and `StatusCommand` take injected `out`
  and `err` sinks (defaulting to the process streams) and the supervisor
  seams, so the verbs are drivable without a subprocess.
- Removed: the hand-filled `CHANGE_ME` LaunchAgent template and its lint test
  (`apps/space/tool/launchd/`) — replaced by the rendered agent, which cannot
  drift from the invocation it supervises.

## 0.5.0-dev.2

- Breaking: Removes SpaceDelegate.arming, SpaceDelegate.harnesses, codedArmingOf, and SubstationSeed.arming; SpaceDelegate.environments now takes (context, configuration), open seat-provider seeds mount during build, and codedSeatEnvironmentsOf returns CodedSeatEnvironmentSnapshot.
  Migration: Extending stations replace an arming getter with seatSeeds(context, configuration), returning one seat.provider() seed per preference, and override environments(context, configuration); lunar adopts this in its separate downstream bead.

## 0.5.0-dev.1

- Added: the shared station runner now composes the vended `park`, `unpark`,
  and cross-store `show` filing commands, plus the generic resident-control
  `pause` and `resume` pair. A dependency-derived reachability guard accounts
  for every public command vended by the runner's command-bearing direct
  dependencies, so a newly shipped command cannot remain silently uncomposed.
- Floors `grid_assets` at ^0.7.0-dev.1 for `ShowCommand`,
  `github_grid_assets` at ^0.1.1-dev.1, and `dart_grid_assets` at
  ^0.2.1-dev.1 for the compatible asset-pack release wave.

## 0.4.0

- PROMOTED from 0.4.0-rc.4. This is the stable release of the 0.4.0 line; the code is the
  candidate's, unchanged. Every family dependency constraint is rewritten from its prerelease
  form to the stable one, because pub refuses a stable package that depends on a prerelease.
- Consumers on a `^0.4.0-rc.N` constraint resolve this automatically: a caret range admits the
  release above its own prereleases, so no downstream pubspec edit is required to pick it up.
- Floors grid_assets ^0.6.0 and grid_sdk ^0.3.0, the promoted grid core. The coordinated-widening
  guard moves its pins to those stable floors in the same change, which is what that test exists
  to force.

## 0.4.0-rc.4

- Floors grid_assets ^0.6.0-rc.25 and dart_grid_assets ^0.2.0-dev.1.
  grid_assets rc.25 adds the `{{bootRunner}}` overlay hole, so a composing
  station can spell its resident boot — which needs the JIT run form to carry
  `--enable-vm-service` — differently from the verbs a seat calls from a
  substation worktree. The hole defaults to `{{runner}}`, so a station naming
  only one runtime renders byte-identically and nothing changes for space
  itself. dart_grid_assets 0.2.0-dev.1 is the breaking rung/semver split of the
  release service, and this package consumes only `DartCommand` from it, so the
  adoption is the constraint alone. Lunar adopts the bootRunner hole separately
  (lunar_station-cu7, power_station#288/#284).

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
