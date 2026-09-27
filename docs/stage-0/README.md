# Stage 0: theory, architecture and feasibility

**Project 1.5: VM-to-Kubernetes Migration Platform (ESXi -> KubeVirt Migration & VM Modernization)**

Stage 0 status: **complete, with a technical refinement pass** (2026-09-27), pending user review. Nothing was installed or created. ESXi, VMware networking, Windows virtualization and AWS are unchanged.

## Why Stage 0 exists

Migration tooling hides a long chain of layers: VMware objects, disk formats, guest drivers, KVM/QEMU/libvirt, KubeVirt objects, CDI, Kubernetes storage and networking, and controller design. If we start installing before we understand that chain, every failure becomes guesswork. Stage 0 builds the mental model first, checks current (not remembered) version facts, and identifies what must be proven before any build.

## Documents

| Document | Covers |
|---|---|
| [virtualization-fundamentals.md](virtualization-fundamentals.md) | ESXi VM vs KubeVirt VM vs Pod; the ESXi -> guest OS chain and owners; KVM, QEMU, libvirt, VirtIO; VMware -> KVM translation table; nested virtualization (L0/L1/L2, VT-x/EPT) |
| [kubevirt-architecture.md](kubevirt-architecture.md) | Current KubeVirt components, VM vs VMI, lifecycle from `kubectl apply` to guest boot, install requirements |
| [crd-controller-fundamentals.md](crd-controller-fundamentals.md) | CRDs, controllers, reconcile, status, conditions, finalizers; why a controller instead of scripts; the controller model mapped to our state machine |
| [cdi-storage-model.md](cdi-storage-model.md) | CDI, DataVolume, PVC, import/upload/clone; where CDI ends and KubeVirt begins; VMDK/QCOW2/RAW; qemu-img, virt-v2v, libguestfs; storage mapping |
| [vmware-source-model.md](vmware-source-model.md) | Our ESXi objects, what to discover, the inventory model, metadata vs disk data vs runtime state |
| [migration-architecture.md](migration-architecture.md) | End-to-end migration flow, cold vs warm, MTV/Forklift as reference vs our platform, the conceptual `VirtualMachineMigration` CRD, the first demo design |
| [migration-state-machine.md](migration-state-machine.md) | Phases, automatic / retryable / terminal transitions, idempotency |
| [networking-model.md](networking-model.md) | Pod network, masquerade, bridge, Multus, NAD, secondary networks vs vSwitch / port group / vNIC; network mapping |
| [modernization-model.md](modernization-model.md) | VM migration vs application modernization, worked nginx example |
| [architecture.md](architecture.md) | End-to-end architecture, component responsibilities, lab resource architecture (local + disposable AWS) |
| [feasibility.md](feasibility.md) | What must be validated before Stage 1, with status and sources |
| [evidence-index.md](evidence-index.md) | Summarized, non-sensitive evidence of the current lab |
| [glossary.md](glossary.md) | Terms, with VMware analogies |
| [interview-notes.md](interview-notes.md) | 13 interview questions with short and detailed answers |

Diagrams (all in [../diagrams/](../diagrams/)):

| Diagram | Used in |
|---|---|
| [virtualization-stack-comparison.svg](../diagrams/virtualization-stack-comparison.svg) | virtualization-fundamentals |
| [kubevirt-object-chain.svg](../diagrams/kubevirt-object-chain.svg) | virtualization-fundamentals, architecture |
| [nested-virtualization-layers.svg](../diagrams/nested-virtualization-layers.svg) | virtualization-fundamentals |
| [kubevirt-architecture.svg](../diagrams/kubevirt-architecture.svg) | kubevirt-architecture |
| [cdi-import-flow.svg](../diagrams/cdi-import-flow.svg) | cdi-storage-model |
| [migration-flow.svg](../diagrams/migration-flow.svg) | migration-architecture |
| [migration-state-machine.svg](../diagrams/migration-state-machine.svg) | migration-state-machine |
| [controller-reconcile-loop.svg](../diagrams/controller-reconcile-loop.svg) | crd-controller-fundamentals |
| [networking-model.svg](../diagrams/networking-model.svg) | networking-model |
| [lab-resource-architecture.svg](../diagrams/lab-resource-architecture.svg) | architecture |
| [modernization-paths.svg](../diagrams/modernization-paths.svg) | modernization-model |

