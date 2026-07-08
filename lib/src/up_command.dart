/// `space up` — RS-5b (`the_grid/docs/SCRATCH-resident-station.md` D-R1/D-C3):
/// the resident station, re-seated over [SpaceDelegate] (Track G-space).
///
/// `up` no longer hand-mirrors `grid_cli`'s station-runner flags. It authors a
/// [SpaceDelegate] — space_station as a Seed (the v3 §2 tree) — from its OWN
/// flag surface ([addSpaceStationFlags] / [spaceStationArgsFrom], in
/// `space_delegate.dart`), and drives it. The station flags are space's own and
/// take NO `--bead` (a resident verb has no drive-list, EVER — D-R4/D-R1: the
/// ready frontier of the owned substation IS the drive set).
///
/// The pieces, in order (the inversion): boot-eager `AgentHarnessRegistry`
/// validation → `discoverWorkspaces` → `buildControllers` → `buildLiveWiring` →
/// author the [SpaceDelegate] over the live git machinery → drive its ASSET
/// SEAM ([SpaceDelegate.circuitResolver] / [SpaceDelegate.codeRegistry] /
/// [SpaceDelegate.wrapRoot] + [serviceBundleMapFor]) through `composeStation`
/// with `resident: true` → `driveStation` (arms RS-3, acquires the RS-2 lock,
/// binds the RS-4 control surface, parks on the termination signal).
/// Foreground-resident: no self-daemonization, no double-fork — the supervisor
/// (launchd, RS-6) owns backgrounding.
///
/// The remaining transitional seam (honest scope): the v3 end-state is `up`
/// driving by `runGrid(SpaceDelegate())` — mounting [SpaceDelegate.build]
/// directly. That needs the composition tree bound to the engine's live driving
/// (`StationKernel` / `WorkList` / lock), which lives in `grid_sdk` /
/// `grid_engine` (the private engine). Until it lands, `up` drives through
/// `grid_cli`'s primitives, sourced from the delegate — see `space_delegate.dart`.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentConfig,
        ModelTarget,
        OpenAiCompatible,
        ProviderManaged,
        SwiftInfer,
        buildAgentHarnessRegistry;
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart' show SubstationConfig;

import 'space_delegate.dart';

/// `space up`: boots the resident station.
class UpCommand extends Command<int> {
  /// Creates the up command (space's own station flags MINUS `--bead`, plus the
  /// agent scope's).
  UpCommand() {
    addSpaceStationFlags(argParser);
    argParser
      ..addOption(
        'harness',
        defaultsTo: 'claude',
        allowed: ['claude', 'copilot', 'pi', 'opencode'],
        help:
            'The agentic harness coding work runs on (the station default; a '
            'bead may override via its grid.agent envelope, a step via '
            'params).',
      )
      ..addOption(
        'model',
        help:
            'The model a managed tool selects (claude/copilot) or an '
            'endpoint harness requests — rides AgentConfig.params, not the '
            'target.',
      )
      ..addOption(
        'openai-base',
        help:
            'An OpenAI-compatible inference endpoint (e.g. a llama.cpp '
            'server) — sets the model target for pi/opencode.',
      )
      ..addOption(
        'swift-base',
        help: 'A swift-infer server endpoint — sets the model target for pi.',
      );
  }

  @override
  final String name = 'up';

  @override
  final String description =
      'Boot the resident station (RS-5b), authored as a SpaceDelegate: '
      'validated harness scope, discovered workspaces, live wiring, and the '
      'code asset\'s per-substation git — but ALWAYS resident: the ready '
      'frontier of the owned substation IS the drive set (RS-3; no --bead, '
      'ever), guarded by the ONE-supervisor-per-store lock (RS-2) and '
      'observable over the read-only StationControl surface (RS-4). '
      'Foreground-resident: no self-daemonization, no double-fork — a '
      'supervisor (launchd) owns backgrounding. Defaults to --dry-run '
      '(observe-only).';

