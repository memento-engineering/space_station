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

## Dev linkage

Framework + asset packages are declared `any` and resolved via a machine-local
`pubspec_overrides.yaml` (gitignored) — path deps into the sibling `../the_grid`
and `../power_station` checkouts during dev. The dart domain's `grid dart link`
generates it; see the_grid `docs/SCRATCH-pub-capability-and-repo-split.md`.
