import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart'
    show Bead, BdResult, BdRunner, BeadStatus, IssueType;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart' as github;
import 'package:grid_assets/grid_assets.dart'
    show
        GitSourceControl,
        kApprovedAtKey,
        kApprovedByKey,
        kApprovedLabel,
        kApprovedRevKey;
import 'package:grid_engine/grid_engine.dart'
    show
        MountEligibilityDecision,
        MountEligible,
        MountRefused,
        ServiceBundle,
        TrustFloor,
        TrustLevel;
import 'package:grid_runtime/grid_runtime.dart'
    show GitOps, PrOpener, PullRequestRef, PullRequestResult, SystemGitRunner;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_sdk/grid_sdk.dart' show Provider, ProviderScope;
import 'package:space_station_assets/src/substation_seed.dart';
import 'package:test/test.dart';

/// space-47t: the ONE composed seed ([SubstationSeed]) and its `const`,
/// watch-based stack assets ([GitGridAssets] / imported GitHub assets). Pure +
/// offline — every tree mounts in a bare genesis [TreeOwner] under a
/// [ProviderScope] (the availability registry `runGrid` mounts at the
/// production root).
void main() {
  group('SubstationSeed — the composed seed', () {
    test(
      'explicit landing policies are observable on the effective gated seat',
      () {
        const policies = <github.GitHubDeliveryPolicy>[
          github.PrNoMergePolicy(),
          github.PrAutoMergePolicy(),
          github.DirectMergePolicy(),
        ];

        for (final policy in policies) {
          final walk = _mount(
            ProviderScope(
              child: sdk.RawAssetGrid(
                root: '/home/me/station',
                assets: [
                  Provider<GitOps>(
                    create: (_) => GitOps(SystemGitRunner()),
                    child: Provider<PrOpener>.value(
                      _FakePrOpener(),
                      child: SubstationSeed(
                        name: 'mine',
                        root: '../mine',
                        landingPolicy: policy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          expect(
            walk.values<github.GitHubDeliveryPolicy>().single,
            same(policy),
          );
          final gated = _gated(walk);
          final deliveryMatcher = switch (policy) {
            github.PrNoMergePolicy() => isA<github.GitHubPrDelivery>(),
            github.PrAutoMergePolicy() => isA<github.GitHubAutoMergeDelivery>(),
            github.DirectMergePolicy() =>
              isA<github.GitHubDirectMergeDelivery>(),
          };
          expect(gated.delivery, deliveryMatcher);
          expect(gated.sourceControl, isNotNull);
          expect(gated.mountEligibility, isNotNull);
        }
      },
    );

    test(
      'omitted landing policy preserves PR-without-merge and mounts no value',
      () {
        final walk = _mount(
          ProviderScope(
            child: sdk.RawAssetGrid(
              root: '/home/me/station',
              assets: [
                Provider<GitOps>(
                  create: (_) => GitOps(SystemGitRunner()),
                  child: Provider<PrOpener>.value(
                    _FakePrOpener(),
                    child: SubstationSeed(name: 'mine', root: '../mine'),
                  ),
                ),
              ],
            ),
          ),
        );
        expect(walk.values<github.GitHubDeliveryPolicy>(), isEmpty);
        final gated = _gated(walk);
        expect(gated.delivery, isA<github.GitHubPrDelivery>());
        expect(gated.sourceControl, isNotNull);
        expect(gated.mountEligibility, isNotNull);
      },
    );

    test('mounts its Substation UNDER the wrapper: the offline roster '
        'enumeration still finds the SubstationScope (space-47t b: '
        'codedRosterOf/mountedRosterOf are unaffected)', () {
      final walk = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              SubstationSeed(name: 'mine', root: '../mine', prefix: 'mn'),
            ],
          ),
        ),
      );
      final scope = walk.values<sdk.SubstationScope>().single;
      expect(scope.name, 'mine');
      expect(scope.root, '/home/me/mine');
      expect(scope.prefix, 'mn');
    });

    test('THE MOUNT GATE IS COMPOSED: the seat\'s ServiceBundle carries a '
        'mountEligibility predicate that ADMITS an approved, STAMPED, '
        'plan-stamped, driveable bead and REFUSES one missing any of the '
        'four — every refusal CONFIRMED against a fresh store read', () async {
      final store = _FakeMountGateRunner();
      final owned = _mountOwned(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              SubstationSeed(
                name: 'mine',
                root: '../mine',
                mountEligibilityRunnerFor: (storeRoot) {
                  store.roots.add(storeRoot);
                  return store;
                },
              ),
            ],
          ),
        ),
      );
      final walk = owned.walk;

      // pow-50l shipped MountEligibilityAssets and NOTHING mounted it, so the
      // gate was inert on every station: a bead with no `grid.approved` label
      // and an OPEN blocker was mounted by the live lunar arm within minutes
      // of being filed. Absence of this predicate is the whole defect.
      final gated = _gated(walk);
      final predicate = gated.mountEligibility;
      // The gate DERIVES: it must carry the git half forward, not replace it.
      // (GitGridAssets rebuilds the bundle from scratch, which is exactly why
      // this seed is mounted innermost.)
      expect(
        gated.sourceControl,
        isNotNull,
        reason:
            'the gate derives from the ambient bundle — a gate that '
            'dropped sourceControl would break provisioning for every seat',
      );
      expect(
        predicate,
        isNotNull,
        reason:
            'an unmounted MountEligibilityAssets is an INERT gate — the '
            'station admits whatever reaches the ready frontier',
      );

      // An ELIGIBLE snapshot answers SYNCHRONOUSLY — the whole point of the
      // rc.6 two-phase gate: only a REFUSAL costs a store read.
      expect(predicate!(_bead()), isA<MountEligible>());
      expect(
        store.reads,
        isEmpty,
        reason: 'admitting a stamped bead spends no store read',
      );
      expect(
        store.roots,
        everyElement('/home/me/mine'),
        reason: "the gate's bd seam is bound to the SEAT's own work store",
      );

      /// Drives one refusal through BOTH phases and returns the CONFIRMED
      /// decision: rc.6 answers a refused snapshot with a pending projection
      /// and re-reads the seat's own work store, so the clause an operator
      /// ever sees is the second one.
      Future<MountEligibilityDecision> confirmedRefusal(Bead bead) async {
        store.fresh = bead;
        expect(
          predicate(bead),
          isA<MountRefused>().having(
            (r) => r.clause,
            'clause',
            'fresh mount-eligibility read pending: mine-1',
          ),
          reason: 'phase 1 — the snapshot refusal projects the pending read',
        );
        await pumpEventQueue();
        owned.owner.flush();
        return predicate(bead);
      }

      expect(
        await confirmedRefusal(_bead(labels: const [])),
        isA<MountRefused>().having(
          (r) => r.clause,
          'clause',
          contains(kApprovedLabel),
        ),
        reason: 'no grid.approved label — the human approval gate',
      );
      expect(
        await confirmedRefusal(_bead(metadata: const {})),
        isA<MountRefused>().having(
          (r) => r.clause,
          'clause',
          contains('validation_plan'),
        ),
        reason:
            "no validation_plan — the committee's gating lane would run "
            '`false` and grade F by design',
      );
      expect(
        await confirmedRefusal(_bead(type: IssueType.epic)),
        isA<MountRefused>().having((r) => r.clause, 'clause', contains('type')),
        reason: 'an epic is organisational, never driveable',
      );
      // The FOURTH leg, new in rc.6 (power_station `pow-kps`): the label
      // WITHOUT the approve verb's receipt is not approval. Four `pow-n6n`
      // children mounted ahead of their blockers on 2026-09-02 on a
      // hand-added label alone.
      expect(
        await confirmedRefusal(
          _bead(metadata: const {'validation_plan': 'dart test'}),
        ),
        isA<MountRefused>().having(
          (r) => r.clause,
          'clause',
          'approval: unstamped label - approve with the approve verb',
        ),
        reason:
            'a hand-added grid.approved carries no grid.approved_at — only '
            'the `space approve` verb writes the receipt',
      );
      expect(
        store.reads,
        hasLength(4),
        reason: 'exactly one confirming read per refusal, none per admit',
      );
    });

    test('delivery identity selects App opener or ambient fallback', () {
      final transport = _FakeTransport();
      final client = _fakeClient(transport);
      const identity = GitHubAppConfig(
        appId: '1234',
        installationId: '99',
        privateKeyVar: 'MY_APP_KEY',
      );
      final app = _mount(
        ProviderScope(
          child: Provider<github.GitHubAppClient>.value(
            client,
            child: Provider<GitOps>(
              create: (_) => GitOps(SystemGitRunner()),
              child: sdk.RawAssetGrid(
                root: '/home/me/station',
                assets: [
                  SubstationSeed(name: 'mine', root: '../mine', app: identity),
                ],
              ),
            ),
          ),
        ),
      );
      expect(app.values<PrOpener>().single, isA<github.GitHubAppPrOpener>());

      final ambient = _FakePrOpener();
      final noApp = _mount(
        ProviderScope(
          child: Provider<github.GitHubAppClient>.value(
            client,
            child: Provider<GitOps>(
              create: (_) => GitOps(SystemGitRunner()),
              child: Provider<PrOpener>.value(
                ambient,
                child: sdk.RawAssetGrid(
                  root: '/home/me/station',
                  assets: [SubstationSeed(name: 'mine', root: '../mine')],
                ),
              ),
            ),
          ),
        ),
      );
      expect(identical(noApp.values<PrOpener>().single, ambient), isTrue);

      expect(
        () => _mount(
          ProviderScope(
            child: Provider<github.GitHubAppClient>.value(
              client,
              child: Provider<GitOps>(
                create: (_) => GitOps(SystemGitRunner()),
                child: sdk.RawAssetGrid(
                  root: '/home/me/station',
                  assets: [
                    SubstationSeed(
                      name: 'mine',
                      root: '../mine',
                      app: const GitHubAppConfig(
                        appId: '1234',
                        installationId: 'not-an-int',
                        privateKeyVar: 'MY_APP_KEY',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        throwsA(isA<FormatException>()),
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

    test('app identity on an effects-enabled seat provides its own '
        'GitHubAppClient', () async {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              SubstationSeed(
                name: 'org',
                root: '../org',
                app: const GitHubAppConfig(
                  appId: '101',
                  installationId: '201',
                  privateKeyVar: 'ORG_APP_KEY',
                ),
                githubPoll: const github.GitHubReconcilerConfig(
                  owner: 'memento',
                  repository: 'org',
                  substation: 'org',
                  installationId: '201',
                ),
                githubAppCredentialLoader: _FakeGitHubAppCredentials.loader(),
                githubTransportFactory: _FakeGitHubAppCredentials.transport,
              ),
            ],
          ),
        ),
      );
      await _settle(owner);
      final walk = _Walk(root);
      expect(walk.values<github.GitHubAppClient>(), hasLength(1));
      final identity = walk.values<GitHubAppConfig>().single;
      expect((identity.appId, identity.installationId), ('101', '201'));
    });

    test('app identity on a dry arm provides no GitHubAppClient', () async {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              SubstationSeed(
                name: 'org',
                root: '../org',
                app: const GitHubAppConfig(
                  appId: '101',
                  installationId: '201',
                  privateKeyVar: 'ORG_APP_KEY',
                ),
                githubPoll: const github.GitHubReconcilerConfig(
                  owner: 'memento',
                  repository: 'org',
                  substation: 'org',
                  installationId: '201',
                  arm: github.GitHubReconcilerArm.dry,
                ),
                githubAppCredentialLoader: _FakeGitHubAppCredentials.loader(),
                githubTransportFactory: _FakeGitHubAppCredentials.transport,
              ),
            ],
          ),
        ),
      );
      await _settle(owner);
      expect(_Walk(root).values<github.GitHubAppClient>(), isEmpty);
    });

    test(
      'no app identity provides no client and preserves ambient opener',
      () async {
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        final ambient = _FakePrOpener();
        final root = owner.mountRoot(
          ProviderScope(
            child: Provider<PrOpener>.value(
              ambient,
              child: Provider<GitOps>(
                create: (_) => GitOps(SystemGitRunner()),
                child: sdk.RawAssetGrid(
                  root: '/home/me/station',
                  assets: [SubstationSeed(name: 'ambient', root: '../ambient')],
                ),
              ),
            ),
          ),
        );
        await _settle(owner);
        final walk = _Walk(root);
        expect(walk.values<github.GitHubAppClient>(), isEmpty);
        expect(identical(walk.values<PrOpener>().single, ambient), isTrue);
      },
    );

    test('sibling app identities provide distinct GitHubAppClients', () async {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              SubstationSeed(
                name: 'org',
                root: '../org',
                app: const GitHubAppConfig(
                  appId: '101',
                  installationId: '201',
                  privateKeyVar: 'ORG_APP_KEY',
                ),
                githubAppCredentialLoader: _FakeGitHubAppCredentials.loader(),
                githubTransportFactory: _FakeGitHubAppCredentials.transport,
              ),
              SubstationSeed(
                name: 'personal',
                root: '../personal',
                app: const GitHubAppConfig(
                  appId: '102',
                  installationId: '202',
                  privateKeyVar: 'PERSONAL_APP_KEY',
                ),
                githubAppCredentialLoader: _FakeGitHubAppCredentials.loader(),
                githubTransportFactory: _FakeGitHubAppCredentials.transport,
              ),
            ],
          ),
        ),
      );
      await _settle(owner);
      final identities = _Walk(root).branches<GitHubAppConfig>();
      final org = identities.singleWhere(
        (branch) => branch.value.appId == '101',
      );
      final personal = identities.singleWhere(
        (branch) => branch.value.appId == '102',
      );
      final orgClient = _Walk(org).values<github.GitHubAppClient>().single;
      final personalClient = _Walk(
        personal,
      ).values<github.GitHubAppClient>().single;
      expect(identical(orgClient, personalClient), isFalse);
      expect(
        identities
            .map((branch) => (branch.value.appId, branch.value.installationId))
            .toList(),
        [('101', '201'), ('102', '202')],
      );
    });
  });

  test(
    'live poll binding constructs the runtime from a fake client and seat-owned stores',
    () async {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final transport = _FakeTransport();
      final root = owner.mountRoot(
        ProviderScope(
          child: Provider<github.GitHubAppClient>.value(
            _fakeClient(transport),
            child: Provider<github.GitHubSelfTrust>.value(
              github.GitHubSelfTrust(githubUser: 'NiCo'),
              child: sdk.RawAssetGrid(
                root: '/home/me/station',
                assets: [
                  SubstationSeed(
                    name: 'armed',
                    root: '../private',
                    githubPoll: const github.GitHubReconcilerConfig(
                      owner: 'private-owner',
                      repository: 'personal-repo',
                      substation: 'armed',
                      installationId: '99',
                      interval: Duration(days: 1),
                    ),
                  ),
                  SubstationSeed(name: 'absent', root: '../other'),
                ],
              ),
            ),
          ),
        ),
      );
      await _settle(owner);
      final scopes = _Walk(root).branches<sdk.SubstationScope>();
      final armed = scopes.singleWhere((b) => b.value.name == 'armed');
      final absent = scopes.singleWhere((b) => b.value.name == 'absent');
      final armedWalk = _Walk(armed);
      final cursor =
          armedWalk.values<github.GitHubCursorStore>().single
              as github.FileGitHubCursorStore;
      expect(
        cursor.cursorPath,
        '/home/me/private/.grid/github/private-owner-personal-repo.cursor.json',
      );
      expect(armedWalk.values<github.GitHubEventSink>(), hasLength(1));
      final runtime = armedWalk.values<github.GitHubReconcilerRuntime>().single;
      expect(runtime.reconciler.owner, 'private-owner');
      expect(runtime.reconciler.repository, 'personal-repo');
      expect(runtime.reconciler.substation, 'armed');
      expect(_Walk(absent).values<github.GitHubCursorStore>(), isEmpty);
      expect(_Walk(absent).values<github.GitHubEventSink>(), isEmpty);
      expect(_Walk(absent).values<github.GitHubReconcilerRuntime>(), isEmpty);
    },
  );

  test(
    'binding stays absent without poll config, live trust, or effects-enabled arm',
    () async {
      final trust = github.GitHubSelfTrust(githubUser: 'NiCo');
      final cases =
          <
            ({
              String name,
              github.GitHubReconcilerConfig? config,
              github.GitHubSelfTrust? trust,
            })
          >[
            (name: 'no config', config: null, trust: trust),
            (
              name: 'dry arm',
              config: const github.GitHubReconcilerConfig(
                owner: 'private-owner',
                repository: 'personal-repo',
                substation: 'inert',
                installationId: '99',
                arm: github.GitHubReconcilerArm.dry,
              ),
              trust: trust,
            ),
            (
              name: 'offline arm',
              config: const github.GitHubReconcilerConfig(
                owner: 'private-owner',
                repository: 'personal-repo',
                substation: 'inert',
                installationId: '99',
                arm: github.GitHubReconcilerArm.offline,
              ),
              trust: trust,
            ),
            (
              name: 'no trust',
              config: const github.GitHubReconcilerConfig(
                owner: 'private-owner',
                repository: 'personal-repo',
                substation: 'inert',
                installationId: '99',
              ),
              trust: null,
            ),
          ];

      for (final posture in cases) {
        final owner = TreeOwner();
        final transport = _FakeTransport();
        final arm = posture.config?.arm;
        final app =
            arm == github.GitHubReconcilerArm.dry ||
                arm == github.GitHubReconcilerArm.offline
            ? const GitHubAppConfig(
                appId: '1234',
                installationId: '99',
                privateKeyVar: 'MY_APP_KEY',
              )
            : null;
        Seed seat = sdk.RawAssetGrid(
          root: '/home/me/station',
          assets: [
            SubstationSeed(
              name: 'inert',
              root: '../private',
              app: app,
              githubPoll: posture.config,
            ),
          ],
        );
        final selfTrust = posture.trust;
        if (selfTrust != null) {
          seat = Provider<github.GitHubSelfTrust>.value(selfTrust, child: seat);
        }
        final root = owner.mountRoot(
          ProviderScope(
            child: Provider<github.GitHubAppClient>.value(
              _fakeClient(transport),
              child: Provider<GitOps>(
                create: (_) => GitOps(SystemGitRunner()),
                child: seat,
              ),
            ),
          ),
        );
        await _settle(owner);
        final walk = _Walk(root);
        expect(
          walk.values<github.GitHubCursorStore>(),
          isEmpty,
          reason: posture.name,
        );
        expect(
          walk.values<github.GitHubEventSink>(),
          isEmpty,
          reason: posture.name,
        );
        expect(
          walk.values<github.GitHubReconcilerRuntime>(),
          isEmpty,
          reason: posture.name,
        );
        expect(transport.calls, 0, reason: posture.name);
        if (arm == github.GitHubReconcilerArm.dry ||
            arm == github.GitHubReconcilerArm.offline) {
          expect(walk.values<PrOpener>(), isEmpty);
          expect(
            walk.values<ServiceBundle>().where((b) => b.delivery != null),
            isEmpty,
          );
        }
        owner.dispose();
      }
    },
  );

  test(
    'sibling live seats own distinct cursor stores under their resolved roots',
    () async {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final transport = _FakeTransport();
      final root = owner.mountRoot(
        ProviderScope(
          child: Provider<github.GitHubAppClient>.value(
            _fakeClient(transport),
            child: Provider<github.GitHubSelfTrust>.value(
              github.GitHubSelfTrust(githubUser: 'NiCo'),
              child: sdk.RawAssetGrid(
                root: '/station',
                assets: [
                  SubstationSeed(
                    name: 'one',
                    root: '/work/one',
                    githubPoll: const github.GitHubReconcilerConfig(
                      owner: 'memento',
                      repository: 'one',
                      substation: 'one',
                      installationId: '99',
                      interval: Duration(days: 1),
                    ),
                  ),
                  SubstationSeed(
                    name: 'two',
                    root: '/work/two',
                    githubPoll: const github.GitHubReconcilerConfig(
                      owner: 'memento',
                      repository: 'two',
                      substation: 'two',
                      installationId: '99',
                      interval: Duration(days: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await _settle(owner);
      final scopes = _Walk(root).branches<sdk.SubstationScope>();
      final first = scopes.singleWhere((branch) => branch.value.name == 'one');
      final second = scopes.singleWhere((branch) => branch.value.name == 'two');
      final firstStore =
          _Walk(first).values<github.GitHubCursorStore>().single
              as github.FileGitHubCursorStore;
      final secondStore =
          _Walk(second).values<github.GitHubCursorStore>().single
              as github.FileGitHubCursorStore;
      expect(identical(firstStore, secondStore), isFalse);
      expect(
        firstStore.cursorPath,
        '/work/one/.grid/github/memento-one.cursor.json',
      );
      expect(
        secondStore.cursorPath,
        '/work/two/.grid/github/memento-two.cursor.json',
      );
    },
  );

  group('GitHubGridAssets — the watch-based delivery binding', () {
    test('delivery fail-safe and private repository coordinates', () {
      // GitOps alone — no opener anywhere: commit-only.
      final opsOnly = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              Provider<GitOps>(
                create: (_) => GitOps(SystemGitRunner()),
                child: SubstationSeed(name: 'mine', root: '../mine'),
              ),
            ],
          ),
        ),
      );
      expect(
        opsOnly.values<ServiceBundle>().where((b) => b.delivery != null),
        isEmpty,
        reason: 'ops without an opener must stay commit-only',
      );

      // Opener alone (an ambient opener with no GitOps anywhere — the seat
      // itself authors an opener only when it observes ops): still
      // commit-only (GitHub can only ADD delivery to a checkout it can
      // commit from).
      final openerOnly = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              Provider<PrOpener>.value(
                _FakePrOpener(),
                child: SubstationSeed(name: 'mine', root: '../mine'),
              ),
            ],
          ),
        ),
      );
      expect(
        openerOnly.values<ServiceBundle>().where((b) => b.delivery != null),
        isEmpty,
        reason: 'an opener without ops must stay commit-only',
      );

      // Both halves: the seat re-provides a delivery-bound bundle.
      final both = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              Provider<GitOps>(
                create: (_) => GitOps(SystemGitRunner()),
                child: Provider<PrOpener>.value(
                  _FakePrOpener(),
                  child: SubstationSeed(name: 'mine', root: '../mine'),
                ),
              ),
            ],
          ),
        ),
      );
      // Exactly ONE seat binds delivery. Assert it on the EFFECTIVE bundle:
      // the gate derives from GitHubGridAssets' bundle and carries `delivery`
      // forward, so a raw `where(delivery != null)` count now sees both.
      expect(_gated(both).delivery, isNotNull);
      expect(
        both.values<ServiceBundle>().where((b) => b.mountEligibility != null),
        hasLength(1),
        reason: 'one gated bundle per seat, and this tree mounts one seat',
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
                  describe: () => _seedStack(),
                ),
              ),
            ],
          ),
        ),
      );
      owner.flush();
      var gated = _gated(_Walk(root));
      expect(
        gated.delivery,
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
          _seedStack(),
        ]),
      );
      owner.flush();
      await _pump();
      owner.flush();
      gated = _gated(_Walk(root));
      expect(
        gated.delivery,
        isNull,
        reason: 'a sibling provider is not an ancestor — still commit-only',
      );

      // The opener now mounts ABOVE the seat (the production shape: the seat
      // value gains an app identity, or the station's live arm authors the
      // ambient opener): the re-described subtree observes it and BINDS.
      host.swap(
        () => Provider<PrOpener>.value(_FakePrOpener(), child: _seedStack()),
      );
      owner.flush();
      await _pump();
      owner.flush();
      gated = _gated(_Walk(root));
      expect(
        gated.delivery,
        isNotNull,
        reason: 'both halves observed: delivery-bound',
      );
    });

    test('a non-default ambient trustFloor SURVIVES the delivery rebind — '
        'silently dropping it would reset the substation\'s admitted-origin '
        'floor to `trusted` exactly when PR-opening delivery is armed', () {
      final walk = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              Provider<GitOps>(
                create: (_) => GitOps(SystemGitRunner()),
                child: Provider<PrOpener>.value(
                  _FakePrOpener(),
                  child: InheritedSeed<ServiceBundle>(
                    value: const ServiceBundle(
                      sourceControl: GitSourceControl(),
                      trustFloor: TrustFloor(TrustLevel.self),
                    ),
                    child: const github.GitHubGridAssets(child: _Leaf()),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      final bound = walk
          .values<ServiceBundle>()
          .where((b) => b.delivery != null)
          .single;
      expect(
        bound.trustFloor.level,
        TrustLevel.self,
        reason: 'every ambient field rides the rebind — the floor included',
      );
    });

    test('STANDALONE GitHubGridAssets (no ambient bundle) binds NOTHING even '
        'with both halves observed — GitHub can only ADD delivery to a '
        'checkout it can commit from, never conjure one', () {
      final walk = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [
              Provider<GitOps>(
                create: (_) => GitOps(SystemGitRunner()),
                child: Provider<PrOpener>.value(
                  _FakePrOpener(),
                  child: const github.GitHubGridAssets(child: _Leaf()),
                ),
              ),
            ],
          ),
        ),
      );
      expect(
        walk.values<ServiceBundle>(),
        isEmpty,
        reason:
            'no source control above ⇒ no bundle is provided at all — '
            'a delivery over no checkout is the conjured posture the '
            'fail-safe forbids',
      );
    });

    test('a NO-OP re-description does not notify bundle dependents: the '
        're-derived ServiceBundle is a fresh instance, but equal derivation '
        'inputs suppress the notification (grid_engine WorkList treats the '
        'ambient bundle as a config axis)', () async {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      late _HostState host;
      var probeBuilds = 0;
      final probe = _BundleDependent(onBuild: () => probeBuilds++);
      // The SAME probe instance rides every description (identical-skip),
      // so any extra build can only arrive through dependency notification.
      Seed describe() => sdk.Substation(
        'mine',
        '../mine',
        assets: [GitGridAssets(child: probe)],
      );
      owner.mountRoot(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [_Host(onCreate: (s) => host = s, describe: describe)],
          ),
        ),
      );
      owner.flush();
      expect(probeBuilds, 1);
      // Re-describe with FRESH (non-identical) asset seeds and UNCHANGED
      // derivation inputs: the asset rebuilds and re-derives a new bundle
      // instance, but input equality suppresses updateShouldNotify.
      host.swap(describe);
      owner.flush();
      await _pump();
      owner.flush();
      expect(
        probeBuilds,
        1,
        reason:
            'an input-equal re-derivation must not rebuild dependents — '
            'instance-identity notification would re-run every WorkList '
            'build beneath the seat on any ancestor re-description',
      );
    });
  });

  group('a non-git seed (STYLE rule 4: no provider is universal)', () {
    test('a composed seat whose stack carries NO git assets mounts clean '
        'with neither StationGitService nor GitOps anywhere in the tree, '
        'and the roster enumeration still sees it', () {
      final walk = _mount(
        ProviderScope(
          child: sdk.RawAssetGrid(
            root: '/home/me/station',
            assets: [const _NonGitSeed(name: 'notes', root: '../notes')],
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

/// A composed seed with a DIFFERENT stack — the test-only proof that a
/// non-git substation composes without `StationGitService`/`GitOps` (no
/// production seed needs this yet, so none ships in lib).
class _NonGitSeed extends StatelessSeed {
  const _NonGitSeed({required this.name, required this.root});

  final String name;
  final String root;

  @override
  Seed build(TreeContext context) =>
      sdk.Substation(name, root, assets: const [sdk.SubstationWork()]);
}

/// The standard seed stack under test (no app identity — the opener, when
/// present, is ambient).
Seed _seedStack() => SubstationSeed(name: 'mine', root: '../mine');

_Walk _mount(Seed root) => _mountOwned(root).walk;

/// [_mount], keeping the [TreeOwner] — the mount gate's CONFIRMING re-read
/// lands asynchronously, so its test must `flush()` the owner between the
/// pending answer and the confirmed one.
({TreeOwner owner, _Walk walk}) _mountOwned(Seed root) {
  final owner = TreeOwner();
  final branch = owner.mountRoot(root);
  owner.flush();
  return (owner: owner, walk: _Walk(branch));
}

/// The mount gate's `bd` seam as a FAKE (house rule: Fakes, not mocks).
///
/// Every `bd query` answers with [fresh], enveloped in the same
/// `{schema_version, data}` shape `test/filing_composition_test.dart`'s
/// `_ScriptedBdRunner` uses — so a refused snapshot's confirming re-read
/// resolves offline, with no process and no store on disk.
final class _FakeMountGateRunner implements BdRunner {
  /// The bead the store reports on the confirming re-read.
  Bead fresh = _bead();

  /// Every work-store root the gate asked for a runner against.
  final List<String> roots = <String>[];

  /// Every `bd` argv the gate actually spent on a confirming read.
  final List<List<String>> reads = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    reads.add(args);
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode({
        'schema_version': 1,
        'data': [fresh.toJson()],
      }),
      stderr: '',
    );
  }
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

  List<InheritedBranch<T>> branches<T extends Object>() {
    final found = <InheritedBranch<T>>[];
    void walk(Branch branch) {
      if (branch is InheritedBranch<T>) found.add(branch);
      branch.visitChildren(walk);
    }

    walk(root);
    return found;
  }
}

/// Drains the microtask queue (the availability registry delivers deferred),
/// so the next flush observes the pinged rebuilds.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

Future<void> _settle(TreeOwner owner) async {
  owner.flush();
  await _pump();
  owner.flush();
  await _pump();
  owner.flush();
}

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

/// A dependent of the ambient [ServiceBundle] that counts its own builds —
/// the WorkList stand-in for the no-op-rebuild damping test. Reused as ONE
/// instance across descriptions so the identical-skip fast path isolates
/// dependency notification as the only rebuild trigger.
class _BundleDependent extends StatelessSeed {
  const _BundleDependent({required this.onBuild});

  final void Function() onBuild;

  @override
  Seed build(TreeContext context) {
    context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    onBuild();
    return const _Leaf();
  }
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

final class _FakeTokens implements github.GitHubAppTokenProvider {
  @override
  Future<String> accessToken() async => 'token';
}

final class _FakeGitHubAppCredentials {
  static const keyPath = '/fake/app.pem';

  static Map<String, String> environment() => const {
    'ORG_APP_KEY': keyPath,
    'PERSONAL_APP_KEY': keyPath,
  };

  static Future<github.GitHubKeyFileStat> stat(String path) async =>
      const github.GitHubKeyFileStat(
        type: FileSystemEntityType.file,
        mode: 0x180,
      );

  static Future<String> read(String path) async => 'fake-private-key';

  static github.GitHubAppCredentialLoader loader() =>
      github.GitHubAppCredentialLoader(
        environment: environment,
        stat: stat,
        read: read,
      );

  static github.GitHubHttpTransport transport() => _FakeTransport();
}

final class _FakeTransport implements github.GitHubHttpTransport {
  int calls = 0;

  @override
  Future<github.GitHubHttpResponse> send(
    github.GitHubHttpRequest request,
  ) async {
    calls += 1;
    return const github.GitHubHttpResponse(statusCode: 500, body: 'unused');
  }
}

github.GitHubAppClient _fakeClient(_FakeTransport transport) =>
    github.GitHubAppClient(
      config: github.GitHubAppConfig(appId: '1234', installationId: 99),
      tokens: _FakeTokens(),
      transport: transport,
    );

/// The APPROVED metadata a mount-eligible bead carries: the plan the
/// committee's gating lane runs, plus the three-key RECEIPT the `approve` verb
/// writes (`grid_assets 0.6.0-rc.6` — the label alone is no longer approval).
const Map<String, String> _approvedMetadata = {
  'validation_plan': 'dart analyze && dart test',
  kApprovedByKey: 'governor',
  kApprovedAtKey: '2026-09-02T14:30:00.000Z',
  kApprovedRevKey: '9f1c2d3e4b5a69788899aabbccddeeff00112233',
};

/// A work bead shaped for the mount gate: driveable type + `validation_plan` +
/// the `grid.approved` label + the approve verb's stamp. Each argument is
/// overridden individually so a test can knock out exactly one leg of the four.
Bead _bead({
  IssueType type = IssueType.task,
  List<String> labels = const [kApprovedLabel],
  Map<String, String> metadata = _approvedMetadata,
}) => Bead(
  id: 'mine-1',
  title: 'a work bead',
  issueType: type,
  status: BeadStatus.open,
  labels: labels,
  metadata: metadata,
);

/// The EFFECTIVE seat bundle — the one `SubstationWork` resolves. Each seat now
/// mounts two: `GitGridAssets`' fresh bundle and, innermost, the bundle
/// `MountEligibilityAssets` derives from it. Only the latter carries the mount
/// predicate, so it is the one every assertion about seat posture means.
ServiceBundle _gated(_Walk walk) =>
    walk.values<ServiceBundle>().singleWhere((b) => b.mountEligibility != null);
