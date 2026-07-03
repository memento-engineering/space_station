import 'dart:io';

import 'package:test/test.dart';

/// RS-5b rework round 1 (tg-3s8.6): offline coverage for `UpCommand`'s
/// boot-eager validation branches (`up_command.dart`'s `run()`, mirroring
/// `CodeRunCommand`'s) — the `--openai-base`/`--swift-base` mutual
/// exclusion, a malformed endpoint url, and the boot-eager
/// `AgentHarnessRegistry.validate` legality check. All three RETURN before
/// `validateArming`/`discoverWorkspaces`/`buildControllers` run, so none of
/// them touch a beads workspace or the station lock — no `--workspace`,
/// `--state-workspace`, `--substation`, or `--root` needed. Still exercised
/// over the real `space` CLI (`bin/space.dart`) for the same reason
/// `up_down_status_smoke_test.dart` is: `Stdout`/`Stderr` cannot be faked
/// in-process (no public constructor), so a real process is this codebase's
/// only capture seam for a command's rendered refusal text — but unlike that
/// file's full lifecycle boot/shutdown smoke, every case here returns
/// immediately (no lock, no boot, no wait).
void main() {
  test(
    '--openai-base + --swift-base together is refused LOUD (exit 64)',
    () async {
      final result = await _runUp([
        '--openai-base',
        'http://localhost:1234',
        '--swift-base',
        'http://localhost:5678',
      ]);
      expect(result.exitCode, 64);
      expect(
        '${result.stderr}',
        contains('space up: pass --openai-base OR --swift-base, not both.'),
      );
    },
  );

  test('a malformed --openai-base url is refused LOUD (exit 64)', () async {
    final result = await _runUp(['--openai-base', 'not-a-url']);
    expect(result.exitCode, 64);
    expect(
      '${result.stderr}',
      contains(
        'space up: --openai-base is not an absolute url: "not-a-url"',
      ),
    );
  });

  test(
    'a harness x target combo the registry rejects is refused LOUD (exit '
    '64) — the boot-eager AgentHarnessRegistry.validate check',
    () async {
      final result = await _runUp([
        '--harness',
        'claude',
        '--swift-base',
        'http://localhost:4321',
      ]);
      expect(result.exitCode, 64);
      expect(
        '${result.stderr}',
        allOf(
          contains('space up: harness "claude" cannot reach'),
          contains('fail-closed'),
        ),
      );
    },
  );
}

/// Runs `space up` with [args] (no station flags — every case here refuses
/// before any workspace IO) from THIS package's root, directly over `dart`
/// (no `dart run` wrapper — mirrors `up_down_status_smoke_test.dart`).
Future<ProcessResult> _runUp(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['bin/space.dart', 'up', ...args],
  workingDirectory: Directory.current.path,
);
