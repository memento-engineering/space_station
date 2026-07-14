// The dev-mode gate is the RUN MODE, and nothing else.
//
// Two alternatives were REJECTED and are fenced out here: an in-process
// filesystem watcher (an auto-reload-on-save would fire mid-build on a resident
// station that is committing and opening PRs) and any out-of-band gate (a
// hostname allowlist, an env var, a flag, a config key). The trigger is the
// operator typing `space reload`; the gate is `stationVmServiceUri() != null`.
//
// `ProcessSignal.watch()` is NOT a filesystem watcher — it is the station's
// signal lifecycle, and `up` keeps it.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late List<File> sources;

  setUp(() {
    sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(sources, isNotEmpty, reason: 'sanity: the sources were found');
  });

  test('no filesystem watcher and no out-of-band gate under lib/', () {
    const banned = <String>[
      // The REJECTED auto-reload trigger.
      'package:watcher',
      'FileSystemEvent',
      'watchDirectory',
      // The REJECTED out-of-band gates: detection is the run mode ALONE.
      'Platform.environment',
      'Platform.localHostname',
    ];
    final hits = <String>[
      for (final f in sources)
        for (final token in banned)
          if (f.readAsStringSync().contains(token)) '${f.path}: $token',
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'the hot-reload trigger is EXPLICIT (`space reload`) and the dev-mode '
          'gate is the run mode alone:\n  ${hits.join('\n  ')}',
    );
  });

  test('the ONE gate is the VM-service probe (the control that makes the ban '
      'meaningful)', () {
    final up = File('lib/src/up_command.dart').readAsStringSync();
    expect(up, contains('stationVmServiceUri()'));
  });

  test('leonard-attach is NOT in this change (its own bead)', () {
    final hits = [
      for (final f in sources)
        if (f.readAsStringSync().contains('leonard')) f.path,
    ];
    expect(hits, isEmpty);
  });
}
