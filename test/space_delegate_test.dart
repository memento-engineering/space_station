import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show AgentConfig, AgentHarnessRegistry, ProviderManaged;
import 'package:grid_runtime/grid_runtime.dart'
    show PrOpener, PullRequestRef, PullRequestResult, RootCheckout;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:space_station/src/space_delegate.dart';
import 'package:test/test.dart';

/// Track G-space (tg-33n): offline coverage for [SpaceDelegate] — space_station
/// authored as a Seed (the v3 §2 tree). Pure + offline: the delegate's [build]
/// tree is mounted in a bare genesis tree (no kernel, no live git/claude —
/// null provisioner/gitOps is the dry authoring where the layout still
/// resolves), and its asset-seam members are read back directly. The Track F
/// assets themselves (GitGridAssets resolving canLand, worktree layout) are
/// proven in power_station; this proves space COMPOSES them into a valid v3
/// tree AND owns the seam `space up` drives through.
void main() {
  RootCheckout root(String name, String path) =>
      RootCheckout(path: path, substation: name, defaultBranch: 'main');

  SpaceDelegate delegate({
    String gridRoot = '/home/space_station',
    List<SpaceSubstation>? substations,
    PrOpener? prOpener,
  }) => SpaceDelegate(
    gridRoot: gridRoot,
    stationName: 'space',
    substations:
        substations ??
        [
          SpaceSubstation(name: 'the_grid', root: root('the_grid', '/work/tg')),
          SpaceSubstation(
            name: 'power_station',
            root: root('power_station', '/work/ps'),
          ),
        ],
    agentConfig: const AgentConfig(harness: 'claude', target: ProviderManaged()),
    prOpener: prOpener,
  );

  group('SpaceDelegate.build — space_station as a Seed (v3 §2)', () {
    test('the well-formed offline tree mounts clean (RawAssetGrid → Station → '
        'HarnessProvider → Substations → Substation[GitGridAssets] validates '
        'end to end)', () {
      expect(() => _mount(_Author(delegate())), returnsNormally);
    });

    test('the land arm (a PR opener) mounts GitHubGridAssets under each '
        'substation, clean', () {
      expect(
        () => _mount(_Author(delegate(prOpener: _FakePrOpener()))),
        returnsNormally,
      );
    });

    test('a single-substation station mounts clean', () {
      expect(
        () => _mount(
          _Author(
            delegate(
              substations: [
                SpaceSubstation(name: 'tgdog', root: root('tgdog', '/work/td')),
              ],
            ),
          ),
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

    test('an EMPTY substation name is refused LOUD at mount', () {
      expect(
        () => _mount(
          _Author(
            delegate(
              substations: [SpaceSubstation(name: '', root: root('', '/work/x'))],
            ),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SpaceDelegate — the asset seam `space up` drives through', () {
    test('wrapRoot mounts the station-default AgentConfig + harness registry as '
        'ancestors (D-C rung 1) — both reach a leaf below', () {
      final d = delegate();
      AgentConfig? cfg;
      AgentHarnessRegistry? reg;
      _mount(
        d.wrapRoot(
          _Probe((ctx) {
            cfg = ctx.getInheritedSeedOfExactType<AgentConfig>();
            reg = ctx.getInheritedSeedOfExactType<AgentHarnessRegistry>();
          }),
        ),
      );
      expect(cfg, same(d.agentConfig));
      expect(reg, same(d.harnesses));
      expect(reg!.ids, contains('claude'));
    });

    test('codeRegistry builds a capability registry rooted at the devRoot', () {
      expect(delegate().codeRegistry('/work/tg'), isNotNull);
    });

    test('harnesses defaults to the first-party claude set', () {
      expect(delegate().harnesses.ids, contains('claude'));
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

/// A terminal leaf that runs [onBuild] against a live TreeContext (inherited
/// lookups are valid only while mounted).
class _Probe extends StatelessSeed {
  const _Probe(this.onBuild);

  final void Function(TreeContext) onBuild;

  @override
  Seed build(TreeContext context) {
    onBuild(context);
    return const _Leaf();
  }
}

class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// A non-throwing PR opener (the land arm only needs a non-null opener to mount
/// GitHubGridAssets).
class _FakePrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => PullRequestResult.opened(const PullRequestRef(url: 'https://x/pr/1'));
}
