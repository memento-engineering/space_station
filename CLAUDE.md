# space_station — memento's grid home (governor's manual)

**What this repo is.** `space_station` is **memento's grid instance**: the JIT runner (`space`) that
arms a **resident `the_grid` station** over the org's substations. It is a *composition
+ config* over the_grid's CLI-SDK and `power_station`'s asset packs — **not an
engine**. It is a **pub workspace**: the thin runner app lives at `apps/space` (`bin/space.dart`
just drives), and the reusable composition lives at `packages/space_station_assets` —
`buildRunner()` assembles the Commands, `SpaceDelegate`
(`packages/space_station_assets/lib/src/space_delegate.dart`) authors the station as a tree. The
assets package is the **extend-don't-fork seam**: a downstream station (an IC's private station,
e.g. lunar) imports `space_station_assets` and composes on top — it never forks this repo. This
repo is the **gold standard for what a station repo should resemble.**

> **Org-internal references.** memento develops in an *umbrella checkout* — the org's repos cloned
> side-by-side under one directory. Paths like `../the_grid` and cross-repo doc citations
> (`the_grid/docs/…`, `power_station/docs/adr/…`, the umbrella map one level up) refer to those
> sibling checkouts and resolve only inside that layout; on GitHub they are intentionally not
> links. Nothing in *building or running this repo* needs the siblings — deps resolve from release
> tags (see Build & Test).

## The governor's posture — READ THIS FIRST

You sit here as the **governor**: the *operator* of the resident station, not an engineer of it.

- **You feed the backlog; you do not build.** The station's agents build — in the substations'
  worktrees, graded by the committee, landed as PRs. **Never edit engine or product code in this seat
  to "fix" a bead.** If work needs doing, you *file, groom, and ready a bead*; the station drives it.
- **Your levers are backlog + station ops, nothing else:**
  - **Ready (kick in)** — undefer a bead into a substation's ready frontier. **Ready = in:** a live station
    mounts an agent on it within seconds.
  - **Operate** — `space up` / `down` / `status`; read `/status`; diagnose a station that is *up but
    driving nothing*; bounce to pick up a landed fix.
  - **Refine** — stamp `validation_plan`, wire deps, stage `deferred` until a human readies it.
- **You hold the human gates.** A live `space up --no-dry-run` station *builds, commits, and
  opens PRs* — delivery is a per-substation BINDING now (every coded seat authors
  `GitHubGridAssets`), so a live arm delivers and there is no separate land flag; readying and
  bouncing it are consequential and outward-facing; confirm intent.
- **When in doubt, file a bead — do not reach for the editor.**

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Build & Test

`space_station` is a **pub workspace** (`publish_to: none` throughout): the root `pubspec.yaml`
lists the members (`apps/space`, `packages/space_station_assets`) + inline melos scripts.

**Deps are RELEASE-TAG constraints (`space-td1`, LANDED; power_station ADR-0003).** Every private
dep uses pub's [git-packages](https://dart.dev/tools/pub/dependencies#git-packages) `tag_pattern`
form — `git: {url, tag_pattern: <package>-v{{version}}, path}` plus a normal `version:` constraint,
so pub feeds the matching release tags to the VERSION SOLVER (Dart 3.9+); genesis packages resolve
HOSTED from pub.dev. A plain checkout `dart pub get`s with **no sibling checkouts and no
overrides** — space always compiles from its own source regardless of any producer's `main` (the
wedge class that stalled the tkm/#56 arc is closed), and a breaking upstream change is adopted
*deliberately* by bumping version constraints (patch/minor releases inside the constraint adopt on
the next `pub upgrade`). For **local co-development** the gitignored, machine-local
`pubspec_overrides.yaml` at the workspace root path-overrides the pins (ADR-0003 D5 — the org-dev
escape hatch; it needs the sibling checkouts). One rule when touching deps: pub unifies git deps by
**descriptor**, so every declaration of the same package (across members and producers) must carry
the identical `{url, tag_pattern, path}` — mixed forms (a bare `ref:`, a `path:` sibling) do not
unify with it.

```bash
dart pub get                              # resolves from the release tags (no siblings needed)
dart analyze                              # workspace-wide, from the root
(cd packages/space_station_assets && dart test)   # the composition suite
(cd apps/space && dart test)              # the process-level CLI smokes
dart run space:space assets install --check      # the operator assets match their vended source

# Operate the resident station (governor) — ALWAYS JIT, never an AOT binary (see below).
# All from the workspace root — `dart run space:space` is workspace-addressable:
dart run space:space status               # what the station is driving right now
dart run --enable-vm-service \            # ARM a LIVE station (builds + opens PRs); JIT keeps the VM
  space:space up --no-dry-run \           #   service open for hot-reload + lenny debugging
  --grid-home "$(pwd)"                    # ABSOLUTE path required (relative = loud refusal).
                                          # NO --substation flags for the memento roster: it is
                                          # CODED in SpaceDelegate.build() (space-6ds; currently
                                          # genesis, the_grid, power_station, space_station, lenny)
                                          # and naming a coded seat REFUSES; flags APPEND only.
dart run space:space down                 # tear down
```

**JIT only — never AOT.** The resident station and every `space` command run under `dart run` (JIT),
**never** a `dart compile exe` binary. JIT keeps the VM service open (hot-reload + lenny debugging) and
guarantees you're running *current source*, not a stale compiled artifact. There is deliberately **no
committed `./space` binary** — if you find one lying around, it's a build leftover; delete it, don't run
it. For a grid op while the runner is mid-migration, still stay JIT: the operation belongs to *space's*
composition, so run it through `dart run space:space <cmd>` — not through the_grid's `grid_cli`, which
sidesteps space's actual station workflow.

