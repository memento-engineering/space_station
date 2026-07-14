import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show Bead, BeadStatus, IssueType;
import 'package:grid_assets/grid_assets.dart'
    show StationSearchService, SubstationBeadSource;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station/space_station.dart';
import 'package:test/test.dart';

/// The LAST-MILE composition: `space search` is the VENDED `grid_assets`
/// Command curried with space's resident-station context, so the roster it
/// searches is the BAKED memento org ([SpaceDelegate.build]) — five coded
/// seats at their `../<repo>` umbrella siblings, resolved against the grid
/// home. The Command's own behaviour is pinned in power_station; this suite
/// pins the WIRING. Offline: a Fake bead source + a Fake directory probe +
/// captured sinks — no `bd`, no processes, no filesystem.
class _FakeBeadSource implements SubstationBeadSource {
  const _FakeBeadSource(this.byRoot);

  final Map<String, List<Bead>> byRoot;

  @override
  Future<List<Bead>> read(sdk.SubstationScope scope) async =>
      byRoot[scope.root] ?? const [];
}

void main() {
  const umbrella = '/home/memento';
  const gridHome = '$umbrella/space_station';

  final beads = <String, List<Bead>>{
    '$umbrella/genesis': const [
      Bead(
        id: 'genesis-1',
        title: 'keyed reconcile for the flux capacitor',
        issueType: IssueType.task,
      ),
    ],
    '$umbrella/the_grid': const [
      Bead(
        id: 'tg-1',
        title: 'Decide the flux wiring',
        closeReason: 'ratified',
        status: BeadStatus.closed,
        issueType: IssueType.decision,
      ),
    ],
  };

  ({CommandRunner<int> runner, StringBuffer out, StringBuffer err}) harness({
    String home = gridHome,
  }) {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = CommandRunner<int>('space', "memento's grid station")
      ..addCommand(
        buildSpaceSearchCommand(
          gridHomeDefault: () => home,
          service: StationSearchService(
            source: _FakeBeadSource(beads),
            dirExists: const {
              '$umbrella/genesis/.beads',
              '$umbrella/the_grid/.beads',
            }.contains,
          ),
          out: out,
          err: err,
        ),
      );
    return (runner: runner, out: out, err: err);
  }

  test('`search --json <q>` searches the BAKED memento roster — the five coded '
      'seats, in tree order, at their ../<repo> siblings, with the coded '
      'prefixes', () async {
    final h = harness();
    final code = await h.runner.run(['search', '--json', 'flux']);

    expect(code, 0);
    final json = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    expect(json['query'], 'flux');
    expect(json['hitCount'], 2);
    final stores = [
      for (final s in json['stores']! as List) s as Map<String, dynamic>,
    ];
    expect(
      stores.map((s) => s['substation']),
      ['genesis', 'the_grid', 'power_station', 'space_station', 'lenny'],
      reason: "the roster is SpaceDelegate.build's, not a hardcoded list",
    );
    expect(
      {for (final s in stores) s['substation']: s['prefix']},
      {
        'genesis': 'genesis',
        'the_grid': 'tg',
        'power_station': 'pow',
        'space_station': 'space',
        'lenny': 'lenny',
      },
    );
    expect(stores.first['root'], '$umbrella/genesis');
    final hit = (stores.first['hits']! as List).single as Map<String, dynamic>;
    expect(hit['id'], 'genesis-1');
    expect(hit['store'], 'genesis');
    // A seat with no store is REPORTED, never dropped (the skip-loud posture).
    expect(
      [for (final s in stores) if (s['outcome'] == 'absent') s['substation']],
      ['power_station', 'space_station', 'lenny'],
    );
  });

  test('an explicit --grid-home re-roots the roster (the flag reaches '
      'SpaceDelegate.gridRoot); an all-absent roster is a LOUD non-answer '
      '(exit 1), never an empty result', () async {
    final h = harness();
    final code = await h.runner.run([
      'search',
      '--grid-home',
      '/other/space_station',
      '--json',
      'flux',
    ]);

    expect(code, 1, reason: 'no seat under /other resolves a store');
    final json = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    final stores = [
      for (final s in json['stores']! as List) s as Map<String, dynamic>,
    ];
    expect(stores.first['root'], '/other/genesis');
    expect(stores.every((s) => s['outcome'] == 'absent'), isTrue);
  });

  test('a RELATIVE --grid-home is refused LOUD (UsageException → exit 64 '
      'through bin/space.dart), never a raw ArgumentError from the mount',
      () async {
    final h = harness();
    await expectLater(
      h.runner.run(['search', '--grid-home', 'rel/home', 'flux']),
      throwsA(isA<UsageException>()),
    );
  });

  test('no query is a usage refusal: exit 64, loud on stderr, nothing on '
      'stdout', () async {
    final h = harness();
    expect(await h.runner.run(['search']), 64);
    expect(h.err.toString(), contains('a query is required'));
    expect(h.out.toString(), isEmpty);
  });
}
