# space_station

memento's grid **application + configuration** — the assembled station runner
over [the_grid](https://github.com/memento-engineering/the_grid) (framework +
CLI-SDK) and [power_station](https://github.com/memento-engineering/power_station)
(first-party asset packs).

the_grid is a framework, not a turnkey tool (the Dart runner model): a station
is a user-composed runner. This repo is a **pub workspace**:
`packages/space_station_assets` builds the `CommandRunner` (`buildRunner()`)
from the Commands memento wants — the generic CLI-SDK ones
(`watch`/`gate`/`demo` + `serve`/`lease`) plus the asset-exported `dart` (the
DART domain's `DartCommand`), plus memento's OWN resident verbs
(`up`/`down`/`status`, below) — and the thin runner app `apps/space` drives it.
A downstream station imports `space_station_assets` and extends it
(`buildRunner(name: …)..addCommand(…)`) instead of forking this repo.

**JIT only — never AOT.** Every `space` invocation runs from source
(`dart run space:space`, workspace-addressable from the repo root); there is
deliberately no committed binary. JIT keeps the VM service open (hot-reload +
lenny debugging) and guarantees current source.

## Assemble

```sh
dart pub get                       # resolves hosted releases (no siblings needed)
dart run space:space up --grid-home "$(pwd)"   # arms the coded memento org (dry-run)
```

## The resident station (`up` / `down` / `status`)

`up` is THE resident verb (RS-5b —
`the_grid/docs/SCRATCH-resident-station.md` (org-internal)):
validated agent scope, discovered workspaces, live wiring, the code asset's
registry + git `SourceControl` (per registered root, tg-7gm) — ALWAYS
resident — the ready frontier of the owned substation IS the drive set
(RS-3; `up` takes no `--bead`, ever — a drive-list is a trigger surface
under resident arming), guarded by the ONE-supervisor-per-state-store
station lock (RS-2), and observable over a read-only loopback
`StationControl` surface (RS-4). Foreground-resident: no self-daemonization,
no double-fork — a supervisor owns backgrounding, and `up --daemon` is how the
station wires one (see "Resident operation" below).

```sh
space() { dart run space:space "$@"; }     # (illustrative shorthand — always JIT)
space up --grid-home "$(pwd)" --dry-run                     # arm the coded org, observe-only
space up --grid-home "$(pwd)" --substation extra=/work/extra  # APPEND a seat (coded names refuse)
space up --grid-home "$(pwd)" --no-dry-run                  # arm the coded org, LIVE (human gate)
```

**The roster is memento's org, authored in code** (space-6ds;
`the_grid/docs/SCRATCH-memento-composition.md`, org-internal): `space_station`
IS memento's grid instance, so `SpaceDelegate.substations()` — the delegate's
roster BUILD HOOK — seats the five sibling repos (`genesis`, `the_grid`,
`power_station`, `space_station`, `lenny`) at their umbrella-sibling `../<repo>`
roots, resolved against the grid home. A downstream station SUBCLASSES the
delegate and overrides the hook (extend, never fork). No-flag `space up` arms
the coded base; a coded substation whose checkout isn't present is skipped LOUD
(the org still arms). `--substation <name>[@<prefix>]=<root>` (repeatable)
APPENDS a new seat after the roster — a coded name on a flag is REFUSED (the
roster changes in code, never by config). An operator-named substation with no
work store is still a LOUD refusal.

`down` and `status` are thin clients over the SAME `--state-workspace` `up`
was given — they read the station lock and, for `status`, attach to the
control surface; lifecycle rides OS signals (`down` SIGTERMs the holder),
never HTTP (the control surface is GET-only, by construction):

```sh
dart run space:space status --state-workspace ../tgdog --substation tg --workspace ../the_grid
dart run space:space down --state-workspace ../tgdog
```

`status` renders the live `/status` payload when a station is up, or falls
back to a direct, read-only store view — clearly labeled `(station: down)`
— when it isn't (never spawns `bd` per issue; no requery side effects).
`down` gracefully stops a live station and is a clean no-op when nothing is
up.

`run` (`CodeRunCommand`) is retired (RS-8) — `up`'s composed pieces are the
only consumer left.

## Resident operation (launchd)

`up` is **foreground-resident by design** — no self-daemonization, no
double-fork; a supervisor owns backgrounding. On macOS that supervisor is
**launchd**, and `up --daemon` is how the station wires one: it renders a
`LaunchAgent` for **this** station, writes it to `~/Library/LaunchAgents/`,
and loads it. The hand-filled `CHANGE_ME` template that used to ship here is
retired — a template earns automation once it has been operated by hand, and
it has.

### 1. Arm it

```sh
dart run space:space up --daemon --grid-home "$(pwd)" --no-dry-run
```

`--daemon` is the only token removed from the invocation launchd re-executes:
every other flag — `--no-dry-run`, `--max-agents`, `--substation`,
`--trajectory` — rides through verbatim, so a supervised boot is the same
posture as the foreground one you just typed. The recipe cannot drift from
the station it supervises, because it IS the invocation.

What gets written:

- **Label** — `grid.station.<station name>`, derived from the delegate's
  `stationName`, so a downstream station gets its own agent and can never
  bootout the station it extends.
- **ProgramArguments** — the resolved `dart` binary (launchd execs a path,
  never a name on `$PATH`), the VM flags this process was started with
  (`--enable-vm-service` survives, so a supervised station still hot-reloads),
  then `up` and your flags.
- **WorkingDirectory** — the grid home.
- **KeepAlive** — `SuccessfulExit: false`, **not** a bare `true`: launchd
  relaunches only on a non-zero or signal exit, so a graceful `down`
  (SIGTERM → exit 0) is a real stop, not an instant bounce, while a crash or
  `kill -9` IS relaunched.
- **RunAtLoad** — boots the station now and on every future login.
- **StandardOutPath / StandardErrorPath** —
  `<grid-home>/.grid/logs/<station>.{out,err}.log`.

Re-running `up --daemon` while the label is loaded is a **refusal naming the
label** — never a second resident. The verb writes nothing outside
`~/Library/LaunchAgents` and the grid home, which is why running it IS the
approval of the persistence change.

**Known:** a LaunchAgent's process gets its **own** Local Network grant, so
the first supervised boot that drives mDNS work (iOS/butane) prompts once.

### 2. Retire it

```sh
dart run space:space down --daemon
```

One `bootout` — which terminates the job — and the plist is removed.

### 3. `space status` / `space down`

Thin clients over the SAME `--state-workspace` the supervised `up` was given:

```sh
dart run space:space status --state-workspace <path> --substation <sub> --workspace <path>
dart run space:space down --state-workspace <path>
```

`status` attaches to the live `StationControl` surface when up, or falls
back to a direct, read-only store view labeled `(station: down)`. It adds one
line — `supervised: launchd <label>` — whenever launchd holds this station's
agent, which answers what the lock cannot: whether anything will bring the
station back. `down` (without `--daemon`) reads the station lock, SIGTERMs
the holder, and waits for its own graceful release — it never escalates to
SIGKILL, is a clean no-op when nothing is up, and thanks to
`SuccessfulExit: false` does not trigger a relaunch.

### 4. Logs

```sh
tail -f <grid-home>/.grid/logs/space.err.log
```

### 5. The lock

Every `up` acquires `<state-workspace>/.grid/station.lock` (RS-2, D-A1)
before anything else — one supervisor per station state store. The file is
`chmod 0600` and holds `pid`/`pgid`/`startedAt`, plus — once the control
surface mounts — `controlUrl`/`token` (RS-4's per-boot bearer token).
**The token never leaves this file**: never on argv, never logged, and the
surface it authorizes is loopback-only and read-only by construction. A live
holder refuses a second `up` LOUD, naming the pid; a dead holder (crashed
without releasing) is stolen automatically on the next `up`.

### 6. Crash recovery

The crash story is unchanged and load-bearing, whether the process dies to
`kill -9` or an uncaught crash:

```
kill -9 / crash -> launchd relaunch (RunAtLoad)
  -> freshness barrier -> RestartReconciler (respawn-or-skip; adopt once
     tg-9fl lands) -> kernel mount
```

launchd notices the exit and restarts the station (a signal death or
non-zero exit does not satisfy `SuccessfulExit: false`, so `KeepAlive`
fires). The new process re-acquires the lock — stealing the stale one the
dead pid left behind — then waits on the freshness barrier (a COMPLETED
re-query of the read + state runtimes) before deciding anything. Only then
does the `RestartReconciler` walk surviving worktrees + session beads:
done work is skipped, still-alive orphaned process groups are killed, and
everything else is marked respawn-pending for the kernel to re-mount.
Nothing is ever decided on stale state.

### 7. Best practice: one grid per machine

**One grid per machine** — one agentic fabric across the station's assets.
The lock is scoped per station STATE STORE (not per substation) precisely
so a single store supervises everything on the box; running a second,
independent grid alongside it is unsupported — two supervisors would
double-spawn agents against unrelated stores with no arbitration between
them. Want multiple independent grids? Run them in separate
containers/VMs, not side-by-side processes on bare metal.

## Dev linkage

Framework + asset packages resolve from committed hosted pub.dev constraints by default. This amends the earlier ADR-0003 D1 git-tag source because published sibling packages use hosted intra-repo dependencies, and pub cannot resolve one package from both git and hosted sources. Deliberate adoption still occurs through committed constraint bumps.

For local co-editing only, `pubspec_overrides.yaml` (gitignored) path-overrides those hosted releases into sibling `../the_grid` and `../power_station` checkouts. The dart domain's `grid dart link` generates it; see the_grid `docs/SCRATCH-pub-capability-and-repo-split.md` and ADR-0003 D5.
