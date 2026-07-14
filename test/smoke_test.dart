import 'package:grid_assets/grid_assets.dart' show SearchCommand;
import 'package:space_station/space_station.dart';
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
        'search',
        'dart',
        'gate',
        'demo',
        'serve',
        'lease',
      ]),
    );
  });

  test('`search` is the VENDED grid_assets Command, composed — not a '
      'space-local reimplementation (the asset owns the logic)', () {
    expect(buildRunner().commands['search'], isA<SearchCommand>());
  });
}
