import 'package:args/args.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart' show AgentConfig, ProviderManaged;
import 'package:grid_runtime/grid_runtime.dart' show RootCheckout;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station/src/space_delegate.dart';
import 'package:test/test.dart';

/// space-6ds (`the_grid/docs/SCRATCH-memento-composition.md` §3): the coded
/// memento roster (Fork A) + the `--substation`/TOML append/merge layer
/// (Fork B). Pure + offline — the roster helpers ([mementoCodedRoster],
/// [mergeRoster], [mementoCodedNames]) and the config assembly
/// ([spaceStationConfigFrom]) are pure logic; the delegate's [SpaceDelegate.build]
/// tree mounts in a bare genesis tree (the same tree `runGrid` mounts under
/// `space up`).
void main() {
  // A grid home that looks like the umbrella sibling (space_station beside its
  // peers): the coded roots resolve to `<umbrella>/<repo>`.
  const gridHome = '/home/memento/space_station';
  const umbrella = '/home/memento';

  group('mementoCodedRoster — the coded org (Fork A)', () {
    test('is the five memento repos, in mount order, rooted at umbrella siblings '
        'with the right issue-id prefixes', () {
      final roster = mementoCodedRoster(gridHome);
      expect(
        roster.map((s) => s.name),
        ['genesis', 'the_grid', 'power_station', 'space_station', 'lenny'],
        reason: 'the coded roster IS the memento-engineering org, in order',
      );
      // Roots are the umbrella siblings `../<name>`, resolved absolute.
      expect(
        {for (final s in roster) s.name: s.root.path},
        {
          'genesis': '$umbrella/genesis',
          'the_grid': '$umbrella/the_grid',
          'power_station': '$umbrella/power_station',
          'space_station': '$umbrella/space_station',
          'lenny': '$umbrella/lenny',
        },
      );
      // Prefix is a SEPARATE axis from the name (the_grid mints `tg-…`).
      expect(
        {for (final s in roster) s.name: s.prefix},
        {
          'genesis': 'genesis',
          'the_grid': 'tg',
          'power_station': 'pow',
          'space_station': 'space',
          'lenny': 'lenny',
        },
      );
    });

    test('mementoCodedNames is exactly the coded roster names', () {
      expect(
        mementoCodedNames,
        {'genesis', 'the_grid', 'power_station', 'space_station', 'lenny'},
      );
      expect(
        mementoCodedNames,
        mementoCodedRoster(gridHome).map((s) => s.name).toSet(),
        reason: 'the name set and the roster must never drift',
      );
    });
  });

  group('mergeRoster — the append/merge layer (Fork B)', () {
    RootCheckout root(String name, String path) =>
        RootCheckout(path: path, substation: name, defaultBranch: 'main');

    test('no overrides ⇒ the coded base, unchanged', () {
      final base = mementoCodedRoster(gridHome);
      final merged = mergeRoster(base, const []);
      expect(merged.map((s) => s.name), base.map((s) => s.name));
      expect(merged.map((s) => s.root.path), base.map((s) => s.root.path));
    });

    test('an override of a CODED name rebinds its root IN PLACE (same position, '
        'the override wins) — never a duplicate, never a reorder', () {
      final base = mementoCodedRoster(gridHome);
      final merged = mergeRoster(base, [
        SpaceSubstation(
          name: 'the_grid',
          prefix: 'tg',
          root: root('the_grid', '/custom/tg'),
        ),
      ]);
      // Order and count are the coded five — the merge is IN PLACE.
      expect(
        merged.map((s) => s.name),
        ['genesis', 'the_grid', 'power_station', 'space_station', 'lenny'],
      );
      expect(merged.length, 5);
      expect(merged[1].name, 'the_grid');
      expect(merged[1].root.path, '/custom/tg', reason: 'the override won');
    });

    test('rebinding a coded root WITHOUT a prefix PRESERVES the coded prefix '
        '(power_station stays `pow`, not the name) — a field merge, not a '
        'wholesale replace', () {
      final base = mementoCodedRoster(gridHome);
      final merged = mergeRoster(base, [
        // No `@prefix`: the operator only means to rebind the root.
        SpaceSubstation(
          name: 'power_station',
          root: root('power_station', '/elsewhere/ps'),
        ),
      ]);
      final ps = merged.firstWhere((s) => s.name == 'power_station');
      expect(ps.root.path, '/elsewhere/ps', reason: 'the root rebound');
      expect(ps.prefix, 'pow', reason: 'the coded prefix survived the rebind');
    });

    test('an EXPLICIT prefix on the override wins over the coded one', () {
      final base = mementoCodedRoster(gridHome);
      final merged = mergeRoster(base, [
        SpaceSubstation(
          name: 'power_station',
          prefix: 'psx',
          root: root('power_station', '/elsewhere/ps'),
        ),
      ]);
      final ps = merged.firstWhere((s) => s.name == 'power_station');
      expect(ps.prefix, 'psx');
    });

    test('an override with a NEW name is APPENDED after the coded roster', () {
      final base = mementoCodedRoster(gridHome);
      final merged = mergeRoster(base, [
        SpaceSubstation(name: 'tgdog', root: root('tgdog', '/work/td')),
      ]);
      expect(merged.length, 6);
      expect(merged.last.name, 'tgdog');
      expect(
        merged.take(5).map((s) => s.name),
        ['genesis', 'the_grid', 'power_station', 'space_station', 'lenny'],
        reason: 'the coded base stays first, in order',
      );
    });

    test('merge + append together preserve order (coded first, extras after in '
        'flag order)', () {
      final base = mementoCodedRoster(gridHome);
      final merged = mergeRoster(base, [
        SpaceSubstation(name: 'extra_a', root: root('extra_a', '/x/a')),
        SpaceSubstation(
          name: 'genesis',
          root: root('genesis', '/custom/genesis'),
        ),
        SpaceSubstation(name: 'extra_b', root: root('extra_b', '/x/b')),
      ]);
      expect(merged.map((s) => s.name), [
        'genesis',
        'the_grid',
        'power_station',
        'space_station',
        'lenny',
        'extra_a',
        'extra_b',
      ]);
      expect(merged.first.root.path, '/custom/genesis');
    });
  });

  group('spaceStationConfigFrom — hardcoded base ⊕ flags (Fork B)', () {
    ArgResults parse(List<String> args) {
      final parser = ArgParser();
      addSpaceStationFlags(parser);
      return parser.parse(args);
    }

    test('no --substation ⇒ the effective roster IS the coded org (the '
        '"refuse with none" gate is retired)', () {
      final config = spaceStationConfigFrom(
        parse(['--grid-home', gridHome]),
      );
      expect(config, isNotNull);
      expect(
        config!.substations.map((s) => s.name),
        ['genesis', 'the_grid', 'power_station', 'space_station', 'lenny'],
      );
      expect(config.operatorNames, isEmpty);
    });

    test('a --substation overriding a coded name merges (root rebound) and marks '
        'the name operator-provided', () {
      final config = spaceStationConfigFrom(
        parse([
          '--grid-home',
          gridHome,
          '--substation',
          'the_grid@tg=/custom/tg',
        ]),
      )!;
      expect(config.substations.length, 5, reason: 'in-place merge');
      final tg = config.substations.firstWhere((s) => s.name == 'the_grid');
      expect(tg.root.path, '/custom/tg');
      expect(tg.prefix, 'tg');
      expect(config.operatorNames, contains('the_grid'));
    });

    test('a --substation with a new name appends and is operator-provided', () {
      final config = spaceStationConfigFrom(
        parse([
          '--grid-home',
          gridHome,
          '--substation',
          'tgdog=/work/td',
        ]),
      )!;
      expect(config.substations.length, 6);
      expect(config.substations.last.name, 'tgdog');
      expect(config.operatorNames, {'tgdog'});
    });

    test('a missing --grid-home is a null return (LOUD arming refusal upstream)',
        () {
      expect(spaceStationConfigFrom(parse(const [])), isNull);
    });

    test('the same --substation name twice is a LOUD FormatException (a real '
        'duplicate — distinct from a coded-name MERGE)', () {
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
    });
  });

  group('SpaceDelegate.build — the coded roster seats into the tree', () {
    SpaceDelegate delegate(List<SpaceSubstation> substations) => SpaceDelegate(
      gridRoot: gridHome,
      stationName: 'space',
      substations: substations,
      agentConfig: const AgentConfig(
        harness: 'claude',
        target: ProviderManaged(),
      ),
    );

    test('the full coded org mounts clean (all five sibling roots resolve as a '
        'valid v3 tree)', () {
      expect(
        () => _mount(_Author(delegate(mementoCodedRoster(gridHome)))),
        returnsNormally,
      );
    });

    test('the coded base plus an appended flag substation mounts clean', () {
      final roster = mergeRoster(mementoCodedRoster(gridHome), [
        SpaceSubstation(
          name: 'tgdog',
          root: RootCheckout(
            path: '/work/td',
            substation: 'tgdog',
            defaultBranch: 'main',
          ),
        ),
      ]);
      expect(() => _mount(_Author(delegate(roster))), returnsNormally);
    });

    test('a single coded substation (only genesis) still seats — the literal '
        'coded branch fires by name', () {
      expect(
        () => _mount(
          _Author(delegate(mementoCodedRoster(gridHome).take(1).toList())),
        ),
        returnsNormally,
      );
    });
  });
}

/// Mounts [root] in a bare tree and flushes one build pass (the Track B/F
/// template, mirroring `space_delegate_test.dart`).
void _mount(Seed root) {
  final owner = TreeOwner();
  owner.mountRoot(root);
  owner.flush();
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
