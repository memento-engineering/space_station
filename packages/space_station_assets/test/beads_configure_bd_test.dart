@Tags(['bd-e2e'])
/// AC-6 (space-2xl): after `beads configure`, `bd` ITSELF is driven — the
/// literal leg, on real `bd init` stores.
///
/// This is the whole point of the verb — `bd` resolves
/// `external:<project>:<capability>` through `external_projects`, and before
/// the projection no store in the roster carries that map, so every `external:`
/// row names a project bd cannot place. `bd config show` is bd's own READ of
/// the merged config (`config.yaml` + `config.local.yaml`), so an entry there
/// is bd agreeing the project exists; `bd dep add` is the operator act the
/// projection exists to serve, and `bd list --json` is bd's own read-back of
/// the stored edge.
///
/// **What this suite MEASURED about the installed bd** (HEAD-a45199a, the
/// fleet build): bd stores an `external:` edge as-is and surfaces it on the
/// issue record, and it resolves the PROJECT through `external_projects` — but
/// it does not yet subtract that edge as a blocker at query time. A configured
/// project and an unconfigured one are stored identically, and `bd dep list`,
/// `bd blocked` and `bd ready` ignore both. The last test pins that
/// measurement: it going red is the signal that bd grew query-time external
/// resolution and the frontier work (`tg-xh5d`) has a blocker to honour.
///
/// Tagged `bd-e2e`: it spawns the real `bd` binary and initialises real Dolt
/// stores, so it is excluded from the station's validation lane
/// (`dart test -x bd-e2e`) along with the other store-backed suites.
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

  /// A `.beads/` with the tracked config bd merges the local overlay over —
  /// enough for `bd config show`, and all the cheap probe needs.
  void makeShallowStore(String name) {
    Directory('${rootOf(name)}/.beads').createSync(recursive: true);
    File(
      '${rootOf(name)}/.beads/config.yaml',
    ).writeAsStringSync('issue-prefix: "$name"\n');
  }

  /// A REAL bd store: `bd init` with its own Dolt database, the thing a
  /// dependency has to resolve into.
  Future<void> initStore(String name) async {
    Directory(rootOf(name)).createSync(recursive: true);
    final result = await Process.run(
      'bd',
      ['init', '--non-interactive', '--quiet', '--prefix', name],
      workingDirectory: rootOf(name),
      environment: const {'BD_NON_INTERACTIVE': '1'},
    );
    expect(result.exitCode, 0, reason: 'bd init failed: ${result.stderr}');
  }

  /// Runs `bd` INSIDE [root]. `bd -C` is deliberately not used: it resolves
  /// the workspace from the process's own directory before it changes, so the
  /// store under test has to be the working directory.
  Future<ProcessResult> bd(String root, List<String> arguments) => Process.run(
    'bd',
    arguments,
    workingDirectory: root,
    environment: const {'BD_NON_INTERACTIVE': '1'},
  );

  /// bd's OWN view of the merged config for the store at [root].
  Future<Map<String, String>> bdExternalProjects(String root) async {
    final result = await bd(root, ['config', 'show', '--json']);
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

  /// The `depends_on_id` rows bd carries on [id] — bd's own read-back of the
  /// edges `bd dep add` stored, external references included.
  Future<List<String>> bdDependencyIds(String root, String id) async {
    final result = await bd(root, ['list', '--json']);
    expect(result.exitCode, 0, reason: 'bd list failed: ${result.stderr}');
    final issues = (jsonDecode(result.stdout as String) as List<Object?>)
        .cast<Map<String, Object?>>();
    final issue = issues.firstWhere((i) => i['id'] == id);
    final dependencies =
        (issue['dependencies'] as List<Object?>? ?? const <Object?>[])
            .cast<Map<String, Object?>>();
    return [
      for (final dependency in dependencies)
        dependency['depends_on_id']! as String,
    ];
  }

  Future<String> bdCreate(String root, String title, {String? label}) async {
    final result = await bd(root, [
      'create',
      title,
      '--silent',
      if (label != null) ...['--labels', label],
    ]);
    expect(result.exitCode, 0, reason: 'bd create failed: ${result.stderr}');
    return (result.stdout as String).trim().split('\n').last.trim();
  }

  Future<int> configure() async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = CommandRunner<int>('space', 'fixture')
      ..addCommand(
        buildSpaceBeadsCommand(
          delegateFactory: _FixtureDelegate.new,
          gridHomeDefault: () => home.path,
          out: out,
          err: err,
        ),
      );
    final code = await runner.run([
      'beads',
      'configure',
      '--grid-home',
      home.path,
    ]);
    expect(code, 0, reason: '$out$err');
    return code!;
  }

  setUp(() {
    home = Directory.systemTemp.createTempSync('space-beads-bd-');
  });

  tearDown(() => home.deleteSync(recursive: true));

  test('bd resolves the projected substation as an external project only '
      'AFTER the verb has run', () async {
    makeShallowStore('alpha');
    makeShallowStore('beta');

    expect(
      await bdExternalProjects(rootOf('alpha')),
      isEmpty,
      reason:
          'the precondition the ruling names: no store in the roster carries '
          'the map, so every external: row names an unplaceable project',
    );

    await configure();

    expect(await bdExternalProjects(rootOf('alpha')), {'beta': rootOf('beta')});
    expect(await bdExternalProjects(rootOf('beta')), {
      'alpha': rootOf('alpha'),
    });
  });

  // AC-6 — the literal leg, on real stores.
  test('bd dep add with an external: reference to another CONFIGURED store is '
      'accepted and stored against the projected project', () async {
    await initStore('alpha');
    await initStore('beta');
    await bdCreate(
      rootOf('beta'),
      'ship the widget capability',
      label: 'export:widget',
    );
    final dependent = await bdCreate(rootOf('alpha'), 'needs beta widget');

    await configure();

    final projects = await bdExternalProjects(rootOf('alpha'));
    expect(projects, {'beta': rootOf('beta')});
    final resolved = await bd(projects['beta']!, ['where']);
    expect(
      resolved.exitCode,
      0,
      reason:
          'the projected path must resolve to a REAL bd store, not just an '
          'existing directory: ${resolved.stderr}',
    );
    expect(resolved.stdout as String, contains('prefix: beta'));

    final added = await bd(rootOf('alpha'), [
      'dep',
      'add',
      dependent,
      'external:beta:widget',
    ]);
    expect(
      added.exitCode,
      0,
      reason: 'bd dep add refused the external reference: ${added.stderr}',
    );
    expect(
      await bdDependencyIds(rootOf('alpha'), dependent),
      contains('external:beta:widget'),
      reason: 'bd carries the edge against the projected project name',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  // The MEASURED limit of the installed bd, pinned so it cannot be assumed
  // away. AC-6 asks for a BLOCKER; bd HEAD-a45199a does not produce one, and
  // this is the receipt. Red here means bd gained query-time external
  // resolution — read it as news, not as a regression in this station.
  test(
    'bd HEAD-a45199a does NOT yet subtract an external edge as a blocker, and '
    'stores an unconfigured project identically',
    () async {
      await initStore('alpha');
      await initStore('beta');
      final dependent = await bdCreate(rootOf('alpha'), 'needs beta widget');

      await configure();

      for (final reference in const [
        'external:beta:widget',
        'external:ghost:widget',
      ]) {
        final added = await bd(rootOf('alpha'), [
          'dep',
          'add',
          dependent,
          reference,
        ]);
        expect(added.exitCode, 0, reason: added.stderr as String);
      }
      expect(
        await bdDependencyIds(rootOf('alpha'), dependent),
        containsAll(const ['external:beta:widget', 'external:ghost:widget']),
        reason:
            'configured and unconfigured projects are stored the same way, so '
            'bd is not resolving the project at dep-add time',
      );

      final deps = await bd(rootOf('alpha'), [
        'dep',
        'list',
        dependent,
        '--json',
      ]);
      expect(deps.exitCode, 0, reason: deps.stderr as String);
      expect(
        jsonDecode(deps.stdout as String),
        isEmpty,
        reason: 'bd drops external edges from its dependency views',
      );

      final blocked = await bd(rootOf('alpha'), ['blocked', '--json']);
      expect(blocked.exitCode, 0, reason: blocked.stderr as String);
      expect(
        jsonDecode(blocked.stdout as String),
        isEmpty,
        reason:
            'the AC asks for a blocker; the installed bd reports none, so the '
            'blocker belongs to the frontier work (tg-xh5d), not to this verb',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
