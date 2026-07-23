import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// A PROCESS-LEVEL smoke over the REAL `space` CLI (`bin/space.dart`):
/// `space search` must actually RUN, over the REAL read path (the vended
/// `bd export --all` source — ONE spawn per store, read-only, A37). The
/// fixture mirrors the fabricated-umbrella case in
/// `up_down_status_smoke_test.dart`: the grid home is an umbrella member whose
/// SIBLINGS are the coded `../<repo>` roots; two of the five get real bd
/// stores, the other three are absent from this "checkout". No live station,
/// no state store, no lock — search attaches to none of them.
void main() {
  test('`space search --json <token>` runs from the CLI: a real hit in the '
      'sibling store, the absent seats named, exit 0', () async {
    final umbrella = Directory(
      (await Directory.systemTemp.createTemp(
        'space-search-umbrella-',
      )).resolveSymbolicLinksSync(),
    );
    addTearDown(() => umbrella.delete(recursive: true));
    final gridHome = Directory('${umbrella.path}/space_station')..createSync();
    final genesisRoot = Directory('${umbrella.path}/genesis')..createSync();
    await _bd(genesisRoot.path, const ['init']);
    await _bd(genesisRoot.path, const [
      'create',
      'zzflux the keyed reconcile',
      '--actor',
      'space-search-smoke',
    ]);
    final theGridRoot = Directory('${umbrella.path}/the_grid')..createSync();
    await _bd(theGridRoot.path, const ['init', '--prefix', 'tg']);

    final run = await Process.run(Platform.resolvedExecutable, [
      'bin/space.dart',
      'search',
      '--grid-home',
      gridHome.path,
      '--json',
      'zzflux',
    ], workingDirectory: Directory.current.path);

    expect(
      run.exitCode,
      0,
      reason: 'stdout: ${run.stdout}\nstderr: ${run.stderr}',
    );
    final json = jsonDecode('${run.stdout}') as Map<String, dynamic>;
    expect(json['query'], 'zzflux');
    expect(json['hitCount'], 1);
    final stores = [
      for (final s in json['stores']! as List) s as Map<String, dynamic>,
    ];
    expect(stores.map((s) => s['substation']), [
      'genesis',
      'the_grid',
      'power_station',
      'space_station',
      'lenny',
    ]);
    expect(stores.first['outcome'], 'searched');
    final hit = (stores.first['hits']! as List).single as Map<String, dynamic>;
    expect(hit['store'], 'genesis');
    expect(hit['field'], 'title');
    expect(
      [
        for (final s in stores)
          if (s['outcome'] == 'absent') s['substation'],
      ],
      ['power_station', 'space_station', 'lenny'],
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Runs `bd` in a hermetic TEMP store (embedded Dolt — no server, no
/// credentials). Only ever a throwaway store this test just created: `init`
/// seeds it, `create` puts ONE searchable bead in it. Never a foreign store.
Future<void> _bd(String dir, List<String> args) async {
  final run = await Process.run(
    'bd',
    args,
    workingDirectory: dir,
    environment: {...Platform.environment, 'BD_JSON_ENVELOPE': '1'},
    includeParentEnvironment: false,
  );
  if (run.exitCode != 0) {
    fail(
      'bd ${args.join(' ')} failed (${run.exitCode}): '
      '${run.stderr}\n${run.stdout}',
    );
  }
}
