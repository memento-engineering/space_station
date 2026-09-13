/// `space status` — RS-5b (tg-3s8.6, `the_grid/docs/SCRATCH-resident-station.md`
/// D-C3): a thin render over `grid_cli`'s [StationAttach.status] (RS-5a) when
/// a station is up, falling back to a DIRECT, READ-ONLY store view — clearly
/// labeled `(station: down)` — when it isn't. The fallback reuses the
/// existing one-shot [SnapshotReader] path ([CliSnapshotReader]: `bd export`
/// + `bd ready`, TWO spawns total) — never `bd show` per issue, never a
/// requery side effect, never the reactive polling controller.
///
/// Track G-space (tg-33n): the station it reports on is the one `up` boots from
/// its `SpaceDelegate`; `status` re-seats over that station by attaching to the
/// SAME state-store lock (`--state-workspace`).
///
/// space-5lh adds ONE line, on top of the same lock read: `supervised: launchd
/// <label>` whenever launchd is holding this station's LaunchAgent. It is a
/// supervisor fact, not a station fact, so it rides every rendering — UP,
/// DOWN, and every stale/unreachable lock verdict — and answers the question
/// the lock cannot: whether anything will bring this station back.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart'
    show
        BdCliService,
        BeadsWorkspace,
        CliSnapshotReader,
        GraphSnapshot,
        ProcessBdRunner;
// ignore: implementation_imports
import 'package:grid_cli/src/station_attach.dart'
    show
        AttachResult,
        DeadPid,
        Down,
        SlowUp,
        Starting,
        StationAttach,
        Unauthorized,
        Unreachable,
        Up;
import 'package:grid_runtime/grid_runtime.dart' show BeadOwnershipPredicate;

import 'attach_support.dart';
import 'launch_agent.dart';
import 'space_delegate.dart';
import 'trajectory_surface.dart';

