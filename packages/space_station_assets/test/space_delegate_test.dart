import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead, BdResult, BdRunner;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentCapability,
        AgentConfig,
        AgentEnvironment,
        BaseScope,
        EnvironmentRegistry,
        EnvBaseRef,
        GitGridAssets,
        GridAssetRosterOverride,
        MountEligibilityAssets,
        PackagedAssetLoader,
        SpecifyCapability,
        SubstationFacts,
        SubstationFactsSnapshot,
        SubstationKey,
        kCodeCircuit,
        kProvenanceMarker,
        kSpecReviewCircuit,
        kSpecifyStep,
        kUnknownSourceRef,
        mountedValuesOf,
        resolveOverlaySourceRefSync,
        usageReportPath;
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
import 'package:space_station_assets/space_station_assets.dart' as station;
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

StepMount _specifyMount(String beadId) => StepMount(
  step: kSpecReviewCircuit.steps.whereType<CapabilityStep>().singleWhere(
    (step) => step.stepId == kSpecifyStep,
  ),
  nodePath: '$beadId/spec_review/specify',
  circuit: kSpecReviewCircuit,
  circuitPath: '$beadId/spec_review',
  session: const SessionHandle('space-specify-session'),
  node: const NodeCursor(),
  key: ValueKey('$beadId/spec_review/specify#0.0'),
);

