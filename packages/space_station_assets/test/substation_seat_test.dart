import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart' show ServiceBundle;
import 'package:grid_runtime/grid_runtime.dart'
    show GitOps, PrOpener, PullRequestRef, PullRequestResult, SystemGitRunner;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_sdk/grid_sdk.dart' show Provider, ProviderScope;
import 'package:space_station_assets/src/substation_seat.dart';
import 'package:test/test.dart';

/// space-47t: the ONE composed seat ([SubstationSeat]) and its `const`,
/// watch-based stack assets ([GitGridAssets] / [GitHubGridAssets]). Pure +
/// offline — every tree mounts in a bare genesis [TreeOwner] under a
/// [ProviderScope] (the availability registry `runGrid` mounts at the
/// production root).
void main() {
  group('SubstationSeat — the composed seat', () {
    test('mounts its Substation UNDER the wrapper: the offline roster '
        'enumeration still finds the SubstationScope (space-47t b: '
        'codedRosterOf/mountedRosterOf are unaffected)', () {
      final walk = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              SubstationSeat(name: 'mine', root: '../mine', prefix: 'mn'),
            ],
          ),
        ),
      );
      final scope = walk.values<sdk.SubstationScope>().single;
      expect(scope.name, 'mine');
      expect(scope.root, '/home/me/mine');
      expect(scope.prefix, 'mn');
    });

    test('app == null mounts NO PrOpener provider — the commit-only posture '
        'is ABSENCE in the tree, never a null-valued provider', () {
      final walk = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [SubstationSeat(name: 'mine', root: '../mine')],
          ),
        ),
      );
      expect(
        walk.values<PrOpener>(),
        isEmpty,
        reason: 'no GitHubAppConfig value ⇒ no provider node at all',
      );
      // And with no opener (and no GitOps) observed, the seat's bundle stays
      // commit-only.
      expect(walk.values<ServiceBundle>().single.delivery, isNull);
    });

    test('app != null mounts a seat-scoped Provider<PrOpener> ABOVE the '
        'Substation — per-seat delivery identity by COMPOSITION, and it '
        'never passed through boot', () {
      final walk = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              SubstationSeat(
                name: 'mine',
                root: '../mine',
                app: const GitHubAppConfig(
                  appId: '1234',
                  installationId: '99',
                  privateKeyVar: 'MY_APP_KEY',
                ),
              ),
            ],
          ),
        ),
      );
      expect(
        walk.values<PrOpener>(),
        hasLength(1),
        reason: 'the seat mounts exactly one opener provider, in-tree',
      );
    });

    test('GitHubAppConfig is a VALUE: identity-only fields, equality by '
        'value, and nowhere to store a secret', () {
      const a = GitHubAppConfig(
        appId: '1234',
        installationId: '99',
        privateKeyVar: 'MY_APP_KEY',
      );
      const b = GitHubAppConfig(
        appId: '1234',
        installationId: '99',
        privateKeyVar: 'MY_APP_KEY',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect('$a', contains('MY_APP_KEY'), reason: 'the NAME is config');
    });
  });

  group('GitHubGridAssets — the watch-based delivery binding', () {
    test('binds delivery only when BOTH halves are observed; either absent '
        'passes the ambient bundle through commit-only', () {
      // GitOps alone — no opener anywhere: commit-only.
      final opsOnly = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              Provider<GitOps>(
                create: (_) => GitOps(SystemGitRunner()),
                child: SubstationSeat(name: 'mine', root: '../mine'),
              ),
            ],
          ),
        ),
      );
      expect(opsOnly.values<ServiceBundle>().single.delivery, isNull);

      // Opener alone (a seat app identity) — no GitOps: still commit-only
      // (GitHub can only ADD delivery to a checkout it can commit from).
      final openerOnly = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              SubstationSeat(
                name: 'mine',
                root: '../mine',
                app: const GitHubAppConfig(
                  appId: '1',
                  installationId: '2',
                  privateKeyVar: 'K',
                ),
              ),
            ],
          ),
        ),
      );
      expect(openerOnly.values<ServiceBundle>().single.delivery, isNull);

      // Both halves: the seat re-provides a delivery-bound bundle.
      final both = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              Provider<GitOps>(
                create: (_) => GitOps(SystemGitRunner()),
                child: SubstationSeat(
                  name: 'mine',
                  root: '../mine',
                  app: const GitHubAppConfig(
                    appId: '1',
                    installationId: '2',
                    privateKeyVar: 'K',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      expect(
        both.values<ServiceBundle>().where((b) => b.delivery != null),
        hasLength(1),
      );
    });

    test('FLIPS posture when the opener provider appears later: the watch '
        'MISS parks with the availability registry, and the re-described '
        'tree rebinds delivery (grid_engine Provider/ProviderScope '
        'semantics, #182)', () async {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      late _HostState host;
      final root = owner.mountRoot(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              Provider<GitOps>(
                create: (_) => GitOps(SystemGitRunner()),
                child: _Host(
                  onCreate: (s) => host = s,
                  describe: () => _seatStack(),
                ),
              ),
            ],
          ),
        ),
      );
      owner.flush();
      var bundles = _Walk(root).values<ServiceBundle>();
      expect(
        bundles.single.delivery,
        isNull,
        reason: 'no opener observed yet: commit-only',
      );

      // A PrOpener provider mounts in a SIBLING slot first: the parked
      // registration is drained and the asset rebuilds through the pending
      // registry — resolution stays ancestral, so the posture REMAINS
      // commit-only (rule 3: availability is observed, including absence).
      host.swap(
        () => _Slots([
          Provider<PrOpener>.value(_FakePrOpener(), child: const _Leaf()),
          _seatStack(),
        ]),
      );
      owner.flush();
      await _pump();
      owner.flush();
      bundles = _Walk(root).values<ServiceBundle>();
      expect(
        bundles.single.delivery,
        isNull,
        reason: 'a sibling provider is not an ancestor — still commit-only',
      );

      // The opener now mounts ABOVE the seat (the production shape: the seat
      // value gains an app identity, or the station's live arm authors the
      // ambient opener): the re-described subtree observes it and BINDS.
      host.swap(
        () => Provider<PrOpener>.value(_FakePrOpener(), child: _seatStack()),
      );
      owner.flush();
      await _pump();
      owner.flush();
      bundles = _Walk(root).values<ServiceBundle>();
      expect(
        bundles.where((b) => b.delivery != null),
        hasLength(1),
        reason: 'both halves observed: delivery-bound',
      );
    });
  });

  group('a non-git seat (STYLE rule 4: no provider is universal)', () {
    test('a composed seat whose stack carries NO git assets mounts clean '
        'with neither StationGitService nor GitOps anywhere in the tree, '
        'and the roster enumeration still sees it', () {
      final walk = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [const _NonGitSeat(name: 'notes', root: '../notes')],
          ),
        ),
      );
      final scope = walk.values<sdk.SubstationScope>().single;
      expect(scope.name, 'notes');
      expect(
        walk.values<ServiceBundle>(),
        isEmpty,
        reason: 'no git asset ⇒ no bundle — a posture, not an error',
      );
    });
  });
}

