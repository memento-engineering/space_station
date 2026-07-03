import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart' show StationLockService;
import 'package:test/test.dart';

/// RS-5b (tg-3s8.6, `the_grid/docs/SCRATCH-resident-station.md` D-R1/D-C3):
/// a PROCESS-LEVEL smoke over the REAL `space` CLI (`bin/space.dart`) —
/// nothing here calls into `lib/` directly. Two hermetic, `bd init`'d temp
/// beads workspaces (a work store + a SEPARATE state store, A36/A37); no live
/// `tg`, no real `claude`/`git`, `--dry-run` throughout. What this file
/// locks (the acceptance criteria):
///
///  (b) `up --dry-run` boots resident: the station lock exists, advertises a
///      REAL loopback control endpoint + bearer token, `GET /status` answers
///      200 with that token;
///  (c) a SECOND `up` against the SAME state store while the first is live
///      is refused LOUD (exit 64, naming the live holder + the invariant);
///  (d) `status` renders live while up, and falls back to a direct,
///      read-only store view labeled `(station: down)` once it isn't;
///  (e) `down` ITSELF performs the graceful stop of a live station (its
///      `Stopped` message, exit 0, the lock released, AND the target process
///      confirmed exited) and no-ops cleanly (exit 0) when nothing is up.
///      The raw-OS-SIGTERM path (e)'s `down` rides internally is proven as
///      its OWN case below — the signal-path control `down` depends on.
///  (f) RS-5b rework round 2 (tg-1di, tg-7gm's multi-root surface): booting
///      with TWO named `--root` registrations — one equal to the owned
///      `--substation` (its DEFAULT) and one EXTRA name — `GET /status`
///      reports BOTH under `station.workRoot`, proving the parsed
///      `StationArgs.roots` map (not just a single legacy path) actually
///      reaches the live control surface.
void main() {
  test('up boots resident (lock + control) -> a second up is refused LOUD -> '
      'status renders live -> `down` gracefully stops it (Stopped, exit 0, '
      'lock released, process exited) -> status falls back to '
      '(station: down) -> down no-ops cleanly when already down', () async {
    final workDir = await _bdInitWorkspace('space-up-smoke-work-');
    final stateDir = await _bdInitWorkspace('space-up-smoke-state-');
    addTearDown(() async {
      await workDir.delete(recursive: true);
      await stateDir.delete(recursive: true);
    });
    final lockPath = StationLockService.lockPath(stateDir.path);

    // --- (b) boot resident, wait for the lock to advertise control -------
    final up = await _spawnSpace([
      'up',
      '--dry-run',
      '--substation',
      'smoketest',
      '--workspace',
      workDir.path,
      '--state-workspace',
      stateDir.path,
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

    // --- (c) a second `up` over the SAME state store is refused LOUD -----
    final second = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'up',
      '--dry-run',
      '--substation',
      'smoketest',
      '--workspace',
      workDir.path,
      '--state-workspace',
      stateDir.path,
      '--control-port',
      '0',
    ], workingDirectory: Directory.current.path);
    expect(second.exitCode, 64, reason: 'refused before any composition');
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
      stateDir.path,
      '--workspace',
      workDir.path,
      '--substation',
      'smoketest',
    ], workingDirectory: Directory.current.path);
    expect(liveStatus.exitCode, 0);
    expect('${liveStatus.stdout}', contains('station: UP'));

    // A settle margin: driveStation attaches its signal listener AFTER
    // sources.start()/wiring.start() complete, strictly later than the
    // control-advertise moment this test already waited on — a SIGTERM sent
    // before that listener attaches (whether raw, or via `down` below) would
    // hit the default (abrupt) disposition instead of the graceful path (the
    // exact race grid_cli's own RS-1 suite proves narrowly; this smoke just
    // needs a safe margin past it, not to re-litigate the race itself).
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // --- (e) `down` ITSELF performs the graceful stop ----------------------
    final down = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'down',
      '--state-workspace',
      stateDir.path,
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
      stateDir.path,
      '--workspace',
      workDir.path,
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
      stateDir.path,
    ], workingDirectory: Directory.current.path);
    expect(downAgain.exitCode, 0);
    expect('${downAgain.stdout}', contains('already down'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'a real OS SIGTERM to the resident process also drains it gracefully '
    '(exit 0, lock released) — the signal-path control `down` itself '
    'relies on (StationAttach.stop signals + polls exactly this path)',
    () async {
      final workDir = await _bdInitWorkspace('space-up-signal-work-');
      final stateDir = await _bdInitWorkspace('space-up-signal-state-');
      addTearDown(() async {
        await workDir.delete(recursive: true);
        await stateDir.delete(recursive: true);
      });
      final lockPath = StationLockService.lockPath(stateDir.path);

      final up = await _spawnSpace([
        'up',
        '--dry-run',
        '--substation',
        'smoketest',
        '--workspace',
        workDir.path,
        '--state-workspace',
        stateDir.path,
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

      // A settle margin — GENEROUS, not the lifecycle test's 500ms: THAT test's
      // margin is safe only because the second-`up`-refused + live-`status`
      // round trips ahead of it already burn several real seconds (each spins
      // up its own `dart`/`bd` subprocess), which is what actually outlasts
      // `sources.start()`/`wiring.start()` (a real Dolt-backed workspace boot,
      // not a fixed-cost step) before this test's SIGTERM. This test has no
      // such incidental warm-up, so it waits outright (empirically bisected on
      // this machine: 2s still raced the listener attach, 3-3.5s consistently
      // didn't — 5s below is that margin plus headroom).
      await Future<void>.delayed(const Duration(seconds: 5));

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

  test('up --dry-run with TWO named --root registrations (tg-7gm) reports '
      'BOTH under GET /status\'s station.workRoot — the DEFAULT (named after '
      'the owned --substation) and an EXTRA named root', () async {
    final workDir = await _bdInitWorkspace('space-up-multiroot-work-');
    final stateDir = await _bdInitWorkspace('space-up-multiroot-state-');
    addTearDown(() async {
      await workDir.delete(recursive: true);
      await stateDir.delete(recursive: true);
    });
    final lockPath = StationLockService.lockPath(stateDir.path);

    const defaultRoot = '/tmp/space-up-multiroot-default';
    const extraRoot = '/tmp/space-up-multiroot-extra';
    final up = await _spawnSpace([
      'up',
      '--dry-run',
      '--substation',
      'smoketest',
      '--workspace',
      workDir.path,
      '--state-workspace',
      stateDir.path,
      '--control-port',
      '0',
      '--root',
      'smoketest=$defaultRoot',
      '--root',
      'power_station=$extraRoot',
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
        contains('smoketest=$defaultRoot'),
        contains('power_station=$extraRoot'),
      ),
      reason:
          'both registered roots must reach the live control surface, '
          'not just the owned substation\'s own\nfull payload: $status\n'
          'stdout: ${upIo.out}\nstderr: ${upIo.err}',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));
}

/// `bd init`s a fresh, hermetic temp workspace (embedded Dolt — no server, no
/// credentials; mirrors `beads_dart`'s `HermeticWorkspace` test fixture).
/// Never touches the live `tg` store.
Future<Directory> _bdInitWorkspace(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  final resolved = Directory(dir.resolveSymbolicLinksSync());
  final init = await Process.run(
    'bd',
    ['init'],
    workingDirectory: resolved.path,
    environment: {...Platform.environment, 'BD_JSON_ENVELOPE': '1'},
    includeParentEnvironment: false,
  );
  if (init.exitCode != 0) {
    await resolved.delete(recursive: true);
    fail('bd init failed (${init.exitCode}): ${init.stderr}\n${init.stdout}');
  }
  return resolved;
}

/// Spawns `bin/space.dart` with [args] directly over `dart` (no `dart run`
/// wrapper — mirrors `grid_cli`'s own process-level smoke,
/// `station_signals_test.dart`), from THIS package's root.
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
/// startup + `bd` calls under the CLI read path) until it parses AND carries
/// `controlUrl`/`token` (RS-4's advertise moment, strictly after RS-2's
/// acquire).
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
/// body — this helper only asserts reachability + auth, not the payload
/// shape, which `station_control_test.dart` already locks upstream).
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

/// A bearer-gated `GET`, decoding the JSON body — the multi-root case (f)
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
