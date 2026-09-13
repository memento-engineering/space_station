/// The launchd supervisor surface behind `up --daemon` / `down --daemon`
/// (space-5lh).
///
/// `up` is foreground-resident by design — no self-daemonization, no
/// double-fork — so the resident is a CHILD of whichever shell booted it: it
/// dies with that session, a handoff relaunch is chaotic by construction, and
/// a machine reboot leaves a station lock naming a dead pid. `up`'s own help
/// has always said a SUPERVISOR owns backgrounding; this file is the wiring
/// for one.
///
/// The posture is unchanged from the hand-operated recipe it replaces: launchd
/// execs the `dart` binary itself with the operator's own JIT invocation
/// (JIT only — never a compiled binary), `KeepAlive` is
/// `SuccessfulExit: false` so a graceful `down` (SIGTERM → exit 0) is a REAL
/// stop and only a crash or signal death is relaunched, and `RunAtLoad` boots
/// the station now and on every future login. What changed is that the
/// station RENDERS and LOADS the agent instead of shipping a `CHANGE_ME`
/// template: the plist is derived from the invocation the operator just typed,
/// so it cannot drift from the station it supervises.
///
/// Nothing here reads the ambient process environment
/// (`no_watcher_no_gate_test` bans that under `lib/`): the LaunchAgents
/// directory arrives as a VALUE from the composition root, and the launchd
/// domain (`gui/<uid>`) is resolved by [ProcessLaunchctl] through `id -u`,
/// never through `$UID`.
///
/// KNOWN, and not solved here: a LaunchAgent's process gets its OWN Local
/// Network TCC grant, so the first supervised boot that needs mDNS prompts
/// once. The verb's help says so.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// One `launchctl` invocation's outcome.
typedef LaunchctlResult = ({int exitCode, String stdout, String stderr});

/// Runs one process on behalf of [ProcessLaunchctl].
typedef LaunchctlProcess =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// The `launchctl` verbs a station supervisor needs.
///
/// An INTERFACE because the station must be testable without mutating the
/// operator's real launchd domain: tests bind a Fake (never a mock) and assert
/// the exact call sequence.
abstract interface class Launchctl {
  /// Whether [label] is currently loaded in this session's launchd domain.
  Future<bool> isLoaded(String label);

  /// Loads the LaunchAgent at [plistPath] into this session's domain.
  Future<LaunchctlResult> bootstrap({required String plistPath});

  /// Unloads [label] from this session's domain, terminating its job.
  Future<LaunchctlResult> bootout({required String label});
}

/// The real [Launchctl]: `launchctl` over this session's GUI domain.
class ProcessLaunchctl implements Launchctl {
  /// Creates the client. [run] is the process seam.
  const ProcessLaunchctl({this.run = Process.run});

  /// How a subprocess is started.
  final LaunchctlProcess run;

  /// `gui/<uid>` — the per-user domain a LaunchAgent loads into.
  ///
  /// The uid is read from `id -u` rather than `$UID`: the environment is not
  /// readable from this library, and `$UID` is a shell variable that is not
  /// exported to child processes anyway.
  Future<String> domainTarget() async {
    final result = await run('/usr/bin/id', const ['-u']);
    final uid = '${result.stdout}'.trim();
    if (result.exitCode != 0 || uid.isEmpty) {
      throw StateError(
        'launchctl: could not resolve this session\'s uid — `id -u` exited '
        '${result.exitCode}.',
      );
    }
    return 'gui/$uid';
  }

  @override
  Future<bool> isLoaded(String label) async {
    final domain = await domainTarget();
    final result = await run('/bin/launchctl', ['print', '$domain/$label']);
    return result.exitCode == 0;
  }

  @override
  Future<LaunchctlResult> bootstrap({required String plistPath}) async {
    final domain = await domainTarget();
    final result = await run('/bin/launchctl', [
      'bootstrap',
      domain,
      plistPath,
    ]);
    return _result(result);
  }

  @override
  Future<LaunchctlResult> bootout({required String label}) async {
    final domain = await domainTarget();
    final result = await run('/bin/launchctl', ['bootout', '$domain/$label']);
    return _result(result);
  }

  LaunchctlResult _result(ProcessResult result) => (
    exitCode: result.exitCode,
    stdout: '${result.stdout}'.trim(),
    stderr: '${result.stderr}'.trim(),
  );
}

/// The launchd label for the station named [stationName].
///
/// Derived from the STATION word alone (`SpaceDelegate.stationName`), so a
/// downstream station that renames itself gets its own agent and can never
/// bootout the station it extends. Reverse-DNS-ish and org-free on purpose: a
/// private station is not memento's.
String launchAgentLabel(String stationName) => 'grid.station.$stationName';

