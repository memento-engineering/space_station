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
