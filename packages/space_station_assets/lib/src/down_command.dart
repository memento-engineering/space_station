/// `space down` — RS-5b (tg-3s8.6, `the_grid/docs/SCRATCH-resident-station.md`
/// D-C3): resolves the state-store address and delegates lock interpretation
/// and OS signaling to `grid_cli`'s [StationAttach.stop] (RS-5a). Lifecycle
/// rides OS signals, never HTTP (D-C3): this command does not classify it from
/// nullable `controlUrl`, `token`, or `vmServiceUri` advertisements, mutate the
/// lock file itself, or escalate to SIGKILL (that is a human/supervisor call).
///
/// Track G-space (tg-33n): the station it stops is the one `up` boots from its
/// `SpaceDelegate`; `down` re-seats over that station by attaching to the SAME
/// state-store lock (`--state-workspace`), never re-deriving arming/ownership.
///
/// `--daemon` is the OTHER axis (space-5lh): it retires the launchd
/// LaunchAgent `up --daemon` installed — one `bootout` (which terminates the
/// job) and the plist removed — rather than signalling the current run. Plain
/// `down` remains the way to stop the CURRENT run without unregistering the
/// agent; because `KeepAlive` is `SuccessfulExit: false`, that graceful stop
/// is a real stop and not a bounce.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
// ignore: implementation_imports
import 'package:grid_cli/src/station_attach.dart'
    show AlreadyDown, StationAttach, Stopped, TimedOut;

import 'attach_support.dart';
import 'launch_agent.dart';
import 'space_delegate.dart';

/// `space down`: gracefully stops the resident station.
class DownCommand extends Command<int> {
  /// Creates the down command.
  ///
  /// [delegateFactory] supplies the STATION word the launchd label derives
  /// from, [environment] is the INJECTED process environment the LaunchAgents
  /// directory resolves through, and [launchctl] / [launchAgentsDirectory] are
  /// the supervisor seams a test binds.
  DownCommand({
    SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
    Map<String, String> environment = const <String, String>{},
    Launchctl launchctl = const ProcessLaunchctl(),
    String? launchAgentsDirectory,
    void Function(String message)? out,
    void Function(String message)? err,
  }) : _delegateFactory = delegateFactory,
       _environment = environment,
       _launchctl = launchctl,
       _launchAgentsDirectory = launchAgentsDirectory,
       _out = out ?? stdout.writeln,
       _err = err ?? stderr.writeln {
    argParser
      ..addOption('state-workspace', help: stateWorkspaceHelp)
      ..addFlag(
        'daemon',
        negatable: false,
        help:
            'Retire the launchd LaunchAgent instead: one bootout (which stops '
            'the job) and the plist removed. macOS only.',
      );
  }

  final SpaceDelegateFactory _delegateFactory;

  /// The INJECTED process environment; `HOME` locates `~/Library/LaunchAgents`.
  final Map<String, String> _environment;

  /// The `launchctl` client, INJECTED so a test never mutates the operator's
  /// real launchd domain.
  final Launchctl _launchctl;

  /// An explicit LaunchAgents directory; absent, derived from [_environment].
  final String? _launchAgentsDirectory;

  /// The verb's sinks, INJECTED; they default to the process streams.
  final void Function(String message) _out;
  final void Function(String message) _err;

  @override
  final String name = 'down';

  @override
  final String description =
      'Gracefully stop the resident station (RS-5b): read the station lock '
      '(RS-2) at --state-workspace, SIGTERM the holder, and wait for its own '
      'graceful-shutdown release. A clean no-op when nothing is up.';

  @override
  Future<int> run() async {
    if (argResults!.flag('daemon')) return await _stopDaemon();
    final resolved = resolveStateWorkspace(
      verb: 'down',
      stateWorkspacePath: argResults!.option('state-workspace'),
    );
    switch (resolved) {
      case StateWorkspaceRefusal(:final message, :final code):
        _err(message);
        return code;
      case StateWorkspaceFound(:final home):
        final result = await StationAttach().stop(stateWorkspaceDir: home);
        switch (result) {
          case AlreadyDown():
            _out('down: already down — no live station at $home.');
            return 0;
          case Stopped(:final pid):
            _out('down: stopped station (pid $pid) — the lock is released.');
            return 0;
          case TimedOut(:final pid):
            _err(
              'down: SIGTERM sent to pid $pid but it did not exit (and '
              'release its lock) within the grace window — this client '
              'NEVER escalates to SIGKILL. Investigate pid $pid directly.',
            );
            return 1;
        }
    }
  }

  /// Boots out this station's LaunchAgent and removes its plist.
  Future<int> _stopDaemon() async {
    if (!Platform.isMacOS) {
      _err(
        'down: --daemon retires a launchd LaunchAgent, which is macOS only.',
      );
      return 64;
    }
    final directory =
        _launchAgentsDirectory ?? launchAgentsDirectoryFor(_environment);
    if (directory == null) {
      _err(
        'down: --daemon needs HOME to locate ~/Library/LaunchAgents, and this '
        'process was handed no HOME.',
      );
      return 64;
    }
    final supervisor = LaunchAgentSupervisor(
      stationName: codedStationNameOf(_delegateFactory),
      launchAgentsDirectory: directory,
      launchctl: _launchctl,
    );
    final outcome = await supervisor.stop();
    switch (outcome) {
      // The two halves are reported as they actually happened. They can
      // disagree — a plist hand-deleted under a loaded job, a job booted out
      // by hand leaving its recipe — and a line claiming a deletion that did
      // not happen is precisely what hides that tampering.
      case DaemonStopped(
        :final label,
        :final plistPath,
        :final wasLoaded,
        :final removedPlist,
      ):
        _out(switch ((wasLoaded, removedPlist)) {
          (true, true) =>
            'down: booted out $label and removed $plistPath — launchd no '
                'longer supervises this station.',
          (true, false) =>
            'down: booted out $label — launchd no longer supervises this '
                'station. There was no plist at $plistPath to remove; the '
                'recipe had already been deleted by hand.',
          (false, true) =>
            'down: $label was not loaded; removed the stale recipe at '
                '$plistPath.',
          // Unreachable: neither half is DaemonNotSupervised, above.
          (false, false) =>
            'down: nothing to retire — launchd does not hold $label and there '
                'is no plist at $plistPath.',
        });
        return 0;
      case DaemonNotSupervised(:final label, :final plistPath):
        _out(
          'down: nothing to retire — launchd does not hold $label and there '
          'is no plist at $plistPath.',
        );
        return 0;
      case DaemonStopRefused(:final label, :final plistPath, :final message):
        _err(
          'down: launchctl refused to bootout $label — $message. The plist at '
          '$plistPath is left in place; investigate the job directly.',
        );
        return 1;
    }
  }
}
