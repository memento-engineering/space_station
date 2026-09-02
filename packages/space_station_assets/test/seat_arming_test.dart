import 'package:grid_assets/grid_assets.dart'
    show AgentConfig, AgentRole, mountedValuesOf;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// The PER-SUBSTATION rung, PROVED in the tree. ADR-0008 Decision 10 claimed
/// the agent config was "overridable per-substation" and no seat ever nested
/// its own provider; these mount the REAL coded station offline and read each
/// seat's resolved config off the projection its own subtree provides.
void main() {
  Map<String, AgentConfig?> seatConfigs() {
    final delegate = SpaceDelegate(gridRoot: '/home/memento/space_station');
    try {
      return {
        for (final seat in mountedValuesOf<MountedSubstationSeed>(delegate))
          seat.scope.name: seat.agentConfig,
      };
    } finally {
      delegate.dispose();
    }
  }

  test('the ARMED seat shadows the station: power_station builds on frontier '
      'while every other coded seat rides the coded codex posture', () {
    final configs = seatConfigs();
    expect(configs.keys, hasLength(6));
    expect(
      configs['power_station']?.roleEnvironments[AgentRole.build],
      'frontier',
    );
    for (final name in configs.keys.where((n) => n != 'power_station')) {
      expect(
        configs[name]?.roleEnvironments[AgentRole.build],
        'codex-frontier',
        reason: name,
      );
    }
  });

  test('the armed seat diverges ONLY on the rung it arms — its ambient '
      'environment is still the station default', () {
    final configs = seatConfigs();
    expect(configs['power_station']?.harness, configs['genesis']?.harness);
  });

  test('a station whose delegate arms a different posture re-seats every '
      'unarmed seat (the override point drives the tree)', () {
    final delegate = _CodexEverywhereDelegate(gridRoot: '/home/memento/space');
    try {
      final seats = mountedValuesOf<MountedSubstationSeed>(delegate);
      final genesis = seats.firstWhere((s) => s.scope.name == 'genesis');
      final power = seats.firstWhere((s) => s.scope.name == 'power_station');
      expect(genesis.agentConfig?.roleEnvironments[AgentRole.grade], 'cheap');
      // The SEAT rung still wins over the station's, whatever the station arms.
      expect(power.agentConfig?.roleEnvironments[AgentRole.build], 'frontier');
    } finally {
      delegate.dispose();
    }
  });

  test(
    'the station mounts its NAMED environments, so a seat rung resolves',
    () {
      final delegate = SpaceDelegate(gridRoot: '/home/memento/space_station');
      try {
        expect(
          delegate.harnesses.names,
          containsAll(['frontier', 'codex-frontier']),
        );
        expect(
          delegate.agentConfig.roleEnvironments[AgentRole.build],
          'codex-frontier',
        );
      } finally {
        delegate.dispose();
      }
    },
  );
}

/// A downstream station that overrides the CODED arming — the extend-don't-fork
/// seam this change makes real.
class _CodexEverywhereDelegate extends SpaceDelegate {
  _CodexEverywhereDelegate({required super.gridRoot});

  @override
  AgentArming get arming => const AgentArming(
    roleEnvironments: {
      AgentRole.build: 'codex-frontier',
      AgentRole.grade: 'cheap',
    },
  );
}
