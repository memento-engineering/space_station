---
status: accepted
date: 2026-09-02
decision-makers: ["nico", "agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: org-intake-is-armed-per-seat-under-the-org-app
  surfaces:
    - "packages/space_station_assets/lib/src/space_delegate.dart"
  obsoletes: []
  updates: ["the-memento-org-app-identity-is-one-const-carried-per-seat"]
  obsoleted-by: null
  updated-by: []
  bead: space-3ds
  legacy-id: null
---
## Org intake is armed PER SEAT, under the org App's installation

**Decision.** The six org seats authored by `SpaceDelegate.substations()` each
carry their own `githubPoll` VALUE: `owner: 'memento-engineering'`, `repository`
and `substation` both equal to the SEAT NAME, and `installationId: '152260260'`
— the same installation the seats already deliver under as `kMementoOrgApp`. The
`interval`, `minimumSpacing` and `arm` defaults (1 minute, 5 seconds, live) are
left unauthored.

**The gap this closes.** Every org seat already carried the memento App as its
delivery identity, but no seat carried a `githubPoll`, so `SubstationSeed.build`
never mounted a reconciler for any of them (`substation_seed.dart:212-215`,
guarded on `githubPoll != null`). Intake read as healthy because an absent seed
raises no flare. The cost was manual: on 2026-08-25 four open org issues had to
be hand-filed as beads, and one had sat unintaken for three weeks.

**WHERE (human ruling, Nico, 2026-08-25).** The org roster is armed HERE, in
`SpaceDelegate.substations()`. That method is the subclass override point a
downstream station composes through `super`, and an org and a personal station
differ only in the VALUES their `substations()` passes. Arming org intake in a
downstream station would fork the org roster; arming it here means every station
that inherits through `super` gets it.

**WHAT (AI).** One App, not two. The poll installation IS the delivery
installation, so a seat's GitHub identity is one fact rather than two that can
drift. Because the config is `const`, `installationId` is written as the literal
`'152260260'` rather than as `kMementoOrgApp.installationId`; a test pins the
two value-equal.

**ONE STATION OWNS INTAKE FOR THESE REPOS**, exactly as it owns delivery:
whichever station runs resident polls all six, and two resident stations over the
same umbrella would intake the same issues twice. The one-grid-per-machine rule
fences that.

**What this entry does NOT decide.** The seats' `landingPolicy` stays null — the
deliver / commit-only selection is space-9d0's. Threading a `prOpener` into
APPENDED seats is space-sph's. Neither field nor seam is touched here.

**Consequences.** The six values duplicate `owner` and `installationId` six
times; they are pinned per seat by test rather than shared through a const, so a
partial edit fails a test instead of being structurally impossible. And intake
files beads with `--defer` (`github_grid_assets`
`src/intake/github_intake_store.dart:93`), so an intaken issue still needs a
governor to refine and approve it before anything drives — that posture belongs
to `github_grid_assets` and is unchanged here.

**Affects:** `packages/space_station_assets/lib/src/space_delegate.dart`
(`SpaceDelegate.substations`); tests `test/memento_roster_test.dart`,
`test/space_delegate_test.dart`.
