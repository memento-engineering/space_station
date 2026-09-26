/// The station's OWN relay collaborators (space-8pq): the four read tools and
/// the inference seam grid_assets' vended `RelayAssets` takes by construction,
/// implemented over the services the shared runner already owns.
///
/// `RelayAssets` is only the ARMING seed. It mounts a `RelayAgentObserver`
/// under an exact `RelayAgentEnvironment` presence, but it cannot be composed
/// without a `RelayReadTools` and a `RelayInferenceRunner`, and grid_assets
/// ships no implementation of either (they are DI by design). This library is
/// that implementation for any station built on `SpaceDelegate`, so a
/// downstream station's presence declaration ALONE arms a relay:
///
///  * `worktree.read` — the session worktree the station's own git layout
///    places at `<substation root>/.grid/worktrees/<substation>/<workBeadId>`
///    ([WorktreeLayout]), its most recently modified paths and its last commit;
///  * `flares.read` — a bounded in-process tail of the flares the station's
///    diagnostics reporter ACCEPTED ([StationFlareTail]), filtered to the
///    session;
///  * `telemetry.read` — the FT-2 usage envelopes the session's harness runs
///    wrote under the worktree's `.grid/telemetry`, read through grid_assets'
///    own [readUsageFields];
///  * `gates.read` — the open `gate` bead the engine minted against the
///    session in the station's STATE store (`<grid home>/.grid`, the
///    `metadata.blocks` edge `StationBeadWriter.createGate` stamps);
///  * the inference seam — one harness-rendered process ([spawnFor]) in a
///    throwaway directory, whose stdout is the answer ([ProcessRelayInference]).
///
/// **Failure escalates, never absorbs** (`memento-engineering#protect-the-governor`,
/// rule 5). Every reader here THROWS when it cannot answer — no worktree under
/// any roster root, no flare source attached, an unreadable git log, a failed
/// bd read, a non-zero or timed-out inference — so the engine turns the
/// observation into `relay.error` rather than letting a blind absorb stand. An
/// EMPTY answer is returned only when the source was reached and holds nothing
/// (a worktree with no telemetry directory yet, a session parked at no gate).
///
/// Every collaborator is plain Dart over injected seams ([GitRunner],
/// [BdRunner], the clock), so the suite drives each one offline with Fakes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart'
    show BdCliService, BdRunner, BeadStatus, IssueType, ProcessBdRunner;
import 'package:grid_assets/grid_assets.dart'
    show
        AgentBrief,
        AgentEnvironment,
        RelayFlareRecord,
        RelayGateRecord,
        RelayInferenceRunner,
        RelayReadTools,
        RelayTelemetryRecord,
        RelayWorktreeSnapshot,
        kTelemetryDir,
        readUsageFields,
        spawnFor;
import 'package:grid_cli/grid_cli.dart' show StationDiagnosticsReporter;
import 'package:grid_engine/grid_engine.dart'
    show ExplorationTransport, RelayObservation, Workspace;
import 'package:genesis_tree/genesis_tree.dart' show Seed;
import 'package:grid_runtime/grid_runtime.dart'
    show GitRunner, SystemGitRunner, WorktreeLayout;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import 'substation_seed.dart' show SubstationSeed;

/// One substation's worktree home, as the relay searches it: the substation
/// NAME (the middle segment of [WorktreeLayout.worktreePath]) and its ABSOLUTE
/// root checkout.
typedef RelayWorktreeRoot = ({String substation, String root});

/// The worktree homes of every [roster] entry whose name and root are authored
/// VALUES — [SubstationSeed] and the SDK's own `Substation` — with each root
/// resolved against [gridRoot] by the SDK's rule (absolute passes through,
/// relative joins the grid root, both normalized).
///
/// A composed seed of any other class carries no readable root at build time;
/// a session under it cannot be located, and `worktree.read` then THROWS, so
/// its observation escalates rather than absorbing blind.
List<RelayWorktreeRoot> relayWorktreeRootsOf(
  List<Seed> roster, {
  required String gridRoot,
}) {
  String absolute(String root) => p.isAbsolute(root)
      ? p.normalize(root)
      : p.normalize(p.join(gridRoot, root));
  return [
    for (final seed in roster)
      if (seed case SubstationSeed(:final name, :final root))
        (substation: name, root: absolute(root))
      else if (seed case sdk.Substation(:final name, :final root))
        (substation: name, root: absolute(root)),
  ];
}

