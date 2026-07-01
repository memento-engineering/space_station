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
`DartCommand`); `bin/space.dart` drives it.

## Assemble

```sh
dart pub get                              # needs the sibling checkouts + overrides
dart compile exe bin/space.dart -o space  # the AOT station binary
./space run --substation tg --bead tg-… --dry-run
```

## Dev linkage

Framework + asset packages are declared `any` and resolved via a machine-local
`pubspec_overrides.yaml` (gitignored) — path deps into the sibling `../the_grid`
and `../power_station` checkouts during dev. The dart domain's `grid dart link`
generates it; see the_grid `docs/SCRATCH-pub-capability-and-repo-split.md`.
