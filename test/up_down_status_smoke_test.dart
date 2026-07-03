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
///      200 with that token, a real OS SIGTERM drains it gracefully (exit 0,
///      the lock released);
///  (c) a SECOND `up` against the SAME state store while the first is live
///      is refused LOUD (exit 64, naming the live holder + the invariant);
///  (d) `status` renders live while up, and falls back to a direct,
///      read-only store view labeled `(station: down)` once it isn't;
///  (e) `down` stops the live station gracefully and no-ops cleanly
///      (exit 0) when nothing is up.
void main() {
  test('up boots resident (lock + control) -> a second up is refused LOUD -> '
      'status renders live -> a real SIGTERM drains it (exit 0, lock gone) -> '
      'status falls back to (station: down) -> down no-ops cleanly', () async {
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
    // control-advertise moment this test already waited on — a real OS
    // SIGTERM sent before that listener attaches would hit the default
    // (abrupt) disposition instead of the graceful path (the exact race
    // grid_cli's own RS-1 suite proves narrowly; this smoke just needs a
    // safe margin past it, not to re-litigate the race itself).
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // --- (b, cont'd) a REAL OS SIGTERM drains it gracefully ---------------
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

    // --- (e) `down` no-ops cleanly when nothing is up ---------------------
    final downAgain = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'down',
      '--state-workspace',
      stateDir.path,
    ], workingDirectory: Directory.current.path);
    expect(downAgain.exitCode, 0);
    expect('${downAgain.stdout}', contains('already down'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// `bd init`s a fresh, hermetic temp workspace (embedded Dolt — no server, no
/// credentials; mirrors `grid_controller`'s `HermeticWorkspace` test fixture).
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

/// `kill -0`: true iff [pid] is still alive and signalable by this user.
Future<bool> _isAlive(int pid) async =>
    (await Process.run('kill', ['-0', '$pid'])).exitCode == 0;
