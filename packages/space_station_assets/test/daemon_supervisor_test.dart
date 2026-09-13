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
void main() {
  late Directory home;
  late Directory launchAgents;
  late _FakeLaunchctl launchctl;
  late List<String> out;
  late List<String> err;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('space-5lh-home');
    launchAgents = await Directory.systemTemp.createTemp('space-5lh-agents');
    launchctl = _FakeLaunchctl();
    out = <String>[];
    err = <String>[];
  });

  tearDown(() async {
    await home.delete(recursive: true);
    await launchAgents.delete(recursive: true);
  });

  UpCommand up() => UpCommand(
    launchctl: launchctl,
    launchAgentsDirectory: launchAgents.path,
    out: out.add,
    err: err.add,
  );

  CommandRunner<int> runner() => CommandRunner<int>('space', 'test')
    ..addCommand(up())
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
      '--grid-home',
      home.path,
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
    expect(await runner().run(['up', '--daemon', '--grid-home', home.path]), 0);
    expect(launchctl.bootstrapped, hasLength(1));
    err.clear();

    expect(
      await runner().run(['up', '--daemon', '--grid-home', home.path]),
      64,
    );
    expect(err.join('\n'), contains('grid.station.space'));
    expect(err.join('\n'), contains('refusing to start a second resident'));
    // Nothing was started, and the installed recipe is untouched.
    expect(launchctl.bootstrapped, hasLength(1));
    expect(File(plistPath()).existsSync(), isTrue);
  }, onPlatform: const {'!mac-os': Skip('launchd is macOS only')});

  // AC-3.
  test(
    'down --daemon boots out once and removes the plist',
    () async {
      expect(
        await runner().run(['up', '--daemon', '--grid-home', home.path]),
        0,
      );
      expect(File(plistPath()).existsSync(), isTrue);

      expect(await runner().run(['down', '--daemon']), 0);
      expect(launchctl.bootedOut, ['grid.station.space']);
      expect(File(plistPath()).existsSync(), isFalse);
      expect(launchctl.loaded, isEmpty);

      // A second retire is a clean no-op — nothing loaded, nothing on disk, no
      // second bootout.
      expect(await runner().run(['down', '--daemon']), 0);
      expect(launchctl.bootedOut, hasLength(1));
    },
    onPlatform: const {'!mac-os': Skip('launchd is macOS only')},
  );

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
      ),
    );
    final lint = await Process.run('plutil', ['-lint', file.path]);
    expect(
      lint.exitCode,
      0,
      reason: 'plutil -lint failed:\n${lint.stdout}\n${lint.stderr}',
    );
  });

  // AC-4.
  test('--trajectory and --dual-read ride through verbatim; --daemon is the '
      'only token removed', () {
    const arguments = [
      '--daemon',
      '--grid-home',
      '/tmp/grid',
      '--trajectory',
      '--dual-read=observe',
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
        '--dual-read=observe',
        '--no-dry-run',
      ],
    );
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

/// A recording [Launchctl] — a Fake, never a mock: it holds the real state
/// (which labels are loaded) and answers every verb from it.
class _FakeLaunchctl implements Launchctl {
  final Set<String> loaded = <String>{};
  final List<String> bootstrapped = <String>[];
  final List<String> bootedOut = <String>[];

  @override
  Future<bool> isLoaded(String label) async => loaded.contains(label);

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
