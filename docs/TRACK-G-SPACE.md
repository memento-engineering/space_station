# Track G-space (tg-33n) — `space` becomes a `GridDelegate`; the hand-mirror dies

Executes the **space half** of Track G in `the_grid/docs/GRID-SDK-BUILD-ORDER.md`
(the v3 code-as-config model, `the_grid/docs/SCRATCH-station-config-model.md`).
Absorbs **tg-da7** (the flag-mirror audit).

## What landed

- **`lib/src/space_delegate.dart` — `SpaceDelegate extends GridDelegate`.**
  space_station **authored as a Seed**: its master `build` returns the canonical
  v3 §2 tree —
  `RawAssetGrid → Station → HarnessProvider → Substations → Substation`, with each
  project's git as a **substation-scoped asset** (`GitGridAssets` /
  `GitHubGridAssets`, Track F) resolved by tree position (bead → substation →
  root), not a runner-built `ServiceBundle` map. Offline-constructible and
  covered by `test/space_delegate_test.dart` (mounts the tree in a bare
  `TreeOwner`; asserts the loud refusals and the asset seam).

- **space owns its CLI; the hand-mirror is gone.** `up_command.dart`'s
  `_addResidentStationFlags` / `_residentStationArgsFrom` — a by-hand byte-copy of
  `grid_cli`'s `addStationFlags` / `StationArgs.from`, kept "in lockstep by hand"
  — are **deleted**. Their replacement, `addSpaceStationFlags` /
  `spaceStationArgsFrom`, lives on the delegate side as **space's own** surface.

- **The verbs re-seat over the delegate.** `up` authors a `SpaceDelegate` from
  the live wiring and drives its **asset seam** (`circuitResolver` /
  `codeRegistry` / `wrapRoot` + `serviceBundleMapFor`, all owned by the delegate)
  through `composeStation`. `down` / `status` attach to the SAME state-store lock
  that delegate-driven `up` created.

- **launchd posture unchanged.** Still foreground-resident, `KeepAlive` with
  `SuccessfulExit=false`, `RunAtLoad`. The `ProgramArguments` are space's own CLI
  (comment refreshed); the AOT binary rebuilds (`dart compile exe bin/space.dart
  -o space`).

## The transitional seam (READ — honest scope)

The v3 end-state is `up` driving by **`runGrid(SpaceDelegate())`** — mounting the
delegate's `build` tree and letting the reactive loop drive. That last hop needs
the composition tree bound to the engine's live driving (`StationKernel` /
`WorkList` / the station lock / the signal-park). Track F itself defers that
binding to *"Track G's runner work"*, and it lives in **`grid_sdk` /
`grid_engine`** (the private engine — ADR-0008 D2), which are sibling repos
**outside this bead's worktree**.

Until that bridge exists, `space up` still **drives through `grid_cli`'s
station-runner primitives** (`composeStation` / `driveStation`), now sourced from
the delegate rather than a mirrored flag parser. Consequence: the flag surface
stays **arg-compatible** with `grid_cli`'s `StationArgs` (because `up` still feeds
those primitives). It gains full independence the day `up` drives through
`runGrid(this)` — the `SpaceDelegate.build` tree is already that tree, exercised
offline and ready.

**No live regression:** boot / lock / control / graceful-`down` / SIGTERM-drain
behaviour is byte-identical to before (see `test/up_down_status_smoke_test.dart`,
still green over a real resident process).

## Out of scope here (other Track G / H beads)

- **`rework` re-seat** — `rework` is `grid_cli`'s `ReworkCommand` (composed into
  `buildRunner`), not space's; re-seating it is the **grid_cli half** of Track G.
- **The `runGrid` → kernel driving bridge** — `grid_sdk` / `grid_engine` engine
  work (the prerequisite for the flags to truly diverge / the primitives to be
  deleted).
- **Fossil deletion** (Track H) — `defaultSubstation` / `substations.first` /
  `RootSpec`+`--root` grammar / the `--workspace` axis / `--state-*` flags /
  `serviceBundleMapFor` all survive here (still load-bearing for the primitive
  drive) and die in Track H once the bridge lands.

## Validation

`dart analyze` clean (one pre-existing `info`: `StationArgs.workspacePath`, the
tg-nsj back-compat alias the old code used too). `dart test` green (28). Binary
compiles and `space up --help` renders space's own flag surface.
