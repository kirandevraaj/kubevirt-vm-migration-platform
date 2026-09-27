# ADR 002: AWS as the disposable migration target

- **Status:** Accepted

## Context

KubeVirt needs Kubernetes worker nodes with hardware virtualization (`/dev/kvm`). The laptop cannot host both nested ESXi and a KVM-capable Kubernetes cluster with enough memory. Project 1 already established Terraform, EKS and GitOps practice on AWS. Since 2026-02-16, AWS supports nested virtualization on virtual (non-metal) instances such as C8i/M8i/R8i, which can be much cheaper than `*.metal`.

## Decision

The destination Kubernetes + KubeVirt environment runs on **AWS**, is **created only through Terraform**, and is **disposable**: built for a working session and destroyed afterwards. No AWS resources are created in Stage 0.

## Consequences

- Cost is bounded by session length; Git + Terraform are the source of truth.
- Open questions: EKS managed node group support for the `NestedVirtualization` CPU option, node AMI kernel vs the Enterprise Linux virt-launcher userland, and whether bare metal is needed after all (see [feasibility](../stage-0/feasibility.md)).
- EBS gp3 volumes are RWO and AZ-scoped: VM worker and volumes live in one AZ; no live migration across nodes.
- Every session repeats cluster bootstrap, so KubeVirt/CDI install must be automated.
- Blocker: AWS credentials must be recovered or re-issued first.

## Evidence

[AWS: nested virtualization on EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html), [What's New 2026-02-16](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual/), [EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html). Project 1 ADR 001 (Terraform for AWS) precedent.
