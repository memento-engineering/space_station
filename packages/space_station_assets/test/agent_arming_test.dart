import 'package:grid_assets/grid_assets.dart'
    show AgentConfig, AgentRole, EnvironmentRegistry;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// The ARMING value layer: memento's NAMED environments, the coded station
/// posture, and the two ladder applications. Pure + offline — no tree, no
/// process (the house rule: pure logic tested before IO is wired).
void main() {
  group('memento environments', () {
    final registry = buildMementoEnvironmentRegistry();

    test('the four semantic names are armed over the five builtins', () {
      expect(
        registry.names,
        containsAll(<String>[
          'cheap',
          'claude',
          'codex',
          'codex-frontier',
          'frontier',
          'mid',
        ]),
      );
    });

    test('every armed name RESOLVES and self-validates', () {
      for (final name in registry.names) {
        expect(registry.resolve(name).validate(), isNull, reason: name);
      }
    });

    test('the semantic names fold onto their builtin commands and models', () {
      expect(registry.resolve('frontier').command, 'claude');
      expect(registry.resolve('frontier').model, 'opus');
      expect(registry.resolve('mid').model, 'sonnet');
      expect(registry.resolve('cheap').model, 'haiku');
      // grid_assets 0.6.0-rc.6 drives codex through the ACP adapter, so the
      // builtin this name folds onto spawns the pinned adapter under `npx`
      // rather than a bare `codex` argv. The native model pin is unchanged.
      final codex = registry.resolve('codex-frontier');
      expect(codex.command, 'npx');
      expect(codex.args, ['-y', '@agentclientprotocol/codex-acp@1.6.2']);
      expect(codex.sessionAdapter, 'acp');
      expect(codex.model, 'gpt-5.6-sol');
    });
  });

  group('AgentArming', () {
    test('the coded station posture arms BUILD on codex, nothing else', () {
      expect(kMementoStationArming.roleEnvironments, {
        AgentRole.build: 'codex-frontier',
      });
      expect(kMementoStationArming.environment, isNull);
    });

    test('underlay FILLS an unarmed role rung', () {
      final resolved = kMementoStationArming.underlay(const AgentConfig());
      expect(resolved.roleEnvironments[AgentRole.build], 'codex-frontier');
    });

    test('underlay NEVER overwrites an armed rung (A20(2) no-wedge)', () {
      final resolved = kMementoStationArming.underlay(
        const AgentConfig(roleEnvironments: {AgentRole.build: 'claude'}),
      );
      expect(resolved.roleEnvironments[AgentRole.build], 'claude');
    });

    test('underlay leaves the ambient harness alone', () {
      final resolved = kMementoStationArming.underlay(
        const AgentConfig(harness: 'opencode'),
      );
      expect(resolved.harness, 'opencode');
    });

    test('applyTo OVERRIDES both axes (the seat rung)', () {
      const seat = AgentArming(
        environment: 'frontier',
        roleEnvironments: {AgentRole.build: 'frontier'},
      );
      final resolved = seat.applyTo(
        const AgentConfig(
          harness: 'claude',
          roleEnvironments: {AgentRole.build: 'codex-frontier'},
        ),
      );
      expect(resolved.harness, 'frontier');
      expect(resolved.roleEnvironments[AgentRole.build], 'frontier');
    });

    test('an empty arming is a no-op on both applications', () {
      const empty = AgentArming();
      const base = AgentConfig(harness: 'claude');
      expect(empty.isEmpty, isTrue);
      expect(empty.applyTo(base), base);
      expect(empty.underlay(base), base);
    });
  });

  group('roleArmingRefusal', () {
    final registry = buildMementoEnvironmentRegistry();

    test('the coded posture passes the boot-eager guard', () {
      final config = kMementoStationArming.underlay(const AgentConfig());
      expect(roleArmingRefusal(config, registry), isNull);
    });

    test('an unarmed role environment refuses LOUD, naming role and fix', () {
      final refusal = roleArmingRefusal(
        const AgentConfig(roleEnvironments: {AgentRole.build: 'nope'}),
        registry,
      );
      expect(refusal, isNotNull);
      expect(refusal, contains('build'));
      expect(refusal, contains('nope'));
      expect(refusal, contains('armed:'));
    });

    test('a config arming no role passes', () {
      expect(
        roleArmingRefusal(
          const AgentConfig(),
          const EnvironmentRegistry(custom: {}),
        ),
        isNull,
      );
    });
  });
}
