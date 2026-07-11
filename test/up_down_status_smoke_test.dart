import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart' show StationLockService;
import 'package:test/test.dart';

/// RS-5b / H2 (tg-r81, `the_grid/docs/SCRATCH-resident-station.md` D-R1/D-C3):
/// a PROCESS-LEVEL smoke over the REAL `space` CLI (`bin/space.dart`) —
/// nothing here calls into `lib/` directly. Migrated onto the v3 store model
/// (Track G-space / H2, DoD#6): `space up` now drives the C/D-era pieces —
/// `runGrid(SpaceDelegate())` over stores at roots — with the old
/// `composeStation`/`driveStation` boot path GONE. The resident
/// lock/control/drain contract (RS-2/RS-4/D-R2) survives, orchestrated by `up`
/// over the surviving lock/control primitives; the LIVE work-driving arm is
/// held for the human gate (Track J), so `--dry-run` mounts the tree and guards
/// the store but spawns no work.
///
/// Fixtures: a bd-init'd GRID HOME (its `.grid/station.lock` is the RS-2 lock;
/// its `.beads/` is what `space down`/`space status` discover to attach) and a
/// bd-init'd SUBSTATION ROOT (its `.beads/` is the substation's work store, the
/// exact-at-root store `up` resolves). No live `tg`, no real `claude`/`git`,
/// `--dry-run` throughout. What this file locks (the acceptance criteria):
///
///  (b) `up --dry-run` boots resident: the station lock exists, advertises a
///      REAL loopback control endpoint + bearer token, `GET /status` answers
///      200 with that token;
///  (c) a SECOND `up` against the SAME grid home while the first is live is
///      refused LOUD (exit 64, naming the live holder + the invariant);
///  (d) `status` renders live while up, and falls back to a direct, read-only
///      store view labeled `(station: down)` once it isn't;
///  (e) `down` ITSELF performs the graceful stop of a live station (its
///      `Stopped` message, exit 0, the lock released, AND the target process
///      confirmed exited) and no-ops cleanly (exit 0) when nothing is up. The
///      raw-OS-SIGTERM path is proven as its OWN case below.
///  (f) booting with TWO appended substations (v3: each a name AND its ONE
///      root; space-6ds round 3: flags APPEND, so both names are non-coded)
///      reports BOTH under `GET /status`'s `station.workRoot`, proving the
///      parsed multi-substation config reaches the live control surface.
///  (g) a NO-FLAG `up` over a fabricated umbrella (space-6ds Fork A/B: the
///      memento roster hardcoded in `SpaceDelegate.build` IS the default)
///      arms exactly the coded siblings that resolve work stores — skipping
///      the absent ones LOUD — and reports the armed set under
///      `station.workRoot`.
void main() {
  test('up boots resident (lock + control) -> a second up is refused LOUD -> '
      'status renders live -> `down` gracefully stops it (Stopped, exit 0, '
      'lock released, process exited) -> status falls back to '
      '(station: down) -> down no-ops cleanly when already down', () async {
    final gridHome = await _bdInitGridHome('space-up-smoke-home-');
    final subRoot = await _bdInitWorkspace('space-up-smoke-sub-');
    addTearDown(() async {
      await gridHome.delete(recursive: true);
      await subRoot.delete(recursive: true);
    });
    final lockPath = StationLockService.lockPath(gridHome.path);

    // --- (b) boot resident, wait for the lock to advertise control -------
    final up = await _spawnSpace([
      'up',
      '--dry-run',
      '--substation',
      'smoketest=${subRoot.path}',
      '--grid-home',
      gridHome.path,
      '--control-port',
      '0',
    ]);
    final upIo = _CapturedIo(up);
    addTearDown(() async {
      if (await _isAlive(up.pid)) {
        up.kill(ProcessSignal.sigkill);
      }
    });

    final lock = await _untilLockAdvertised(lockPath);
    final controlUrl = lock['controlUrl']! as String;
    final token = lock['token']! as String;

    final statusCode = await _get(
      Uri.parse('$controlUrl/status'),
      token: token,
    );
    expect(statusCode, HttpStatus.ok, reason: 'GET /status, the real bearer');

    // --- (c) a second `up` over the SAME grid home is refused LOUD -------
    final second = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'up',
      '--dry-run',
      '--substation',
      'smoketest=${subRoot.path}',
      '--grid-home',
      gridHome.path,
      '--control-port',
      '0',
    ], workingDirectory: Directory.current.path);
    expect(second.exitCode, 64, reason: 'refused at the station lock');
    expect(
      '${second.stderr}',
      allOf(
        contains('refusing to start'),
        contains('LIVE supervisor'),
        contains('ONE supervisor per station state store'),
      ),
    );

    // --- (d, live half) `status` renders the live station ----------------
    final liveStatus = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'status',
      '--state-workspace',
      gridHome.path,
      '--workspace',
      subRoot.path,
      '--substation',
      'smoketest',
    ], workingDirectory: Directory.current.path);
    expect(liveStatus.exitCode, 0);
    expect('${liveStatus.stdout}', contains('station: UP'));

    // A settle margin past the (now negligible) window between the control
    // advertise and `up`'s signal-listener attach — `up` attaches SIGINT/
    // SIGTERM synchronously right after `updateControl`, but this margin keeps
    // the smoke robust to scheduling on a loaded machine.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // --- (e) `down` ITSELF performs the graceful stop ----------------------
    final down = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'down',
      '--state-workspace',
      gridHome.path,
    ], workingDirectory: Directory.current.path);
    expect(down.exitCode, 0, reason: 'graceful stop.\nstderr: ${down.stderr}');
    expect(
      '${down.stdout}',
      contains('down: stopped station (pid ${up.pid}) — the lock is released.'),
    );

    final exitCode = await up.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        up.kill(ProcessSignal.sigkill);
        fail(
          'up did not exit after `down` reported Stopped.\n'
          'stdout: ${upIo.out}\nstderr: ${upIo.err}',
        );
      },
    );
    expect(exitCode, 0, reason: 'graceful drain.\nstderr: ${upIo.err}');
    expect(
      await File(lockPath).exists(),
      isFalse,
      reason: '`down`\'s graceful stop released the lock',
    );

    // --- (d, fallback half) `status` falls back once nothing is up -------
    final downStatus = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'status',
      '--state-workspace',
      gridHome.path,
      '--workspace',
      subRoot.path,
      '--substation',
      'smoketest',
    ], workingDirectory: Directory.current.path);
    expect(downStatus.exitCode, 0);
    expect('${downStatus.stdout}', contains('(station: down)'));

    // --- (e, cont'd) `down` no-ops cleanly when already down --------------
    final downAgain = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'down',
      '--state-workspace',
      gridHome.path,
    ], workingDirectory: Directory.current.path);
    expect(downAgain.exitCode, 0);
    expect('${downAgain.stdout}', contains('already down'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'a real OS SIGTERM to the resident process also drains it gracefully '
    '(exit 0, lock released) — the signal-path control `down` itself '
    'relies on (StationAttach.stop signals + polls exactly this path)',
    () async {
      final gridHome = await _bdInitGridHome('space-up-signal-home-');
      final subRoot = await _bdInitWorkspace('space-up-signal-sub-');
      addTearDown(() async {
        await gridHome.delete(recursive: true);
        await subRoot.delete(recursive: true);
      });
      final lockPath = StationLockService.lockPath(gridHome.path);

      final up = await _spawnSpace([
        'up',
        '--dry-run',
        '--substation',
        'smoketest=${subRoot.path}',
        '--grid-home',
        gridHome.path,
        '--control-port',
        '0',
      ]);
      final upIo = _CapturedIo(up);
      addTearDown(() async {
        if (await _isAlive(up.pid)) {
          up.kill(ProcessSignal.sigkill);
        }
      });

      final lock = await _untilLockAdvertised(lockPath);
      final controlUrl = lock['controlUrl']! as String;
      final token = lock['token']! as String;
      final statusCode = await _get(
        Uri.parse('$controlUrl/status'),
        token: token,
      );
      expect(statusCode, HttpStatus.ok, reason: 'GET /status, the real bearer');

      // A generous settle margin before the SIGTERM (see the lifecycle test).
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(Process.killPid(up.pid, ProcessSignal.sigterm), isTrue);
      final exitCode = await up.exitCode.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          up.kill(ProcessSignal.sigkill);
          fail(
            'up did not exit after SIGTERM.\n'
            'stdout: ${upIo.out}\nstderr: ${upIo.err}',
          );
        },
      );
      expect(exitCode, 0, reason: 'graceful drain.\nstderr: ${upIo.err}');
      expect(
        await File(lockPath).exists(),
        isFalse,
        reason: 'the graceful path released the lock',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('up --dry-run with TWO appended substations (v3: each a name AND its '
      'ONE root) reports BOTH under GET /status\'s station.workRoot', () async {
    final gridHome = await _bdInitGridHome('space-up-multi-home-');
    final rootA = await _bdInitWorkspace('space-up-multi-a-');
    final rootB = await _bdInitWorkspace('space-up-multi-b-');
    addTearDown(() async {
      await gridHome.delete(recursive: true);
      await rootA.delete(recursive: true);
      await rootB.delete(recursive: true);
    });
    final lockPath = StationLockService.lockPath(gridHome.path);

    final up = await _spawnSpace([
      'up',
      '--dry-run',
      '--substation',
      'smoketest=${rootA.path}',
      '--substation',
      'smokemate=${rootB.path}',
      '--grid-home',
      gridHome.path,
      '--control-port',
      '0',
    ]);
    final upIo = _CapturedIo(up);
    addTearDown(() async {
      if (await _isAlive(up.pid)) {
        up.kill(ProcessSignal.sigkill);
      }
    });

    final lock = await _untilLockAdvertised(lockPath);
    final controlUrl = lock['controlUrl']! as String;
    final token = lock['token']! as String;

    final status = await _getJson(
      Uri.parse('$controlUrl/status'),
      token: token,
    );
    final station = status['station']! as Map<String, Object?>;
    final workRoot = station['workRoot'] as String?;
    expect(
      workRoot,
      allOf(
        contains('smoketest=${rootA.path}'),
        contains('smokemate=${rootB.path}'),
      ),
      reason:
          'both substation roots must reach the live control surface\n'
          'full payload: $status\n'
          'stdout: ${upIo.out}\nstderr: ${upIo.err}',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('NO-FLAG up over a fabricated umbrella arms the coded siblings that '
      'resolve stores and skips the absent ones LOUD (space-6ds Fork A/B: '
      'the coded memento roster is the default drive set)', () async {
    // The umbrella: the grid home is a member directory whose SIBLINGS are the
    // coded `../<repo>` roots. Two of the five (genesis, the_grid) get real
    // bd stores; the other three are absent from this "checkout".
    final umbrella = Directory(
      (await Directory.systemTemp.createTemp(
        'space-up-coded-umbrella-',
      )).resolveSymbolicLinksSync(),
    );
    addTearDown(() => umbrella.delete(recursive: true));
    final gridHome = Directory('${umbrella.path}/home')..createSync();
    final runtimeDir = Directory('${gridHome.path}/.grid')..createSync();
    await _bdInit(runtimeDir.path, args: const ['init', '--prefix', 'state']);
    final genesisRoot = Directory('${umbrella.path}/genesis')..createSync();
    await _bdInit(genesisRoot.path, args: const ['init']);
    final theGridRoot = Directory('${umbrella.path}/the_grid')..createSync();
    await _bdInit(theGridRoot.path, args: const ['init', '--prefix', 'tg']);
    final lockPath = StationLockService.lockPath(gridHome.path);

    final up = await _spawnSpace([
      'up',
      '--dry-run',
      '--grid-home',
      gridHome.path,
      '--control-port',
      '0',
    ]);
    final upIo = _CapturedIo(up);
    addTearDown(() async {
      if (await _isAlive(up.pid)) {
        up.kill(ProcessSignal.sigkill);
      }
    });

    final lock = await _untilLockAdvertised(lockPath);
    final controlUrl = lock['controlUrl']! as String;
    final token = lock['token']! as String;

    final status = await _getJson(
      Uri.parse('$controlUrl/status'),
      token: token,
    );
    final station = status['station']! as Map<String, Object?>;
    final workRoot = station['workRoot'] as String?;
    expect(
      workRoot,
      allOf(
        contains('genesis=${genesisRoot.path}'),
        contains('the_grid=${theGridRoot.path}'),
        isNot(contains('power_station=')),
        isNot(contains('space_station=')),
        isNot(contains('lenny=')),
      ),
      reason:
          'the no-flag boot must arm EXACTLY the coded siblings with stores\n'
          'full payload: $status\n'
          'stdout: ${upIo.out}\nstderr: ${upIo.err}',
    );
    // The absent coded siblings were skipped LOUD, not silently dropped.
    for (final absent in ['power_station', 'space_station', 'lenny']) {
      expect(
        upIo.out.toString(),
        contains('skipping coded substation "$absent"'),
        reason: 'stdout: ${upIo.out}\nstderr: ${upIo.err}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// `bd init`s a fresh, hermetic temp workspace (embedded Dolt — no server, no
/// credentials; mirrors `beads_dart`'s `HermeticWorkspace` test fixture).
/// Never touches the live `tg` store.
Future<Directory> _bdInitWorkspace(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  final resolved = Directory(dir.resolveSymbolicLinksSync());
  await _bdInit(resolved.path, args: const ['init']);
  return resolved;
}

/// A hermetic GRID HOME: the state store lives NESTED at `<home>/.grid/.beads`
/// (Q5a stores-at-roots — `space up`'s assembly binds it exact-at-root and
/// refuses a home whose store sits anywhere else). The home root itself holds
/// no store.
Future<Directory> _bdInitGridHome(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  final resolved = Directory(dir.resolveSymbolicLinksSync());
  final runtimeDir = Directory('${resolved.path}/.grid')..createSync();
  await _bdInit(runtimeDir.path, args: const ['init', '--prefix', 'state']);
  return resolved;
}

Future<void> _bdInit(String dir, {required List<String> args}) async {
  final init = await Process.run(
    'bd',
    args,
    workingDirectory: dir,
    environment: {...Platform.environment, 'BD_JSON_ENVELOPE': '1'},
    includeParentEnvironment: false,
  );
  if (init.exitCode != 0) {
    fail(
      'bd ${args.join(' ')} failed (${init.exitCode}): '
      '${init.stderr}\n${init.stdout}',
    );
  }
}

/// Spawns `bin/space.dart` with [args] directly over `dart` (no `dart run`
/// wrapper — mirrors `grid_cli`'s own process-level smoke), from THIS package's
/// root.
Future<Process> _spawnSpace(List<String> args) => Process.start(
  Platform.resolvedExecutable,
  ['bin/space.dart', ...args],
  workingDirectory: Directory.current.path,
);

/// Captures a spawned process's stdout/stderr for failure diagnostics.
class _CapturedIo {
  _CapturedIo(Process process) {
    process.stdout.transform(utf8.decoder).listen(out.write);
    process.stderr.transform(utf8.decoder).listen(err.write);
  }

  final StringBuffer out = StringBuffer();
  final StringBuffer err = StringBuffer();
}

/// Polls [lockPath] (a bounded wait — `up`'s boot spans real `dart` JIT
/// startup) until it parses AND carries `controlUrl`/`token` (RS-4's advertise
/// moment, strictly after RS-2's acquire).
Future<Map<String, Object?>> _untilLockAdvertised(String lockPath) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final file = File(lockPath);
    if (await file.exists()) {
      try {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        if (json['controlUrl'] != null && json['token'] != null) return json;
      } on Object {
        // A torn write mid-acquire — keep polling.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('timed out waiting for $lockPath to advertise controlUrl/token');
}

/// A bearer-gated `GET`, returning the response status code (draining the
/// body — this helper only asserts reachability + auth, not the payload shape).
Future<int> _get(Uri url, {required String token}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// A bearer-gated `GET`, decoding the JSON body — the multi-substation case (f)
/// needs the actual `/status` payload (`station.workRoot`), not just
/// reachability.
Future<Map<String, Object?>> _getJson(Uri url, {required String token}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, HttpStatus.ok, reason: 'GET $url\n$body');
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}

/// `kill -0`: true iff [pid] is still alive and signalable by this user.
Future<bool> _isAlive(int pid) async =>
    (await Process.run('kill', ['-0', '$pid'])).exitCode == 0;
