/// The identity-rendered lines of `space up`'s boot banner (space-grl).
///
/// A downstream station composes this runner rather than forking it
/// (`buildRunner(name: 'lunar', runnerInvocation: 'dart run lunar:lunar')`
/// over a `SpaceDelegate` subclass), so these lines are authored from the
/// composition's OWN identity: the RUNNER word an operator types, the
/// STATION word the delegate names itself with, and the runner's JIT
/// invocation. Pure functions — the `trajectoryBannerLine` precedent — so the
/// rendering is provable without booting a station.
library;

/// The resident boot line: `<runner> up — <station> as a Seed (runGrid)`.
///
/// [runner] is the runner word (`buildRunner`'s `name`), [station] the
/// delegate's `stationName`. For space both are `space`; for a downstream
/// station both are its own.
String stationBootLine({required String runner, required String station}) =>
    '$runner up — $station as a Seed (runGrid)';

/// The dev-mode line: JIT (a VM service) arms the station's `reload` verb;
/// AOT (no VM service) reports it unavailable and names the JIT invocation
/// that arms it.
///
/// [vmServiceUri] is the armed host's URI, or null for the OFF branch.
/// [runner] names the VERB an operator types (`<runner> reload`);
/// [runnerInvocation] is the runner's full JIT invocation, rendered into the
/// arming hint through [jitArmingInvocation].
String devModeBannerLine({
  required String? vmServiceUri,
  required String runner,
  required String runnerInvocation,
}) => vmServiceUri == null
    ? 'dev mode: OFF (no VM service) — `$runner reload` is unavailable; arm '
          'it JIT: `${jitArmingInvocation(runnerInvocation)} up …`'
    : 'dev mode: JIT — VM service $vmServiceUri  ·  '
          '`$runner reload` ARMED (ext.exploration.grid.reload registered)';

/// Splices `--enable-vm-service` into [runnerInvocation]'s `dart run`.
///
/// The runner invocation is already the full JIT form
/// (`dart run space:space`), so the hint is built from it rather than
/// rebuilt from the runner name — a downstream runner whose package spec is
/// not `<name>:<name>` still renders a hint that works. An invocation that
/// does not open with `dart run ` is prefixed whole, so the hint degrades to
/// something runnable rather than to nonsense.
String jitArmingInvocation(String runnerInvocation) {
  const dartRun = 'dart run ';
  final spec = runnerInvocation.startsWith(dartRun)
      ? runnerInvocation.substring(dartRun.length)
      : runnerInvocation;
  return 'dart run --enable-vm-service $spec';
}
