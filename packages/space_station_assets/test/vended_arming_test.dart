import 'dart:io';

import 'package:grid_assets/grid_assets.dart' as ga;
import 'package:space_station_assets/space_station_assets.dart'
    show AgentArming, SeatEnvironments, TypedEnvironmentProvider;
import 'package:test/test.dart';

/// The typed-seat arming MECHANISM is the FRAMEWORK's (grid_assets
/// 0.6.0-rc.9, `lib/src/agent/seat_environments.dart`; power_station bead
/// `pow-lb0`) and space vends only its POSTURE.
///
/// Two checks fence that in both directions, and BOTH failure modes are real:
/// this file's own `show` clause is lunar's import shape, so dropping the
/// re-export breaks COMPILATION here; re-exporting a FORK instead compiles but
/// fails the `isA` pair below; and re-declaring one under `lib/` fails the
/// source scan. Nothing here asserts a tautology.
void main() {
  test('the three arming names ARE grid_assets\' declarations', () {
    // Mutually assignable in both directions ⇒ one declaration (Dart is
    // nominally typed, so a fork could satisfy neither).
    expect(const AgentArming(), isA<ga.AgentArming>());
    expect(const ga.AgentArming(), isA<AgentArming>());

    expect(const SeatEnvironments(), isA<ga.SeatEnvironments>());
    expect(const ga.SeatEnvironments(), isA<SeatEnvironments>());

    const provider = TypedEnvironmentProvider(arming: AgentArming());
    expect(provider, isA<ga.TypedEnvironmentProvider>());
    expect(provider.arming, const ga.AgentArming());
  });

  test('space declares none of the three under lib/', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'sanity: the lib dir was found');

    final dartFiles = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(dartFiles, isNotEmpty, reason: 'sanity: the sources were found');

    const retired = <String>[
      'class AgentArming',
      'class TypedEnvironmentProvider',
      'class SeatEnvironments',
    ];
    final hits = <String>[
      for (final f in dartFiles)
        for (final token in retired)
          if (f.readAsStringSync().contains(token)) '${f.path}: $token',
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'the arming MECHANISM is vended by grid_assets and re-exported here, '
          'never re-declared — posture stays, mechanism does not:\n  '
          '${hits.join('\n  ')}',
    );
  });
}