/// `<HOME>/Library/LaunchAgents` for the INJECTED [environment], or null when
/// the process was handed no `HOME`.
///
/// The environment arrives as a VALUE from the composition root
/// (`bin/space.dart` → `buildRunner`), never read ambiently: `lib/` is barred
/// from reading the process environment directly, so no out-of-band gate can
/// grow here.
String? launchAgentsDirectoryFor(Map<String, String> environment) {
  final home = environment['HOME']?.trim();
  if (home == null || home.isEmpty) return null;
  return p.join(home, 'Library', 'LaunchAgents');
}

/// The VM arguments worth re-exec'ing under launchd.
///
/// `Platform.executableArguments` carries the VM's own self-description
/// (`--resolved_executable_name=` / `--executable_name=`) alongside the flags
/// the operator actually typed. Only the operator's survive — notably
/// `--enable-vm-service`, which is what keeps a supervised station
/// hot-reloadable.
List<String> supervisedVmArguments(List<String> executableArguments) => [
  for (final argument in executableArguments)
    if (!argument.startsWith('--resolved_executable_name=') &&
        !argument.startsWith('--executable_name='))
      argument,
];

/// The launchd `ProgramArguments` for a supervised boot: the operator's exact
/// JIT invocation, MINUS `--daemon`.
///
/// `--daemon` is the only token removed. Every other flag — `--no-dry-run`,
/// `--max-agents`, `--trajectory`, `--substation`, any future knob — rides
/// through verbatim, so a supervised boot is the same posture as the
/// foreground one the operator just typed.
///
/// [dartExecutable] is `Platform.resolvedExecutable`: launchd execs a PATH,
/// never a name looked up on `$PATH`, so the bare word `dart` in
/// [runnerInvocation] is replaced by the absolute binary running right now.
/// [vmArguments] are spliced immediately after the `run` word, where the dart
/// tool expects them.
List<String> daemonProgramArguments({
  required String dartExecutable,
  required List<String> vmArguments,
  required String runnerInvocation,
  required String verb,
  required List<String> arguments,
}) {
  final invocation = runnerInvocation
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();
  // Token 0 is the `dart` WORD; launchd needs the resolved binary instead.
  final tail = invocation.isEmpty ? <String>[] : invocation.sublist(1);
  final runIndex = tail.indexOf('run');
  final spliced = runIndex < 0
      ? [...vmArguments, ...tail]
      : [
          ...tail.sublist(0, runIndex + 1),
          ...vmArguments,
          ...tail.sublist(runIndex + 1),
        ];
  return [
    dartExecutable,
    ...spliced,
    verb,
    for (final argument in arguments)
      if (argument != '--daemon') argument,
  ];
}

/// Renders a LaunchAgent property list.
///
/// `KeepAlive` is `SuccessfulExit: false`, NOT a bare `true`: launchd then
/// relaunches only on a non-zero or signal exit, so a graceful `down`
/// (SIGTERM → exit 0) is a real stop rather than an instant bounce, while a
/// `kill -9` or a crash IS relaunched.
///
/// [environmentVariables] is the POSTURE the supervised resident inherits.
/// launchd does NOT hand a job the launching shell's environment, so a key
/// the operator exported before typing `up --daemon` reaches the supervised
/// boot only by being written here. The map arrives as a VALUE (this library
/// reads no ambient environment) and the caller keeps it to an explicit
/// allowlist — never the whole environment, which would copy every ambient
/// secret into a file under `~/Library/LaunchAgents`.
///
/// The conventional Apple DOCTYPE is deliberately OMITTED. Its system
/// identifier is a url, and `no_endpoint_url_test` bans every url token from
/// this package's committed Dart (ADR-0002 D3: an endpoint is a machine fact,
/// never committed source). That guard is blunt on purpose and this file is
/// not the place to blunt it back — and nothing needs the DOCTYPE: launchd
/// reads the plist through CFPropertyList, which parses the document without
/// fetching a DTD. That is not reasoning from the spec: a DOCTYPE-less
/// rendering of this exact shape was bootstrapped into, and booted out of, a
/// real `gui/<uid>` domain under a throwaway label during space-5lh review
/// (`launchctl bootstrap` exit 0, `launchctl print` showing the job), and
/// `plutil -lint` accepts it (the test proves that half on every run).
String renderLaunchAgentPlist({
  required String label,
  required List<String> programArguments,
  required String workingDirectory,
  required String standardOutPath,
  required String standardErrorPath,
  Map<String, String> environmentVariables = const <String, String>{},
}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<plist version="1.0">')
    ..writeln('<dict>')
    ..writeln('\t<key>Label</key>')
    ..writeln('\t<string>${_escaped(label)}</string>')
    ..writeln('\t<key>ProgramArguments</key>')
    ..writeln('\t<array>');
  for (final argument in programArguments) {
    buffer.writeln('\t\t<string>${_escaped(argument)}</string>');
  }
  buffer.writeln('\t</array>');
  if (environmentVariables.isNotEmpty) {
    // Sorted so the rendered recipe is byte-stable across runs: a plist that
    // re-orders itself reads as a change to anything diffing it.
    final keys = environmentVariables.keys.toList()..sort();
    buffer
      ..writeln('\t<key>EnvironmentVariables</key>')
      ..writeln('\t<dict>');
    for (final key in keys) {
      buffer
        ..writeln('\t\t<key>${_escaped(key)}</key>')
        ..writeln(
          '\t\t<string>${_escaped(environmentVariables[key]!)}</string>',
        );
    }
    buffer.writeln('\t</dict>');
  }
  buffer
    ..writeln('\t<key>WorkingDirectory</key>')
    ..writeln('\t<string>${_escaped(workingDirectory)}</string>')
    ..writeln('\t<key>KeepAlive</key>')
    ..writeln('\t<dict>')
    ..writeln('\t\t<key>SuccessfulExit</key>')
    ..writeln('\t\t<false/>')
    ..writeln('\t</dict>')
    ..writeln('\t<key>RunAtLoad</key>')
    ..writeln('\t<true/>')
    ..writeln('\t<key>StandardOutPath</key>')
    ..writeln('\t<string>${_escaped(standardOutPath)}</string>')
    ..writeln('\t<key>StandardErrorPath</key>')
    ..writeln('\t<string>${_escaped(standardErrorPath)}</string>')
    ..writeln('</dict>')
    ..writeln('</plist>');
  return buffer.toString();
}

