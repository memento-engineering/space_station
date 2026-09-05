import 'dart:io';

import 'package:args/command_runner.dart' show CommandRunner;
import 'package:grid_assets/grid_assets.dart'
    show
        GridAssetsPack,
        SubstationFacts,
        SubstationFactsSnapshot,
        SubstationKey,
        resolveGridAssets;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

const _fixtureSubstation = SubstationKey('fixture');

void main() {
  test(
    'buildRunnerComposition exposes the unchanged runner and paired commands',
    () {
      final composition = buildRunnerComposition();
      final expectedCommands = <String>{
        'watch',
        'up',
        'down',
        'status',
        'reload',
        'search',
        'filing',
        'approve',
        'prime',
        'seat',
        'link',
        'unlink',
        'assets',
        'dart',
        'gate',
        'rework',
        'serve',
        'lease',
      };

      expect(composition.assetRegistry.packs, hasLength(1));
      expect(
        composition.assetRegistry.packs.single,
        same(GridAssetsPack.definition),
      );
      expect(_composedCommandNames(composition.runner), expectedCommands);
      expect(_composedCommandNames(buildRunner()), expectedCommands);
    },
  );

  test('paired command names are exact, registered, and unmodifiable', () {
    final composition = buildRunnerComposition();

    expect(composition.pairedCommandNames, <String>{
      'assets',
      'search',
      'filing',
      'approve',
      'link',
      'up',
      'down',
      'status',
    });
    for (final name in composition.pairedCommandNames) {
      expect(composition.runner.commands[name], isNotNull, reason: name);
    }
    expect(
      () => composition.pairedCommandNames.add('watch'),
      throwsUnsupportedError,
    );
  });

  test('reachable baseline skills teach every paired command', () {
    final composition = buildRunnerComposition();
    final reachable = _resolve(composition.assetRegistry);

    expect(
      _teachingCoverageRefusals(
        pairedCommandNames: composition.pairedCommandNames,
        baselineRegistry: composition.assetRegistry,
        reachableDefinitions: reachable,
      ),
      isEmpty,
    );
  });

  test('coverage refuses removed, renamed, and selector-excluded teachers', () {
    final composition = buildRunnerComposition();
    final stationOperations = GridAssetsPack.skillStationOperations;
    final removedRegistry = _registryWithStationOperations();
    final renamedRegistry = _registryWithStationOperations(
      replacement: _copyStationOperations(
        assetKey: sdk.AssetKey(
          package: GridAssetsPack.package,
          kind: sdk.AssetKind.skill,
          id: 'station-operations-renamed',
        ),
      ),
    );
    final selectorExcludedRegistry = _registryWithStationOperations(
      replacement: _copyStationOperations(
        selector: const sdk.RequiresPath('fixture/missing-station-operations'),
      ),
    );

    for (final reachable in <List<sdk.GridAssetDefinition>>[
      _resolve(removedRegistry),
      _resolve(renamedRegistry),
      _resolve(
        selectorExcludedRegistry,
        existingPaths: const <String>['docs/decisions'],
      ),
    ]) {
      expect(
        _teachingCoverageRefusals(
          pairedCommandNames: composition.pairedCommandNames,
          baselineRegistry: composition.assetRegistry,
          reachableDefinitions: reachable,
        ),
        isNotEmpty,
      );
    }

    expect(stationOperations.teaches, <String>['up', 'down', 'status']);
  });

  test('coverage refusal names the command and former canonical skill key', () {
    final composition = buildRunnerComposition();
    final refusals = _teachingCoverageRefusals(
      pairedCommandNames: composition.pairedCommandNames,
      baselineRegistry: composition.assetRegistry,
      reachableDefinitions: _resolve(_registryWithStationOperations()),
    ).join('\n');

    expect(refusals, contains('paired command "up" is untaught'));
    expect(refusals, contains('grid_assets/skill/station-operations'));
  });

  test('package contains no extension root or SKILL.md', () {
    final packageRoot = Directory.current;

    expect(Directory('extension').existsSync(), isFalse);
    final skillFiles = packageRoot
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where(
          (file) => file.path.split(Platform.pathSeparator).last == 'SKILL.md',
        );
    expect(skillFiles, isEmpty);
  });
}

Set<String> _composedCommandNames(CommandRunner<int> runner) =>
    runner.commands.keys.where((name) => name != 'help').toSet();

List<String> _teachingCoverageRefusals({
  required Set<String> pairedCommandNames,
  required sdk.GridAssetRegistry baselineRegistry,
  required Iterable<sdk.GridAssetDefinition> reachableDefinitions,
}) {
  final reachable = reachableDefinitions.toList(growable: false);
  final refusals = <String>[];
  for (final name in pairedCommandNames) {
    final expectedTeacherKeys = baselineRegistry.assets
        .where(
          (definition) =>
              definition.assetKey.kind == sdk.AssetKind.skill &&
              definition.teaches.contains(name),
        )
        .map((definition) => definition.assetKey)
        .toSet();
    final remainsTaught = reachable.any(
      (definition) =>
          expectedTeacherKeys.contains(definition.assetKey) &&
          definition.assetKey.kind == sdk.AssetKind.skill &&
          definition.teaches.contains(name),
    );
    if (remainsTaught) continue;

    final canonicalKeys =
        expectedTeacherKeys.map((key) => key.canonical).toList()..sort();
    refusals.add(
      'paired command "$name" is untaught; expected teaching skill '
      '${canonicalKeys.join(', ')} to remain reachable and declare it',
    );
  }
  return refusals;
}

List<sdk.GridAssetDefinition> _resolve(
  sdk.GridAssetRegistry registry, {
  Iterable<String> existingPaths = const <String>['docs/decisions'],
}) => resolveGridAssets(
  registry: registry,
  snapshot: SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
    _fixtureSubstation: SubstationFacts(
      root: '/fixture/space_station_assets',
      dartPackages: const <String>[GridAssetsPack.package, 'grid_sdk'],
      packageRoots: <String, String>{
        GridAssetsPack.package: '/fixture/grid_assets',
      },
      existingPaths: existingPaths,
    ),
  }),
  substation: _fixtureSubstation,
).definitions;

sdk.GridAssetRegistry _registryWithStationOperations({
  sdk.GridAssetDefinition? replacement,
}) {
  final stationOperationsKey = GridAssetsPack.skillStationOperations.assetKey;
  return sdk.GridAssetRegistry(<sdk.GridAssetPackDefinition>[
    sdk.GridAssetPackDefinition(
      package: GridAssetsPack.package,
      assets: <sdk.GridAssetDefinition>[
        for (final definition in GridAssetsPack.definition.assets)
          if (definition.assetKey != stationOperationsKey)
            definition
          else if (replacement != null)
            replacement,
      ],
    ),
  ]);
}

sdk.GridAssetDefinition _copyStationOperations({
  sdk.AssetKey? assetKey,
  sdk.AssetSelector? selector,
}) {
  final source = GridAssetsPack.skillStationOperations;
  return sdk.GridAssetDefinition(
    assetKey: assetKey ?? source.assetKey,
    description: source.description,
    artifacts: source.artifacts,
    teaches: source.teaches,
    audience: source.audience,
    visibility: source.visibility,
    selector: selector ?? source.selector,
  );
}
