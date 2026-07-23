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
import 'package:grid_cli/grid_cli.dart'
    show AttachResult, Down, StationAttach, Stale, Unauthorized, Up;
import 'package:grid_runtime/grid_runtime.dart' show BeadOwnershipPredicate;

import 'attach_support.dart';

/// `space status`: renders the resident station's status, live when it's up.
class StatusCommand extends Command<int> {
  /// Creates the status command.
  StatusCommand() {
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
        stderr.writeln(message);
        return code;
      case StateWorkspaceFound(:final home, :final workspace):
        final AttachResult result = await StationAttach().status(
          stateWorkspaceDir: home,
        );
        switch (result) {
          case Up(:final payload):
            _renderUp(payload);
            return 0;
          case Down():
            await _renderDownFallback(results, workspace);
            return 0;
          case Stale(:final pid, :final record):
            stderr.writeln(
              'status: station.lock at $home/.grid/station.lock '
              'names pid $pid but it is unreachable (dead, or '
              'alive-but-not-answering — record: $record). (station: down) '
              '— a fresh `up` steals a dead lock automatically; if $pid is '
              'alive, investigate it directly.',
            );
            return 1;
          case Unauthorized(:final record):
            stderr.writeln(
              'status: the station at ${record.controlUrl} rejected this '
              'client\'s bearer token (401) — the lock may be stale or '
              'foreign. Investigate directly; refusing to guess.',
            );
            return 1;
        }
    }
  }

  void _renderUp(Map<String, Object?> payload) {
    final station = payload['station'] as Map<String, Object?>? ?? const {};
    final process = payload['process'] as Map<String, Object?>? ?? const {};
    final work = payload['work'] as Map<String, Object?>? ?? const {};
    stdout
      ..writeln('station: UP')
      ..writeln('  substation: ${station['substation']}')
      ..writeln('  state store: ${station['stateStore']}')
      ..writeln('  work root: ${station['workRoot']}')
      ..writeln(
        '  mode: '
        '${(station['dryRun'] as bool? ?? true) ? 'DRY-RUN' : 'LIVE'}',
      )
      ..writeln(
        '  pid: ${process['pid']}  ·  uptime: '
        '${process['uptimeSeconds']}s  ·  version: ${process['version']}',
      )
      ..writeln(
        '  ready: ${work['ready']}  ·  mounted: ${work['mounted']}  ·  '
        'live sessions: ${work['liveSessions']}  ·  last sync: '
        '${work['lastSyncAt']}',
      );
  }

  Future<void> _renderDownFallback(
    ArgResults results,
    BeadsWorkspace stateWorkspace,
  ) async {
    stdout
      ..writeln('station: DOWN  (station: down)')
      ..writeln('  state store: ${stateWorkspace.root}');

    final workspaceWs = BeadsWorkspace.discover(
      start: results.option('workspace'),
    );
    if (workspaceWs == null) {
      stdout.writeln(
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
      stdout.writeln(
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
    stdout
      ..writeln(
        '  substation: ${substations.join(',')}  ·  work root: '
        '${workspaceWs.root}',
      )
      ..writeln('  ready (owned): $ready');
  }
}
