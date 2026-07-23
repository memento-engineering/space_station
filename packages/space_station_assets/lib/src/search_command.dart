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
    show AgentConfig, SearchCommand, StationSearchService;
import 'package:path/path.dart' as p;

import 'space_delegate.dart';

/// Builds the VENDED `search` Command curried with space's resident-station
/// context ([SpaceDelegate] — the baked memento roster).
///
/// [gridHomeDefault] resolves the home used when `--grid-home` is absent (the
/// real CWD; tests inject a fixture home). [service] is the vended search
/// service (tests inject a Fake source + a Fake directory probe and search
/// offline). [out]/[err] default to the process sinks.
SearchCommand buildSpaceSearchCommand({
  String Function() gridHomeDefault = _currentDirectory,
  StationSearchService service = const StationSearchService(),
  List<SubstationSpec>? roster,
  String stationName = 'space',
  StringSink? out,
  StringSink? err,
}) {
  late final SearchCommand command;
  command = SearchCommand(
    delegate: () {
      final flag = command.argResults?.option('grid-home')?.trim();
      final home = (flag == null || flag.isEmpty) ? gridHomeDefault() : flag;
      if (!p.isAbsolute(home)) {
        command.usageException(
          'space search: --grid-home must be an ABSOLUTE path (got "$home") — '
          'a cwd-relative grid home re-imports the ambience the v3 model kills '
          '(the coded roster resolves its ../<repo> seats against it).',
        );
      }
      return SpaceDelegate(
        gridRoot: p.normalize(home),
        stationName: stationName,
        roster: roster,
        // Search reads stores; it spawns no agent. The station-default agent
        // scope is the delegate's required ambient rung (ADR-0008 D10) — this
        // authoring-only mount never reads it.
        agentConfig: const AgentConfig(harness: 'claude'),
      );
    },
    service: service,
    out: out,
    err: err,
  );
  command.argParser.addOption(
    'grid-home',
    abbr: 'g',
    help:
        "The grid's HOME (ABSOLUTE): the root the coded memento roster's "
        '../<repo> substation seats resolve against. Defaults to the current '
        'directory — `space` is run FROM its grid home. Read-only: search '
        'attaches to no station, no state store, and no lock (A37).',
  );
  return command;
}

String _currentDirectory() => Directory.current.path;
