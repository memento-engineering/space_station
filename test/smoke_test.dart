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
        'run',
        'dart',
        'gate',
        'demo',
        'serve',
        'lease',
      ]),
    );
  });
}
