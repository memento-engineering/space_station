import 'package:grid_cli/grid_cli.dart' show buildDryTreeGitService;
import 'package:grid_runtime/grid_runtime.dart'
    show
        GitOps,
        GitRunResult,
        GitRunner,
        PrOpener,
        PullRequestResult,
        RootCheckout;
import 'package:space_station/src/up_command.dart' show serviceBundleMapFor;
import 'package:test/test.dart';

/// RS-5b rework round 2 (tg-1di): offline coverage for `serviceBundleMapFor`
/// (`up_command.dart`) — the pure `composeStation(services:)` construction
/// `UpCommand.run()` extracted from (tg-7gm's per-substation `ServiceBundle`
/// map + the per-root `GitSourceControl` split, `sourceControl` vs
/// `sourceControlsByRoot`). Zero I/O: [buildDryTreeGitService] is the SAME
/// inert provisioner `up` wires under `--dry-run`, and the two roots below
/// are distinguished only by `defaultBranch` (cheaper than asserting the
/// `workspaceFor` path layout, which `grid_cli`'s own suite already locks).
void main() {
  final provisioner = buildDryTreeGitService();

  RootCheckout root(String branch) => RootCheckout(
    path: '/tmp/$branch',
    defaultBranch: branch,
    substation: branch,
  );

  group(
    'serviceBundleMapFor — the composeStation services-map shape (tg-7gm)',
    () {
      test(
        'keys the map by the ONE composed substation id, not by root name',
        () {
          final map = serviceBundleMapFor(
            defaultSubstation: 'tgdog',
            workRoot: root('main'),
            roots: const {},
            provisioner: provisioner,
          );
          expect(map.keys, {'tgdog'});
        },
      );

      test('no --root registered at all: sourceControlsByRoot stays EMPTY, '
          'sourceControl resolves the DEFAULT workRoot', () {
        final map = serviceBundleMapFor(
          defaultSubstation: 'tgdog',
          workRoot: root('default-branch'),
          roots: const {},
          provisioner: provisioner,
        );
        final bundle = map['tgdog']!;
        expect(bundle.sourceControlsByRoot, isEmpty);
        expect(bundle.sourceControl!.baseBranch, 'default-branch');
      });

      test("the default substation's OWN entry in `roots` folds into "
          '`sourceControl` — it must NOT also appear in `sourceControlsByRoot` '
          '(that map is EXTRA roots only)', () {
        final defaultRoot = root('default-branch');
        final map = serviceBundleMapFor(
          defaultSubstation: 'tgdog',
          workRoot: defaultRoot,
          roots: {'tgdog': defaultRoot},
          provisioner: provisioner,
        );
        final bundle = map['tgdog']!;
        expect(bundle.sourceControlsByRoot, isEmpty);
        expect(bundle.sourceControl!.baseBranch, 'default-branch');
      });

      test(
        'an EXTRA registered root (tg-7gm) lands in `sourceControlsByRoot`, '
        'keyed by ITS OWN name — a DIFFERENT SourceControl than the default',
        () {
          final map = serviceBundleMapFor(
            defaultSubstation: 'tg',
            workRoot: root('tg-branch'),
            roots: {
              'tg': root('tg-branch'),
              'power_station': root('ps-branch'),
            },
            provisioner: provisioner,
          );
          final bundle = map['tg']!;
          expect(bundle.sourceControlsByRoot.keys, {'power_station'});
          expect(bundle.sourceControl!.baseBranch, 'tg-branch');
          expect(
            bundle.sourceControlsByRoot['power_station']!.baseBranch,
            'ps-branch',
          );
        },
      );

      test('MULTIPLE extra roots all land, each under its own name; still only '
          'ONE substation key in the returned map', () {
        final map = serviceBundleMapFor(
          defaultSubstation: 'tg',
          workRoot: root('tg-branch'),
          roots: {
            'tg': root('tg-branch'),
            'power_station': root('ps-branch'),
            'genesis': root('genesis-branch'),
          },
          provisioner: provisioner,
        );
        expect(map.keys, {'tg'});
        final bundle = map['tg']!;
        expect(bundle.sourceControlsByRoot.keys, {'power_station', 'genesis'});
      });

      test('land ops absent (the default posture): canLand is false on EVERY '
          'constructed SourceControl — default AND extra', () {
        final map = serviceBundleMapFor(
          defaultSubstation: 'tg',
          workRoot: root('tg-branch'),
          roots: {'tg': root('tg-branch'), 'power_station': root('ps-branch')},
          provisioner: provisioner,
        );
        final bundle = map['tg']!;
        expect(bundle.sourceControl!.canLand, isFalse);
        expect(bundle.sourceControlsByRoot['power_station']!.canLand, isFalse);
      });

      test('gitOps + prOpener BOTH wired (an armed --land): canLand is true on '
          'EVERY constructed SourceControl — default AND extra', () {
        final map = serviceBundleMapFor(
          defaultSubstation: 'tg',
          workRoot: root('tg-branch'),
          roots: {'tg': root('tg-branch'), 'power_station': root('ps-branch')},
          provisioner: provisioner,
          gitOps: GitOps(_UnreachableGitRunner()),
          prOpener: _UnreachablePrOpener(),
        );
        final bundle = map['tg']!;
        expect(bundle.sourceControl!.canLand, isTrue);
        expect(bundle.sourceControlsByRoot['power_station']!.canLand, isTrue);
      });
    },
  );
}

/// A [GitRunner] never actually invoked — [serviceBundleMapFor] only STORES
/// its wrapping [GitOps], never calls it (a real `--land` run's LandCapability
/// is the only caller, and it is not exercised by this pure-construction
/// suite).
class _UnreachableGitRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) => throw UnimplementedError('never called by serviceBundleMapFor');
}

/// A [PrOpener] never actually invoked — same rationale as
/// [_UnreachableGitRunner].
class _UnreachablePrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) => throw UnimplementedError('never called by serviceBundleMapFor');
}
