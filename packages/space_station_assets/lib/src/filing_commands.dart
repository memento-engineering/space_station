/// `space filing` / `space approve` / `space park` / `space unpark` /
/// `space show` — the COMPOSITION of the VENDED filing Commands from
/// `grid_assets`, never new ones.
///
/// The asset owns the domain AND its CLI component (the_grid ADR-0011 D3;
/// power_station ADR-0001): `grid_assets` ships the deterministic four-row
/// filing preflight ([FilingService]) and the approval verb over it
/// ([ApproveService] — the preflight, then ONE stamped `bd update`), plus the
/// THIN Commands over both. A station COMPOSES them with ITS resident-station
/// context. space's context is the CODED memento roster
/// ([SpaceDelegate.substations]): these verbs take a BEAD ID, and the store
/// that owns it is whichever substation mints that id's prefix —
/// [storeRootForBead] resolves it from the roster at run time, never from a
/// hardcoded list (ADR-0001: "Roster-aware, read-only across foreign stores —
/// resolves the attached/resident substations from the resident-station
/// context at run time (never a hardcoded list)"). Nothing about filing or
/// approving is reimplemented here — this file resolves the store and curries
/// the sinks.
///
/// **The grid home.** `--grid-home` names it explicitly — the option this
/// composition ADDS to each vended parser, the same act as
/// `ServeCommand(configureFlags: …)` in `buildRunner`. Absent, it is the CWD:
/// `space` is run FROM its grid home, and the installed `discover` skill calls
/// `space filing --json <id>` with no home flag.
///
/// **A relative home is refused inside the vended guard.** Every work-store
/// callback raises the absolute-path refusal from [storeRootForBead], which the
/// vended `run()` bodies call INSIDE their own error guards: nothing is read or
/// written from an ambiguously rooted work store. That is the vended posture,
/// not a fork of it — contrast `space search`, whose exit-64 `UsageException`
/// is the vended `SearchCommand`'s own guard over the flag IT owns.
///
/// **Writes.** `filing` and `show` are pure reads. `approve` WRITES the approval
/// receipt onto the WORK bead. `park` and `unpark` deliberately coordinate the
/// work bead with its SESSION bead across A37's split. The cross-store link and
/// session-lifecycle beads live in the state store at `<grid-home>/.grid/`.
library;

import 'dart:io';

import 'package:args/command_runner.dart' show Command;
import 'package:grid_assets/grid_assets.dart'
    show
        ApproveCommand,
        ApproveService,
        FilingCommand,
        FilingService,
        ParkCommand,
        ParkService,
        ShowCommand,
        ShowService,
        UnparkCommand,
        UnparkService;
import 'package:grid_sdk/grid_sdk.dart'
    show
        GridStateStore,
        SubstationScope,
        SubstationScopeStores,
        requireAbsoluteRoot;
import 'package:path/path.dart' as p;

import 'space_delegate.dart';

/// The vended filing verbs composed with this station's coded roster.
typedef SpaceFilingCommands = ({
  FilingCommand filing,
  ApproveCommand approve,
  ParkCommand park,
  UnparkCommand unpark,
  ShowCommand show,
});

/// Resolves the WORK-STORE root that owns [beadId] from the roster
/// [delegateFactory] authors, rooted at [gridHome].
///
/// The owning substation is the one whose `prefix` matches [beadId] at a COMPLETE
/// `<prefix>-` boundary with a non-empty suffix (`pow-x6k` → `pow` → the
/// `power_station` substation); when several substations match, the LONGEST
/// prefix wins (`swift-infer-zfor` → `swift-infer`, never the `swift`
/// substation it extends).
/// A prefix may itself contain hyphens — a store's issue prefix follows its
/// REPO NAME, and repo names may — so the id is never split at its first
/// hyphen. [verb] names the composing command in every refusal. Throws
/// [ArgumentError] when [gridHome] is not absolute and [StateError] when no
/// coded substation mints the id — both LOUD, never a silent fall back to the
/// CWD's store.
String storeRootForBead({
  required String verb,
  required String beadId,
  required String gridHome,
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
}) {
  final home = _resolvedHome(verb, gridHome);
  final roster = codedRosterOf(delegateFactory, gridRoot: home);
  SubstationScope? owner;
  for (final scope in roster) {
    final boundary = '${scope.prefix}-';
    if (!beadId.startsWith(boundary) || beadId.length == boundary.length) {
      continue;
    }
    if (owner == null || scope.prefix.length > owner.prefix.length) {
      owner = scope;
    }
  }
  if (owner != null) return owner.workStore.storeRoot;
  throw StateError(
    'space $verb: no substation in the CODED roster mints "$beadId". The '
    'coded substations are '
    '${[for (final scope in roster) '${scope.name}@${scope.prefix}'].join(', ')}'
    ' — the roster is CODE (SpaceDelegate.substations), never a flag.',
  );
}

