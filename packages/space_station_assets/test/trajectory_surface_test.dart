import 'package:args/args.dart';
import 'package:grid_engine/grid_engine.dart' show DualReadMode;
import 'package:grid_sdk/grid_sdk.dart'
    show
        TrajectoryConfig,
        TrajectoryConfigMode,
        TrajectoryHarnessMode,
        TrajectoryHarnessStatus,
        kNotWedged;
import 'package:space_station_assets/src/trajectory_surface.dart';
import 'package:space_station_assets/src/up_command.dart' show UpCommand;
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

  group('the dual-read posture is FED, never sniffed', () {
    test(
      'an unfed runner arms off — the default posture needs no environment',
      () {
        expect(
          trajectoryConfigFrom(parse(const [])).dualRead,
          DualReadMode.off,
        );
      },
    );

    test('GRID_DUAL_READ names the posture when the entrypoint feeds it', () {
      for (final (value, expected) in const [
        ('observe', DualReadMode.observe),
        ('primary', DualReadMode.primary),
        ('off', DualReadMode.off),
      ]) {
        expect(
          trajectoryConfigFrom(
            parse(const []),
            environment: {'GRID_DUAL_READ': value},
          ).dualRead,
          expected,
          reason: 'GRID_DUAL_READ=$value',
        );
      }
    });

    test('an unrecognized value is off, never a boot failure', () {
      expect(
        trajectoryConfigFrom(
          parse(const []),
          environment: const {'GRID_DUAL_READ': 'shadow'},
        ).dualRead,
        DualReadMode.off,
      );
    });

    test('the posture rides every --trajectory branch', () {
      for (final args in const [
        <String>[],
        ['--trajectory'],
        ['--no-trajectory'],
      ]) {
        expect(
          trajectoryConfigFrom(
            parse(args),
            environment: const {'GRID_DUAL_READ': 'observe'},
          ).dualRead,
          DualReadMode.observe,
        );
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
          suppressed: 4,
          queueDepth: 12,
        ),
      );
      expect(line, contains('trajectory: LIVE'));
      expect(line, contains('epoch 7'));
      expect(line, contains('appended 42'));
      expect(line, contains('deduped 3'));
      expect(line, contains('dropped 1  ·  suppressed 4  ·  queue 12'));
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
      expect(
        lineFor(TrajectoryHarnessMode.unprovisioned),
        contains('UNPROVISIONED'),
      );
      expect(lineFor(TrajectoryHarnessMode.down), contains('DOWN'));
      expect(lineFor(TrajectoryHarnessMode.degraded), contains('DEGRADED'));
      expect(lineFor(TrajectoryHarnessMode.fencedOut), contains('FENCED-OUT'));
      expect(lineFor(TrajectoryHarnessMode.halted), contains('HALTED'));
    });

    test('the banner keeps the HARNESS vocabulary — it never invents a word '
        'the wire, the enum, and the design doc do not share', () {
      for (final mode in TrajectoryHarnessMode.values) {
        final word = trajectoryPostureWord(mode.name);
        expect(
          trajectoryBannerLine(status(mode, cause: 'why')),
          contains('trajectory: $word'),
          reason: mode.name,
        );
        // The word is the mode's own name, modulo case and the one
        // hyphenation §3 itself writes.
        expect(
          word.replaceAll('-', '').toLowerCase(),
          mode.name.toLowerCase(),
          reason: '${mode.name} must not render as a second vocabulary',
        );
      }
    });

    test('INERT is gone: an unprovisioned home renders the mode the harness '
        'and the wire both name', () {
      final line = trajectoryBannerLine(
        status(TrajectoryHarnessMode.unprovisioned, cause: 'no secret'),
      );
      expect(line, contains('UNPROVISIONED'));
      expect(line, isNot(contains('INERT')));
      // The cause stays a PARENTHETICAL suffix, never the posture word.
      expect(line, contains('(no secret)'));
    });

    test('DEGRADED surfaces dropped and suppressed counts before its '
        'legacy-only clause', () {
      expect(
        trajectoryBannerLine(
          status(
            TrajectoryHarnessMode.degraded,
            cause: 'socket',
            dropped: 9,
            suppressed: 6,
          ),
        ),
        contains('dropped 9  ·  suppressed 6 — running legacy-only'),
      );
    });

    test('a HALTED harness with no recorded cause still renders', () {
      final line = trajectoryBannerLine(status(TrajectoryHarnessMode.halted));
      expect(line, contains('HALTED'));
      expect(line, contains('presumed damaged'));
    });

    test('an IMPLICIT dry-run force names the dry run as the cause — the '
        'assembly force reads `disabled by config`, which would look like a '
        'flag the operator never passed', () {
      for (final requested in const [
        TrajectoryConfigMode.auto,
        TrajectoryConfigMode.required,
      ]) {
        final line = trajectoryBannerLine(
          status(TrajectoryHarnessMode.disabled, cause: 'disabled by config'),
          dryRun: true,
          requested: requested,
        );
        expect(line, contains('DISABLED'), reason: requested.name);
        expect(line, contains('dry arm'), reason: requested.name);
        expect(line, contains('claims no epoch'), reason: requested.name);
        expect(
          line,
          isNot(contains('disabled by config')),
          reason: requested.name,
        );
      }
    });

    test('an EXPLICIT --no-trajectory under the default dry run renders the '
        "OPERATOR's choice, not `dry arm` — both are true, and reporting only "
        'the dry run hides the choice that was actually made', () {
      final line = trajectoryBannerLine(
        status(TrajectoryHarnessMode.disabled, cause: 'disabled by config'),
        dryRun: true,
        requested: TrajectoryConfigMode.disabled,
      );
      expect(line, contains('DISABLED (--no-trajectory'));
      // The dry run is still named — as a secondary clause, not the cause.
      expect(line, contains('also a dry arm'));
      expect(line.indexOf('--no-trajectory'), lessThan(line.indexOf('dry')));
    });

    test('a LIVE arm with --no-trajectory names the flag and nothing about a '
        'dry run', () {
      final line = trajectoryBannerLine(
        status(TrajectoryHarnessMode.disabled, cause: 'disabled by config'),
        requested: TrajectoryConfigMode.disabled,
      );
      expect(line, contains('--no-trajectory'));
      expect(line, isNot(contains('dry')));
    });

    test('a disabled posture the operator did NOT request keeps the harness '
        'cause verbatim', () {
      expect(
        trajectoryBannerLine(
          status(TrajectoryHarnessMode.disabled, cause: 'disabled by config'),
        ),
        contains('disabled by config'),
      );
    });
  });

  group("required mode's LOUD warning (§1.3)", () {
    test('every degraded posture under --trajectory warns, and it names the '
        'posture, the cause, and that no round can be scored', () {
      for (final mode in TrajectoryHarnessMode.values) {
        if (mode == TrajectoryHarnessMode.live) continue;
        if (mode == TrajectoryHarnessMode.disabled) continue;
        final warning = trajectoryRequiredWarning(
          status(mode, cause: 'why ${mode.name}'),
          requested: TrajectoryConfigMode.required,
        );
        expect(warning, isNotNull, reason: mode.name);
        expect(warning, contains('WARNING'), reason: mode.name);
        expect(warning, contains('REQUIRED'), reason: mode.name);
        expect(
          warning,
          contains(trajectoryPostureWord(mode.name)),
          reason: mode.name,
        );
        expect(warning, contains('why ${mode.name}'), reason: mode.name);
        expect(warning, contains('NOT counting'), reason: mode.name);
      }
    });

    test('a LIVE harness under --trajectory is silent — the flag got what it '
        'asked for', () {
      expect(
        trajectoryRequiredWarning(
          status(TrajectoryHarnessMode.live, epoch: 3),
          requested: TrajectoryConfigMode.required,
        ),
        isNull,
      );
    });

    test("the dry-run force is NOT a degradation — it is the operator's own "
        'instruction (§1.3), so `--trajectory --dry-run` does not warn', () {
      expect(
        trajectoryRequiredWarning(
          status(TrajectoryHarnessMode.disabled, cause: 'disabled by config'),
          requested: TrajectoryConfigMode.required,
        ),
        isNull,
      );
    });

    test('auto and disabled never warn — §1.3 designs auto to be a one-line '
        'notice, NOT a warning storm', () {
      for (final requested in const [
        TrajectoryConfigMode.auto,
        TrajectoryConfigMode.disabled,
      ]) {
        for (final mode in TrajectoryHarnessMode.values) {
          expect(
            trajectoryRequiredWarning(
              status(mode, cause: 'why'),
              requested: requested,
            ),
            isNull,
            reason: '${requested.name}/${mode.name}',
          );
        }
      }
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

    test('the forwarding constructor reaches EVERY base field — a base '
        'parameter this subclass forgets is unreachable, silently', () {
      final json = SpaceStationStatus(
        trajectory: status(TrajectoryHarnessMode.live, epoch: 1),
        substation: 'space_station',
        stateStore: '/home/memento/space_station',
        workRoot: 'space_station=/home/memento/space_station',
        dryRun: false,
        pid: 4242,
        startedAt: DateTime.utc(2026, 8, 31),
        version: '3.11.0',
        ready: 3,
        mounted: 1,
        liveSessions: 1,
        lastSyncAt: null,
        perSubstation: const [],
        wedge: kNotWedged,
        sync: const {'stats': <String, Object?>{}},
      ).toJson();
      expect(json.keys, contains('trajectory'));
      expect(json.keys, contains('wedge'));
    });
  });

  group('`status` renders the block (§3: loud on every status read)', () {
    Map<String, Object?> payload(TrajectoryHarnessStatus s) =>
        <String, Object?>{
          'station': <String, Object?>{'dryRun': false},
          'trajectory': trajectoryStatusJson(s),
        };

    test('an ABSENT block renders nothing and does not throw — an older '
        'producer, or a station booted before chunk WS', () {
      expect(
        trajectoryStatusLine(<String, Object?>{
          'station': <String, Object?>{'dryRun': true},
        }),
        isNull,
      );
      expect(trajectoryStatusLine(const <String, Object?>{}), isNull);
      // A malformed block is absence, never a crash on the operator's only
      // read of the station.
      expect(
        trajectoryStatusLine(<String, Object?>{'trajectory': 'nonsense'}),
        isNull,
      );
    });

    test('a clean LIVE harness renders ONE quiet line carrying every counter '
        'the cut criterion is scored on', () {
      final rendered = trajectoryStatusLine(
        payload(
          status(
            TrajectoryHarnessMode.live,
            epoch: 4,
            appended: 118,
            queueDepth: 2,
          ),
        ),
      );
      expect(rendered, isNotNull);
      expect(rendered!.loud, isFalse);
      expect(rendered.line, startsWith('trajectory: LIVE'));
      expect(rendered.line, contains('armed'));
      expect(rendered.line, contains('epoch 4'));
      expect(rendered.line, contains('queue 2'));
      expect(rendered.line, contains('appended 118'));
      expect(rendered.line, contains('dropped 0  ·  suppressed 0'));
      expect(rendered.line, isNot(startsWith('!!')));
    });

    test('DISABLED renders ONE quiet line — a flag the operator passed is not '
        'an alarm', () {
      final rendered = trajectoryStatusLine(
        payload(
          status(TrajectoryHarnessMode.disabled, cause: 'disabled by config'),
        ),
      )!;
      expect(rendered.loud, isFalse);
      expect(rendered.line, contains('DISABLED'));
      expect(rendered.line, contains('not armed'));
      expect(rendered.line, contains('disabled by config'));
      expect(rendered.line, isNot(startsWith('!!')));
    });

    test('UNPROVISIONED stays quiet too — §1.3: a one-line notice, NOT a '
        'warning storm', () {
      expect(
        trajectoryStatusLine(
          payload(
            status(TrajectoryHarnessMode.unprovisioned, cause: 'no secret'),
          ),
        )!.loud,
        isFalse,
      );
    });

    test('every posture that can latch AFTER boot renders LOUD — the banner '
        'fired once and the harness flared once, so this read is the only '
        'thing that repeats', () {
      for (final mode in const [
        TrajectoryHarnessMode.halted,
        TrajectoryHarnessMode.fencedOut,
        TrajectoryHarnessMode.degraded,
        TrajectoryHarnessMode.down,
      ]) {
        final rendered = trajectoryStatusLine(
          payload(status(mode, cause: 'why ${mode.name}')),
        )!;
        expect(rendered.loud, isTrue, reason: mode.name);
        expect(rendered.line, startsWith('!! trajectory: '), reason: mode.name);
        expect(
          rendered.line,
          contains(trajectoryPostureWord(mode.name)),
          reason: mode.name,
        );
        expect(rendered.line, contains('why ${mode.name}'), reason: mode.name);
        expect(rendered.line, contains('legacy-only'), reason: mode.name);
      }
    });

    test('HALTED matches §3 verbatim: `trajectory: HALTED — <reason>`', () {
      expect(
        trajectoryStatusLine(
          payload(
            status(TrajectoryHarnessMode.halted, cause: 'belt seq 42 skipped'),
          ),
        )!.line,
        contains('trajectory: HALTED — belt seq 42 skipped'),
      );
    });

    test('a LIVE harness with ANY dropped append is LOUD — §3: a round with a '
        'dropped append cannot count as a clean round', () {
      final rendered = trajectoryStatusLine(
        payload(
          status(
            TrajectoryHarnessMode.live,
            epoch: 4,
            appended: 90,
            dropped: 7,
          ),
        ),
      )!;
      expect(rendered.loud, isTrue);
      expect(rendered.line, startsWith('!!'));
      expect(rendered.line, contains('7 dropped append'));
      expect(rendered.line, contains('clean round'));
    });

    test('a LIVE harness with ANY suppressed append is LOUD and cannot count '
        'as a clean round', () {
      final rendered = trajectoryStatusLine(
        payload(
          status(
            TrajectoryHarnessMode.live,
            epoch: 4,
            appended: 90,
            suppressed: 7,
          ),
        ),
      )!;
      expect(rendered.loud, isTrue);
      expect(rendered.line, startsWith('!!'));
      expect(rendered.line, contains('dropped 0  ·  suppressed 7'));
      expect(
        rendered.line,
        contains(
          '7 suppressed append(s) — a round with any suppressed append '
          'cannot count as a clean round',
        ),
      );
    });

    test('DEGRADED renders dropped then suppressed and explains suppression '
        'while remaining LOUD', () {
      final rendered = trajectoryStatusLine(
        payload(
          status(
            TrajectoryHarnessMode.degraded,
            cause: 'socket',
            dropped: 9,
            suppressed: 6,
          ),
        ),
      )!;
      expect(rendered.loud, isTrue);
      expect(rendered.line, startsWith('!! trajectory: DEGRADED'));
      expect(rendered.line, contains('dropped 9  ·  suppressed 6'));
      expect(
        rendered.line,
        contains(
          '6 suppressed append(s) — a round with any suppressed append '
          'cannot count as a clean round',
        ),
      );
    });

    test('a LIVE harness with an exit-join gap is LOUD, the same '
        'disqualification', () {
      final rendered = trajectoryStatusLine(
        payload(status(TrajectoryHarnessMode.live, epoch: 4, exitJoinGaps: 3)),
      )!;
      expect(rendered.loud, isTrue);
      expect(rendered.line, contains('3 exit-join gap'));
    });

    test('the render keeps the harness vocabulary — no third word set across '
        'banner, wire, and status', () {
      for (final mode in TrajectoryHarnessMode.values) {
        expect(
          trajectoryStatusLine(payload(status(mode, cause: 'why')))!.line,
          contains('trajectory: ${trajectoryPostureWord(mode.name)}'),
          reason: mode.name,
        );
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
