import 'dart:io';

import 'package:test/test.dart';

/// `space up`'s AGENT SCOPE — the station's two model RUNGS, split by role.
/// The rungs are asymmetric ON PURPOSE: `params['model']` is simultaneously the
/// harness TRANSPORT key every harness reads, so ONE map cannot carry two roles'
/// models — the BUILD rung stays there (`--model`) and the GRADE rung rides its
/// own field (`--grader-model` → `AgentConfig.graderModel`).
///
/// Bounded (`--for-seconds`) `--dry-run` boots over hermetic `bd init` fixtures:
/// a real lock and control surface, no spawn, no store write, no git.
void main() {
  test(
    'NO --model / NO --grader-model: each role falls through to its ASSET '
    'default — build on opus, grade on sonnet. The station-side `?? sonnet` '
    'pin that out-ranked those defaults (and drove an ALL-sonnet grid) is GONE',
    () async {
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
        allOf(contains('build model opus'), contains('grader model sonnet')),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '--model and --grader-model set the two rungs INDEPENDENTLY — the grade '
    "model reaches AgentConfig.graderModel, never params['model']",
    () async {
      final home = await _bdInitGridHome('space-scope-split-home-');
      final sub = await _bdInitWorkspace('space-scope-split-sub-');
      addTearDown(() async {
        await home.delete(recursive: true);
        await sub.delete(recursive: true);
      });

      // Deliberately the INVERSE of the asset defaults (opus build / sonnet
      // grade), so a regression that dropped either flag would still print the
      // defaults and fail here.
      final result = await _runUp(
        home: home,
        sub: sub,
        args: const ['--model', 'sonnet', '--grader-model', 'haiku'],
      );

      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(
        '${result.stdout}',
        allOf(contains('build model sonnet'), contains('grader model haiku')),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
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