  @override
  Future<int> run() async {
    final results = argResults!;
    final args = spaceStationArgsFrom(results);
    final out = _out;
    final err = _err;

    // --- the station-default agent scope (D-C rung 1) + boot-eager
    // validation (OQ-c moment 1: a misconfigured MACHINE fails loud before
    // any work mounts; a misconfigured BEAD fails per-work at resolution).
    final openaiBase = results.option('openai-base');
    final swiftBase = results.option('swift-base');
    if (openaiBase != null && swiftBase != null) {
      err('space up: pass --openai-base OR --swift-base, not both.');
      return 64;
    }
    final ModelTarget target;
    try {
      target = openaiBase != null
          ? OpenAiCompatible(_parseBase(openaiBase, '--openai-base'))
          : swiftBase != null
          ? SwiftInfer(_parseBase(swiftBase, '--swift-base'))
          : const ProviderManaged();
    } on FormatException catch (e) {
      err('space up: ${e.message}');
      return 64;
    }
    final model = results.option('model');
    final agentConfig = AgentConfig(
      harness: results.option('harness') ?? 'claude',
      target: target,
      params: {if (model != null) 'model': model},
    );
    final harnesses = buildAgentHarnessRegistry();
    final invalid = harnesses.validate(agentConfig);
    if (invalid != null) {
      err('space up: $invalid');
      return 64;
    }

    // Held outside the try so a refusal AFTER the controllers exist still
    // releases them (the Dolt pool would otherwise keep the process alive).
    StationSources? sources;
    try {
      // --- the station-runner pieces, in order (the inversion) ---
      validateArming(args);
      final ws = discoverWorkspaces(
        workspaces: args.workspaces,
        defaultSubstation: args.substations.first,
        stateWorkspacePath: args.stateWorkspacePath,
      );
      sources = await buildControllers(
        work: ws.work,
        state: ws.state,
        noSql: args.noSql,
      );
      final live = await buildLiveWiring(
        args: args,
        sources: sources,
        onRefusal: out,
      );

      // --- space_station AS A SEED: author the delegate over the live git
      // machinery. Its per-substation `GitGridAssets` (Track F) are the v3
      // successor to the `serviceBundleMapFor` map below; both describe the
      // SAME per-substation source control (the delegate authors the tree, the
      // map feeds the primitive drive until `up` drives through runGrid).
      final delegate = SpaceDelegate(
        gridRoot: live.workRoot.path,
        stationName: 'space',
        substations: [
          for (final entry in live.roots.entries)
            SpaceSubstation(name: entry.key, root: entry.value),
        ],
        agentConfig: agentConfig,
        harnesses: harnesses,
        provisioner: live.git,
        gitOps: live.gitOps,
        prOpener: live.prOpener,
      );

      // The asset's OWN per-substation services (tg-7gm): the git SourceControl
      // over the leased execution machinery + EVERY registered root — the
      // owned substation's DEFAULT root ([live.workRoot]) plus any OTHER
      // registered name a bead opts into (gitOps/prOpener are non-null only
      // when --land armed a live run; null ⇒ canLand false ⇒ commit-only).
      final services = serviceBundleMapFor(
        defaultSubstation: args.substations.first,
        workRoot: live.workRoot,
        roots: live.roots,
        provisioner: live.git,
        gitOps: live.gitOps,
        prOpener: live.prOpener,
      );

      final wiring = composeStation(
        work: sources.work,
        state: sources.state,
        stationServices: live.stationServices,
        substations: [
          SubstationConfig(
            substationId: args.substations.first,
            ownedSubstations: args.substations,
            // A resident station takes no drive-list, ever (D-R4) — the
            // engine's own narrowing to driveable-work TYPES (task/bug/
            // feature/chore) rides `resident`, never `driveList`.
            resident: true,
            // The registered root NAMES (tg-7gm) gate `WorkList`'s mount
            // boundary: an owned bead whose root selection isn't in this set
            // is a LOUD per-bead skip, never a station-wide gate. Empty (no
            // --root) stays UNCONSTRAINED.
            registeredRoots: live.roots.keys.toSet(),
          ),
        ],
        git: live.git,
        workRoot: live.workRoot,
        groups: live.groups,
        freshnessBarrier: live.freshnessBarrier,
        // The ASSET SEAM, owned by the delegate (ADR-0008 D1).
        resolver: delegate.circuitResolver,
        registry: delegate.codeRegistry(live.workRoot.path),
        services: services,
        // D-C rung 1: the delegate mounts its station-default config VALUES as
        // ancestors of everything (Theme-of-context; the effect boundary
        // resolves the ladder per work).
        wrapRoot: delegate.wrapRoot,
      );

      out(
        'agent scope: harness ${agentConfig.harness} → ${agentConfig.target}'
        '${model != null ? '  ·  model $model' : ''}',
      );
      return await driveStation(
        wiring: wiring,
        sources: sources,
        args: args,
        out: out,
      );
    } on StationRefusal catch (refusal) {
      await sources?.shutdown();
      err(refusal.message);
      return refusal.code;
    }
  }

  void _out(String message) => stdout.writeln(message);
  void _err(String message) => stderr.writeln(message);
}

Uri _parseBase(String raw, String flag) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) {
    throw FormatException('$flag is not an absolute url: "$raw"');
  }
  return uri;
}
