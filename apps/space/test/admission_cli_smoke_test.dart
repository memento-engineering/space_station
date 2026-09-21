import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('real runner help exposes the admission noun', () async {
    final run = await _runSpace(const <String>['--help']);

    expect(run.exitCode, 0, reason: 'stdout: ${run.stdout}');
    expect('${run.stderr}', isEmpty);
    expect(
      '${run.stdout}',
      matches(
        RegExp(
          r'^  admission\s+Operate the resident admission budget\.$',
          multiLine: true,
        ),
      ),
    );
  });

  test('real admission help exposes only the set verb', () async {
    final run = await _runSpace(const <String>['admission', '--help']);

    expect(run.exitCode, 0, reason: 'stdout: ${run.stdout}');
    expect('${run.stderr}', isEmpty);
    expect(
      '${run.stdout}',
      contains('Usage: space admission <subcommand> [arguments]'),
    );
    expect(
      '${run.stdout}',
      matches(
        RegExp(
          r'^  set\s+Set the live station-wide maximum number of admitted agents\.$',
          multiLine: true,
        ),
      ),
    );
  });
}

Future<ProcessResult> _runSpace(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  <String>['run', 'space:space', ...arguments],
  workingDirectory: Directory.current.path,
);
