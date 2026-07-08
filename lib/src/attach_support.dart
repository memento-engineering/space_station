/// Shared plumbing for `space down`/`space status` (RS-5b) — both are thin
/// renders over `grid_cli`'s [StationAttach] (RS-5a): read the SAME
/// `--state-workspace` an `up` was given, resolve it to the discovered
/// [BeadsWorkspace] root (the identical root `driveStation`'s station lock
/// (RS-2) is scoped to), and hand that root to [StationAttach]. Neither verb
/// re-derives arming/ownership — the lock is the only address that matters.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show BeadsWorkspace;
import 'package:path/path.dart' as p;

/// Adds the ONE flag `down`/`status` need to find the lock: the SAME
/// `--state-workspace` `up` was given. Unlike `up`'s station flags, this is
/// REQUIRED (no cwd-discovery default) — the state store is never guessed
/// (A36/A37's discipline: it must never default from a read `--workspace`).
const String stateWorkspaceHelp =
    'The the_grid-owned state workspace whose station.lock (RS-2, D-A1) this '
    'verb attaches to — the SAME --state-workspace `up` was given. Required '
    '(the lock is scoped per station state store; never guessed).';

/// Resolves `--state-workspace` to its discovered [BeadsWorkspace] — or a
/// [StateWorkspaceRefusal] naming exactly what went wrong (missing flag, or
/// no discoverable `.beads/` at that path).
sealed class StateWorkspaceResult {
  const StateWorkspaceResult();
}

/// The resolved grid home + its state store.
class StateWorkspaceFound extends StateWorkspaceResult {
  /// Wraps the grid [home] (the lock's scope — `<home>/.grid/station.lock`)
  /// and the parsed state-store [workspace] (rooted at `<home>/.grid`).
  const StateWorkspaceFound({required this.home, required this.workspace});

  /// The grid home — the SAME `--grid-home`/`--state-workspace` `up` was
  /// given; the RS-2 lock is scoped here.
  final String home;

  /// The parsed state store (its root is `<home>/.grid`, per Q5a).
  final BeadsWorkspace workspace;
}

/// `--state-workspace` was missing, empty, or named a path with no
/// discoverable `.beads/` — [message] is the user-facing refusal and [code]
/// the process exit code (64 = usage, 1 = environment — mirrors
/// [StationRefusal]'s convention).
class StateWorkspaceRefusal extends StateWorkspaceResult {
  /// Creates the refusal.
  const StateWorkspaceRefusal(this.message, {required this.code});

  /// The user-facing refusal text.
  final String message;

  /// The process exit code.
  final int code;
}

/// Resolves [verb]'s `--state-workspace` value ([stateWorkspacePath]) to a
/// discovered [BeadsWorkspace], or a loud, typed refusal.
StateWorkspaceResult resolveStateWorkspace({
  required String verb,
  required String? stateWorkspacePath,
}) {
  if (stateWorkspacePath == null || stateWorkspacePath.trim().isEmpty) {
    return StateWorkspaceRefusal(
      'space $verb: --state-workspace is required — the station lock (RS-2) '
      'is scoped per station state store (D-A1); pass the SAME '
      '--state-workspace `up` was given.',
      code: 64,
    );
  }
  // v3 stores-at-roots (Q5a): the grid's state store lives at
  // `<home>/.grid/.beads` — resolved EXACTLY there, never by walk-up (a
  // walk-up from the home would bind the dual-role repo's WORK store at
  // `<home>/.beads` and attach the lock to the wrong scope — A37).
  final home = stateWorkspacePath.trim();
  final runtimeDir = p.join(home, '.grid');
  if (!File(p.join(runtimeDir, '.beads', 'metadata.json')).existsSync()) {
    return StateWorkspaceRefusal(
      'space $verb: no grid state store at $runtimeDir/.beads — the grid\'s '
      'own store lives under <grid-home>/.grid/ (Q5a). Pass the SAME '
      '--grid-home `up` was given (seed a new home via the substation-init '
      'process, the_grid docs/SUBSTATION-INIT.md).',
      code: 1,
    );
  }
  final workspace = BeadsWorkspace.discover(start: runtimeDir);
  if (workspace == null || workspace.root != runtimeDir) {
    return StateWorkspaceRefusal(
      'space $verb: could not parse the grid state store at '
      '$runtimeDir/.beads (resolved: ${workspace?.root ?? 'nothing'})',
      code: 1,
    );
  }
  return StateWorkspaceFound(home: home, workspace: workspace);
}
