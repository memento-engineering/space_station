/// `space up` — RS-5b (tg-3s8.6, `the_grid/docs/SCRATCH-resident-station.md`
/// D-R1/D-C3): the resident station.
///
/// EXACTLY [CodeRunCommand]'s composed pieces (station flags MINUS any bead
/// flag — a resident verb takes no drive-list, ever, per D-R4/D-R1: the ready
/// frontier of the owned substation IS the drive set; a `--bead` would be a
/// trigger surface a misbehaving agent or a confused human could pull) —
/// boot-eager `AgentHarnessRegistry.validate`, `discoverWorkspaces` →
/// `buildControllers` → `buildLiveWiring` → the code asset's own
/// `ServiceBundle` (`GitSourceControl`) → `composeStation` + `wrapRoot`
/// mounting `InheritedSeed<AgentConfig>` + `InheritedSeed<AgentHarnessRegistry>`
/// → `driveStation` — but with [StationArgs.resident] ON so `driveStation`
/// arms RS-3 (the ready-frontier drive set), acquires the RS-2 station lock,
/// and binds the RS-4 `StationControl` surface. Foreground-resident: no
/// self-daemonization, no double-fork — the supervisor (launchd, RS-6) owns
/// backgrounding; `up` just parks on `driveStation`'s termination-signal wait
/// exactly like `run` does.
///
/// `run` ([CodeRunCommand]) stays byte-identical and untouched — it is
/// transitional scaffolding until RS-8 retires it (D-R1).
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentConfig,
        AgentHarnessRegistry,
        GitSourceControl,
        ModelTarget,
        OpenAiCompatible,
        ProviderManaged,
        SwiftInfer,
        buildAgentHarnessRegistry,
        buildCodeRegistry,
        kCodeCircuit;
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_controller/grid_controller.dart' show Bead;
import 'package:grid_engine/grid_engine.dart';

/// The bead→circuit policy for the `code` asset (mirrors [CodeRunCommand]'s
/// own private tear-off — all coding work roots the `code` circuit).
Circuit _codeCircuit(Bead bead) => kCodeCircuit;

