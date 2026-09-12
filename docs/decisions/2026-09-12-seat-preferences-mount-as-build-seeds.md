---
status: accepted
date: 2026-09-12
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: seat-preferences-mount-as-build-seeds
  surfaces:
    - "packages/space_station_assets/lib/src/agent_arming.dart"
    - "packages/space_station_assets/lib/src/space_delegate.dart"
    - "packages/space_station_assets/lib/src/substation_seed.dart"
    - "packages/space_station_assets/lib/src/up_command.dart"
  obsoletes: []
  updates: ["the-typed-seat-arming-mechanism-is-consumed-from-grid-assets"]
  obsoleted-by: null
  updated-by: []
  bead: space-0q1
  legacy-id: null
---

# Seat preferences mount as build seeds

## Context and Problem Statement

Delegate hooks are build methods: their values belong to the build phase and
must be derived with that build's `TreeContext` and `GridConfiguration`.
`SpaceDelegate.arming` instead returned a static four-field compatibility
record, and command policy read it from a delegate that never mounted a tree.
The open-seat mechanism now lets every `SeatPreference` own the provider seed
that mounts its exact static type, so the record is no longer the composition
seam.

## Decision Outcome

Station posture is an ordered, open collection of `SeatPreference` values.
`SpaceDelegate.seatSeeds(context, configuration)` mounts each preference's own
provider seed during build, above the station roster. A substation authors a
list of seat provider seeds that wraps only its subtree, allowing one exact
seat type to shadow the station default without enumerating or replacing the
other seats.

Named environments are built by
`SpaceDelegate.environments(context, configuration)` from the same build's
`TreeContext` and `GridConfiguration`. Commands obtain the registry, station
seat projection, and ordered station and substation preferences only through
one owned offline mount of the coded delegate.

This updates the earlier mechanism-placement decision: the open
`SeatPreference`, `SeatProvider`, `CriticSeatProvider`, and `SeatEnvironments`
types remain consumed from `grid_assets`, while the compatibility-only
`AgentArming` and `TypedEnvironmentProvider` barrel re-exports are removed.

### Consequences

* Good, because every seat subtype owns how it enters the tree and every
  environment registry is derived in the build context that consumes it.
* Bad, because extending stations must replace `SpaceDelegate.arming` with
  `seatSeeds(context, configuration)`, update `environments` to its build-method
  signature, replace `SubstationSeed.arming` with provider seeds, and stop using
  `codedArmingOf` or the removed compatibility barrel exports.
