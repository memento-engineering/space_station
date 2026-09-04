/// `space assets install` — the COMPOSITION of the VENDED `assets` Command
/// group (`grid_assets`' [AssetsCommand]), never a new one.
///
/// The asset owns the domain AND its CLI component (the_grid ADR-0011 D3;
/// power_station ADR-0001): `grid_assets` ships the root-parametric overlay
/// installer ([OverlayInstallService] + the declaration-driven asset registry)
/// plus the THIN Command over it, and a station COMPOSES that Command with ITS
/// resident-station context. space's context is [SpaceDelegate]: the
/// `RawAssetGrid` root it authors IS the repo the overlay lands on, and IS the
/// `{{gridHome}}` every vended skill is rendered against.
/// Nothing about installing is reimplemented here — this file only curries the
/// delegate and guards the one input.
///
/// **The grid home.** `--grid-home` names it explicitly; absent, it is the CWD
/// — `space` is run FROM its grid home. A RELATIVE home is refused LOUD (exit
/// 64): the coded roster resolves its `../<repo>` seats against it (a relative
/// root surfaces as a raw `ArgumentError` out of the tree mount), and the
/// install RENDERS it into every asset it stamps — a relative `{{gridHome}}`
/// would be baked into the committed manual.
library;

import 'dart:io';

import 'package:grid_assets/grid_assets.dart'
    show
        AssetsCommand,
        FileSystemSubstationFactsRepository,
        GridAssetRosterOverride,
        OverlayInstallService,
        SubstationFactsRepository,
        SubstationFactsRepositoryFactory,
        SubstationKey;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import 'space_delegate.dart';

/// The verb [AssetsCommand.runnerInvocation] renders into the vended operator
/// skills' `{{runner}}` holes. space is JIT-only — there is deliberately no
/// `space` binary (`CLAUDE.md`: "JIT only — never AOT"), so the installed
/// manual must teach the workspace-addressable JIT invocation (`dart run
/// space:space`, resolvable from the workspace root), NEVER the runner's own
/// executable name.
///
/// A downstream station overrides this per-install via
/// [buildSpaceAssetsCommand]'s `runnerInvocation` (e.g. `dart run
/// lunar:lunar`), so ITS installed manual teaches ITS runner.
const String kSpaceRunner = 'dart run space:space';

/// Builds the VENDED `assets` Command group curried with space's
/// resident-station context ([SpaceDelegate]).
///
/// [gridHomeDefault] resolves the home used when `--grid-home` is absent (the
/// real CWD; tests inject a fixture home). [registry], [rosterOverride],
/// [factsRepository], and [service] are the vended declaration-driven install
/// seams; their defaults retain the generated registry, filesystem facts, and
/// real installer. [sourceRef] is the provenance-ref resolver (tests inject a
/// fixed ref, so no `git` subprocess runs). [runnerInvocation] is the JIT
/// invocation rendered into the manual's `{{runner}}` holes through
/// [AssetsCommand.runnerInvocation], the single vended seam for a station's JIT
/// invocation (a downstream station passes its own, e.g. `dart run
/// lunar:lunar`). [delegateFactory] names WHICH [SpaceDelegate] subclass
/// authors the station (the base class absent: space's posture).
/// [out]/[err] default to the process sinks.
AssetsCommand buildSpaceAssetsCommand({
  String Function() gridHomeDefault = _currentDirectory,
  sdk.GridAssetRegistry? registry,
  GridAssetRosterOverride? rosterOverride,
  SubstationFactsRepositoryFactory factsRepository = _fileFactsRepository,
  OverlayInstallService? service,
  String runnerInvocation = kSpaceRunner,
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
  String Function(String overlayRoot)? sourceRef,
  StringSink? out,
  StringSink? err,
}) {
  late final AssetsCommand command;
  command = AssetsCommand(
    delegate: () {
      // The home flag rides the `install` SUBCOMMAND (the umbrella parses no
      // args of its own), and the factory is called from inside its `run`.
      final install = command.subcommands['install']!;
      final flag = install.argResults?.option('grid-home')?.trim();
      final home = (flag == null || flag.isEmpty) ? gridHomeDefault() : flag;
      if (!p.isAbsolute(home)) {
        install.usageException(
          'space assets install: --grid-home must be an ABSOLUTE path (got '
          '"$home") — the install RENDERS the grid home into every asset it '
          'stamps, and the coded roster resolves its relative seats against '
          'it; a cwd-relative home would be baked into the committed manual.',
        );
      }
      // Installing reads asset packs and writes files; it spawns no agent.
      // The delegate's DEFAULT agent scope (the authoring-only claude rung,
      // ADR-0008 D10) rides — this authoring-only mount never reads it.
      return delegateFactory(gridRoot: p.normalize(home));
    },
    registry: registry,
    rosterOverride: rosterOverride,
    factsRepository: factsRepository,
    service: service ?? const OverlayInstallService(),
    runnerInvocation: runnerInvocation,
    sourceRef: sourceRef,
    out: out,
    err: err,
  );
  return command;
}

SubstationFactsRepository _fileFactsRepository({
  required Map<SubstationKey, String> roots,
  required sdk.GridAssetRegistry registry,
}) => FileSystemSubstationFactsRepository(roots: roots, registry: registry);

String _currentDirectory() => Directory.current.path;