/// Track G-space / H2 (tg-r81), re-cut by space-47t: offline coverage for
/// [SpaceDelegate] — space_station authored as a Seed (the v3 §2 tree). Pure
/// + offline: the delegate's [build] tree is mounted in a bare genesis tree
/// (no kernel, no live git/claude — the dry authoring mounts NO effect
/// providers, and the substation assets observe that absence as the commit-only /
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
    BdRunner Function(String workspaceRoot)? specifyBdRunnerFor,
    bool live = false,
  }) => SpaceDelegate(
    gridRoot: gridRoot,
    appended: appended,
    agentConfig: const AgentConfig(harness: 'claude'),
    githubSelfTrust: githubSelfTrust,
    specifyBdRunnerFor: specifyBdRunnerFor,
    live: live,
  );

  test('state-store maintenance follows the live posture', () {
    final dryDelegate = delegate();
    final liveDelegate = delegate(live: true);
    addTearDown(dryDelegate.dispose);
    addTearDown(liveDelegate.dispose);

    expect(dryDelegate.maintainsStateStoreOnBoot, isFalse);
    expect(liveDelegate.maintainsStateStoreOnBoot, isTrue);
  });

  test('the coded roster snapshot carries per-substation asset rosters', () {
    final snapshot = codedRosterSnapshotOf(_AssetRosterDelegate.new);

    expect(
      snapshot.scopes.map((scope) => scope.name),
      orderedEquals(['authored', 'polling']),
    );
    expect(snapshot.githubPollingSubstationNames, {'polling'});
    expect(snapshot.assetRosters.keys, orderedEquals(['authored']));
    expect(
      snapshot.assetRosters['authored'],
      same(_AssetRosterDelegate.assetRoster),
    );
    expect(
      () => snapshot.assetRosters['polling'] = _AssetRosterDelegate.assetRoster,
      throwsUnsupportedError,
    );
  });

  test('the barrel re-exports the roster override vocabulary', () {
    final override = station.GridAssetRosterOverride(
      include: <station.AssetKey>{},
    );

    expect(override.include, isEmpty);
  });

  group('SpaceDelegate.build — space_station as a Seed (v3 §2)', () {
    test('the well-formed offline tree mounts clean (ProviderScope → '
        'RawAssetGrid → Station → HarnessProvider → Substations → the seven '
        'coded SubstationSeed wrappers validate end to end)', () {
      expect(() => _mount(_Author(delegate())), returnsNormally);
    });

    test('the DRY tree (the default) binds NO delivery anywhere — the effect '
        'providers are ABSENT from the tree, so every substation bundle is '
        'commit-only (space-47t: inertness declared in the tree)', () {
      final bundles = _mountedBundles(_Author(delegate()));
      expect(
        bundles,
        hasLength(7),
        reason: 'one gated bundle per coded substation',
      );
      expect(bundles.every((b) => b.delivery == null), isTrue);
    });

    test('a LIVE delegate authors the effect providers IN-TREE and every '
        'coded substation binds GitHub delivery by OBSERVING both halves '
        '(space-47t: no effect instance passes through boot)', () {
      final bundles = _mountedBundles(_Author(delegate(live: true)));
      expect(
        bundles.where((b) => b.delivery != null),
        hasLength(7),
        reason: 'each coded substation re-provides its bundle delivery-bound',
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

    test('resolveGitHubSelfTrustFromGh SKIPS gh when NO armed substation polls '
        '— the '
        'function\'s own contract, keyed on the flag; and the coded roster now '
        'reports seven polling substations, so a live boot reaches the probe '
        'instead '
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
      expect(roster.githubPollingSubstationNames, hasLength(7));
    });

    test('the seven LIVE poll values author NO reconciler runtime on an '
        'OFFLINE '
        'mount: without self trust the per-substation binding provides no cursor '
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

    test(
      'an appended (--substation) substation mounts clean after the literal '
      'coded org (space-6ds: the seven coded substations are always authored)',
      () {
        expect(
          () => _mount(
            _Author(delegate(appended: [sdk.Substation('tgdog', '/work/td')])),
          ),
          returnsNormally,
        );
      },
    );

    test(
      'a LIVE flag-appended substation retains git and gate but binds no delivery',
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
        expect(bundles, hasLength(8));
        expect(
          bundles.take(7).every((bundle) => bundle.delivery != null),
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
    test('the mounted registry defaults to the first-party claude set', () {
      expect(
        codedSeatEnvironmentsOf(SpaceDelegate.new).registry.names,
        contains('claude'),
      );
    });

    test('environments is a build method resolved by the offline mount', () {
      _BuildMethodProbeDelegate.reset();
      final unmounted = _BuildMethodProbeDelegate(gridRoot: '/unmounted');
      expect(_BuildMethodProbeDelegate.environmentBuilds, 0);
      expect(_BuildMethodProbeDelegate.delegateBuilds, 0);
      unmounted.dispose();

      _BuildMethodProbeDelegate.reset();
      const configuration = sdk.GridConfiguration(
        settings: {'probe': 'configuration'},
      );
      final snapshot = codedSeatEnvironmentsOf(
        _BuildMethodProbeDelegate.new,
        gridRoot: '/mounted',
        configuration: configuration,
      );

      expect(_BuildMethodProbeDelegate.delegateBuilds, 1);
      expect(_BuildMethodProbeDelegate.environmentBuilds, 1);
      expect(_BuildMethodProbeDelegate.disposals, 1);
      expect(_BuildMethodProbeDelegate.observedContext, isNotNull);
      expect(_BuildMethodProbeDelegate.observedConfiguration, configuration);
      expect(snapshot.registry, same(_BuildMethodProbeDelegate.registry));
    });

    test('constructor registry injection short-circuits environments', () {
      _BuildMethodProbeDelegate.reset();
      final injected = station.buildMementoEnvironmentRegistry();
      final subject = _BuildMethodProbeDelegate(
        gridRoot: '/injected',
        harnesses: injected,
      );
      try {
        final mounted = mountedValuesOf<Object>(subject);
        expect(mounted.whereType<EnvironmentRegistry>().first, same(injected));
        expect(_BuildMethodProbeDelegate.delegateBuilds, 1);
        expect(_BuildMethodProbeDelegate.environmentBuilds, 0);
      } finally {
        subject.dispose();
      }
    });
  });

  group('SpaceDelegate — resident work policy hooks', () {
    test('defaults retain migration-aware routing and the code registry', () {
      final subject = delegate();
      expect(subject.circuitOverrideFor(const Bead(id: 'space-code')), isNull);

      final registry = subject.buildWorkRegistry(
        (_, _) async {},
        _ignoreSpecifyAuthoredSpec,
      );
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

    test('two-parameter downstream registry override still composes', () {
      final subject = _MarkerDelegate(gridRoot: '/home/space');
      Future<void> appendNote(String beadId, String line) async {}
      Future<void> writeSpecifyAuthoredSpec(
        String beadId, {
        required String design,
        required String acceptanceCriteria,
      }) => _ignoreSpecifyAuthoredSpec(
        beadId,
        design: design,
        acceptanceCriteria: acceptanceCriteria,
      );
      expect(
        subject.circuitOverrideFor(const Bead(id: 'space-marker')),
        same(_MarkerDelegate.markerCircuit),
      );
      expect(subject.circuitOverrideFor(const Bead(id: 'space-code')), isNull);

      final registry = subject.buildWorkRegistry(
        appendNote,
        writeSpecifyAuthoredSpec,
      );
      expect(registry.circuit('code'), same(kCodeCircuit));
      expect(subject.receivedAppender, same(appendNote));
      expect(subject.receivedSpecWriter, same(writeSpecifyAuthoredSpec));
    });

    test('resident registry forwards the exact specify writer', () async {
      const beadId = 'space-spec';
      const design =
          '## Implementation Plan\n\n### Step 1 — thread the writer\n';
      const acceptance =
          '- [ ] AC-1 — preserve the design\n'
          '- [ ] AC-2 — preserve the acceptance text';
      const nodePath = '$beadId/spec_review/specify';
      final workspace = Directory.current.createTempSync(
        '.space-specify-writer-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      File(p.join(workspace.path, usageReportPath(nodePath)))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'type': 'result',
            'duration_ms': 100,
            'num_turns': 1,
            'usage': {'input_tokens': 8, 'output_tokens': 5},
            'result': jsonEncode({'acceptance': acceptance, 'design': design}),
          }),
        );
      final recorder = _RecordingSpecWriter();
      final readback = _RecordingBdRunner();
      final subject = delegate(specifyBdRunnerFor: (_) => readback);
      final registry = subject.buildWorkRegistry(
        (_, _) async {},
        recorder.record,
      );
      final capability =
          (registry.host(_specifyMount(beadId)) as CapabilityHost).capability
              as SpecifyCapability;

      await capability.result(
        FakeTreeContext(
          values: {
            Bead: const Bead(id: beadId),
            Workspace: testWorkspace(
              beadId,
              workspaceDir: workspace.path,
              branch: 'grid/$beadId',
            ),
          },
        ),
        stepArgs(nodePath),
      );

      expect(recorder.calls, [
        (beadId: beadId, design: design, acceptanceCriteria: acceptance),
      ]);
      expect(readback.argvs, [
        ['query', 'id=space-spec', '--json', '--limit', '0'],
      ]);
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
        contains(
          'registryBuilderWithSpecWriter: '
          '(appendNote, writeSpecifyAuthoredSpec) =>\n'
          '            workPolicyDelegate.buildWorkRegistry(\n'
          '              appendNote,\n'
          '              writeSpecifyAuthoredSpec,\n'
          '            ),',
        ),
      );
      expect(source, isNot(contains('registryBuilder:')));
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

    test('coded seat snapshot owns the mount and includes substation '
        'preferences', () {
      final snapshot = codedSeatEnvironmentsOf(
        _InvalidSubstationSeatDelegate.new,
      );

      expect(snapshot.station, isNotNull);
      expect(snapshot.preferences, hasLength(5));
      expect(
        snapshot.preferences.last,
        same(_InvalidSubstationSeatDelegate.invalidPreference),
      );
      expect(
        () => snapshot.preferences.add(
          _InvalidSubstationSeatDelegate.invalidPreference,
        ),
        throwsUnsupportedError,
      );
      final refusal = station.preferenceArmingRefusal(
        snapshot.preferences,
        snapshot.registry,
      );
      expect(refusal, contains('_InvalidSeatPreference'));
      expect(refusal, contains('normal form'));
    });

    test('seat policy is read only through mounted build snapshots', () {
      final delegateSource = File(
        'lib/src/space_delegate.dart',
      ).readAsStringSync();
      final upSource = File('lib/src/up_command.dart').readAsStringSync();
      final snapshotStart = delegateSource.indexOf(
        'CodedSeatEnvironmentSnapshot codedSeatEnvironmentsOf(',
      );
      final snapshotEnd = delegateSource.indexOf(
        '\n/// The delegate memento',
        snapshotStart,
      );
      final snapshotSource = delegateSource.substring(
        snapshotStart,
        snapshotEnd,
      );
      final runSource = upSource.substring(
        upSource.indexOf('Future<int> run() async'),
      );

      for (final retired in const <String>[
        'codedArmingOf',
        'AgentArming',
        'TypedEnvironmentProvider',
      ]) {
        expect(delegateSource, isNot(contains(retired)), reason: retired);
        expect(upSource, isNot(contains(retired)), reason: retired);
      }
      expect(
        delegateSource,
        isNot(matches(RegExp(r'EnvironmentRegistry\s+get\s+environments'))),
      );
      expect(
        delegateSource,
        isNot(matches(RegExp(r'List<SingleChildSeed>\s+get\s+seatSeeds'))),
      );
      expect(
        delegateSource,
        isNot(contains('late final EnvironmentRegistry harnesses')),
      );
      expect(snapshotSource, contains('mountedValuesOf<Object>('));
      expect(
        RegExp(r'mountedValuesOf<Object>\(').allMatches(snapshotSource),
        hasLength(1),
      );
      expect(
        RegExp(r'codedSeatEnvironmentsOf\(').allMatches(runSource),
        hasLength(1),
        reason: 'run owns one requested-home seat snapshot through boot',
      );
      expect(runSource, contains('codedSeats.registry'));
      expect(runSource, contains('codedSeats.preferences'));
      expect(runSource, contains('codedSeats.station'));
      expect(
        upSource,
        isNot(matches(RegExp(r'delegate\.(?:arming|environments)'))),
      );
    });

    test('dependency floors and breaking release note name coordinated '
        'widening', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final changelog = File('CHANGELOG.md').readAsStringSync();
      final lockfile = File('../../pubspec.lock').readAsStringSync();

      expect(
        pubspec,
        matches(RegExp(r'version: 0\.4\.0(?:-rc\.\d+)?$', multiLine: true)),
      );
      expect(pubspec, contains('grid_assets: ^0.7.0-dev.1'));
      expect(pubspec, contains('grid_sdk: ^0.3.0'));
      expect(changelog, matches(RegExp(r'^# Changelog\n\n## Unreleased\n')));
      const breakingLine =
          '- Breaking: Removes SpaceDelegate.arming, SpaceDelegate.harnesses, codedArmingOf, and SubstationSeed.arming; SpaceDelegate.environments now takes (context, configuration), open seat-provider seeds mount during build, and codedSeatEnvironmentsOf returns CodedSeatEnvironmentSnapshot.';
      const migrationLine =
          '  Migration: Extending stations replace an arming getter with seatSeeds(context, configuration), returning one seat.provider() seed per preference, and override environments(context, configuration); lunar adopts this in its separate downstream bead.';
      expect(changelog, contains('$breakingLine\n$migrationLine\n'));
      expect(
        changelog,
        matches(RegExp(r'^## 0\.4\.0(?:-rc\.\d+)?$', multiLine: true)),
      );
      expect(changelog, contains('Breaking: coordinated widening (A)'));
      expect(changelog, contains('Lunar adopts it separately'));
      expect(changelog, contains('grid_assets ^0.6.0'));
      expect(changelog, contains('grid_sdk ^0.3.0'));

      String lockEntry(String package) {
        final header = '  $package:\n';
        final start = lockfile.indexOf(header);
        expect(start, greaterThanOrEqualTo(0));
        final rest = lockfile.substring(start + header.length);
        final nextPackage = RegExp(
          r'^  [a-zA-Z0-9_]+:\n',
          multiLine: true,
        ).firstMatch(rest);
        return rest.substring(0, nextPackage?.start ?? rest.length);
      }

      expect(lockEntry('grid_assets'), contains('version: "0.7.0-dev.1"'));
      expect(lockEntry('grid_sdk'), contains('version: "0.3.0"'));
    });
  });
}

/// Mounts [root] in a bare tree and flushes one build pass (the Track B/F
/// template).
void _mount(Seed root) {
  final owner = TreeOwner();
  // The coded substations carry the org App (space-u8q), so each mounts a
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
/// A commit-only substation provides ONE bundle (its git asset's); a
/// delivery-bound substation re-provides a second, delivery-carrying bundle
/// below it, so the outermost bundle per substation is filtered to the DEEPEST
/// per substation by taking `delivery != null` counts where bound.
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
  // A substation mounts SEVERAL bundles as its stack assets each re-provide:
  // git's,
  // GitHub's delivery re-provision, and innermost the one the mount gate
  // derives. Only the innermost is what `SubstationWork` resolves, so it is
  // the only one a substation-posture assertion means.
  //
  // `MountEligibilityAssets` is mounted innermost on EVERY substation, so
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
  sdk.SpecifyAuthoredSpecWriter? receivedSpecWriter;

  @override
  sdk.Circuit? circuitOverrideFor(Bead bead) =>
      bead.id == 'space-marker' ? markerCircuit : null;

  @override
  sdk.CapabilityRegistry buildWorkRegistry(
    NoteAppender appendNote,
    sdk.SpecifyAuthoredSpecWriter writeSpecifyAuthoredSpec,
  ) {
    receivedAppender = appendNote;
    receivedSpecWriter = writeSpecifyAuthoredSpec;
    return super.buildWorkRegistry(appendNote, writeSpecifyAuthoredSpec);
  }
}

class _AssetRosterDelegate extends SpaceDelegate {
  _AssetRosterDelegate({
    required super.gridRoot,
    super.agentConfig,
    super.appended,
    super.harnesses,
    super.wiring,
    super.provisioner,
    super.githubSelfTrust,
    super.live,
  });

  static const assetKey = sdk.AssetKey(
    package: 'fixture_assets',
    kind: sdk.AssetKind.skill,
    id: 'authored',
  );
  static final assetRoster = GridAssetRosterOverride(include: {assetKey});

  @override
  List<Seed> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    station.SubstationSeed(
      name: 'authored',
      root: '../authored',
      assetRoster: assetRoster,
    ),
    station.SubstationSeed(
      name: 'polling',
      root: '../polling',
      githubPoll: const github.GitHubReconcilerConfig(
        owner: 'fixture',
        repository: 'polling',
        substation: 'polling',
        installationId: '1',
        arm: github.GitHubReconcilerArm.offline,
      ),
    ),
  ];
}

class _BuildMethodProbeDelegate extends SpaceDelegate {
  _BuildMethodProbeDelegate({
    required super.gridRoot,
    super.agentConfig,
    super.appended,
    super.harnesses,
    super.wiring,
    super.provisioner,
    super.githubSelfTrust,
    super.live,
  });

  static int delegateBuilds = 0;
  static int environmentBuilds = 0;
  static int disposals = 0;
  static TreeContext? observedContext;
  static sdk.GridConfiguration? observedConfiguration;
  static EnvironmentRegistry? registry;

  static void reset() {
    delegateBuilds = 0;
    environmentBuilds = 0;
    disposals = 0;
    observedContext = null;
    observedConfiguration = null;
    registry = null;
  }

  @override
  EnvironmentRegistry environments(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) {
    environmentBuilds += 1;
    observedContext = context;
    observedConfiguration = configuration;
    return registry = station.buildMementoEnvironmentRegistry();
  }

  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) {
    delegateBuilds += 1;
    return super.build(context, configuration);
  }

  @override
  void dispose() {
    disposals += 1;
    super.dispose();
  }
}

class _InvalidSubstationSeatDelegate extends SpaceDelegate {
  _InvalidSubstationSeatDelegate({
    required super.gridRoot,
    super.agentConfig,
    super.appended,
    super.harnesses,
    super.wiring,
    super.provisioner,
    super.githubSelfTrust,
    super.live,
  });

  static const invalidPreference = _InvalidSeatPreference([
    AgentEnvironment(
      base: EnvBaseRef('claude', scope: BaseScope.builtin),
      model: 'opus',
    ),
  ]);

  @override
  List<Seed> substations(
    TreeContext context,
    sdk.GridConfiguration configuration,
  ) => [
    station.SubstationSeed(
      name: 'invalid-seat',
      root: '../invalid-seat',
      seatSeeds: [invalidPreference.provider()],
    ),
  ];
}

class _InvalidSeatPreference extends station.SeatPreference {
  const _InvalidSeatPreference(super.entries);

  @override
  SingleChildSeed provider() =>
      station.SeatProvider<_InvalidSeatPreference>(this);
}

String _materializeDiscoverSkill(SpaceDelegate delegate) {
  addTearDown(delegate.dispose);
  final worktree = Directory.systemTemp.createTempSync('delegate-overlay-');
  addTearDown(() {
    if (worktree.existsSync()) worktree.deleteSync(recursive: true);
  });

  final registry = delegate.buildWorkRegistry(
    (_, _) async {},
    _ignoreSpecifyAuthoredSpec,
  );
  final capability =
      (registry.host(_overlayAgentMount()) as CapabilityHost).capability
          as AgentCapability;
  capability.spawn(
    FakeTreeContext(
      values: {
        Bead: const Bead(id: 'space-overlay'),
        sdk.SubstationScope: sdk.SubstationScope(
          name: 'space_station',
          root: worktree.path,
          prefix: 'space',
        ),
        SubstationFactsSnapshot: SubstationFactsSnapshot({
          const SubstationKey('space_station'): SubstationFacts(
            root: worktree.path,
            dartPackages: const ['grid_assets'],
            packageRoots: {
              'grid_assets': p.dirname(PackagedAssetLoader().root),
            },
          ),
        }),
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

Future<void> _ignoreSpecifyAuthoredSpec(
  String beadId, {
  required String design,
  required String acceptanceCriteria,
}) async {}

final class _RecordingSpecWriter {
  final List<({String beadId, String design, String acceptanceCriteria})>
  calls = [];

  Future<void> record(
    String beadId, {
    required String design,
    required String acceptanceCriteria,
  }) async => calls.add((
    beadId: beadId,
    design: design,
    acceptanceCriteria: acceptanceCriteria,
  ));
}

final class _RecordingBdRunner implements BdRunner {
  final List<List<String>> argvs = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.unmodifiable(args));
    return const BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":[]}',
      stderr: '',
    );
  }
}

class _OverlayIdentityDelegate extends SpaceDelegate {
  _OverlayIdentityDelegate({required super.gridRoot, required this.sourceRef});

  final String sourceRef;

  @override
  String get runnerInvocation => 'dart run lunar:lunar';

  @override
  String get overlaySourceRef => sourceRef;
}
