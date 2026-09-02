/// memento's grid station — the assembled runner (the Dart runner model — see
/// the_grid `docs/SCRATCH-dart-runner-and-cli-sdk.md`).
///
/// A station is a user-composed JIT runner: [buildRunner] assembles
/// the Commands memento wants — the generic CLI-SDK ones (watch/gate/demo)
/// from `grid_cli`, plus serve/lease ("leasing is core") from power_station's
/// `federated_grid_assets` (AL-5c, D-A9 — moved out of `grid_cli`), plus the
/// asset-exported [DartCommand] from the DART domain, plus memento's OWN
/// resident verbs (RS-5b, `the_grid/docs/SCRATCH-resident-station.md`):
/// `up`/`down`/`status`, plus the SEARCH asset's exported `search` Command,
/// composed with space's own resident-station context (`SpaceDelegate`) — the
/// coupled skill+command pattern (power_station ADR-0001).
///
/// Track G-space / H2 (tg-33n → tg-r81): the resident station is **authored as
/// a Seed** — [SpaceDelegate], a `grid_sdk` `GridDelegate` subclass carrying
/// space's v3 §2 composition tree and its OWN CLI surface (the hand-mirror of
/// `grid_cli`'s station flags is gone; absorbs tg-da7). H2 cut the last wrapper:
/// `up` now **drives the C/D-era pieces** — `runGrid(SpaceDelegate())` over
/// stores at roots — and nothing here imports the old station-runner kill-list
/// (`StationArgs` / `RootSpec` / `composeStation` / `driveStation` /
/// `serviceBundleMapFor`; DoD#6). `grid_cli` is consumed only for the four
/// re-seated verbs (watch/gate/rework/demo) + the RS-2/RS-4 lock/control/attach
/// survivors. The engine's `WorkList`/kernel binding into the tree (live work
/// driving) is the pending `runGrid`→kernel bridge — held for the human gate
/// (Track J); see `src/space_delegate.dart` / `src/up_command.dart`.
///
/// The thin runner app (`apps/space`, `dart run space:space`) drives it — JIT
/// only, never a compiled binary (space_station CLAUDE.md). The construction
/// lives here in the lib (not on the bin) so a test — or a downstream station
/// like an IC's private runner — can build and EXTEND the runner without
/// running it: `buildRunner(name: 'lunar', …)..addCommand(...)`.
library;

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart' show DartCommand;
import 'package:federated_grid_assets/federated_grid_assets.dart'
    show LeaseCommand, ServeCommand;
import 'package:grid_assets/grid_assets.dart'
    show
        CommandResult,
        ComputeBounds,
        DispatchCommand,
        computeDispatchHandler,
        kComputeKind;
// ignore: implementation_imports
import 'package:grid_cli/src/gate_command.dart' show GateCommand;
// ignore: implementation_imports
import 'package:grid_cli/src/reload_command.dart' show ReloadCommand;
// ignore: implementation_imports
import 'package:grid_cli/src/rework_command.dart' show ReworkCommand;
// ignore: implementation_imports
import 'package:grid_cli/src/watch_command.dart' show WatchCommand;

import 'src/assets_command.dart';
import 'src/down_command.dart';
import 'src/filing_commands.dart';
import 'src/link_commands.dart';
import 'src/search_command.dart';
import 'src/space_delegate.dart';
import 'src/status_command.dart';
import 'src/up_command.dart';

// The ARMING layer: the station's coded environments as COMPLETE const values,
// the canned preference ladders, the TYPED seat arming and the seed that
// mounts it. A downstream station overrides SpaceDelegate.environments/arming
// with these.
export 'src/agent_arming.dart'
    show
        AgentArming,
        SeatEnvironments,
        TypedEnvironmentProvider,
        buildMementoEnvironmentRegistry,
        kCheapEnvironment,
        kCheapLadder,
        kCodexFrontierEnvironment,
        kCodexLadder,
        kFrontierEnvironment,
        kFrontierLadder,
        kMementoEnvironments,
        kMementoStationArming,
        kMidEnvironment,
        kMidLadder,
        preferenceArmingRefusal;
// space_station authored as a Seed (Track G-space): the delegate the resident
// verbs re-seat over is part of the public library surface. A downstream
// station SUBCLASSES SpaceDelegate (the substations()/seat()/stationName/
// umbrella override points) and hands its constructor tear-off to
// [buildRunner] as a SpaceDelegateFactory. codedRosterOf is the owned
// (construct → mount → dispose) roster enumeration over that factory.
export 'src/space_delegate.dart'
    show
        NoteAppender,
        SpaceDelegate,
        SpaceDelegateFactory,
        codedArmingOf,
        codedRosterOf,
        codedRosterSnapshotOf,
        codedSeatEnvironmentsOf;
