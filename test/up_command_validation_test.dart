import 'dart:io';

import 'package:test/test.dart';

/// RS-5b / H2 (tg-r81): offline coverage for `UpCommand`'s boot-eager
/// validation + v3 arming branches (`up_command.dart`'s `run()`) — the
/// `--openai-base`/`--swift-base` mutual exclusion, a malformed endpoint url,
/// the boot-eager `AgentHarnessRegistry.validate` legality check, and the
/// stores-at-roots arming gates (`--grid-home` + `--substation <name>=<root>`,
/// the exact-at-root work-store refusal). Every case here returns BEFORE the
/// station lock is acquired or the tree mounts — no lock, no boot, no wait.
///
/// Exercised over the real `space` CLI (`bin/space.dart`) because
/// `Stdout`/`Stderr` cannot be faked in-process (no public constructor), so a
/// real process is this codebase's only capture seam for a command's rendered
/// refusal text.
///
/// Track G-space / H2: the resident-station flags + config construction live in
/// `space_delegate.dart` as space's OWN v3 CLI surface
/// (`addSpaceStationFlags` / `spaceStationConfigFrom`) — no `StationArgs`, no
/// `RootSpec`, no `--workspace` axis. A substation is a name AND its ONE root,
/// paired in `--substation <name>=<root>`.
void main() {
  group('boot-eager agent-scope validation (returns before any config)', () {
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
        contains('space up: --openai-base is not an absolute url: "not-a-url"'),
      );
    });

    test('a harness x target combo the registry rejects is refused LOUD (exit '
        '64) — the boot-eager AgentHarnessRegistry.validate check', () async {
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
    });
  });

  group('v3 stores-at-roots arming (returns before the lock / tree mount)', () {
    test('NO --grid-home and NO --substation is refused LOUD (exit 64) — v3 §0: '
        'no default root, no default substation', () async {
      final result = await _runUp([]);
      expect(result.exitCode, 64);
      expect(
        '${result.stderr}',
        allOf(
          contains('--grid-home'),
          contains('--substation <name>=<root>'),
          contains('required to ARM'),
        ),
      );
    });

    test('--grid-home present but NO --substation is refused LOUD (exit 64)',
        () async {
      final result = await _runUp(['--grid-home', '/tmp/space-up-nosub']);
      expect(result.exitCode, 64);
      expect('${result.stderr}', contains('required to ARM'));
    });

    test('a --substation with no "=" (unpaired name) is a LOUD FormatException '
        '— a config defect the operator sees immediately, not exit 64', () async {
      final result = await _runUp([
        '--grid-home',
        '/tmp/space-up-unpaired',
        '--substation',
        'lonely',
      ]);
      expect(result.exitCode, isNot(0));
      expect(
        '${result.stderr}',
        contains(
          'FormatException: space up: --substation "lonely" must pair a name '
          'with its ONE root',
        ),
      );
    });

    test('registering the SAME --substation name twice is a LOUD FormatException '
        '(never a silent overwrite)', () async {
      final result = await _runUp([
        '--grid-home',
        '/tmp/space-up-dup',
        '--substation',
        'foo=/tmp/a',
        '--substation',
        'foo=/tmp/b',
      ]);
      expect(result.exitCode, isNot(0));
      expect(
        '${result.stderr}',
        contains(
          'FormatException: space up: --substation "foo=/tmp/b" registers name '
          '"foo" more than once',
        ),
      );
    });

    test('a RELATIVE substation root is refused LOUD (exit 64) — cwd-relative '
        'roots re-import the ambience v3 kills', () async {
      final result = await _runUp([
        '--grid-home',
        '/tmp/space-up-rel',
        '--substation',
        'foo=relative/path',
      ]);
      expect(result.exitCode, 64);
      expect(
        '${result.stderr}',
        allOf(contains('space up:'), contains('ABSOLUTE')),
      );
    });

    test('an absolute substation root with NO `.beads/` work store is refused '
        'LOUD (exit 1) — exact-at-root, no walk-up (grid_sdk StoreLocator)',
        () async {
      final result = await _runUp([
        '--grid-home',
        '/tmp/space-up-nostore',
        '--substation',
        'foo=/tmp/space-up-nonexistent-work-root-xyz',
      ]);
      expect(result.exitCode, 1);
      expect(
        '${result.stderr}',
        allOf(
          contains('space up:'),
          contains('no work store'),
          contains('/tmp/space-up-nonexistent-work-root-xyz'),
        ),
      );
    });
  });
}

/// Runs `space up` with [args] from THIS package's root, directly over `dart`
/// (no `dart run` wrapper — mirrors `up_down_status_smoke_test.dart`).
Future<ProcessResult> _runUp(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['bin/space.dart', 'up', ...args],
  workingDirectory: Directory.current.path,
);
