# Stage 1: source environment build-out

**Project 1.5: VM-to-Kubernetes Migration Platform (ESXi -> KubeVirt Migration & VM Modernization)**

Stage 1 turns the Stage 0 design into a working source environment, one small, separately approved step at a time. Each sub-stage has its own scope, change boundary, evidence and entry criteria for the next step.

Background: [Stage 0 README](../stage-0/README.md), [Stage 0 feasibility](../stage-0/feasibility.md), [ADRs](../adr/README.md).

## Sub-stages

| Sub-stage | Objective | Status | Document |
|---|---|---|---|
| 1A | Prove the ESXi source host survives a controlled reboot and all required configuration persists | **Complete (PASS)**, 2026-09-27 | [stage-1a-esxi-reboot-validation.md](stage-1a-esxi-reboot-validation.md) |
| 1B | One Linux learning VM on ESXi: KVM / QEMU / libvirt / VirtIO fundamentals and nested KVM feasibility | **In progress**: lab work done, all gates B1 to B10 PASS, awaiting user review | [stage-1b-kvm-qemu-fundamentals.md](stage-1b-kvm-qemu-fundamentals.md), [kvm-learning-lab.md](kvm-learning-lab.md), [nested-kvm-feasibility.md](nested-kvm-feasibility.md) |
| 1C | Not yet defined (likely the migration source VM `legacy-source-vm`) | Not started; awaiting user approval | - |

Diagram of the actual lab layers: [lab-nested-kvm-layers.svg](../diagrams/lab-nested-kvm-layers.svg).

Labels used in all Stage 1 documents: **OBSERVED** = seen in this lab by a command we ran. **INFERRED** = reasoned from observations or documentation, not directly tested. **NOT TESTED** = deliberately not done.

## Stage 1A in one paragraph

A graceful `esxcli system shutdown reboot` was performed with the host in maintenance mode and no guest VMs. The host was back on the management network 40 s later (host log) and every checked item persisted: hostname, ESXi 8.0.3 build 24677879, `vmk0` 192.168.50.11/24 static, default route and DNS 192.168.50.2, vSwitch0 with vmnic0 and both port groups, `migration-datastore` (VMFS-6, byte-identical free space), HV Support 3, hostd, rhttpproxy, vpxa, SSH and ESXi Shell, HTTPS 443 and SSH key login. NTP re-synchronized on its own within about 3.5 minutes. Maintenance mode was then exited. This closes Stage 0 item N2 (reboot persistence).

## Stage 1B in one paragraph

One Ubuntu 24.04.4 LTS VM, `kvm-learning-01` (2 vCPU, 4 GB, 40 GB thin, one VMXNET3 NIC on VM Network, UEFI, `vhv.enable = TRUE`), was installed unattended on `migration-datastore`. It booted as a 64-bit guest, which closes Stage 0 item N1. Inside it, ESXi exposes VT-x and EPT: `/dev/kvm` exists, and `kvm_intel` loads with `nested=Y`. With a minimal package set (QEMU 8.2.2, libvirt 10.0.0, cpu-checker), a tiny L3 guest booted **KVM accelerated**, both directly and through libvirt, and showed virtio-blk, virtio-scsi and virtio-net devices. CPU-bound work in L3 runs at near-L2 speed. VM exits are very expensive three hypervisors deep, so this lab is for learning and functional tests, not performance numbers. Details: [Stage 1B record](stage-1b-kvm-qemu-fundamentals.md).

## Current source host state (after Stage 1B lab work)

| Item | Value |
|---|---|
| Host | `esxi-8-lab.localdomain`, ESXi 8.0.3 build 24677879 |
| Management | `vmk0` 192.168.50.11/24 static, gateway and DNS 192.168.50.2 (unchanged) |
| Datastore | `migration-datastore`, VMFS-6, 199.8 GB, 186.5 GB free (200,268,578,816 bytes; GB = 2^30 bytes here, as in Stage 1A); holds `kvm-learning-01/` and `iso/` (Ubuntu 24.04.4 ISO) |
| Nested virtualization | HV Support 3; 64-bit L2 guest validated; KVM inside L2 validated |
| Time | NTP enabled and synchronized |
| Access | SSH key login via the `esxi-8-lab` alias; HTTPS 443 reachable |
| Guest VMs | 1: `kvm-learning-01` (Vmid 1), powered on, 192.168.50.30, no snapshots |
| Maintenance mode | Disabled |

## Stage 1C entry criteria

See [section 11 of the Stage 1B record](stage-1b-kvm-qemu-fundamentals.md#11-stage-1c-entry-criteria). The Stage 1B entry criteria are in [section 11 of the Stage 1A document](stage-1a-esxi-reboot-validation.md#11-stage-1b-entry-criteria).
