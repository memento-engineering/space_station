// ignore_for_file: deprecated_member_use

import 'package:args/args.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart' as github;
import 'package:grid_assets/grid_assets.dart' show AgentConfig;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station_assets/space_station_assets.dart'
    show CodedRosterSnapshotCompatibility;
import 'package:space_station_assets/src/space_delegate.dart'
    show
        SpaceDelegate,
        addSpaceStationFlags,
        codedRosterOf,
        codedRosterSnapshotOf,
        kMementoOrgApp,
        spaceStationConfigFrom;
import 'package:space_station_assets/src/substation_seed.dart';
import 'package:test/test.dart';

/// space-6ds round 3 (`the_grid/docs/SCRATCH-memento-composition.md` §3,
/// evolved): the memento org is authored as seven literal substations in
/// [SpaceDelegate.substations] (the roster BUILD HOOK) and `--substation`
/// flags APPEND new substations after it — no merge, no override-by-name (Fork B
/// as re-ruled: the roster changes in CODE — space edits [substations]; a
/// downstream station SUBCLASSES and overrides it). Pure + offline: the
/// delegate's tree mounts in a bare genesis tree (the same tree `runGrid`
/// mounts under `space up`) and its mounted [sdk.SubstationScope]s are
/// walked to prove the roster is authored IN the tree — literal substations,
/// never threaded config values.
void main() {
  // A grid home that looks like the umbrella sibling (space_station beside its
  // peers): each literal `../<repo>` substation resolves against the ambient
  // GridRoot (tg-32r) to `<umbrella>/<repo>`.
  const gridHome = '/home/memento/space_station';
  const umbrella = '/home/memento';
  const codedNames = {
    'genesis',
    'the_grid',
    'power_station',
    'space_station',
    'lenny',
    'decisions',
    'memento-engineering',
  };

  SpaceDelegate delegate({List<sdk.Substation> appended = const []}) =>
      SpaceDelegate(
        gridRoot: gridHome,
        appended: appended,
        agentConfig: const AgentConfig(harness: 'claude'),
      );

  group('SpaceDelegate.build — the hardcoded memento org (Fork A)', () {
    test('a BARE delegate mounts the seven coded substations at their '
        '../<repo> '
        'umbrella siblings with the coded prefixes — the roster is the tree, '
        'not config', () {
      final substations = _mountedSubstations(_Author(delegate()));
      expect(
        substations.map((s) => s.name),
        [
          'genesis',
          'the_grid',
          'power_station',
          'space_station',
          'lenny',
          'decisions',
          'memento-engineering',
        ],
        reason: 'the org, in mount order, from the literal Substation values',
      );
      // Roots are the umbrella siblings `../<repo>`, resolved by the SDK
      // against the ambient GridRoot.
      expect(
        {for (final s in substations) s.name: s.root},
        {
          'genesis': '$umbrella/genesis',
          'the_grid': '$umbrella/the_grid',
          'power_station': '$umbrella/power_station',
          'space_station': '$umbrella/space_station',
          'lenny': '$umbrella/lenny',
          'decisions': '$umbrella/decisions',
          'memento-engineering': '$umbrella/memento-engineering',
        },
      );
      // Prefix is a SEPARATE axis from the name wherever the store mints
      // differently (the_grid → `tg-…`, power_station → `pow-…`,
      // space_station → `space-…`, decisions → `dec-…`); genesis and lenny
      // default to their names (round 3).
      expect(
        {for (final s in substations) s.name: s.prefix},
        {
          'genesis': 'genesis',
          'the_grid': 'tg',
          'power_station': 'pow',
          'space_station': 'space',
          'lenny': 'lenny',
          'decisions': 'dec',
          'memento-engineering': 'org',
        },
      );
    });

    test('appended substations mount AFTER the coded org, in order — never '
        'instead '
        'of it', () {
      final substations = _mountedSubstations(
        _Author(
          delegate(
            appended: [
              sdk.Substation('tgdog', '/work/td'),
              sdk.Substation('extra', '/work/x', prefix: 'ex'),
            ],
          ),
        ),
      );
      expect(substations.map((s) => s.name), [
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'decisions',
        'memento-engineering',
        'tgdog',
        'extra',
      ]);
      expect(substations[7].root, '/work/td');
      expect(substations.last.prefix, 'ex');
    });
  });

  group('the org DELIVERY IDENTITY — the memento App, per substation '
      '(space-u8q)', () {
    test('every org substation carries the memento App identity as its OWN '
        'value, and no substation gains a landing policy', () {
      final substations = _capturedSubstations(delegate());
      expect(substations.map((substation) => substation.name), [
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'decisions',
        'memento-engineering',
      ]);
      expect(
        substations.map((substation) => substation.app),
        everyElement(kMementoOrgApp),
      );
      expect(kMementoOrgApp.appId, '4529262');
      expect(kMementoOrgApp.installationId, '152260260');
      expect(kMementoOrgApp.privateKeyVar, 'GRID_GITHUB_APP_KEY_MEMENTO');
      // DELIVERY identity here; the poll VALUES are pinned by the intake group
      // below (space-3ds). The deliver / commit-only selection is space-9d0 and
      // is still unauthored.
      expect(
        substations.map((substation) => substation.landingPolicy),
        everyElement(isNull),
      );
    });

    test('the identity binds PER SUBSTATION: seven identity providers, each '
        'over '
        'exactly one substation scope — none above the fan-out, no name-keyed '
        'map', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(_Author(delegate()));
      owner.flush();
      final identities = _branches<GitHubAppConfig>(root);
      expect(identities, hasLength(7));
      expect(identities.map((branch) => branch.value).toSet(), {
        kMementoOrgApp,
      });
      for (final identity in identities) {
        expect(
          _branches<sdk.SubstationScope>(identity),
          hasLength(1),
          reason: 'an identity above the fan-out would carry all seven scopes',
        );
      }
    });

    test('a downstream override inherits the seven org substations WITH the '
        'memento App through super, and its own substation keeps its own '
        'identity', () {
      final substations = _capturedSubstations(
        _DownstreamDelegate(gridRoot: '/home/me/my_station'),
      );
      expect(substations, hasLength(8));
      expect(
        substations.take(7).map((substation) => substation.app),
        everyElement(kMementoOrgApp),
      );
      expect(substations.last.name, 'mine');
      expect(substations.last.app, _downstreamApp);
      expect(
        substations.last.app?.privateKeyVar,
        'GRID_GITHUB_APP_KEY_NICHOLAS',
      );
    });
  });

  group('the org INTAKE — GitHub polling, per substation (space-3ds)', () {
    test('every org substation polls its OWN repository under the org App '
        'installation, and the three cadence defaults stand', () {
      final substations = _capturedSubstations(delegate());
      expect(substations.map((substation) => substation.name), [
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'decisions',
        'memento-engineering',
      ]);
      for (final substation in substations) {
        final poll = substation.githubPoll;
        expect(poll, isNotNull, reason: '${substation.name} must poll');
        expect(poll!.owner, 'memento-engineering');
        // repository AND substation are the SUBSTATION NAME — never the
        // bead-id
        // prefix, which addresses the work store and not GitHub.
        expect(poll.repository, substation.name);
        expect(poll.substation, substation.name);
        // ONE App: the poll installation IS the delivery installation.
        expect(poll.installationId, kMementoOrgApp.installationId);
        expect(poll.installationId, '152260260');
        // Unauthored, so the package defaults stand.
        expect(poll.arm, github.GitHubReconcilerArm.live);
        expect(poll.interval, const Duration(minutes: 1));
        expect(poll.minimumSpacing, const Duration(seconds: 5));
      }
    });

    test(
      'a downstream override inherits the seven polling org substations '
      'through super and keeps its own substation on its own installation',
      () {
        final substations = _capturedSubstations(
          _DownstreamDelegate(gridRoot: '/home/me/my_station'),
        );
        expect(substations, hasLength(8));
        expect(
          substations
              .take(7)
              .map((substation) => substation.githubPoll?.installationId),
          everyElement('152260260'),
        );
        expect(substations.last.name, 'mine');
        expect(substations.last.githubPoll?.installationId, '1');
        expect(
          substations.last.githubPoll?.arm,
          github.GitHubReconcilerArm.offline,
        );
      },
    );
  });

  group('the SUBCLASS extension seam — a downstream station overrides the '
      'delegate hooks (extend, never fork)', () {
    test('an overridden substations() composes super\'s org (at the '
        'overridden umbrella) plus the downstream substations, and stationName '
        're-identifies the station', () {
      final downstream = _DownstreamDelegate(gridRoot: '/home/me/my_station');
      expect(downstream.stationName, 'downstream');
      final substations = _mountedSubstations(_Author(downstream));
      expect(substations.map((s) => s.name), [
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'decisions',
        'memento-engineering',
        'mine',
      ]);
      // The org resolves at the OVERRIDDEN umbrella (relative to the
      // downstream grid home), the downstream substation at its own root — both
      // through the SAME SubstationSeed class (one seed class, different
      // VALUES — space-47t).
      expect(substations.first.root, '/home/me/memento/genesis');
      expect(substations.last.root, '/home/me/mine');
      expect(substations.last.prefix, 'mn');
    });

    test('codedRosterOf enumerates the subclass roster through one OWNED '
        'offline mount (construct → mount → dispose)', () {
      final scopes = codedRosterOf(_DownstreamDelegate.new);
      expect(scopes.map((s) => s.name), contains('mine'));
      expect(scopes, hasLength(8));
    });

    test('coded roster snapshot keeps scopes and reports every GitHub polling '
        'substation — the seven org substations, plus a downstream substation '
        'that polls', () {
      final base = codedRosterSnapshotOf(SpaceDelegate.new, gridRoot: gridHome);
      expect(base.scopes.map((scope) => scope.name), [
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'decisions',
        'memento-engineering',
      ]);
      expect(base.githubPollingSubstationNames, {
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'decisions',
        'memento-engineering',
      });
      expect(
        base.githubPollingSeatNames,
        same(base.githubPollingSubstationNames),
      );

      final downstream = codedRosterSnapshotOf(_DownstreamDelegate.new);
      expect(downstream.scopes.map((scope) => scope.name), [
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'decisions',
        'memento-engineering',
        'mine',
      ]);
      expect(downstream.githubPollingSubstationNames, {
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'decisions',
        'memento-engineering',
        'mine',
      });
    });
  });

  group(
    'spaceStationConfigFrom — flags APPEND onto the coded org (Fork B)',
    () {
      ArgResults parse(List<String> args) {
        final parser = ArgParser();
        addSpaceStationFlags(parser, codedNames: codedNames.toList());
        return parser.parse(args);
      }

      test('no --substation ⇒ nothing appended (the coded org needs no flags — '
          'the "refuse with none" gate stays retired)', () {
        final config = spaceStationConfigFrom(
          parse(['--grid-home', gridHome]),
          codedNames: codedNames,
        );
        expect(config, isNotNull);
        expect(config!.appended, isEmpty);
      });

      test('a NEW name parses into an appended substation (with its @prefix) '
          'that '
          'composes into the delegate tree after the org', () {
        final config = spaceStationConfigFrom(
          parse(['--grid-home', gridHome, '--substation', 'tgdog@td=/work/td']),
          codedNames: codedNames,
        )!;
        final substation = config.appended.single;
        expect(substation.name, 'tgdog');
        expect(substation.root, '/work/td');
        expect(substation.prefix, 'td');
        // The parsed substation carries the standard substation stack — it
        // mounts clean after the coded seven.
        final substations = _mountedSubstations(
          _Author(delegate(appended: config.appended)),
        );
        expect(substations.map((s) => s.name), [
          'genesis',
          'the_grid',
          'power_station',
          'space_station',
          'lenny',
          'decisions',
          'memento-engineering',
          'tgdog',
        ]);
        expect(substations.last.prefix, 'td');
      });

      test('a flag naming a CODED substation is a LOUD FormatException — the '
          'roster is code, never overridden by config (round 3)', () {
        expect(
          () => spaceStationConfigFrom(
            parse([
              '--grid-home',
              gridHome,
              '--substation',
              'the_grid@tg=/custom/tg',
            ]),
            codedNames: codedNames,
          ),
          throwsFormatException,
        );
      });

      test(
        'the same --substation name twice is a LOUD FormatException (never a '
        'silent overwrite)',
        () {
          expect(
            () => spaceStationConfigFrom(
              parse([
                '--grid-home',
                gridHome,
                '--substation',
                'tgdog=/work/a',
                '--substation',
                'tgdog=/work/b',
              ]),
              codedNames: codedNames,
            ),
            throwsFormatException,
          );
        },
      );

      test(
        'a missing --grid-home is a null return (LOUD arming refusal upstream)',
        () {
          expect(
            spaceStationConfigFrom(parse(const []), codedNames: codedNames),
            isNull,
          );
        },
      );
    },
  );
}