/// `space status`: renders the resident station's status, live when it's up.
class StatusCommand extends Command<int> {
  /// Creates the status command.
  ///
  /// [delegateFactory] supplies the STATION word the launchd label derives
  /// from; [environment], [launchctl] and [launchAgentsDirectory] are the
  /// supervisor seams the `supervised:` line reads through.
  StatusCommand({
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
      ..addOption(
        'workspace',
        abbr: 'w',
        help:
            'The beads workspace to read the OWNED ready count from — only '
            'consulted for the store-fallback view (station: down). Defaults '
            'to discovery from the cwd.',
      )
      ..addMultiOption(
        'substation',
        abbr: 'r',
        help:
            'An OWNED substation / ownership token (repeatable) — only '
            'consulted for the store-fallback view (station: down).',
      )
      ..addMultiOption(
        'owner',
        help: 'Alias for --substation; merged into one shared allow-set.',
      );
  }

  final SpaceDelegateFactory _delegateFactory;

  /// The INJECTED process environment; `HOME` locates `~/Library/LaunchAgents`.
  final Map<String, String> _environment;

  /// The `launchctl` client, INJECTED so a test never probes the operator's
  /// real launchd domain.
  final Launchctl _launchctl;

  /// An explicit LaunchAgents directory; absent, derived from [_environment].
  final String? _launchAgentsDirectory;

  /// The verb's sinks, INJECTED; they default to the process streams.
  final void Function(String message) _out;
  final void Function(String message) _err;

  @override
  final String name = 'status';

  @override
  final String description =
      'Show the resident station\'s status (RS-5b): attaches to the '
      'StationControl surface (RS-4) at --state-workspace and renders it '
      'live when up, or falls back to a direct, read-only store view — '
      "clearly labeled '(station: down)' — when it isn't.";

  @override
  Future<int> run() async {
    final results = argResults!;
    final resolved = resolveStateWorkspace(
      verb: 'status',
      stateWorkspacePath: results.option('state-workspace'),
    );
    switch (resolved) {
      case StateWorkspaceRefusal(:final message, :final code):
        _err(message);
        return code;
      case StateWorkspaceFound(:final home, :final workspace):
        final code = await _render(results, home, workspace);
        final supervised = await _supervisedLine();
        if (supervised != null) _out(supervised);
        return code;
    }
  }

  /// The lock-derived rendering — unchanged by space-5lh.
  Future<int> _render(
    ArgResults results,
    String home,
    BeadsWorkspace workspace,
  ) async {
    final AttachResult result = await StationAttach().status(
      stateWorkspaceDir: home,
    );
    switch (result) {
      case Up(:final payload):
        _renderUp(payload);
        return 0;
      case SlowUp(:final payload, :final elapsed):
        _renderUp(payload);
        _out(
          '  door: SLOW — /status answered after ${elapsed.inSeconds} s '
          '(alive but saturated; a status that reads DOWN under load is '
          'this door, not the resident)',
        );
        return 0;
      case Down():
        await _renderDownFallback(results, workspace);
        return 0;
      case Starting(:final pid):
        _out('station: STARTING');
        _out('  state store: $home');
        _out('  pid: $pid');
        return 0;
      case DeadPid(:final pid, :final record):
        // A STALE LOCK, and it is worth its own case rather than folding
        // into Down: the lock names a pid the probe found dead, so the
        // store is not in use and a fresh `up` will steal it. Down would
        // render the same word and hide the reason a boot was refused.
        _err(
          'status: station.lock at $home/.grid/station.lock names pid '
          '$pid, but no such process is alive — the lock is STALE '
          '(record: $record). (station: down) — a fresh `up` steals a '
          'dead lock automatically; nothing needs clearing by hand.',
        );
        return 1;
      case Unreachable(:final pid, :final record):
        _err(
          'status: station.lock at $home/.grid/station.lock '
          'names pid $pid but it is unreachable (dead, or '
          'alive-but-not-answering — record: $record). (station: down) '
          '— a fresh `up` steals a dead lock automatically; if $pid is '
          'alive, investigate it directly.',
        );
        return 1;
      case Unauthorized(:final record):
        _err(
          'status: the station at ${record.controlUrl} rejected this '
          'client\'s bearer token (401) — the lock may be stale or '
          'foreign. Investigate directly; refusing to guess.',
        );
        return 1;
    }
  }

  /// `supervised: launchd <label>` when launchd holds this station's agent,
  /// else null.
  ///
  /// A supervisor fact the lock cannot carry: a DOWN station with a loaded
  /// agent will come back, and an UP station with none dies with its shell.
  /// Silent — never a refusal — when launchd is not the supervisor here
  /// (non-macOS, no HOME) or when the probe itself fails: `status` must stay
  /// readable on a box that never installed an agent.
  Future<String?> _supervisedLine() async {
    if (!Platform.isMacOS) return null;
    final directory =
        _launchAgentsDirectory ?? launchAgentsDirectoryFor(_environment);
    if (directory == null) return null;
    final supervisor = LaunchAgentSupervisor(
      stationName: codedStationNameOf(_delegateFactory),
      launchAgentsDirectory: directory,
      launchctl: _launchctl,
    );
    try {
      if (!await supervisor.isLoaded) return null;
    } on Object {
      return null;
    }
    return '  supervised: launchd ${supervisor.label}';
  }

  void _renderUp(Map<String, Object?> payload) {
    final station = payload['station'] as Map<String, Object?>? ?? const {};
    final process = payload['process'] as Map<String, Object?>? ?? const {};
    final work = payload['work'] as Map<String, Object?>? ?? const {};
    _out('station: UP');
    _out('  substation: ${station['substation']}');
    _out('  state store: ${station['stateStore']}');
    _out('  work root: ${station['workRoot']}');
    final roster = station['roster'] as List<Object?>? ?? const [];
    if (roster.isNotEmpty) {
      _out('  roster:');
      for (final value in roster) {
        final entry = value as Map<String, Object?>;
        _out(
          '    - name: ${entry['name']}  ·  root: ${entry['root']}  ·  '
          'prefix: ${entry['prefix']}',
        );
      }
    }
    _out(
      '  mode: '
      '${(station['dryRun'] as bool? ?? true) ? 'DRY-RUN' : 'LIVE'}',
    );
    _out(
      '  pid: ${process['pid']}  ·  uptime: '
      '${process['uptimeSeconds']}s  ·  version: ${process['version']}',
    );
    _out(
      '  ready: ${work['ready']}  ·  mounted: ${work['mounted']}  ·  '
      'live sessions: ${work['liveSessions']}  ·  last sync: '
      '${work['lastSyncAt']}',
    );
    // The Stage-1 trajectory posture (stage1-wiring §3). `up`'s banner fires
    // ONCE, at boot; every posture that can arise afterwards — fenced out by a
    // successor, halted on belt corruption, degraded on a dead socket — is
    // latched later and flared exactly once, on the harness's stated
    // assumption that THIS surface carries the repetition.
    //
    // ALWAYS exactly one line, and always on stdout with the rest of the
    // block: a degradation must not be something an operator can lose by
    // redirecting a stream. Loudness is the `!!` prefix and the BROKEN
    // indentation — the row stops lining up with the tidy block above it, so
    // an operator scanning for "is the shadow window counting?" cannot read
    // past it.
    final trajectory = trajectoryStatusLine(payload);
    if (trajectory == null) return;
    _out(trajectory.loud ? trajectory.line : '  ${trajectory.line}');
  }

  Future<void> _renderDownFallback(
    ArgResults results,
    BeadsWorkspace stateWorkspace,
  ) async {
    _out('station: DOWN  (station: down)');
    _out('  state store: ${stateWorkspace.root}');

    final workspaceWs = BeadsWorkspace.discover(
      start: results.option('workspace'),
    );
    if (workspaceWs == null) {
      _out(
        '  (pass --workspace to see the owned ready count — none '
        'discoverable from '
        '${results.option('workspace') ?? Directory.current.path})',
      );
      return;
    }
    final substations = <String>{
      ...results.multiOption('substation'),
      ...results.multiOption('owner'),
    }..removeWhere((s) => s.trim().isEmpty);
    if (substations.isEmpty) {
      _out(
        '  work root: ${workspaceWs.root}  (pass --substation to see the '
        'owned ready count)',
      );
      return;
    }

    // The one-shot, read-only snapshot path — TWO bd spawns total (`bd
    // export --all` + `bd ready`), never `bd show` per issue, never a
    // requery/reactive-controller side effect (the design constraint this
    // fallback exists to honor).
    final GraphSnapshot snapshot = await CliSnapshotReader(
      BdCliService(ProcessBdRunner(workspaceRoot: workspaceWs.root)),
    ).read();
    final ownership = BeadOwnershipPredicate(substations);
    var ready = 0;
    for (final id in snapshot.readyIds) {
      final bead = snapshot.beadsById[id];
      if (bead == null || !ownership.owns(bead)) continue;
      if (!bead.issueType.isCore) continue;
      ready++;
    }
    _out(
      '  substation: ${substations.join(',')}  ·  work root: '
      '${workspaceWs.root}',
    );
    _out('  ready (owned): $ready');
  }
}
