---
status: accepted
date: 2026-09-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: substation-asset-selection-is-derived-with-coded-exceptions
  surfaces:
    - "packages/space_station_assets/lib/src/substation_seed.dart"
    - "packages/space_station_assets/lib/src/space_delegate.dart"
    - "packages/space_station_assets/lib/space_station_assets.dart"
    - "packages/space_station_assets/pubspec.yaml"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-kwv
  legacy-id: null
---
## Substation asset selection is derived by default with coded exceptions

**Decision.** Actual asset selection is derived from each
`GridAssetDefinition.selector` against the substation's observed facts by the
one shipped `resolveGridAssets`. `SubstationSeed.assetRoster` carries only a
coded `GridAssetRosterOverride`: explicit includes and excludes for exceptions
that derivation cannot know. A null override means pure selector-derived
selection. It is not a per-substation manifest of the assets expected at every
repository.

**Placement.** space stores the override on the composed seat and projects the
identical value through `MountedSubstationSeed`, allowing
`codedRosterSnapshotOf` to enumerate authored exceptions from its one offline
mount. It does not evaluate selectors or resolve assets for a seat.
Per-substation resolution and root observation through
`FileSystemSubstationFactsRepository` stay upstream in the power asset pack.
`buildSpaceAssetsCommand` remains unchanged: its station-wide registry,
override, and facts-repository seams serve the operator install over the grid
home as one substation.

**Authority.** `AssetKey`, `GridAssetRosterOverride`, its include/exclude
overlap refusal, the unknown-registry refusal, selector evaluation,
`SubstationFactsSnapshot`, `GridAssetResolution`, `resolveGridAssets`, and
`FileSystemSubstationFactsRepository` remain the shipped `grid_sdk` and
`grid_assets` definitions. This repository introduces no second asset identity,
overlap guard, selector evaluator, facts value, filesystem observer, resolver,
selection wrapper, or per-substation asset manifest.
