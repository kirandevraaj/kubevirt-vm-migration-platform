# ADR 004: KubeVirt as the VM destination

- **Status:** Accepted

## Context

Migrated VMs need a destination on Kubernetes, the platform built in Project 1, so VMs and containers share one control plane, GitOps flow and observability stack. The project must also show the difference between rehosting a VM and modernizing it.

## Decision

Use upstream **KubeVirt** (currently v1.9) with **CDI** (currently v1.66.x) as the VM destination, on Kubernetes **1.35 or 1.36** (inside the KubeVirt v1.9 support window). Not OpenShift Virtualization, because that requires OpenShift.

## Alternatives considered

| Option | Why not |
|---|---|
| OpenShift Virtualization + MTV | Excellent industry reference, but needs OpenShift; hides the layers we want to learn |
| Plain EC2 import (AWS VM Import) | Target is not Kubernetes; no VM/container coexistence |
| Rebuild as containers only | Skips the migration problem; not every workload can be containerized |

## Consequences

- VMs become Kubernetes objects (`VirtualMachine`, VMI, DataVolume) manageable by GitOps.
- Worker nodes need `/dev/kvm`, privileged virt-handler, containerd/CRI-O (see [feasibility](../stage-0/feasibility.md)).
- Guest drivers must work on virtio.
- KubeVirt and CDI versions must be pinned together and checked against the Kubernetes version.

## Evidence

[KubeVirt architecture](https://kubevirt.io/user-guide/architecture/), [KubeVirt installation](https://kubevirt.io/user-guide/cluster_admin/installation/), [support matrix](https://github.com/kubevirt/sig-release/blob/main/releases/k8s-support-matrix.md), [CDI releases](https://github.com/kubevirt/containerized-data-importer/releases).
