/// `space assets install` — the COMPOSITION of the VENDED `assets` Command
/// group (`grid_assets`' [AssetsCommand]), never a new one.
///
/// The asset owns the domain AND its CLI component (the_grid ADR-0011 D3;
/// power_station ADR-0001): `grid_assets` ships the root-parametric overlay
/// installer ([OverlayInstallService] + the non-prescriptive
/// `extension_discovery` root walk) plus the THIN Command over it, and a station
/// COMPOSES that Command with ITS resident-station context. space's context is
/// [SpaceDelegate]: the `RawAssetGrid` root it authors IS the repo the overlay
/// lands on, and IS the `{{gridHome}}` every vended skill is rendered against.
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
    show AssetsCommand, OverlayInstallReport, OverlayInstallService;
import 'package:path/path.dart' as p;

import 'space_delegate.dart';

/// The verb the vended operator skills' `{{runner}}` holes render to. space is
/// JIT-only — there is deliberately no `space` binary (`CLAUDE.md`: "JIT only —
/// never AOT"), so the installed manual must teach the workspace-addressable
/// JIT invocation (`dart run space:space`, resolvable from the workspace
/// root), NEVER the runner's own executable name (`space`, the vended
/// `kDefaultOverlayRunner` the install reads off `runner.executableName`).
///
/// A downstream station overrides this per-install via
/// [buildSpaceAssetsCommand]'s `runnerInvocation` (e.g. `dart run
/// lunar:lunar`), so ITS installed manual teaches ITS runner.
const String kSpaceRunner = 'dart run space:space';

/// The vended [OverlayInstallService] with the ONE station-specific override:
/// it FORCES the overlay's `{{runner}}` arg to the station's JIT invocation
/// before the materializer renders and stamps.
///
/// The vended `AssetsInstallCommand.run()` binds `runner` off
/// `runner.executableName` (`space`); a station cannot rename its
/// `CommandRunner` without corrupting every other command's usage banner, so it
/// overrides the value at the single seam it owns — the injected service. A
/// THIN forward (one arg rewritten, everything else passed through), not a
/// re-implementation.
class _SpaceOverlayInstallService extends OverlayInstallService {
  const _SpaceOverlayInstallService([this.runnerInvocation = kSpaceRunner]);

  /// The JIT invocation rendered into every `{{runner}}` hole.
  final String runnerInvocation;

  @override
  Future<OverlayInstallReport> install({
    required List<String> overlayRoots,
    required String targetRoot,
    required String sourceRef,
    Map<String, String> args = const {},
    bool check = false,
  }) => super.install(
    overlayRoots: overlayRoots,
    targetRoot: targetRoot,
    sourceRef: sourceRef,
    // run() set args['runner'] = runner.executableName ('space'); overwrite it
    // with the JIT invocation. gridHome (and any other arg) rides through.
    args: {...args, 'runner': runnerInvocation},
    check: check,
  );
}

/// Builds the VENDED `assets` Command group curried with space's
/// resident-station context ([SpaceDelegate]).
///
/// [gridHomeDefault] resolves the home used when `--grid-home` is absent (the
/// real CWD; tests inject a fixture home). [service] is the vended install
/// service, [roots] the overlay-root resolver and [sourceRef] the
/// provenance-ref resolver — all three default to the vended implementations
/// (tests inject a fake overlay root and a fixed ref, so no `git` subprocess
/// runs). [runnerInvocation] is the JIT invocation rendered into the manual's
/// `{{runner}}` holes (a downstream station passes its own, e.g. `dart run
/// lunar:lunar`); it feeds the DEFAULT service only — an explicit [service]
/// owns its own runner arg. [delegateFactory] names WHICH [SpaceDelegate]
/// subclass authors the station (the base class absent: space's posture).
/// [out]/[err] default to the process sinks.
AssetsCommand buildSpaceAssetsCommand({
  String Function() gridHomeDefault = _currentDirectory,
  OverlayInstallService? service,
  String runnerInvocation = kSpaceRunner,
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
  Future<List<String>> Function(String gridHome)? roots,
  String Function(String overlayRoot)? sourceRef,
  StringSink? out,
  StringSink? err,
}) {
  service ??= _SpaceOverlayInstallService(runnerInvocation);
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
    service: service,
    roots: roots,
    sourceRef: sourceRef,
    out: out,
    err: err,
  );
  return command;
}

String _currentDirectory() => Directory.current.path;