/// Calls [delegate]'s roster hook with a live [TreeContext] and returns the
/// authored seeds — the VALUES only. The substations themselves are never
/// mounted, so no substation asset resolves a credential and the read is
/// machine-independent.
List<SubstationSeed> _capturedSubstations(SpaceDelegate delegate) {
  final captured = <Seed>[];
  final owner = TreeOwner();
  addTearDown(owner.dispose);
  owner.mountRoot(_RosterCapture(delegate, captured));
  owner.flush();
  return captured.cast<SubstationSeed>();
}

/// Collects every [InheritedBranch] of [T] under [root], in tree order.
List<InheritedBranch<T>> _branches<T extends Object>(Branch root) {
  final found = <InheritedBranch<T>>[];
  void walk(Branch branch) {
    if (branch is InheritedBranch<T>) found.add(branch);
    branch.visitChildren(walk);
  }

  walk(root);
  return found;
}

/// Mounts [delegate]'s roster hook and records the seeds it authored.
class _RosterCapture extends StatelessSeed {
  const _RosterCapture(this.delegate, this.captured);

  final SpaceDelegate delegate;
  final List<Seed> captured;

  @override
  Seed build(TreeContext context) {
    captured
      ..clear()
      ..addAll(delegate.substations(context, const sdk.GridConfiguration()));
    return const _Leaf();
  }
}

