import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:space_station/space_station.dart';

// memento's grid station: a user-composed, AOT-compiled runner (the Dart
// runner model — see the_grid docs/SCRATCH-dart-runner-and-cli-sdk.md).
// The assembly lives in lib/space_station.dart (buildRunner) so it is
// constructible without running; this bin just drives it.
//
//   dart compile exe bin/space.dart -o space
Future<void> main(List<String> arguments) async {
  final runner = buildRunner();
  try {
    final code = await runner.run(arguments);
    if (code != null && code != 0) exitCode = code;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  }
}
