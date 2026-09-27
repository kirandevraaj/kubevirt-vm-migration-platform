# ADR 003: Cold migration before warm migration

- **Status:** Accepted

## Context

Warm migration copies disks while the source runs, using VM snapshots and VMware Changed Block Tracking (CBT), then performs a short cutover. It needs API write access to the source (snapshots, CBT). Our source is free standalone ESXi, where API use is unsupported and may be read-only, and there is no vCenter. Our first workload is one small nginx VM where minutes of downtime are acceptable.

## Decision

The first real migration is **cold**: power off the source, copy and convert the disk, import with CDI, start on KubeVirt. **Warm migration is theory and industry reference only** (as implemented by MTV). We do **not** design a custom warm-migration engine.

## Consequences

- Simpler, consistent disk images; no snapshot or CBT dependency.
- Downtime = copy + convert + import + boot. It will be measured and recorded in the migration status.
- The CRD keeps `spec.strategy.type` with `Cold` only, reserving `Warm`.
- Revisit only with a licensed vSphere (or vCenter) source and a demonstrated need.
- Clarification (Stage 0 refinement): warm migration (precopy, CBT, cutover) remains **reference and study work** only, documented from MTV as an industry reference. No warm-migration code, CRD phases or controller logic will be designed until this ADR is superseded.

## Evidence

[MTV 2.11 planning guide](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.11/html-single/planning_your_migration_to_red_hat_openshift_virtualization/index) (precopy snapshots every 60 min by default, 28-CBT-snapshot limit, RAM not migrated at cutover); [Broadcom KB 399823](https://knowledge.broadcom.com/external/article/399823) (free-edition API limits).