// The COMPOSED SEED (space-47t): the ONE per-substation seed class a
// station's substations() authors (value config: name/root/prefix + an
// optional GitHubAppConfig delivery identity). Exported so a downstream
// station's substations() override authors the same seeds. Raw stack assets
// are deliberately NOT exported: stations author seeds, not the local git
// asset or the imported github_grid_assets extension it composes.
export 'src/substation_seed.dart'
    show
        GitHubAppConfig,
        MountedSubstationSeat,
        MountedSubstationSeed,
        SubstationSeat,
        SubstationSeed;
// The composition site of the VENDED `assets` Command group — exported so a
// test (or a Flutter app) can build the seat with its seams injected.
// kSpaceRunner rides along so a downstream runner can reference the canonical
// JIT invocation it is overriding.
export 'src/assets_command.dart' show buildSpaceAssetsCommand, kSpaceRunner;
// The composition site of the VENDED `search` Command — exported so a test
// (or a Flutter app) can build the seat with its seams injected.
export 'src/search_command.dart' show buildSpaceSearchCommand;
// The composition site of the VENDED front-door pair (`filing`/`approve`) —
// exported so a test (or a Flutter app) can build the seat with its seams
// injected. storeRootForBead rides along: resolving a bead id to its owning
// seat's work store is the station-context half a downstream station reuses.
export 'src/filing_commands.dart'
    show SpaceFilingCommands, buildSpaceFilingCommands, storeRootForBead;
export 'src/link_commands.dart'
    show SpaceLinkCommands, buildSpaceLinkCommands, kSpaceStateStorePrefix;