/// A childless leaf — the capture's inert subtree.
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// Mounts [root] in a bare tree, flushes one build pass (the Track B/F
/// template, mirroring `space_delegate_test.dart`), and walks the mounted
/// branches collecting every provided [sdk.SubstationScope] in tree order —
/// the substations [SpaceDelegate.build] actually authored.
List<sdk.SubstationScope> _mountedSubstations(Seed root) {
  final owner = TreeOwner();
  addTearDown(owner.dispose);
  final branch = owner.mountRoot(root);
  owner.flush();
  return _branches<sdk.SubstationScope>(
    branch,
  ).map((substation) => substation.value).toList();
}

/// Calls [SpaceDelegate.build] with a live [TreeContext] during mount (the
/// offline stand-in for runGrid's `_DelegateRoot`).
class _Author extends StatelessSeed {
  const _Author(this.delegate);

  final SpaceDelegate delegate;

  @override
  Seed build(TreeContext context) =>
      delegate.build(context, const sdk.GridConfiguration());
}

/// The DOWNSTREAM station's own App (lunar's shape): a SECOND identity on a
/// SECOND key variable. Each substation carries exactly one — neither station
/// gains a second identity.
const _downstreamApp = GitHubAppConfig(
  appId: '9001',
  installationId: '9002',
  privateKeyVar: 'GRID_GITHUB_APP_KEY_NICHOLAS',
);

/// The downstream-station shape, in miniature (the lunar pattern): a
/// [SpaceDelegate] SUBCLASS whose constructor mirrors the base via
/// super-parameters (so `.new` satisfies `SpaceDelegateFactory`) and whose
/// hooks re-identify the station, re-point the org umbrella, and COMPOSE the
/// inherited roster with its own substations.
class _DownstreamDelegate extends SpaceDelegate {
  _DownstreamDelegate({
    super.gridRoot = '/home/me/my_station',
    super.agentConfig,
    super.appended,
    super.harnesses,
    super.wiring,
    super.provisioner,
    super.githubSelfTrust,
    super.live,
  });

  @override
  String get stationName => 'downstream';

  @override
  String get umbrella => '../memento';

  @override
  List<Seed> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    ...super.substations(context, configuration),
    SubstationSeed(
      name: 'mine',
      root: '../mine',
      prefix: 'mn',
      app: _downstreamApp,
      githubPoll: const github.GitHubReconcilerConfig(
        owner: 'memento',
        repository: 'mine',
        substation: 'mine',
        installationId: '1',
        arm: github.GitHubReconcilerArm.offline,
      ),
    ),
  ];
}
