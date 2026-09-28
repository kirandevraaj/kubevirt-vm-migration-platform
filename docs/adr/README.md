# Architecture Decision Records (ADRs)

| ADR | Decision | Status | Evidence |
|---|---|---|---|
| [001](001-local-esxi-migration-source.md) | Local nested ESXi as the migration source | Accepted | Stage 0 evidence index; Broadcom free-edition KB |
| [002](002-aws-disposable-target.md) | AWS as the disposable, Terraform-built target (topology and instance family deferred) | Accepted | AWS nested virtualization docs; KubeVirt install requirements |
| [003](003-cold-before-warm.md) | Cold migration before warm; warm stays reference/study work | Accepted | MTV 2.11 warm-migration docs; free ESXi API limits |
| [004](004-kubevirt-vm-destination.md) | Upstream KubeVirt + CDI as the VM destination; versions as a runtime-validated tuple | Accepted | KubeVirt release notes, install docs; CDI releases / API reference |
| [005](005-custom-controller-vs-scripts.md) | Custom Kubernetes controller owns the declarative migration workflow | Accepted (implementation deferred) | Stage 0 CRD / controller / state-machine design |
| [006](006-dedicated-conversion-host.md) | `conversion-host-01` is the dedicated lab host for disk inspection, conversion and QEMU/KVM boot validation, separate from the source and learning VMs (target format and production conversion location not decided) | Accepted | Stage 1F and Stage 1G records |
| [007](007-kubevirt-target-platform.md) | First KubeVirt target: self-managed kubeadm, single node, on one nested-virtualization EC2 instance (`m8i.xlarge`, ap-south-1, CentOS Stream 9, CRI-O 1.36, Kubernetes 1.36, KubeVirt v1.9.0, CDI v1.66.1); EKS deferred; not a production design | Accepted (design; nothing provisioned) | Stage 1H record, sources E1 to E49 |
| [008](008-kubevirt-network-model.md) | Pod network with masquerade binding, no Multus; the VMware IP 192.168.50.31 is not preserved; a NodePort Service provides the stable reachability | Accepted (design) | Stage 1H record; KubeVirt interfaces and networks guide |
| [009](009-kubevirt-storage-model.md) | EBS gp3 Block-mode RWO PVC filled by a CDI upload DataVolume; qcow2 in transit, raw at rest; not live-migratable | Accepted (design) | Stage 1H record; CDI upload, scratch space and block-volume docs; EBS CSI docs |
| [010](010-migration-network-remediation.md) | Guest network remediation: netplan match by driver `virtio_net` with DHCP, applied offline to a disposable copy at conversion time | Accepted (design) | Stage 1G boot evidence; Stage 1H record |

ADRs 001 to 005 were made in **Stage 0** (2026-09-27) and clarified in the Stage 0 technical refinement. ADR 006 was added in **Stage 1G** (2026-09-28). ADRs 007 to 010 were added in **Stage 1H** (2026-09-28) as design decisions; nothing was provisioned.
