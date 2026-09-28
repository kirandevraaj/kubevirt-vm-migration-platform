# ADR 009: EBS gp3 Block PVC through CDI upload; qcow2 in transit, raw at rest

- **Status:** Accepted (Stage 1H, 2026-09-28). Design decision; nothing has been deployed.

## Context

[ADR 006](006-dedicated-conversion-host.md) left the KubeVirt target disk format and the CDI import path open. Stage 1G produced a guest-adapted qcow2 (virt-v2v, 40 GiB virtual, 2.73 GiB file) from the golden VMDK. CDI v1.66.1 imports qcow2, VMDK, VDI, VHD, VHDX and raw, and converts all of them to raw [E14]. KubeVirt consumes a PVC either as a raw block device or as a raw `disk.img` file on a filesystem [E23]. The target is one EC2 node with EBS ([ADR 007](007-kubevirt-target-platform.md)).

## Decision

| Item | Decision |
|---|---|
| Storage backend | AWS EBS CSI driver, **gp3** (3,000 IOPS / 125 MiB/s baseline) [E40, E41] |
| StorageClass | `type: gp3`, `volumeBindingMode: WaitForFirstConsumer`, `reclaimPolicy: Delete`, `allowVolumeExpansion: true` |
| VM disk PVC | **`volumeMode: Block`**, **`ReadWriteOnce`**, **40Gi** (equal to the source's virtual size, never smaller) |
| Scratch | Same class, Filesystem, RWO (CDI always uses Filesystem RWO scratch, and upload always needs it) [E17] |
| Input format | VMDK, read only, never converted in place |
| **Transfer format** | **qcow2**: the guest-adapted virt-v2v output, remediated on a disposable copy (about 2.7 GiB to move instead of 40 GiB) |
| **Target representation** | **raw on the Block PVC**, written by CDI |
| Import | CDI **upload** DataVolume via `virtctl image-upload` run on the node through `kubectl port-forward`, so the upload proxy is never exposed [E16, E49] |
| Lifecycle | A standalone DataVolume/PVC referenced by the VM (not a `dataVolumeTemplate`), so deleting the VM keeps the disk |
| Disk bus | `virtio` |
| Runtime setting | CRI-O `device_ownership_from_security_context = true` (required for CDI on block PVCs) [E18] |

## Why

- **Block over Filesystem:** KubeVirt reads the raw device directly, with no `disk.img` or filesystem overhead [E23]. EBS supports raw block volumes [E40].
- **qcow2 over raw in transit:** CDI converts to raw anyway [E14, E15], and qcow2 moves only allocated data.
- **Not VMDK straight into CDI:** CDI would accept it, but that would skip the guest adaptation (netplan, VMware Tools, first-boot jobs) that Stage 1G showed is required.
- **Not a containerDisk:** ephemeral; a migrated server needs persistent storage.
- **40Gi exactly:** CDI resizes the image to the available space for `kubevirt` content [E15]; an equal size keeps the guest-visible disk geometry unchanged.
- **Upload on the node:** no public exposure of `cdi-uploadproxy`, and no extra Service or Ingress.

## Cold versus live migration

Live migration requires shared ReadWriteMany volumes [E22]. EBS gp3 is RWO and AZ-scoped, so this VM is **not live-migratable**. That is accepted: the first migration is a cold copy. RWX storage is deferred and the design is not shaped around live migration.

## Consequences

- An import temporarily needs about twice the disk size (Block target plus Filesystem scratch).
- The disk is deleted with the cluster (`reclaimPolicy: Delete`). The authoritative copy is the prepared qcow2 on `conversion-host-01`, plus the golden VMDK.
- The EBS CSI driver needs an instance-profile IAM policy and IMDSv2 hop limit 2 (a documented security trade-off in the Stage 1H record, section 23).
- Deferred: RWX storage, snapshots and backup, preallocation tuning, other CSI drivers, HTTP or registry import sources.

## Evidence

[Stage 1H record](../stage-1/stage-1h-kubevirt-target-feasibility.md), sections 16 to 18, sources E14 to E18, E22, E23, E40, E41, E49.
