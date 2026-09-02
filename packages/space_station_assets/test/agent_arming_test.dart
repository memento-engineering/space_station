import 'package:grid_assets/grid_assets.dart'
    show
        AgentEnvironment,
        AvailableEnvironments,
        BaseScope,
        BuildAgentEnvironment,
        CriticAgentEnvironment,
        CriticLane,
        EnvBaseRef,
        GatherAgentEnvironment,
        SpecAgentEnvironment,
        kBuiltinEnvironments;
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

/// The ARMING value layer: memento's COMPLETE const environments, the canned
/// preference ladders, the coded station posture and the boot-eager guard.
/// Pure + offline — no tree, no process (the house rule: pure logic tested
/// before IO is wired).
void main() {
  final registry = buildMementoEnvironmentRegistry();

  group('memento environments', () {
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

    test('the semantic names fold onto their commands and models', () {
      expect(registry.resolve('frontier').command, 'claude');
      expect(registry.resolve('frontier').model, 'opus');
      expect(registry.resolve('mid').model, 'sonnet');
      expect(registry.resolve('cheap').model, 'haiku');
      final codex = registry.resolve('codex-frontier');
      expect(codex.command, 'npx');
      expect(codex.args, ['-y', '@agentclientprotocol/codex-acp@1.6.2']);
      expect(codex.sessionAdapter, 'acp');
      expect(codex.model, 'gpt-5.6-sol');
    });

    test('each environment IS its own normal form, so a const preference over '
        'it is PRESENT (the property ADR-0006 D1 rests on)', () {
      final present = AvailableEnvironments.fromRegistry(registry);
      for (final entry in kMementoEnvironments.entries) {
        expect(
          registry.resolve(entry.key),
          entry.value.flattened,
          reason: entry.key,
        );
        expect(present.contains(entry.value), isTrue, reason: entry.key);
        expect(registry.nameOf(entry.value), isNotEmpty, reason: entry.key);
      }
    });

    test('TRANSPORT PARITY with the builtins — a grid_assets bump that changes '
        'a builtin turns this RED instead of drifting silently', () {
      final claude = kBuiltinEnvironments['claude']!;
      for (final value in <AgentEnvironment>[
        kFrontierEnvironment,
        kMidEnvironment,
        kCheapEnvironment,
      ]) {
        expect(value.command, claude.command);
        expect(value.args, claude.args);
        expect(value.promptMode, claude.promptMode);
        expect(value.promptFlag, claude.promptFlag);
        expect(value.target, claude.target);
        expect(value.usageJsonArgs, claude.usageJsonArgs);
        expect(value.resumeFlag, claude.resumeFlag);
        expect(value.sessionAdapter, claude.sessionAdapter);
        expect(value.env, claude.env);
      }
      expect(
        kCodexFrontierEnvironment.flattened,
        kBuiltinEnvironments['codex']!.flattened,
      );
    });
  });

  group('AgentArming', () {
    test('the coded station posture arms all FOUR typed seats', () {
      expect(
        kMementoStationArming.build,
        const BuildAgentEnvironment(kCodexLadder),
      );
      expect(
        kMementoStationArming.spec,
        const SpecAgentEnvironment(kFrontierLadder),
      );
      expect(
        kMementoStationArming.critic,
        const CriticAgentEnvironment(kMidLadder),
      );
      expect(
        kMementoStationArming.gather,
        const GatherAgentEnvironment(kCheapLadder),
      );
      expect(kMementoStationArming.isEmpty, isFalse);
      expect(kMementoStationArming.seats, hasLength(4));
      expect(kMementoStationArming.seats.first, isA<BuildAgentEnvironment>());
    });

    test('an empty arming says nothing', () {
      expect(const AgentArming().isEmpty, isTrue);
      expect(const AgentArming().seats, isEmpty);
    });

    test('a seat arming naming ONE type equals itself and not the station', () {
      const seat = AgentArming(build: BuildAgentEnvironment(kFrontierLadder));
      expect(
        seat,
        const AgentArming(build: BuildAgentEnvironment(kFrontierLadder)),
      );
      expect(seat, isNot(kMementoStationArming));
    });
  });

  group('preferenceArmingRefusal', () {
    test('the coded posture passes the boot-eager guard', () {
      expect(preferenceArmingRefusal(kMementoStationArming, registry), isNull);
    });

    test('a base-layered entry refuses LOUD, naming the SEAT TYPE', () {
      // The pre-migration shape of `frontier`: it INHERITS its transport from
      // the builtin, so it is not its own normal form and matches nothing.
      const layered = AgentEnvironment(
        base: EnvBaseRef('claude', scope: BaseScope.builtin),
        model: 'opus',
      );
      final refusal = preferenceArmingRefusal(
        const AgentArming(build: BuildAgentEnvironment([layered])),
        registry,
      );
      expect(refusal, isNotNull);
      expect(refusal, contains('BuildAgentEnvironment'));
      expect(refusal, contains('normal form'));
    });

    test('an EMPTY armed preference refuses LOUD', () {
      final refusal = preferenceArmingRefusal(
        const AgentArming(spec: SpecAgentEnvironment([])),
        registry,
      );
      expect(refusal, isNotNull);
      expect(refusal, contains('SpecAgentEnvironment'));
      expect(refusal, contains('EMPTY'));
    });

    test('a critic LANE override is walked too', () {
      const layered = AgentEnvironment(
        base: EnvBaseRef('claude', scope: BaseScope.builtin),
        model: 'opus',
      );
      final refusal = preferenceArmingRefusal(
        AgentArming(
          critic: CriticAgentEnvironment(
            kMidLadder,
            lanes: {
              CriticLane('adr-alignment'): [layered],
            },
          ),
        ),
        registry,
      );
      expect(refusal, isNotNull);
      expect(refusal, contains('CriticAgentEnvironment'));
    });

    test('an arming that arms nothing passes', () {
      expect(preferenceArmingRefusal(const AgentArming(), registry), isNull);
    });
  });
}
