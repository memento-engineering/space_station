import 'package:grid_assets/grid_assets.dart'
    show BuildAgentEnvironment, mountedValuesOf;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// The PER-SUBSTATION rung, PROVED in the tree. These mount the REAL coded
/// station offline and read each substation's TYPED resolution off the
/// projection its own subtree provides (ADR-0002 D5, ADR-0006 D2).
void main() {
  final registry = buildMementoEnvironmentRegistry();

  Map<String, SeatEnvironments?> seatEnvironmentsBySubstation() {
    final delegate = SpaceDelegate(gridRoot: '/home/memento/space_station');
    try {
      return {
        for (final substation in mountedValuesOf<MountedSubstationSeed>(
          delegate,
        ))
          substation.scope.name: substation.environments,
      };
    } finally {
      delegate.dispose();
    }
  }

  test('every coded substation resolves all four typed lookups; power_station '
      'BUILDS on frontier while every other substation rides the coded codex '
      'posture', () {
    final bySubstation = seatEnvironmentsBySubstation();
    expect(bySubstation.keys, hasLength(7));
    expect(bySubstation['power_station']?.build, registry.resolve('frontier'));
    for (final name in bySubstation.keys.where((n) => n != 'power_station')) {
      expect(
        bySubstation[name]?.build,
        registry.resolve('codex-frontier'),
        reason: name,
      );
    }
    for (final name in bySubstation.keys) {
      expect(
        bySubstation[name]?.spec,
        registry.resolve('frontier'),
        reason: name,
      );
      expect(bySubstation[name]?.critic, registry.resolve('mid'), reason: name);
      expect(
        bySubstation[name]?.gather,
        registry.resolve('cheap'),
        reason: name,
      );
    }
  });

  test('the armed substation diverges ONLY on the type it arms', () {
    final bySubstation = seatEnvironmentsBySubstation();
    final power = bySubstation['power_station']!;
    final genesis = bySubstation['genesis']!;
    expect(power.spec, genesis.spec);
    expect(power.critic, genesis.critic);
    expect(power.gather, genesis.gather);
    expect(power.build, isNot(genesis.build));
  });

  test('a station whose delegate arms a different posture re-resolves every '
      'unarmed substation (the override point drives the tree)', () {
    final delegate = _CheapEverywhereDelegate(gridRoot: '/home/memento/space');
    try {
      final substations = mountedValuesOf<MountedSubstationSeed>(delegate);
      final genesis = substations.firstWhere((s) => s.scope.name == 'genesis');
      final power = substations.firstWhere(
        (s) => s.scope.name == 'power_station',
      );
      expect(genesis.environments?.build, registry.resolve('cheap'));
      // The SUBSTATION rung still wins over the station's, whatever the
      // station arms.
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
