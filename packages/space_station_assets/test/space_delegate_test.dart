import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentCapability,
        AgentConfig,
        GitGridAssets,
        MountEligibilityAssets,
        PackagedAssetLoader,
        kCodeCircuit,
        kProvenanceMarker,
        kUnknownSourceRef,
        resolveOverlaySourceRefSync;
import 'package:grid_engine/grid_engine.dart'
    show
        CapabilityHost,
        CapabilityStep,
        Circuit,
        NodeCursor,
        ServiceBundle,
        SessionHandle,
        StepMount,
        Workspace;
import 'package:grid_engine/testing.dart'
    show FakeTreeContext, stepArgs, testWorkspace;
import 'package:grid_runtime/grid_runtime.dart' show GitOps, PrOpener;
import 'package:github_grid_assets/github_grid_assets.dart' as github;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:space_station_assets/src/assets_command.dart' show kSpaceRunner;
import 'package:space_station_assets/src/space_delegate.dart';
import 'package:space_station_assets/src/up_command.dart';
import 'package:test/test.dart';

const _overlayAgentCircuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

StepMount _overlayAgentMount() => StepMount(
  step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
  nodePath: 'space-overlay/agent',
  circuit: _overlayAgentCircuit,
  circuitPath: 'space-overlay',
  session: const SessionHandle('space-overlay-s'),
  node: const NodeCursor(),
  key: const ValueKey('space-overlay/agent#0.0'),
);

