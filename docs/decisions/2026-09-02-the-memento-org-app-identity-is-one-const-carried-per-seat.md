---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-memento-org-app-identity-is-one-const-carried-per-seat
  surfaces:
    - "packages/space_station_assets/lib/src/space_delegate.dart"
    - "packages/space_station_assets/lib/space_station_assets.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-u8q
  legacy-id: null
---
## The memento org App identity is ONE const, carried per seat

**Decision (AI; PLACEMENT only).** The org's GitHub App identity — appId
`4529262`, installationId `152260260`, private-key variable
`GRID_GITHUB_APP_KEY_MEMENTO` — is authored ONCE as the top-level
`const kMementoOrgApp` in `space_delegate.dart` and passed as the `app:` VALUE of
each of the six org seats, rather than repeated as six inline `GitHubAppConfig`
literals. It is exported from the package barrel so a downstream station can name
the identity it inherits.

**Why one const.** Six copies of the same three fields is a drift surface: a
re-keyed installation would have to be edited in six places, and a partial edit
would be a silently mixed-identity roster. Authoring the identity once makes
"which App does the org deliver under" a single readable line.

**Why this is NOT a station-level identity.** The binding stays per substation
(pow-1rn, 2026-08-08): the const is a VALUE, not a provider. Nothing mounts it
above the substation fan-out, nothing keys it by seat name, and each seat's own
subtree mounts its own `GitHubAppClientAssets` from its own `app:` value. A seat
delivering under a different App simply passes a different value — which is
exactly how a downstream station's private seats keep their own App while
inheriting these six through `super.substations(...)`.

**What this entry does NOT decide.** The seats' `githubPoll` (org intake —
space-3ds) and `landingPolicy` (the deliver / commit-only selection — space-9d0)
stay null. Both are separate values on the same seeds, owned by those beads.

**Affects:** `packages/space_station_assets/lib/src/space_delegate.dart`
(`kMementoOrgApp`, `SpaceDelegate.substations`),
`lib/space_station_assets.dart` (the export show-list); tests
`test/memento_roster_test.dart`, `test/substation_seed_test.dart`,
`test/space_delegate_test.dart`.
