/// The trajectory RUNNER surface — Stage-1 chunk WS and Stage-2 chunk G2-S of
/// `the_grid/docs/design/trajectory/stage1-wiring.md` and
/// `the_grid/docs/design/trajectory/stage2-wiring.md`.
///
/// §1.1 splits Stage 1 across two repos: the harness, the recorder, and the
/// hooks land in the_grid; the `--trajectory`/`--no-trajectory` flag, the boot
/// banner lines, and the `/status` block land HERE. This library is that whole
/// surface, and it is deliberately nothing but PURE FUNCTIONS OVER VALUES plus
/// one serializer — provable with a scripted [TrajectoryHarnessStatus], no
/// dolt server, no epoch claim, no station.
///
/// It lives beside `up_command.dart` rather than inside it because two
/// commands consume it: `up` renders the boot banner and serves the `/status`
/// block, and `status` RENDERS that block back to the operator (§3's "loud on
/// every status read", which `TrajectoryHarness` explicitly delegates to this
/// side — see its `_latchHalted` comment).
library;

import 'package:args/args.dart' show ArgResults;
// ignore: implementation_imports
import 'package:grid_cli/src/station_control.dart'
    show GovernorFlareStatus, StationStatus;
import 'package:grid_engine/grid_engine.dart' show DualReadMode;
import 'package:grid_sdk/grid_sdk.dart'
    show
        G2Posture,
        TrajectoryConfig,
        TrajectoryConfigMode,
        TrajectoryDiscipline,
        TrajectoryHarnessMode,
        TrajectoryHarnessStatus;

/// A resolved trajectory configuration together with invalid runner input.
///
/// Each nullable value is the exact set value that could not be resolved, or
/// null when its input was unset or recognized. Invalid input resolves
/// [config] to a safe carrier; the runner decides whether that value refuses.
typedef TrajectoryConfigResolution = ({
  TrajectoryConfig config,
  String? unrecognizedDualReadValue,
  String? unrecognizedDisciplineValue,
  String? unrecognizedG2PostureValue,
  String? unrecognizedSoakWindowEpochValue,
});

/// A Stage-2 posture input outside the exact `off|shadow|cut` vocabulary.
///
/// The resolver carries [configuredValue] beside an inert `off` config so the
/// runner can refuse by name before assembly. The fallback is never authority
/// to continue booting.
final class G2PostureConfigRefused implements Exception {
  /// Creates the named refusal with the exact unrecognized input.
  const G2PostureConfigRefused(this.configuredValue)
    : expected = 'off|shadow|cut';

  /// The exact flag or environment value the operator supplied.
  final String configuredValue;

  /// The complete accepted wire vocabulary.
  final String expected;

  @override
  String toString() =>
      'G2PostureConfigRefused(configuredValue: $configuredValue, '
      'expected: $expected)';
}

