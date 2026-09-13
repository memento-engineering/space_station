@Tags(['bd-e2e'])
/// AC-6 (space-2xl): after `beads configure`, `bd` ITSELF resolves the
/// projected substation as an external project.
///
/// This is the whole point of the verb — bd resolves
/// `external:<project>:<capability>` through `external_projects`
/// (`GetExternalProjects` / `ResolveExternalProjectPath`), and before the
/// projection no store in the roster carries that map, so every `external:`
/// row is dead on arrival. `bd config show` is bd's own READ of the merged
/// config (`config.yaml` + `config.local.yaml`), so an entry here is bd
/// agreeing the project exists and its path resolves — the exact state a
/// cross-store dependency needs.
///
/// Tagged `bd-e2e`: it spawns the real `bd` binary, so it is excluded from the
/// station's validation lane (`dart test -x bd-e2e`) along with the other
/// store-backed suites.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart' show CommandRunner;
import 'package:genesis_tree/genesis_tree.dart' show Seed, TreeContext;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

class _FixtureDelegate extends SpaceDelegate {
  _FixtureDelegate({
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

void main() {
  late Directory home;

  String rootOf(String name) => '${home.path}/$name';

  void makeStore(String name) {
    Directory('${rootOf(name)}/.beads').createSync(recursive: true);
    File(
      '${rootOf(name)}/.beads/config.yaml',
    ).writeAsStringSync('issue-prefix: "$name"\n');
  }

  /// bd's OWN view of the merged config for the store at [root].
  Future<Map<String, String>> bdExternalProjects(String root) async {
    final result = await Process.run('bd', [
      'config',
      'show',
      '--json',
    ], workingDirectory: root);
    expect(
      result.exitCode,
      0,
      reason: 'bd config show failed: ${result.stderr}',
    );
    final entries = jsonDecode(result.stdout as String) as List<Object?>;
    return {
      for (final entry in entries.cast<Map<String, Object?>>())
        if ((entry['key']! as String).startsWith('external_projects.'))
          (entry['key']! as String).substring('external_projects.'.length):
              entry['value']! as String,
    };
  }

  setUp(() {
    home = Directory.systemTemp.createTempSync('space-beads-bd-');
    makeStore('alpha');
    makeStore('beta');
  });

  tearDown(() => home.deleteSync(recursive: true));

  test('bd resolves the projected substation as an external project only '
      'AFTER the verb has run', () async {
    expect(
      await bdExternalProjects(rootOf('alpha')),
      isEmpty,
      reason:
          'the precondition the ruling names: no store in the roster carries '
          'the map, so every external: row is dead on arrival',
    );

    final out = StringBuffer();
    final runner = CommandRunner<int>('space', 'fixture')
      ..addCommand(
        buildSpaceBeadsCommand(
          delegateFactory: _FixtureDelegate.new,
          gridHomeDefault: () => home.path,
          out: out,
        ),
      );
    expect(
      await runner.run(['beads', 'configure', '--grid-home', home.path]),
      0,
    );

    expect(await bdExternalProjects(rootOf('alpha')), {'beta': rootOf('beta')});
    expect(await bdExternalProjects(rootOf('beta')), {
      'alpha': rootOf('alpha'),
    });
  });
}
