@Tags(['bd-e2e'])
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cli/grid_cli.dart' show LinkCommand, UnlinkCommand;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

class _DownstreamDelegate extends SpaceDelegate {
  _DownstreamDelegate({
    required super.gridRoot,
    super.agentConfig,
    super.appended,
    super.harnesses,
    super.wiring,
    super.provisioner,
    super.githubSelfTrust,
    super.live,
  });

  @override
  String get stateStorePrefix => 'tranquility';

  @override
  String get umbrella => '.';

  @override
  List<Seed> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    SubstationSeed(name: 'alpha', root: 'alpha'),
    SubstationSeed(name: 'beta', root: 'beta'),
  ];
}

Future<String> _runBd(String root, List<String> args) async {
  final result = await Process.run('bd', args, workingDirectory: root);
  if (result.exitCode != 0) {
    throw StateError('bd ${args.join(' ')} failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

Future<void> _init(String root, String prefix) async {
  Directory(root).createSync(recursive: true);
  await _runBd(root, [
    'init',
    '--non-interactive',
    '--skip-agents',
    '--skip-hooks',
    '-p',
    prefix,
  ]);
}

Future<List<Bead>> _stateBeads(String stateRoot) async {
  final workspace = BeadsWorkspace.discover(start: stateRoot)!;
  return BdCliService(ProcessBdRunner(workspaceRoot: workspace.root)).query(
    'status=open OR status=in_progress OR status=blocked OR '
    'status=deferred OR status=closed',
    includeClosed: true,
  );
}

void main() {
  test(
    'derives the delegate-owned state prefix and one immutable endpoint roster',
    () {
      final spaceCommands = buildSpaceLinkCommands(gridRoot: '/fixture/space');
      expect(spaceCommands.link.stateStorePrefix, 'houston');
      expect(spaceCommands.unlink.stateStorePrefix, 'houston');

      final downstreamCommands = buildSpaceLinkCommands(
        gridRoot: '/fixture/space',
        delegateFactory: _DownstreamDelegate.new,
      );
      expect(downstreamCommands.link.stateStorePrefix, 'tranquility');
      expect(downstreamCommands.unlink.stateStorePrefix, 'tranquility');
      expect(
        downstreamCommands.link.endpoints.map(
          (endpoint) => (endpoint.prefix, endpoint.store.root),
        ),
        [('alpha', '/fixture/space/alpha'), ('beta', '/fixture/space/beta')],
      );
      expect(
        downstreamCommands.unlink.endpoints.map(
          (endpoint) => (endpoint.prefix, endpoint.store.root),
        ),
        downstreamCommands.link.endpoints.map(
          (endpoint) => (endpoint.prefix, endpoint.store.root),
        ),
      );
    },
  );

  test(
    'a downstream runner links then unlinks its tranquility-owned bead',
    () async {
      final fixture = await Directory.systemTemp.createTemp('space_link_');
      addTearDown(() => fixture.delete(recursive: true));
      final root = fixture.resolveSymbolicLinksSync();
      final stateRoot = '$root/.grid';
      await _init(stateRoot, 'tranquility');
      await _init('$root/alpha', 'alpha');
      await _init('$root/beta', 'beta');
      await _runBd(stateRoot, ['config', 'set', 'types.custom', 'link']);

      final previousWorkingDirectory = Directory.current.path;
      late CommandRunner<int> runner;
      try {
        Directory.current = root;
        runner = buildRunner(
          name: 'lunar',
          delegateFactory: _DownstreamDelegate.new,
        );
      } finally {
        Directory.current = previousWorkingDirectory;
      }

      expect(runner.commands['link'], isA<LinkCommand>());
      expect(runner.commands['unlink'], isA<UnlinkCommand>());
      expect(
        runner.commands['link']!.argParser.usage,
        contains('--blocked-by'),
      );
      expect(runner.commands['unlink']!.argParser.usage, contains('--reason'));
      expect(await runner.run(['link', '--grid-root', root, 'ls']), 0);
      expect(runner.commands['ls'], isNull);

      expect(
        await runner.run([
          'link',
          '--grid-root',
          root,
          '--prefix',
          'tranquility',
          '--prefix',
          'alpha',
          '--prefix',
          'beta',
          '--blocked-by',
          'beta-1',
          '--reason',
          'integration proof',
          '--actor',
          'test',
          'alpha-1',
        ]),
        0,
      );
      final opened = (await _stateBeads(
        stateRoot,
      )).singleWhere((bead) => bead.id.startsWith('tranquility-'));
      expect(opened.isClosed, isFalse);

      expect(
        await runner.run([
          'unlink',
          '--grid-root',
          root,
          '--prefix',
          'tranquility',
          '--reason',
          'blocker landed',
          '--actor',
          'test',
          opened.id,
        ]),
        0,
      );
      final closed = (await _stateBeads(
        stateRoot,
      )).singleWhere((bead) => bead.id == opened.id);
      expect(closed.isClosed, isTrue);
    },
  );
}