/// Directory names a worktree walk never descends into: git's own metadata and
/// tool caches whose mtimes say nothing about whether the SESSION moved.
const Set<String> kRelayWorktreeWalkSkips = <String>{
  '.git',
  '.dart_tool',
  'build',
  'node_modules',
};

/// A bounded, in-process tail of the flares a station's diagnostics reporter
/// accepted — the `flares.read` source.
///
/// The resident has no durable flare store (engine flares go to stderr and the
/// authenticated `/stream`), so the relay reads what THIS process saw. It is
/// attached to the reporter through [StationDiagnosticsReporter.addTransport],
/// the reporter's own process-lifetime sink seam, AFTER the reporter's rate
/// limit, so it holds exactly the flares every other sink received.
final class StationFlareTail implements ExplorationTransport {
  /// Creates an unattached tail holding at most [capacity] flares, stamped by
  /// [clock] (UTC).
  StationFlareTail({this.capacity = 2000, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The most flares retained; the oldest is dropped first.
  final int capacity;

  final DateTime Function() _clock;
  final List<RelayFlareRecord> _records = <RelayFlareRecord>[];

  static final Expando<StationFlareTail> _attached = Expando<StationFlareTail>(
    'StationFlareTail',
  );

  /// The ONE tail attached to [transport], attaching it on first use.
  ///
  /// Idempotent per reporter: a hot-restarted delegate over the SAME runtime
  /// wiring gets the tail its predecessor attached, never a second sink.
  /// Returns null when [transport] is not the resident's
  /// [StationDiagnosticsReporter] (a hand-built wiring, an offline mount):
  /// there is then no flare source, and `flares.read` refuses to answer.
  static StationFlareTail? attachedTo(ExplorationTransport? transport) {
    if (transport is! StationDiagnosticsReporter) return null;
    final existing = _attached[transport];
    if (existing != null) return existing;
    final tail = StationFlareTail();
    transport.addTransport(tail);
    _attached[transport] = tail;
    return tail;
  }

  @override
  void flare(String name, Map<String, String> data) {
    _records.add(
      RelayFlareRecord(occurredAt: _clock().toUtc(), name: name, data: data),
    );
    final overflow = _records.length - capacity;
    if (overflow > 0) _records.removeRange(0, overflow);
  }

  /// The newest [limit] retained flares about [observation]'s session, in the
  /// order they were emitted.
  ///
  /// A flare is about the session when any payload value IS its session id or
  /// work bead id, or is a node path under that work bead (`<bead>/<step>`).
  Future<List<RelayFlareRecord>> tailFor(
    RelayObservation observation, {
    int limit = 50,
  }) async {
    final session = observation.sessionId;
    final bead = observation.workBeadId;
    final matching = [
      for (final record in _records)
        if (record.data.values.any(
          (value) =>
              value == session || value == bead || value.startsWith('$bead/'),
        ))
          record,
    ];
    return matching.length <= limit
        ? matching
        : matching.sublist(matching.length - limit);
  }
}

/// The station's `RelayReadTools`, over its own roster roots, state store and
/// flare tail.
///
/// [tools] is created once per instance, so a delegate that holds one
/// instance hands `RelayAssets` the same identity on every build and the
/// mounted observer is not churned.
final class StationRelayReads {
  /// Creates the readers.
  ///
  /// [worktreeRoots] are the roster's substations (absolute roots).
  /// [stateStoreRoot] is the station state store's workspace
  /// (`<grid home>/.grid`). [flares] is the attached tail, or null when the
  /// station has no flare source. [git] and [stateStoreBd] default to the
  /// real process runners; [mtimeLimit] bounds the worktree evidence to the
  /// newest paths so a large checkout never floods the brief.
  StationRelayReads({
    required List<RelayWorktreeRoot> worktreeRoots,
    required this.stateStoreRoot,
    this.flares,
    GitRunner? git,
    BdRunner? stateStoreBd,
    this.mtimeLimit = 25,
  }) : worktreeRoots = List<RelayWorktreeRoot>.unmodifiable(worktreeRoots),
       _git = git ?? SystemGitRunner(),
       _stateStoreBd = stateStoreBd;

  /// The roster's substations, searched in order for the session worktree.
  final List<RelayWorktreeRoot> worktreeRoots;

  /// The station state store's bd workspace root.
  final String stateStoreRoot;

  /// The station's flare tail; null ⇒ `flares.read` refuses.
  final StationFlareTail? flares;

  /// The most worktree paths reported, newest first.
  final int mtimeLimit;

  final GitRunner _git;
  final BdRunner? _stateStoreBd;

  late final BdCliService _stateStore = BdCliService(
    _stateStoreBd ?? ProcessBdRunner(workspaceRoot: stateStoreRoot),
  );

  /// The four readers bound to their vended tool names.
  late final RelayReadTools tools = RelayReadTools(
    readWorktree: readWorktree,
    readFlareTail: readFlareTail,
    readTelemetry: readTelemetry,
    readGate: readGate,
  );

  /// The session's worktree directory: the first roster root holding
  /// `<root>/.grid/worktrees/<substation>/<workBeadId>`. Throws when none does
  /// — a live session whose worktree cannot be found is not something a relay
  /// may absorb blind.
  Future<String> worktreeOf(RelayObservation observation) async {
    for (final home in worktreeRoots) {
      final path = WorktreeLayout.worktreePath(
        home.root,
        home.substation,
        observation.workBeadId,
      );
      if (await Directory(path).exists()) return path;
    }
    throw StateError(
      'worktree.read: no worktree for work bead ${observation.workBeadId} '
      '(session ${observation.sessionId}) under any of the station\'s '
      '${worktreeRoots.length} substation roots',
    );
  }

  /// `worktree.read`: the newest [mtimeLimit] paths (worktree-relative, git
  /// metadata and tool caches skipped) and the last commit.
  Future<RelayWorktreeSnapshot> readWorktree(
    RelayObservation observation,
  ) async {
    final worktree = await worktreeOf(observation);
    final mtimes = <String, DateTime>{};
    await _walk(Directory(worktree), worktree, mtimes);
    final newest = mtimes.keys.toList()
      ..sort((a, b) => mtimes[b]!.compareTo(mtimes[a]!));
    final log = await _git.run(
      workingDirectory: worktree,
      args: const ['log', '-1', '--format=%H %s%x00%cI'],
    );
    final record = log.output.trim();
    final separator = record.indexOf('\x00');
    if (!log.ok || separator < 0) {
      throw StateError(
        'worktree.read: git log failed in $worktree '
        '(exit ${log.exitCode}): $record',
      );
    }
    return RelayWorktreeSnapshot(
      mtimes: {for (final path in newest.take(mtimeLimit)) path: mtimes[path]!},
      lastCommit: record.substring(0, separator),
      lastCommitAt: DateTime.parse(record.substring(separator + 1)).toUtc(),
    );
  }

  Future<void> _walk(
    Directory directory,
    String worktree,
    Map<String, DateTime> mtimes,
  ) async {
    await for (final entity in directory.list(followLinks: false)) {
      if (kRelayWorktreeWalkSkips.contains(p.basename(entity.path))) continue;
      if (entity is Directory) {
        await _walk(entity, worktree, mtimes);
      } else if (entity is File) {
        final stat = await entity.stat();
        mtimes[p.relative(entity.path, from: worktree)] = stat.modified.toUtc();
      }
    }
  }

  /// `flares.read`: the attached tail filtered to the session. Throws when the
  /// station has no flare source — an empty list would claim "no flares", which
  /// nobody observed.
  Future<List<RelayFlareRecord>> readFlareTail(
    RelayObservation observation,
  ) async {
    final tail = flares;
    if (tail == null) {
      throw StateError(
        'flares.read: this station has no flare source attached '
        '(its work wiring carries no StationDiagnosticsReporter)',
      );
    }
    return tail.tailFor(observation);
  }

  /// `telemetry.read`: every FT-2 usage envelope under the worktree's
  /// `.grid/telemetry`, keyed by its node file stem, in name order. A worktree
  /// with no telemetry directory has captured nothing yet (empty); an envelope
  /// that does not parse is reported as such, never dropped.
  Future<List<RelayTelemetryRecord>> readTelemetry(
    RelayObservation observation,
  ) async {
    final worktree = await worktreeOf(observation);
    final directory = Directory(p.join(worktree, kTelemetryDir));
    if (!await directory.exists()) return const <RelayTelemetryRecord>[];
    const suffix = '.usage.json';
    final stems = <String>[
      await for (final entity in directory.list(followLinks: false))
        if (entity is File && entity.path.endsWith(suffix))
          p
              .basename(entity.path)
              .substring(0, p.basename(entity.path).length - suffix.length),
    ]..sort();
    return [
      for (final stem in stems)
        RelayTelemetryRecord(
          nodePath: stem,
          // Pure capture: a diagnostic read derives no cost it will not
          // record (the empty price table readUsageReport documents).
          usage: switch (readUsageFields(
            worktree,
            stem,
            modelPrices: const {},
          )) {
            final fields when fields.isNotEmpty => fields,
            _ => const {'error': 'unreadable usage envelope'},
          },
        ),
    ];
  }

  /// `gates.read`: the open `gate` bead blocking the session in the state
  /// store, or null when it is parked at none. Every state-store gate is a
  /// park awaiting an operator's ruling (the engine's human escalation), so it
  /// is reported as awaiting a human.
  Future<RelayGateRecord?> readGate(RelayObservation observation) async {
    final scope = await _stateStore.listScope(
      type: const IssueType('gate'),
      status: BeadStatus.open,
      metadataFields: {'blocks': observation.sessionId},
    );
    if (scope.beads.isEmpty) return null;
    final gate = scope.beads.first;
    final reason = gate.metadata['reason'];
    return RelayGateRecord(
      id: gate.id,
      reason: reason is String && reason.trim().isNotEmpty
          ? reason
          : gate.title,
      awaitingHuman: true,
    );
  }
}

/// The relay's inference seam over a real harness process.
///
/// Renders the SEAT-selected environment and the brief through grid_assets'
/// own [spawnFor] (the renderer every seat rides), runs it to completion in a
/// throwaway directory — a relay has no workspace and must touch none — and
/// returns trimmed stdout. A launch failure, a non-zero exit, a timeout (the
/// child is killed) or an empty answer THROWS, so the engine escalates.
final class ProcessRelayInference implements RelayInferenceRunner {
  /// Creates the runner; [timeout] is the wall-clock cap on one answer, set
  /// under the engine's own relay observation timeout.
  const ProcessRelayInference({this.timeout = const Duration(minutes: 4)});

  /// The wall-clock cap on one relay answer.
  final Duration timeout;

  @override
  Future<String> run({
    required AgentEnvironment environment,
    required AgentBrief brief,
  }) async {
    final scratch = await Directory.systemTemp.createTemp('grid-relay-');
    try {
      final config = spawnFor(
        environment: environment,
        brief: brief,
        workspace: Workspace(
          workspaceDir: scratch.path,
          branch: '',
          baseBranch: '',
        ),
      );
      final process = await Process.start(
        config.command,
        config.args,
        workingDirectory: config.workDir,
        environment: config.env.isEmpty ? null : config.env,
      );
      await process.stdin.close();
      final stdoutText = process.stdout.transform(utf8.decoder).join();
      final stderrText = process.stderr.transform(utf8.decoder).join();
      var timedOut = false;
      final code = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      if (timedOut) {
        // Never wait on the pipes of a killed child: a grandchild it left
        // behind could hold them open past the deadline. Their late results
        // (or a decode error on a cut-off byte) are dropped, never unhandled.
        stdoutText.ignore();
        stderrText.ignore();
        throw StateError('relay inference timed out after $timeout');
      }
      final answer = (await stdoutText).trim();
      final errors = (await stderrText).trim();
      if (code != 0) {
        throw StateError('relay inference exited $code: $errors');
      }
      if (answer.isEmpty) {
        throw StateError('relay inference exited 0 with no answer');
      }
      return answer;
    } finally {
      await scratch.delete(recursive: true);
    }
  }
}

/// The relay's inference seam under a DRY-RUN arm: it spawns nothing and
/// refuses every brief, because a dry run spawns no agent process. The relay
/// is still mounted (presence is the whole existence rule), so a due session
/// escalates as `relay.error` with this reason instead of `relay.absent`.
final class DryRunRelayInference implements RelayInferenceRunner {
  /// Creates the refusing seam.
  const DryRunRelayInference();

  @override
  Future<String> run({
    required AgentEnvironment environment,
    required AgentBrief brief,
  }) async => throw StateError(
    'dry run: the relay spawns no inference process; this observation '
    'escalates',
  );
}