**`space reload` — the EXPLICIT hot-reload trigger.** JIT-from-source is the default dev operating
mode (the mac studio dogfoods from source), so a landed change activates **without a down/up bounce**:
`dart run space:space reload --grid-home .` connects to the RESIDENT station over the VM service it
advertised in its 0600 `.grid/station.lock`, swaps the sources, and re-composes the tree — live
sessions are ADOPTED, never killed. `--restart` re-runs the delegate factory instead of the master
build. The trigger is EXPLICIT and operator-driven: there is deliberately **no file-watcher and no
auto-reload** (an auto-reload-on-save would fire mid-build on a station that is committing and opening
PRs). Arming it is the **run mode alone** — a station booted JIT with `--enable-vm-service` registers
`ext.exploration.grid.reload` (the `up` banner then reads `dev mode: JIT … ARMED`); an AOT binary
registers nothing, reports `dev mode: OFF`, and `space reload` refuses LOUD.

**`validation_plan` shape.** With the release pins landed (`space-td1`), a per-bead worktree
resolves from the tags and just `dart pub get`s — the old absolute-cd hack (and the `tg-8uz`
override-materialization stopgap) is RETIRED. space_station beads use the same **relative** plan
shape as everyone else: `dart pub get && dart analyze && (cd packages/space_station_assets && dart
test) && (cd apps/space && dart test)`. (Existing beads stamped with the old absolute-cd plan still
run; re-stamp on next refinement.)

## Architecture Overview

**space is a station-as-a-tree.** `SpaceDelegate.build()` authors
`RawAssetGrid(gridHome) → Station → HarnessProvider(registry, config) → Substations →` per-substation
`Substation( Nest[ GitGridAssets, GitHubGridAssets?, SubstationWork ] )`. `space up` mounts it via
`runGrid(SpaceDelegate)`; armed, `StationWork` provides the engine's work-axis so each substation
drives its `.beads` ready frontier.

**The drive loop (per bead, in a worktree).** The station takes **no drive-list** (`ready` IS the
drive set — there is deliberately no `--bead`). It mounts a build agent, the **committee** gates it,
and it **lands** (commit + PR). Session states are just `open / gated / closed`.

**The front-of-house lifecycle** (design-side, being ported into `grid_assets`):
`discover` (HITL skill) → `specify` (agentic asset + its own **spec** committee) → `build` (agentic +
**code** committee) → `land`. The committee is **pluggable** — a `Circuit` over rubric ids + a
`RubricSource` fed by Packaged AI Assets + a gating rubric whose `F` hard-blocks — so a new review
type is a new rubric pack, not new machinery. The **coupled skill+command** pattern (a skill CALLS a
vended deterministic Command like `space search`, instead of inferring the operation) is
`ADR-0001, draft`.

**The roster.** The coded drive set is the five memento org seats — `genesis`, `the_grid`,
`power_station`, `space_station` (self), `lenny` — authored as literal seats in
`SpaceDelegate.substations()` (space-6ds; the subclass override point a downstream station
composes). `decisions`/`expression` join when they gain bead stores. **Coexistence:** the_grid's
work store is the shared `tg` Dolt server (gc coexists on `ga-*`); the A37 split fences session
writes to the `houston` state store so the work store stays read-only.

## Conventions & Patterns

- **Backlog is `bd`, actor is `governor`.** Every mutation `--actor governor`; reasons carry receipts.
  Stage new work `--defer <date>` (kills the mount race against a live station); let a human ready it. A
  driveable bead needs a `validation_plan`, a driveable type (`task/bug/feature/chore`), and a
  description an agent can act on alone. **Cross-store deps DO exist** — each substation is its own Dolt
  DB, but bd ships a native cross-store edge (`bd dep add <id> external:<project>:<capability>` → the
  `depends_on_external` column, resolved at query time via the `external_projects` config), and
  the_grid's federated engine already enforces cross-store BLOCKING across the substation union:
  `FederatedSnapshotSource._applyExternalDepGuard` keys `DependencyType.affectsBlocking` and fails
  closed when no member observes the target (the_grid ADR-0000 **A44**, pending). What `external:` does
  NOT give you is BEAD granularity — it says "project X shipped capability Z," not "this bead waits on
  that bead" — so homing tightly-coupled beads in ONE store stays the simplest default: a grooming
  CHOICE, not a platform limitation.
- **The memento house set** (genesis ADR-0001 D7): Dart `^3.11`, freezed + json_serializable,
  exhaustive `switch`, Fakes-not-mocks, no `print` in lib. **Terminology:** "extension," never
  "plugin"; package names are faculties/crafts, never agent-nouns.
- **Operator assets are GENERATED, never hand-edited.** `.claude/skills/` (`station-operations` —
  boot/bounce/status/diagnose; `intake-grooming` — make a bead driveable; `harvest-review` — land
  what the station built; `gate-medicine` — clear gated sessions; `discover`), `.claude/agents/governor.md`
  and `.claude/settings.json` are INSTALLED from `grid_assets`' vended `station_overlay` —
  `dart run space:space assets install` — and each carries a `generated from grid_assets@<ref>`
  stamp. The authored home is `power_station`, not here: to change a skill, change
  it there and re-install. `assets install --check` is part of the house gate and FAILS on an
  out-of-band edit. The `governor` agent is the persona for this seat — reach for these before
  improvising.
- **Standing operational hazards** (check live state before acting): the roster the armed station
  actually mounts; open **P0s in `bd ready`** — a committee-locality bug can wedge non-power_station
  grading, so a station can be *up but driving nothing*. Diagnose with `station-operations` before
  readying more. Persist durable findings with `bd remember`, not a MEMORY file.
