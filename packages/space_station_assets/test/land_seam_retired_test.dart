// The station-level land ARMING SEAM is retired in space too.
//
// the_grid's route unification (ADR-0000 A51 / M5 D-4a) DELETED grid_sdk's
// `buildLandOps(armed:)`: landing is no longer a station-wide boolean threaded
// into every substation — a substation BINDS a `DeliveryMethod` on its
// `ServiceBundle`, and binding NONE is the commit-only posture. space's runner
// therefore names NO land flag and NO land factory: `up` hands the real
// delivery halves (`GitOps` + `PrOpener`) to the imported GitHub asset on
// a LIVE arm, and NOTHING on a dry run.
//
// This mirrors grid_sdk's own `land_seam_retired_test.dart` one repo down: if
// either token reappears under `lib/`, the flag came back.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('space names no land arming seam under lib/', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'sanity: the lib dir was found');

    final dartFiles = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(dartFiles, isNotEmpty, reason: 'sanity: the sources were found');

    // `buildLandOps` — the DELETED grid_sdk factory. The quoted flag NAME —
    // catches both its `addFlag` declaration and every `results.flag(…)` read.
    const retired = <String>['buildLandOps', "'land'"];
    final hits = <String>[
      for (final f in dartFiles)
        for (final token in retired)
          if (f.readAsStringSync().contains(token)) '${f.path}: $token',
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'the station-level land arming seam is retired: delivery is a '
          'per-substation binding on the ServiceBundle, not a boolean flag '
          '(the_grid ADR-0000 A51):\n  ${hits.join('\n  ')}',
    );
  });
}
