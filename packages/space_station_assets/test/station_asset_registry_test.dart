import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:genesis_tree/genesis_tree.dart' show ValueKey;
import 'package:grid_assets/grid_assets.dart'
    show
        AgentCapability,
        GridAssetsPack,
        PackagedAssetLoader,
        SubstationFacts,
        SubstationFactsSnapshot,
        SubstationKey;
import 'package:grid_engine/grid_engine.dart'
    show
        CapabilityHost,
        CapabilityStep,
        Circuit,
        NodeCursor,
        SessionHandle,
        StepMount,
        Workspace;
import 'package:grid_engine/testing.dart'
    show FakeTreeContext, stepArgs, testWorkspace;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:space_station_assets/station_asset_registry.dart';
import 'package:test/test.dart';

const _fixtureSubstation = SubstationKey('fixture');

const _agentCircuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

StepMount _agentMount() => StepMount(
  step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
  nodePath: 'fixture/agent',
  circuit: _agentCircuit,
  circuitPath: 'fixture',
  session: const SessionHandle('fixture-session'),
  node: const NodeCursor(),
  key: const ValueKey('fixture/agent#0.0'),
);

void main() {
  test(
    'generator delegates and checks without writes',
    () async {
      final packageRoot = Directory.current.absolute;
      final generated = File(
        p.join(packageRoot.path, 'lib', 'station_asset_registry.dart'),
      );
      final beforeBytes = generated.readAsBytesSync();
      final beforeModified = generated.lastModifiedSync();
      final generator = p.join(
        packageRoot.path,
        'tool',
        'generate_station_asset_registry.dart',
      );

      final checked = await Process.run(Platform.resolvedExecutable, [
        generator,
        '--check',
      ], workingDirectory: packageRoot.path);

      expect(checked.exitCode, 0, reason: checked.stderr as String);
      expect(checked.stdout, contains('station assets:'));
      expect(generated.readAsBytesSync(), orderedEquals(beforeBytes));
      expect(generated.lastModifiedSync(), beforeModified);

      final missingGraph = Directory.systemTemp.createTempSync(
        'space-station-registry-missing-graph-',
      );
      addTearDown(() => missingGraph.deleteSync(recursive: true));
      final refused = await Process.run(Platform.resolvedExecutable, [
        generator,
        '--station-root',
        missingGraph.path,
        '--output',
        p.join(missingGraph.path, 'registrant.dart'),
      ], workingDirectory: packageRoot.path);

      expect(refused.exitCode, 2);
      expect(refused.stderr, contains('.dart_tool/package_config.json'));
      expect(
        File(p.join(missingGraph.path, 'registrant.dart')).existsSync(),
        isFalse,
      );

      final tool = File(
        p.join(
          packageRoot.path,
          'tool',
          'generate_station_asset_registry.dart',
        ),
      ).readAsStringSync();
      expect(tool, contains('runStationAssetRegistryGenerator('));
      expect(tool, contains('kGeneratedStationAssetRegistryPath'));
      for (final type in <String>[
        'StalePackageGraphException',
        'StationAssetRegistryException',
        'GridBlockException',
        'ArgumentError',
      ]) {
        expect(tool, contains('on $type catch (error)'));
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('registry: SpaceDelegate override reaches buildCodeRegistry', () {
    final delegate = _RegistryDelegate(gridRoot: '/fixture/grid-home');
    addTearDown(delegate.dispose);
    expect(delegate.assetRegistry, same(_RegistryDelegate.registry));

    final worktree = Directory.systemTemp.createTempSync(
      'space-registry-worktree-',
    );
    addTearDown(() => worktree.deleteSync(recursive: true));
    final registry = delegate.buildWorkRegistry(
      (_, _) async {},
      (
        _, {
        required String design,
        required String acceptanceCriteria,
      }) async {},
    );
    final capability =
        (registry.host(_agentMount()) as CapabilityHost).capability
            as AgentCapability;
    capability.spawn(
      FakeTreeContext(
        values: {
          Bead: const Bead(id: 'fixture-work'),
          sdk.SubstationScope: sdk.SubstationScope(
            name: _fixtureSubstation.name,
            root: worktree.path,
            prefix: 'fx',
          ),
          SubstationFactsSnapshot: _gridAssetsFacts(worktree.path),
          Workspace: testWorkspace(
            'fixture-work',
            workspaceDir: worktree.path,
            branch: 'grid/fixture-work',
          ),
        },
      ),
      stepArgs('fixture-work/agent'),
    );

    expect(_stationOperationsSkill(worktree).existsSync(), isTrue);
    expect(_discoverSkill(worktree).existsSync(), isFalse);
  });

  test(
    'space defaults to its generated registry without a literal catalog; '
    'one downstream registry reaches assets command and composition',
    () async {
      final baseDelegate = SpaceDelegate(gridRoot: '/fixture/grid-home');
      addTearDown(baseDelegate.dispose);
      expect(
        baseDelegate.assetRegistry,
        same(GeneratedGridAssetRegistrant.registry),
      );

      final defaultComposition = buildRunnerComposition();
      expect(
        defaultComposition.assetRegistry,
        same(GeneratedGridAssetRegistrant.registry),
      );
      expect(defaultComposition.assetRegistry.packs, hasLength(1));
      expect(
        defaultComposition.assetRegistry.packs.single,
        same(GridAssetsPack.definition),
      );

      final composition = buildRunnerComposition(
        delegateFactory: _RegistryDelegate.new,
        assetRegistry: _RegistryDelegate.registry,
      );
      expect(composition.assetRegistry, same(_RegistryDelegate.registry));
      expect(
        buildRunner(
          assetRegistry: _RegistryDelegate.registry,
        ).commands['assets'],
        isNotNull,
      );

      final target = Directory.systemTemp.createTempSync(
        'space-registry-assets-',
      );
      addTearDown(() => target.deleteSync(recursive: true));
      _writePackageConfig(target);

      expect(
        await composition.runner.run([
          'assets',
          'install',
          '--grid-home',
          target.absolute.path,
          '--source-ref',
          'fixture-ref',
          '--no-diff',
        ]),
        0,
      );
      expect(_stationOperationsSkill(target).existsSync(), isTrue);
      expect(_discoverSkill(target).existsSync(), isFalse);

      final source = File('lib/space_station_assets.dart').readAsStringSync();
      expect(source, isNot(contains('GridAssetRegistry(')));
      expect(
        source,
        contains('registry: resolvedAssetRegistry'),
        reason: 'the composed AssetsCommand must receive the returned object',
      );
    },
  );
}

SubstationFactsSnapshot _gridAssetsFacts(String root) =>
    SubstationFactsSnapshot({
      _fixtureSubstation: SubstationFacts(
        root: root,
        dartPackages: const ['grid_assets'],
        packageRoots: {'grid_assets': _gridAssetsPackageRoot},
      ),
    });

String get _gridAssetsPackageRoot => p.dirname(PackagedAssetLoader().root);

File _stationOperationsSkill(Directory root) => File(
  p.join(root.path, '.claude', 'skills', 'station-operations', 'SKILL.md'),
);

File _discoverSkill(Directory root) =>
    File(p.join(root.path, '.claude', 'skills', 'discover', 'SKILL.md'));

void _writePackageConfig(Directory target) {
  final config = File(p.join(target.path, '.dart_tool', 'package_config.json'))
    ..createSync(recursive: true);
  config.writeAsStringSync(
    jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': 'grid_assets',
          'rootUri': Directory(_gridAssetsPackageRoot).uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.11',
        },
      ],
    }),
  );
}

final class _RegistryDelegate extends SpaceDelegate {
  _RegistryDelegate({
    required super.gridRoot,
    super.agentConfig,
    super.appended,
    super.harnesses,
    super.wiring,
    super.provisioner,
    super.githubSelfTrust,
    super.live,
  });

  static final sdk.GridAssetRegistry registry = sdk.GridAssetRegistry([
    sdk.GridAssetPackDefinition(
      package: GridAssetsPack.package,
      assets: [GridAssetsPack.skillStationOperations],
    ),
  ]);

  @override
  sdk.GridAssetRegistry get assetRegistry => registry;

  @override
  String get overlaySourceRef => 'fixture-ref';
}
