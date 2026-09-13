/// `beads configure` — the coded roster projected into bd's OWN
/// `external_projects` primitive (space-2xl).
///
/// The roster here is a FIXTURE station (three substations at temp roots), and
/// the stores are real directories: the verb's whole contract is what lands on
/// disk, so nothing about the filesystem is faked.
library;

import 'dart:io';

import 'package:args/command_runner.dart' show CommandRunner, UsageException;
import 'package:genesis_tree/genesis_tree.dart' show Seed, TreeContext;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart' show YamlMap, loadYaml;

/// A three-substation station whose roots are RELATIVE, so each one resolves
/// against whatever grid home the test passes — no statics, no ambient state.
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
    SubstationSeed(name: 'gamma', root: 'gamma'),
  ];
}

void main() {
  late Directory home;
  late StringBuffer out;
  late StringBuffer err;
  late CommandRunner<int> runner;

  String rootOf(String name) => '${home.path}/$name';
  String localConfigOf(String name) =>
      '${rootOf(name)}/.beads/config.local.yaml';
  String trackedConfigOf(String name) => '${rootOf(name)}/.beads/config.yaml';

  /// Creates `<home>/<name>/.beads/` with a tracked config bd would read.
  void makeStore(String name) {
    Directory('${rootOf(name)}/.beads').createSync(recursive: true);
    File(trackedConfigOf(name)).writeAsStringSync('issue-prefix: "$name"\n');
  }

  Map<String, String> externalProjectsIn(String name) {
    final document = loadYaml(File(localConfigOf(name)).readAsStringSync());
    final projects = (document as YamlMap)['external_projects'] as YamlMap;
    return {
      for (final entry in projects.entries) '${entry.key}': '${entry.value}',
    };
  }

  Future<int> configure({bool dryRun = false, String? gridHome}) => runner
      .run([
        'beads',
        'configure',
        '--grid-home',
        gridHome ?? home.path,
        if (dryRun) '--dry-run',
      ])
      .then((code) => code!);

  setUp(() {
    home = Directory.systemTemp.createTempSync('space-beads-configure-');
    out = StringBuffer();
    err = StringBuffer();
    runner = CommandRunner<int>('space', 'fixture')
      ..addCommand(
        buildSpaceBeadsCommand(
          delegateFactory: _FixtureDelegate.new,
          gridHomeDefault: () => home.path,
          out: out,
          err: err,
        ),
      );
  });

  tearDown(() => home.deleteSync(recursive: true));

  test('the projection maps every OTHER ARMED substation, sorted by name', () {
    const armed = [
      sdk.SubstationScope(name: 'beta', root: '/r/beta', prefix: 'beta'),
      sdk.SubstationScope(name: 'alpha', root: '/r/alpha', prefix: 'alpha'),
      sdk.SubstationScope(name: 'gamma', root: '/r/gamma', prefix: 'gamma'),
    ];

    expect(externalProjectsFor(name: 'beta', armed: armed), {
      'alpha': '/r/alpha',
      'gamma': '/r/gamma',
    });
    expect(
      externalProjectsFor(name: 'beta', armed: armed).keys.toList(),
      ['alpha', 'gamma'],
      reason: 'sorted, so a re-run is byte-identical',
    );
    expect(
      externalProjectsFor(name: 'solo', armed: const []),
      isEmpty,
      reason: 'an empty armed roster projects nothing rather than refusing',
    );
  });

  // AC-1
  test('writes every store the other two substations, and never touches the '
      'tracked config.yaml', () async {
    for (final name in const ['alpha', 'beta', 'gamma']) {
      makeStore(name);
    }
    final trackedBefore = {
      for (final name in const ['alpha', 'beta', 'gamma'])
        name: File(trackedConfigOf(name)).readAsBytesSync(),
    };

    expect(await configure(), 0, reason: err.toString());

    expect(externalProjectsIn('alpha'), {
      'beta': rootOf('beta'),
      'gamma': rootOf('gamma'),
    });
    expect(externalProjectsIn('beta'), {
      'alpha': rootOf('alpha'),
      'gamma': rootOf('gamma'),
    });
    expect(externalProjectsIn('gamma'), {
      'alpha': rootOf('alpha'),
      'beta': rootOf('beta'),
    });
    for (final name in const ['alpha', 'beta', 'gamma']) {
      expect(
        File(trackedConfigOf(name)).readAsBytesSync(),
        trackedBefore[name],
        reason: '$name/.beads/config.yaml must be untouched',
      );
      expect(out.toString(), contains('$name -> 2 projects written'));
    }
    expect(err.toString(), isEmpty);
  });

  // AC-2
  test(
    'a second run reports unchanged and leaves the files byte-identical',
    () async {
      for (final name in const ['alpha', 'beta', 'gamma']) {
        makeStore(name);
      }
      expect(await configure(), 0, reason: err.toString());
      final afterFirst = {
        for (final name in const ['alpha', 'beta', 'gamma'])
          name: File(localConfigOf(name)).readAsBytesSync(),
      };
      out.clear();

      expect(await configure(), 0, reason: err.toString());

      for (final name in const ['alpha', 'beta', 'gamma']) {
        expect(out.toString(), contains('$name -> 2 projects unchanged'));
        expect(out.toString(), isNot(contains('$name -> 2 projects written')));
        expect(File(localConfigOf(name)).readAsBytesSync(), afterFirst[name]);
      }
    },
  );

  // AC-3
  test('--dry-run prints the per-store map and writes no file', () async {
    for (final name in const ['alpha', 'beta', 'gamma']) {
      makeStore(name);
    }

    expect(await configure(dryRun: true), 0, reason: err.toString());

    for (final name in const ['alpha', 'beta', 'gamma']) {
      expect(File(localConfigOf(name)).existsSync(), isFalse);
    }
    expect(out.toString(), contains('DRY-RUN, nothing is written.'));
    expect(out.toString(), contains('alpha -> 2 projects to write'));
    expect(out.toString(), contains('    beta: ${rootOf('beta')}'));
    expect(out.toString(), contains('    gamma: ${rootOf('gamma')}'));
    expect(out.toString(), contains('    alpha: ${rootOf('alpha')}'));
  });

  // AC-4
  test('an unrelated pre-existing local key survives the write', () async {
    for (final name in const ['alpha', 'beta', 'gamma']) {
      makeStore(name);
    }
    File(localConfigOf('beta')).writeAsStringSync(
      '# the operator wrote this by hand\n'
      'sync.remote: "file:///Users/nico/.dolt-remotes/beta"\n',
    );

    expect(await configure(), 0, reason: err.toString());

    final rewritten = File(localConfigOf('beta')).readAsStringSync();
    expect(rewritten, contains('# the operator wrote this by hand'));
    final document = loadYaml(rewritten) as YamlMap;
    expect(document['sync.remote'], 'file:///Users/nico/.dolt-remotes/beta');
    expect(externalProjectsIn('beta'), {
      'alpha': rootOf('alpha'),
      'gamma': rootOf('gamma'),
    });
  });

  // AC-4 — the half-finished hand edit: the key is PRESENT with no value at
  // all. Treating that as an absent key appends a second `external_projects:`
  // and the rewrite stops parsing, which used to throw out of the verb and
  // strand the rest of the roster unconfigured.
  test('a present-but-EMPTY external_projects key is filled in, not '
      'duplicated, and the rest of the roster still runs', () async {
    for (final name in const ['alpha', 'beta', 'gamma']) {
      makeStore(name);
    }
    File(localConfigOf('beta')).writeAsStringSync(
      '# operator started filling this in\n'
      'external_projects:\n',
    );

    expect(await configure(), 0, reason: err.toString());

    final rewritten = File(localConfigOf('beta')).readAsStringSync();
    expect(
      'external_projects:'.allMatches(rewritten).length,
      1,
      reason: 'exactly one top-level key, so the document still parses',
    );
    expect(rewritten, contains('# operator started filling this in'));
    expect(externalProjectsIn('beta'), {
      'alpha': rootOf('alpha'),
      'gamma': rootOf('gamma'),
    });
    for (final name in const ['alpha', 'beta', 'gamma']) {
      expect(out.toString(), contains('$name -> 2 projects written'));
    }
    expect(err.toString(), isEmpty);
  });

  test('an existing external_projects key is REPLACED, not merged, so a '
      'retired substation leaves no stale row', () async {
    for (final name in const ['alpha', 'beta', 'gamma']) {
      makeStore(name);
    }
    File(
      localConfigOf('beta'),
    ).writeAsStringSync('external_projects:\n  retired: /gone\n');

    expect(await configure(), 0, reason: err.toString());

    expect(externalProjectsIn('beta'), {
      'alpha': rootOf('alpha'),
      'gamma': rootOf('gamma'),
    });
  });

  // AC-5
  test('a substation root with no .beads store is reported and skipped, and '
      'no store is created', () async {
    makeStore('alpha');
    makeStore('beta');
    Directory(rootOf('gamma')).createSync(recursive: true);

    expect(await configure(), 0, reason: err.toString());

    expect(
      out.toString(),
      contains('gamma -> skipped (no store at ${rootOf('gamma')}/.beads)'),
    );
    expect(Directory('${rootOf('gamma')}/.beads').existsSync(), isFalse);
    expect(File(localConfigOf('alpha')).existsSync(), isTrue);
    expect(
      externalProjectsIn('alpha'),
      {'beta': rootOf('beta')},
      reason:
          'the WHAT maps every OTHER ARMED substation: an unarmed root is no '
          'project, so writing its name would leave a row bd resolves to a '
          'directory with no store',
    );
    expect(out.toString(), contains('alpha -> 1 projects written'));
  });

  test('a root that does not exist at all is skipped the same way', () async {
    makeStore('alpha');
    makeStore('beta');

    expect(await configure(), 0, reason: err.toString());

    expect(out.toString(), contains('gamma -> skipped (no store at '));
    expect(Directory(rootOf('gamma')).existsSync(), isFalse);
  });

  // A store bd will not read a local overlay for: the write would be inert, so
  // it is skipped and reported rather than made and silently ignored. It is
  // still ARMED, so the other stores still carry it as a project.
  test('a .beads store with no tracked config.yaml is skipped, never written, '
      'and its config.yaml is not invented', () async {
    makeStore('alpha');
    makeStore('beta');
    Directory('${rootOf('gamma')}/.beads').createSync(recursive: true);

    expect(await configure(), 0, reason: err.toString());

    expect(
      out.toString(),
      contains(
        'gamma -> skipped (no config.yaml at ${trackedConfigOf('gamma')}',
      ),
    );
    expect(File(localConfigOf('gamma')).existsSync(), isFalse);
    expect(File(trackedConfigOf('gamma')).existsSync(), isFalse);
    expect(
      externalProjectsIn('alpha'),
      {'beta': rootOf('beta'), 'gamma': rootOf('gamma')},
      reason:
          'gamma resolves a work store, so it IS armed and IS a project — only '
          'its own overlay would have gone unread',
    );
  });

  test(
    'a local config that is not a mapping is REFUSED, never clobbered',
    () async {
      makeStore('alpha');
      makeStore('beta');
      makeStore('gamma');
      File(
        localConfigOf('beta'),
      ).writeAsStringSync('- a list, not a mapping\n');

      expect(await configure(), 1);

      expect(
        err.toString(),
        contains('beta -> REFUSED ${localConfigOf('beta')}'),
      );
      expect(
        File(localConfigOf('beta')).readAsStringSync(),
        '- a list, not a mapping\n',
      );
      expect(out.toString(), contains('alpha -> 2 projects written'));
      expect(
        out.toString(),
        contains('gamma -> 2 projects written'),
        reason: 'a refusal is per store; the roster AFTER it still runs',
      );
    },
  );

  test('an external_projects value that is not a mapping is REFUSED', () async {
    makeStore('alpha');
    makeStore('beta');
    makeStore('gamma');
    File(localConfigOf('beta')).writeAsStringSync('external_projects: nope\n');

    expect(await configure(), 1);

    expect(err.toString(), contains('beta -> REFUSED'));
    expect(
      File(localConfigOf('beta')).readAsStringSync(),
      'external_projects: nope\n',
    );
  });

  test('a local config that is not valid YAML is REFUSED, and a --dry-run '
      'reports the same refusal', () async {
    makeStore('alpha');
    makeStore('beta');
    makeStore('gamma');
    File(
      localConfigOf('beta'),
    ).writeAsStringSync('external_projects:\n  a: 1\nexternal_projects:\n');

    expect(await configure(dryRun: true), 1);
    expect(err.toString(), contains('beta -> REFUSED'));
    err.clear();

    expect(await configure(), 1);
    expect(err.toString(), contains('beta -> REFUSED'));
    expect(
      File(localConfigOf('beta')).readAsStringSync(),
      'external_projects:\n  a: 1\nexternal_projects:\n',
    );
  });

  test(
    'a relative --grid-home is refused LOUD, before anything is written',
    () async {
      makeStore('alpha');

      expect(
        () => configure(gridHome: 'relative/home'),
        throwsA(isA<UsageException>()),
      );
      expect(File(localConfigOf('alpha')).existsSync(), isFalse);
    },
  );

  test('the verb is composed on the station runner', () {
    final beads = buildRunner().commands['beads'];
    expect(beads, isNotNull);
    expect(beads!.subcommands.keys, contains('configure'));
  });
}
