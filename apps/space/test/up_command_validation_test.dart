import 'dart:io';

import 'package:test/test.dart';

/// RS-5b / H2 (tg-r81): offline coverage for `UpCommand`'s boot-eager
/// validation + v3 arming branches (`up_command.dart`'s `run()`) — that the
/// DELETED machine-fact endpoint flags (`--openai-base`/`--swift-base`) are
/// gone (ADR-0002 D4: WHERE inference runs is the named environment's own
/// property, and an endpoint is a site-binding machine-fact, never argv), and
/// the stores-at-roots arming gates (`--grid-home`, the coded roster +
/// `--substation` merge, the exact-at-root work-store refusal). Every case here
/// returns BEFORE the station lock is acquired or the tree mounts — no lock, no
/// boot, no wait.
///
/// space-6ds round 3 (`the_grid/docs/SCRATCH-memento-composition.md`):
/// `--substation` is no longer required — no-flag `space up` arms the CODED
/// memento roster, hardcoded in `SpaceDelegate.build` (Fork A); a flag
/// APPENDS a new substation after it, and a flag naming a CODED substation is
/// a LOUD refusal (Fork B as re-ruled: the org is forked, never overridden).
/// Outside the umbrella the coded siblings do not resolve, so a hermetic
/// (non-umbrella) grid home arms nothing — itself a LOUD refusal (exit 1). An
/// APPENDED substation with no store still refuses LOUD; a coded one absent
/// from the checkout is skipped, not fatal.
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
  group('deleted machine-fact endpoint flags (ADR-0002 D4)', () {
    // WHERE inference runs is a property of the named environment, and an
    // endpoint is a site-binding machine-fact (D3) — never argv. The old
    // --openai-base/--swift-base flags and the harness×target legality table
    // are DELETED (no deprecation). The flags no longer parse.
    test(
      '--openai-base is gone — rejected as an unknown option (exit 64)',
      () async {
        final result = await _runUp(['--openai-base', 'http://localhost:1234']);
        expect(result.exitCode, 64);
        expect('${result.stderr}', contains('openai-base'));
      },
    );

    test(
      '--swift-base is gone — rejected as an unknown option (exit 64)',
      () async {
        final result = await _runUp(['--swift-base', 'http://localhost:5678']);
        expect(result.exitCode, 64);
        expect('${result.stderr}', contains('swift-base'));
      },
    );
  });

  group('deleted agent-scope flags (ADR-0002 D4)', () {
    // A20(2)'s no-wedge rule is SATISFIED by deletion: a removed flag is a
    // loud argparse usage error (exit 64), never a silent drop. Model
    // selection is the named environment's (D2) and the per-role posture is
    // the delegate's coded arming (D5) — neither is an operator flag.
    for (final flag in const <String>[
      'harness',
      'build-harness',
      'model',
      'grader-model',
    ]) {
      test('--$flag is gone — refused by the PARSER (exit 64)', () async {
        final result = await _runUp(['--$flag', 'claude']);
        expect(result.exitCode, 64);
        // Split rather than one literal: args 2.7 renders `Could not find an
        // option named "--x".` while older args omits the dashes.
        expect(
          '${result.stderr}',
          allOf(contains('Could not find an option named'), contains(flag)),
        );
      });
    }

    test('an UNARMED --env name is refused LOUD (exit 64) before any tree '
        'mounts, and the refusal lists the armed registry', () async {
      final result = await _runUp(['--env', 'nope']);
      expect(result.exitCode, 64);
      expect(
        '${result.stderr}',
        allOf(
          contains('--env "nope"'),
          contains('names no armed environment'),
          contains('codex-frontier'),
        ),
      );
    });
  });

  group('v3 stores-at-roots arming (returns before the lock / tree mount)', () {
    test(
      'NO --grid-home is refused LOUD (exit 64) — v3 §0: no default grid home '
      '(the roster now defaults to the coded org, but the home never does)',
      () async {
        final result = await _runUp([]);
        expect(result.exitCode, 64);
        expect(
          '${result.stderr}',
          allOf(
            contains('--grid-home'),
            contains('required to ARM'),
            contains('no default grid home'),
          ),
        );
      },
    );

    test('--grid-home present but NO --substation, OUTSIDE the umbrella: the '
        'coded siblings do not resolve, so nothing arms — a LOUD refusal (exit '
        '1), never a silent empty boot', () async {
      // An isolated grid home whose `../<repo>` siblings cannot exist, so every
      // coded substation is skipped and the armed roster is empty.
      final result = await _runUp([
        '--grid-home',
        '/tmp/space-6ds-nosub-xyz/home',
      ]);
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('nothing to arm'));
    });

    test(
      'a --substation with no "=" (unpaired name) is a LOUD FormatException '
      '— a config defect the operator sees immediately, not exit 64',
      () async {
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
      },
    );

    test('a --substation with an EMPTY "@" prefix is a LOUD FormatException — '
        'omit the "@" entirely when the prefix is the name', () async {
      final result = await _runUp([
        '--grid-home',
        '/tmp/space-up-empty-prefix',
        '--substation',
        'the_grid@=/tmp/tg',
      ]);
      expect(result.exitCode, isNot(0));
      expect('${result.stderr}', contains('has an empty prefix after "@"'));
    });

    test('--land is GONE — the retired arming flag is refused by the PARSER '
        '(exit 64), never silently accepted: delivery is a per-substation '
        'BINDING now, not a station boolean (the_grid ADR-0000 A51)', () async {
      final result = await _runUp([
        '--dry-run',
        '--land',
        '--grid-home',
        '/tmp/space-up-land-retired',
        '--substation',
        'foo=/tmp/a',
      ]);
      expect(result.exitCode, 64);
      // Split rather than one literal: args 2.7 renders `Could not find an
      // option named "--land".` while older args omits the dashes.
      expect(
        '${result.stderr}',
        allOf(contains('Could not find an option named'), contains('land')),
      );
    });

    test(
      'a --substation naming a CODED substation is a LOUD FormatException '
      '— the hardcoded roster is forked, never overridden (round 3)',
      () async {
        final result = await _runUp([
          '--grid-home',
          '/tmp/space-up-coded-name',
          '--substation',
          'power_station=/tmp/ps',
        ]);
        expect(result.exitCode, isNot(0));
        expect(
          '${result.stderr}',
          allOf(
            contains(
              'FormatException: space up: --substation "power_station=/tmp/ps" '
              'names the CODED substation "power_station"',
            ),
            contains('APPEND new substations only'),
          ),
        );
      },
    );

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

    test(
      'an absolute substation root with NO `.beads/` work store is refused '
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
      },
    );
  });
}

/// Runs `space up` with [args] from THIS package's root, directly over `dart`
/// (no `dart run` wrapper — mirrors `up_down_status_smoke_test.dart`).
Future<ProcessResult> _runUp(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['bin/space.dart', 'up', ...args],
  workingDirectory: Directory.current.path,
);
