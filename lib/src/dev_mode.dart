/// space's DEV-MODE seat — the host half of the EXPLICIT hot-reload trigger.
///
/// The station's RUN MODE is the whole gate: a JIT station started with
/// `--enable-vm-service` reports a VM service, so `up` composes
/// `grid_exploration`'s optional [ReassembleTool] into a [GridExplorationHost] —
/// the SOLE registrar of `ext.exploration.*` — and `ext.exploration.grid.reload`
/// exists for `space reload` to invoke. An AOT binary (or a JIT one launched
/// without the flag) reports no VM service, so nothing is composed and the
/// client classifies the station not-dev-mode.
///
/// There is NO hostname allowlist, NO env var, NO flag, NO config — and NO
/// filesystem watcher: an auto-reload-on-save would fire mid-build on a resident
/// station that is committing and opening PRs. The operator triggers the reload,
/// explicitly, by typing `space reload`.
library;

import 'package:beads_dart/beads_dart.dart'
    show GraphSnapshot, GridControllerRuntime, SnapshotReader;
import 'package:grid_exploration/grid_exploration.dart'
    show GridControllerPlugin, GridExplorationHost, ReassembleTool;
import 'package:grid_sdk/grid_sdk.dart' show GridHandle;

/// Reads the station's ALREADY-JOINED work graph — what the bridge last pushed,
/// the same snapshot `space up`'s `/status` view renders (D-H rule 2: never a
/// notifier's reactive state).
///
/// This is why the dev-mode host opens NO second controller over the substation
/// stores: `buildStationWork` already owns one per store, and re-opening them
/// would double every read AND arm a second set of dirty sources. The host reads
/// the join the station already has, and carries no dirty source of its own.
class JoinedWorkReader implements SnapshotReader {
  /// Creates the reader over the station's [latest] joined graph.
  const JoinedWorkReader(this.latest);

  /// The station's current joined work graph (`StationWorkRuntime.latest.graph`).
  final GraphSnapshot Function() latest;

  @override
  Future<GraphSnapshot> read() async => latest();
}

/// The composed dev-mode seat: the exploration host, the read-only controller it
/// answers observation tools from, and the VM-service URI the station advertises.
class DevModeSeat {
  DevModeSeat._(this.host, this.runtime, this.vmServiceUri);

  /// The sole registrar, carrying the dev-mode contributor.
  final GridExplorationHost host;

  /// The controller the host's five read-only tools observe through.
  final GridControllerRuntime runtime;

  /// The URI `space reload` connects to — advertised in the 0600 station lock
  /// (it carries the service auth code).
  final String vmServiceUri;

  /// Registers the extensions on the VM service. `up` calls this ONCE; a test
  /// never does (a second `registerExtension` of the same method on one isolate
  /// throws), which is why [armDevMode] does not call it.
  void register() => host.register();

  /// Tears the seat down: the host's event subscription first, then the runtime.
  Future<void> dispose() async {
    await host.dispose();
    await runtime.dispose();
  }
}

/// Arms the dev-mode seat when — and ONLY when — the station runs JIT.
///
/// [vmServiceUri] is this process's own `stationVmServiceUri()`: non-null under
/// `--enable-vm-service`, null on an AOT binary. Null in ⇒ null out: no host, no
/// [ReassembleTool], no `ext.exploration.grid.reload`. [latest] is the station's
/// joined graph and [readPath] its controllers' read-path provenance (banner
/// material the observation plugin surfaces); [grid] is the LIVE tree the two
/// reassemble verbs re-compose.
Future<DevModeSeat?> armDevMode({
  required String? vmServiceUri,
  required GridHandle grid,
  required GraphSnapshot Function() latest,
  required String Function() readPath,
}) async {
  if (vmServiceUri == null) return null;
  final runtime = GridControllerRuntime(
    reader: JoinedWorkReader(latest),
    dirtySources: const [],
  );
  await runtime.start();
  final host = GridExplorationHost(
    runtime,
    plugin: GridControllerPlugin(runtime, readPath: readPath),
    reassemble: ReassembleTool(
      hotReload: () async => (await grid.hotReload()).toJson(),
      hotRestart: () async => (await grid.hotRestart()).toJson(),
    ),
  );
  return DevModeSeat._(host, runtime, vmServiceUri);
}
