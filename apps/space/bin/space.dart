import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:space_station_assets/space_station_assets.dart';

// memento's grid station: a user-composed runner (the Dart runner model —
// see the_grid docs/SCRATCH-dart-runner-and-cli-sdk.md). The assembly lives
// in space_station_assets (buildRunner) so it is constructible — and
// EXTENDABLE by a downstream station — without running; this bin just drives
// it. JIT only — `dart run space:space` from the workspace root (never a
// compiled binary; see CLAUDE.md).
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
