@Tags(['bd-e2e'])
library;

import 'dart:io';

import 'package:args/command_runner.dart';
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
    super.gitOps,
    super.prOpener,
  });

  @override
  String get umbrella => '.';

  @override
  List<sdk.Substation> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [seat(context, 'alpha', 'alpha'), seat(context, 'beta', 'beta')];
}

Future<void> _init(String root, String prefix) async {
  Directory(root).createSync(recursive: true);
  final result = await Process.run('bd', [
    'init',
    '--non-interactive',
    '--skip-agents',
    '--skip-hooks',
    '-p',
    prefix,
  ], workingDirectory: root);
  if (result.exitCode != 0) {
    fail('bd init failed in $root: ${result.stderr}');
  }
}

void main() {
  test('derives one immutable endpoint roster for both vended commands', () {
    final commands = buildSpaceLinkCommands(
      gridRoot: '/fixture/space',
      delegateFactory: _DownstreamDelegate.new,
    );

    expect(commands.link.stateStorePrefix, kSpaceStateStorePrefix);
    expect(commands.unlink.stateStorePrefix, kSpaceStateStorePrefix);
    expect(commands.link.endpoints.map((e) => (e.prefix, e.store.root)), [
      ('alpha', '/fixture/space/alpha'),
      ('beta', '/fixture/space/beta'),
    ]);
    expect(
      commands.unlink.endpoints.map((e) => (e.prefix, e.store.root)),
      commands.link.endpoints.map((e) => (e.prefix, e.store.root)),
    );
  });

  test(
    'a downstream runner inherits link, unlink, and internal link ls',
    () async {
      final fixture = await Directory.systemTemp.createTemp('space_link_');
      addTearDown(() => fixture.delete(recursive: true));
      final root = fixture.resolveSymbolicLinksSync();
      await _init('$root/.grid', 'houston');
      await _init('$root/alpha', 'alpha');
      await _init('$root/beta', 'beta');

      final commands = buildSpaceLinkCommands(
        gridRoot: root,
        delegateFactory: _DownstreamDelegate.new,
      );
      final runner = CommandRunner<int>('lunar', 'fixture')
        ..addCommand(commands.link)
        ..addCommand(commands.unlink);

      expect(runner.commands['link'], isA<LinkCommand>());
      expect(runner.commands['unlink'], isA<UnlinkCommand>());
      expect(
        runner.commands['link']!.argParser.usage,
        contains('--blocked-by'),
      );
      expect(runner.commands['unlink']!.argParser.usage, contains('--reason'));
      expect(await runner.run(['link', '--grid-root', root, 'ls']), 0);
      expect(runner.commands['ls'], isNull);
    },
  );
}
