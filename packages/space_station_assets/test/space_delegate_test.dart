import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show AgentConfig, buildCodeRegistry, kCodeCircuit;
import 'package:grid_runtime/grid_runtime.dart'
    show PrOpener, PullRequestRef, PullRequestResult;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station_assets/src/space_delegate.dart';
import 'package:test/test.dart';

/// Track G-space / H2 (tg-r81): offline coverage for [SpaceDelegate] —
/// space_station authored as a Seed (the v3 §2 tree). Pure + offline: the
/// delegate's [build] tree is mounted in a bare genesis tree (no kernel, no
/// live git/claude — null provisioner/gitOps rides the ambient `GitServices`
/// as the dry authoring where the layout still resolves — Track F/pow-72b),
/// the same tree `runGrid(SpaceDelegate())` mounts under `space up`. The
/// Track F assets themselves (a bare GitGridAssets sourcing its halves from
/// context, the delivery binding, worktree layout) are proven in power_station;
/// this
/// proves space COMPOSES them into a valid v3 tree with the memento org
/// hardcoded in it (space-6ds — see `memento_roster_test.dart` for the
/// roster/append coverage).
void main() {
  SpaceDelegate delegate({
    String gridRoot = '/home/memento/space_station',
    List<sdk.Substation> appended = const [],
    PrOpener? prOpener,
  }) => SpaceDelegate(
    gridRoot: gridRoot,
    appended: appended,
    agentConfig: const AgentConfig(harness: 'claude'),
    prOpener: prOpener,
  );

  group('SpaceDelegate.build — space_station as a Seed (v3 §2)', () {
    test('the well-formed offline tree mounts clean (RawAssetGrid → Station → '
        'HarnessProvider → GitServices → Substations → the five coded '
        'Substation[GitGridAssets] seats validate end to end)', () {
      expect(() => _mount(_Author(delegate())), returnsNormally);
    });

    test('a PR opener DI-d into each seat mounts GitHubGridAssets clean (the '
        'delivery BINDING itself also needs the commit/push half — '
        'GitHubGridAssets binds a method only with BOTH, and power_station '
        'proves that)', () {
      expect(
        () => _mount(_Author(delegate(prOpener: _FakePrOpener()))),
        returnsNormally,
      );
    });

    test('an appended (--substation) seat mounts clean after the literal '
        'coded org (space-6ds: the five coded seats are always authored)', () {
      expect(
        () => _mount(
          _Author(delegate(appended: [sdk.Substation('tgdog', '/work/td')])),
        ),
        returnsNormally,
      );
    });

    test('a RELATIVE gridRoot is refused LOUD at mount (v3 §0: no cwd-relative '
        'root — the ambience fossil the model kills)', () {
      expect(
        () => _mount(_Author(delegate(gridRoot: 'relative/path'))),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the overridden `root` getter surfaces the grid home (not the base\'s '
        'no-default-root throw)', () {
      expect(delegate(gridRoot: '/home/space').root, '/home/space');
    });
  });

  group('SpaceDelegate — the station-default agent scope', () {
    test('harnesses defaults to the first-party claude set', () {
      expect(delegate().harnesses.names, contains('claude'));
    });
  });

  group('SpaceDelegate — resident work policy hooks', () {
    test('defaults retain migration-aware routing and the code registry', () {
      final subject = delegate();
      expect(subject.circuitOverrideFor(const Bead(id: 'space-code')), isNull);

      final registry = subject.buildWorkRegistry((_, _) async {});
      for (final id in <String>{
        'code',
        'spec_review',
        'discovery',
        'code_review',
        'docs_review',
        'landing',
      }) {
        expect(registry.circuit(id), isNotNull, reason: id);
      }
    });

    test('a downstream delegate selects only its marker bead', () {
      final subject = _MarkerDelegate(gridRoot: '/home/space');
      expect(
        subject.circuitOverrideFor(const Bead(id: 'space-marker')),
        same(_MarkerDelegate.markerCircuit),
      );
      expect(subject.circuitOverrideFor(const Bead(id: 'space-code')), isNull);

      final registry = subject.buildWorkRegistry((_, _) async {});
      expect(registry.circuit('code'), same(kCodeCircuit));
      expect(subject.receivedAppender, isNotNull);
    });

    test('resident assembly owns and disposes its policy delegate', () {
      final source = File('lib/src/up_command.dart').readAsStringSync();
      final construction = source.indexOf('final workPolicyDelegate =');
      final assembly = source.indexOf('workRuntime = await buildStationWork(');
      expect(construction, greaterThanOrEqualTo(0));
      expect(construction, lessThan(assembly));
      expect(
        source,
        contains('overrideFor: workPolicyDelegate.circuitOverrideFor'),
      );
      expect(
        source,
        contains('workPolicyDelegate.buildWorkRegistry(appendNote)'),
      );
      expect(source, isNot(contains('registry: buildCodeRegistry()')));
      expect(
        RegExp(r'workPolicyDelegate\.dispose\(\);').allMatches(source).length,
        6,
      );
    });
  });
}

/// Mounts [root] in a bare tree and flushes one build pass (the Track B/F
/// template).
void _mount(Seed root) {
  final owner = TreeOwner();
  owner.mountRoot(root);
  owner.flush();
}

/// Calls [SpaceDelegate.build] with a live [TreeContext] during mount (the
/// offline stand-in for runGrid's `_DelegateRoot`, which does the same).
class _Author extends StatelessSeed {
  const _Author(this.delegate);

  final SpaceDelegate delegate;

  @override
  Seed build(TreeContext context) =>
      delegate.build(context, const sdk.GridConfiguration());
}

/// A non-throwing PR opener. The offline delegate DI-s only this half, which is
/// enough to mount `GitHubGridAssets` under every seat; the delivery BINDING
/// needs the commit/push half too (power_station proves that seam).
class _FakePrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async =>
      PullRequestResult.opened(const PullRequestRef(url: 'https://x/pr/1'));
}

class _MarkerDelegate extends SpaceDelegate {
  _MarkerDelegate({required super.gridRoot});

  static final sdk.Circuit markerCircuit = kCodeCircuit.copyWith(id: 'marker');

  NoteAppender? receivedAppender;

  @override
  sdk.Circuit? circuitOverrideFor(Bead bead) =>
      bead.id == 'space-marker' ? markerCircuit : null;

  @override
  sdk.CapabilityRegistry buildWorkRegistry(NoteAppender appendNote) {
    receivedAppender = appendNote;
    return buildCodeRegistry();
  }
}