/// Builds the VENDED filing Commands curried with space's resident-station
/// context.
///
/// [gridHomeDefault] resolves the home used when `--grid-home` is absent (the
/// real CWD; tests inject a fixture home). [filing], [approve], [park],
/// [unpark], and [show] are the vended services (tests inject a scripted `bd`
/// runner and drive the verbs offline). [delegateFactory] names WHICH
/// [SpaceDelegate] subclass authors the roster the bead id is resolved
/// against. [out]/[err] default to the process sinks.
SpaceFilingCommands buildSpaceFilingCommands({
  String Function() gridHomeDefault = _currentDirectory,
  FilingService filing = const FilingService(),
  ApproveService? approve,
  ParkService? park,
  UnparkService? unpark,
  ShowService? show,
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
  StringSink? out,
  StringSink? err,
}) {
  late final FilingCommand filingCommand;
  late final ApproveCommand approveCommand;
  late final ParkCommand parkCommand;
  late final UnparkCommand unparkCommand;
  late final ShowCommand showCommand;

  String homeOf(Command<int> command) {
    final flag = command.argResults?.option('grid-home')?.trim();
    return flag == null || flag.isEmpty ? gridHomeDefault() : flag;
  }

  filingCommand = FilingCommand(
    service: filing,
    // Called from INSIDE the vended run(), after its own "exactly one bead id"
    // usage check has passed — `rest.single` is safe here and nowhere earlier.
    storeRoot: () => storeRootForBead(
      verb: 'filing',
      beadId: filingCommand.argResults!.rest.single.trim(),
      gridHome: homeOf(filingCommand),
      delegateFactory: delegateFactory,
    ),
    out: out,
    err: err,
  );
  approveCommand = ApproveCommand(
    service: approve,
    storeRoot: () => storeRootForBead(
      verb: 'approve',
      beadId: approveCommand.argResults!.rest.single.trim(),
      gridHome: homeOf(approveCommand),
      delegateFactory: delegateFactory,
    ),
    // The state store carrying the cross-store link beads is `<home>/.grid/`
    // (GridStateStore.runtimeDir). Deliberately UNGUARDED: the vended run()
    // resolves the state root BEFORE entering its error guard, so raising the
    // absolute-home refusal here would escape as a bare stack trace. It is
    // raised from storeRoot above instead, where the vended guard catches it
    // and reports it LOUD on stderr.
    stateRoot: () => GridStateStore(
      gridRoot: p.normalize(homeOf(approveCommand)),
    ).runtimeDir,
    out: out,
    err: err,
  );
  parkCommand = ParkCommand(
    service: park,
    workStoreRoot: (beadId) => storeRootForBead(
      verb: 'park',
      beadId: beadId,
      gridHome: homeOf(parkCommand),
      delegateFactory: delegateFactory,
    ),
    stateRoot: () => homeOf(parkCommand),
    out: out,
    err: err,
  );
  unparkCommand = UnparkCommand(
    service: unpark,
    workStoreRoot: (beadId) => storeRootForBead(
      verb: 'unpark',
      beadId: beadId,
      gridHome: homeOf(unparkCommand),
      delegateFactory: delegateFactory,
    ),
    stateRoot: () => homeOf(unparkCommand),
    out: out,
    err: err,
  );
  showCommand = ShowCommand(
    service: show,
    // Show's vended callback takes no id, so read it inside the command's run
    // guard after the exactly-one-bead check has succeeded.
    storeRoot: () => storeRootForBead(
      verb: 'show',
      beadId: showCommand.argResults!.rest.single.trim(),
      gridHome: homeOf(showCommand),
      delegateFactory: delegateFactory,
    ),
    stateRoot: () => homeOf(showCommand),
    out: out,
    err: err,
  );
  for (final command in <Command<int>>[
    filingCommand,
    approveCommand,
    parkCommand,
    unparkCommand,
    showCommand,
  ]) {
    command.argParser.addOption(
      'grid-home',
      help:
          "The grid's HOME (absolute). Absent, the CWD — `space` is run FROM "
          "its grid home. The bead id's prefix is resolved against the coded "
          'roster this home roots.',
    );
  }
  return (
    filing: filingCommand,
    approve: approveCommand,
    park: parkCommand,
    unpark: unparkCommand,
    show: showCommand,
  );
}

String _resolvedHome(String verb, String raw) =>
    p.normalize(requireAbsoluteRoot(raw, 'space $verb --grid-home'));

String _currentDirectory() => Directory.current.path;