/// A composed seat with a DIFFERENT stack — the test-only proof that a
/// non-git substation composes without `StationGitService`/`GitOps` (no
/// production seat needs this yet, so none ships in lib).
class _NonGitSeat extends StatelessSeed {
  const _NonGitSeat({required this.name, required this.root});

  final String name;
  final String root;

  @override
  Seed build(TreeContext context) =>
      sdk.Substation(name, root, assets: const [sdk.SubstationWork()]);
}

/// The standard seat stack under test (no app identity — the opener, when
/// present, is ambient).
Seed _seatStack() => SubstationSeat(name: 'mine', root: '../mine');

/// Mounts [root] in a bare tree, flushes once, and returns the branch walker.
_Walk _mount(Seed root) {
  final owner = TreeOwner();
  final branch = owner.mountRoot(root);
  owner.flush();
  return _Walk(branch);
}

/// Collects every `InheritedBranch<T>` value in tree order.
class _Walk {
  _Walk(this.root);
  final Branch root;

  List<T> values<T extends Object>() {
    final found = <T>[];
    void walk(Branch b) {
      if (b is InheritedBranch<T>) found.add(b.value);
      b.visitChildren(walk);
    }

    walk(root);
    return found;
  }
}

/// Drains the microtask queue (the availability registry delivers deferred),
/// so the next flush observes the pinged rebuilds.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// A swappable host: [swap] replaces the described subtree entirely.
class _Host extends StatefulSeed {
  const _Host({required this.onCreate, required this.describe});

  final void Function(_HostState state) onCreate;
  final Seed Function() describe;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Seed Function()? _describe;

  @override
  void initState() {
    seed.onCreate(this);
  }

  void swap(Seed Function() describe) => setState(() => _describe = describe);

  @override
  Seed build(TreeContext context) => (_describe ?? seed.describe)();
}

/// A bare multi-child fan-out (sibling slots for the pending-registry leg).
class _Slots extends MultiChildSeed {
  const _Slots(List<Seed> slots) : super(children: slots);
}

/// An empty leaf.
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// A non-throwing PR opener fake (never invoked — posture only).
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