ADRs: [../adr/README.md](../adr/README.md).

## What was learned

1. **A KubeVirt VM is still a VM.** The guest OS, kernel and disk are the same as on ESXi. What changes is the manager: VMkernel/vCenter becomes Linux KVM + QEMU + libvirt, driven by Kubernetes objects.
2. **The chain and its owners:** `VirtualMachine` (you / controller) -> `VirtualMachineInstance` (virt-controller) -> virt-launcher Pod (scheduler + kubelet) -> libvirt domain (virt-handler) -> QEMU (libvirt) -> KVM (node kernel) -> guest OS (app team).
3. **CDI ends at the PVC.** CDI turns an image into a raw disk in a PVC. KubeVirt starts when a VM references that PVC.
4. **Format conversion is not guest conversion.** qemu-img changes the container format; virt-v2v also fixes drivers and boot config for virtio.
5. **Metadata is translated, disk data is copied, runtime state is only observed.**
6. **Cold first.** Warm migration depends on snapshots and CBT via the vSphere API, which the free ESXi edition does not support.
7. **A controller, not scripts,** is the right owner of a long, failure-prone, multi-step workflow. The state machine is a set of **declarative reconciliation checkpoints**, not a procedural script; idempotency, resumability and retry safety are the core design rules.
8. **A VMDK's file layout depends on its format and provisioning mode** (descriptor + extents, or monolithic sparse); discovery must read it, not assume it.
9. **Versions are a tuple, validated at deployment time.** "Latest at documentation time" is an observation, not a decision.
10. **Migration preserves the VM model; modernization removes it.**

## What was validated (in our lab)

