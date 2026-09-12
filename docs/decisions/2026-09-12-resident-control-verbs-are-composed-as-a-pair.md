---
status: accepted
date: 2026-09-12
decision-makers: ["specify"]
consulted: []
informed: []
register:
  spec: 1
  slug: resident-control-verbs-are-composed-as-a-pair
  surfaces:
    - "packages/space_station_assets/lib/space_station_assets.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-u7h
  legacy-id: null
---

# Resident-control verbs are composed as a pair

## Context and Problem Statement

`grid_cli` vends generic `pause` and `resume` commands over its
`StationCommandClient`. The standalone grid binary composes both, but station
runners compose neither. Deciding whether `pause` belongs on a station runner
cannot stop at the command's immediate effect: its own recovery instruction
directs the operator to `resume`, so reachability of either verb creates a
reachability obligation for the other.

This is composition posture only. The resident-control protocol, client, and
command behavior remain owned by `grid_cli`; the station runner supplies no
parallel service or wrapper.

## Considered Options

- Compose `PauseCommand` and `ResumeCommand` together, bare over their vended
  `StationCommandClient`.
- Leave resident control on the standalone grid binary only. This was rejected
  because the station runner is the operator-facing surface for the resident
  station and already composes the other generic resident-door verbs.
- Compose `PauseCommand` without `ResumeCommand`. This was rejected because
  pause's own recovery instruction requires resume; exposing the entry into a
  held state without its exit would make the command pair operationally
  incomplete.

## Decision Outcome

`PauseCommand` and `ResumeCommand` form one generic resident-control pair.
Every station exposing either command composes both bare over the vended
`StationCommandClient`. `buildRunnerComposition` is the shared composition
surface, so downstream stations inherit the pair without adding their own
wiring.

This applies
`space_station#operator-command-teaching-stays-with-the-baseline-pack`: neither
verb joins `pairedCommandNames` until the baseline pack teaches it. It also
preserves the birth value of
`space_station#up-s-banner-is-authored-from-the-station-composition`: runner
identity remains authored by the shared composition and is not copied into a
resident-control wrapper.

### Consequences

- Good, because the runner that operates the resident station exposes both the
  pause action and its required recovery action.
- Good, because downstream runners receive the same pair through the existing
  shared builder.
- Good, because command behavior and control-door transport remain vended by
  `grid_cli` rather than forked in this package.
