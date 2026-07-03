/// Shared plumbing for `space down`/`space status` (RS-5b) — both are thin
/// renders over `grid_cli`'s [StationAttach] (RS-5a): read the SAME
/// `--state-workspace` an `up` was given, resolve it to the discovered
/// [BeadsWorkspace] root (the identical root `driveStation`'s station lock
/// (RS-2) is scoped to), and hand that root to [StationAttach]. Neither verb
/// re-derives arming/ownership — the lock is the only address that matters.
library;

import 'package:beads_dart/beads_dart.dart' show BeadsWorkspace;

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

/// The discovered state workspace.
class StateWorkspaceFound extends StateWorkspaceResult {
  /// Wraps the discovered [workspace].
  const StateWorkspaceFound(this.workspace);

  /// The discovered workspace.
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
  final workspace = BeadsWorkspace.discover(start: stateWorkspacePath);
  if (workspace == null) {
    return StateWorkspaceRefusal(
      'space $verb: no .beads/ state workspace found from '
      '$stateWorkspacePath (--state-workspace)',
      code: 1,
    );
  }
  return StateWorkspaceFound(workspace);
}
