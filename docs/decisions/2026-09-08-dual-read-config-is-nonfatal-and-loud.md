---
status: accepted
date: 2026-09-08
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: dual-read-config-is-nonfatal-and-loud
  surfaces:
    - "packages/space_station_assets/lib/src/trajectory_surface.dart"
    - "packages/space_station_assets/lib/src/up_command.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-0n8
  legacy-id: null
---

# Dual-read configuration remains non-fatal and loud

## Context and Problem Statement

The wave-1 exit gate requires three clean consecutive live rounds in
dual-read observe posture, but the station has twice run silently with
dual-read off. First, the runner entrypoint did not feed its process
environment into `buildRunner`, so every configured posture resolved to off.
Later, a live boot received `GRID_DUAL_READ=1`; because `1` is unrecognized,
the resilient fallback armed off while the station otherwise appeared live
and driving. In both cases operators could discover that the soak was not
accruing only by noticing the absence of dual-read flares.

Station availability remains a constraint. An automated boot can carry stale
environment configuration, so invalid dual-read input must not prevent the
station from serving its other responsibilities.

## Considered Options

* Keep the non-fatal fallback and emit positive posture evidence plus a
  distinct invalid-configuration flare.
* Refuse boot when `GRID_DUAL_READ` is unrecognized. This was rejected because
  stale automated-launch configuration would turn a disabled soak into a dead
  station.
* Keep the current silent fallback to off. This was rejected because unset and
  invalid configuration remain indistinguishable and soak time can be lost
  without a positive signal.

## Decision Outcome

The recognized `GRID_DUAL_READ` values are exactly `off`, `observe`, and
`primary`. Unset configuration resolves to `off`. Every other set value also
resolves non-fatally to `off`, while preserving the exact offending value for
boot diagnostics.

Every boot that reaches work assembly emits a `trajectory.dualReadPosture`
flare with `{"posture": "<resolved posture>"}` and one human log line in the
form `<runner> up: dual-read posture resolved to <resolved posture>.`. When a
set value is unrecognized, boot additionally emits
`trajectory.dualReadConfigUnrecognized` with
`{"configuredValue": "<exact value>", "armedPosture": "off"}`. The invalid
value does not throw, alter the resolved fallback, or refuse the boot.

### Consequences

* Good, because station availability is preserved while operators can prove
  the soak posture from positive flare and log evidence on every applicable
  boot.
* Good, because set-but-invalid configuration is distinguishable from unset
  configuration and names the exact value that needs correction.
* Bad, because a misconfigured station still comes up with dual-read off and
  requires an operator or automation to act on the emitted diagnostic.