/// Maps `up`'s tri-state `--trajectory` flag onto the assembly's
/// [TrajectoryConfig] and preserves invalid dual-read input (stage1-wiring
/// §1.3).
///
/// `--dual-read` is not, and is not becoming, an `up` flag: the dual-read
/// posture is the ENVIRONMENT's (`GRID_DUAL_READ`), its discipline
/// `GRID_TRAJECTORY_DISCIPLINE` and its soak window `GRID_SOAK_WINDOW_EPOCH`.
/// A supervised boot inherits them because `up --daemon` captures every
/// `GRID_*` key into the LaunchAgent (`supervisedEnvironment`), not because
/// any of them is a flag.
///
/// The flag is declared `defaultsTo: null` precisely so ABSENT is a third
/// state: absent ⇒ [TrajectoryConfigMode.auto] (arm iff the home carries the
/// provisioning artifact), `--trajectory` ⇒ [TrajectoryConfigMode.required]
/// (degrade LOUD, never block the boot), `--no-trajectory` ⇒
/// [TrajectoryConfigMode.disabled] (no connection, no claim, a silent
/// counting no-op).
///
/// The dry-run force is NOT applied here — `assembleStationWork` applies
/// `TrajectoryConfig.asDisabled` when `dryRun` is set, which is the one place
/// the rule lives.
/// [environment] is INJECTED, never read ambiently: `no_watcher_no_gate_test`
/// bans every ambient process-environment read under `lib/`, so nothing in the
/// assembly can grow a hidden out-of-band gate. The environment enters at the
/// composition root — `bin/space.dart` hands it to [buildRunner] — and an
/// unfed runner simply arms the default posture.
TrajectoryConfigResolution trajectoryConfigResolutionFrom(
  ArgResults args, {
  Map<String, String> environment = const <String, String>{},
}) {
  // The dual-read posture is the RUNNER's to feed (TrajectoryConfig.dualRead
  // docs): `GRID_DUAL_READ=<off|observe|primary>`. An absent value remains an
  // OMITTED constructor request so the SDK's cut implication cannot mistake
  // the default posture for an explicit `off` disagreement. An unrecognized
  // value is an explicit `off` fallback and stays available for diagnostics.
  final rawDualRead = environment['GRID_DUAL_READ'];
  final (dualRead, unrecognizedDualReadValue) = switch (rawDualRead) {
    null => (null, null),
    'off' => (DualReadMode.off, null),
    'observe' => (DualReadMode.observe, null),
    'primary' => (DualReadMode.primary, null),
    final value => (DualReadMode.off, value),
  };

  final rawDiscipline = environment['GRID_TRAJECTORY_DISCIPLINE'];
  final (discipline, unrecognizedDisciplineValue) = switch (rawDiscipline) {
    null || 'shadow' => (TrajectoryDiscipline.shadow, null),
    'cut' => (TrajectoryDiscipline.cut, null),
    final value => (TrajectoryDiscipline.shadow, value),
  };

  final rawSoakWindowEpoch = environment['GRID_SOAK_WINDOW_EPOCH'];
  final parsedSoakWindowEpoch = rawSoakWindowEpoch == null
      ? null
      : int.tryParse(rawSoakWindowEpoch);
  final (soakWindowEpoch, unrecognizedSoakWindowEpochValue) = switch ((
    rawSoakWindowEpoch,
    parsedSoakWindowEpoch,
  )) {
    (null, _) => (0, null),
    (_, final parsed?) when parsed >= 0 => (parsed, null),
    (final value, _) => (0, value),
  };

  // G2 stays inert unless one of its three exact posture values is supplied.
  // A bad value is retained for the runner's named pre-assembly refusal; the
  // accompanying `off` value is only a safe carrier and never authorizes boot.
  final rawG2Posture = args.wasParsed('g2-posture')
      ? args.option('g2-posture')
      : environment['GRID_G2_POSTURE'];
  final (g2Posture, unrecognizedG2PostureValue) = switch (rawG2Posture) {
    null || 'off' => (G2Posture.off, null),
    'shadow' => (G2Posture.shadow, null),
    'cut' => (G2Posture.cut, null),
    final value => (G2Posture.off, value),
  };

  // This is a recorded receipt, not a boot-time certification calculation.
  // wasParsed preserves the flag's explicit false rung from absence.
  final bool? g1CertificatePassed = args.wasParsed('g1-certificate-passed')
      ? args.flag('g1-certificate-passed')
      : switch (environment['GRID_G1_CERTIFICATE_PASSED']) {
          'true' => true,
          'false' => false,
          _ => null,
        };

  final trajectoryMode = !args.wasParsed('trajectory')
      ? null
      : args.flag('trajectory')
      ? TrajectoryConfigMode.required
      : TrajectoryConfigMode.disabled;
  final config = TrajectoryConfig(
    discipline: discipline,
    mode: trajectoryMode,
    dualRead: dualRead,
    g2Posture: g2Posture,
    g1CertificatePassed: g1CertificatePassed,
    soakWindowEpoch: soakWindowEpoch,
  );
  return (
    config: config,
    unrecognizedDualReadValue: unrecognizedDualReadValue,
    unrecognizedDisciplineValue: unrecognizedDisciplineValue,
    unrecognizedG2PostureValue: unrecognizedG2PostureValue,
    unrecognizedSoakWindowEpochValue: unrecognizedSoakWindowEpochValue,
  );
}

