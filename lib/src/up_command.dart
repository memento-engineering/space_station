/// `space up` — RS-5b (tg-3s8.6, `the_grid/docs/SCRATCH-resident-station.md`
/// D-R1/D-C3): the resident station.
///
/// The station flags MINUS any bead flag (a resident verb takes no
/// drive-list, ever, per D-R4/D-R1: the ready frontier of the owned
/// substation IS the drive set; a `--bead` would be a trigger surface a
/// misbehaving agent or a confused human could pull) — boot-eager
/// `AgentHarnessRegistry.validate`, `discoverWorkspaces` → `buildControllers`
/// → `buildLiveWiring` → the code asset's own per-substation `ServiceBundle`
/// (`GitSourceControl` over the DEFAULT root + EVERY EXTRA registered root,
/// tg-7gm — `sourceControlsByRoot`) → `composeStation` + `wrapRoot` mounting
/// `InheritedSeed<AgentConfig>` + `InheritedSeed<AgentHarnessRegistry>` →
/// `driveStation` — but with [StationArgs.resident] ON so `driveStation` arms
/// RS-3 (the ready-frontier drive set), acquires the RS-2 station lock, and
/// binds the RS-4 `StationControl` surface. Foreground-resident: no
/// self-daemonization, no double-fork — the supervisor (launchd, RS-6) owns
/// backgrounding; `up` just parks on `driveStation`'s termination-signal wait.
///
/// `run` (`CodeRunCommand`) is RETIRED (RS-8, tg-opp) — `up`'s composed
/// pieces are the only consumer left; this file is no longer a mirror of it.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show Bead;
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
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show GitOps, PrOpener, RootCheckout, StationGitService;

/// The bead→circuit policy for the `code` asset — all coding work roots the
/// `code` circuit.
Circuit _codeCircuit(Bead bead) => kCodeCircuit;

/// `space up`: boots the resident station.
class UpCommand extends Command<int> {
  /// Creates the up command (the station flags MINUS `--bead`, plus the
  /// agent scope's).
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
      'Boot the resident station (RS-5b): validated harness scope, '
      'discovered workspaces, live wiring, the code asset\'s registry + git '
      'SourceControl (per registered root, tg-7gm), but ALWAYS '
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
    // the same lesson station_runner.dart's own doc-comment example carries).
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

      // The asset's OWN per-substation services: the git SourceControl over
      // the leased execution machinery + EVERY registered root (tg-7gm) —
      // the owned substation's OWN name's entry is its DEFAULT root
      // ([live.workRoot]); any OTHER registered name is an EXTRA root a bead
      // opts into via its `metadata.grid.root`, resolved through
      // `ServiceBundle.sourceControlFor` (provisioning works even when LAND
      // is off — gitOps/prOpener are non-null only when --land armed a live
      // run; null ⇒ canLand false ⇒ commit-only posture).
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
            // boundary: an owned bead whose `metadata.grid.root` selection
            // isn't in this set is a LOUD per-bead skip, never a
            // station-wide gate. Empty (no --root at all) stays
            // UNCONSTRAINED — matches pre-multi-root behavior.
            registeredRoots: live.roots.keys.toSet(),
          ),
        ],
        git: live.git,
        workRoot: live.workRoot,
        groups: live.groups,
        freshnessBarrier: live.freshnessBarrier,
        resolver: const CircuitResolver(_codeCircuit),
        registry: buildCodeRegistry(devRoot: live.workRoot.path),
        // ONE substation composed (this resident verb owns exactly one), so
        // ITS bundle is the only entry — tg-7gm's `services` param is keyed
        // by `SubstationConfig.substationId`, not by root name.
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

/// Builds `composeStation`'s `services` map (tg-7gm) for the ONE substation
/// `up` composes: [defaultSubstation]'s entry carries a [GitSourceControl]
/// over [workRoot] as its DEFAULT `sourceControl`, plus one EXTRA
/// [GitSourceControl] per OTHER [roots] entry (every name but
/// [defaultSubstation] itself) under `sourceControlsByRoot` — the split
/// [ServiceBundle.sourceControlFor] resolves a bead's `metadata.grid.root`
/// against. [gitOps]/[prOpener] ride every constructed [GitSourceControl]
/// unchanged (non-null only when `--land` armed a live run; null ⇒ canLand
/// false ⇒ the commit-only posture) — pure construction, no I/O. Exposed
/// (no leading `_`) — RS-5b rework r2's seam for asserting the map's shape
/// without booting a real station; `run()` above is the only real call site.
Map<String, ServiceBundle> serviceBundleMapFor({
  required String defaultSubstation,
  required RootCheckout workRoot,
  required Map<String, RootCheckout> roots,
  required StationGitService provisioner,
  GitOps? gitOps,
  PrOpener? prOpener,
}) {
  final sourceControlsByRoot = <String, SourceControl>{
    for (final entry in roots.entries)
      if (entry.key != defaultSubstation)
        entry.key: GitSourceControl(
          gitOps: gitOps,
          prOpener: prOpener,
          provisioner: provisioner,
          root: entry.value,
        ),
  };
  return {
    defaultSubstation: ServiceBundle(
      sourceControl: GitSourceControl(
        gitOps: gitOps,
        prOpener: prOpener,
        provisioner: provisioner,
        root: workRoot,
      ),
      sourceControlsByRoot: sourceControlsByRoot,
    ),
  };
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
    ..addMultiOption(
      'root',
      help:
          'A registered worktree root checkout (repeatable, tg-7gm): '
          '`--root <name>=<path>[@head]` registers <path> under <name> — a '
          'name equal to an owned --substation becomes that substation\'s '
          'DEFAULT root; any OTHER name is an EXTRA root a bead opts into via '
          'its `metadata.grid.root` (e.g. a `tg` bead building `power_station` '
          'names `--root power_station=<path>` + `grid.root: power_station`). '
          'Bare `--root <path>` (no `=`) is the single-root shorthand — '
          'back-compatible: registers under the first --substation. At least '
          'one is required to ARM a non-dry run; never created by the runner.',
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
/// mirrors [StationArgs.from] otherwise, including its `--root` parse
/// (`<name>=<path>[@head]`, tg-7gm) into [StationArgs.roots]; the deprecated
/// `rootPath` alias is NOT used here).
StationArgs _residentStationArgsFrom(ArgResults args) {
  final seconds = args.option('for-seconds');
  final substations = <String>{
    ...args.multiOption('substation'),
    ...args.multiOption('owner'),
  }..removeWhere((r) => r.trim().isEmpty);
  final roots = <String, RootSpec>{};
  for (final raw in args.multiOption('root')) {
    if (raw.trim().isEmpty) continue;
    final entry = RootSpec.parse(
      raw,
      defaultName: substations.isNotEmpty ? substations.first : '',
    );
    if (roots.containsKey(entry.key)) {
      throw FormatException(
        'space up: --root "$raw" registers name "${entry.key}" more than '
        'once',
      );
    }
    roots[entry.key] = entry.value;
  }
  return StationArgs(
    substations: substations,
    provider: RuntimeProviderKind.parse(args.option('provider')),
    roots: roots,
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
