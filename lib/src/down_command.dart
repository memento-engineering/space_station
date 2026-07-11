/// `space down` — RS-5b (tg-3s8.6, `the_grid/docs/SCRATCH-resident-station.md`
/// D-C3): a thin render over `grid_cli`'s [StationAttach.stop] (RS-5a).
/// Lifecycle rides OS signals, never HTTP (D-C3) — this command reads the
/// station lock, SIGTERMs the holder, and waits for the target's OWN
/// graceful-shutdown release; it never mutates the lock file itself and never
/// escalates to SIGKILL (that is a human/supervisor call).
///
/// Track G-space (tg-33n): the station it stops is the one `up` boots from its
/// `SpaceDelegate`; `down` re-seats over that station by attaching to the SAME
/// state-store lock (`--state-workspace`), never re-deriving arming/ownership.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart'
    show AlreadyDown, StationAttach, Stopped, TimedOut;

import 'attach_support.dart';

/// `space down`: gracefully stops the resident station.
class DownCommand extends Command<int> {
  /// Creates the down command.
  DownCommand() {
    argParser.addOption('state-workspace', help: stateWorkspaceHelp);
  }

  @override
  final String name = 'down';

  @override
  final String description =
      'Gracefully stop the resident station (RS-5b): read the station lock '
      '(RS-2) at --state-workspace, SIGTERM the holder, and wait for its own '
      'graceful-shutdown release. A clean no-op when nothing is up.';

  @override
  Future<int> run() async {
    final resolved = resolveStateWorkspace(
      verb: 'down',
      stateWorkspacePath: argResults!.option('state-workspace'),
    );
    switch (resolved) {
      case StateWorkspaceRefusal(:final message, :final code):
        stderr.writeln(message);
        return code;
      case StateWorkspaceFound(:final home):
        final result = await StationAttach().stop(stateWorkspaceDir: home);
        switch (result) {
          case AlreadyDown():
            stdout.writeln('down: already down — no live station at $home.');
            return 0;
          case Stopped(:final pid):
            stdout.writeln(
              'down: stopped station (pid $pid) — the lock is released.',
            );
            return 0;
          case TimedOut(:final pid):
            stderr.writeln(
              'down: SIGTERM sent to pid $pid but it did not exit (and '
              'release its lock) within the grace window — this client '
              'NEVER escalates to SIGKILL. Investigate pid $pid directly.',
            );
            return 1;
        }
    }
  }
}
