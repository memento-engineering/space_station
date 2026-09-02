import 'dart:io';

import 'package:test/test.dart';

/// ADR-0002 D3, guarded: the inference endpoint is a MACHINE FACT and lives ONLY
/// in the machine-local site binding — never in committed source, never on argv,
/// never in a bead. This scans the whole committed Dart surface of the station,
/// so a url added in a doc comment fails too: cite a repo or a service by NAME
/// here, not by url.
void main() {
  const forbidden = <String>['http://', 'https://', 'localhost', '127.0.0.1'];

  test('no endpoint url appears in the committed Dart source', () {
    final roots = <Directory>[
      Directory('lib'),
      Directory('../../apps/space/bin'),
    ];
    final offences = <String>[];
    for (final root in roots) {
      expect(root.existsSync(), isTrue, reason: root.path);
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final token in forbidden) {
          if (source.contains(token)) offences.add('${entity.path}: $token');
        }
      }
    }
    expect(offences, isEmpty);
  });
}
