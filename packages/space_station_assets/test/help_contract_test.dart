import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart' show ReadCommand, kDefaultReadCapBytes;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

const _decisionSurface =
    'space_station/packages/space_station_assets/lib/src/up_command.dart';

void main() {
  test('all composed command help is bounded recursively', () {
    final runner = buildRunner();

    for (final command in _allCommands(runner)) {
      expect(
        _cliBytes(command.description),
        lessThanOrEqualTo(kDefaultReadCapBytes),
        reason: '${command.invocation} description exceeds the shared cap',
      );
      expect(
        _cliBytes(command.usage),
        lessThanOrEqualTo(kDefaultReadCapBytes),
        reason: '${command.invocation} help exceeds the shared cap',
      );
    }
  });

  test('up help is compact and rationale-free', () {
    final help = buildRunner().commands['up']!.usage;

    expect(_cliBytes(help), lessThanOrEqualTo(2500));
    for (final rationale in const [
      'authored as a SpaceDelegate',
      'driven with runGrid',
      'v3 stores-at-roots',
      'Track J',
      'stage1-wiring',
      'ADR-0002 D1',
      'tg-42f',
    ]) {
      expect(help, isNot(contains(rationale)));
    }
  });

  test('up help names withheld rationale and lookup', () async {
    final space = buildRunner();
    final spaceHelp = space.commands['up']!.usage;
    expect(space.commands['decisions'], isNull);
    expect(
      spaceHelp,
      contains('This runner does not vend the decision lookup'),
    );
    expect(spaceHelp, isNot(contains('`space decisions index')));

    final lunar = buildRunner(name: 'lunar')
      ..addCommand(_ReachableDecisionsCommand());
    expect(lunar.commands['decisions']!.subcommands, contains('index'));
    expect(
      lunar.commands['up']!.usageFooter,
      'Withheld: design rationale and architecture history. Ask for it with '
      '`lunar decisions index --surface $_decisionSurface`.',
    );
    expect(
      await lunar.run(['decisions', 'index', '--surface', _decisionSurface]),
      0,
      reason: 'the lookup advertised by up help must resolve on the runner',
    );
  });

  test('root help records the byte reduction', () {
    // Base: 3,527 → 2,886 bytes. Measured downstream lunar: 4,587 → 3,946.
    expect(_cliBytes(buildRunner().usage), 2886);
  });

  test('up help retains its operational contract', () {
    final help = buildRunner().commands['up']!.usage;
    final codedNames = codedRosterOf(
      SpaceDelegate.new,
    ).map((substation) => substation.name).join(', ');
    final armedEnvironments = codedArmingOf(
      SpaceDelegate.new,
    ).environments.names.join(', ');

    for (final contract in [
      'safe dry-run is the default',
      'Observe without spawns, writes, or delivery (default)',
      '--no-dry-run arms live work and GitHub delivery',
      'Malformed entries, duplicate names, and coded names ($codedNames) are '
          'refused',
      'Missing and relative paths are refused',
      'Unknown names are refused',
      'Armed names: $armedEnvironments',
      'non-integers are refused',
      'Other values are refused',
      '--trajectory requires it',
      '--no-trajectory disables it',
      'Required-mode connection failure degrades loudly without blocking boot',
      'Withheld: design rationale and architecture history',
      'decisions index --surface $_decisionSurface',
    ]) {
      expect(help, contains(contract), reason: 'missing contract: $contract');
    }
  });

  test('read and search remain the reference shape', () {
    final runner = buildRunner();
    expect(
      runner.commands['read'],
      isNull,
      reason: '`read` is a downstream lunar composition, not a space command',
    );

    final gridReference = CommandRunner<int>('grid', 'reference')
      ..addCommand(ReadCommand());
    expect(_cliBytes(gridReference.commands['read']!.usage), 777);

    // The runner-authored help hint makes lunar's vended form one byte longer.
    final reference = CommandRunner<int>('lunar', 'reference')
      ..addCommand(ReadCommand());
    final read = reference.commands['read']!;
    expect(_cliBytes(read.usage), 778);
    expect(_cliBytes(read.usage), lessThanOrEqualTo(kDefaultReadCapBytes));

    final search = runner.commands['search']!;
    expect(_cliBytes(search.usage), 631);
    expect(_cliBytes(search.usage), lessThanOrEqualTo(kDefaultReadCapBytes));
  });
}

int _cliBytes(String output) => utf8.encode('$output\n').length;

Iterable<Command<int>> _allCommands(CommandRunner<int> runner) sync* {
  final seen = <Command<int>>{};

  Iterable<Command<int>> visit(Command<int> command) sync* {
    if (!seen.add(command)) return;
    yield command;
    for (final child in command.subcommands.values) {
      yield* visit(child);
    }
  }

  for (final command in runner.commands.values) {
    yield* visit(command);
  }
}

final class _ReachableDecisionsCommand extends Command<int> {
  _ReachableDecisionsCommand() {
    addSubcommand(_ReachableIndexCommand());
  }

  @override
  String get name => 'decisions';

  @override
  String get description => 'Test decision-register composition.';
}

final class _ReachableIndexCommand extends Command<int> {
  _ReachableIndexCommand() {
    argParser.addOption('surface');
  }

  @override
  String get name => 'index';

  @override
  String get description => 'Test roster index.';

  @override
  int run() => 0;
}
