---
status: accepted
date: 2026-09-12
decision-makers: ["governor"]
consulted: []
informed: []
register:
  spec: 1
  slug: installed-overlay-freshness-reuses-the-vended-dry-run
  surfaces:
    - ".github/workflows/ci.yml"
    - "apps/space/test/overlay_freshness_contract_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: space-0p5
  legacy-id: null
---

# Installed-overlay freshness reuses the vended dry-run

## Context and Problem Statement

This repository installs its operator overlay from `grid_assets`, but a
generated copy can remain unchanged after the resolved pack has moved. A
one-time re-vend repairs the current files without preventing the installed
tree from silently lagging again.

The provenance marker is not a freshness oracle. The public provenance seam
does not read a source ref back out of an installed stamp, and a ref-only
difference is deliberately not drift: forcing every artifact to adopt every
new pack ref would churn bodies that did not change. The overlay manifest also
does not carry per-file provenance. A local ref parser or manifest reader would
therefore create a second implementation without proving body freshness.

The vended materializer already resolves every artifact selected by the
station overlay's source-to-target mappings, renders it from the resolved pack,
and compares it with the stripped installed body. Its check mode writes nothing
and exits non-zero when an artifact is missing, drifted, hand-edited, or stale.

## Considered Options

- Run the vended `assets install` command in check mode as part of this
  repository's gate.
- Parse installed provenance stamps and compare their refs with the resolved
  pack. Rejected because no public read seam exists and a ref-only difference
  is not body drift.
- Read the overlay manifest and reproduce selection and comparison locally.
  Rejected because it would duplicate the materializer and create a second
  overlay authority in this repository.
- Re-vend the current overlay without a lasting gate. Rejected because it
  corrects one stale snapshot while leaving recurrence silent.

## Decision Outcome

The repository CI runs
`dart run space:space assets install --check --no-diff` immediately after
`dart pub get`. Freshness means that every artifact selected across the complete
installed overlay has the same rendered body as the resolved pack. The vended
command's non-zero exit is the fail-closed signal, and this repository adds no
provenance parser, manifest reader, local overlay source, or second materializer.

A file-reading contract test pins both the command and its adjacency to
dependency resolution. The existing process smoke remains responsible for
proving that a deliberately drifted installed body exits non-zero.

This applies
`power_station#the-worktree-overlay-scope-widens-to-every-skill-tree` to the
complete selected overlay and follows
`power_station#a4-gate-integrity-3-bead-tg-bns-the-verdict-freshness-stamp` by
testing the failure arm, not only a clean tree. It also preserves
`power_station#a32-skills-home-s-placement-split-is-stale-every-vended-skil`:
the gate covers the general vended-tree failure rather than one named skill.

### Consequences

- Good, because dependency resolution and installed overlay freshness are one
  ordered repository gate.
- Good, because every declared harness mapping is checked by the same
  materializer that installs it.
- Good, because unchanged bodies do not churn solely to acquire a newer
  provenance ref.
- Bad, because the gate depends on the resolved pack's install command being
  runnable before analysis and tests begin.