/// Maps `up`'s trajectory inputs onto their non-fatal resolved configuration.
///
/// Invalid environment input retains each key's safe fallback. Call
/// [trajectoryConfigResolutionFrom] when the caller also needs to report an
/// invalid value.
TrajectoryConfig trajectoryConfigFrom(
  ArgResults args, {
  Map<String, String> environment = const <String, String>{},
}) => trajectoryConfigResolutionFrom(args, environment: environment).config;

/// Renders positive boot evidence for the complete resolved trajectory posture.
String dualReadBootLogLine({
  required String runnerName,
  required TrajectoryConfig config,
}) =>
    '$runnerName up: dual-read posture resolved to ${config.dualRead.name}. '
    'Trajectory discipline resolved to ${config.discipline.name}; soak window '
    'epoch resolved to ${config.soakWindowEpoch}.';

/// The operator-facing WORD for a harness posture — DERIVED from the mode's
/// own name so no surface can invent a second vocabulary.
///
/// `trajectoryStatusJson` puts `mode.name` on the wire and the banner and the
/// `status` render put this on a terminal; an operator who reads a word here
/// and greps the wire, `TrajectoryHarnessMode`, or stage1-wiring for it finds
/// the same posture. The ONE deviation is cosmetic: `fencedOut` renders
/// hyphenated, matching §3's own `trajectory: FENCED-OUT (…)` sample.
///
/// Takes the wire name (not the enum) so both producers — `up`, which holds a
/// [TrajectoryHarnessMode], and `status`, which holds a decoded JSON string —
/// go through this one function.
String trajectoryPostureWord(String modeName) =>
    modeName == TrajectoryHarnessMode.fencedOut.name
    ? 'FENCED-OUT'
    : modeName.toUpperCase();

/// The boot banner's trajectory line, rendered from a STARTED harness's
/// [TrajectoryHarnessStatus] (stage1-wiring §3's operator-surface column).
///
/// Every non-live posture says the same two things in the same order: what
/// the posture is (with its cause as a PARENTHETICAL — the word itself is
/// always [trajectoryPostureWord]'s, never a second vocabulary), and that the
/// station is running legacy-only with the shadow window not counting —
/// because that, not the mode name, is the thing an operator must not misread.
///
/// [requested] is the mode the OPERATOR asked for ([trajectoryConfigFrom]'s
/// output), which the harness status alone cannot carry: a `disabled` posture
/// is either the operator's own `--no-trajectory` or the assembly's dry-run
/// force, and those are different facts. Naming the flag when the operator
/// passed it keeps the banner from reporting the dry run as the cause of a
/// choice the operator made explicitly; only the IMPLICIT force (`auto` or
/// `required` under [dryRun]) gets the dry-arm wording, so
/// `--trajectory --dry-run` still never looks like a refused flag.
String trajectoryBannerLine(
  TrajectoryHarnessStatus status, {
  bool dryRun = false,
  TrajectoryConfigMode requested = TrajectoryConfigMode.auto,
}) {
  final word = trajectoryPostureWord(status.mode.name);
  final cause = status.cause == null ? '' : ' (${status.cause})';
  const legacyOnly = ' — running legacy-only; shadow window not counting';
  const dryArm = 'a dry run claims no epoch and writes nothing';
  switch (status.mode) {
    case TrajectoryHarnessMode.live:
      return 'trajectory: $word  ·  epoch ${status.epoch}  ·  '
          'appended ${status.appended}  ·  deduped ${status.deduped}  ·  '
          'dropped ${status.dropped}  ·  '
          'suppressed ${status.suppressed}  ·  queue ${status.queueDepth}';
    case TrajectoryHarnessMode.disabled:
      // The operator's own flag outranks the dry-run force as the CAUSE: both
      // are true on `--no-trajectory --dry-run` (the default), and reporting
      // only the dry run there hides the choice that was actually made.
      if (requested == TrajectoryConfigMode.disabled) {
        return 'trajectory: $word (--no-trajectory'
            '${dryRun ? '; also a dry arm — $dryArm' : ''})$legacyOnly';
      }
      return dryRun
          ? 'trajectory: $word (dry arm — $dryArm)$legacyOnly'
          : 'trajectory: $word$cause$legacyOnly';
    case TrajectoryHarnessMode.unprovisioned:
    case TrajectoryHarnessMode.down:
      return 'trajectory: $word$cause$legacyOnly';
    case TrajectoryHarnessMode.degraded:
      return 'trajectory: $word$cause  ·  dropped ${status.dropped}'
          '  ·  suppressed ${status.suppressed}'
          '$legacyOnly';
    case TrajectoryHarnessMode.fencedOut:
      return 'trajectory: $word$cause  ·  epoch ${status.epoch}$legacyOnly';
    case TrajectoryHarnessMode.halted:
      return 'trajectory: $word — ${status.cause ?? 'reason unrecorded'}; the '
          'log is presumed damaged until a human looks$legacyOnly';
  }
}

