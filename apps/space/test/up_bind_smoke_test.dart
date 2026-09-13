@Tags(['bd-e2e'])
library;

import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart' show StationLockService;
import 'package:test/test.dart';

import 'station_fixtures.dart';

void main() {
  test(
    'omitted bind preserves loopback lock and banner',
    () async {
      final fixture = await _startStation('space-bind-default-', const []);

      final controlUrl = fixture.lock['controlUrl']! as String;
      expect(Uri.parse(controlUrl).host, '127.0.0.1');
      await untilOutputContains(fixture.io, 'control: $controlUrl');
      expect('${fixture.io.out}', isNot(contains('control (LAN):')));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'lan bind advertises wildcard control URL and LAN posture',
    () async {
      final fixture = await _startStation('space-bind-lan-', const [
        '--bind',
        'lan',
      ]);

      final controlUrl = fixture.lock['controlUrl']! as String;
      expect(Uri.parse(controlUrl).host, '0.0.0.0');
      await untilOutputContains(fixture.io, 'control (LAN): $controlUrl');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'LAN-bound healthz still requires bearer',
    () async {
      final fixture = await _startStation('space-bind-auth-', const [
        '--bind',
        'lan',
      ]);

      final advertised = Uri.parse(fixture.lock['controlUrl']! as String);
      final healthz = advertised.replace(host: '127.0.0.1', path: '/healthz');

      final unauthorized = await _get(healthz);
      expect(unauthorized.statusCode, HttpStatus.unauthorized);
      expect(unauthorized.body, '{"error":"unauthorized"}');

      final authorized = await _get(
        healthz,
        token: fixture.lock['token']! as String,
      );
      expect(authorized.statusCode, HttpStatus.ok);
      expect(authorized.body, '{"ok":true}');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

typedef _StationFixture = ({
  Process process,
  CapturedIo io,
  Map<String, Object?> lock,
});

Future<_StationFixture> _startStation(
  String prefix,
  List<String> bindArguments,
) async {
  final gridHome = await bdInitGridHome('${prefix}home-');
  final subRoot = await bdInitWorkspace('${prefix}sub-');
  addTearDown(() async {
    await gridHome.delete(recursive: true);
    await subRoot.delete(recursive: true);
  });

  final process = await spawnSpace([
    'up',
    '--dry-run',
    '--substation',
    'smoketest=${subRoot.path}',
    '--grid-home',
    gridHome.path,
    '--control-port',
    '0',
    ...bindArguments,
  ]);
  final io = CapturedIo(process);
  addTearDown(() => _terminateAndWait(process));

  final lockPath = StationLockService.lockPath(gridHome.path);
  final lock = await untilLockCarries(lockPath, ['controlUrl', 'token']);
  return (process: process, io: io, lock: lock);
}

Future<void> _terminateAndWait(Process process) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(const Duration(seconds: 20));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }
}

Future<({int statusCode, String body})> _get(Uri url, {String? token}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close();
    return (
      statusCode: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}
