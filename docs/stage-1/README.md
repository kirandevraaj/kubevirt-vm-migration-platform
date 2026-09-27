# Stage 1: source environment build-out

**Project 1.5: VM-to-Kubernetes Migration Platform (ESXi -> KubeVirt Migration & VM Modernization)**

Stage 1 turns the Stage 0 design into a working source environment, one small, separately approved step at a time. Each sub-stage has its own scope, change boundary, evidence and entry criteria for the next step.

Background: [Stage 0 README](../stage-0/README.md), [Stage 0 feasibility](../stage-0/feasibility.md), [ADRs](../adr/README.md).

## Sub-stages

| Sub-stage | Objective | Status | Document |
|---|---|---|---|
| 1A | Prove the ESXi source host survives a controlled reboot and all required configuration persists | **Complete (PASS)**, 2026-09-27 | [stage-1a-esxi-reboot-validation.md](stage-1a-esxi-reboot-validation.md) |
| 1B | One Linux learning VM on ESXi: KVM / QEMU / libvirt / VirtIO fundamentals and nested KVM feasibility | **Complete (PASS)**, 2026-09-27 | [stage-1b-kvm-qemu-fundamentals.md](stage-1b-kvm-qemu-fundamentals.md), [kvm-learning-lab.md](kvm-learning-lab.md), [nested-kvm-feasibility.md](nested-kvm-feasibility.md) |
| 1C | Create and baseline the VMware migration source VM `legacy-source-vm` (Ubuntu 24.04.5, nginx, PVSCSI, VMXNET3, static IP) | **Complete (PASS)**, 2026-09-27 | [stage-1c-migration-source.md](stage-1c-migration-source.md) |
| 1D | Characterize the source VM's datastore artifacts and VMDK; investigate free-ESXi acquisition; design the cold copy (not executed) | **Investigation done**: all gates D1 to D10 PASS, awaiting user review | [stage-1d-vmware-source-artifacts.md](stage-1d-vmware-source-artifacts.md) |
| 1E | Not yet defined (likely the approved cold acquisition of the source disk) | Not started; awaiting user approval | - |

Diagrams: [lab-nested-kvm-layers.svg](../diagrams/lab-nested-kvm-layers.svg) (lab layers, Stage 1B), [stage-1c-source-lab.svg](../diagrams/stage-1c-source-lab.svg) (VM roles after Stage 1C) and [stage-1d-source-artifacts.svg](../diagrams/stage-1d-source-artifacts.svg) (source VM artifacts and the future conversion boundary).

Labels used in all Stage 1 documents: **OBSERVED** = seen in this lab by a command we ran. **INFERRED** = reasoned from observations or documentation, not directly tested. **NOT TESTED** = deliberately not done.

## Stage 1A in one paragraph

A graceful `esxcli system shutdown reboot` was performed with the host in maintenance mode and no guest VMs. The host was back on the management network 40 s later (host log) and every checked item persisted: hostname, ESXi 8.0.3 build 24677879, `vmk0` 192.168.50.11/24 static, default route and DNS 192.168.50.2, vSwitch0 with vmnic0 and both port groups, `migration-datastore` (VMFS-6, byte-identical free space), HV Support 3, hostd, rhttpproxy, vpxa, SSH and ESXi Shell, HTTPS 443 and SSH key login. NTP re-synchronized on its own within about 3.5 minutes. Maintenance mode was then exited. This closes Stage 0 item N2 (reboot persistence).

## Stage 1B in one paragraph

One Ubuntu 24.04.4 LTS VM, `kvm-learning-01` (2 vCPU, 4 GB, 40 GB thin, one VMXNET3 NIC on VM Network, UEFI, `vhv.enable = TRUE`), was installed unattended on `migration-datastore`. It booted as a 64-bit guest, which closes Stage 0 item N1. Inside it, ESXi exposes VT-x and EPT: `/dev/kvm` exists, and `kvm_intel` loads with `nested=Y`. With a minimal package set (QEMU 8.2.2, libvirt 10.0.0, cpu-checker), a tiny L3 guest booted **KVM accelerated**, both directly and through libvirt, and showed virtio-blk, virtio-scsi and virtio-net devices. CPU-bound work in L3 runs at near-L2 speed. VM exits are very expensive three hypervisors deep, so this lab is for learning and functional tests, not performance numbers. Details: [Stage 1B record](stage-1b-kvm-qemu-fundamentals.md).

