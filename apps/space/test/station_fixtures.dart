import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Hermetic station fixtures, shared by the process-level smokes that drive the
/// REAL `bin/space.dart`. (`up_down_status_smoke_test.dart` keeps its own private
/// copies — migrating its unrelated assertions is churn.)

/// `bd init`s a fresh, hermetic temp work store (embedded Dolt — no server, no
/// credentials). Never touches the live `tg` store.
Future<Directory> bdInitWorkspace(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  final resolved = Directory(dir.resolveSymbolicLinksSync());
  await _bdInit(resolved.path, args: const ['init']);
  return resolved;
}

/// A hermetic GRID HOME: the state store lives NESTED at `<home>/.grid/.beads`
/// (Q5a stores-at-roots); the home root itself holds no store.
Future<Directory> bdInitGridHome(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  final resolved = Directory(dir.resolveSymbolicLinksSync());
  final runtimeDir = Directory('${resolved.path}/.grid')..createSync();
  await _bdInit(runtimeDir.path, args: const ['init', '--prefix', 'state']);
  return resolved;
}

/// Runs `bd [args]` in [dir] — a hermetic TEMP store this suite just created,
/// never a foreign store (A37). Fails the test LOUD on a non-zero exit.
Future<void> runBd(String dir, List<String> args) async {
  final run = await Process.run(
    'bd',
    args,
    workingDirectory: dir,
    environment: {...Platform.environment, 'BD_JSON_ENVELOPE': '1'},
    includeParentEnvironment: false,
  );
  if (run.exitCode != 0) {
    fail(
      'bd ${args.join(' ')} failed (${run.exitCode}): '
      '${run.stderr}\n${run.stdout}',
    );
  }
}

Future<void> _bdInit(String dir, {required List<String> args}) =>
    runBd(dir, args);

/// Spawns `bin/space.dart` over `dart`, with [vmOptions] passed to the VM BEFORE
/// the script (`--enable-vm-service=0` is what makes the station JIT-observable —
/// the run mode IS the dev-mode gate).
Future<Process> spawnSpace(
  List<String> args, {
  List<String> vmOptions = const [],
}) => Process.start(Platform.resolvedExecutable, [
  ...vmOptions,
  'bin/space.dart',
  ...args,
], workingDirectory: Directory.current.path);

/// Captures a spawned process's stdout/stderr for failure diagnostics.
class CapturedIo {
  /// Starts draining [process].
  CapturedIo(Process process) {
    process.stdout.transform(utf8.decoder).listen(out.write);
    process.stderr.transform(utf8.decoder).listen(err.write);
  }

  /// What the process wrote to stdout.
  final StringBuffer out = StringBuffer();

  /// What the process wrote to stderr.
  final StringBuffer err = StringBuffer();
}

/// Polls [io]'s stdout until it carries [token] (a bounded wait).
///
/// The lock is advertised BEFORE the banner is printed, so a test that has only
/// seen the lock has NOT necessarily seen the banner — asserting on [CapturedIo]
/// straight after [untilLockCarries] races the station's own stdout.
Future<void> untilOutputContains(CapturedIo io, String token) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if ('${io.out}'.contains(token)) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('timed out waiting for the station to print "$token"\ngot:\n${io.out}');
}

/// Polls the station lock at [lockPath] (a bounded wait — boot spans a real
/// `dart` JIT startup) until it parses AND carries every key in [keys].
Future<Map<String, Object?>> untilLockCarries(
  String lockPath,
  List<String> keys,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    final file = File(lockPath);
    if (await file.exists()) {
      try {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        if (keys.every((k) => json[k] != null)) return json;
      } on Object {
        // A torn write mid-acquire — keep polling.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('timed out waiting for $lockPath to carry ${keys.join('/')}');
}
