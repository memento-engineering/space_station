library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cli/grid_cli.dart' show LinkCommand;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

class _DownstreamDelegate extends SpaceDelegate {
  _DownstreamDelegate({
    required super.gridRoot,
    super.agentConfig,
    super.appended,
    super.harnesses,
    super.wiring,
    super.provisioner,
    super.trajectoryConfig,
    super.githubSelfTrust,
    super.live,
  });

  @override
  String get stateStorePrefix => 'tranquility';

  @override
  String get umbrella => '.';

  @override
  List<Seed> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    SubstationSeed(name: 'alpha', root: 'alpha'),
    SubstationSeed(name: 'beta', root: 'beta'),
  ];
}

Future<String> _runBd(String root, List<String> args) async {
  final result = await Process.run('bd', args, workingDirectory: root);
  if (result.exitCode != 0) {
    throw StateError('bd ${args.join(' ')} failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

Future<Map<String, Object?>?> _beadJson(String root, String id) async {
  final rows =
      jsonDecode(await _runBd(root, ['show', id, '--json'])) as List<Object?>;
  return rows.isEmpty ? null : rows.single as Map<String, Object?>;
}

final class _LinkStoreFixture {
  _LinkStoreFixture._(this.root);

  static Future<_LinkStoreFixture> create() async {
    final directory = await Directory.systemTemp.createTemp('space_link_');
    return _LinkStoreFixture._(directory.resolveSymbolicLinksSync());
  }

  final String root;
  final List<String> _stores = [];
  final Set<int> _capturedPids = {};
  bool _disposed = false;

  Set<int> get capturedPids => Set.unmodifiable(_capturedPids);

  Future<String> initStore(
    String relativePath,
    String prefix, {
    bool proxied = false,
  }) async {
    final store = p.join(root, relativePath);
    _stores.add(store);
    Directory(store).createSync(recursive: true);
    await _runBd(store, [
      'init',
      '--non-interactive',
      '--skip-agents',
      '--skip-hooks',
      if (proxied) ...[
        '--proxied-server',
        '--proxied-server-idle-timeout',
        '0',
      ],
      '-p',
      prefix,
    ]);
    return store;
  }

  Future<Set<int>> processCensus() async {
    final owned = await _workspaceProcessCensus(root, _stores);
    _capturedPids.addAll(owned);
    return owned;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await _stopAndAwaitWorkspaceProcesses(
      census: processCensus,
      signal: Process.killPid,
      delay: Future<void>.delayed,
    );
    await _deleteWorkspaceWithRetry(root: root);
    if (Directory(root).existsSync() || _systemTempContainsExactRoot(root)) {
      throw StateError('the link fixture root survived teardown: $root');
    }
    _disposed = true;
  }
}

Future<Set<int>> _workspaceProcessCensus(
  String root,
  Iterable<String> stores,
) async {
  final processTable = await Process.run('ps', ['-axo', 'pid=,command=']);
  if (processTable.exitCode != 0) {
    throw StateError('ps process census failed: ${processTable.stderr}');
  }

  final commands = <int, String>{};
  for (final line in (processTable.stdout as String).split('\n')) {
    final match = RegExp(r'^\s*(\d+)\s+(.*)$').firstMatch(line);
    if (match == null) continue;
    final processId = int.parse(match.group(1)!);
    if (processId > 0) commands[processId] = match.group(2)!;
  }

  final owned = <int>{};
  for (final store in stores) {
    final pidRoot = p.join(store, '.beads', 'dolt');
    for (final name in ['proxy.pid', 'proxy-child.pid']) {
      final recorded = _readPositivePid(p.join(pidRoot, name));
      if (recorded != null && commands.containsKey(recorded)) {
        owned.add(recorded);
      }
    }
  }

  for (final MapEntry(key: processId, value: command) in commands.entries) {
    if (processId == pid) continue;
    if (!command.contains('dolt sql-server') &&
        !command.contains('db-proxy-child')) {
      continue;
    }
    if (_commandPaths(command).any((path) => _pathIsWithin(root, path))) {
      owned.add(processId);
    }
  }

  try {
    final residents = await Process.run('lsof', [
      '-w',
      '-a',
      '-d',
      'cwd',
      '-Fp',
      '+D',
      root,
    ]);
    for (final line in (residents.stdout as String).split('\n')) {
      if (!line.startsWith('p')) continue;
      final resident = int.tryParse(line.substring(1));
      if (resident != null && resident > 0 && resident != pid) {
        owned.add(resident);
      }
    }
  } on ProcessException {
    // CI images may omit lsof; the PID and argv arms remain authoritative.
  }
  return owned;
}

int? _readPositivePid(String path) {
  final file = File(path);
  final String contents;
  try {
    contents = file.readAsStringSync().trim();
  } on PathNotFoundException {
    return null;
  }
  final jsonPid = RegExp(r'"pid"\s*:\s*(\d+)').firstMatch(contents);
  final parsed =
      int.tryParse(contents) ??
      (jsonPid == null ? null : int.tryParse(jsonPid.group(1)!));
  if (parsed == null || parsed <= 0) {
    throw StateError('the bd pid file did not name a positive PID: $path');
  }
  return parsed;
}

Iterable<String> _commandPaths(String command) sync* {
  final arguments = RegExp(
    r'''(?:^|\s)--(?:config|root)(?:=|\s+)(?:"([^"]+)"|'([^']+)'|(\S+))''',
  );
  for (final match in arguments.allMatches(command)) {
    yield match.group(1) ?? match.group(2) ?? match.group(3)!;
  }
}

bool _pathIsWithin(String root, String candidate) {
  if (!p.isAbsolute(candidate)) return false;
  final normalizedRoot = p.normalize(root);
  final normalizedCandidate = p.normalize(candidate);
  return p.equals(normalizedRoot, normalizedCandidate) ||
      p.isWithin(normalizedRoot, normalizedCandidate);
}

Future<void> _stopAndAwaitWorkspaceProcesses({
  required Future<Set<int>> Function() census,
  required bool Function(int, ProcessSignal) signal,
  required Future<void> Function(Duration) delay,
  int polls = 40,
  Duration interval = const Duration(milliseconds: 50),
}) async {
  var owned = await census();
  for (final processId in owned) {
    signal(processId, ProcessSignal.sigterm);
  }
  for (var poll = 0; poll < polls; poll++) {
    await delay(interval);
    owned = await census();
    if (owned.isEmpty) return;
    for (final processId in owned) {
      signal(processId, ProcessSignal.sigterm);
    }
  }

  for (final processId in owned) {
    signal(processId, ProcessSignal.sigkill);
  }
  for (var poll = 0; poll < polls; poll++) {
    await delay(interval);
    owned = await census();
    if (owned.isEmpty) return;
    for (final processId in owned) {
      signal(processId, ProcessSignal.sigkill);
    }
  }
  throw StateError(
    'fixture-owned processes survived shutdown: ${owned.toList()..sort()}',
  );
}

Future<void> _deleteWorkspaceWithRetry({
  required String root,
  Future<void> Function()? delete,
  bool Function()? exists,
  Future<void> Function(Duration)? delay,
  int attempts = 5,
  int absenceChecks = 5,
  Duration interval = const Duration(milliseconds: 50),
}) async {
  final deleteRoot = delete ?? () => Directory(root).delete(recursive: true);
  final rootExists = exists ?? Directory(root).existsSync;
  final wait = delay ?? Future<void>.delayed;

  for (var attempt = 1; attempt <= attempts; attempt++) {
    if (rootExists()) {
      try {
        await deleteRoot();
      } on FileSystemException catch (error) {
        if (!rootExists()) {
          // Another closer completed the deletion; prove it stays absent.
        } else if (_retryableDeletionError(error)) {
          if (attempt == attempts) rethrow;
          await wait(interval);
          continue;
        } else {
          rethrow;
        }
      }
    }

    var stayedAbsent = true;
    for (var check = 0; check < absenceChecks; check++) {
      await wait(interval);
      if (rootExists()) {
        stayedAbsent = false;
        break;
      }
    }
    if (stayedAbsent) return;
  }
  throw StateError('the link fixture root kept reappearing: $root');
}

bool _retryableDeletionError(FileSystemException error) {
  final errorCode = error.osError?.errorCode;
  return error is PathNotFoundException ||
      errorCode == 2 ||
      errorCode == 39 ||
      errorCode == 66;
}

bool _systemTempContainsExactRoot(String root) {
  final normalizedRoot = p.normalize(root);
  final resolvedSystemTemp = Directory.systemTemp.resolveSymbolicLinksSync();
  for (final entry in Directory.systemTemp.listSync(followLinks: false)) {
    final candidate = p.join(resolvedSystemTemp, p.basename(entry.path));
    if (p.equals(normalizedRoot, p.normalize(candidate))) return true;
  }
  return false;
}

Future<Set<int>> _liveProcessPids(Set<int> processIds) async {
  if (processIds.isEmpty) return const {};
  final result = await Process.run('ps', [
    '-o',
    'pid=',
    '-p',
    processIds.join(','),
  ]);
  return {
    for (final line in (result.stdout as String).split('\n'))
      if (int.tryParse(line.trim()) case final processId?) processId,
  };
}

void main() {
  test('composes ONE immutable endpoint roster carrying name AND prefix', () {
    final endpoints = buildSpaceLinkCommand(
      gridRoot: '/fixture/space',
      delegateFactory: _DownstreamDelegate.new,
    ).endpoints;
    // The NAME is the `<project>` token an `external:<project>:<capability>`
    // row carries (grid_cli 0.6.0-dev.3); the PREFIX is how an endpoint id
    // resolves to a store. Both come from the coded roster, in roster order.
    expect(
      endpoints.map(
        (endpoint) => (endpoint.name, endpoint.prefix, endpoint.store.root),
      ),
      [
        ('alpha', 'alpha', '/fixture/space/alpha'),
        ('beta', 'beta', '/fixture/space/beta'),
      ],
    );
  });

  test('the station composes `link` alone — the unlink verb is GONE', () {
    final runner = buildRunner(delegateFactory: _DownstreamDelegate.new);
    final link = runner.commands['link'];
    expect(link, isA<LinkCommand>());
    // The additive migrate flags ride the same parser (the_grid#447).
    expect(link!.argParser.usage, contains('--blocked-by'));
    expect(link.argParser.usage, contains('--grid-root'));
    expect(link.argParser.usage, contains('--dry-run'));
    // HARD CUT, no shim: grid_cli deleted `UnlinkCommand` with the state-store
    // link bead, so this station composes no unlink verb and mints no
    // replacement for it. A cross-store blocker is a bd dependency row; it is
    // removed with `bd dep remove` or lifts when the target ships.
    expect(runner.commands['unlink'], isNull);
    expect(runner.commands.keys, isNot(contains('unlink')));
  });

  test('a live proxied store is stopped before its root is deleted', () async {
    final fixture = await _LinkStoreFixture.create();
    addTearDown(fixture.dispose);
    await fixture.initStore('proxied', 'proxied', proxied: true);

    final livePids = await fixture.processCensus();
    expect(livePids, isNotEmpty);

    await fixture.dispose();

    expect(await _liveProcessPids(fixture.capturedPids), isEmpty);
    expect(Directory(fixture.root).existsSync(), isFalse);
    expect(_systemTempContainsExactRoot(fixture.root), isFalse);
  }, tags: ['bd-e2e']);

  test('workspace deletion retries ENOTEMPTY within its bound', () async {
    final failure = FileSystemException(
      'Deletion failed',
      '/tmp/space_link_fake',
      const OSError('Directory not empty', 66),
    );
    var present = true;
    var deletes = 0;
    final waits = <Duration>[];

    await _deleteWorkspaceWithRetry(
      root: '/tmp/space_link_fake',
      delete: () async {
        deletes++;
        if (deletes == 1) throw failure;
        present = false;
      },
      exists: () => present,
      delay: (duration) async => waits.add(duration),
    );

    expect(deletes, 2);
    expect(waits, hasLength(6));
    expect(waits, everyElement(const Duration(milliseconds: 50)));
    expect(present, isFalse);
  });

  test('workspace deletion retries ENOENT while the root remains', () async {
    final failure = FileSystemException(
      'Deletion failed',
      '/tmp/space_link_fake',
      const OSError('No such file or directory', 2),
    );
    var present = true;
    var deletes = 0;
    final waits = <Duration>[];

    await _deleteWorkspaceWithRetry(
      root: '/tmp/space_link_fake',
      delete: () async {
        deletes++;
        if (deletes == 1) throw failure;
        present = false;
      },
      exists: () => present,
      delay: (duration) async => waits.add(duration),
    );

    expect(deletes, 2);
    expect(waits, hasLength(6));
    expect(waits, everyElement(const Duration(milliseconds: 50)));
    expect(present, isFalse);
  });

  test('workspace deletion rethrows its final filesystem failure', () async {
    final failure = FileSystemException(
      'Deletion failed',
      '/tmp/space_link_fake',
      const OSError('Directory not empty', 66),
    );
    var deletes = 0;
    final waits = <Duration>[];

    await expectLater(
      _deleteWorkspaceWithRetry(
        root: '/tmp/space_link_fake',
        delete: () async {
          deletes++;
          throw failure;
        },
        exists: () => true,
        delay: (duration) async => waits.add(duration),
      ),
      throwsA(same(failure)),
    );

    expect(deletes, 5);
    expect(waits, hasLength(4));
    expect(waits, everyElement(const Duration(milliseconds: 50)));
  });

  test('workspace shutdown signals late arrivals and escalates', () async {
    final censuses = <Set<int>>[
      {11},
      {11, 12},
      {12},
      {12},
      {},
    ];
    final signals = <(int, ProcessSignal)>[];
    final waits = <Duration>[];

    await _stopAndAwaitWorkspaceProcesses(
      census: () async => censuses.removeAt(0),
      signal: (processId, processSignal) {
        signals.add((processId, processSignal));
        return true;
      },
      delay: (duration) async => waits.add(duration),
      polls: 2,
    );

    expect(signals, [
      (11, ProcessSignal.sigterm),
      (11, ProcessSignal.sigterm),
      (12, ProcessSignal.sigterm),
      (12, ProcessSignal.sigterm),
      (12, ProcessSignal.sigkill),
      (12, ProcessSignal.sigkill),
    ]);
    expect(waits, hasLength(4));
    expect(waits, everyElement(const Duration(milliseconds: 50)));
  });

  test(
    'a downstream runner links its tranquility-owned bead as a bd '
    'external dependency row',
    () async {
      final fixture = await _LinkStoreFixture.create();
      addTearDown(fixture.dispose);
      final root = fixture.root;
      await fixture.initStore('.grid', 'tranquility');
      await fixture.initStore('alpha', 'alpha');
      await fixture.initStore('beta', 'beta');
      // Both endpoints must be OBSERVABLE: the verb labels the target and adds
      // the row, and refuses when the target is not in its substation's store.
      await _runBd('$root/alpha', ['create', 'consumer', '--id', 'alpha-1']);
      await _runBd('$root/beta', ['create', 'provider', '--id', 'beta-1']);

      final previousWorkingDirectory = Directory.current.path;
      late CommandRunner<int> runner;
      try {
        Directory.current = root;
        runner = buildRunner(
          name: 'lunar',
          delegateFactory: _DownstreamDelegate.new,
        );
      } finally {
        Directory.current = previousWorkingDirectory;
      }

      expect(await runner.run(['link', '--grid-root', root, 'ls']), 0);
      expect(runner.commands['ls'], isNull);

      expect(
        await runner.run([
          'link',
          '--grid-root',
          root,
          '--blocked-by',
          'beta-1',
          'alpha-1',
        ]),
        0,
      );

      // The row is bd's, in the CONSUMER's own store. `bd dep list` resolves
      // each row to an issue RECORD and a cross-project target has none here,
      // so the row shows up as the record's dependency COUNT, never in that
      // listing — the same asymmetry grid_assets reads through bd's record
      // surface.
      final consumer = (await _beadJson('$root/alpha', 'alpha-1'))!;
      expect(consumer['dependency_count'], 1);

      // The TARGET carries the export label the row points at.
      expect(
        (await _beadJson('$root/beta', 'beta-1'))!['labels'],
        contains('export:beta-1'),
      );

      // NOTHING was minted in the station's own state store.
      expect(
        jsonDecode(await _runBd('$root/.grid', ['list', '--json'])),
        isEmpty,
      );
    },
    tags: ['bd-e2e'],
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
