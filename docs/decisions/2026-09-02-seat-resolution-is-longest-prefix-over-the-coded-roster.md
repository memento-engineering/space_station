---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: seat-resolution-is-longest-prefix-over-the-coded-roster
  surfaces:
    - "packages/space_station_assets/lib/src/filing_commands.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-fvg
  legacy-id: null
---
## A bead id resolves to its seat by LONGEST-PREFIX match over the coded roster — a seat prefix MAY contain hyphens

**Decision (AI; MECHANISM only).** `storeRootForBead` maps a bead id to the
seat that mints it by testing each coded roster seat for a COMPLETE
`<prefix>-` boundary with a non-empty suffix, and taking the LONGEST match.
It does not extract a prefix from the id and compare it for equality. No
constraint is placed on the characters a prefix may hold.

**Why.** A substation's issue prefix follows its REPO NAME, and repo names may
contain hyphens: the `swift-infer` seat mints `swift-infer-zfor`. Splitting the
id at its first hyphen yielded `swift`, which no seat minted, so BOTH vended
verbs — `filing` and `approve` — refused every bead that seat mints while the
refusal itself enumerated `swift-infer@swift-infer`. The seat was structurally
unreachable. Constraining prefixes to be hyphen-free was rejected: the prefix
follows the repo name by design, and the constraint would move the failure
from the verb to the roster.

**Precedent, not invention.** the_grid already resolves bead ownership this
way — `BeadOwnershipPredicate.ownedPrefixOf` takes "the longest prefix in
[knownPrefixes] that matches at a complete `<prefix>-` boundary with a
non-empty suffix", and its own doc names this exact case (`swift-infer`
accepts `swift-infer-097`). This entry adopts that rule at space's filing
seam so the two agree; it does not invent a second ownership model.

**Consequences.** An id no coded seat mints is still refused LOUD, and the
refusal still enumerates the coded seats — it now quotes the whole bead id
rather than an extracted prefix, because no single extracted prefix exists.
An id with an empty suffix (`pow-`) or no hyphen at all (`space`) is refused;
the old equality path would have resolved the latter.

**Affects:** `packages/space_station_assets/lib/src/filing_commands.dart`
(`storeRootForBead`), which backs both Commands built by
`buildSpaceFilingCommands`.
