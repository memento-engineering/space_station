import 'package:args/args.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart' as github;
import 'package:grid_assets/grid_assets.dart' show AgentConfig;
import 'package:grid_engine/grid_engine.dart' show ServiceBundle;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station_assets/src/space_delegate.dart';
import 'package:space_station_assets/src/substation_seat.dart';
import 'package:test/test.dart';

/// space-6ds round 3 (`the_grid/docs/SCRATCH-memento-composition.md` §3,
/// evolved): the memento org is authored as five literal seats in
/// [SpaceDelegate.substations] (the roster BUILD HOOK) and `--substation`
/// flags APPEND new seats after it — no merge, no override-by-name (Fork B
/// as re-ruled: the roster changes in CODE — space edits [substations]; a
/// downstream station SUBCLASSES and overrides it). Pure + offline: the
/// delegate's tree mounts in a bare genesis tree (the same tree `runGrid`
/// mounts under `space up`) and its mounted [sdk.SubstationScope]s are
/// walked to prove the roster is authored IN the tree — literal seats, never
/// threaded config values.
void main() {
  // A grid home that looks like the umbrella sibling (space_station beside its
  // peers): each literal `../<repo>` seat resolves against the ambient
  // GridRoot (tg-32r) to `<umbrella>/<repo>`.
  const gridHome = '/home/memento/space_station';
  const umbrella = '/home/memento';
  const codedNames = {
    'genesis',
    'the_grid',
    'power_station',
    'space_station',
    'lenny',
  };

  SpaceDelegate delegate({List<SubstationSeat> appended = const []}) =>
      SpaceDelegate(
        gridRoot: gridHome,
        appended: appended,
        agentConfig: const AgentConfig(harness: 'claude'),
      );

  group('SpaceDelegate.build — the hardcoded memento org (Fork A)', () {
    test('a BARE delegate mounts the five coded seats at their ../<repo> '
        'umbrella siblings with the coded prefixes — the roster is the tree, '
        'not config', () {
      final seats = _mountedSeats(_Author(delegate()));
      expect(
        seats.map((s) => s.name),
        ['genesis', 'the_grid', 'power_station', 'space_station', 'lenny'],
        reason: 'the org, in mount order, from the literal Substation seats',
      );
      // Roots are the umbrella siblings `../<repo>`, resolved by the SDK
      // against the ambient GridRoot.
      expect(
        {for (final s in seats) s.name: s.root},
        {
          'genesis': '$umbrella/genesis',
          'the_grid': '$umbrella/the_grid',
          'power_station': '$umbrella/power_station',
          'space_station': '$umbrella/space_station',
          'lenny': '$umbrella/lenny',
        },
      );
      // Prefix is a SEPARATE axis from the name wherever the store mints
      // differently (the_grid → `tg-…`, power_station → `pow-…`,
      // space_station → `space-…`); the rest default to the name (round 3).
      expect(
        {for (final s in seats) s.name: s.prefix},
        {
          'genesis': 'genesis',
          'the_grid': 'tg',
          'power_station': 'pow',
          'space_station': 'space',
          'lenny': 'lenny',
        },
      );
    });

    test('appended seats mount AFTER the coded org, in order — never instead '
        'of it', () {
      final seats = _mountedSeats(
        _Author(
          delegate(
            appended: [
              SubstationSeat(name: 'tgdog', root: '/work/td'),
              SubstationSeat(name: 'extra', root: '/work/x', prefix: 'ex'),
            ],
          ),
        ),
      );
      expect(seats.map((s) => s.name), [
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'tgdog',
        'extra',
      ]);
      expect(seats[5].root, '/work/td');
      expect(seats.last.prefix, 'ex');
    });
  });

  group('the SUBCLASS extension seam — a downstream station overrides the '
      'delegate hooks (extend, never fork)', () {
    test('an overridden substations() composes super\'s org (at the '
        'overridden umbrella) plus the downstream seats, and stationName '
        're-identifies the station', () {
      final downstream = _DownstreamDelegate(gridRoot: '/home/me/my_station');
      expect(downstream.stationName, 'downstream');
      final seats = _mountedSeats(_Author(downstream));
      expect(seats.map((s) => s.name), [
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'mine',
      ]);
      // The org resolves at the OVERRIDDEN umbrella (relative to the
      // downstream grid home), the downstream seat at its own root — both
      // through the SAME SubstationSeat class (one seat class, different
      // VALUES — space-47t).
      expect(seats.first.root, '/home/me/memento/genesis');
      expect(seats.last.root, '/home/me/mine');
      expect(seats.last.prefix, 'mn');
    });

    test('codedRosterOf enumerates the subclass roster through one OWNED '
        'offline mount (construct → mount → dispose)', () {
      final scopes = codedRosterOf(_DownstreamDelegate.new);
      expect(scopes.map((s) => s.name), contains('mine'));
      expect(scopes, hasLength(6));
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

      test('a NEW name parses into an appended seat (with its @prefix) that '
          'composes into the delegate tree after the org', () {
        final config = spaceStationConfigFrom(
          parse(['--grid-home', gridHome, '--substation', 'tgdog@td=/work/td']),
          codedNames: codedNames,
        )!;
        final seat = config.appended.single;
        expect(seat.name, 'tgdog');
        expect(seat.root, '/work/td');
        expect(seat.prefix, 'td');
        expect(seat.landingPolicy, isNull);
        expect(
          _mountedValues<github.GitHubDeliveryPolicy>(
            _Author(delegate(appended: config.appended)),
          ),
          isEmpty,
        );
        final appendedBundle = _mountedValues<ServiceBundle>(
          _Author(delegate(appended: config.appended)),
        ).where((bundle) => bundle.mountEligibility != null).last;
        expect(appendedBundle.sourceControl, isNotNull);
        expect(appendedBundle.mountEligibility, isNotNull);
        // The parsed seat carries the standard substation stack — it mounts
        // clean after the coded five.
        final seats = _mountedSeats(
          _Author(delegate(appended: config.appended)),
        );
        expect(seats.map((s) => s.name), [
          'genesis',
          'the_grid',
          'power_station',
          'space_station',
          'lenny',
          'tgdog',
        ]);
        expect(seats.last.prefix, 'td');
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

/// Mounts [root] in a bare tree, flushes one build pass (the Track B/F
/// template, mirroring `space_delegate_test.dart`), and walks the mounted
/// branches collecting every provided [sdk.SubstationScope] in tree order —
/// the seats [SpaceDelegate.build] actually authored.
List<sdk.SubstationScope> _mountedSeats(Seed root) {
  final owner = TreeOwner();
  final branch = owner.mountRoot(root);
  owner.flush();
  final seats = <sdk.SubstationScope>[];
  void walk(Branch b) {
    if (b is InheritedBranch<sdk.SubstationScope>) seats.add(b.value);
    b.visitChildren(walk);
  }

  walk(branch);
  return seats;
}

List<T> _mountedValues<T extends Object>(Seed root) {
  final owner = TreeOwner();
  addTearDown(owner.dispose);
  final branch = owner.mountRoot(root);
  owner.flush();
  final values = <T>[];
  void walk(Branch current) {
    if (current is InheritedBranch<T>) values.add(current.value);
    current.visitChildren(walk);
  }

  walk(branch);
  return values;
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

/// The downstream-station shape, in miniature (the lunar pattern): a
/// [SpaceDelegate] SUBCLASS whose constructor mirrors the base via
/// super-parameters (so `.new` satisfies `SpaceDelegateFactory`) and whose
/// hooks re-identify the station, re-point the org umbrella, and COMPOSE the
/// inherited roster with its own seats.
class _DownstreamDelegate extends SpaceDelegate {
  _DownstreamDelegate({
    super.gridRoot = '/home/me/my_station',
    super.agentConfig,
    super.appended,
    super.harnesses,
    super.wiring,
    super.provisioner,
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
    SubstationSeat(name: 'mine', root: '../mine', prefix: 'mn'),
  ];
}
