/// `space search` — the COMPOSITION of the VENDED `search` Command
/// (`grid_assets`' [SearchCommand]), never a new one.
///
/// The asset owns the domain AND its CLI component (the_grid ADR-0011 D3;
/// power_station ADR-0001): `grid_assets` ships the deterministic, read-only
/// cross-store search ([StationSearchService]) plus the THIN Command over it,
/// and a station COMPOSES that Command with ITS resident-station context (the
/// Command takes a `GridDelegate Function()` factory and the composing station
/// curries its context). space's context is [SpaceDelegate]: the memento
/// roster baked into its tree, enumerated by the vended `mountedRosterOf`'s
/// OFFLINE mount. Nothing about search is reimplemented here — this file only
/// curries the delegate.
///
/// **The grid home.** The coded seats are `../<repo>` siblings of the grid
/// home, so the home is the one input the composition supplies. `--grid-home`
/// names it explicitly; absent, it is the CWD — `space` is run FROM its grid
/// home (`./space search …`), and the installed `discover` skill calls
/// `space search --json <query>` with no home flag. A cwd that is NOT a grid
/// home needs no extra guard: every coded seat resolves to an absent store,
/// the report names each root, and the run exits 1 (the vended loud
/// non-answer). A RELATIVE `--grid-home` is refused LOUD (exit 64): a relative
/// grid root is the ambience the v3 model kills, and unguarded it surfaces as
/// a raw `ArgumentError` out of the tree mount.
///
/// READ-ONLY (A37): search touches no state store and no RS-2 lock — it reads
/// each seat's work store through the vended `bd export --all` seam, one spawn
/// per store, and has no mutation surface to fence.
library;

import 'dart:io';

import 'package:grid_assets/grid_assets.dart'
    show SearchCommand, StationSearchService;
import 'space_delegate.dart';

/// Builds the VENDED `search` Command curried with the station's
/// resident-station context — [delegateFactory] names WHICH [SpaceDelegate]
/// subclass authors the roster searched over (the base class absent: space's
/// posture); `mountedRosterOf` enumerates its offline mount.
///
/// [gridHomeDefault] resolves the home used when `--grid-home` is absent (the
/// real CWD; tests inject a fixture home). [service] is the vended search
/// service (tests inject a Fake source + a Fake directory probe and search
/// offline). [out]/[err] default to the process sinks.
SearchCommand buildSpaceSearchCommand({
  String Function() gridHomeDefault = _currentDirectory,
  StationSearchService service = const StationSearchService(),
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
  StringSink? out,
  StringSink? err,
}) {
  // The vended SearchCommand OWNS the --grid-home flag + absolute-path guard
  // + normalization (pow-x3b, A24-aligned): the factory receives the resolved
  // home. Search reads stores; it spawns no agent. The delegate's DEFAULT
  // agent scope (the authoring-only claude rung, ADR-0008 D10) rides — this
  // authoring-only mount never reads it.
  final command = SearchCommand(
    delegate: (gridHome) => delegateFactory(gridRoot: gridHome),
    gridHomeDefault: gridHomeDefault,
    service: service,
    out: out,
    err: err,
  );
  return command;
}

String _currentDirectory() => Directory.current.path;