/// Builds memento's `space` [CommandRunner]: the generic CLI-SDK commands plus
/// the power_station assets' exported Commands, with the COMPUTE asset's use
/// (bounded dispatch + its payload/result codec) assembled into the generic
/// serve/lease commands — the asset owns the "use" (ADR-0011 D3).
///
/// A downstream station extends this runner instead of forking it: [name] and
/// [description] rebrand the banner (`buildRunner(name: 'lunar', …)`);
/// [runnerInvocation] is the JIT invocation its installed manual teaches
/// (`dart run lunar:lunar`) — threaded into the composed `assets` seat so the
/// vended `{{runner}}` holes render to the DOWNSTREAM runner, not space's;
/// [delegateFactory] is the station-authorship seam — the constructor
/// tear-off of the station's [SpaceDelegate] SUBCLASS (identity, roster and
/// seat stacks live on the class as override points), threaded into the
/// resident verbs (`up`) and the station-context compositions
/// (`search`/`assets`). Absent, the base [SpaceDelegate] — space's posture.
/// [environment] is the PROCESS environment, handed in by the entrypoint
/// (`bin/space.dart` reads it from `dart:io` and passes it here). The assembly
/// never reads it ambiently — `no_watcher_no_gate_test` bans that under
/// `lib/`, gate or not — so an unfed runner arms the default posture and a
/// test feeds a literal map.
CommandRunner<int> buildRunner({
  String name = 'space',
  String description = "memento's grid station",
  String runnerInvocation = kSpaceRunner,
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
  Map<String, String> environment = const <String, String>{},
}) {
  final linkCommands = buildSpaceLinkCommands(delegateFactory: delegateFactory);
  // Unlike `link`, whose endpoint list must exist at PARSE time, the
  // front-door pair resolves its store from the bead id at RUN time — so this
  // builder mounts no tree and costs nothing at assembly.
  final filingCommands = buildSpaceFilingCommands(
    delegateFactory: delegateFactory,
  );
  return CommandRunner<int>(name, description)
    ..addCommand(WatchCommand())
    // memento's OWN resident verbs (RS-5b): the composed resident station
    // (up) + the thin StationAttach renders over it (down/status).
    ..addCommand(
      UpCommand(delegateFactory: delegateFactory, environment: environment),
    )
    ..addCommand(DownCommand())
    ..addCommand(StatusCommand())
    // The operator's EXPLICIT hot-reload trigger. `reload` talks to the
    // RESIDENT station over the VM service it advertised in its lock — it
    // starts no second station and watches no file. Generic and
    // asset-agnostic (it carries its own --grid-home/--restart flags and
    // injects its own client), so it is composed BARE — contrast `search`
    // below, which is curried with space's station context because the
    // ASSET's Command needs it.
    ..addCommand(ReloadCommand())
    // The SEARCH asset's exported CLI component, COMPOSED with space's
    // resident-station context — `space search <query>`: the deterministic,
    // read-only (A37) cross-store search the `discover` skill CALLS instead
    // of reinventing it by inference (the coupled skill+command pattern,
    // power_station ADR-0001). The logic is the asset's; this is the
    // last-mile composition.
    ..addCommand(buildSpaceSearchCommand(delegateFactory: delegateFactory))
    // The FILING asset's exported CLI components, COMPOSED with space's
    // resident-station context — `space filing <id>` (the deterministic
    // four-row front-door preflight the `discover` skill CALLS) and
    // `space approve --actor <name> <id>` (the operator's approval VERB: the
    // same preflight, then ONE stamped receipt on the work bead). Both take a
    // bead id and are curried with the roster that resolves WHICH seat's store
    // owns it (power_station ADR-0001, the coupled skill+command pattern).
    ..addCommand(filingCommands.filing)
    ..addCommand(filingCommands.approve)
    ..addCommand(linkCommands.link)
    ..addCommand(linkCommands.unlink)
    // The ASSETS domain's exported Command group, COMPOSED with space's
    // resident-station context — `space assets install`: the operator leg of
    // overlay delivery. It overlays the vended `station_overlay` onto THIS
    // repo's root, path-preserving and provenance-stamped, so the operator's
    // own manual (the skills, the governor agent-def, the harness settings)
    // is GENERATED from grid_assets rather than hand-copied here. NEVER
    // folded into `up` — installing the manual is an explicit act, the same
    // reason auto-reload was rejected.
    ..addCommand(
      buildSpaceAssetsCommand(
        runnerInvocation: runnerInvocation,
        delegateFactory: delegateFactory,
      ),
    )
    // The butane burn is TEMPORARILY decomposed (2026-07-02): the pack lives
    // in gc-owned butane_flutter, which is not yet migrated onto the Circuit
    // rename (the_grid #10 / power_station #4) — recompose `BurnRunCommand()`
    // when butane_grid_assets migrates (butane integration is deprioritized
    // per Nico's policy; the pack stays with its domain).
    // Asset-exported Commands consumed by a runner (the CLI-SDK model): the
    // DART domain ships DartCommand from dart_grid_assets; this app just
    // assembles it.
    ..addCommand(DartCommand())
    ..addCommand(GateCommand())
    ..addCommand(ReworkCommand())
    // serve/lease are GENERIC core commands ("leasing is core"); the
    // COMPUTE asset's use (bounded dispatch + its payload/result codec) is
    // assembled in here — the asset owns the "use" (ADR-0011 D3).
    ..addCommand(
      ServeCommand(
        defaultKind: kComputeKind,
        configureFlags: (parser) => parser
          ..addMultiOption(
            'allow',
            defaultsTo: const [
              'dart',
              'echo',
              'flutter',
              'git',
              'hostname',
              'melos',
              'uname',
            ],
            help:
                'The executables the lessor will run (the bounded-use '
                'allow-list). A dispatched command not on this list is '
                'REFUSED (no shell-as-a-service; ADR-0011 RCE-bounds).',
          )
          ..addOption(
            'exec-timeout',
            defaultsTo: '300',
            help:
                'Per-command timeout in seconds (the bounded-use upper '
                'bound).',
          ),
        handlerFor: (args, log) {
          final bounds = ComputeBounds(
            allowedCommands: args.multiOption('allow').toSet(),
            timeout: Duration(seconds: int.parse(args.option('exec-timeout')!)),
          );
          return (
            handler: computeDispatchHandler(bounds: bounds, onLog: log),
            banner:
                'bounded use: allow-list '
                '${bounds.allowedCommands.toList()..sort()}  ·  '
                'timeout ${bounds.timeout.inSeconds}s',
            // Compute launches nothing that outlives a dispatch — no
            // lease-end teardown (the burn's lessor, by contrast, reaps
            // its follower app here).
            onLeaseEnded: null,
          );
        },
      ),
    )
    ..addCommand(
      LeaseCommand(
        defaultKind: kComputeKind,
        payloadFor: (rest) => DispatchCommand(
          command: rest.first,
          args: rest.skip(1).toList(),
        ).toJson(),
        render: (raw, out, err) {
          final r = CommandResult.fromJson(raw);
          if (r.stdout.isNotEmpty) out(r.stdout);
          if (r.stderr.isNotEmpty) err(r.stderr);
          return r.exitCode;
        },
      ),
    );
}
