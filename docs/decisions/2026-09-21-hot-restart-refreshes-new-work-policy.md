---
status: accepted
date: 2026-09-21
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: hot-restart-refreshes-new-work-policy
  surfaces:
    - "packages/space_station_assets/lib/src/up_command.dart"
    - "packages/space_station_assets/lib/src/space_delegate.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-hjf
  legacy-id: null
---

# Hot restart refreshes new work policy

## Context and Problem Statement

The resident runner assembles station work resources once, then passes their
wiring into each delegate produced by the SDK hot-restart factory. Circuit and
capability policy was previously frozen into that assembly-time wiring. A new
delegate generation could rebuild the tree, but work first mounted after the
restart still resolved through the old generation's registry and circuit
policy.

The work runtime owns long-lived resources such as store connections,
notifiers, services, process leases, transports, trajectory recording, and
relay registration. Refreshing policy must not rebuild or re-own those
resources, and hot restart must continue to use the SDK's lifecycle so active
keyed work is adopted rather than killed and respawned.

## Considered Options

* Keep assembly-time policy until a full down/up cycle.
* Reassemble the station work runtime on every hot restart.
* Retain the runtime-owned resources and project each delegate generation's
  policy through the tree.

## Decision Outcome

Hot restart refreshes registry and circuit policy for work first mounted by the
new delegate generation. Work already active at restart remains adopted under
its existing policy: it is neither stopped nor respawned.

The station work runtime remains the sole owner of stable resources. A
non-owning refreshable wiring value copies those handles once and binds each
delegate generation's resolver and registry during `SpaceDelegate.build` via
an equality-aware inherited policy value. Restart, swap, refusal, and disposal
remain owned by the SDK's existing `GridHandle.hotRestart` lifecycle; no
parallel restart manager or `GridDelegate.boot` functionality is introduced.

`apps/space` consumes this behavior through `UpCommand`. Downstream
`SpaceDelegate` subclasses inherit it through their existing
`circuitOverrideFor` and two-argument `buildWorkRegistry` overrides, without a
constructor or restart override.

### Consequences

* Good, because registry and circuit edits affect newly mounted work after an
  explicit hot restart without requiring a full station bounce.
* Good, because active keyed work keeps one policy and one allocation for its
  lifetime.
* Good, because runtime connections and effect resources retain exactly one
  owner and one shutdown path.
* Bad, because a running station can temporarily contain active work under an
  older policy beside newly mounted work under the current generation.
