import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// `space up`'s flag surgery (power_station ADR-0002 D4): six operator knobs
/// DELETED, one `--env` added. Parser-shape coverage — the process-level lane
/// (`apps/space/test/up_command_validation_test.dart`) proves the LOUD
/// refusal; this proves the thing a refusal cannot show, that `--env`'s
/// allowed set is the ARMED REGISTRY rather than a literal list.
void main() {
  /// The six knobs D4 deletes: the two machine-fact endpoints, the two model
  /// rungs, and the two harness allowlists.
  const deleted = <String>[
    'openai-base',
    'swift-base',
    'model',
    'grader-model',
    'harness',
    'build-harness',
  ];

  test('every deleted operator knob is GONE from the parser', () {
    final parser = buildRunner().commands['up']!.argParser;
    for (final flag in deleted) {
      expect(parser.options.containsKey(flag), isFalse, reason: flag);
    }
  });

  test('--env names NO literal allowed-set — the allowed set is the armed '
      'registry, resolved at run time', () {
    final env = buildRunner().commands['up']!.argParser.options['env'];
    expect(env, isNotNull, reason: '--env is the one replacement knob');
    expect(
      env!.allowed,
      isNull,
      reason:
          'a hardcoded allowlist is the bug D4 deletes; legality is checked '
          'against the boot registry in UpCommand.run()',
    );
  });

  test('--daemon is the SUPERVISOR knob, not a posture: present, '
      'non-negatable, and off unless typed', () {
    // space-5lh. `up` is foreground-resident by design; `--daemon` hands THIS
    // invocation to launchd instead of running it here. It is deliberately
    // non-negatable — `--no-daemon` would name the default, and the operator
    // surface must not imply a posture axis that does not exist.
    final daemon = buildRunner().commands['up']!.argParser.options['daemon'];
    expect(daemon, isNotNull);
    expect(daemon!.negatable, isFalse);
    expect(daemon.isFlag, isTrue);
    expect(
      buildRunner().commands['up']!.argParser.parse(const []).flag('daemon'),
      isFalse,
      reason: 'the foreground path is unchanged unless --daemon is typed',
    );
  });

  test('--env help renders the ARMED registry, custom names included', () {
    final env = buildRunner().commands['up']!.argParser.options['env']!;
    expect(
      env.help,
      allOf(
        // A CUSTOM memento name: no builtin allowlist could have held it.
        contains('codex-frontier'),
        contains('frontier'),
        contains('cheap'),
        contains('mid'),
      ),
    );
  });
}
