# ADR 004: KubeVirt as the VM destination

- **Status:** Accepted

## Context

Migrated VMs need a destination on Kubernetes, the platform built in Project 1, so VMs and containers share one control plane, GitOps flow and observability stack. The project must also show the difference between rehosting a VM and modernizing it.

## Decision

Use upstream **KubeVirt** with **CDI** as the VM destination. Not OpenShift Virtualization, because that requires OpenShift.

## Version clarification (Stage 0 refinement)

- Observed at documentation time (2026-09-27): KubeVirt v1.9 is the newest release (built for Kubernetes 1.36, supported on 1.35 and 1.34); CDI v1.66.1 is the newest CDI release. These are observations, **not pins**.
- No official KubeVirt-to-CDI pairing statement was found, so this ADR does not claim any specific pairing is supported.
- The versions are chosen **at deployment time** as one **compatibility tuple** (KubeVirt, Kubernetes, CDI) and accepted only after the runtime validation gate passes ([feasibility section 3](../stage-0/feasibility.md#3-compatibility-tuple-and-runtime-validation-gate)).

## Alternatives considered

| Option | Why not |
|---|---|
| OpenShift Virtualization + MTV | Excellent industry reference, but needs OpenShift; hides the layers we want to learn |
| Plain EC2 import (AWS VM Import) | Target is not Kubernetes; no VM/container coexistence |
| Rebuild as containers only | Skips the migration problem; not every workload can be containerized |

## Consequences

- VMs become Kubernetes objects (`VirtualMachine`, VMI, DataVolume) manageable by GitOps.
- Worker nodes must meet KubeVirt host requirements: `/dev/kvm`, `/dev/vhost-net`, `/dev/net/tun`, privileged virt-handler, containerd/CRI-O, aligned host kernel/userland (see [feasibility section 5](../stage-0/feasibility.md#5-eks-host-requirement-compatibility)).
- Guest drivers must work on virtio.
- KubeVirt, Kubernetes and CDI versions are recorded together as one tuple and validated at runtime before use.

## Evidence

[KubeVirt architecture](https://kubevirt.io/user-guide/architecture/), [KubeVirt installation](https://kubevirt.io/user-guide/cluster_admin/installation/), [support matrix](https://github.com/kubevirt/sig-release/blob/main/releases/k8s-support-matrix.md), [CDI releases](https://github.com/kubevirt/containerized-data-importer/releases), [CDI API reference](https://kubevirt.io/cdi-api-reference/), [KubeVirt: CDI](https://kubevirt.io/user-guide/storage/containerized_data_importer/), [KubeVirt release notes](https://kubevirt.io/user-guide/release_notes/).