/// Track G-space / H2 (tg-r81), re-cut by space-47t: offline coverage for
/// [SpaceDelegate] — space_station authored as a Seed (the v3 §2 tree). Pure
/// + offline: the delegate's [build] tree is mounted in a bare genesis tree
/// (no kernel, no live git/claude — the dry authoring mounts NO effect
/// providers, and the seat assets observe that absence as the commit-only /
/// offline posture), the same tree `runGrid(SpaceDelegate())` mounts under
/// `space up`. The composed seed itself ([SubstationSeed] and its watch-based
/// assets) is proven in `substation_seed_test.dart`; this proves space
/// COMPOSES it into a valid v3 tree with the memento org hardcoded in it
/// (space-6ds — see `memento_roster_test.dart` for the roster/append
/// coverage).
void main() {
  SpaceDelegate delegate({
    String gridRoot = '/home/memento/space_station',
    List<sdk.Substation> appended = const [],
    github.GitHubSelfTrust? githubSelfTrust,
    bool live = false,
  }) => SpaceDelegate(
    gridRoot: gridRoot,
    appended: appended,
    agentConfig: const AgentConfig(harness: 'claude'),
    githubSelfTrust: githubSelfTrust,
    live: live,
  );

  group('SpaceDelegate.build — space_station as a Seed (v3 §2)', () {
    test('the well-formed offline tree mounts clean (ProviderScope → '
        'RawAssetGrid → Station → HarnessProvider → Substations → the six '
        'coded SubstationSeed wrappers validate end to end)', () {
      expect(() => _mount(_Author(delegate())), returnsNormally);
    });

    test('the DRY tree (the default) binds NO delivery anywhere — the effect '
        'providers are ABSENT from the tree, so every seat bundle is '
        'commit-only (space-47t: inertness declared in the tree)', () {
      final bundles = _mountedBundles(_Author(delegate()));
      expect(bundles, hasLength(6), reason: 'one gated bundle per coded seat');
      expect(bundles.every((b) => b.delivery == null), isTrue);
    });

    test('a LIVE delegate authors the effect providers IN-TREE and every '
        'coded seat binds GitHub delivery by OBSERVING both halves '
        '(space-47t: no effect instance passes through boot)', () {
      final bundles = _mountedBundles(_Author(delegate(live: true)));
      expect(
        bundles.where((b) => b.delivery != null),
        hasLength(6),
        reason: 'each coded seat re-provides its bundle delivery-bound',
      );
    });

    test(
      'GitHub self trust resolves through gh and mounts once only for live station',
      () async {
        final diagnostics = <String>[];
        final calls =
            <
              ({
                String executable,
                List<String> arguments,
                String? workingDirectory,
              })
            >[];
        Future<ProcessResult> fakeGh(
          String executable,
          List<String> arguments, {
          String? workingDirectory,
        }) async {
          calls.add((
            executable: executable,
            arguments: List<String>.of(arguments),
            workingDirectory: workingDirectory,
          ));
          return ProcessResult(1, 0, 'NiCo\n', '');
        }

        final trust = await resolveGitHubSelfTrustFromGh(
          workingDirectory: '/home/memento/space_station',
          githubPollingConfigured: true,
          writeDiagnostic: diagnostics.add,
          timeout: const Duration(milliseconds: 50),
          run: fakeGh,
        );
        expect(calls, hasLength(1));
        expect(calls.single.executable, 'gh');
        expect(calls.single.arguments, ['api', 'user', '-q', '.login']);
        expect(calls.single.workingDirectory, '/home/memento/space_station');
        expect(trust, isNotNull);
        expect(trust!.githubUser, 'NiCo');
        expect(
          _mountedValues<github.GitHubSelfTrust>(
            _Author(delegate(live: true, githubSelfTrust: trust)),
          ),
          [same(trust)],
        );
        expect(
          _mountedValues<github.GitHubSelfTrust>(
            _Author(delegate(githubSelfTrust: trust)),
          ),
          isEmpty,
        );

        for (final result in [
          ProcessResult(2, 1, '', 'not authenticated'),
          ProcessResult(3, 0, '  \n', ''),
        ]) {
          Future<ProcessResult> absentGh(
            String executable,
            List<String> arguments, {
            String? workingDirectory,
          }) async => result;
          expect(
            await resolveGitHubSelfTrustFromGh(
              workingDirectory: '/home/memento/space_station',
              githubPollingConfigured: true,
              writeDiagnostic: diagnostics.add,
              timeout: const Duration(milliseconds: 50),
              run: absentGh,
            ),
            isNull,
          );
        }

        Future<ProcessResult> unavailableGh(
          String executable,
          List<String> arguments, {
          String? workingDirectory,
        }) async {
          throw ProcessException(executable, arguments);
        }

        expect(
          await resolveGitHubSelfTrustFromGh(
            workingDirectory: '/home/memento/space_station',
            githubPollingConfigured: true,
            writeDiagnostic: diagnostics.add,
            timeout: const Duration(milliseconds: 50),
            run: unavailableGh,
          ),
          isNull,
        );
        expect(diagnostics, isEmpty);
      },
    );

    test(
      'GitHub self trust timeout is loud and leaves live intake trust absent',
      () async {
        final never = Completer<ProcessResult>();
        final diagnostics = <String>[];
        Future<ProcessResult> hangingGh(
          String executable,
          List<String> arguments, {
          String? workingDirectory,
        }) async {
          return await never.future;
        }

        final elapsed = Stopwatch()..start();
        final trust = await resolveGitHubSelfTrustFromGh(
          workingDirectory: '/home/memento/space_station',
          githubPollingConfigured: true,
          writeDiagnostic: diagnostics.add,
          timeout: const Duration(milliseconds: 10),
          run: hangingGh,
        );
        elapsed.stop();

        expect(trust, isNull);
        expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
        expect(diagnostics, [
          'space up: gh api user login probe timed out after 10ms; '
              'continuing without GitHub self trust — polling intake remains inert.',
        ]);
        expect(
          _mountedValues<github.GitHubSelfTrust>(
            _Author(delegate(live: true, githubSelfTrust: trust)),
          ),
          isEmpty,
        );
      },
    );

    test('resolveGitHubSelfTrustFromGh SKIPS gh when NO armed seat polls — the '
        'function\'s own contract, keyed on the flag; and the coded roster now '
        'reports six polling seats, so a live boot reaches the probe instead '
        '(space-3ds)', () async {
      var calls = 0;
      final diagnostics = <String>[];
      Future<ProcessResult> fakeGh(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
      }) async {
        calls += 1;
        return ProcessResult(1, 0, 'NiCo\n', '');
      }

      final trust = await resolveGitHubSelfTrustFromGh(
        workingDirectory: '/home/memento/space_station',
        githubPollingConfigured: false,
        writeDiagnostic: diagnostics.add,
        timeout: const Duration(milliseconds: 10),
        run: fakeGh,
      );

      expect(calls, 0, reason: 'the flag alone gates the probe');
      expect(trust, isNull);
      expect(diagnostics, isEmpty);

      // The PRODUCTION input to that flag is no longer empty: `up` computes
      // `githubPollingArmed` from this set (up_command.dart:444-446), so a
      // live boot over the real umbrella takes the probe branch, not this one.
      final roster = codedRosterSnapshotOf(
        SpaceDelegate.new,
        gridRoot: '/home/memento/space_station',
      );
      expect(roster.githubPollingSeatNames, hasLength(6));
    });

    test('the six LIVE poll values author NO reconciler runtime on an OFFLINE '
        'mount: without self trust the per-seat binding provides no cursor '
        'store or sink, and the App client resolves asynchronously so a '
        'synchronous flush never has one (space-3ds)', () {
      expect(
        _mountedValues<github.GitHubReconcilerRuntime>(
          _Author(delegate(live: true)),
        ),
        isEmpty,
      );
      expect(
        _mountedValues<github.GitHubReconcilerRuntime>(
          _Author(
            delegate(
              live: true,
              githubSelfTrust: github.GitHubSelfTrust(githubUser: 'NiCo'),
            ),
          ),
        ),
        isEmpty,
        reason:
            'trust alone does not arm a runtime — GitHubReconcilerAssets also '
            'requires a GitHubAppClient, which the credential load never '
            'produces within one synchronous flush',
      );
    });

    test('an appended (--substation) seat mounts clean after the literal '
        'coded org (space-6ds: the six coded seats are always authored)', () {
      expect(
        () => _mount(
          _Author(delegate(appended: [sdk.Substation('tgdog', '/work/td')])),
        ),
        returnsNormally,
      );
    });

    test(
      'a LIVE flag-appended seat retains git and gate but binds no delivery',
      () {
        final bundles = _mountedBundles(
          _Author(
            delegate(
              live: true,
              appended: [
                sdk.Substation(
                  'tgdog',
                  '/work/td',
                  assets: const [
                    Nest(
                      children: [GitGridAssets(), MountEligibilityAssets()],
                      child: sdk.SubstationWork(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        expect(bundles, hasLength(7));
        expect(
          bundles.take(6).every((bundle) => bundle.delivery != null),
          isTrue,
        );
        final appended = bundles.last;
        expect(appended.delivery, isNull);
        expect(appended.sourceControl, isNotNull);
        expect(appended.mountEligibility, isNotNull);
      },
    );

    test('the LIVE effect providers are TREE-OWNED (create:, STYLE rule 2): '
        'a full re-description keeps the SAME GitOps/PrOpener instances — a '
        '.value posture would thread a fresh pre-built instance per build', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final subject = delegate(live: true);
      addTearDown(subject.dispose);
      late _SwapHostState host;
      final root = owner.mountRoot(
        _SwapHost(onCreate: (s) => host = s, describe: () => _Author(subject)),
      );
      owner.flush();
      List<T> valuesOf<T extends Object>() {
        final found = <T>[];
        void walk(Branch b) {
          if (b is InheritedBranch<T>) found.add(b.value);
          b.visitChildren(walk);
        }

        walk(root);
        return found;
      }

      final opsBefore = valuesOf<GitOps>().single;
      final openerBefore = valuesOf<PrOpener>().single;
      // Re-describe the WHOLE delegate tree with fresh seed instances:
      // reconcile updates the providers in place, and create: never re-runs.
      host.swap(() => _Author(subject));
      owner.flush();
      expect(
        identical(valuesOf<GitOps>().single, opsBefore),
        isTrue,
        reason:
            'create: runs once per mount — the tree owns ONE GitOps for '
            'the life of the branch (a .value posture would adopt a new '
            'boot-built instance on every rebuild)',
      );
      expect(
        identical(valuesOf<PrOpener>().single, openerBefore),
        isTrue,
        reason: 'same ownership pin for the station-level opener',
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

    test(
      'a downstream delegate materializes its runner and a real source ref',
      () {
        final sourceRef = resolveOverlaySourceRefSync(Directory.current.path);
        expect(
          sourceRef,
          isNot(kUnknownSourceRef),
          reason: 'the package test runs inside a git worktree',
        );

        final body = _materializeDiscoverSkill(
          _OverlayIdentityDelegate(
            gridRoot: '/home/lunar',
            sourceRef: sourceRef,
          ),
        );

        expect(body, contains('dart run lunar:lunar search --json'));
        expect(body, contains('`dart run lunar:lunar assets install`'));
        expect(body, contains('$kProvenanceMarker$sourceRef'));
        expect(body, isNot(contains('$kProvenanceMarker$kUnknownSourceRef')));
      },
    );

    test('the base delegate materializes the space runner', () {
      final subject = SpaceDelegate(gridRoot: '/home/space');
      expect(
        subject.overlaySourceRef,
        resolveOverlaySourceRefSync(
          p.join(PackagedAssetLoader().root, 'station_overlay'),
        ),
      );

      final body = _materializeDiscoverSkill(subject);
      expect(body, contains('$kSpaceRunner search --json'));
      expect(body, contains('`$kSpaceRunner assets install`'));
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
      final assembly = source.indexOf(
        'workRuntime = await assembleStationWork(',
      );
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
      // The policy delegate is ASSEMBLY-ONLY and must stay DRY: neither of
      // its hooks reads the posture, and a live-postured delegate mounted
      // for an enumeration would author effect providers into an offline
      // tree (the boot-leak class space-47t removed).
      final constructionEnd = source.indexOf(');', construction);
      expect(
        source.substring(construction, constructionEnd),
        isNot(contains('live')),
        reason: 'workPolicyDelegate must be constructed without live:',
      );
    });
  });
}

/// Mounts [root] in a bare tree and flushes one build pass (the Track B/F
/// template).
void _mount(Seed root) {
  final owner = TreeOwner();
  // The coded seats carry the org App (space-u8q), so each mounts a
  // GitHubAppClientAssets that starts a credential load. Disposing at teardown
  // makes that load a no-op instead of letting it outlive the test.
  addTearDown(owner.dispose);
  owner.mountRoot(root);
  owner.flush();
}

List<T> _mountedValues<T extends Object>(Seed seed) {
  final owner = TreeOwner();
  final root = owner.mountRoot(seed);
  owner.flush();
  final values = <T>[];
  void walk(Branch branch) {
    if (branch is InheritedBranch<T>) values.add(branch.value);
    branch.visitChildren(walk);
  }

  walk(root);
  owner.dispose();
  return values;
}

/// Mounts [root], flushes once, and collects every provided [ServiceBundle]
/// in tree order — the delivery-posture projection of the authored tree.
/// A commit-only seat provides ONE bundle (its git asset's); a
/// delivery-bound seat re-provides a second, delivery-carrying bundle below
/// it, so the outermost bundle per seat is filtered to the DEEPEST per
/// substation by taking `delivery != null` counts where bound.
List<ServiceBundle> _mountedBundles(Seed root) {
  final owner = TreeOwner();
  addTearDown(owner.dispose);
  final branch = owner.mountRoot(root);
  owner.flush();
  final bundles = <ServiceBundle>[];
  void walk(Branch b) {
    if (b is InheritedBranch<ServiceBundle>) bundles.add(b.value);
    b.visitChildren(walk);
  }

  walk(branch);
  // A seat mounts SEVERAL bundles as its stack assets each re-provide: git's,
  // GitHub's delivery re-provision, and innermost the one the mount gate
  // derives. Only the innermost is what `SubstationWork` resolves, so it is
  // the only one a seat-posture assertion means.
  //
  // `MountEligibilityAssets` is mounted innermost on EVERY seat, so
  // "carries a mount predicate" identifies that bundle exactly — replacing the
  // pairwise delivery heuristic this helper used to need, which could only
  // collapse pairs and silently mis-collapsed a triple.
  return bundles.where((b) => b.mountEligibility != null).toList();
}

/// A swappable host: [_SwapHostState.swap] re-describes the subtree with
/// fresh seed instances (the ownership-pinning tests' rebuild trigger).
class _SwapHost extends StatefulSeed {
  const _SwapHost({required this.onCreate, required this.describe});

  final void Function(_SwapHostState state) onCreate;
  final Seed Function() describe;

  @override
  State<_SwapHost> createState() => _SwapHostState();
}

class _SwapHostState extends State<_SwapHost> {
  Seed Function()? _describe;

  @override
  void initState() {
    seed.onCreate(this);
  }

  void swap(Seed Function() describe) => setState(() => _describe = describe);

  @override
  Seed build(TreeContext context) => (_describe ?? seed.describe)();
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
    return super.buildWorkRegistry(appendNote);
  }
}

String _materializeDiscoverSkill(SpaceDelegate delegate) {
  addTearDown(delegate.dispose);
  final worktree = Directory.systemTemp.createTempSync('delegate-overlay-');
  addTearDown(() {
    if (worktree.existsSync()) worktree.deleteSync(recursive: true);
  });

  final registry = delegate.buildWorkRegistry((_, _) async {});
  final capability =
      (registry.host(_overlayAgentMount()) as CapabilityHost).capability
          as AgentCapability;
  capability.spawn(
    FakeTreeContext(
      values: {
        Bead: const Bead(id: 'space-overlay'),
        Workspace: testWorkspace(
          'space-overlay',
          workspaceDir: worktree.path,
          branch: 'grid/space-overlay',
        ),
      },
    ),
    stepArgs('space-overlay/agent'),
  );

  return File(
    p.join(worktree.path, '.claude', 'skills', 'discover', 'SKILL.md'),
  ).readAsStringSync();
}

class _OverlayIdentityDelegate extends SpaceDelegate {
  _OverlayIdentityDelegate({required super.gridRoot, required this.sourceRef});

  final String sourceRef;

  @override
  String get runnerInvocation => 'dart run lunar:lunar';

  @override
  String get overlaySourceRef => sourceRef;
}
