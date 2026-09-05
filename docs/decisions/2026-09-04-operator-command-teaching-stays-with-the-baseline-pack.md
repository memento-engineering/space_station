---
status: accepted
date: 2026-09-04
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: operator-command-teaching-stays-with-the-baseline-pack
  surfaces:
    - "packages/space_station_assets/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-eqh
  legacy-id: null
---
## Operator command teaching stays with the baseline pack

**Decision.** `space_station_assets` owns and exposes the command half of the
operator pairing through `buildRunnerComposition`. The baseline
`GridAssetsPack` published by power_station owns the paired skill files and
their `teaches` claims. The accepted pairs are:

- `assets` — `grid_assets/skill/asset-author`
- `search` — `grid_assets/skill/discover`
- `filing` — `grid_assets/skill/intake-refinement`
- `approve` — `grid_assets/skill/intake-refinement`
- `link` — `grid_assets/skill/intake-refinement`
- `up` — `grid_assets/skill/station-operations`
- `down` — `grid_assets/skill/station-operations`
- `status` — `grid_assets/skill/station-operations`

`watch`, `reload`, `gate`, `rework`, `dart`, `serve`, `lease`, `unlink`,
`prime`, and `seat` remain outside the pairing. Their presence on the runner
does not create a teaching claim.

**Ownership boundary.** Space composes the commands but ships no `extension/`
root and no `SKILL.md`. It does not copy, move, or re-author the baseline
skills. The coverage fence consumes `GridAssetRegistry`,
`GridAssetsPack.definition`, and `resolveGridAssets`; it does not scan files,
read a pubspec, or create another asset authority. A paired skill's removal,
canonical-key rename, or selector exclusion must refuse with both the untaught
command and its former canonical teacher key.

**Accepted precedents.** This applies
`power_station#adr-0001-packaged-ai-asset-skill-command-coupling`: a packaged
AI asset vends a coupled agentic file and deterministic command. It also
applies `the_grid#adr-0008-authoring-sdk-and-reentrant-engine`: `grid_assets`
is the bare baseline pack and consumers compose rather than subclass it. The
local decision
`space_station#the-typed-seat-arming-mechanism-is-consumed-from-grid-assets`
already rules that “mechanism is vended, posture is not.” Composing the vended
`GridAssetsPack.definition` and `GridAssetRegistry` in the same public runner
library extends that precedent: power_station vends the neutral teaching
mechanism, while space retains only its runner composition posture.

**Consequence.** A published baseline-pack change cannot silently strand one
of the paired space commands. The public composition exposes the exact command
instances' derived names and the reachable registry together, and the offline
mutation probes hold the cross-package ownership boundary closed.
