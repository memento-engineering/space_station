# space_station

memento's grid **application + configuration** — the assembled station runner
over [the_grid](https://github.com/memento-engineering/the_grid) (framework +
CLI-SDK) and [power_station](https://github.com/memento-engineering/power_station)
(first-party asset packs).

the_grid is a framework, not a turnkey tool (the Dart runner model): a station
is a user-composed, AOT-compiled runner. `lib/space_station.dart` builds the
`CommandRunner` (`buildRunner()`) from the Commands memento wants — the generic
CLI-SDK ones (`watch`/`gate`/`demo` + `serve`/`lease`) plus the asset-exported
ones (`run` = the code asset's `CodeRunCommand`, `dart` = the DART domain's
`DartCommand`), plus memento's OWN resident verbs (`up`/`down`/`status`,
below); `bin/space.dart` drives it.

## Assemble

```sh
dart pub get                              # needs the sibling checkouts + overrides
dart compile exe bin/space.dart -o space  # the AOT station binary
./space run --substation tg --bead tg-… --dry-run
```

## The resident station (`up` / `down` / `status`)

`up` is THE resident verb (RS-5b —
[`the_grid/docs/SCRATCH-resident-station.md`](../the_grid/docs/SCRATCH-resident-station.md)):
the same composed pieces `run` assembles (validated agent scope,
discovered workspaces, live wiring, the code asset's registry + git
`SourceControl`), but ALWAYS resident — the ready frontier of the owned
substation IS the drive set (RS-3; `up` takes no `--bead`, ever — a
drive-list is a trigger surface under resident arming), guarded by the
ONE-supervisor-per-state-store station lock (RS-2), and observable over a
read-only loopback `StationControl` surface (RS-4). Foreground-resident: no
self-daemonization, no double-fork — a supervisor (launchd; the runbook is
RS-6) owns backgrounding.

```sh
./space up --substation tg --state-workspace ../tgdog --dry-run   # observe-only
./space up --substation tg --state-workspace ../tgdog --root . --no-dry-run
```

`down` and `status` are thin clients over the SAME `--state-workspace` `up`
was given — they read the station lock and, for `status`, attach to the
control surface; lifecycle rides OS signals (`down` SIGTERMs the holder),
never HTTP (the control surface is GET-only, by construction):

```sh
./space status --state-workspace ../tgdog --substation tg --workspace ../the_grid
./space down --state-workspace ../tgdog
```

`status` renders the live `/status` payload when a station is up, or falls
back to a direct, read-only store view — clearly labeled `(station: down)`
— when it isn't (never spawns `bd` per issue; no requery side effects).
`down` gracefully stops a live station and is a clean no-op when nothing is
up.

`run` ([`CodeRunCommand`]) stays exactly as it is — transitional scaffolding
until RS-8 retires it once the first live `up` arm is proven.

## Resident operation (launchd, RS-6)

`up` is **foreground-resident by design** — no self-daemonization, no
double-fork; a supervisor owns backgrounding. On macOS that supervisor is
**launchd**, recipe-first (D-R3): a `LaunchAgent` plist template ships at
[`tool/launchd/engineering.memento.space.plist`](tool/launchd/engineering.memento.space.plist)
plus this runbook. There is deliberately **no `space install` command yet** —
a template earns automation only after it's been operated by hand.

### 1. Compile

launchd execs a binary path directly (no `dart run`, no shell), so ship the
AOT artifact the template's `ProgramArguments` points at:

```sh
dart compile exe bin/space.dart -o space
```

### 2. Install

Copy the template into `~/Library/LaunchAgents/`, fill in every `CHANGE_ME`
placeholder (the `space` binary path, `--state-workspace`, `--substation`,
`--root`, `WorkingDirectory`, and both log paths — **launchd does not expand
`~` or `$HOME`**, so the log paths need your real home directory), lint it,
then bootstrap it into your GUI session:

