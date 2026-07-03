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
///
/// RS-5b rework round 2 (tg-1di): the `--root` grammar tg-7gm's multi-root
/// surface mirrors (`_addResidentStationFlags`/`_residentStationArgsFrom`,
/// both private to `up_command.dart` — there is no public seam a test can
/// call directly, so this stays process-level). The three PARSE-SUCCEEDS
/// shapes (bare shorthand / `name=path` / `name=path@head`) are proven by
/// `--no-dry-run`ing PAST the `--root` gate: a parse failure would throw an
/// uncaught `FormatException` (see the duplicate-name case) or trip the
/// `requires --root` refusal below — reaching the NEXT gate
/// (`requires --state-workspace`) instead is the observable proof the
/// `--root` value parsed clean, with no real workspace ever touched.
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

  test(
    'a live arm (--no-dry-run) with NO --root at all is refused LOUD (exit '
    '64) — validateArming\'s root gate, unchanged by the tg-7gm grammar',
    () async {
      final result = await _runUp(['--substation', 'foo', '--no-dry-run']);
      expect(result.exitCode, 64);
      expect(
        '${result.stderr}',
        contains('a non-dry (live) run requires --root'),
      );
    },
  );

  group('the tg-7gm --root grammar parses (proven by reaching the NEXT '
      'gate, --state-workspace, rather than being refused for a missing '
      '--root)', () {
    test('a bare --root <path> (no "=") — the single-root shorthand', () async {
      final result = await _runUp([
        '--substation',
        'foo',
        '--no-dry-run',
        '--root',
        '/tmp/some/path',
      ]);
      expect(result.exitCode, 64);
      expect(
        '${result.stderr}',
        contains('a non-dry (live) run requires --state-workspace'),
      );
    });

    test('"--root <name>=<path>" — an explicitly named root', () async {
      final result = await _runUp([
        '--substation',
        'foo',
        '--no-dry-run',
        '--root',
        'foo=/tmp/some/path',
      ]);
      expect(result.exitCode, 64);
      expect(
        '${result.stderr}',
        contains('a non-dry (live) run requires --state-workspace'),
      );
    });

    test('"--root <name>=<path>@<head>" — a per-root assigned head', () async {
      final result = await _runUp([
        '--substation',
        'foo',
        '--no-dry-run',
        '--root',
        'foo=/tmp/some/path@some-branch',
      ]);
      expect(result.exitCode, 64);
      expect(
        '${result.stderr}',
        contains('a non-dry (live) run requires --state-workspace'),
      );
    });
  });

  test('registering the SAME --root name twice is refused LOUD: '
      '_residentStationArgsFrom throws a FormatException BEFORE the '
      'try/catch in run() that maps StationRefusal -> (message, code) — an '
      'uncaught exception, not exit 64 (a config defect the operator should '
      'see immediately, not silently overwrite)', () async {
    final result = await _runUp([
      '--substation',
      'foo',
      '--root',
      'foo=/tmp/a',
      '--root',
      'foo=/tmp/b',
    ]);
    expect(result.exitCode, isNot(0));
    expect(
      '${result.stderr}',
      contains(
        'FormatException: space up: --root "foo=/tmp/b" registers name '
        '"foo" more than once',
      ),
    );
  });
}

/// Runs `space up` with [args] (no station flags — every case here refuses
/// before any workspace IO) from THIS package's root, directly over `dart`
/// (no `dart run` wrapper — mirrors `up_down_status_smoke_test.dart`).
Future<ProcessResult> _runUp(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['bin/space.dart', 'up', ...args],
  workingDirectory: Directory.current.path,
);