Only facts we observed ourselves. Full list: [feasibility.md, "Proven in our lab"](feasibility.md#proven-in-our-lab).

| Item | How |
|---|---|
| Nested ESXi 8.0.3 build 24677879 runs on VMware Workstation | Read-only SSH (see [evidence-index.md](evidence-index.md)) |
| ESXi sees hardware virtualization (`HV Support: 3`) | Read-only SSH |
| VMFS-6 `migration-datastore` 199.8 GB / 198.3 GB free, no VMs | Read-only SSH |
| Static vmk0 192.168.50.11, SSH key auth, NTP in sync | Read-only SSH |

## What was confirmed from documentation (documented, NOT validated)

| Item | Source |
|---|---|
| KubeVirt v1.9 is built for Kubernetes 1.36 and supported on the previous two minors | KubeVirt release notes / support matrix |
| Kubernetes 1.34 EOL 2026-10-27; EKS standard support 1.34-1.36 | kubernetes.io, AWS docs |
| CDI v1.66.1 is the newest release; no official KubeVirt-to-CDI pairing statement found | CDI releases / API reference |
| AWS nested virtualization on supported non-bare-metal instances since 2026-02-16; KVM and Hyper-V; no additional cost | AWS EC2 user guide |
| Free ESXi: API unsupported / possibly read-only, no vCenter, 8 vCPU per VM | Broadcom KB + release notes |
| `virt-v2v -i vmx -it ssh` requirements (guest shut down, no snapshots, key auth) | virt-v2v-input-vmware(1) |
| MTV 2.11 architecture and warm-migration limits | Red Hat docs |

## What remains unvalidated

See [feasibility.md, "Not yet proven"](feasibility.md#not-yet-proven). Most important:

- A nested 64-bit L2 guest on our ESXi, and ESXi config persistence across a controlled reboot.
- KVM and `/dev/kvm` on an actual AWS target node.
- Whether EKS worker nodes (or a self-managed node) meet every KubeVirt host requirement.
- The runtime combination of CDI, KubeVirt and Kubernetes (the compatibility tuple).
- VMDK acquisition from this free ESXi host and virt-v2v conversion of the source.
- Target VM boot and end-to-end migration.

## Architecture

See [architecture.md](architecture.md). In one line: **local nested ESXi source -> SSH discovery and cold disk copy -> conversion -> S3 staging -> CDI DataVolume/PVC on a disposable Terraform-built AWS Kubernetes cluster -> KubeVirt VM -> validation -> containerized version of the same app.**

## Decisions

| Decision | Record |
|---|---|
| Local nested ESXi is the source | [ADR 001](../adr/001-local-esxi-migration-source.md) |
| AWS is the disposable target, Terraform only | [ADR 002](../adr/002-aws-disposable-target.md) |
| Cold before warm; no custom warm engine | [ADR 003](../adr/003-cold-before-warm.md) |
| Upstream KubeVirt + CDI is the destination; versions chosen as a validated compatibility tuple at deployment time | [ADR 004](../adr/004-kubevirt-vm-destination.md) |
| Custom controller + `VirtualMachineMigration` CR owns the declarative migration workflow (reconciliation checkpoints) | [ADR 005](../adr/005-custom-controller-vs-scripts.md) |

Deferred decisions:

- Where conversion runs: local helper Linux environment, AWS conversion helper, or another controlled Linux runtime ([feasibility section 6](feasibility.md#6-conversion-host-deferred-decision)).
- qemu-img-only vs virt-v2v conversion (test both).
- Kubernetes topology: EKS vs self-managed (both unvalidated, neither rejected).
- EC2 instance family, exact size, Region and AMI; nested-virtualization instance vs `*.metal`.
- The exact compatibility tuple (KubeVirt, Kubernetes, CDI).
- Source guest OS, version and sizing.
- Controller language / framework.
- Multus secondary networks (not needed for the first demo).
- Stage 1 scope and order.

## Stage 1 entry criteria

Stage 1 may begin only when **all** general criteria are met, plus the criteria for whichever track Stage 1 covers.

General (always required):

1. The user has reviewed Stage 0 (including this refinement) and explicitly approved starting Stage 1.
2. Stage 1 scope is written down: which track (source side, destination side, or both), what will be created, and what is out of scope.
3. The approved change boundary is explicit: which systems Stage 1 may modify (ESXi, AWS, Kubernetes). Anything not listed stays unchanged.
4. Deferred decisions needed by that scope are either made (recorded as an ADR) or explicitly kept out of scope.
5. Success criteria and evidence to capture are defined for each Stage 1 task, using the categories in [feasibility.md](feasibility.md).

Source-side track (creating `legacy-source-vm` on ESXi):

1. A controlled ESXi reboot has been approved, performed, and vmk0/route/DNS/hostname/NTP/datastore/SSH re-verified (N2).
2. Guest OS, version, ISO (with checksum) and sizing (at most 8 vCPU) are chosen.
3. The ISO upload location on `migration-datastore` and the VM's port group ("VM Network") are agreed.
4. The first Stage 1 check is a nested 64-bit guest boot (N1). If it fails, stop and report.

Destination-side track (any AWS or Kubernetes work):

1. AWS credentials are recovered from the Docker volume or re-issued, stored outside Git, and verified with a read-only call (F20).
2. Terraform is the only creation path; a `terraform destroy` plan and cost guardrails (tags, budget alert, session teardown) are defined.
3. A candidate compatibility tuple (KubeVirt, Kubernetes, CDI) is written down with its evidence, and the runtime validation gate G1-G7 is the acceptance test ([feasibility section 3](feasibility.md#3-compatibility-tuple-and-runtime-validation-gate)).
4. The first test node is scoped to the host-requirement checklist H1-H11 ([feasibility section 5](feasibility.md#5-eks-host-requirement-compatibility)), for whichever topology is tried first; EKS vs self-managed is decided from that evidence.
5. Instance family, size, Region and AMI for the test node are chosen and recorded (currently deferred).

Migration track (only after both sides exist):

1. The conversion host location is decided and recorded as an ADR.
2. The source VM exists, runs nginx, has no snapshots, and has a recorded baseline (page content, checksums).

## Official sources consulted

All checked on 2026-09-27.

KubeVirt:

- [KubeVirt user guide](https://kubevirt.io/user-guide/)
- [KubeVirt user guide: Architecture](https://kubevirt.io/user-guide/architecture/)
- [KubeVirt user guide: Installation](https://kubevirt.io/user-guide/cluster_admin/installation/)
- [KubeVirt user guide: Run Strategies](https://kubevirt.io/user-guide/compute/run_strategies/)
- [KubeVirt user guide: Interfaces and Networks](https://kubevirt.io/user-guide/network/interfaces_and_networks/)
- [KubeVirt user guide: Containerized Data Importer](https://kubevirt.io/user-guide/storage/containerized_data_importer/)
- [KubeVirt user guide: Release notes](https://kubevirt.io/user-guide/release_notes/)
- [KubeVirt to Kubernetes support matrix](https://github.com/kubevirt/sig-release/blob/main/releases/k8s-support-matrix.md)
- [kubevirt/kubevirt: Kubernetes compatibility](https://github.com/kubevirt/kubevirt/blob/main/docs/kubernetes-compatibility.md), [components](https://github.com/kubevirt/kubevirt/blob/main/docs/components.md), [releases](https://github.com/kubevirt/kubevirt/releases)

CDI:

- [CDI API reference](https://kubevirt.io/cdi-api-reference/)
- [CDI repository](https://github.com/kubevirt/containerized-data-importer), [releases](https://github.com/kubevirt/containerized-data-importer/releases)
- [DataVolumes](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md), [Supported operations](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/supported_operations.md), [Upload](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/upload.md), [Scratch space](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/scratch-space.md)

Kubernetes:

- [Releases](https://kubernetes.io/releases/)
- [Custom resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/), [CRDs](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
- [Controllers](https://kubernetes.io/docs/concepts/architecture/controller/), [Operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [Finalizers](https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/), [Owners and dependents](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/)
- [API conventions](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md)
- [Cluster networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)

Red Hat MTV / Forklift:

- [MTV 2.11: Planning your migration to Red Hat OpenShift Virtualization](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.11/html-single/planning_your_migration_to_red_hat_openshift_virtualization/index)
- [MTV 2.11: Migrating your virtual machines (CLI example with Provider, NetworkMap, StorageMap, Plan, Migration)](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.11/html/migrating_your_virtual_machines_to_red_hat_openshift_virtualization/assembly_migrating-from-rhv_mtv)
- [Forklift (upstream)](https://github.com/kubev2v/forklift)

libvirt, QEMU, KVM, libguestfs:

- [libvirt domain XML](https://libvirt.org/formatdomain.html), [libvirt QEMU driver](https://libvirt.org/drvqemu.html)
- [QEMU system emulation](https://www.qemu.org/docs/master/system/index.html), [QEMU disk images](https://www.qemu.org/docs/master/system/images.html), [qemu-img](https://www.qemu.org/docs/master/tools/qemu-img.html)
- [Linux KVM API](https://docs.kernel.org/virt/kvm/api.html)
- [libguestfs](https://libguestfs.org/), [virt-v2v(1)](https://libguestfs.org/virt-v2v.1.html), [virt-v2v-input-vmware(1)](https://libguestfs.org/virt-v2v-input-vmware.1.html)

VMware / Broadcom:

- [Broadcom KB 399823: ESXi 8.0 Update 3e now available as a Free Hypervisor](https://knowledge.broadcom.com/external/article/399823)
- [VMware ESXi 8.0 Update 3e release notes](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/release-notes/esxi-update-and-patch-release-notes/vsphere-esxi-80u3e-release-notes.html)

AWS:

- [Use nested virtualization to run hypervisors in Amazon EC2 instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html)
- [What's New: nested virtualization on virtual EC2 instances (2026-02-16)](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual/)
- [LaunchTemplateCpuOptionsRequest](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_LaunchTemplateCpuOptionsRequest.html)
- [Amazon EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html), [Amazon EBS CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)

Multus:

- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni)
