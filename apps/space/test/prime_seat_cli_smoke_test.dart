import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

typedef _RunResult = ({int code, String stdout, String stderr});

void main() {
  final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('space-prime-seat-');
  });
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  Future<_RunResult> runPrime(
    String source, {
    Map<String, String> environment = const {},
  }) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'space:space', 'prime', '--hook-json'],
      workingDirectory: repoRoot,
      environment: <String, String>{
        ...Platform.environment,
        'GRID_SEAT': '',
        'GRID_HOME': '',
        ...environment,
      },
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.writeln(
      jsonEncode(<String, String>{
        'hook_event_name': 'SessionStart',
        'source': source,
      }),
    );
    await process.stdin.close();
    return (
      code: await process.exitCode,
      stdout: await stdout,
      stderr: await stderr,
    );
  }

  String contextOf(_RunResult run) {
    expect(run.code, 0, reason: 'stdout: ${run.stdout}\nstderr: ${run.stderr}');
    final hook = jsonDecode(run.stdout.trim()) as Map<String, dynamic>;
    final output = hook['hookSpecificOutput']! as Map<String, dynamic>;
    expect(output['hookEventName'], 'SessionStart');
    return output['additionalContext']! as String;
  }

  void writeHandoff(String fileName, String body, DateTime modified) {
    final file = File(
      p.join(home.path, '.grid', 'seats', 'governor', fileName),
    );
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '---\n'
        'name: ${p.basenameWithoutExtension(fileName)}\n'
        'seat: governor\n'
        'date: 2026-09-04\n'
        'kind: handoff\n'
        '---\n'
        '$body\n',
      )
      ..setLastModifiedSync(modified);
  }

  test(
    'real dart run space:space prime answers SessionStart: startup, clear and '
    'compact inject the newest handoff; resume is bd-only',
    () async {
      writeHandoff('older.md', 'OLDER HANDOFF', DateTime.utc(2026, 9, 4, 10));
      writeHandoff('newest.md', 'NEWEST HANDOFF', DateTime.utc(2026, 9, 4, 11));
      final bdOnly = contextOf(await runPrime('resume'));

      for (final source in const ['startup', 'clear', 'compact']) {
        final injected = contextOf(
          await runPrime(
            source,
            environment: {'GRID_SEAT': 'governor', 'GRID_HOME': home.path},
          ),
        );
        expect(injected, startsWith(bdOnly), reason: source);
        expect(
          injected,
          contains(
            'Handoff ${p.join('.grid', 'seats', 'governor', 'newest.md')}',
          ),
          reason: source,
        );
        expect(injected, contains('NEWEST HANDOFF'), reason: source);
        expect(injected, isNot(contains('OLDER HANDOFF')), reason: source);
      }

      final resumed = contextOf(
        await runPrime(
          'resume',
          environment: {'GRID_SEAT': 'governor', 'GRID_HOME': home.path},
        ),
      );
      expect(resumed, bdOnly);
      expect(resumed, isNot(contains('NEWEST HANDOFF')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'space seat governor refuses loudly when its role definition is absent',
    () async {
      final run = await Process.run(Platform.resolvedExecutable, [
        'run',
        'space:space',
        'seat',
        'governor',
        '--once',
        '--grid-home',
        home.path,
      ], workingDirectory: repoRoot);

      expect(
        run.exitCode,
        1,
        reason: 'stdout: ${run.stdout}\nstderr: ${run.stderr}',
      );
      expect(
        '${run.stderr}',
        contains(
          'seat: "governor" has no role definition at '
          '${p.join(home.path, '.claude', 'agents', 'governor.md')}',
        ),
      );
      expect(
        Directory(p.join(home.path, '.grid', 'seats', 'governor')).existsSync(),
        isFalse,
        reason: 'the refusal happens before disc creation or harness launch',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