/// `required` mode's warning, or null when none is due (stage1-wiring §1.3).
///
/// §1.3 defines the three modes by their operator LOUDNESS, not only by their
/// arming rule: `auto` on an unprovisioned home is deliberately quiet ("a
/// one-line notice, **not a warning storm**"), while `required` is — verbatim
/// — "a failed connect/claim still NEVER blocks the boot …, but the
/// degradation is a **loud, repeated warning** and `/status` shows
/// `trajectory: DEGRADED`".
///
/// Two surfaces discharge that clause together, and honesty about which is
/// which matters: this string is the LOUD half, emitted to stderr at boot;
/// the REPEATED half is [trajectoryStatusLine], which renders every non-armed
/// posture loud on EVERY status read — the same delegation `TrajectoryHarness`
/// makes when it flares once and leaves repetition to the status surface. `up`
/// has no periodic operator log to hang a timer on, and inventing one to
/// re-print a line into a parked foreground process would be the warning storm
/// §1.3 rules out for the quiet mode.
///
/// A `disabled` posture under `required` is NOT a degradation: the only thing
/// that produces it is the assembly's dry-run force, which is the operator's
/// own instruction (§1.3's "Dry-run forces `disabled`"), and the banner
/// already names it.
String? trajectoryRequiredWarning(
  TrajectoryHarnessStatus status, {
  required TrajectoryConfigMode requested,
}) {
  if (requested != TrajectoryConfigMode.required) return null;
  if (status.mode == TrajectoryHarnessMode.live) return null;
  if (status.mode == TrajectoryHarnessMode.disabled) return null;
  return 'WARNING: --trajectory was REQUIRED and the shadow window is NOT '
      'counting — trajectory: ${trajectoryPostureWord(status.mode.name)}'
      '${status.cause == null ? '' : ' (${status.cause})'}. The station runs '
      'legacy-only; every append is a silent counting no-op, so no round from '
      'this arm can be scored. `space status` repeats this on every read.';
}

/// The `/status` trajectory block (stage1-wiring §3): the posture, its cause,
/// the claimed epoch, the queue depth, and the divergence counters the cut
/// criterion is read off — a round with any dropped or suppressed append cannot
/// count as a clean round, so `dropped` and `suppressed` are first-class
/// fields, not log lines.
///
/// [armed] is the derived one-bit read a watcher polls; [mode] keeps the
/// harness's own vocabulary so the wire never invents a second one.
/// [g2ThreeCleanRoundsPassed] and [g2ZeroResiduePassed] remain null until their
/// runtime receipt producers land; null is serialized as an explicit absence.
Map<String, Object?> trajectoryStatusJson(
  TrajectoryHarnessStatus status, {
  required TrajectoryConfig config,
  bool? g2ThreeCleanRoundsPassed,
  bool? g2ZeroResiduePassed,
}) => <String, Object?>{
  'mode': status.mode.name,
  'armed': status.mode == TrajectoryHarnessMode.live,
  'discipline': config.discipline.name,
  'soakWindowEpoch': config.soakWindowEpoch,
  'g2Posture': config.g2Posture.name,
  'g1CertificatePassed': config.g1CertificatePassed,
  'g2ThreeCleanRoundsPassed': g2ThreeCleanRoundsPassed,
  'g2ZeroResiduePassed': g2ZeroResiduePassed,
  'cause': status.cause,
  'epoch': status.epoch,
  'queueDepth': status.queueDepth,
  'appended': status.appended,
  'deduped': status.deduped,
  'dropped': status.dropped,
  'suppressed': status.suppressed,
  'exitJoinGaps': status.exitJoinGaps,
};