/// What `launchctl` said, collapsed to one line, always naming the exit code.
String _refusalMessage(LaunchctlResult result) {
  final said = [
    result.stderr,
    result.stdout,
  ].where((line) => line.isNotEmpty).join(' ').replaceAll(RegExp(r'\s+'), ' ');
  return said.isEmpty
      ? 'exit ${result.exitCode}'
      : '$said (exit ${result.exitCode})';
}

String _escaped(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// What arming the LaunchAgent did.
sealed class DaemonArmOutcome {
  const DaemonArmOutcome({required this.label, required this.plistPath});

  /// The launchd label.
  final String label;

  /// Where the plist lives (or would have).
  final String plistPath;
}

/// The agent was rendered, written, and bootstrapped.
final class DaemonArmed extends DaemonArmOutcome {
  /// Creates the armed outcome.
  const DaemonArmed({
    required super.label,
    required super.plistPath,
    required this.standardOutPath,
    required this.standardErrorPath,
  });

  /// Where launchd writes the resident's stdout.
  final String standardOutPath;

  /// Where launchd writes the resident's stderr.
  final String standardErrorPath;
}

/// The label is ALREADY loaded — the refusal that keeps RS-2 (one resident per
/// station state store) true through the supervisor.
final class DaemonAlreadyLoaded extends DaemonArmOutcome {
  /// Creates the already-loaded refusal.
  const DaemonAlreadyLoaded({required super.label, required super.plistPath});
}

/// `launchctl bootstrap` refused; the half-written plist was removed.
final class DaemonArmRefused extends DaemonArmOutcome {
  /// Creates the bootstrap refusal.
  const DaemonArmRefused({
    required super.label,
    required super.plistPath,
    required this.message,
  });

  /// What `launchctl` said.
  final String message;
}

/// What stopping the LaunchAgent did.
sealed class DaemonStopOutcome {
  const DaemonStopOutcome({required this.label, required this.plistPath});

  /// The launchd label.
  final String label;

  /// Where the plist lives (or lived).
  final String plistPath;
}

/// The supervision was retired: the label booted out if launchd held it, the
/// plist removed if one was on disk.
///
/// Both halves are reported SEPARATELY because they can disagree — a plist
/// hand-deleted under a loaded job, or a recipe left behind by a job that was
/// booted out by hand — and a verb that claims it removed a file that was
/// already gone hides exactly that tampering.
final class DaemonStopped extends DaemonStopOutcome {
  /// Creates the stopped outcome.
  const DaemonStopped({
    required super.label,
    required super.plistPath,
    required this.wasLoaded,
    required this.removedPlist,
  });

  /// Whether launchd was actually holding the label, i.e. whether a `bootout`
  /// ran at all.
  final bool wasLoaded;

  /// Whether a plist was actually on disk, i.e. whether a file was deleted.
  final bool removedPlist;
}

/// Nothing to stop: no loaded label and no plist. A clean no-op.
final class DaemonNotSupervised extends DaemonStopOutcome {
  /// Creates the no-op outcome.
  const DaemonNotSupervised({required super.label, required super.plistPath});
}

/// `launchctl bootout` refused a LOADED label; the plist is left in place
/// rather than orphaning a running job from its recipe.
final class DaemonStopRefused extends DaemonStopOutcome {
  /// Creates the bootout refusal.
  const DaemonStopRefused({
    required super.label,
    required super.plistPath,
    required this.message,
  });

  /// What `launchctl` said.
  final String message;
}

/// ONE station's LaunchAgent: its label, its plist, and the two transitions.
///
/// The supervisor writes NOTHING outside [launchAgentsDirectory] and the grid
/// home's own `.grid/logs/` — which is why the operator's approval of a
/// persistence change is the run itself.
class LaunchAgentSupervisor {
  /// Creates the supervisor for [stationName].
  const LaunchAgentSupervisor({
    required this.stationName,
    required this.launchAgentsDirectory,
    this.launchctl = const ProcessLaunchctl(),
  });

  /// The STATION word (`SpaceDelegate.stationName`) the label derives from.
  final String stationName;

  /// `~/Library/LaunchAgents`, as a VALUE (this library reads no environment).
  final String launchAgentsDirectory;

  /// The `launchctl` client.
  final Launchctl launchctl;

  /// This station's launchd label.
  String get label => launchAgentLabel(stationName);

  /// Where this station's plist is installed.
  String get plistPath => p.join(launchAgentsDirectory, '$label.plist');

  /// Whether launchd currently holds [label].
  Future<bool> get isLoaded async => launchctl.isLoaded(label);

  /// Renders, installs, and loads the agent for [programArguments].
  ///
  /// A LOADED label short-circuits BEFORE anything is written or started: a
  /// second supervised boot is a refusal, never a second resident.
  Future<DaemonArmOutcome> arm({
    required String gridHome,
    required List<String> programArguments,
    Map<String, String> environmentVariables = const <String, String>{},
  }) async {
    if (await launchctl.isLoaded(label)) {
      return DaemonAlreadyLoaded(label: label, plistPath: plistPath);
    }
    final logs = p.join(gridHome, '.grid', 'logs');
    await Directory(logs).create(recursive: true);
    final standardOutPath = p.join(logs, '$stationName.out.log');
    final standardErrorPath = p.join(logs, '$stationName.err.log');
    final plist = File(plistPath);
    await plist.parent.create(recursive: true);
    await plist.writeAsString(
      renderLaunchAgentPlist(
        label: label,
        programArguments: programArguments,
        workingDirectory: gridHome,
        standardOutPath: standardOutPath,
        standardErrorPath: standardErrorPath,
        environmentVariables: environmentVariables,
      ),
    );
    final result = await launchctl.bootstrap(plistPath: plistPath);
    if (result.exitCode != 0) {
      // Leave nothing half-installed: an unloadable recipe on disk reads as a
      // supervised station to the next `status`.
      await plist.delete();
      return DaemonArmRefused(
        label: label,
        plistPath: plistPath,
        message: _refusalMessage(result),
      );
    }
    return DaemonArmed(
      label: label,
      plistPath: plistPath,
      standardOutPath: standardOutPath,
      standardErrorPath: standardErrorPath,
    );
  }

  /// Boots the agent out and removes its plist.
  ///
  /// `bootout` runs ONLY against a label launchd actually holds: issuing one
  /// against an unheld label is a guaranteed non-zero exit whose failure would
  /// have to be swallowed to stay useful, and a swallowed failure is
  /// indistinguishable from a real one. A plist with no loaded job is still
  /// removed — the recipe is the thing `up --daemon` installed — and the
  /// outcome reports the two halves separately, so `down` never claims a
  /// deletion that did not happen.
  Future<DaemonStopOutcome> stop() async {
    final plist = File(plistPath);
    final loaded = await launchctl.isLoaded(label);
    final installed = await plist.exists();
    if (!loaded && !installed) {
      return DaemonNotSupervised(label: label, plistPath: plistPath);
    }
    if (loaded) {
      final result = await launchctl.bootout(label: label);
      if (result.exitCode != 0) {
        return DaemonStopRefused(
          label: label,
          plistPath: plistPath,
          message: _refusalMessage(result),
        );
      }
    }
    if (installed) await plist.delete();
    return DaemonStopped(
      label: label,
      plistPath: plistPath,
      wasLoaded: loaded,
      removedPlist: installed,
    );
  }
}
