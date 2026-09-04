import 'package:grid_assets/grid_assets.dart'
    show
        ApproveCommand,
        FilingCommand,
        PrimeCommand,
        SearchCommand,
        SeatCommand;
import 'package:grid_cli/grid_cli.dart' show LinkCommand, UnlinkCommand;
// ignore: implementation_imports
import 'package:grid_cli/src/reload_command.dart' show ReloadCommand;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

void main() {
  test('buildRunner assembles the expected station commands', () {
    final runner = buildRunner();
    expect(runner.executableName, 'space');
    expect(runner.description, "memento's grid station");
    expect(
      runner.commands.keys,
      containsAll(<String>[
        'watch',
        'up',
        'down',
        'status',
        'reload',
        'search',
        'filing',
        'approve',
        'prime',
        'seat',
        'link',
        'unlink',
        'dart',
        'gate',
        'serve',
        'lease',
      ]),
    );
    expect(runner.commands['demo'], isNull);
  });

  test('`link` and `unlink` are the VENDED grid_cli commands', () {
    final runner = buildRunner();
    expect(runner.commands['link'], isA<LinkCommand>());
    expect(runner.commands['unlink'], isA<UnlinkCommand>());
  });

  test('`search` is the VENDED grid_assets Command, composed — not a '
      'space-local reimplementation (the asset owns the logic)', () {
    expect(buildRunner().commands['search'], isA<SearchCommand>());
  });

  test('`filing` and `approve` are the VENDED grid_assets Commands, composed '
      '— not space-local reimplementations (the asset owns the logic)', () {
    final runner = buildRunner();
    expect(runner.commands['filing'], isA<FilingCommand>());
    expect(runner.commands['approve'], isA<ApproveCommand>());
  });

  test('prime and seat are the VENDED grid_assets Commands, composed — not '
      'space-local reimplementations', () {
    final runner = buildRunner();
    expect(runner.commands['prime'], isA<PrimeCommand>());
    expect(runner.commands['seat'], isA<SeatCommand>());
  });

  test('`reload` is the VENDED grid_cli Command, composed — the operator\'s '
      'EXPLICIT hot-reload trigger, not a space-local reimplementation', () {
    expect(buildRunner().commands['reload'], isA<ReloadCommand>());
  });
}
