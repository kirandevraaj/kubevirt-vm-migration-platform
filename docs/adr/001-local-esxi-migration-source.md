# ADR 001: Local nested ESXi as the migration source

- **Status:** Accepted

## Context

Project 1.5 needs a real VMware source to migrate from. There is no spare physical server and no access to a corporate vSphere. The laptop (i7-14650HX, 32 GB RAM) can run VMware Workstation Pro, and nested virtualization works once the Windows hypervisor is off.

## Decision

Use **nested ESXi 8.0 U3e (free "vSphere 8 Hypervisor")** running as the Workstation VM `esxi-8-lab` (192.168.50.11, `migration-datastore` VMFS-6) as the migration source. Source VMs (starting with `legacy-source-vm`) will be created on it in a later stage.

## Alternatives considered

| Option | Why not (for now) |
|---|---|
| vCenter + evaluation licenses | Adds a large appliance and a 60-day clock; not needed for one-VM cold migration |
| Exported OVA only, no ESXi | Skips discovery, power control and the datastore model we want to learn |
| Physical ESXi server | Not available |

## Consequences

- Real ESXi objects (VMX, VMDK, VMFS, vSwitch, port groups, `vim-cmd`) are available to learn and automate against.
- Free edition limits apply: no vCenter, 8 vCPU per VM, no VADP, and API use is unsupported and may be read-only. MTV/VDDK/CBT-based paths are not reliable here. Discovery and disk access go through SSH.
- The Windows hypervisor must stay off, so WSL2 and Docker Desktop are unavailable while the lab runs.
- Nested virtualization means performance results are not representative.
- Clarification (Stage 0 refinement): the host itself is proven (ESXi 8.0.3, VMFS-6 datastore, static vmk0, SSH key auth, NTP). A nested 64-bit L2 guest and VMDK acquisition from this free host are **not yet proven** ([feasibility](../stage-0/feasibility.md#not-yet-proven)).

## Evidence

ESXi 8.0.3 build 24677879, `HV Support: 3`, `migration-datastore` 199.8 GB (see [evidence index](../stage-0/evidence-index.md)). Free-edition limits: [Broadcom KB 399823](https://knowledge.broadcom.com/external/article/399823), [ESXi 8.0 U3e release notes](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/release-notes/esxi-update-and-patch-release-notes/vsphere-esxi-80u3e-release-notes.html).
