# ADR 007: Self-managed kubeadm on one nested-virtualization EC2 instance as the first KubeVirt target

- **Status:** Accepted (Stage 1H, 2026-09-28). Design decision; nothing has been provisioned.

## Context

[ADR 002](002-aws-disposable-target.md) placed the target on AWS (Terraform, disposable) but left the topology open: EKS or self-managed Kubernetes, instance family, AMI, and nested virtualization versus bare metal. [ADR 004](004-kubevirt-vm-destination.md) chose upstream KubeVirt + CDI with versions recorded as one runtime-validated tuple. Stage 1H had to close these questions from official evidence, without creating anything.

The evidence that decided it (all retrieved 2026-09-28; details and URLs in the [Stage 1H record](../stage-1/stage-1h-kubevirt-target-feasibility.md#sources)):

- KubeVirt v1.9.0 is the stable release. It is built for Kubernetes 1.36 and supported on 1.35 and 1.34, not on 1.37 [E1 to E4].
- KubeVirt's virt-launcher ships a CentOS Stream 9 libvirt/QEMU userland. The project recommends a host kernel aligned with it, and its CI runs only on EL9 host kernels [E5 to E7].
- KubeVirt's release-1.9 CI runs its Kubernetes 1.36 lanes on kubeadm + CentOS Stream 9 + CRI-O 1.36 + flannel [E8, E9].
- AWS offers nested virtualization (KVM as the L1 hypervisor, no extra charge) on listed Intel families, including M8i and M7i, and all of them are sold in ap-south-1 [E32, E33, E42].
- EKS offers Kubernetes 1.36 and admits privileged pods by default [E35, E38]. Its optimized AMIs are Amazon Linux, Bottlerocket, Ubuntu and Windows, none of them Enterprise Linux [E37]. CPU options are not prohibited in managed-node-group launch templates [E36], but AWS does not document KubeVirt on EKS.

## Decision

**Chosen target for the first KubeVirt migration:**

| Item | Value |
|---|---|
| Platform | Self-managed Kubernetes, bootstrapped with kubeadm, **one node** acting as control plane and worker (control-plane taint removed) |
| Compute | One EC2 `m8i.xlarge` (4 vCPU, 16 GiB, Intel), **nested virtualization enabled** at launch, on demand; `m7i.xlarge` as the alternate |
| Region / AZ | **ap-south-1**, one Availability Zone |
| Node OS | CentOS Stream 9, x86_64 (official CentOS AMI) |
| Runtime | CRI-O 1.36, systemd cgroup driver, cgroup v2, SELinux enforcing |
| Kubernetes | 1.36 (patch pinned at build time) |
| KubeVirt / CDI | v1.9.0 / v1.66.1 |
| CNI / CSI | flannel / AWS EBS CSI driver |
| Lifecycle | Built and destroyed with Terraform per session (ADR 002) |

This is the platform KubeVirt's own CI uses for Kubernetes 1.36, with EC2 nested virtualization in place of kubevirtci's VMs. The tuple stays a candidate until the Stage 0 runtime validation gate passes on the real node.

Not a claim about production suitability.

## Alternatives

| Alternative | Outcome | Reason |
|---|---|---|
| **EKS** with nested-virtualization managed nodes | **Deferred** | Kernel alignment would need a self-built EL9 node AMI, which removes most of the managed-node benefit. The `/dev/kvm` path on EKS is undocumented, the VPC CNI is not a KubeVirt CI platform, and the control plane adds USD 0.10/h (+42%). Not rejected: a later stage can compare it on evidence |
| **Local VMware-hosted Kubernetes** | Rejected as the primary target | Guests would run four layers deep; the laptop has about 6 GiB free and ESXi is at 11.3 of 16 GB; ADR 002 fixed AWS; keeping VMnet8 would invite artificial preservation of 192.168.50.31 |
| **Bare-metal EC2** (`m7i.metal-24xl`, USD 5.0904/h) | Fallback only | About 23 times the cost. Used only if nested virtualization fails, and only after a new decision |
| **Software emulation** (`useEmulation`) | Rejected | Not representative; the build stops if `/dev/kvm` is missing |
| **Ubuntu or Amazon Linux nodes** | Rejected | Non-EL kernels are outside KubeVirt's upstream validation [E7] |
| **Multi-node / multi-AZ** | Deferred | Nothing in one cold migration needs it |

## Consequences

- **Technical:** every host requirement (VT-x, `/dev/kvm`, `/dev/vhost-net`, `/dev/net/tun`, privileged API server, CRI-O, SELinux, cgroup v2, EL kernel) is under our control and inspectable. The only unproven element is nested virtualization on the chosen type in ap-south-1.
- **Operational:** we own the control plane, upgrades and certificates. That is acceptable for a disposable single node; one node means no HA.
- **Cost (ap-south-1, on demand, 2026-09-28 price files):** about USD 0.239/h all-in (instance 0.2227, 90 GiB gp3 about 0.011, public IPv4 0.005). A 4-hour session is about USD 0.96; a forgotten month about USD 174.
- **Reproducibility:** plain EC2/VPC/IAM resources in Terraform; the CentOS AMI ID is re-resolved at build time.
- **Migration suitability:** fits a cold migration of one VM. It cannot live-migrate (one node, RWO storage).
- **Limitations:** nested virtualization is slower than metal and new on EC2 (February 2026). CentOS Stream 9 reaches EOL on 2027-05-31. AWS credentials must be available before any build (ADR 002 blocker).

## Evidence

[Stage 1H record](../stage-1/stage-1h-kubevirt-target-feasibility.md), sections 6 to 12 and 22, sources E1 to E9, E25 to E38, E42 to E48.
