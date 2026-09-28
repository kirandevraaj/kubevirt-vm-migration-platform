# ADR 002: AWS as the disposable migration target

- **Status:** Accepted

## Context

KubeVirt needs Kubernetes worker nodes with hardware virtualization (`/dev/kvm`). The laptop cannot host both nested ESXi and a KVM-capable Kubernetes cluster with enough memory. Project 1 already established Terraform, EKS and GitOps practice on AWS. AWS announced on 2026-02-16 that nested virtualization is available on supported non-bare-metal EC2 instances (KVM and Hyper-V as L1 hypervisors, no additional cost), in addition to bare-metal instances.

## Decision

The destination Kubernetes + KubeVirt environment runs on **AWS**, is **created only through Terraform**, and is **disposable**: built for a working session and destroyed afterwards. No AWS resources are created in Stage 0.

## Scope clarification (Stage 0 refinement)

This ADR decides **where** the target runs and **how** it is managed (Terraform, disposable). It deliberately does **not** decide:

- the Kubernetes topology: **EKS** and **self-managed Kubernetes** are parallel, unvalidated options;
- the EC2 **instance family**, exact size, Region or AMI;
- nested-virtualization instance vs `*.metal`.

Those are deferred decisions, to be made from test evidence against the KubeVirt host-requirement checklist ([feasibility section 5](../stage-0/feasibility.md#5-eks-host-requirement-compatibility)).

Cross-reference (Stage 1H): the first-migration target topology, instance family, Region and node OS are decided by design in [ADR 007](007-kubevirt-target-platform.md), still subject to a runtime validation gate.

## Consequences

- Cost is bounded by session length; Git + Terraform are the source of truth.
- Open validation questions: whether the chosen worker architecture (EKS-managed or self-managed) satisfies every KubeVirt host requirement (CPU nested virtualization, `/dev/kvm`, `/dev/vhost-net`, `/dev/net/tun`, privileged DaemonSets, host kernel/userland alignment, runtime, device ownership, node image, storage, networking).
- EBS gp3 volumes are RWO and AZ-scoped: VM workers and volumes live in one AZ; no live migration across nodes.
- Every session repeats cluster bootstrap, so KubeVirt/CDI install must be automated.
- Blocker: AWS credentials must be recovered or re-issued first.

## Evidence

[AWS: nested virtualization on EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html), [What's New 2026-02-16](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual/), [KubeVirt installation requirements](https://kubevirt.io/user-guide/cluster_admin/installation/), [EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html). Project 1 ADR 001 (Terraform for AWS) precedent.
