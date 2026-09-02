import 'package:grid_assets/grid_assets.dart'
    show BuildAgentEnvironment, mountedValuesOf;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// The PER-SUBSTATION rung, PROVED in the tree. These mount the REAL coded
/// station offline and read each seat's TYPED resolution off the projection its
/// own subtree provides (ADR-0002 D5, ADR-0006 D2).
void main() {
  final registry = buildMementoEnvironmentRegistry();

  Map<String, SeatEnvironments?> seatEnvironments() {
    final delegate = SpaceDelegate(gridRoot: '/home/memento/space_station');
    try {
      return {
        for (final seat in mountedValuesOf<MountedSubstationSeed>(delegate))
          seat.scope.name: seat.environments,
      };
    } finally {
      delegate.dispose();
    }
  }

  test('every coded seat resolves all four typed lookups; power_station BUILDS '
      'on frontier while every other seat rides the coded codex posture', () {
    final seats = seatEnvironments();
    expect(seats.keys, hasLength(6));
    expect(seats['power_station']?.build, registry.resolve('frontier'));
    for (final name in seats.keys.where((n) => n != 'power_station')) {
      expect(
        seats[name]?.build,
        registry.resolve('codex-frontier'),
        reason: name,
      );
    }
    for (final name in seats.keys) {
      expect(seats[name]?.spec, registry.resolve('frontier'), reason: name);
      expect(seats[name]?.critic, registry.resolve('mid'), reason: name);
      expect(seats[name]?.gather, registry.resolve('cheap'), reason: name);
    }
  });

  test('the armed seat diverges ONLY on the type it arms', () {
    final seats = seatEnvironments();
    final power = seats['power_station']!;
    final genesis = seats['genesis']!;
    expect(power.spec, genesis.spec);
    expect(power.critic, genesis.critic);
    expect(power.gather, genesis.gather);
    expect(power.build, isNot(genesis.build));
  });

  test('a station whose delegate arms a different posture re-seats every '
      'unarmed seat (the override point drives the tree)', () {
    final delegate = _CheapEverywhereDelegate(gridRoot: '/home/memento/space');
    try {
      final seats = mountedValuesOf<MountedSubstationSeed>(delegate);
      final genesis = seats.firstWhere((s) => s.scope.name == 'genesis');
      final power = seats.firstWhere((s) => s.scope.name == 'power_station');
      expect(genesis.environments?.build, registry.resolve('cheap'));
      // The SEAT rung still wins over the station's, whatever the station arms.
      expect(power.environments?.build, registry.resolve('frontier'));
    } finally {
      delegate.dispose();
    }
  });

  test('the STATION posture is readable off an owned offline mount', () {
    final seats = codedSeatEnvironmentsOf(SpaceDelegate.new);
    expect(seats, isNotNull);
    expect(seats!.build, registry.resolve('codex-frontier'));
    expect(seats.spec, registry.resolve('frontier'));
    expect(seats.critic, registry.resolve('mid'));
    expect(seats.gather, registry.resolve('cheap'));
    expect(
      seats.describe(registry),
      'build codex  ·  spec frontier  ·  critic mid  ·  gather cheap',
    );
  });

  test(
    'the station mounts its NAMED environments, so a bead rung resolves',
    () {
      final delegate = SpaceDelegate(gridRoot: '/home/memento/space_station');
      try {
        expect(
          delegate.harnesses.names,
          containsAll(['frontier', 'codex-frontier']),
        );
        expect(delegate.agentConfig.harness, 'claude');
      } finally {
        delegate.dispose();
      }
    },
  );
}

/// A downstream station that overrides the CODED arming — the
/// extend-don't-fork seam this change makes real.
class _CheapEverywhereDelegate extends SpaceDelegate {
  _CheapEverywhereDelegate({required super.gridRoot});

  @override
  AgentArming get arming =>
      const AgentArming(build: BuildAgentEnvironment(kCheapLadder));
}
