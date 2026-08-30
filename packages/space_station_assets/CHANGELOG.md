# Changelog

## 0.2.0

API additions since 0.1.0:

- Added the `SpaceDelegate.buildWorkRegistry` and
  `SpaceDelegate.circuitOverrideFor` delegate work-policy hooks for downstream
  stations.
- Added `githubSelfTrust` forwarding through `SpaceDelegateFactory` and
  `SpaceDelegate`, providing the station-global GitHub trust value to polling
  seats.
