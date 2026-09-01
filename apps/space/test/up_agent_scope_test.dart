import 'dart:io';

import 'package:test/test.dart';

/// `space up`'s AGENT SCOPE after the flag surgery (power_station ADR-0002
/// D4): ONE knob, `--env`, naming the station-default environment from the
/// ARMED registry. The model each role rides is the ENVIRONMENT's (D2) and
/// the per-role posture is the delegate's coded `arming` (D5) — there is no
/// --model, no --grader-model, and no --build-harness rung.
///
/// Bounded (`--for-seconds`) `--dry-run` boots over hermetic `bd init`
/// fixtures: a real lock and control surface, no spawn, no store write, no
/// git.
void main() {
  test('no --env: the station default is claude, the CODED arming still puts '
      'the build role on its codex environment', () async {
    final home = await _bdInitGridHome('space-scope-default-home-');
    final sub = await _bdInitWorkspace('space-scope-default-sub-');
    addTearDown(() async {
      await home.delete(recursive: true);
      await sub.delete(recursive: true);
    });

    final result = await _runUp(home: home, sub: sub);

    expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
    expect(
      '${result.stdout}',
      allOf(
        contains('agent scope: environment claude'),
        contains('build model gpt-5.6-sol'),
        contains('grader model sonnet'),
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('--env selects the station-default environment BY NAME from the armed '
      'registry — including a CUSTOM name no allowlist ever held', () async {
    final home = await _bdInitGridHome('space-scope-env-home-');
    final sub = await _bdInitWorkspace('space-scope-env-sub-');
    addTearDown(() async {
      await home.delete(recursive: true);
      await sub.delete(recursive: true);
    });

    // `cheap` is a memento CUSTOM environment (claude at haiku). Its grade
    // model is deliberately the INVERSE of the mid asset default, so a
    // regression that dropped --env would print `sonnet` and fail here. The
    // BUILD role stays on the coded codex arming: a seat/station rung
    // out-ranks the ambient one.
    final result = await _runUp(
      home: home,
      sub: sub,
      args: const ['--env', 'cheap'],
    );

    expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
    expect(
      '${result.stdout}',
      allOf(
        contains('agent scope: environment cheap'),
        contains('grader model haiku'),
        contains('build model gpt-5.6-sol'),
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// A bounded, hermetic `--dry-run` boot of the REAL `space` CLI: arms [sub]
/// under [home], prints the banner, and exits 0 a second later
/// (`--for-seconds`), from THIS package's root.
Future<ProcessResult> _runUp({
  required Directory home,
  required Directory sub,
  List<String> args = const [],
}) => Process.run(Platform.resolvedExecutable, [
  'bin/space.dart',
  'up',
  '--dry-run',
  '--grid-home',
  home.path,
  '--substation',
  'smoketest=${sub.path}',
  '--control-port',
  '0',
  '--for-seconds',
  '1',
  ...args,
], workingDirectory: Directory.current.path);

/// A hermetic GRID HOME: the state store lives NESTED at `<home>/.grid/.beads`
/// (Q5a stores-at-roots — `up` binds it exact-at-root).
Future<Directory> _bdInitGridHome(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  final resolved = Directory(dir.resolveSymbolicLinksSync());
  final runtimeDir = Directory('${resolved.path}/.grid')..createSync();
  await _bdInit(runtimeDir.path, args: const ['init', '--prefix', 'state']);
  return resolved;
}

/// A hermetic substation WORK store (embedded Dolt — never the live `tg`).
Future<Directory> _bdInitWorkspace(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  final resolved = Directory(dir.resolveSymbolicLinksSync());
  await _bdInit(resolved.path, args: const ['init']);
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
    fail('bd ${args.join(' ')} failed (${init.exitCode}): ${init.stderr}');
  }
}
