import 'package:beads_dart/beads_dart.dart' show Bead, GraphSnapshot;
import 'package:genesis_tree/genesis_tree.dart' show Seed, TreeContext;
import 'package:grid_exploration/grid_exploration.dart' show kExtensionsKey;
import 'package:grid_sdk/grid_sdk.dart'
    show GridConfiguration, GridDelegate, RawAssetGrid, runGrid;
import 'package:space_station_assets/src/dev_mode.dart';
import 'package:test/test.dart';

/// Offline coverage for space's DEV-MODE seat — the host half of the EXPLICIT
/// hot-reload trigger. No VM service is needed to prove the composition: the
/// host's `dispatchTool` is the SAME entry point `register()` binds to the wire,
/// so the re-composition is provable in-process (the live two-process arc is
/// `reload_smoke_test.dart`).
///
/// The whole gate is the run mode: a VM-service URI in ⇒ the reload tool exists;
/// null in ⇒ nothing is armed.
void main() {
  /// A build-counting station — the witness that a reload RE-COMPOSED the tree.
  GraphSnapshot joined() => GraphSnapshot.fromParts(
    beads: const [Bead(id: 'space-1')],
    dependencies: const [],
    readyIds: const {'space-1'},
    capturedAt: DateTime.utc(2026),
  );

  test(
    'JIT (a VM service) arms the seat: the reload tool is composed, the '
    'handshake ADVERTISES it, and dispatching it re-composes the tree',
    () async {
      final builds = <int>[];
      final grid = runGrid(
        _ProbeDelegate(builds),
        delegateFactory: () => _ProbeDelegate(builds),
      );
      addTearDown(grid.teardown);
      expect(builds, hasLength(1), reason: 'the launch build');

      final seat = await armDevMode(
        vmServiceUri: 'http://127.0.0.1:8181/aBc=/',
        grid: grid,
        latest: joined,
        readPath: () => 'sql',
      );
      addTearDown(() async => seat!.dispose());

      expect(seat, isNotNull);
      expect(seat!.vmServiceUri, 'http://127.0.0.1:8181/aBc=/');
      // A registered tool is a discoverable tool: the handshake carries it.
      expect(seat.host.toolNames, contains('reload'));
      final extensions = seat.host.handshakeJson()[kExtensionsKey]! as List;
      expect((extensions.single! as Map)['tools'], contains('reload'));

      // The wire dispatch RE-RUNS the master build — GridHandle.hotReload().
      final reload = await seat.host.dispatchTool('reload', {'mode': 'reload'});
      expect(reload['ok'], isTrue);
      expect((reload['value']! as Map)['mode'], 'reload');
      expect((reload['value']! as Map)['generation'], 1);
      expect(builds, hasLength(2), reason: 'the master build re-ran');

      // `--restart` re-runs the delegate FACTORY (armed by up on the same gate).
      final restart = await seat.host.dispatchTool('reload', {
        'mode': 'restart',
      });
      expect((restart['value']! as Map)['mode'], 'restart');
      expect(builds, hasLength(3), reason: 'a FRESH delegate built');
    },
  );

  test('AOT (no VM service) arms NOTHING: null in, null out — no host, no '
      'reload tool, nothing registered', () async {
    final grid = runGrid(_ProbeDelegate(<int>[]));
    addTearDown(grid.teardown);

    final seat = await armDevMode(
      vmServiceUri: null,
      grid: grid,
      latest: joined,
      readPath: () => 'sql',
    );

    expect(seat, isNull);
  });

  test('the seat observes the station\'s JOINED graph — no second controller '
      'over the stores, no dirty source of its own', () async {
    final grid = runGrid(_ProbeDelegate(<int>[]));
    addTearDown(grid.teardown);
    final seat = await armDevMode(
      vmServiceUri: 'http://127.0.0.1:8181/aBc=/',
      grid: grid,
      latest: joined,
      readPath: () => 'sql',
    );
    addTearDown(() async => seat!.dispose());

    final snapshot = await seat!.host.dispatchTool('snapshot', const {});
    expect(snapshot['ok'], isTrue);
    expect('$snapshot', contains('space-1'), reason: 'the joined graph, read');
  });
}

/// A station whose only job is to COUNT its builds.
class _ProbeDelegate extends GridDelegate {
  _ProbeDelegate(this.builds);

  final List<int> builds;

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    builds.add(1);
    return const RawAssetGrid(root: '/grid/home');
  }
}
