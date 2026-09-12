import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        BuildAgentEnvironment,
        CriticAgentEnvironment,
        GatherAgentEnvironment,
        SpecAgentEnvironment,
        mountedValuesOf;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// The station-default and per-substation provider seeds, proved in the real
/// tree. The type is the scope: a nested provider shadows only its exact seat
/// type and only inside the substation it wraps.
void main() {
  final registry = buildMementoEnvironmentRegistry();

  Map<String, SeatEnvironments?> seatEnvironmentsBySubstation(
    SpaceDelegate delegate,
  ) {
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

  test('SpaceDelegate mounts one provider seed per station preference', () {
    final snapshot = codedSeatEnvironmentsOf(_TwoSubstationDelegate.new);

    expect(
      snapshot.preferences.take(4),
      orderedEquals(const <SeatPreference>[
        BuildAgentEnvironment(kCheapLadder),
        SpecAgentEnvironment(kFrontierLadder),
        CriticAgentEnvironment(kMidLadder),
        GatherAgentEnvironment(kCheapLadder),
      ]),
    );
    expect(
      snapshot.preferences.map((seat) => seat.runtimeType),
      orderedEquals(<Type>[
        BuildAgentEnvironment,
        SpecAgentEnvironment,
        CriticAgentEnvironment,
        GatherAgentEnvironment,
        BuildAgentEnvironment,
      ]),
      reason: 'the child-only build provider follows the four station seeds',
    );
  });

  test('substation seat seed shadows only its subtree', () {
    final bySubstation = seatEnvironmentsBySubstation(
      _TwoSubstationDelegate(gridRoot: '/home/memento/space'),
    );
    final overridden = bySubstation['overridden']!;
    final sibling = bySubstation['sibling']!;

    expect(overridden.build, registry.resolve('frontier'));
    expect(sibling.build, registry.resolve('cheap'));
    expect(overridden.spec, sibling.spec);
    expect(overridden.critic, sibling.critic);
    expect(overridden.gather, sibling.gather);
    expect(sibling.spec, registry.resolve('frontier'));
    expect(sibling.critic, registry.resolve('mid'));
    expect(sibling.gather, registry.resolve('cheap'));
  });

  test('the real coded power_station exception overrides build only', () {
    final bySubstation = seatEnvironmentsBySubstation(
      SpaceDelegate(gridRoot: '/home/memento/space_station'),
    );
    expect(bySubstation.keys, hasLength(7));
    final power = bySubstation['power_station']!;
    final genesis = bySubstation['genesis']!;

    expect(power.build, registry.resolve('frontier'));
    expect(genesis.build, registry.resolve('codex-frontier'));
    expect(power.spec, genesis.spec);
    expect(power.critic, genesis.critic);
    expect(power.gather, genesis.gather);
  });

  test('the coded snapshot carries the station projection and preferences', () {
    final snapshot = codedSeatEnvironmentsOf(SpaceDelegate.new);
    final station = snapshot.station;

    expect(station, isNotNull);
    expect(station!.build, registry.resolve('codex-frontier'));
    expect(station.spec, registry.resolve('frontier'));
    expect(station.critic, registry.resolve('mid'));
    expect(station.gather, registry.resolve('cheap'));
    expect(
      station.describe(snapshot.registry),
      'build codex  ·  spec frontier  ·  critic mid  ·  gather cheap',
    );
    expect(snapshot.preferences, hasLength(5));
    expect(
      snapshot.registry.names,
      containsAll(['frontier', 'codex-frontier']),
    );
  });
}

class _TwoSubstationDelegate extends SpaceDelegate {
  _TwoSubstationDelegate({
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
  List<SingleChildSeed> seatSeeds(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => const <SeatPreference>[
    BuildAgentEnvironment(kCheapLadder),
    SpecAgentEnvironment(kFrontierLadder),
    CriticAgentEnvironment(kMidLadder),
    GatherAgentEnvironment(kCheapLadder),
  ].map((seat) => seat.provider()).toList();

  @override
  List<Seed> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    SubstationSeed(
      name: 'overridden',
      root: '../overridden',
      seatSeeds: [const BuildAgentEnvironment(kFrontierLadder).provider()],
    ),
    SubstationSeed(name: 'sibling', root: '../sibling'),
  ];
}
