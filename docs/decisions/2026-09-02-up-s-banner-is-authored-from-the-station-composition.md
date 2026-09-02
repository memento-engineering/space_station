---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: up-s-banner-is-authored-from-the-station-composition
  surfaces:
    - "packages/space_station_assets/lib/src/station_banner.dart"
    - "packages/space_station_assets/lib/src/up_command.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-grl
  legacy-id: null
---
## `up`'s banner is authored from the station composition — and space's boot line loses its repo-name suffix

**Decision (AI; MECHANISM + one wording change).** `space up`'s boot line and
dev-mode line are rendered by pure functions in `station_banner.dart` from
three composed values: `buildRunner`'s `name` (the RUNNER word), the mounted
`SpaceDelegate`'s `stationName` (the STATION word) and `runnerInvocation` (the
JIT arming hint). No flag and no new config is added — the identity was
already in the composition, it simply never reached the render site.

**The wording change.** The boot line was `space up — space_station as a Seed
(runGrid)`; it is now `space up — space as a Seed (runGrid)`. The sentence's
station word is `SpaceDelegate.stationName`, which is `space`. Keeping the
`_station` suffix would have meant rendering `lunar_station` downstream, which
contradicts the shape space-grl specifies (`lunar up — lunar as a Seed
(runGrid)`), and there is no repo-name attribute on the delegate to author the
old wording from. No test asserted the old literal, so nothing churns.

**Why the arming hint is built from `runnerInvocation`, not from `name`.**
`dart run --enable-vm-service <name>:<name> up` assumes the package spec
mirrors the runner word. `runnerInvocation` is the invocation the station's own
installed manual already teaches (`AssetsCommand.runnerInvocation`), so the hint
is spliced from it and a runner whose package spec differs still prints a
command that works.

**Affects:** `packages/space_station_assets/lib/src/station_banner.dart`
(`stationBootLine`, `devModeBannerLine`, `jitArmingInvocation`),
`lib/src/up_command.dart` (`UpCommand.runnerName`, `UpCommand.runnerInvocation`),
`lib/space_station_assets.dart` (`buildRunner`); test
`test/station_banner_test.dart`.
