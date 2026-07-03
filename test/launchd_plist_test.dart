import 'dart:io';

import 'package:test/test.dart';

/// RS-6: the launchd recipe is a template + runbook, not lib code — its one
/// checkable acceptance criterion is that `plutil -lint` accepts it. `plutil`
/// is a macOS-only tool (as is launchd itself, the thing this template is
/// for), so this test skips rather than fails when it's unavailable (e.g. CI
/// on a non-Darwin host) — the runbook documents the same lint step for a
/// human running it by hand.
void main() {
  test('tool/launchd/engineering.memento.space.plist passes plutil -lint', () {
    final plutil = Process.runSync('which', ['plutil']);
    if (plutil.exitCode != 0) {
      markTestSkipped('plutil not on PATH (non-macOS host)');
      return;
    }

    final plist = File(
      '${Directory.current.path}/tool/launchd/engineering.memento.space.plist',
    );
    expect(plist.existsSync(), isTrue, reason: '${plist.path} is missing');

    final result = Process.runSync('plutil', ['-lint', plist.path]);
    expect(
      result.exitCode,
      0,
      reason: 'plutil -lint failed:\n${result.stdout}\n${result.stderr}',
    );
  });
}