/// Renders Stage 2's posture and cut receipts from the trajectory wire block.
///
/// Null means a missing receipt. A false G1 or three-clean-round receipt is
/// `uncertified`; a false residue receipt is `not-zero`. An older or malformed
/// block renders nothing instead of inventing a cut result.
String? g2CutStatusLine(Map<String, Object?> payload) {
  final block = payload['trajectory'];
  if (block is! Map<String, Object?>) return null;

  final posture = block['g2Posture'];
  if (posture is! String ||
      !G2Posture.values.any((value) => value.name == posture)) {
    return null;
  }

  String? certificateState(Object? value) => switch (value) {
    null => 'missing',
    false => 'uncertified',
    true => 'certified',
    _ => null,
  };
  String? residueState(Object? value) => switch (value) {
    null => 'missing',
    false => 'not-zero',
    true => 'zero',
    _ => null,
  };

  final g1 = certificateState(block['g1CertificatePassed']);
  final threeClean = certificateState(block['g2ThreeCleanRoundsPassed']);
  final zeroResidue = residueState(block['g2ZeroResiduePassed']);
  if (g1 == null || threeClean == null || zeroResidue == null) return null;

  return 'g2: posture=$posture · g1-certificate=$g1 · '
      'three-clean-rounds=$threeClean · zero-residue=$zeroResidue';
}

/// One rendered trajectory line for `status`, plus whether it is LOUD.
typedef TrajectoryLine = ({String line, bool loud});

/// Renders the `/status` payload's `trajectory` block for `space status` —
/// the surface stage1-wiring §3 makes load-bearing: the halt row's operator
/// column is `trajectory: HALTED — the reason`, **loud on every status read**.
///
/// This is the ONLY repeatable operator read of the posture. The boot banner
/// fires once; every posture that can arise AFTER boot — `fencedOut` (a
/// successor claimed the epoch), `halted` (belt corruption), `degraded` (a
/// dead socket, dropped appends) — is latched later, and the harness flares
/// each ONCE on the explicit assumption that the status surface carries the
/// repetition.
///
/// Returns null when the payload carries no `trajectory` block — an older
/// producer, or a station booted before chunk WS. Absence renders NOTHING
/// rather than a phantom posture, and never throws.
///
/// LOUD (an unmissable `!!` prefix, which the caller renders un-indented so
/// the row breaks the status block's alignment) whenever the posture is one an
/// operator must act on:
///  * not armed, in a mode that is not a deliberate quiet one — `disabled` is
///    a choice and `unprovisioned` is §1.3's "one-line notice, not a warning
///    storm", so those two stay quiet; every other non-armed posture is a
///    degradation;
///  * `dropped > 0` — §3: a round with ANY dropped append cannot count as a
///    clean round, even from an otherwise LIVE harness;
///  * `suppressed > 0` — a fenced-out, halted, or degraded latch refused an
///    append, which likewise disqualifies the round;
///  * `exitJoinGaps > 0` — a derivation that never joined its exit, the same
///    disqualification.
TrajectoryLine? trajectoryStatusLine(Map<String, Object?> payload) {
  final block = payload['trajectory'];
  if (block is! Map<String, Object?>) return null;
  int count(String key) => (block[key] as num?)?.toInt() ?? 0;

  final mode = block['mode'] as String? ?? 'unknown';
  final armed = block['armed'] as bool? ?? false;
  final cause = block['cause'] as String?;
  final epoch = block['epoch'];
  final dropped = count('dropped');
  final suppressed = count('suppressed');
  final gaps = count('exitJoinGaps');
  // `disabled` and `unprovisioned` are the two postures §1.3 designs to be
  // quiet — a flag the operator passed, and an unprovisioned home.
  final quietPosture =
      mode == TrajectoryHarnessMode.disabled.name ||
      mode == TrajectoryHarnessMode.unprovisioned.name;
  final loud =
      (!armed && !quietPosture) || dropped > 0 || suppressed > 0 || gaps > 0;

  final counters =
      '  ·  epoch ${epoch ?? '—'}  ·  queue ${count('queueDepth')}  ·  '
      'appended ${count('appended')}  ·  dropped $dropped  ·  '
      'suppressed $suppressed';

  if (!loud) {
    final armedNote = armed
        ? 'armed'
        : 'not armed${cause == null ? '' : ' — $cause'}';
    return (
      line: 'trajectory: ${trajectoryPostureWord(mode)} ($armedNote)$counters',
      loud: false,
    );
  }

  final reasons = <String>[
    if (!armed && !quietPosture)
      '${cause ?? 'reason unrecorded'}; the station runs legacy-only and the '
          'shadow window is NOT counting',
    if (dropped > 0)
      '$dropped dropped append(s) — a round with any dropped append cannot '
          'count as a clean round',
    if (suppressed > 0)
      '$suppressed suppressed append(s) — a round with any suppressed append '
          'cannot count as a clean round',
    if (gaps > 0) '$gaps exit-join gap(s)',
  ];
  return (
    line:
        '!! trajectory: ${trajectoryPostureWord(mode)} — '
        '${reasons.join('; ')}$counters',
    loud: true,
  );
}

