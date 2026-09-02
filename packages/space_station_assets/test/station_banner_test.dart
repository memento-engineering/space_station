import 'dart:io';

import 'package:space_station_assets/space_station_assets.dart';
// ignore: implementation_imports
import 'package:space_station_assets/src/station_banner.dart';
// ignore: implementation_imports
import 'package:space_station_assets/src/up_command.dart' show UpCommand;
import 'package:test/test.dart';

/// space-grl: `up`'s boot banner and dev-mode line are authored from the
/// STATION COMPOSITION, never the literal word `space`. A downstream station
/// (the lunar pattern) composes this runner with its own name and JIT
/// invocation over a `SpaceDelegate` subclass, and every line it prints must
/// name ITS station and a verb that is actually on ITS path.
void main() {
  const lunarRunner = 'dart run lunar:lunar';

  group('a downstream station names ITSELF', () {
    test('the boot line names the downstream runner and station', () {
      final line = stationBootLine(runner: 'lunar', station: 'lunar');
      expect(line, 'lunar up — lunar as a Seed (runGrid)');
      expect(line, isNot(contains('space')));
    });

    test('dev mode OFF names the downstream reload verb AND an arming hint '
        'that is actually runnable for that runner', () {
      final line = devModeBannerLine(
        vmServiceUri: null,
        runner: 'lunar',
        runnerInvocation: lunarRunner,
      );
      expect(line, contains('dev mode: OFF (no VM service)'));
      expect(line, contains('`lunar reload` is unavailable'));
      expect(line, contains('`dart run --enable-vm-service lunar:lunar up …`'));
      expect(line, isNot(contains('space')));
    });

    test(
      'dev mode JIT names the VM service and the downstream reload verb',
      () {
        final line = devModeBannerLine(
          vmServiceUri: 'http://127.0.0.1:8181/aBc=/',
          runner: 'lunar',
          runnerInvocation: lunarRunner,
        );
        expect(line, contains('dev mode: JIT'));
        expect(line, contains('VM service http://127.0.0.1:8181/aBc=/'));
        expect(
          line,
          contains(
            '`lunar reload` ARMED '
            '(ext.exploration.grid.reload registered)',
          ),
        );
        expect(line, isNot(contains('space')));
      },
    );

    test('a runner invocation that is NOT a `dart run` form still renders a '
        'runnable hint rather than nonsense', () {
      expect(
        jitArmingInvocation('lunar'),
        'dart run --enable-vm-service lunar',
      );
    });
  });

  group("space's own lines", () {
    test('both dev-mode branches are BYTE-IDENTICAL to the hardcoded ones', () {
      expect(
        devModeBannerLine(
          vmServiceUri: null,
          runner: 'space',
          runnerInvocation: kSpaceRunner,
        ),
        'dev mode: OFF (no VM service) — `space reload` is unavailable; arm '
        'it JIT: `dart run --enable-vm-service space:space up …`',
      );
      expect(
        devModeBannerLine(
          vmServiceUri: 'http://127.0.0.1:8181/aBc=/',
          runner: 'space',
          runnerInvocation: kSpaceRunner,
        ),
        'dev mode: JIT — VM service http://127.0.0.1:8181/aBc=/  ·  '
        '`space reload` ARMED (ext.exploration.grid.reload registered)',
      );
    });

    test('the boot line is authored from stationName — the ONE deliberate '
        'wording change (docs/decisions, space-grl)', () {
      expect(
        stationBootLine(runner: 'space', station: 'space'),
        'space up — space as a Seed (runGrid)',
      );
    });
  });

  group('the composition threads the identity', () {
    test('a downstream buildRunner hands BOTH halves to `up`', () {
      final up =
          buildRunner(
                name: 'lunar',
                runnerInvocation: lunarRunner,
              ).commands['up']!
              as UpCommand;
      expect(up.runnerName, 'lunar');
      expect(up.runnerInvocation, lunarRunner);
    });

    test('the default runner is still space', () {
      final up = buildRunner().commands['up']! as UpCommand;
      expect(up.runnerName, 'space');
      expect(up.runnerInvocation, kSpaceRunner);
      // The bare constructor two other tests use keeps space's defaults.
      expect(UpCommand().runnerName, 'space');
    });
  });

  test('no hardcoded station literal survives in up_command.dart', () {
    final source = File('lib/src/up_command.dart').readAsStringSync();
    expect(source, isNotEmpty, reason: 'sanity: the source was found');
    const retired = <String>[
      'space_station as a Seed (runGrid)',
      'space reload',
      'space:space',
    ];
    final hits = [
      for (final token in retired)
        if (source.contains(token)) token,
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'up prints the COMPOSED identity, never the literal word: '
          '${hits.join(', ')}',
    );
  });
}
