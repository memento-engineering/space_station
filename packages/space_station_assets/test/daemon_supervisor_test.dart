import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:space_station_assets/space_station_assets.dart';
// ignore: implementation_imports
import 'package:space_station_assets/src/down_command.dart' show DownCommand;
// ignore: implementation_imports
import 'package:space_station_assets/src/status_command.dart'
    show StatusCommand;
// ignore: implementation_imports
import 'package:space_station_assets/src/up_command.dart' show UpCommand;
import 'package:test/test.dart';

/// `up --daemon` / `down --daemon` / the `status` supervised line (space-5lh).
///
/// The resident today is a CHILD of whichever shell booted it: it dies with
/// that session, and a reboot leaves a station lock naming a dead pid. These
/// verbs hand the resident to launchd instead. Every `launchctl` call rides a
/// FAKE — the operator's real GUI domain is never touched by a test run — and
/// the plist lands in a temp directory, never `~/Library/LaunchAgents`.
///
/// The fixture gives the grid home ONE substation that really resolves a work
/// store (`--substation demo=<root>` over a directory carrying `.beads/`),
/// because the supervisor fork sits BELOW every arming refusal: an invocation
/// that could not boot in the foreground must never become a launchd job.
/// `RunAtLoad` + `KeepAlive{SuccessfulExit: false}` would respawn it forever
/// and resurrect it on every login.
void main() {
  late Directory home;
  late Directory substation;
  late Directory launchAgents;
  late _FakeLaunchctl launchctl;
  late _FakeStartCheck startCheck;
  late List<String> out;
  late List<String> err;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('space-5lh-home');
    substation = await Directory.systemTemp.createTemp('space-5lh-sub');
    await Directory('${substation.path}/.beads').create(recursive: true);
    launchAgents = await Directory.systemTemp.createTemp('space-5lh-agents');
    launchctl = _FakeLaunchctl();
    startCheck = _FakeStartCheck();
    out = <String>[];
    err = <String>[];
  });

  tearDown(() async {
    await home.delete(recursive: true);
    await substation.delete(recursive: true);
    await launchAgents.delete(recursive: true);
  });

  UpCommand up({Map<String, String> environment = const <String, String>{}}) =>
      UpCommand(
        environment: environment,
        launchctl: launchctl,
        startCheck: startCheck,
        launchAgentsDirectory: launchAgents.path,
        out: out.add,
        err: err.add,
      );

  CommandRunner<int> runner({
    Map<String, String> environment = const <String, String>{},
  }) => CommandRunner<int>('space', 'test')
    ..addCommand(up(environment: environment))
    ..addCommand(
      DownCommand(
        launchctl: launchctl,
        launchAgentsDirectory: launchAgents.path,
        out: out.add,
        err: err.add,
      ),
    )
    ..addCommand(
      StatusCommand(
        launchctl: launchctl,
        launchAgentsDirectory: launchAgents.path,
        out: out.add,
        err: err.add,
      ),
    );

  /// The minimum argv that ARMS: a grid home plus one substation whose root
  /// really carries a work store.
  List<String> armable() => [
    '--substation',
    'demo=${substation.path}',
    '--grid-home',
    home.path,
  ];

  String plistPath() =>
      '${launchAgents.path}/${launchAgentLabel('space')}.plist';

  List<String> programArgumentsOf(String plist) {
    final array = RegExp(
      r'<key>ProgramArguments</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist)!.group(1)!;
    return [
      for (final match in RegExp(r'<string>(.*?)</string>').allMatches(array))
        match.group(1)!,
    ];
  }

  Map<String, String> environmentVariablesOf(String plist) {
    final dict = RegExp(
      r'<key>EnvironmentVariables</key>\s*<dict>(.*?)</dict>',
      dotAll: true,
    ).firstMatch(plist);
    if (dict == null) return const <String, String>{};
    return {
      for (final match in RegExp(
        r'<key>(.*?)</key>\s*<string>(.*?)</string>',
        dotAll: true,
      ).allMatches(dict.group(1)!))
        match.group(1)!: match.group(2)!,
    };
  }

  String? valueOf(String plist, String key) => RegExp(
    '<key>$key</key>\\s*<string>(.*?)</string>',
  ).firstMatch(plist)?.group(1);

  // AC-1.
  test('up --daemon writes the plist, keeps the invocation minus --daemon, '
      'roots it at the grid home, and bootstraps exactly once', () async {
    final invocation = <String>[
      '--daemon',
      '--no-dry-run',
      '--max-agents',
      '6',
      ...armable(),
    ];
    expect(
      await runner().run(['up', ...invocation]),
      0,
      reason: err.join('\n'),
    );

    final plist = await File(plistPath()).readAsString();
    final programArguments = programArgumentsOf(plist);

    // The operator's invocation, MINUS --daemon and nothing else.
    expect(programArguments.sublist(programArguments.indexOf('up')), [
      'up',
      ...invocation.where((argument) => argument != '--daemon'),
    ]);
    // launchd execs a PATH, never a name looked up on $PATH.
    expect(programArguments.first, Platform.resolvedExecutable);
    expect(programArguments, containsAllInOrder(const ['run', 'space:space']));

    expect(valueOf(plist, 'WorkingDirectory'), home.path);
    expect(valueOf(plist, 'Label'), 'grid.station.space');
    expect(
      valueOf(plist, 'StandardOutPath'),
      '${home.path}/.grid/logs/space.out.log',
    );
    expect(
      valueOf(plist, 'StandardErrorPath'),
      '${home.path}/.grid/logs/space.err.log',
    );
    // KeepAlive on CRASH only: a graceful `down` must not bounce.
    expect(plist, contains('<key>SuccessfulExit</key>\n\t\t<false/>'));

    expect(launchctl.bootstrapped, [plistPath()]);
    expect(launchctl.bootedOut, isEmpty);
    expect(
      out.join('\n'),
      contains(
        'supervised by launchd as '
        'grid.station.space',
      ),
    );
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  // AC-2.
  test('a second up --daemon on a loaded label refuses naming it and starts '
      'nothing', () async {
    expect(
      await runner().run(['up', '--daemon', ...armable()]),
      0,
      reason: err.join('\n'),
    );
    expect(launchctl.bootstrapped, hasLength(1));
    err.clear();

    expect(await runner().run(['up', '--daemon', ...armable()]), 64);
    expect(err.join('\n'), contains('grid.station.space'));
    expect(err.join('\n'), contains('refusing to start a second resident'));
    // Nothing was started, and the installed recipe is untouched.
    expect(launchctl.bootstrapped, hasLength(1));
    expect(File(plistPath()).existsSync(), isTrue);
    // The loaded label short-circuits BEFORE the start check: the second
    // `up --daemon` probed nothing, so `starts nothing` is literal.
    expect(startCheck.probes, hasLength(1));
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  // AC-5 — the refusal ordering the supervisor fork depends on. A launchd job
  // that exits non-zero is RESPAWNED (throttled) forever and comes back on
  // every login, so an invocation that could not boot in the foreground must
  // install no agent at all.
  test('up --daemon over a grid home where no substation resolves a work '
      'store refuses exactly as the foreground path does, and installs '
      'nothing', () async {
    // No --substation: the coded roster resolves siblings of a temp home, and
    // none of them exist.
    final code = await runner().run([
      'up',
      '--daemon',
      '--grid-home',
      home.path,
    ]);

    expect(code, 1);
    expect(
      err.join('\n'),
      contains('no substation resolved a work store at its root'),
    );
    expect('${out.join('\n')}${err.join('\n')}', isNot(contains('launchd as')));
    expect(launchctl.bootstrapped, isEmpty);
    expect(launchctl.isLoadedCalls, isEmpty);
    expect(launchAgents.listSync(), isEmpty);
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  // AC-5 — the appended-substation store guard is a refusal too.
  test('up --daemon whose appended substation has no work store refuses '
      'before any agent is installed', () async {
    final empty = await Directory.systemTemp.createTemp('space-5lh-empty');
    addTearDown(() async => empty.delete(recursive: true));

    final code = await runner().run([
      'up',
      '--daemon',
      '--substation',
      'ghost=${empty.path}',
      '--grid-home',
      home.path,
    ]);

    expect(code, 1);
    expect(err.join('\n'), contains('has no work store'));
    expect(launchctl.bootstrapped, isEmpty);
    expect(launchAgents.listSync(), isEmpty);
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  // AC-5 — RS-2 through the supervisor. The foreground path REFUSES (exit 64)
  // when a live resident holds the store; the supervised path must refuse too
  // rather than install an agent that loses that race on every respawn.
  test('up --daemon over a store a live resident already holds refuses and '
      'installs nothing', () async {
    await File('${home.path}/.grid/station.lock').create(recursive: true);
    await File('${home.path}/.grid/station.lock').writeAsString(
      jsonEncode(<String, Object?>{
        // This very process: alive by construction, so the probe cannot
        // classify it as a stale lock.
        'pid': pid,
        'pgid': pid,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        // `acquired`, not `live`: a live record makes the probe dial the
        // advertised control url, and this test must touch no socket.
        'phase': 'acquired',
      }),
    );

    final code = await runner().run(['up', '--daemon', ...armable()]);

    expect(code, 64);
    expect(err.join('\n'), contains('station lock'));
    expect(err.join('\n'), contains('pid $pid'));
    expect(launchctl.bootstrapped, isEmpty);
    expect(launchAgents.listSync(), isEmpty);
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  // AC-3.
  test(
    'down --daemon boots out once and removes the plist',
    () async {
      expect(
        await runner().run(['up', '--daemon', ...armable()]),
        0,
        reason: err.join('\n'),
      );
      expect(File(plistPath()).existsSync(), isTrue);

      expect(await runner().run(['down', '--daemon']), 0);
      expect(launchctl.bootedOut, ['grid.station.space']);
      expect(File(plistPath()).existsSync(), isFalse);
      expect(launchctl.loaded, isEmpty);
      expect(out.join('\n'), contains('booted out grid.station.space'));

      // A second retire is a clean no-op — nothing loaded, nothing on disk, no
      // second bootout.
      expect(await runner().run(['down', '--daemon']), 0);
      expect(launchctl.bootedOut, hasLength(1));
    },
    onPlatform: const {'!mac-os': Skip('launchd is macOS only')},
  );

  // AC-3 — the two halves can disagree, and `down` must report what actually
  // happened rather than a sentence that assumes they agree.
  test('down --daemon over a recipe launchd does NOT hold removes it without '
      'a bootout', () async {
    expect(
      await runner().run(['up', '--daemon', ...armable()]),
      0,
      reason: err.join('\n'),
    );
    // The job died / was booted out by hand; the recipe outlived it.
    launchctl.loaded.clear();
    out.clear();

    expect(await runner().run(['down', '--daemon']), 0);
    // No bootout against an unheld label: it would fail, and its failure would
    // have to be swallowed to stay useful.
    expect(launchctl.bootedOut, isEmpty);
    expect(File(plistPath()).existsSync(), isFalse);
    expect(out.join('\n'), contains('was not loaded'));
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  // AC-3 — the mirror case: a plist hand-deleted under a loaded job. `down`
  // must not claim it removed a file that was already gone.
  test('down --daemon over a loaded label whose plist was hand-deleted boots '
      'out and says the recipe was already gone', () async {
    expect(
      await runner().run(['up', '--daemon', ...armable()]),
      0,
      reason: err.join('\n'),
    );
    await File(plistPath()).delete();
    out.clear();

    expect(await runner().run(['down', '--daemon']), 0);
    expect(launchctl.bootedOut, ['grid.station.space']);
    expect(out.join('\n'), contains('booted out grid.station.space'));
    expect(out.join('\n'), contains('already been deleted by hand'));
    expect(out.join('\n'), isNot(contains('and removed')));
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  // AC-4.
  test('the rendered plist parses as a property list', () async {
    final plutil = await Process.run('which', ['plutil']);
    if (plutil.exitCode != 0) {
      markTestSkipped('plutil not on PATH (non-macOS host)');
      return;
    }
    final file = File('${launchAgents.path}/lint.plist');
    await file.writeAsString(
      renderLaunchAgentPlist(
        label: 'grid.station.lunar',
        programArguments: const [
          '/opt/dart',
          'run',
          '--enable-vm-service',
          'lunar:lunar',
          'up',
          '--grid-home',
          '/tmp/a & b',
          '--trajectory',
        ],
        workingDirectory: '/tmp/a & b',
        standardOutPath: '/tmp/a & b/.grid/logs/lunar.out.log',
        standardErrorPath: '/tmp/a & b/.grid/logs/lunar.err.log',
        environmentVariables: const {
          'GRID_DUAL_READ': 'observe',
          'GRID_TRAJECTORY_DISCIPLINE': 'strict & loud',
        },
      ),
    );
    final lint = await Process.run('plutil', ['-lint', file.path]);
    expect(
      lint.exitCode,
      0,
      reason: 'plutil -lint failed:\n${lint.stdout}\n${lint.stderr}',
    );
    // The escaped value survives the round trip byte-for-byte.
    final read = await Process.run('plutil', [
      '-extract',
      'EnvironmentVariables.GRID_TRAJECTORY_DISCIPLINE',
      'raw',
      '-o',
      '-',
      file.path,
    ]);
    expect(read.exitCode, 0, reason: '${read.stderr}');
    expect('${read.stdout}'.trim(), 'strict & loud');
  });

  // AC-4 — the flag surgery itself: `--daemon` is the ONLY token removed, so
  // any `--<knob>=<value>` the verb grows rides through untouched.
  test('every token but --daemon rides through verbatim', () {
    const arguments = [
      '--daemon',
      '--grid-home',
      '/tmp/grid',
      '--trajectory',
      '--max-agents',
      '6',
      '--no-dry-run',
    ];
    expect(
      daemonProgramArguments(
        dartExecutable: '/opt/dart',
        vmArguments: const ['--enable-vm-service'],
        runnerInvocation: 'dart run lunar:lunar',
        verb: 'up',
        arguments: arguments,
      ),
      const [
        '/opt/dart',
        'run',
        '--enable-vm-service',
        'lunar:lunar',
        'up',
        '--grid-home',
        '/tmp/grid',
        '--trajectory',
        '--max-agents',
        '6',
        '--no-dry-run',
      ],
    );
  });

  // AC-4, end to end through the VERB, under RULING 2026-09-13 (1): the plist
  // captures PATH, HOME and every GRID_*/BEADS_* key present at arm time.
  //
  // `--trajectory` is a flag and lands in ProgramArguments. The dual-read
  // posture is NOT a flag — it is `GRID_DUAL_READ` — and launchd hands a job
  // none of the launching shell's environment, so it (and the App key paths
  // `gh`/`git` need, and PATH itself) rides in the plist's
  // EnvironmentVariables or it is silently lost.
  test(
    'the arm-time environment rides into the supervised boot: --trajectory '
    'in ProgramArguments, PATH/HOME/GRID_*/BEADS_* in EnvironmentVariables',
    () async {
      expect(
        await runner(
          environment: const {
            'PATH': '/opt/homebrew/bin:/usr/bin:/bin',
            'HOME': '/Users/operator',
            'GRID_DUAL_READ': 'observe',
            'GRID_TRAJECTORY_DISCIPLINE': 'required',
            'GRID_SOAK_WINDOW_EPOCH': '7',
            // An App key path: under launchd this is the ONLY way `gh` and the
            // delivery identity resolve, so it must be captured (RULING (1)).
            'GRID_GITHUB_APP_KEY_MEMENTO': '/keys/memento.pem',
            'BEADS_DB': 'tranquility',
            // Neither allowlisted key nor allowlisted prefix: a plist under
            // ~/Library/LaunchAgents is a plain file, and this must not land in
            // it.
            'AWS_SECRET_ACCESS_KEY': 'never-copy-me',
            // Set but EMPTY: omitted, never written empty — an empty
            // GRID_DUAL_READ is an unrecognized value, not an absent one.
            'GRID_SOAK_WINDOW_LABEL': '',
          },
        ).run(['up', '--daemon', '--trajectory', ...armable()]),
        0,
        reason: err.join('\n'),
      );

      final plist = await File(plistPath()).readAsString();
      expect(programArgumentsOf(plist), contains('--trajectory'));
      expect(environmentVariablesOf(plist), const {
        'BEADS_DB': 'tranquility',
        'GRID_DUAL_READ': 'observe',
        'GRID_GITHUB_APP_KEY_MEMENTO': '/keys/memento.pem',
        'GRID_SOAK_WINDOW_EPOCH': '7',
        'GRID_TRAJECTORY_DISCIPLINE': 'required',
        'HOME': '/Users/operator',
        'PATH': '/opt/homebrew/bin:/usr/bin:/bin',
      });
      expect(plist, isNot(contains('never-copy-me')));
      expect(plist, isNot(contains('AWS_SECRET_ACCESS_KEY')));
      expect(plist, isNot(contains('GRID_SOAK_WINDOW_LABEL')));
    },
    onPlatform: const {'!mac-os': Skip('launchd is macOS only')},
  );

  test('an environment with nothing to capture writes no EnvironmentVariables '
      'block at all', () async {
    expect(
      await runner().run(['up', '--daemon', ...armable()]),
      0,
      reason: err.join('\n'),
    );
    final plist = await File(plistPath()).readAsString();
    expect(plist, isNot(contains('EnvironmentVariables')));
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  // The capture rule as a pure function — the allowlist, the prefixes, and
  // the empty-value omission, without a station.
  test('supervisedEnvironment captures PATH, HOME and every GRID_*/BEADS_* '
      'key, verbatim, and nothing else', () {
    expect(
      supervisedEnvironment(const {
        'PATH': '/usr/bin',
        'HOME': '/Users/operator',
        'GRID_DUAL_READ': 'observe',
        'GRID_GITHUB_APP_KEY_NICHOLAS': '/keys/personal.pem',
        'BEADS_DB': 'tranquility',
        'BEADS_PROXY_PORT': '7001',
        'PATH_TO_NOWHERE': 'not the PATH key',
        'MY_GRID_TOKEN': 'prefix must ANCHOR, not match anywhere',
        'OPENAI_API_KEY': 'never',
        'GRID_EMPTY': '',
      }),
      const {
        'PATH': '/usr/bin',
        'HOME': '/Users/operator',
        'GRID_DUAL_READ': 'observe',
        'GRID_GITHUB_APP_KEY_NICHOLAS': '/keys/personal.pem',
        'BEADS_DB': 'tranquility',
        'BEADS_PROXY_PORT': '7001',
      },
    );
    expect(isSupervisedEnvironmentKey('GRID_'), isTrue);
    expect(isSupervisedEnvironmentKey('PATHS'), isFalse);
  });

  test('the VM self-description flags never reach launchd; the operator ones '
      'do', () {
    expect(
      supervisedVmArguments(const [
        '--enable-vm-service',
        '--resolved_executable_name=/x/dart',
        '--executable_name=/x/dart',
      ]),
      const ['--enable-vm-service'],
    );
  });

  // RULING 2026-09-13 (3) — the LAST refusal. A LaunchAgent for an invocation
  // that cannot start is worse than no agent: `RunAtLoad` plus
  // `KeepAlive{SuccessfulExit: false}` turns one failure into a job launchd
  // respawns forever and brings back on every login.
  test('up --daemon proves the runner starts from the grid home, under the '
      'environment the plist will carry, before it writes anything', () async {
    expect(
      await runner(
        environment: const {
          'PATH': '/opt/homebrew/bin:/usr/bin',
          'HOME': '/Users/operator',
          'AWS_SECRET_ACCESS_KEY': 'never-copy-me',
        },
      ).run(['up', '--daemon', ...armable()]),
      0,
      reason: err.join('\n'),
    );

    final probe = startCheck.probes.single;
    // `<dart> run <runner> --help`: the cheapest thing that exercises the
    // whole resolve-and-load path without arming a station or touching a
    // store. No VM flags — a one-shot probe must not bind the service port.
    expect(probe.command, [
      Platform.resolvedExecutable,
      'run',
      'space:space',
      '--help',
    ]);
    expect(probe.command, isNot(contains('--enable-vm-service')));
    // From WHERE launchd will run it…
    expect(probe.workingDirectory, home.path);
    // …under exactly what the plist carries, and nothing more.
    expect(probe.environment, const {
      'PATH': '/opt/homebrew/bin:/usr/bin',
      'HOME': '/Users/operator',
    });
    expect(
      probe.environment,
      environmentVariablesOf(await File(plistPath()).readAsString()),
    );
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  test('a runner that cannot start from the grid home refuses, installs '
      'nothing, and says what failed', () async {
    startCheck
      ..exitCode = 254
      ..output =
          "Error: Couldn't resolve the package 'space' in 'package:space/space.dart'.";

    final code = await runner().run(['up', '--daemon', ...armable()]);

    expect(code, 64);
    expect(err.join('\n'), contains('cannot start'));
    expect(err.join('\n'), contains('exited 254'));
    expect(err.join('\n'), contains(home.path));
    expect(err.join('\n'), contains("Couldn't resolve the package"));
    // Nothing written, nothing loaded — not even a half-installed recipe.
    expect(launchctl.bootstrapped, isEmpty);
    expect(launchAgents.listSync(), isEmpty);
    expect(File(plistPath()).existsSync(), isFalse);
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  test('a silent start-check failure still refuses, naming the exit code '
      'alone', () async {
    startCheck.exitCode = 1;

    expect(await runner().run(['up', '--daemon', ...armable()]), 64);
    expect(err.join('\n'), contains('exited 1'));
    expect(launchctl.bootstrapped, isEmpty);
    expect(launchAgents.listSync(), isEmpty);
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  test('the start-check command is the runner invocation plus --help, with '
      'the dart WORD replaced by the resolved binary', () {
    expect(
      daemonStartCheckCommand(
        dartExecutable: '/opt/dart',
        runnerInvocation: 'dart run lunar:lunar',
      ),
      const ['/opt/dart', 'run', 'lunar:lunar', '--help'],
    );
  });

  // AC-5.
  test('status reports supervised: launchd <label> when the agent is loaded, '
      'and says nothing when it is not', () async {
    // The state store `status` attaches to (Q5a: `<grid-home>/.grid/.beads`).
    // No station.lock, so the lock-derived rendering is the DOWN fallback —
    // which is exactly the case the supervised line exists for: a station
    // that is down but WILL come back.
    await File(
      '${home.path}/.grid/.beads/metadata.json',
    ).create(recursive: true);
    await File(
      '${home.path}/.grid/.beads/metadata.json',
    ).writeAsString('{"dolt_mode":"direct","dolt_database":"houston"}');

    expect(
      await runner().run(['status', '--state-workspace', home.path]),
      0,
      reason: err.join('\n'),
    );
    expect(out.join('\n'), contains('station: DOWN'));
    expect(out.join('\n'), isNot(contains('supervised:')));

    out.clear();
    launchctl.loaded.add('grid.station.space');
    expect(await runner().run(['status', '--state-workspace', home.path]), 0);
    // ONE extra line on top of the unchanged lock-derived rendering.
    expect(out.join('\n'), contains('station: DOWN'));
    expect(out.join('\n'), contains('supervised: launchd grid.station.space'));
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  // AC-5.
  test('the non-daemon up path is unchanged: --daemon is absent by default, '
      'non-negatable, and installs nothing', () async {
    expect(up().argParser.options['daemon']!.negatable, isFalse);
    expect(up().argParser.parse(const []).flag('daemon'), isFalse);

    // A plain `up` over a grid home whose coded siblings resolve no work
    // store refuses at the store guard — the pre-existing behaviour — and
    // touches no LaunchAgent.
    final code = await runner().run([
      'up',
      '--grid-home',
      home.path,
      '--for-seconds',
      '0',
    ]);
    expect(code, isNot(0));
    expect('${out.join('\n')}${err.join('\n')}', isNot(contains('launchd')));
    expect(launchctl.bootstrapped, isEmpty);
    expect(launchAgents.listSync(), isEmpty);
  });
}

/// One recorded start probe.
typedef _Probe = ({
  List<String> command,
  String workingDirectory,
  Map<String, String> environment,
});

/// A scripted [StartCheck] — a Fake, never a mock: it records what was probed
/// and answers from plain state, so a test proves the refusal without paying
/// for a real `dart run` compile.
class _FakeStartCheck implements StartCheck {
  int exitCode = 0;
  String output = '';
  final List<_Probe> probes = <_Probe>[];

  @override
  Future<StartCheckResult> probe({
    required List<String> command,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    probes.add((
      command: command,
      workingDirectory: workingDirectory,
      environment: environment,
    ));
    return (exitCode: exitCode, output: output);
  }
}

/// A recording [Launchctl] — a Fake, never a mock: it holds the real state
/// (which labels are loaded) and answers every verb from it.
class _FakeLaunchctl implements Launchctl {
  final Set<String> loaded = <String>{};
  final List<String> isLoadedCalls = <String>[];
  final List<String> bootstrapped = <String>[];
  final List<String> bootedOut = <String>[];

  @override
  Future<bool> isLoaded(String label) async {
    isLoadedCalls.add(label);
    return loaded.contains(label);
  }

  @override
  Future<LaunchctlResult> bootstrap({required String plistPath}) async {
    bootstrapped.add(plistPath);
    final plist = await File(plistPath).readAsString();
    final label = RegExp(
      r'<key>Label</key>\s*<string>(.*?)</string>',
    ).firstMatch(plist)!.group(1)!;
    loaded.add(label);
    return (exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<LaunchctlResult> bootout({required String label}) async {
    bootedOut.add(label);
    final held = loaded.remove(label);
    return held
        ? (exitCode: 0, stdout: '', stderr: '')
        : (exitCode: 3, stdout: '', stderr: 'No such process');
  }
}