## Stage 1C in one paragraph

The migration source VM `legacy-source-vm` (Vmid 2: 2 vCPU, 4096 MB, 40 GB thin, UEFI, PVSCSI, one VMXNET3 NIC on VM Network) was installed unattended from the official Ubuntu 24.04.5 live-server ISO. The ISO was downloaded from `releases.ubuntu.com`, and its SHA256 and signature were verified. The VM serves a deterministic nginx page (267 bytes, fixed sha256) at the static address 192.168.50.31, reachable from Windows and ESXi. The baseline records the stable identifiers (filesystem and partition UUIDs, machine-id, SSH host keys, config checksums) and the VMware-specific ones that will change on KubeVirt: disk and NIC drivers, device names, MAC, SMBIOS UUID and UEFI NVRAM. The biggest recorded risk is that netplan matches the NIC by the name `ens192`, so a virtio-net NIC would come up unconfigured. As required, nothing was adapted. `kvm-learning-01` was then shut down gracefully. The conversion host remains deferred. Details: [Stage 1C record](stage-1c-migration-source.md).

## Stage 1D in one paragraph

A read-only investigation of `legacy-source-vm` on the datastore. The disk is an ESXi `vmfs` VMDK: a 541-byte text descriptor plus one thin flat extent (40 GiB logical, 3,487 MiB allocated), with no snapshot chain. The VM configuration (`.vmx`) and the UEFI variable store (`.nvram`) are separate files, and neither is part of what a migration moves: only the disk bytes travel. While the VM runs, the flat extent is exclusively locked and cannot be read at all, so acquisition must be cold. On this free ESXi host, SSH/`scp`, `vmkfstools -i` (including a lossless `2gbsparse` export, proven on a throwaway scratch disk) and the authenticated HTTPS datastore file service work. The recommended first acquisition is a cold `scp` of descriptor plus flat extent, with sha256 on both ends: about 40 GiB, 15 to 20 minutes of downtime. It is designed, not executed. The source was verified unchanged before and after. Details: [Stage 1D record](stage-1d-vmware-source-artifacts.md).

## Current source host state (after Stage 1D; unchanged since Stage 1C)

| Item | Value |
|---|---|
| Host | `esxi-8-lab.localdomain`, ESXi 8.0.3 build 24677879 |
| Management | `vmk0` 192.168.50.11/24 static, gateway and DNS 192.168.50.2 (unchanged) |
| Datastore | `migration-datastore`, VMFS-6, 199.8 GB, 179.3 GB free (192,509,116,416 bytes; GB = 2^30 bytes here, as in Stage 1A); holds `legacy-source-vm/`, `kvm-learning-01/` and `iso/` (Ubuntu 24.04.4 and 24.04.5 ISOs) |
| Nested virtualization | HV Support 3; 64-bit L2 guest validated; KVM inside L2 validated |
| Time | NTP enabled and synchronized |
| Access | SSH key login via the `esxi-8-lab` alias; HTTPS 443 reachable |
| Guest VMs | 2: `legacy-source-vm` (Vmid 2), **powered on**, 192.168.50.31, nginx on :80; `kvm-learning-01` (Vmid 1), **powered off**, 192.168.50.30 when running. No snapshots on either. |
| Conversion host | Not created; decision deferred |
| Maintenance mode | Disabled |

## Stage 1E entry criteria

See [section 14 of the Stage 1D record](stage-1d-vmware-source-artifacts.md#14-stage-1e-entry-criteria). Earlier entry criteria: Stage 1D in [section 16 of the Stage 1C record](stage-1c-migration-source.md#16-stage-1d-entry-criteria), Stage 1C in [section 11 of the Stage 1B record](stage-1b-kvm-qemu-fundamentals.md#11-stage-1c-entry-criteria), Stage 1B in [section 11 of the Stage 1A document](stage-1a-esxi-reboot-validation.md#11-stage-1b-entry-criteria).
