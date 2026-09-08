import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart' show StationDiagnosticsReporter;
import 'package:grid_sdk/grid_sdk.dart' show GridHookError;
import 'package:space_station_assets/src/up_command.dart'
    show buildContainedGridHookErrorSink;
import 'package:test/test.dart';

void main() {
  test('contained hook errors emit one bounded flare and one-line summary', () {
    final reporterLines = <String>[];
    final errorLines = <String>[];
    final reporter = StationDiagnosticsReporter(writeLine: reporterLines.add);
    final cause =
        '${List.filled(240, 'a').join()}\r\n'
        '${List.filled(300, 'b').join()}\n'
        '${List.filled(100, 'c').join()}';
    final frames = List.generate(
      10,
      (index) => '#${index + 1} frame ${index + 1}',
    );
    final refusal = GridHookError(
      'onReady',
      _SyntheticDelegate,
      _SyntheticCause(cause),
      StackTrace.fromString(frames.join('\n')),
    );

    try {
      buildContainedGridHookErrorSink(
        diagnostics: reporter,
        writeError: errorLines.add,
        runnerName: 'lunar',
      )(refusal);

      expect(reporterLines, hasLength(1));
      final flare = jsonDecode(reporterLines.single) as Map<String, dynamic>;
      expect(flare['type'], 'flare');
      expect(flare['name'], 'station.errorContained');
      final data = flare['data'] as Map<String, dynamic>;
      expect(data.keys.toSet(), <String>{
        'hook',
        'delegateType',
        'cause',
        'stack',
      });
      expect(data['hook'], 'onReady');
      expect(data['delegateType'], '_SyntheticDelegate');
      final truncatedCause = cause.substring(0, 500);
      expect(data['cause'], truncatedCause);
      expect(data['stack'], frames.take(8).join('\n'));

      expect(errorLines, hasLength(1));
      expect(errorLines.single, isNot(contains(RegExp(r'[\r\n]'))));
      expect(
        errorLines.single,
        'lunar up: contained _SyntheticDelegate.onReady() error — '
        '${truncatedCause.replaceAll(RegExp(r'[\r\n]+'), ' ')}',
      );
    } finally {
      reporter.dispose();
    }
  });

  test('the production runGrid call installs the contained-error sink', () {
    final source = File('lib/src/up_command.dart').readAsStringSync();
    final runGridCalls = RegExp(r'await runGrid\(').allMatches(source);
    expect(runGridCalls, hasLength(1));

    final call = RegExp(
      r'grid = await runGrid\(\s*buildDelegate\(\),(.*?)\n\s*\);',
      dotAll: true,
    ).firstMatch(source);
    expect(call, isNotNull, reason: 'the production runGrid call was found');
    final invocation = call!.group(0)!;
    expect(invocation, contains('onError: buildContainedGridHookErrorSink('));
    expect(invocation, contains('diagnostics: diagnostics'));
    expect(invocation, contains('writeError: err'));
    expect(invocation, contains('runnerName: runnerName'));
  });
}

final class _SyntheticCause {
  const _SyntheticCause(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _SyntheticDelegate {}
