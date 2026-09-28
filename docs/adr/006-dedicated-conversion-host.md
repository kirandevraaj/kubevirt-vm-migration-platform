# ADR 006: Dedicated conversion host for disk inspection, conversion and boot validation

- **Status:** Accepted (Stage 1G, 2026-09-28)

## Context

A migration needs somewhere to hold VM disk copies and run offline disk tools: qemu-img (disk containers), libguestfs (guest filesystems), virt-v2v (whole-guest conversion) and QEMU/KVM (boot tests of converted disks). [Stage 0 feasibility section 6](../stage-0/feasibility.md#6-conversion-host-deferred-decision) listed three places this could run: a local Linux helper VM on ESXi, an AWS instance, or a Job inside the target cluster. The Stage 1E entry criteria asked for the choice to be recorded as an ADR.

The lab already had two Linux VMs with fixed roles. `legacy-source-vm` (Vmid 2) is the migration source and must stay an unaltered, running reference. `kvm-learning-01` (Vmid 1) is the Stage 1B learning VM and is kept powered off. Stage 1F therefore built a third VM, `conversion-host-01` (Vmid 3), for inspection only. Stage 1G then needed a place to run real conversions and boot converted guests, which raised the same question again with higher stakes.

## Decision

`conversion-host-01` is the **dedicated host for disk inspection, conversion experiments and QEMU/KVM boot validation** in this lab. It is separate from `legacy-source-vm` and from `kvm-learning-01`, and neither of those is used for this work.

Operating rules:

1. **Golden protection.** The golden Stage 1E artifact stays on the Windows host (`C:\VMs\legacy-source-vm\stage-1e\`) and is only ever read. Its descriptor and flat extent carry the Windows read-only attribute (set in Stage 1G). It is re-hashed before and after each stage.
2. **Protected input.** Tools on the conversion host read only the hash-verified working copy in `/srv/migration-lab/working/` (mode 0444, `chattr +i`). Nothing converts in place: every conversion writes to a new path, every output is hashed and then made read-only.
3. **Disposable boots.** Converted disks are booted only through qcow2 overlays and per-boot copies of the OVMF variable store, which are deleted afterwards. A remediation is applied to a separate full copy, never to a conversion output.
4. **One-way data flow.** Disk bytes flow golden -> working copy -> outputs. Only text evidence flows back to Windows. Conversion tools never connect to ESXi, vCenter or the running source VM.
5. **Capacity.** One conversion or test VM runs at a time, at most 2 vCPU and 2048 MB for a test guest. Work stops if Windows free memory approaches 2 GiB.
6. **Toolchain.** The tools come from the Ubuntu 24.04 archive, installed with `--no-install-recommends`, and their versions are recorded. They are not upgraded silently. If a tool proves insufficient, the stage stops for review.

### Supported tooling (as of Stage 1G)

| Tool | Package version | Role |
|---|---|---|
| qemu-img / qemu-system-x86_64 | 1:8.2.2+ds-0ubuntu1.18 | Container conversion; direct QEMU/KVM boots without libvirt |
| libguestfs, guestfish | 1:1.52.0-5ubuntu3 | Read-only inspection; overlay instrumentation; file-level diffs (guestfs-tools 1.52.0-2ubuntu5) |
| virt-v2v | 2.4.0-2build4 | Guest-aware conversion, `-i disk` to `-o local` only |
| nbdkit / libnbd / supermin | 1.36.3 / 1.20.0 / 5.2.2 | virt-v2v and libguestfs dependencies |
| ovmf | 2024.02-2ubuntu0.9 | UEFI firmware for boot tests (`OVMF_CODE_4M.fd`, Secure Boot off) |

## Why the separation exists

- **Blast radius.** Conversion tools write large files, run as root and boot untrusted copies of the source guest. None of that can affect the source VM or its disk.
- **A clean reference.** `legacy-source-vm` stays the unaltered "before" state, so every result can be compared against it and it can serve as the rollback.
- **Identity safety.** A converted copy has the same machine-id, SSH host keys, hostname and configured IP as the source. Keeping it on an isolated network inside a separate host means the two identities never meet on the LAN.
- **Role clarity.** The learning VM can be broken by experiments without losing conversion evidence, and the reverse.
- **Resource accounting.** The host's cost is visible on its own and can be powered off as a unit.

## Resource implications

- `conversion-host-01` uses 4 vCPU, 8192 MB and a 60 GB thin disk. While it runs, ESXi reports about 8.2 GB of host memory for it, plus an 8 GiB swap file on the datastore. With it and the source running, ESXi uses about 11.3 of 16 GB, so `kvm-learning-01` should stay off during conversion work (INFERRED from the numbers, not tested).
- A QEMU test guest runs inside the conversion host's own memory: Stage 1G boots of 2048 MB guests did not raise ESXi memory use.
- The kept Stage 1G artifacts use 8.7 GB inside the guest, and datastore free space fell by 9.2 GB (8.58 GiB). Running `fstrim` after deleting temporary files returns their space to the thin VMDK.
- Everything runs three hypervisors deep (Windows -> ESXi -> conversion host -> test guest). Timings are functional evidence only, not performance data.

## Consequences

- There is one reproducible lab pipeline: golden -> working copy -> conversion output -> remediated copy -> boot test. Every step is hash-verified.
- The conversion host is a single point of lab state. Its outputs live outside Git, so the evidence and scripts on the Windows host (`C:\VMs\conversion-host-01\`) are the reproducible record.
- A larger or parallel conversion workload would need more memory than this laptop lab offers.

## What this ADR does NOT decide

- The **KubeVirt target disk format** (raw or qcow2 on the PVC, or a container disk) and the CDI import path. Both remain explicit future decisions.
- Where **production** conversion runs (an AWS instance, a cluster Job or conversion pod as MTV/Forklift does, or elsewhere). This ADR covers the lab only.
- Whether the final pipeline uses virt-v2v, qemu-img plus manual adaptation, or both.
- The network policy for a real cutover: interface matching, static versus DHCP addressing, and when the production IP moves.
- Use of `virt-v2v -o kubevirt`, and anything about Kubernetes, KubeVirt, CDI, AWS or the migration controller ([ADR 005](005-custom-controller-vs-scripts.md)).

## Evidence

[Stage 1F record](../stage-1/stage-1f-conversion-host.md) (host build, toolchain, working copy); [Stage 1G record](../stage-1/stage-1g-controlled-conversion.md) (conversions, boot tests, resource numbers).
