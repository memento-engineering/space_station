---
status: accepted
date: 2026-09-09
decision-makers:
  - "governor"
consulted: []
informed: []
register:
  spec: 1
  slug: spec-writer-widens-work-registry-override
  surfaces:
    - "packages/space_station_assets/lib/src/up_command.dart"
    - "packages/space_station_assets/lib/src/space_delegate.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-q93
  legacy-id: null
---

# The specify writer widens the work-registry override

## Context and Problem Statement

A specify round wipes a bead's authored acceptance criteria and design unless
the code registry is built with the assembly-owned
`SpecifyAuthoredSpecWriter` (grid_assets 0.6.0-rc.24, power_station#279).
`space_station_assets` builds that registry through
`SpaceDelegate.buildWorkRegistry`, which today takes only the station-owned
note appender, and every downstream station overrides that method to compose
its own registries. The writer therefore cannot reach the registry without a
change to the override's shape, and whatever shape is chosen is inherited by
every station that extends the delegate.

## Considered Options

* (A) Coordinated widening: `SpaceDelegate.buildWorkRegistry` accepts the note
  appender and the `SpecifyAuthoredSpecWriter` as two required positional
  parameters, and every override widens in step.
* (B) A sidecar hook: keep the one-parameter override and add a separate seam
  that hands the writer to the base registry. Rejected because a downstream
  station's own registry composition (lunar's burn registry over the code
  registry) must receive the writer itself; a sidecar would leave the
  override's registry writer-less and the wipe in place.

## Decision Outcome

Branch (A). `SpaceDelegate.buildWorkRegistry` takes the station-owned note
appender and the `SpecifyAuthoredSpecWriter` as two required positional
parameters, and `up` threads the assembly-owned writer through it. Every
override must widen to the new signature; there is no one-parameter
compatibility path. Because the override is a public seam, the package starts
the breaking minor `0.4.0-rc.1`, and each downstream station adopts it with
its own version bump.

### Consequences

* Good, because the writer reaches every station's code registry by
  construction, so a specify round can no longer wipe authored specs anywhere
  the delegate is extended.
* Good, because the override has one shape, so a station that fails to widen
  fails to compile instead of silently building a writer-less registry.
* Bad, because the widening is breaking: every extending station must bump
  and migrate its override before it can adopt the release.