/// space's `/status` snapshot: grid_cli's [StationStatus] plus space's resolved
/// roster projection.
///
/// The base owns the top-level `trajectory` wire map and its serialization;
/// this subclass converts the typed constructor input through
/// [trajectoryStatusJson]. The only wire augmentation owned here is the roster
/// nested under `station`.
///
/// **Maintenance contract:** the forwarding constructor below enumerates the
/// base's parameters by hand, so a field ADDED to [StationStatus] upstream is
/// unreachable from space's view until it is added here too — silently, with
/// no compile error. Every base parameter that exists today is forwarded;
/// forward the next one the same way. (The subclass, not composition, is the
/// cheap shape only as long as that list stays short — if [StationStatus]
/// grows a wide constructor, compose a `toJson()` wrapper instead.)
class SpaceStationStatus extends StationStatus {
  /// Creates the snapshot; every base field is forwarded unchanged.
  SpaceStationStatus({
    required TrajectoryHarnessStatus trajectory,
    required TrajectoryConfig trajectoryConfig,
    bool? g2ThreeCleanRoundsPassed,
    bool? g2ZeroResiduePassed,
    this.roster = const [],
    required super.substation,
    required super.stateStore,
    required super.workRoot,
    required super.dryRun,
    required super.pid,
    required super.startedAt,
    required super.version,
    required super.ready,
    required super.mounted,
    required super.liveSessions,
    required super.lastSyncAt,
    super.mintFailedScopes,
    super.perSubstation,
    super.wedge,
    super.sync,
    super.admission,
  }) : super(
         trajectory: trajectoryStatusJson(
           trajectory,
           config: trajectoryConfig,
           g2ThreeCleanRoundsPassed: g2ThreeCleanRoundsPassed,
           g2ZeroResiduePassed: g2ZeroResiduePassed,
         ),
       );

  /// The ordered substation roster resolved and armed by this live station.
  final List<({String name, String root, String prefix})> roster;

  /// Serializes the base wire shape and augments `station` with the roster.
  ///
  /// [governorFlares] is the base's own parameter, forwarded UNREAD: the
  /// delivery snapshot belongs to the `/status` producer that owns the
  /// governor feed, and this subclass augments the `station` map alone (grid_cli
  /// 0.6.0-dev.3).
  @override
  Map<String, Object?> toJson({
    GovernorFlareStatus governorFlares = const GovernorFlareStatus(),
  }) {
    final json = super.toJson(governorFlares: governorFlares);
    return <String, Object?>{
      ...json,
      'station': <String, Object?>{
        ...json['station']! as Map<String, Object?>,
        'roster': <Map<String, Object?>>[
          for (final entry in roster)
            <String, Object?>{
              'name': entry.name,
              'root': entry.root,
              'prefix': entry.prefix,
            },
        ],
      },
    };
  }
}
