# Changelog

## 0.3.0-rc.3

- Breaking: none new in this candidate — it continues the 0.3.0 line; the
  migration notes under 0.3.0-rc.1 still apply.
- Added: the memento org GitHub App identity (`kMementoOrgApp`) is authored and
  exported, and every coded org seat carries it as its `app:` delivery identity
  (space-u8q).
- Added: every coded org seat carries a `githubPoll` reconciler value under the
  org App installation, so the resident station polls the six org repositories
  for issue intake. The defaults stand (1-minute interval, 5-second spacing,
  live arm); one station owns intake for these repos (space-3ds).
- Fix: `filing` and `approve` resolve a bead's seat by the longest coded prefix
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
  seats.
