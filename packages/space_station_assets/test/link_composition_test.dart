library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cli/grid_cli.dart' show LinkCommand;
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
    super.trajectoryConfig,
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

Future<Map<String, Object?>?> _beadJson(String root, String id) async {
  final rows =
      jsonDecode(await _runBd(root, ['show', id, '--json'])) as List<Object?>;
  return rows.isEmpty ? null : rows.single as Map<String, Object?>;
}

void main() {
  test('composes ONE immutable endpoint roster carrying name AND prefix', () {
    final endpoints = buildSpaceLinkCommand(
      gridRoot: '/fixture/space',
      delegateFactory: _DownstreamDelegate.new,
    ).endpoints;
    // The NAME is the `<project>` token an `external:<project>:<capability>`
    // row carries (grid_cli 0.6.0-dev.3); the PREFIX is how an endpoint id
    // resolves to a store. Both come from the coded roster, in roster order.
    expect(
      endpoints.map(
        (endpoint) => (endpoint.name, endpoint.prefix, endpoint.store.root),
      ),
      [
        ('alpha', 'alpha', '/fixture/space/alpha'),
        ('beta', 'beta', '/fixture/space/beta'),
      ],
    );
  });

  test('the station composes `link` alone — the unlink verb is GONE', () {
    final runner = buildRunner(delegateFactory: _DownstreamDelegate.new);
    final link = runner.commands['link'];
    expect(link, isA<LinkCommand>());
    // The additive migrate flags ride the same parser (the_grid#447).
    expect(link!.argParser.usage, contains('--blocked-by'));
    expect(link.argParser.usage, contains('--grid-root'));
    expect(link.argParser.usage, contains('--dry-run'));
    // HARD CUT, no shim: grid_cli deleted `UnlinkCommand` with the state-store
    // link bead, so this station composes no unlink verb and mints no
    // replacement for it. A cross-store blocker is a bd dependency row; it is
    // removed with `bd dep remove` or lifts when the target ships.
    expect(runner.commands['unlink'], isNull);
    expect(runner.commands.keys, isNot(contains('unlink')));
  });

  test('a downstream runner links its tranquility-owned bead as a bd '
      'external dependency row', () async {
    final fixture = await Directory.systemTemp.createTemp('space_link_');
    addTearDown(() => fixture.delete(recursive: true));
    final root = fixture.resolveSymbolicLinksSync();
    await _init('$root/.grid', 'tranquility');
    await _init('$root/alpha', 'alpha');
    await _init('$root/beta', 'beta');
    // Both endpoints must be OBSERVABLE: the verb labels the target and adds
    // the row, and refuses when the target is not in its substation's store.
    await _runBd('$root/alpha', ['create', 'consumer', '--id', 'alpha-1']);
    await _runBd('$root/beta', ['create', 'provider', '--id', 'beta-1']);

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

    expect(await runner.run(['link', '--grid-root', root, 'ls']), 0);
    expect(runner.commands['ls'], isNull);

    expect(
      await runner.run([
        'link',
        '--grid-root',
        root,
        '--blocked-by',
        'beta-1',
        'alpha-1',
      ]),
      0,
    );

    // The row is bd's, in the CONSUMER's own store. `bd dep list` resolves
    // each row to an issue RECORD and a cross-project target has none here,
    // so the row shows up as the record's dependency COUNT, never in that
    // listing — the same asymmetry grid_assets reads through bd's record
    // surface.
    final consumer = (await _beadJson('$root/alpha', 'alpha-1'))!;
    expect(consumer['dependency_count'], 1);

    // The TARGET carries the export label the row points at.
    expect(
      (await _beadJson('$root/beta', 'beta-1'))!['labels'],
      contains('export:beta-1'),
    );

    // NOTHING was minted in the station's own state store.
    expect(
      jsonDecode(await _runBd('$root/.grid', ['list', '--json'])),
      isEmpty,
    );
  }, tags: ['bd-e2e']);
}
