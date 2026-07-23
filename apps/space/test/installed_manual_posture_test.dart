// The INSTALLED operator manual must agree with space's OWN operating posture.
//
// This is the guard `space-izv` round 1 lacked. Its install mechanism was
// right, but the content it materialized was STALE (`grid_assets@429556d`): it
// taught the operator to arm a resident station from a COMPILED `./space`
// binary and to pass a `--land` flag this runner no longer names. Installing it
// REVERTED this repo's own corrected guidance — a regression the committee
// caught by READING, because no test could. Fixed at the source in
// power_station `pow-ej7` (`a09cfb6`); this test is what keeps it fixed.
//
// space is JIT-only (`CLAUDE.md`: the resident station and every `space`
// command run under `dart run`, NEVER a `dart compile exe` binary — JIT keeps
// the VM service open for hot-reload and guarantees current source), and the
// station-level land arming seam is RETIRED (the_grid ADR-0000 A51 — delivery
// is a per-substation `DeliveryMethod` binding, not a station-wide boolean).
// `land_seam_retired_test.dart` fences those tokens out of `lib/`; this fences
// them out of the INSTALLED MANUAL. Whatever `grid_assets` vends, what lands in
// this repo's `.claude/` may not teach an operator to do what this repo cannot.
//
// A hit here is NOT a licence to hand-edit the installed file — that is exactly
// the out-of-band drift the provenance stamp exists to catch, and
// `assets install --check` would then fail on it. Fix it at the AUTHORED home
// (power_station's `grid_assets` `station_overlay`) and re-run
// `dart run space:space assets install`.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('the installed operator manual teaches the JIT-only posture and names '
      'no retired land flag', () {
    // The installed manual lives at the REPO root (the grid home), ../../ from
    // this app package (tests run with cwd = apps/space).
    final claude = Directory(
      p.normalize(p.join(Directory.current.path, '..', '..', '.claude')),
    );
    expect(claude.existsSync(), isTrue, reason: 'sanity: .claude/ was found');

    final assets = claude
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .toList();
    expect(
      assets,
      isNotEmpty,
      reason: 'sanity: the installed assets were found',
    );

    // LITERAL tokens, matched with `String.contains` — never a regex. Each
    // marks a regression that DIFFERS between the stale content and the fix: it
    // is PRESENT in what gated round 1 and ABSENT from the corrected vendor, so
    // the fence bites the regression and passes on the corrected tree.
    //
    // Two near-miss tokens are deliberately NOT fenced, because each survives in
    // the CORRECTED content and would false-positive on the fix:
    //   * bare `AOT` — the corrected manual legitimately says "never an AOT
    //     binary"; the narrower `run the AOT binary` (the removed lure) is used.
    //   * bare `space` — the rendered manual legitimately contains it
    //     everywhere: the `{{runner}}` holes render to `dart run space:space`,
    //     and repo/store names (`space_station`, `space-` bead ids) carry it
    //     too, so bare `space` is not a regression marker.
    // `./space` IS fenced (below): power_station #39 dropped the `./` binary
    // prefix from the vended `{{runner}}` invocations and space binds
    // `{{runner}}` to `dart run space:space`, so the compiled-binary
    // `./space` invocation renders NOWHERE in the corrected tree.
    const retired = <String, String>{
      'compile exe':
          'the AOT build step — there is deliberately no committed `space` '
          'binary',
      'run the AOT binary':
          'the AOT lure — a resident station runs JIT from source',
      '--land':
          'the retired land arming flag — delivery is a per-substation '
          'binding (the_grid ADR-0000 A51)',
      './space':
          'the compiled-binary invocation — space runs JIT via '
          '`dart run space:space`, never a `./space` binary; the overlay '
          'dropped the `./` prefix (power_station #39) and space binds '
          '{{runner}} to the JIT invocation',
    };

    final hits = <String>[
      for (final file in assets)
        for (final entry in retired.entries)
          if (file.readAsStringSync().contains(entry.key))
            '${file.path}: "${entry.key}" — ${entry.value}',
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'the installed operator manual contradicts space\'s own posture. Do '
          'NOT hand-edit the installed file (that is drift `assets install '
          '--check` will fail on) — fix it at the authored home, '
          'power_station\'s grid_assets station_overlay, then re-run '
          '`dart run space:space assets install`:\n  ${hits.join('\n  ')}',
    );
  });
}
