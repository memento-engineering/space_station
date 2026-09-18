---
status: accepted
date: 2026-09-18
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: g1-certificate-is-a-recorded-runner-receipt
  surfaces:
    - "packages/space_station_assets/lib/src/trajectory_surface.dart"
    - "packages/space_station_assets/lib/src/up_command.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-09u
  legacy-id: null
---

# The G1 certificate is a recorded runner receipt

## Context and Problem Statement

Every non-off Stage-2 posture requires a completed G1 cut and its certificate.
The trajectory SDK accepts the runner's already-resolved G1 certificate receipt
and deliberately does not own its persistence. Computing that certificate at
each boot would couple the runner to `traj certify` internals and let one
unclean boot revoke an already-earned certificate, preventing Stage-2 shadow
from gathering its own clean-round evidence.

The runner already has one configuration ladder: explicit flags override the
composed environment, whose values include env-file and station-coded defaults.
That is the natural seam for a durable operator measurement.

## Considered Options

* Recompute the G1 certificate from trajectory state at every boot.
* Record the certificate once and resolve its receipt through the runner's
  existing flag and composed-environment ladder.

## Decision Outcome

The G1 certificate is a once-recorded runner receipt. The explicit
`--g1-certificate-passed` or `--no-g1-certificate-passed` flag outranks
`GRID_G1_CERTIFICATE_PASSED`; absent input remains a missing receipt. The
runner passes that nullable value into `TrajectoryConfig` and never invokes or
reimplements `traj certify` during boot.

A missing or false receipt remains visible to the SDK's named
`G2G1PrerequisiteRefused` gate for every non-off G2 posture. Recording the
receipt does not choose a non-off posture and introduces no non-off default.

### Consequences

* Good, because a completed operator measurement remains stable across later
  boots and can unlock the Stage-2 shadow soak.
* Good, because flag, environment, env-file, and station defaults retain one
  resolution path and one precedence rule.
* Bad, because operators must record or revoke the receipt when the measured
  certification state changes; boot does not infer that state for them.
