import 'dart:io';

import 'package:grid_cli/grid_cli.dart' show StationLockService;
import 'package:test/test.dart';

import 'station_fixtures.dart';

/// A PROCESS-LEVEL smoke over the REAL `space` CLI: the EXPLICIT hot-reload
/// trigger, end to end. A live JIT station advertises its VM service in the 0600
/// lock; a SEPARATE `space reload` process connects to it, swaps sources, and
/// invokes `ext.exploration.grid.reload` — which re-composes the RUNNING station
/// (no second station is started). The AOT case is the same code path with no VM
/// service: nothing is armed and the client refuses LOUD.
void main() {
  test('JIT: the lock advertises the VM service and a separate `space reload` '
      'RE-COMPOSES the resident station (generation 1)', () async {
    final gridHome = await bdInitGridHome('space-reload-home-');
    final subRoot = await bdInitWorkspace('space-reload-sub-');
    addTearDown(() async {
      await gridHome.delete(recursive: true);
      await subRoot.delete(recursive: true);
    });
    final lockPath = StationLockService.lockPath(gridHome.path);

    final up = await spawnSpace([
      'up',
      '--dry-run',
      '--substation',
      'smoketest=${subRoot.path}',
      '--grid-home',
      gridHome.path,
      '--control-port',
      '0',
    ], vmOptions: const ['--enable-vm-service=0']);
    final io = CapturedIo(up);
    addTearDown(() => up.kill(ProcessSignal.sigkill));

    // The dev-mode advertisement: JIT ⇒ the lock carries the VM-service URI.
    final lock = await untilLockCarries(lockPath, [
      'controlUrl',
      'vmServiceUri',
    ]);
    expect('${lock['vmServiceUri']}', startsWith('http://127.0.0.1:'));
    await untilOutputContains(io, '`space reload` ARMED');

    final reload = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'reload',
      '--grid-home',
      gridHome.path,
    ], workingDirectory: Directory.current.path);

    expect(
      reload.exitCode,
      0,
      reason: 'reload stderr: ${reload.stderr}\nstation stderr: ${io.err}',
    );
    expect('${reload.stdout}', contains('reload: reload OK'));
    expect('${reload.stdout}', contains('generation 1'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('no VM service (an AOT binary, or JIT without the flag — the SAME state '
      'at this seam): nothing is armed, the lock carries no vmServiceUri, and '
      '`space reload` refuses LOUD', () async {
    final gridHome = await bdInitGridHome('space-noreload-home-');
    final subRoot = await bdInitWorkspace('space-noreload-sub-');
    addTearDown(() async {
      await gridHome.delete(recursive: true);
      await subRoot.delete(recursive: true);
    });
    final lockPath = StationLockService.lockPath(gridHome.path);

    final up = await spawnSpace([
      'up',
      '--dry-run',
      '--substation',
      'smoketest=${subRoot.path}',
      '--grid-home',
      gridHome.path,
      '--control-port',
      '0',
    ]); // no --enable-vm-service: the run mode IS the gate
    final io = CapturedIo(up);
    addTearDown(() => up.kill(ProcessSignal.sigkill));

    final lock = await untilLockCarries(lockPath, ['controlUrl']);
    expect(lock['vmServiceUri'], isNull, reason: 'nothing to advertise');
    await untilOutputContains(io, 'dev mode: OFF');

    final reload = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'reload',
      '--grid-home',
      gridHome.path,
    ], workingDirectory: Directory.current.path);

    expect(reload.exitCode, 1);
    expect('${reload.stderr}', contains('advertises no VM service'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