```sh
mkdir -p ~/Library/Logs/space_station
cp tool/launchd/engineering.memento.space.plist ~/Library/LaunchAgents/
$EDITOR ~/Library/LaunchAgents/engineering.memento.space.plist   # fill in CHANGE_ME
plutil -lint ~/Library/LaunchAgents/engineering.memento.space.plist   # must print "OK"
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/engineering.memento.space.plist
```

`RunAtLoad` boots the station immediately and on every future login.

### 3. Stop / uninstall

```sh
launchctl bootout gui/$UID/engineering.memento.space
```

`bootout` unregisters the job outright — no relaunch, doesn't survive
reboot. Prefer this for retiring the recipe; prefer `space down` (next
section) to stop the *current* run without unregistering.

### 4. `space status` / `space down`

Thin clients over the SAME `--state-workspace` the plist's `up` was given:

```sh
./space status --state-workspace <path> --substation <sub> --workspace <path>
./space down --state-workspace <path>
```

`status` attaches to the live `StationControl` surface when up, or falls
back to a direct, read-only store view labeled `(station: down)`. `down`
reads the station lock, SIGTERMs the holder, and waits for its own graceful
release — it never escalates to SIGKILL, and is a clean no-op when nothing
is up. Because the template's `KeepAlive` uses `SuccessfulExit: false`
(not a bare `true`), launchd relaunches ONLY on a non-zero/signal exit —
`down`'s graceful SIGTERM → exit 0 does **not** trigger an instant respawn,
so it's a real stop, not a bounce.

### 5. Logs

`StandardOutPath`/`StandardErrorPath` point at
`~/Library/Logs/space_station/space.{out,err}.log`:

```sh
tail -f ~/Library/Logs/space_station/space.err.log
```

### 6. The lock

Every `up` acquires `<state-workspace>/.grid/station.lock` (RS-2, D-A1)
before anything else — one supervisor per station state store. The file is
`chmod 0600` and holds `pid`/`pgid`/`startedAt`, plus — once the control
surface mounts — `controlUrl`/`token` (RS-4's per-boot bearer token).
**The token never leaves this file**: never on argv, never logged, and the
surface it authorizes is loopback-only (`127.0.0.1`) and read-only by
construction. A live holder refuses a second `up` LOUD, naming the pid;
a dead holder (crashed without releasing) is stolen automatically on the
next `up`.

### 7. Crash recovery

The crash story is unchanged and load-bearing, whether the process dies to
`kill -9` or an uncaught crash:

```
kill -9 / crash → launchd relaunch (RunAtLoad)
  → freshness barrier → RestartReconciler (respawn-or-skip; adopt once
    tg-9fl lands) → kernel mount
```

launchd notices the exit and restarts the binary (a signal death or
non-zero exit does not satisfy `SuccessfulExit: false`, so `KeepAlive`
fires). The new process re-acquires the lock — stealing the stale one the
dead pid left behind — then waits on the freshness barrier (a COMPLETED
re-query of the read + state runtimes) before deciding anything. Only then
does the `RestartReconciler` walk surviving worktrees + session beads:
done work is skipped, still-alive orphaned process groups are killed, and
everything else is marked respawn-pending for the kernel to re-mount.
Nothing is ever decided on stale state.

### 8. Best practice: one grid per machine

**One grid per machine** — one agentic fabric across the station's assets.
The lock is scoped per station STATE STORE (not per substation) precisely
so a single store supervises everything on the box; running a second,
independent grid alongside it is unsupported — two supervisors would
double-spawn agents against unrelated stores with no arbitration between
them. Want multiple independent grids? Run them in separate
containers/VMs, not side-by-side processes on bare metal.

## Dev linkage

Framework + asset packages are declared `any` and resolved via a machine-local
`pubspec_overrides.yaml` (gitignored) — path deps into the sibling `../the_grid`
and `../power_station` checkouts during dev. The dart domain's `grid dart link`
generates it; see the_grid `docs/SCRATCH-pub-capability-and-repo-split.md`.