/// `space up`: boots the resident station.
class UpCommand extends Command<int> {
  /// Creates the up command (the station flags MINUS `--bead`, plus the
  /// agent scope's — identical surface to [CodeRunCommand]'s).
  UpCommand() {
    _addResidentStationFlags(argParser);
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
      'Boot the resident station (RS-5b): the SAME composed pieces `run` '
      'assembles (validated harness scope, discovered workspaces, live '
      'wiring, the code asset\'s registry + git SourceControl), but ALWAYS '
      'resident — the ready frontier of the owned substation IS the drive '
      'set (RS-3; no --bead, ever), guarded by the ONE-supervisor-per-store '
      'lock (RS-2) and observable over the read-only StationControl surface '
      '(RS-4). Foreground-resident: no self-daemonization, no double-fork — '
      'a supervisor (launchd) owns backgrounding. Defaults to --dry-run '
      '(observe-only).';

  @override
  Future<int> run() async {
    final results = argResults!;
    final args = _residentStationArgsFrom(results);
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
    // releases them (the Dolt pool would otherwise keep the process alive —
    // the same station_runner.dart lesson CodeRunCommand carries).
    StationSources? sources;
    try {
      // --- the station-runner pieces, in order (the inversion) ---
      validateArming(args);
      final ws = discoverWorkspaces(
        workspacePath: args.workspacePath,
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

      // The asset's OWN per-substation services: the git SourceControl over
      // the leased execution machinery + registered root (provisioning works
      // even when LAND is off — gitOps/prOpener are non-null only when
      // --land armed a live run; null ⇒ canLand false ⇒ commit-only
      // posture).
      final services = ServiceBundle(
        sourceControl: GitSourceControl(
          gitOps: live.gitOps,
          prOpener: live.prOpener,
          provisioner: live.git,
          root: live.workRoot,
        ),
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
          ),
        ],
        git: live.git,
        workRoot: live.workRoot,
        groups: live.groups,
        freshnessBarrier: live.freshnessBarrier,
        resolver: const CircuitResolver(_codeCircuit),
        registry: buildCodeRegistry(devRoot: live.workRoot.path),
        services: services,
        // D-C rung 1: the asset mounts its station-default config VALUES as
        // ancestors of everything (Theme-of-context; the effect boundary
        // resolves the ladder per work).
        wrapRoot: (root) => InheritedSeed<AgentConfig>(
          value: agentConfig,
          child: InheritedSeed<AgentHarnessRegistry>(
            value: harnesses,
            child: root,
          ),
        ),
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

/// Adds the standard station flags MINUS `--bead` — a byte-for-byte mirror of
/// `grid_cli`'s `addStationFlags` (`station_runner.dart`) with the drive-list
/// flag omitted. A resident verb takes no drive-list, EVER (D-R1/D-R4): the
/// flag itself must not exist on `up`'s parser, not merely be refused at
/// arming time — a trigger surface a misbehaving agent could still discover
/// and pass. Kept in lockstep with `addStationFlags` by hand (`args.
/// ArgParser` has no "remove an option" API, so composing-then-stripping
/// isn't possible); a drift here is caught by `space up --help` review.
void _addResidentStationFlags(ArgParser parser) {
  parser
    ..addMultiOption(
      'substation',
      abbr: 'r',
      help:
          'An OWNED substation / ownership token (repeatable) — the SINGLE '
          'allow-set feeding both the ownership gate and the dispatch '
          'predicate. The dogfood substation is `tgdog`.',
    )
    ..addMultiOption(
      'owner',
      help: 'Alias for --substation; merged into one shared allow-set.',
    )
    ..addOption(
      'provider',
      allowed: ['subprocess', 'tmux'],
      defaultsTo: 'subprocess',
      help: 'The runtime provider for agent spawns.',
    )
    ..addOption(
      'root',
      help:
          'The registered worktree root checkout. Required to ARM a non-dry '
          'run; never created by the runner.',
    )
    ..addOption(
      'head',
      help:
          'ASSIGN the base branch per-bead worktrees cut from, overriding '
          'the probed origin/HEAD. Omit to probe.',
    )
    ..addOption(
      'workspace',
      abbr: 'w',
      help:
          'The beads workspace to read ready work from (a dir at or above a '
          '`.beads/`). Defaults to discovery from the cwd; read-only under '
          '--dry-run.',
    )
    ..addOption(
      'state-workspace',
      help:
          'A SEPARATE the_grid-owned beads workspace for its own session/'
          'lifecycle beads (A36/A37), so the --workspace source stays '
          'read-only. Omit to write sessions into --workspace.',
    )
    ..addOption(
      'state-substation',
      defaultsTo: 'tgdog',
      help:
          "the_grid's OWNED session partition (the --state-workspace "
          'prefix), unioned into the allow-set. Only used with '
          '--state-workspace.',
    )
    ..addFlag(
      'dry-run',
      defaultsTo: true,
      help:
          'Observe-only: NO writes, NO spawns (the SAFE DEFAULT). Pass '
          '--no-dry-run to ARM the live writing arm (requires --root).',
    )
    ..addFlag(
      'land',
      defaultsTo: false,
      negatable: false,
      help:
          'ARM the land step (ADR-0006 D3): on step-complete, commit → push '
          '→ open a PR (never auto-merges). OPT-IN, OFF by default; '
          'requires --no-dry-run.',
    )
    ..addOption(
      'for-seconds',
      help: 'Run for a fixed number of seconds then exit (scripted / CI).',
    )
    ..addFlag(
      'no-sql',
      negatable: false,
      help:
          'Force the bd-CLI read path even when pooled Dolt SQL is '
          'available.',
    )
    ..addOption(
      'control-port',
      defaultsTo: '0',
      help:
          'The StationControl loopback port (RS-4). 0 = ephemeral '
          '(default).',
    );
}

/// Builds [StationArgs] from the flags [_addResidentStationFlags] added —
/// [StationArgs.resident] is ALWAYS true and [StationArgs.targetBeads] is
/// ALWAYS empty (there is no `--bead` option on this parser to read from;
/// mirrors [StationArgs.from] otherwise).
StationArgs _residentStationArgsFrom(ArgResults args) {
  final seconds = args.option('for-seconds');
  return StationArgs(
    substations: <String>{
      ...args.multiOption('substation'),
      ...args.multiOption('owner'),
    }..removeWhere((r) => r.trim().isEmpty),
    provider: RuntimeProviderKind.parse(args.option('provider')),
    rootPath: args.option('root'),
    head: args.option('head'),
    workspacePath: args.option('workspace'),
    stateWorkspacePath: args.option('state-workspace'),
    stateSubstation: args.option('state-workspace') == null
        ? null
        : args.option('state-substation'),
    dryRun: args.flag('dry-run'),
    land: args.flag('land'),
    noSql: args.flag('no-sql'),
    runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
    resident: true,
    controlPort: int.parse(args.option('control-port')!),
  );
}
