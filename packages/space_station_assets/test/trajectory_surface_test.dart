import 'package:args/args.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show
        TrajectoryConfig,
        TrajectoryConfigMode,
        TrajectoryHarnessMode,
        TrajectoryHarnessStatus;
import 'package:space_station_assets/src/up_command.dart';
import 'package:test/test.dart';

/// Chunk WS of stage1-wiring (`the_grid/docs/design/trajectory/`): the
/// Stage-1 runner surface space_station owns — the `--trajectory` /
/// `--no-trajectory` flag, the [TrajectoryConfig] it threads into
/// `assembleStationWork`, the boot banner's posture line, and the `/status`
/// trajectory block.
///
/// Pure + offline: every piece under test is a function over values or a
/// serializer, so the whole surface is provable with a SCRIPTED harness
/// status — no dolt server, no epoch claim, no station.
void main() {
  // The real parser, read off the real command, so a flag that stopped being
  // declared on `up` fails here rather than in production.
  ArgResults parse(List<String> args) => UpCommand().argParser.parse([
    '--grid-home',
    '/home/memento/space_station',
    ...args,
  ]);

  TrajectoryHarnessStatus status(
    TrajectoryHarnessMode mode, {
    String? cause,
    int? epoch,
    int appended = 0,
    int deduped = 0,
    int dropped = 0,
    int suppressed = 0,
    int queueDepth = 0,
    int exitJoinGaps = 0,
  }) => TrajectoryHarnessStatus(
    mode: mode,
    cause: cause,
    epoch: epoch,
    appended: appended,
    deduped: deduped,
    dropped: dropped,
    suppressed: suppressed,
    queueDepth: queueDepth,
    exitJoinGaps: exitJoinGaps,
  );

  group('--trajectory is TRI-STATE (§1.3)', () {
    test('the flag is declared on `up`, negatable, and defaults to null — '
        'ABSENT must be a third state, not a silent --no-trajectory', () {
      final option = UpCommand().argParser.options['trajectory'];
      expect(option, isNotNull, reason: '`up` declares --trajectory');
      expect(option!.isFlag, isTrue);
      expect(option.negatable, isTrue, reason: '--no-trajectory must parse');
      expect(option.defaultsTo, isNull, reason: 'absent ≠ false');
    });

    test('ABSENT is auto: the harness arms iff the home is provisioned', () {
      expect(
        trajectoryConfigFrom(parse(const [])).mode,
        TrajectoryConfigMode.auto,
      );
    });

    test('--trajectory is required: a degradation is LOUD, never a boot '
        'failure', () {
      expect(
        trajectoryConfigFrom(parse(const ['--trajectory'])).mode,
        TrajectoryConfigMode.required,
      );
    });

    test('--no-trajectory is disabled: no connection, no epoch claim', () {
      expect(
        trajectoryConfigFrom(parse(const ['--no-trajectory'])).mode,
        TrajectoryConfigMode.disabled,
      );
    });

    test('the flag carries the MODE only — the Stage-0 cadence dials keep '
        'their assembly defaults on every branch', () {
      const defaults = TrajectoryConfig();
      for (final args in const [
        <String>[],
        ['--trajectory'],
        ['--no-trajectory'],
      ]) {
        final config = trajectoryConfigFrom(parse(args));
        expect(config.tickInterval, defaults.tickInterval);
        expect(config.gcInterval, defaults.gcInterval);
        expect(config.commitCadence, defaults.commitCadence);
        expect(config.queueBound, defaults.queueBound);
        expect(config.shutdownDrainTimeout, defaults.shutdownDrainTimeout);
      }
    });
  });

  group('the dry-run force composes (§1.3: a dry arm claims no epoch)', () {
    test('`up` still defaults to --dry-run, so the assembly force is the '
        'DEFAULT path — the runner never re-implements it', () {
      expect(parse(const []).flag('dry-run'), isTrue);
    });

    test('the runner does NOT pre-force: --trajectory under the default dry '
        'arm still hands the assembly `required`, and the assembly is what '
        'disables it', () {
      final args = parse(const ['--trajectory']);
      expect(args.flag('dry-run'), isTrue);
      final config = trajectoryConfigFrom(args);
      expect(config.mode, TrajectoryConfigMode.required);
      // `assembleStationWork` applies exactly this when dryRun is set.
      expect(config.asDisabled.mode, TrajectoryConfigMode.disabled);
    });

    test('the force keeps every other dial, so a LIVE re-arm of the same '
        'flags is the same config minus the mode', () {
      final config = trajectoryConfigFrom(
        parse(const ['--trajectory', '--no-dry-run']),
      ).asDisabled;
      const defaults = TrajectoryConfig();
      expect(config.tickInterval, defaults.tickInterval);
      expect(config.gcInterval, defaults.gcInterval);
      expect(config.queueBound, defaults.queueBound);
      expect(config.livenessThreshold, defaults.livenessThreshold);
      expect(config.pulseCoalesce, defaults.pulseCoalesce);
    });
  });

  group('the boot banner line (§3 operator surface)', () {
    test('LIVE names the epoch and the divergence counters', () {
      final line = trajectoryBannerLine(
        status(
          TrajectoryHarnessMode.live,
          epoch: 7,
          appended: 42,
          deduped: 3,
          dropped: 1,
          queueDepth: 12,
        ),
      );
      expect(line, contains('trajectory: LIVE'));
      expect(line, contains('epoch 7'));
      expect(line, contains('appended 42'));
      expect(line, contains('deduped 3'));
      expect(line, contains('dropped 1'));
      expect(line, contains('queue 12'));
    });

    test('every non-live posture says legacy-only AND that the window is not '
        'counting — the two facts an operator must not misread', () {
      for (final mode in TrajectoryHarnessMode.values) {
        if (mode == TrajectoryHarnessMode.live) continue;
        final line = trajectoryBannerLine(status(mode, cause: 'the cause'));
        expect(
          line,
          contains('running legacy-only'),
          reason: '${mode.name} must say the station still runs',
        );
        expect(
          line,
          contains('shadow window not counting'),
          reason: '${mode.name} must say the window is not counting',
        );
        expect(line, contains('the cause'), reason: '${mode.name} names why');
      }
    });

    test('each posture renders its own word', () {
      String lineFor(TrajectoryHarnessMode mode) =>
          trajectoryBannerLine(status(mode, cause: 'why'));
      expect(lineFor(TrajectoryHarnessMode.disabled), contains('DISABLED'));
      expect(lineFor(TrajectoryHarnessMode.unprovisioned), contains('INERT'));
      expect(lineFor(TrajectoryHarnessMode.down), contains('DOWN'));
      expect(lineFor(TrajectoryHarnessMode.degraded), contains('DEGRADED'));
      expect(lineFor(TrajectoryHarnessMode.fencedOut), contains('FENCED-OUT'));
      expect(lineFor(TrajectoryHarnessMode.halted), contains('HALTED'));
    });

    test('DEGRADED surfaces the drop count inline (§3: a dropped append '
        'disqualifies the round)', () {
      expect(
        trajectoryBannerLine(
          status(TrajectoryHarnessMode.degraded, cause: 'socket', dropped: 9),
        ),
        contains('dropped 9'),
      );
    });

    test('a HALTED harness with no recorded cause still renders', () {
      final line = trajectoryBannerLine(status(TrajectoryHarnessMode.halted));
      expect(line, contains('HALTED'));
      expect(line, contains('presumed damaged'));
    });

    test('a DRY arm names the dry run as the cause — the assembly force reads '
        '`disabled by config`, which would look like a flag the operator '
        'never passed', () {
      final line = trajectoryBannerLine(
        status(TrajectoryHarnessMode.disabled, cause: 'disabled by config'),
        dryRun: true,
      );
      expect(line, contains('DISABLED'));
      expect(line, contains('dry arm'));
      expect(line, contains('claims no epoch'));
      expect(line, isNot(contains('disabled by config')));
    });

    test('a LIVE arm with --no-trajectory keeps the config cause', () {
      expect(
        trajectoryBannerLine(
          status(TrajectoryHarnessMode.disabled, cause: 'disabled by config'),
        ),
        contains('disabled by config'),
      );
    });
  });

  group('the /status trajectory block', () {
    test('it is a TOP-LEVEL peer of work/wedge — never smuggled into sync', () {
      final json = _status(
        status(TrajectoryHarnessMode.live, epoch: 2, appended: 5),
      ).toJson();
      expect(json.keys, contains('trajectory'));
      expect(
        (json['sync'] as Map<String, Object?>?)?.keys ?? const <String>[],
        isNot(contains('trajectory')),
      );
    });

    test('the base StationStatus wire shape is preserved exactly', () {
      final json = _status(status(TrajectoryHarnessMode.disabled)).toJson();
      expect(json.keys, containsAll(['station', 'process', 'work', 'wedge']));
      expect((json['work']! as Map<String, Object?>)['ready'], 3);
      expect((json['station']! as Map<String, Object?>)['dryRun'], isTrue);
    });

    test('LIVE reads armed, with the epoch, the queue depth, and every '
        'counter the cut criterion is scored on', () {
      final block =
          _status(
                status(
                  TrajectoryHarnessMode.live,
                  epoch: 4,
                  appended: 11,
                  deduped: 2,
                  dropped: 0,
                  suppressed: 1,
                  queueDepth: 6,
                  exitJoinGaps: 2,
                ),
              ).toJson()['trajectory']!
              as Map<String, Object?>;
      expect(block['mode'], 'live');
      expect(block['armed'], isTrue);
      expect(block['cause'], isNull);
      expect(block['epoch'], 4);
      expect(block['queueDepth'], 6);
      expect(block['appended'], 11);
      expect(block['deduped'], 2);
      expect(block['dropped'], 0);
      expect(block['suppressed'], 1);
      expect(block['exitJoinGaps'], 2);
    });

    test('every non-live posture reads NOT armed and carries its cause', () {
      for (final mode in TrajectoryHarnessMode.values) {
        if (mode == TrajectoryHarnessMode.live) continue;
        final block = trajectoryStatusJson(
          status(mode, cause: 'why ${mode.name}'),
        );
        expect(block['armed'], isFalse, reason: mode.name);
        expect(block['mode'], mode.name);
        expect(block['cause'], 'why ${mode.name}');
      }
    });

    test('the block keeps the harness vocabulary — no second mode set', () {
      for (final mode in TrajectoryHarnessMode.values) {
        expect(trajectoryStatusJson(status(mode))['mode'], mode.name);
      }
    });
  });
}

/// A `/status` snapshot with scripted station counts, so the tests read the
/// trajectory block through the SAME serializer `up`'s view hands
/// StationControl.
SpaceStationStatus _status(TrajectoryHarnessStatus trajectory) =>
    SpaceStationStatus(
      trajectory: trajectory,
      substation: 'space_station',
      stateStore: '/home/memento/space_station',
      workRoot: 'space_station=/home/memento/space_station',
      dryRun: true,
      pid: 4242,
      startedAt: DateTime.utc(2026, 8, 31),
      version: '3.11.0',
      ready: 3,
      mounted: 1,
      liveSessions: 1,
      lastSyncAt: null,
    );
