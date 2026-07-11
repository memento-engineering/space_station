import 'package:args/args.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart' show AgentConfig, ProviderManaged;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station/src/space_delegate.dart';
import 'package:test/test.dart';

/// space-6ds round 3 (`the_grid/docs/SCRATCH-memento-composition.md` §3): the
/// memento org is HARDCODED as five literal [sdk.Substation] seats in
/// [SpaceDelegate.build] (Fork A) and `--substation` flags APPEND new seats
/// after it — no merge, no override-by-name (Fork B as re-ruled: to change a
/// coded seat you fork the build). Pure + offline: the delegate's tree mounts
/// in a bare genesis tree (the same tree `runGrid` mounts under `space up`)
/// and its mounted [sdk.SubstationScope]s are walked to prove the roster is
/// authored IN the tree — literal seats, never threaded config values.
void main() {
  // A grid home that looks like the umbrella sibling (space_station beside its
  // peers): each literal `../<repo>` seat resolves against the ambient
  // GridRoot (tg-32r) to `<umbrella>/<repo>`.
  const gridHome = '/home/memento/space_station';
  const umbrella = '/home/memento';

  SpaceDelegate delegate({List<sdk.Substation> appended = const []}) =>
      SpaceDelegate(
        gridRoot: gridHome,
        stationName: 'space',
        appended: appended,
        agentConfig: const AgentConfig(
          harness: 'claude',
          target: ProviderManaged(),
        ),
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
      // Prefix is a SEPARATE axis from the name only where the store mints
      // differently (the_grid → `tg-…`, power_station → `pow-…`); the rest
      // default to the name (round 3).
      expect(
        {for (final s in seats) s.name: s.prefix},
        {
          'genesis': 'genesis',
          'the_grid': 'tg',
          'power_station': 'pow',
          'space_station': 'space_station',
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
              sdk.Substation('tgdog', '/work/td'),
              sdk.Substation('extra', '/work/x', prefix: 'ex'),
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

  group(
    'spaceStationConfigFrom — flags APPEND onto the coded org (Fork B)',
    () {
      ArgResults parse(List<String> args) {
        final parser = ArgParser();
        addSpaceStationFlags(parser);
        return parser.parse(args);
      }

      test('no --substation ⇒ nothing appended (the coded org needs no flags — '
          'the "refuse with none" gate stays retired)', () {
        final config = spaceStationConfigFrom(parse(['--grid-home', gridHome]));
        expect(config, isNotNull);
        expect(config!.appended, isEmpty);
      });

      test('a NEW name parses into an appended seat (with its @prefix) that '
          'composes into the delegate tree after the org', () {
        final config = spaceStationConfigFrom(
          parse(['--grid-home', gridHome, '--substation', 'tgdog@td=/work/td']),
        )!;
        final seat = config.appended.single;
        expect(seat.name, 'tgdog');
        expect(seat.root, '/work/td');
        expect(seat.prefix, 'td');
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
          'org is hardcoded and forked, never overridden (round 3)', () {
        expect(
          () => spaceStationConfigFrom(
            parse([
              '--grid-home',
              gridHome,
              '--substation',
              'the_grid@tg=/custom/tg',
            ]),
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
            ),
            throwsFormatException,
          );
        },
      );

      test(
        'a missing --grid-home is a null return (LOUD arming refusal upstream)',
        () {
          expect(spaceStationConfigFrom(parse(const [])), isNull);
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

/// Calls [SpaceDelegate.build] with a live [TreeContext] during mount (the
/// offline stand-in for runGrid's `_DelegateRoot`).
class _Author extends StatelessSeed {
  const _Author(this.delegate);

  final SpaceDelegate delegate;

  @override
  Seed build(TreeContext context) =>
      delegate.build(context, const sdk.GridConfiguration());
}
