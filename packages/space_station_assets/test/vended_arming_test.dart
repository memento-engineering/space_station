import 'dart:io';

import 'package:grid_assets/grid_assets.dart' as ga;
import 'package:space_station_assets/space_station_assets.dart'
    show CriticSeatProvider, SeatEnvironments, SeatPreference, SeatProvider;
import 'package:test/test.dart';

/// The open-seat mechanism is the framework's. Space vends the upstream
/// declarations unchanged and owns only its ordered posture values.
void main() {
  test('the four open-seat names ARE grid_assets declarations', () {
    const upstreamBuild = ga.BuildAgentEnvironment([]);
    expect(upstreamBuild, isA<SeatPreference>());

    const provider = SeatProvider<ga.BuildAgentEnvironment>(upstreamBuild);
    expect(provider, isA<ga.SeatProvider<ga.BuildAgentEnvironment>>());
    expect(
      const ga.SeatProvider<ga.BuildAgentEnvironment>(upstreamBuild),
      isA<SeatProvider<ga.BuildAgentEnvironment>>(),
    );

    const upstreamCritic = ga.CriticAgentEnvironment([]);
    const criticProvider = CriticSeatProvider(upstreamCritic);
    expect(criticProvider, isA<ga.CriticSeatProvider>());
    expect(
      const ga.CriticSeatProvider(upstreamCritic),
      isA<CriticSeatProvider>(),
    );

    expect(const SeatEnvironments(), isA<ga.SeatEnvironments>());
    expect(const ga.SeatEnvironments(), isA<SeatEnvironments>());
  });

  test(
    'space declares none of the open-seat or retired shim types under lib/',
    () {
      final lib = Directory('lib');
      expect(lib.existsSync(), isTrue, reason: 'sanity: the lib dir was found');

      final dartFiles = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(dartFiles, isNotEmpty, reason: 'sanity: the sources were found');

      const declarations = <String>[
        'class SeatPreference',
        'class SeatProvider',
        'class CriticSeatProvider',
        'class SeatEnvironments',
        'class AgentArming',
        'class TypedEnvironmentProvider',
      ];
      final hits = <String>[
        for (final file in dartFiles)
          for (final declaration in declarations)
            if (file.readAsStringSync().contains(declaration))
              '${file.path}: $declaration',
      ];
      expect(
        hits,
        isEmpty,
        reason:
            'the open-seat mechanism is vended by grid_assets, never declared '
            'locally:\n  ${hits.join('\n  ')}',
      );
    },
  );

  test(
    'the open-seat release is hosted and compatibility exports are absent',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final barrel = File('lib/space_station_assets.dart').readAsStringSync();

      expect(
        pubspec,
        matches(RegExp(r'^  grid_assets: \^0\.7\.0-dev\.1$', multiLine: true)),
      );
      expect(
        pubspec,
        isNot(matches(RegExp(r'grid_assets:\s*(?:\n\s+)?(?:git|path):'))),
      );
      expect(barrel, isNot(contains('AgentArming,')));
      expect(barrel, isNot(contains('TypedEnvironmentProvider')));
      for (final name in const <String>[
        'SeatPreference',
        'SeatProvider',
        'CriticSeatProvider',
        'SeatEnvironments',
      ]) {
        expect(barrel, contains(name), reason: name);
      }
    },
  );
}
