# Stage 1: source environment build-out

**Project 1.5: VM-to-Kubernetes Migration Platform (ESXi -> KubeVirt Migration & VM Modernization)**

Stage 1 turns the Stage 0 design into a working source environment, one small, separately approved step at a time. Each sub-stage has its own scope, change boundary, evidence and entry criteria for the next step.

Background: [Stage 0 README](../stage-0/README.md), [Stage 0 feasibility](../stage-0/feasibility.md), [ADRs](../adr/README.md).

## Sub-stages

| Sub-stage | Objective | Status | Document |
|---|---|---|---|
| 1A | Prove the ESXi source host survives a controlled reboot and all required configuration persists | **Complete (PASS)**, 2026-09-27 | [stage-1a-esxi-reboot-validation.md](stage-1a-esxi-reboot-validation.md) |
| 1B | First source VM on ESXi, starting with a nested 64-bit guest boot | Not started; awaiting user approval | - |

## Stage 1A in one paragraph

A graceful `esxcli system shutdown reboot` was performed with the host in maintenance mode and no guest VMs. The host was back on the management network 40 s later (host log) and every checked item persisted: hostname, ESXi 8.0.3 build 24677879, `vmk0` 192.168.50.11/24 static, default route and DNS 192.168.50.2, vSwitch0 with vmnic0 and both port groups, `migration-datastore` (VMFS-6, byte-identical free space), HV Support 3, hostd, rhttpproxy, vpxa, SSH and ESXi Shell, HTTPS 443 and SSH key login. NTP re-synchronized on its own within about 3.5 minutes. Maintenance mode was then exited. This closes Stage 0 item N2 (reboot persistence).

## Current source host state (after Stage 1A)

| Item | Value |
|---|---|
| Host | `esxi-8-lab.localdomain`, ESXi 8.0.3 build 24677879 |
| Management | `vmk0` 192.168.50.11/24 static, gateway and DNS 192.168.50.2 |
| Datastore | `migration-datastore`, VMFS-6, 199.8 GB, 198.3 GB free, empty |
| Nested virtualization | HV Support 3 (64-bit L2 guest not yet tested) |
| Time | NTP enabled and synchronized |
| Access | SSH key login via the `esxi-8-lab` alias; HTTPS 443 reachable |
| Guest VMs | 0 |
| Maintenance mode | Disabled |

## Stage 1B entry criteria

See [section 11 of the Stage 1A document](stage-1a-esxi-reboot-validation.md#11-stage-1b-entry-criteria).
