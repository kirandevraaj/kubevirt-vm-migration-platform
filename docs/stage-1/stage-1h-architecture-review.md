# Stage 1H architecture review: is the KubeVirt target design a sound foundation for Stage 1I?

| Field | Value |
|---|---|
| Date | 2026-09-30 |
| Type | Review only. No infrastructure, cluster, conversion, boot or migration was performed |
| Subject | The Stage 1H design: [stage-1h-kubevirt-target-feasibility.md](stage-1h-kubevirt-target-feasibility.md) and ADRs [007](../adr/007-kubevirt-target-platform.md), [008](../adr/008-kubevirt-network-model.md), [009](../adr/009-kubevirt-storage-model.md), [010](../adr/010-migration-network-remediation.md) |
| Repository state reviewed | `main` at `a9511b6` (Stage 1H itself is commit `43f3b70`) |
| Upstream sources retrieved | 2026-09-30 (section 2) |
| Result | **REQUIRES ARCHITECTURAL CORRECTIONS** (section 17). The core architecture is coherent; eight bounded corrections are needed before Stage 1I is proposed for approval |

Evidence labels used throughout:

- **PROJECT-DERIVED FACT**: observed or recorded in Stages 0 to 1H of this repository.
- **CURRENT UPSTREAM DOCUMENTATION**: read from an official upstream source on 2026-09-30.
- **ENGINEERING INFERENCE**: reasoned from the two above, not observed.
- **PROPOSED DESIGN**: a recommendation of this review, not yet accepted by the user.

This review does not change the Stage 1H record or its ADRs. Where it finds an error, it names it and proposes a correction for the user to approve.

## 1. Review Objective

The question: **is the current Stage 1H KubeVirt target design technically coherent and sufficiently well-defined to become the foundation for Stage 1I?**

The review traces the design back to what Stages 1A to 1G actually proved, rather than accepting the Stage 1H record at face value. It checks:

- versions against upstream on 2026-09-30;
- the KubeVirt object and component chain;
- the storage path from VMDK to a running guest disk;
- the network path, both VMware and KubeVirt;
- where guest remediation belongs;
- the workflow and the future controller;
- failure handling, security and completeness.

Out of scope, by instruction:

- defining or starting Stage 1I;
- new stage numbers;
- Terraform, Kubernetes manifests, KubeVirt YAML, controller code or AWS resources;
- rewriting the Stage 1H design.

## 2. Evidence Reviewed

### Project records (PROJECT-DERIVED FACT)

| Record | What was taken from it |
|---|---|
| [Stage 1H record](stage-1h-kubevirt-target-feasibility.md) | The full design: versions, host requirements, network, remediation, storage, CDI workflow, guest agent, validation, AWS model, security, unknowns U1 to U15, risks, entry criteria, gates H1 to H10 |
| ADRs [007](../adr/007-kubevirt-target-platform.md), [008](../adr/008-kubevirt-network-model.md), [009](../adr/009-kubevirt-storage-model.md), [010](../adr/010-migration-network-remediation.md) | Platform, network, storage and remediation decisions |
| ADRs [002](../adr/002-aws-disposable-target.md), [003](../adr/003-cold-before-warm.md), [005](../adr/005-custom-controller-vs-scripts.md), [006](../adr/006-dedicated-conversion-host.md) | Disposable AWS with Terraform only, cold before warm, custom controller, dedicated conversion host with one-way data flow |
| [Stage 1G record](stage-1g-controlled-conversion.md) | The two conversion paths, the five virt-v2v first-boot scripts, the netplan failure and fix, the test-boot conditions, preserved identity |
| [Stage 1E record](stage-1e-cold-acquisition.md) | One graceful shutdown, a cold copy, then power-on: the golden artifact is a point-in-time copy |
| [Stage 1C](stage-1c-migration-source.md), [Stage 1F](stage-1f-conversion-host.md), [Stage 1 README](README.md) | The source baseline and validation page, the conversion host and working copy, stage status |
| Stage 0 [networking-model](../stage-0/networking-model.md), [cdi-storage-model](../stage-0/cdi-storage-model.md), [kubevirt-architecture](../stage-0/kubevirt-architecture.md), [migration-state-machine](../stage-0/migration-state-machine.md), [migration-architecture](../stage-0/migration-architecture.md), [architecture](../stage-0/architecture.md), [feasibility](../stage-0/feasibility.md) | The conceptual models, the `VirtualMachineMigration` sketch, the state machine, the runtime gate G1 to G7, the lab-to-AWS connectivity assumption |
| [Project status and next steps](../project-context/project-status-and-next-steps.md) | The consolidated status as of the dashboard commit |

### Upstream sources (CURRENT UPSTREAM DOCUMENTATION, retrieved 2026-09-30)

| ID | Source | Used for |
|---|---|---|
| S1 | [KubeVirt releases](https://github.com/kubevirt/kubevirt/releases) (GitHub API) | v1.9.0 published 2026-07-30 is the newest stable; v1.10.0-alpha.0 (2026-09-04) is a pre-release; no v1.9.x patch |
| S2 | [KubeVirt stable.txt](https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt) | `v1.9.0` |
| S3 | [KubeVirt to Kubernetes support matrix](https://github.com/kubevirt/sig-release/blob/main/releases/k8s-support-matrix.md) | KubeVirt 1.9 supports Kubernetes 1.36, 1.35, 1.34 |
| S4 | [Kubernetes releases](https://kubernetes.io/releases/) and [stable-1.36.txt](https://dl.k8s.io/release/stable-1.36.txt) | 1.36.5 (2026-09-15), EOL 2027-06-28; 1.37.1 newest; 1.34 EOL 2026-10-27 |
| S5 | [CDI releases](https://github.com/kubevirt/containerized-data-importer/releases) | v1.66.1 (2026-09-06) is the newest |
| S6 | [CDI scratch space](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/scratch-space.md) | Upload always uses scratch; scratch is Filesystem, RWO, the same size as the DataVolume, even for Block DataVolumes |
| S7 | [CDI upload](https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/upload.md) and [CDI config](https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/cdi-config.md) | Upload tokens are valid for 5 minutes; scratch storage class defaults to the cluster default class, else the DataVolume's class |
| S8 | [CRI-O releases](https://github.com/cri-o/cri-o/releases) | v1.36.6 (2026-09-21) newest 1.36 patch |
| S9 | [flannel releases](https://github.com/flannel-io/flannel/releases) | v0.28.9 (2026-08-07) newest |
| S10 | [AWS EBS CSI driver releases](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/releases) and [parameters](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/v1.66.0/docs/parameters.md) | v1.66.0 (2026-09-10) newest; StorageClass `encrypted` defaults to `false` |
| S11 | [AmazonEBSCSIDriverPolicyV2](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEBSCSIDriverPolicyV2.html) | Create/modify/delete limited to volumes tagged `ebs.csi.aws.com/cluster = true`; attach/detach to any instance |
| S12 | [EC2 nested virtualization](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html) | M8i supported; more Intel families added 2026-06-18; KVM and Hyper-V as L1 hypervisors; opt-in per instance |
| S13 | [CentOS AWS images](https://www.centos.org/download/aws-images/) and [CentOS versions](https://www.centos.org/cl-vs-cs/) | CentOS Stream 9 ap-south-1 x86_64 is still `ami-0e7930d02f47291cb`; EOL 2027-05-31 |
| S14 | [KubeVirt interfaces and networks](https://kubevirt.io/user-guide/network/interfaces_and_networks/) | Masquerade: nftables NAT, guest uses DHCP, `ports` evaluated only by masquerade and passt, masquerade only on the pod network, `vmNetworkCIDR`, MTU via DHCP and libvirt |
| S15 | [KubeVirt v1.9.0 channels.go](https://github.com/kubevirt/kubevirt/blob/v1.9.0/pkg/virt-launcher/virtwrap/converter/compute/channels.go) | The guest-agent channel `org.qemu.guest_agent.0` is added to every domain unconditionally |
| S16 | [KubeVirt v1.9.0 components](https://github.com/kubevirt/kubevirt/blob/v1.9.0/docs/components.md) | virt-handler passes the VMI to virt-launcher; virt-launcher uses its own libvirtd to start the domain |
| S17 | [KubeVirt run strategies](https://kubevirt.io/user-guide/compute/run_strategies/) | Always, RerunOnFailure, Once, Manual, Halted |
| S18 | [Kubernetes Service, type NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport) | Default range 30000-32767; static band 30000-30085; the port is proxied on every node; iptables mode listens on all node IPs |

## 3. Current Proposed Architecture

Summary of Stage 1H as written (PROJECT-DERIVED FACT):

- **Platform (ADR 007).** One EC2 `m8i.xlarge` with nested virtualization in ap-south-1:
  - CentOS Stream 9, CRI-O 1.36, single-node kubeadm Kubernetes 1.36, flannel;
  - the EBS CSI driver, KubeVirt v1.9.0 and CDI v1.66.1 (the CDI pairing is a candidate until the runtime gate).
  - Built and destroyed with Terraform (ADR 002).
- **Network (ADR 008).**
  - Pod network with the masquerade binding, one virtio NIC, no Multus.
  - The guest gets 10.0.2.2/24 by DHCP. 192.168.50.31 is not preserved.
  - A NodePort Service on 30080, reachable only from the operator's /32, is the external check.
- **Storage (ADR 009).**
  - EBS CSI gp3 StorageClass (WaitForFirstConsumer, reclaimPolicy Delete).
  - One 40 GiB Block-mode RWO PVC, filled by a standalone CDI upload DataVolume from a qcow2 prepared on `conversion-host-01`.
  - Raw at rest.
- **Guest remediation (ADR 010).**
  - Offline, on a new copy of the virt-v2v output, replace `/etc/netplan/50-cloud-init.yaml` with one ethernet matched by driver `virtio_net`, DHCPv4 on.
  - Also offline: install qemu-guest-agent from pre-downloaded `.deb` files, and remove the virt-v2v first-boot scripts.
- **VM.** A `VirtualMachine`:
  - references the PVC on bus virtio;
  - EFI with Secure Boot off;
  - 2 vCPU and 4096 Mi (from the source `.vmx`);
  - `runStrategy: Manual`.
- **Validation.** The 12 checks from Stage 1C, adapted, with page sha256 `b9826e18...0046` and marker `p15-stage1c-source-v1`.
- **Deferred.** Among others: the qcow2 transfer route, EKS, Multus, IP preservation, DNS names, live migration, snapshots, the controller, warm migration, production design.

## 4. End-to-End Architecture Trace

Each hop in order: what exists there, who acts, and how much is proven.

| # | Hop | What exists | Who acts | Status | Basis |
|---|---|---|---|---|---|
| 1 | Source workload | `legacy-source-vm` on nested ESXi 8.0.3: Ubuntu 24.04.5, UEFI, 2 vCPU, 4096 MB, 40 GiB PVSCSI disk, VMXNET3 `ens192`, static 192.168.50.31, nginx | VMware ESXi | Running reference, never modified | PROJECT-DERIVED FACT (1C, 1D) |
| 2 | Cold acquisition | One graceful shutdown, `scp` of descriptor and flat extent, power-on | Human, with approval | Done once, on 1E's date | PROJECT-DERIVED FACT (1E) |
| 3 | Golden artifact | VMDK descriptor and 40 GiB flat extent on Windows, ReadOnly, flat sha256 `72ca45c7...c9e7` | None (at rest) | Protected, re-verified | PROJECT-DERIVED FACT (1E, 1G) |
| 4 | Working copy | Hash-verified copy on `conversion-host-01`, mode 0444 and immutable | None (at rest) | Protected | PROJECT-DERIVED FACT (1F) |
| 5 | Guest-aware conversion | virt-v2v qcow2 output, sha256 `94bc1cd6...91c6`: open-vm-tools purged, initramfs rebuilt, first-boot scripts added; netplan unchanged | virt-v2v on the conversion host | Done | PROJECT-DERIVED FACT (1G) |
| 6 | Image preparation | A new copy with the ADR 010 netplan file, the offline guest agent and the first-boot scripts removed | libguestfs tools on the conversion host | **Designed, never produced, never booted** | PROJECT-DERIVED FACT (1H) |
| 7 | Transfer | The prepared qcow2 (about 2.7 GiB) copied to the EC2 node over SSH, sha256 compared at both ends | Human | **Designed; route deferred** | PROJECT-DERIVED FACT (1H section 18) |
| 8 | Import | CDI upload DataVolume: upload proxy through `port-forward`, scratch volume, `qemu-img` writes raw onto the Block PVC | CDI | Designed; U10, U12 open | PROJECT-DERIVED FACT; CURRENT UPSTREAM DOCUMENTATION (S6) |
| 9 | Persistent disk | 40 GiB gp3 EBS volume behind a Block PVC | EBS CSI driver | Designed; U11 open | PROJECT-DERIVED FACT |
| 10 | VM definition | `VirtualMachine` object referencing the PVC | Human (kubectl) | Designed | PROJECT-DERIVED FACT |
| 11 | Runtime | On start: virt-controller creates the VMI and the virt-launcher pod; virt-handler hands the VMI to virt-launcher; libvirtd in the pod starts QEMU on `/dev/kvm` | KubeVirt | Designed; U1, U2, U6 open | CURRENT UPSTREAM DOCUMENTATION (S16) |
| 12 | Guest | Ubuntu boots on virtio-blk, netplan matches `virtio_net`, DHCP 10.0.2.2, nginx | Guest OS | **Only proven as temporary QEMU test boots in 1G**, with a static test address 10.0.2.15 and without the agent | PROJECT-DERIVED FACT (1G) |
| 13 | Validation | 12 checks; HTTP from the operator's /32 to node-public-IP:30080 | Human | Designed | PROJECT-DERIVED FACT (1H section 21) |
| 14 | Teardown | Evidence capture, then destroy | Human, Terraform | **Designed, with an error** (section 7) | PROJECT-DERIVED FACT; ENGINEERING INFERENCE |

Findings from the trace:

1. **The first migration is a point-in-time copy, not a cutover.**
   - Facts: the golden artifact reflects the source at the moment of the Stage 1E shutdown, and the source has run (and written to its disk) since then (PROJECT-DERIVED FACT).
   - Consequence: the migrated VM will contain the source as of 1E, not as of the migration day. For this static page that changes nothing, which is why the design works (ENGINEERING INFERENCE). But 1H never states it.
   - Stage 1H should say it explicitly, because it defines what "migrated" means for this first run (issue I-08).
2. **Hop 6 is the least-proven link that the design relies on.** The image that will actually be imported combines three guest changes that were never booted together:
   - netplan with DHCP (1G proved only a static address);
   - the agent installed offline;
   - the first-boot scripts removed.

   Stage 1H sends that image straight to AWS (issue I-06).
3. **Hops 2 to 5 run in the lab; hops 7 to 14 run in AWS.** Nothing in AWS can reach into the lab (section 8). That shapes the transfer (hop 7) and any future controller (section 11).
4. **The four "VMs" in this chain are different things, and the design keeps them apart correctly** (PROJECT-DERIVED FACT):
   - the source VMware workload (hop 1);
   - disk artifacts (hops 3 to 9);
   - the temporary QEMU/KVM test guests of 1G, which were deleted;
   - the future persistent KubeVirt VM (hops 10 to 12).

   None of the 1G test boots was a migrated KubeVirt VM.

## 5. Version / Compatibility Review

Every version assumption in Stage 1H was re-checked on 2026-09-30. **No version change is proposed.**

| Component | Stage 1H assumption (2026-09-28) | Upstream on 2026-09-30 | Result | Basis |
|---|---|---|---|---|
| KubeVirt | v1.9.0, the current stable | v1.9.0 still newest stable and in stable.txt; only v1.10.0-alpha.0 is newer (pre-release); no v1.9.1 | Unchanged | CURRENT UPSTREAM DOCUMENTATION (S1, S2) |
| KubeVirt Kubernetes range | 1.34 to 1.36 | Matrix unchanged: 1.9 supports 1.36, 1.35, 1.34 | Unchanged | S3 |
| Kubernetes | 1.36, patch pinned at build (1.36.5) | stable-1.36 = v1.36.5 (2026-09-15), EOL 2027-06-28. 1.37.1 is newest but outside KubeVirt 1.9's range | Unchanged; 1.36 remains the right minor | S3, S4 |
| CDI | v1.66.1, candidate until runtime | v1.66.1 still newest; there is still no published KubeVirt-to-CDI matrix | Unchanged; remains a candidate (U12) | S5 |
| CRI-O | 1.36 (v1.36.6) | v1.36.6 still newest 1.36 patch (2026-09-21); 1.37.1 exists, but CRI-O follows the Kubernetes minor | Unchanged | S8 |
| flannel | v0.28.9 | Unchanged | Unchanged | S9 |
| EBS CSI driver | v1.66.0; `AmazonEBSCSIDriverPolicyV2` | Unchanged; policy text confirms tag scoping | Unchanged | S10, S11 |
| CentOS Stream 9 | EOL 2027-05-31; AMI `ami-0e7930d02f47291cb` in ap-south-1 | Both unchanged | Unchanged | S13 |
| EC2 nested virtualization | M8i, all commercial Regions | Unchanged for M8i; AWS has since added more Intel families (such as M7i) | Unchanged | S12 |
| virt-launcher userland | libvirt 11.10.0-12.el9, QEMU 10.1.0-20.el9 | Not re-checked (needs the image manifest) | Carried from 1H | PROJECT-DERIVED FACT |
| gp3 baseline | 3000 IOPS, 125 MiB/s | Not re-fetched | Carried from 1H | PROJECT-DERIVED FACT |

Compatibility across the stack:

- **Kubernetes, CRI-O and KubeVirt: VALID.**
  - The tuple Kubernetes 1.36 + CRI-O 1.36 + CentOS Stream 9 + flannel + kubeadm is the one KubeVirt's own CI lane uses (PROJECT-DERIVED FACT, 1H).
  - Running the CentOS Stream 9 host kernel under the CentOS Stream 9 virt-launcher userland follows KubeVirt's recommendation (PROJECT-DERIVED FACT, 1H).
- **KubeVirt and CDI: NEEDS CLARIFICATION, correctly labelled.**
  - Neither project publishes a pairing matrix.
  - KubeVirt v1.9.0 builds against the CDI v1.64 API, and the DataVolume API it uses (`cdi.kubevirt.io/v1beta1`) has not changed version (PROJECT-DERIVED FACT, 1H).
  - A newer CDI with the same API version is therefore likely to work (ENGINEERING INFERENCE). The runtime gate G1 to G7 remains the proof.
- **Lifecycle dates (ENGINEERING INFERENCE).**
  - CentOS Stream 9 reaches EOL on 2027-05-31, four weeks before Kubernetes 1.36 (2027-06-28).
  - That does not matter for a disposable, rebuilt-per-session lab.
  - It would matter for anything long-lived, so it belongs with the deferred production design.
- **Kubernetes 1.34 reaches EOL on 2026-10-27** (S4). 1H did not choose 1.34, so nothing changes.
- **Uncertainty.**
  - The two values carried from 1H (the virt-launcher package versions and the gp3 baseline) were not re-fetched, and are labelled as such.
  - U1 (whether `m8i.xlarge` reports `nested-virtualization` in ap-south-1) is still open. The documentation says yes; only a `describe-instance-types` call can confirm it.

## 6. KubeVirt Architecture Review

### The chain, as the design depends on it

Kubernetes -> KubeVirt operator and components -> `VirtualMachine` -> `VirtualMachineInstance` -> virt-launcher pod -> libvirt -> QEMU -> KVM -> guest.

| Term | What it is here | Basis |
|---|---|---|
| CRD | A CustomResourceDefinition teaches the API server a new object type. KubeVirt adds `VirtualMachine`, `VirtualMachineInstance` and others; CDI adds `DataVolume` and others. A CRD alone does nothing | CURRENT UPSTREAM DOCUMENTATION (Kubernetes concepts); PROJECT-DERIVED FACT ([Stage 0](../stage-0/crd-controller-fundamentals.md)) |
| Controller | A process that watches objects and works to make the observed state match the declared state (reconciliation). virt-controller reconciles VMs and VMIs; CDI's controller reconciles DataVolumes | PROJECT-DERIVED FACT ([kubevirt-architecture](../stage-0/kubevirt-architecture.md)) |
| Operator | A controller whose job is to install and upgrade other software. `virt-operator` installs and upgrades KubeVirt from the `KubeVirt` CR; `cdi-operator` does the same for CDI from the `CDI` CR. Operators do not run VMs | PROJECT-DERIVED FACT |
| VirtualMachine (VM) | The persistent, declarative object: "this VM should exist, with this spec and this run strategy". It survives stop and start | PROJECT-DERIVED FACT |
| VirtualMachineInstance (VMI) | One running instance. virt-controller creates it from the VM when the run strategy says run, and deletes it on stop | PROJECT-DERIVED FACT |
| virt-launcher | One pod per VMI. It provides the cgroups and namespaces, and runs a private libvirtd that starts QEMU | CURRENT UPSTREAM DOCUMENTATION (S16) |
| virt-handler | The privileged DaemonSet on each node. It sees VMIs scheduled to its node and passes the VMI to virt-launcher | CURRENT UPSTREAM DOCUMENTATION (S16) |
| libvirt | Inside virt-launcher: defines and manages the QEMU domain generated from the VMI | CURRENT UPSTREAM DOCUMENTATION (S15, S16) |
| QEMU | The user-space process that emulates the machine: virtio-blk, virtio-net, firmware | PROJECT-DERIVED FACT (1B, 1G) |
| KVM | The kernel module exposed as `/dev/kvm` that runs guest CPU instructions in hardware. On EC2 this needs nested virtualization | PROJECT-DERIVED FACT; S12 |
| CDI | A separate project (its own operator, controller, upload proxy and importer/upload pods) that fills PVCs with disk images. It does not run VMs | PROJECT-DERIVED FACT ([cdi-storage-model](../stage-0/cdi-storage-model.md)) |
| DataVolume | CDI's object: "a PVC, plus how to fill it". Its phase reports import progress | PROJECT-DERIVED FACT |
| PVC | The Kubernetes storage claim. Here it is bound to one EBS volume by the EBS CSI driver. KubeVirt only sees a PVC | PROJECT-DERIVED FACT |

### Who creates, runs and reconciles

- **Creates the VM:** a human (later, the migration controller) creates the `VirtualMachine` object.
- **Starts the VM:** virt-controller reacts to the run strategy (for `Manual`, an explicit `virtctl start`) by creating the VMI and the virt-launcher pod. The scheduler places the pod. virt-handler hands the VMI to virt-launcher, whose libvirtd starts QEMU (S16).
- **Reconciles:** virt-controller reconciles VM to VMI to pod, and CDI reconciles DataVolume to PVC. The migration controller (future) would reconcile only the migration workflow. It would create KubeVirt and CDI objects and read their status; it would never run VMs or move packets itself.

### Findings

- **VALID.** Stage 1H uses operator, controller, VM, VMI, CDI and DataVolume correctly, and always creates a `VirtualMachine`, never a bare VMI, as Stage 0 intended.
- **Minor imprecision, outside 1H.**
  - [kubevirt-architecture](../stage-0/kubevirt-architecture.md) (lifecycle list, virt-handler step) says virt-handler "converts the VMI into libvirt domain XML".
  - Upstream, virt-handler passes the VMI to virt-launcher, and the conversion to domain XML lives in virt-launcher's code (S15, S16).
  - This is a historical Stage 0 learning note and does not affect the design. It should be corrected only if Stage 0 is revised.
- **Minor imprecision, outside 1H.** The project-status dashboard diagram labels KubeVirt a "VM operator". More precisely, KubeVirt is a set of CRDs and controllers, installed by `virt-operator`. This is cosmetic.
- **Guest-agent channel: now documented upstream.**
  - 1H marked "the channel is added automatically" as INFERRED.
  - The KubeVirt v1.9.0 source adds `org.qemu.guest_agent.0` to every domain unconditionally (S15).
- **VM details left at KubeVirt defaults (NEEDS CLARIFICATION, low risk).**
  - Unstated: machine type, CPU model under nested virtualization, and the EFI variable store (not persistent by default).
  - A non-persistent varstore means every boot takes the ESP fallback path. That is exactly how 1G booted, with a fresh varstore and the fallback loader, so the default is the tested condition (PROJECT-DERIVED FACT, 1G; ENGINEERING INFERENCE for KubeVirt).
  - Stage 1I should record the defaults it actually gets, rather than pin new values.
- **Capacity: VALID (ENGINEERING INFERENCE).**
  - 16 GiB on the node, minus the control plane, CRI-O, KubeVirt, CDI and the virt-launcher overhead (a few hundred MiB), leaves room for a 4096 Mi guest.
  - Four node vCPUs cover 2 guest vCPUs plus the system pods.
  - The margin should be observed at runtime, not assumed.

## 7. Storage Review

### Trace

| Step | Representation | What changes | Basis |
|---|---|---|---|
| Source | VMFS VMDK: descriptor + 40 GiB flat extent, PVSCSI `sda` | - | PROJECT-DERIVED FACT |
| Cold copy (1E) | The same two files on Windows | Nothing: byte copy, hash-verified | PROJECT-DERIVED FACT |
| Working copy (1F) | The same files on `conversion-host-01`, immutable | Nothing | PROJECT-DERIVED FACT |
| virt-v2v (1G) | qcow2, about 2.7 GiB allocated, 40 GiB virtual | Container VMDK -> qcow2 **and** guest changes (tools purged, initramfs, first boot) | PROJECT-DERIVED FACT |
| Preparation (future) | New qcow2 | Guest changes: netplan, agent, first-boot removal | PROJECT-DERIVED FACT (design) |
| Transfer | Same qcow2 bytes | Nothing; sha256 must match | PROJECT-DERIVED FACT (design) |
| CDI upload | qcow2 held on a Filesystem scratch PVC, then converted | Container qcow2 -> raw; scratch deleted | CURRENT UPSTREAM DOCUMENTATION (S6) |
| PVC at rest | Raw guest disk bytes written straight onto the 40 GiB EBS block device; no image file, no filesystem underneath | - | PROJECT-DERIVED FACT; S6 |
| KubeVirt disk | Block PVC attached to QEMU as a virtio-blk disk (`vda` in the guest) | - | PROJECT-DERIVED FACT |

**The guest filesystems are never converted.** The GPT, ESP (vfat) and root filesystem (ext4, same UUIDs) travel as the same bytes inside a different container. Only three things change:

- the container format: VMDK, then qcow2, then raw;
- the files that virt-v2v changed on purpose;
- the files that the preparation step will change on purpose.

(PROJECT-DERIVED FACT, 1G: filesystem UUIDs, fstab and GRUB configuration unchanged.)

### Checks

- **Block vs Filesystem: VALID.**
  - Block mode gives QEMU the device directly, with no `disk.img` file on a filesystem (PROJECT-DERIVED FACT, 1H).
  - CDI requires CRI-O's `device_ownership_from_security_context = true` for block PVCs (PROJECT-DERIVED FACT, 1H).
- **CDI import mechanics: VALID.**
  - An upload always goes through scratch space.
  - Scratch is always requested as Filesystem, RWO, the same size as the DataVolume, even when the target is Block.
  - The scratch storage class is the cluster default class, otherwise the DataVolume's class (CURRENT UPSTREAM DOCUMENTATION, S6, S7).
  - With the gp3 class as the default or the only class, a roughly 40 GiB gp3 Filesystem scratch volume appears and is removed. That matches 1H.
- **40 GiB sizing: VALID.**
  - Equal to the source's virtual size (42,949,672,960 bytes), never smaller.
  - An EBS volume of 40 GiB is exactly that size, so the raw image fills the device exactly (ENGINEERING INFERENCE).
- **gp3 assumptions: VALID for a cold migration.**
  - The baseline 3000 IOPS and 125 MiB/s is independent of size.
  - Worst case, if the converter wrote all 40 GiB including zeros, that is about 5.5 minutes at 125 MiB/s; if it skips unallocated regions, much less (ENGINEERING INFERENCE; the exact write pattern is not documented here).
- **"Raw at rest": NEEDS CLARIFICATION (wording only).**
  - On a Block PVC there is no raw file. The guest disk bytes sit directly on the EBS device.
  - EBS bills the provisioned 40 GiB whatever the guest uses; the thinness of qcow2 exists only in transit (ENGINEERING INFERENCE).
- **Standalone qcow2: NEEDS CLARIFICATION.**
  - The prepared image must be self-contained, with no backing file (`qemu-img info` shows none). An overlay created during preparation would upload only its own clusters (ENGINEERING INFERENCE).
- **Import verification: NEEDS CLARIFICATION.**
  - DataVolume `Succeeded` proves CDI finished, not that the right image was imported.
  - Proof comes from two places: the sha256 of the uploaded file against the preparation record, and the guest-level checks (filesystem UUIDs, netplan content, page hash).
  - Stage 1H should state this explicitly (ENGINEERING INFERENCE).

### Error found: teardown and "deleted with the cluster"

**NEEDS CHANGE.**

- **What the documents say.** 1H section 11 says the teardown is "destroyed with the Terraform state", and section 23 and ADR 009 say the disk "is deleted with the cluster (`reclaimPolicy: Delete`)".
- **Why that is wrong for these volumes.**
  - The 40 GiB VM volume and the scratch volume are created dynamically by the EBS CSI driver, so Terraform does not know about them (ENGINEERING INFERENCE).
  - `reclaimPolicy: Delete` acts only when the PVC is deleted while the CSI controller is still running.
- **Consequence.**
  - If Terraform terminates the instance first, the volumes detach and remain as billed, `available` volumes. They hold a copy of the guest disk, including its SSH host private keys.
  - EBS volumes are not VPC resources, so nothing blocks the destroy: it completes and the volumes are silently left behind (ENGINEERING INFERENCE).
- **Ready-made handle for a check.** Volumes created by the driver carry the tag `ebs.csi.aws.com/cluster = true`, which is also what the IAM policy scopes to (CURRENT UPSTREAM DOCUMENTATION, S11).
- **Required correction:** see R1 in section 15.

### Missing lifecycle steps

- **Preparation record: NEEDS CLARIFICATION.**
  - A record that ties the prepared qcow2 to its inputs: the virt-v2v output hash, the netplan file hash, the `.deb` names, versions and hashes, and the removed first-boot files.
  - Today only the final sha256 is planned.
- **Pre-transfer boot test: NEEDS CHANGE.** See I-06.
- **Deleting the qcow2 from the node root volume after import: NOT YET DEFINED.**
- **Confirming the scratch PVC was removed: NOT YET DEFINED.**
- **Evidence capture before teardown: NOT YET DEFINED.** The 12 check results, VMI status and events.
- **Orderly deletion and an orphan-volume check: NEEDS CHANGE.** See R1.
- **Encryption at rest: NOT YET DEFINED.**
  - The EBS CSI `encrypted` parameter defaults to `false` (S10), and the root volume encryption is not stated either.
  - See R7.
- **Snapshots or backups:** correctly DEFERRED. The authoritative copies remain the golden VMDK and the prepared qcow2 in the lab.

## 8. Network Review

### Where the NIC exists, then and now

**VMware (PROJECT-DERIVED FACT, 1C, 1D, 1G):**

1. ESXi emulates a VMXNET3 device attached to a port group on vSwitch0.
2. vSwitch0 has an uplink (vmnic0) that is Workstation's VMnet8 NAT network.
3. The guest's `vmxnet3` driver names the device `ens192` (from its PCI slot).
4. netplan matches `ens192` by name and sets static 192.168.50.31/24, gateway and DNS 192.168.50.2.

**KubeVirt (CURRENT UPSTREAM DOCUMENTATION, S14; ENGINEERING INFERENCE for the device-level detail):**

1. The EC2 node has an ENI with a VPC private address. The public IPv4 exists only in the internet gateway's 1:1 NAT; the node never sees it.
2. flannel gives the virt-launcher pod an address from the pod network CIDR, on a veth pair.
3. Inside the pod's network namespace, the masquerade binding creates:
   - a bridge and a tap device;
   - a gateway address 10.0.2.1;
   - a small DHCP server;
   - nftables rules.
4. QEMU presents a **virtio-net** device backed by that tap. This is where VirtIO is presented: at the QEMU device, inside the pod.
5. The guest's `virtio_net` driver names the interface from its PCI position: `enp0s3` under plain QEMU in 1G. Under KubeVirt's q35 layout it is likely different. The ADR 010 driver match makes the name irrelevant.
6. The guest asks for DHCP and gets 10.0.2.2/24, gateway 10.0.2.1, the pod's resolver and search domains, and the MTU (S14; its IPv6-only note, which says that without the IPv4 DHCP server the VM gets no search domains, implies that the IPv4 server provides them).

**What each party sees:**

| Party | Address it sees for itself | Basis |
|---|---|---|
| Guest | 10.0.2.2 only. It never sees the pod IP, node IP or public IP | CURRENT UPSTREAM DOCUMENTATION (S14) |
| virt-launcher pod | Its pod IP (flannel range); cluster workloads reach the VM through it | S14 |
| Node | Its VPC private IP | ENGINEERING INFERENCE |
| Internet / operator | The node's public IPv4 | ENGINEERING INFERENCE |

**Masquerade** means NAT inside the virt-launcher pod:

- outbound, source NAT from 10.0.2.2 to the pod IP;
- inbound, destination NAT from pod-IP:port to 10.0.2.2:port, for the ports declared in the interface's `ports` list, which only masquerade and passt evaluate (S14).

Outbound traffic is NATed twice more: by flannel's masquerade to the node IP, then by the internet gateway to the public IPv4 (PROJECT-DERIVED FACT, 1H diagram).

### Service and NodePort

- **What the Service does.**
  - It selects the virt-launcher pod by labels, which KubeVirt propagates from the VM template to the pod.
  - It gives a stable ClusterIP.
  - As type NodePort, it makes every node proxy one port (30080) to the pod's port 80 (S18). After masquerade DNAT, the traffic reaches nginx in the guest.
- **Why NodePort.**
  - A self-managed kubeadm cluster has no cloud load-balancer integration, so a `LoadBalancer` Service would stay pending without extra AWS components (ENGINEERING INFERENCE).
  - NodePort needs no extra AWS resource.
  - 30080 lies in the **static band** (30000-30085) that Kubernetes reserves for manually chosen ports, so it cannot collide with an automatically assigned one (CURRENT UPSTREAM DOCUMENTATION, S18). **VALID.**
- **What NodePort does not solve.**
  - No DNS name and no TLS.
  - No stable address across sessions: the auto-assigned public IPv4 changes with every rebuild.
  - No load balancing or HA on one node.
  - With the default `externalTrafficPolicy: Cluster`, the client's source IP is replaced, so nginx logs show a cluster address, not the operator's (ENGINEERING INFERENCE).
  - No IP continuity.

  All of these are acceptable for a validation endpoint and are correctly deferred.
- **Why 192.168.50.31 is not preserved: VALID.** The four reasons in 1H section 14 hold:
  - VMnet8 is unreachable from AWS;
  - masquerade assigns the address;
  - a VPC only delivers ENI-assigned subnet addresses;
  - the source keeps running.

  Network mapping (port group to pod network with masquerade, a platform declaration in the VM spec) is correctly kept apart from guest network remediation (a file inside the guest).
- **/32 restriction: VALID, with an operating note.**
  - NodePort listens on all node addresses (S18), so the security group is the only filter.
  - The /32 must be the operator's current public egress address. If the design later transfers from `conversion-host-01`, that address is the lab's egress through Workstation NAT, which on a home connection is the same address (ENGINEERING INFERENCE).
  - A changed ISP address means updating the security group through Terraform, not widening it.

### Checks

- **flannel + masquerade: VALID.** Masquerade works on the pod network with any CNI (S14). flannel is KubeVirt's own CI CNI for this tuple (PROJECT-DERIVED FACT, 1H).
- **Multus: not needed. VALID.**
  - One NIC, no L2 requirement, no address preservation: nothing in the design needs a secondary network.
  - No redesign is proposed.
- **CNI dependencies: NEEDS CLARIFICATION.** The standard kubeadm prerequisites need to be in the build checklist:
  - flannel's pod CIDR passed to kubeadm;
  - `br_netfilter` and IP forwarding.
- **Address plan: NEEDS CHANGE.** Stage 1H fixes none of the address ranges that must not overlap:
  - the masquerade guest network (10.0.2.0/24, the `vmNetworkCIDR` default);
  - the flannel pod CIDR;
  - the Kubernetes Service CIDR;
  - the VPC and subnet CIDR.

  Example: if the subnet were 10.0.2.0/24, the guest would treat the node's own subnet as on-link and could not reach it (ENGINEERING INFERENCE). This must be fixed in the design before Terraform is written (R3).
- **Guest management path: NEEDS CHANGE (clarity).** 1H section 21 offers "`virtctl ssh` or SSH through the Service". But:
  - the only Service in the design exposes port 80 as NodePort 30080;
  - the security group opens 22 only to the node's own sshd.

  So "SSH through the Service" does not exist. The working paths all go through the Kubernetes API over the SSH tunnel:
  - `virtctl console`;
  - `virtctl vnc`;
  - `virtctl ssh` or `virtctl port-forward` to the VMI, which is where the declared masquerade port 22 matters.

  The guest login credentials are the source's own and stay outside Git (R4).
- **Guest DNS: NEEDS CLARIFICATION, correctly left open (U5).** Upstream documents DNS and search domains in the IPv4 DHCP reply. Actual resolution through CoreDNS to the VPC resolver remains a runtime check.
- **MTU (ENGINEERING INFERENCE).** MTU is propagated to virtio guests by DHCP and libvirt (S14). No risk is expected, but it should be recorded at runtime.

## 9. Guest Remediation Review

### Where the netplan remediation belongs

| Option | Assessment |
|---|---|
| **Image preparation on the conversion host (chosen by ADR 010)** | Deterministic and offline. Verifiable by file hash and by a local boot. Does not need the guest to have network access, which is exactly what is broken. Independent of KubeVirt features. Follows ADR 006 (tools on the conversion host, one-way data flow). **Best fit** |
| Workflow step after import (edit the PVC in the cluster) | Needs libguestfs inside the cluster against a Block PVC. Moves guest-filesystem editing onto the privileged target and after the transfer, when a mistake costs another import. Worse |
| Inside the controller | A controller should orchestrate, not edit guest filesystems. Remediation logic would run in the reconciler process, needing root-level disk access. Wrong layer |
| First-boot or post-boot step (cloud-init NoCloud, console fix) | cloud-init is disabled in this guest, so NoCloud means re-enabling cloud-init: a larger guest change than one netplan file. A console fix is manual and not repeatable. Worse |

Conclusion (ENGINEERING INFERENCE, agreeing with ADR 010): remediation belongs to **image preparation**, as a declared and recorded step.

- In the future workflow it is a distinct checkpoint between CONVERT and IMPORT (section 10).
- It is performed by whatever executes conversion (today the conversion host). The controller only requests it and records its result.
- **Network mapping and guest network remediation are separate concerns.**
  - Mapping (pod network, masquerade, exposed ports) is declared in the VM and implemented by KubeVirt and the CNI.
  - Remediation (netplan) is a file in the guest.
  - Neither is implemented by the migration controller, which transports no packets.

### Internal consistency of the offline guest-agent approach

- **"Offline" refers to the guest, not the conversion host (NEEDS CLARIFICATION).**
  - The guest never needs internet access at first boot.
  - `conversion-host-01` does need Ubuntu archive access for `apt-get download`.
  - 1H implies this but should say it, since ADR 006 describes that host as a controlled environment.
- **Dependency skew (U8): NEEDS CLARIFICATION.**
  - `apt-get download` fetches current archive versions. Their dependencies may require newer libraries than the guest's package state, so `dpkg -i` either fails or needs library upgrades inside the guest. Either widens the guest change (ENGINEERING INFERENCE).
  - The design should record:
    - the exact package set (names, versions, sha256);
    - a dry run against the guest's own dpkg status;
    - a stop rule: if already-installed guest packages would be upgraded, stop for a human decision.
  - An alternative that resolves against the guest's own package database, such as running the guest's apt inside the libguestfs appliance with network access on the conversion host, is equally "offline at first boot". It is noted, not proposed.
- **First-boot removal (U9): NEEDS CLARIFICATION, and resolvable from existing evidence.**
  - 1G recorded exactly five scripts under `guestfs-firstboot`: wait-online, setenforce 0, install qemu-guest-agent, setenforce restore, start qemu-guest-agent (PROJECT-DERIVED FACT, 1G).
  - All five serve the agent install. Removing all five, or disabling the service, is therefore safe and loses no other virt-v2v action (ENGINEERING INFERENCE).
  - The design should say "all five scripts or the service", not only "the scripts that run apt-get", or the 30-second wait-online script remains.
- **Channel and detection: VALID.**
  - KubeVirt adds the agent channel to every domain (S15).
  - On Ubuntu the agent service is started when that virtio port appears (ENGINEERING INFERENCE).
  - `AgentConnected` is correctly treated as non-blocking.
- **Guest change accounting: NEEDS CHANGE.** The agent, its dependencies, the removed first-boot files and the new netplan file are intended changes to the guest's root filesystem. See the identity inconsistency in section 12 and R2.

## 10. Migration Workflow Review

The target workflow, mapped to artifacts, systems and responsibilities.

- "Controller" means the future `VirtualMachineMigration` controller (ADR 005), which does not exist.
- "Human" means the operator in the first migration.
- All mapping content is PROPOSED DESIGN built from PROJECT-DERIVED FACTS. The Stage 0 phase each step corresponds to is given in brackets.

| Step [Stage 0 phase] | Artifacts | Conversion host | K8s / KubeVirt / CDI resources | Controller (future) | Human (first migration) | Sync / async | Checkpoint, resume, idempotency |
|---|---|---|---|---|---|---|---|
| DISCOVER [Discovering] | Source inventory: CPU, memory, firmware, disk, NIC, guest OS | - | - | Record inventory in `status` (read-only against the source) | Done in 1C, 1D | Sync, short | Idempotent read; re-run freely |
| ACQUIRE [Preparing] | Golden VMDK + hashes | Receives working copy | - | Request power-off per policy, copy, record hashes. Never power off without an explicit policy | Done in 1E (graceful shutdown, copy, power-on) | Async, long | Checkpoint = verified golden hash; resume by re-verifying, never re-copying over a verified golden |
| VERIFY [part of Preparing] | Hash records | Working copy verified, immutable | - | Compare hashes before advancing | Done in 1E to 1G | Sync | Idempotent; mismatch -> manual intervention |
| CONVERT [Converting] | virt-v2v qcow2 + hash | virt-v2v | - | Request, wait, record output hash | Done in 1G | Async, minutes | Output to a new path; resume by hash check; never overwrite |
| REMEDIATE [**missing in Stage 0**] | Prepared qcow2 + preparation record | libguestfs on a new copy; local boot test (R5) | - | Request, record the record's hash | Future | Async, minutes | New path each time; resume by hash; failure -> fix and redo from the virt-v2v output |
| TRANSFER [**missing in Stage 0**; part of Importing] | Same qcow2 on the node | Source of the copy | - | Cannot initiate from AWS (section 11) | Future: `scp` from the lab, sha256 at both ends | Async | Resume by partial copy + hash; mismatch -> re-copy |
| IMPORT [Importing] | DataVolume, PVC, scratch PVC | - | CDI upload DataVolume, PVC, EBS volume | Create DataVolume by a deterministic name; watch phase | Future: `virtctl image-upload` via `port-forward` | Async; reconciled by CDI | Checkpoint = DataVolume `Succeeded`; retry by deleting and recreating the DataVolume (the qcow2 is authoritative) |
| CREATE VM [CreatingVM] | VM object | - | `VirtualMachine` referencing the PVC, Service | Create-if-absent by name; not started yet | Future | Sync (API write) | Idempotent by name; compare spec on resume |
| START [Starting] | VMI, virt-launcher pod | - | VMI, pod, EBS attach | Set run strategy; wait for VMI `Running` | Future: `virtctl start` | Async; reconciled by KubeVirt | Checkpoint = VMI `Running`; retry by stop/start; never recreate the PVC |
| VERIFY [Validating] | Check results | - | Read VMI status, Service | Run or collect the 12 checks; record each | Future | Async | Idempotent reads; failures -> manual intervention, never silent retry |
| CUTOVER / COMPLETE [Completed] | Evidence | - | - | Mark complete; cleanup per policy | Future: capture evidence, then teardown (R1) | Sync | **No cutover in the first migration:** the source keeps running, no address moves (I-08) |

Findings:

- **NEEDS CHANGE (for the controller design; does not block a manual Stage 1I).**
  - The Stage 0 state machine has no REMEDIATE or TRANSFER checkpoint. Stage 1G and 1H made both into real, separately verifiable steps.
  - The Stage 0 phase list should gain them before any controller design.
- **NEEDS CLARIFICATION: run strategy.**
  - 1H uses `Manual`. The Stage 0 state machine creates the VM `Halted` and then sets `Always`, and the Stage 0 CRD sketch uses `Always`.
  - For a manual first migration `Manual` is coherent: start and stop are explicit, and a node reboot leaves the VM off (S17).
  - For an automated migration, the desired final run strategy belongs in the CR spec. Both are defensible; the difference should be written down, not left implicit.
- **Human gates stay human.** Power-off of the source, the start of any AWS spending, and teardown are approval points, not automatic transitions (PROJECT-DERIVED FACT, ADR 002 and the Stage 0 state machine).

## 11. CRD / Controller Review

### Why a controller rather than a script (applies later, not to the first migration)

PROJECT-DERIVED FACT (ADR 005), with ENGINEERING INFERENCE:

- **Long, asynchronous steps.** CDI import and VM start are themselves reconciled by other controllers. A controller watches them; a script polls and loses its place if the terminal dies.
- **State lives in the API.**
  - `status` records the checkpoint and its evidence (hashes, names), so a restart resumes from the record instead of from the top.
  - "Record before you advance" becomes enforceable.
- **Idempotent creation.** Deterministic names, create-if-absent and owner references make a retry safe.
- **Visibility and access.**
  - Phase, conditions and events are visible to `kubectl`.
  - RBAC can scope a service account instead of using the human's admin kubeconfig.
- **Cleanup on delete.** Finalizers can remove half-created objects.

For **one** migration, a written runbook with recorded checkpoints is simpler and sufficient. The first migration is intentionally simpler than production, and ADR 005 already allows scripts as building blocks.

### Conceptual `VirtualMachineMigration`: three kinds of state

PROPOSED DESIGN. This is not a schema; names are illustrative.

| Kind | Where | Contents |
|---|---|---|
| **Desired state** (what the user asks for) | `spec` | Source reference: the VM identity and **how the disk is obtained** (existing acquired artifact with expected hash, or acquisition with an explicit power policy). Conversion profile (virt-v2v). Remediation profile (network: driver match + DHCP; agent: offline install; first boot: remove). Transfer and import method (upload). Destination: namespace, VM name, compute (from inventory or override), firmware (EFI, Secure Boot off), disk bus, storage class, volume mode Block, size not below the source. Network mapping: pod network, masquerade, exposed ports, Service type. Validation profile: expected page hash and marker. Final run strategy. Cleanup policy. Source policy: leave running |
| **Observed state** (what the world reports) | `status`, refreshed from reality | Source inventory snapshot. Artifact hashes seen at each stage. DataVolume phase and progress. PVC phase, size and mode. VMI phase, guest address, `AgentConnected`. Validation result per check. Conditions |
| **Workflow state** (where the migration is) | `status` | Phase and current checkpoint. Per-checkpoint record: started, completed, evidence reference, output hash. Retry count and last error classified as retryable, manual intervention or failed. `observedGeneration`. Pending human approvals |

### Discrepancies with the Stage 0 sketch

The [Stage 0 migration-architecture sketch](../stage-0/migration-architecture.md) predates Stages 1E to 1H. These discrepancies are historical and are not rewritten here (PROJECT-DERIVED FACT):

| Stage 0 sketch | Stage 1H / project evidence | Status |
|---|---|---|
| `volumeMode: Filesystem` | Block (ADR 009) | NEEDS CHANGE before any controller design |
| Staging through S3 with a credentials Secret | CDI upload through `port-forward`; no cloud credentials in the cluster | NEEDS CHANGE before any controller design |
| `runStrategy: Always`; state machine `Halted` -> `Always` | `Manual` | NEEDS CLARIFICATION |
| Demo source 2 vCPU, 2 GB, 20 GB; example DataVolume 20Gi | 2 vCPU, 4096 MB, 40 GiB | Historical example; no action |
| Controller reaches ESXi over SSH (Discovering, Preparing) | The controller would run in AWS; ESXi and the conversion host are behind laptop NAT with no inbound path; ADR 006 forbids conversion tools from contacting ESXi | **NOT YET DEFINED** |

**The controller's reach is the main architectural gap for the controller stage** (ENGINEERING INFERENCE):

- A controller in the AWS cluster cannot drive DISCOVER to TRANSFER in the lab. [Stage 0 architecture](../stage-0/architecture.md) and the [networking model](../stage-0/networking-model.md) themselves state that lab-to-AWS connectivity is outbound-only.
- Viable shapes to decide later:
  - a lab-side executor that connects out to the cluster API, takes work from the CR and reports status;
  - the controller owning only IMPORT onwards, with a lab-side runner recording the earlier checkpoints into the CR;
  - moving conversion into AWS (a conversion pod, as MTV does), which moves the 40 GiB VMDK transfer instead.
- This does not block a manual Stage 1I. It must be decided before any controller design.

## 12. Failure and Recovery Review

ENGINEERING INFERENCE throughout, built on the design and the Stage 0 state machine. "Retry safety" assumes the source and the lab artifacts are never modified, which the design guarantees (PROJECT-DERIVED FACT).

| # | Failure | Detection | State / checkpoint | Retry safe? | Cleanup | Operator intervention |
|---|---|---|---|---|---|---|
| F1 | No `/dev/kvm`: nested virtualization not enabled or not offered (U1) | Pre-flight `describe-instance-types`; KubeVirt reports the node not schedulable; `virt-host-validate` | Platform gate, before any import | Yes, after fixing the CPU option (stop, modify, start) | None | Required. Never switch to software emulation silently; that would invalidate the design |
| F2 | KubeVirt or CDI not `Available`, or a KubeVirt-CDI mismatch (U12) | CR conditions; runtime gate G5 | Platform gate | Yes | Remove the failed install | Required: choosing another CDI version is a documented change, not a silent swap |
| F3 | EBS volume not provisioned (IAM, IMDS hop limit, U11) | PVC `Pending`; DataVolume stuck; driver logs and events | IMPORT, not started | Yes, after the fix | Delete the DataVolume; check for tagged volumes | Required for IAM or metadata settings |
| F4 | Transfer interrupted or corrupted | sha256 mismatch on the node | TRANSFER | Yes: the qcow2 in the lab is authoritative | Delete the partial file | None beyond re-copy |
| F5 | Upload interrupted (port-forward dropped, token expired after 5 minutes, S7) | `virtctl` error; DataVolume not `Succeeded` | IMPORT | Yes: delete and recreate the DataVolume, then re-upload | Scratch PVC removal, confirmed | Minor |
| F6 | Scratch space cannot be provisioned | DataVolume stalls; events show the scratch PVC `Pending` | IMPORT | Yes | Delete the DataVolume | Fix the scratch storage class (S6, S7) |
| F7 | Wrong image imported (for example, the 1G static-address test copy) | Only in the guest: netplan content, `blkid`; prevented by checking the file hash against the preparation record before upload | IMPORT reported success | Yes | Delete the VM and the DataVolume; re-upload | Required; record the mistake |
| F8 | UEFI boot fails under KubeVirt's OVMF (U6) | VMI `Running` but the console shows the firmware shell or no bootloader | START | Not blindly | None until diagnosed | Required: console diagnosis. Any guest change goes through a new preparation cycle |
| F9 | Guest boots without network (driver match, DHCP) | No guest address in VMI status; NodePort fails; console `ip addr` | START / VERIFY | After a new prepared image | Delete the VM and the DataVolume if re-importing | Required. Editing the live guest by hand is recorded as a deviation |
| F10 | Boot stalls on leftover first-boot work, or the agent install breaks packages | Console: `systemctl is-system-running` = `starting`; `dpkg --audit` | START / VERIFY | After a new prepared image | As F9 | Required; U8, U9 |
| F11 | NodePort unreachable | Timeout (security group or wrong /32) vs refused (port not declared, nginx down) vs no endpoints (Service selector mismatch) | VERIFY | Yes | None | Fix the security group through Terraform, or fix the Service or VM spec |
| F12 | Node reboot or instance stop | Node `NotReady` and back; VMI gone; with `Manual`, not restarted | Any; the disk persists on EBS | Yes | None | `virtctl start`; the new public IPv4 changes the validation URL |
| F13 | Guest killed for memory or evicted | Events, VMI `Failed` | START / VERIFY | Yes | None | Check the node's memory headroom (section 6) |
| F14 | Operator workstation or session lost mid-run | Nothing in the cluster knows the checkpoint | Whatever was last written down | Only if checkpoints were recorded | - | The runbook must record each checkpoint as it passes; this is the manual form of "record before you advance" |
| F15 | Teardown leaves volumes behind | Post-destroy check for volumes tagged `ebs.csi.aws.com/cluster = true` in the account and Region | After COMPLETE | Yes | Delete the orphaned volumes | Required once per teardown (R1) |

### Identity inconsistency found while reviewing the checks

**NEEDS CHANGE.**

- 1H section 21 says the workload identity "must not change", including "Ubuntu root filesystem content".
- The design itself changes that content on purpose:
  - netplan;
  - the agent and its dependencies;
  - the removed first-boot files;
  - and, from virt-v2v, the purged open-vm-tools and a rebuilt initramfs.
- As written, a strict reviewer would fail the migration on the design's own changes.
- **Required correction:** "unchanged except for an enumerated list of intended changes", backed by the preparation record (R2).

## 13. Security Review

| Topic | Current design | Assessment | Basis |
|---|---|---|---|
| NodePort /32 | Security group: 30080 and 22 from one /32 | VALID. NodePort listens on all node addresses, so the security group is the control. It must never be widened to 0.0.0.0/0 to work around a changed ISP address | S18; ENGINEERING INFERENCE |
| SSH to the node | New key pair at build time, never committed, password login off | VALID | PROJECT-DERIVED FACT |
| SSH to the guest | Uses the source's own accounts and host keys | NEEDS CLARIFICATION: the path is through the Kubernetes API (section 8); guest credentials stay outside Git | ENGINEERING INFERENCE |
| Artifact handling | Transfer over SSH, sha256 at both ends | VALID; add deletion of the qcow2 from the node after import | ENGINEERING INFERENCE |
| Golden artifact integrity | Hash chain from golden to working copy to virt-v2v output | NEEDS CLARIFICATION: extend the chain with the preparation record (R2) so the imported image is traceable to the golden one | PROJECT-DERIVED FACT |
| Artifacts as sensitive data | Not stated | NEEDS CHANGE. Every copy (VMDK, qcow2, EBS volume) contains the guest's SSH host private keys, `/etc/shadow` hashes and logs. Anyone holding a copy can impersonate the server. Therefore: encrypt at rest in AWS (R7), delete copies deliberately (R1), and never put them in Git (already a standing rule) | ENGINEERING INFERENCE |
| Source disks containing secrets | Guest keeps host keys and machine-id; source and target never share a network | VALID as a network rule; the data-handling side is the row above | PROJECT-DERIVED FACT |
| RBAC | kubeadm admin kubeconfig outside Git; default KubeVirt roles | VALID for one operator on a disposable node. A future controller needs its own narrowly scoped service account (DataVolumes, VMs, Services, upload tokens in one namespace) | ENGINEERING INFERENCE |
| CDI upload permissions | Upload proxy only through `port-forward` on the node; `--insecure` accepted | VALID. Upload tokens are scoped to one PVC and valid for 5 minutes (S7). `--insecure` skips verification of the proxy's self-signed certificate over a loopback port-forward inside an authenticated API tunnel. Acceptable for the lab; not a production pattern | S7; ENGINEERING INFERENCE |
| Privileged components | virt-handler and parts of CDI privileged; node trusted; SELinux enforcing | VALID | PROJECT-DERIVED FACT |
| Instance metadata | IMDSv2, hop limit 2, role with the EBS CSI policy only | VALID as an accepted lab risk. Any pod can obtain the role, and the role can delete CSI-tagged volumes, including the migrated disk. The guest sits one further NAT hop behind its pod, so a hop limit of 2 probably stops it obtaining a token. That is ENGINEERING INFERENCE and worth one runtime check | S11; ENGINEERING INFERENCE |
| Guest isolation | Guest runs inside the virt-launcher pod under QEMU and KVM, behind masquerade | VALID. Only the declared ports reach it | S14 |
| Beta feature gates | All Beta gates on by default in v1.9, accepted | VALID for a disposable lab; hardening deferred | PROJECT-DERIVED FACT |
| Terraform state | Outside Git | VALID. It holds resource IDs and addresses, not credentials, but stays private | PROJECT-DERIVED FACT |

## 14. Architecture Completeness Matrix

| AREA | CURRENT DESIGN | STATUS | ISSUE | RECOMMENDATION |
|---|---|---|---|---|
| Kubernetes | kubeadm 1.36 single node, CRI-O 1.36, CentOS Stream 9 | VALID | Versions re-verified on 2026-09-30 | None |
| KubeVirt | v1.9.0, VM referencing a PVC, EFI with Secure Boot off, `Manual` | VALID | Machine type, CPU model and varstore left at defaults; `Manual` differs from the Stage 0 model | Record the actual defaults at runtime; write down the run-strategy difference (I-11) |
| CDI | v1.66.1 candidate, upload DataVolume, `port-forward`, `--force-bind` | NEEDS CLARIFICATION | Pairing unpublished (U12); `Succeeded` is not content proof | Keep the runtime gate; define import verification (I-07) |
| Compute | `m8i.xlarge` nested; 2 vCPU / 4096 Mi guest | VALID | U1 open; headroom inferred | Pre-flight check; observe headroom |
| Storage | gp3 Block RWO 40 GiB, standalone DataVolume, scratch Filesystem | NEEDS CHANGE | "Deleted with the cluster" is wrong for CSI volumes; encryption unset; standalone qcow2 unstated | R1, R7; state the no-backing-file rule |
| Networking | Pod network, masquerade, NodePort 30080 from the /32 | NEEDS CHANGE | No address plan; guest management path misstated | R3, R4 |
| Guest remediation | Offline netplan driver match + DHCP, offline agent, first-boot removal | NEEDS CLARIFICATION | Never booted together; dependency skew; "all five scripts" | R5; U8 stop rule; name all five scripts |
| Migration workflow | Section 18 steps; first migration manual | NEEDS CLARIFICATION | Point-in-time semantics unstated; REMEDIATE and TRANSFER not Stage 0 phases | R8; add both checkpoints before controller work |
| Controller | ADR 005; Stage 0 CRD sketch | NOT YET DEFINED | Lab reachability from AWS; sketch fields superseded | Decide the executor boundary before controller design (deferred) |
| Observability | Console, VMI status, `AgentConnected`, events | NEEDS CLARIFICATION | No evidence capture before teardown | Capture check results, VMI status and events before destroy (R1) |
| Security | Section 23 model | NEEDS CHANGE | Artifacts as sensitive data; encryption at rest | R7; handling rules in the runbook |
| Validation | 12 checks; infrastructure vs workload identity | NEEDS CHANGE | "Root filesystem must not change" contradicts the design | R2 |
| Failure recovery | Stage 0 state machine; 1H risks | NEEDS CLARIFICATION | Manual run has no checkpoint log | Checkpoint log in the runbook (F14) |
| Cleanup | Terraform destroy | NEEDS CHANGE | Orphaned CSI volumes; qcow2 and scratch cleanup unstated | R1 |
| AWS infrastructure | One VPC, public subnet, security group, instance profile, `m8i.xlarge`, 50 GiB root | NEEDS CLARIFICATION | CIDRs and root encryption not fixed; credentials still BLOCKED (U15) | R3, R7; the U15 gate stays |

## 15. Required Changes Before Stage 1I

PROPOSED DESIGN. All eight are documentation corrections to the Stage 1H design. None needs infrastructure, a conversion or a boot to write down. R5 defines a step that Stage 1I would execute.

| ID | Change | Issue | Why it must come before Stage 1I |
|---|---|---|---|
| R1 | **Teardown order and orphan check.** Before any destroy: capture evidence, delete the VM, the DataVolume and PVC, confirm the PV and EBS volume are gone. Then run the Terraform destroy. Then list volumes tagged `ebs.csi.aws.com/cluster = true` and delete any left over. Delete the qcow2 from the node. Correct the "destroyed with the Terraform state" and "deleted with the cluster" statements in 1H section 11, 1H section 23 and ADR 009 | I-01 | Factual error. The first real session would otherwise leak billed volumes holding a copy of the guest's secrets |
| R2 | **Intended-change manifest.** Define workload identity as "unchanged except for" an enumerated list: the virt-v2v changes recorded in 1G, the netplan file, the agent and its exact dependency set, the removed first-boot files. Tie it to a preparation record (input and output hashes, `.deb` hashes) | I-02 | The pass criteria otherwise contradict the design |
| R3 | **Address plan.** Fix non-overlapping ranges for the VPC and subnet, the flannel pod CIDR, the Service CIDR and the masquerade `vmNetworkCIDR` (default 10.0.2.0/24) | I-03 | Terraform and kubeadm need these values; an overlap breaks guest reachability |
| R4 | **Guest management path.** Replace "SSH through the Service" with the API-tunnel paths (`virtctl console`, `vnc`, `ssh` or `port-forward`). State that port 22 is declared in the masquerade ports for that reason and is not exposed by the security group | I-04 | Validation checks 2 to 8 need a guest shell; the stated path does not exist |
| R5 | **Pre-transfer boot test of the prepared image.** On `conversion-host-01`, before transfer, boot the exact prepared qcow2 once under QEMU/KVM with user-mode networking and the agent's virtio-serial port, as in 1G. Check: DHCP address on the driver-matched NIC, `systemctl is-system-running` = `running`, agent responding, nginx page hash through a port forward. Delete the test guest afterwards | I-06 | The imported image combines three guest changes that were never booted together. Finding a mistake in the lab costs minutes; finding it in AWS costs a re-transfer and re-import on paid, nested infrastructure. QEMU's user-mode network provides DHCP, so the DHCP netplan file can be tested offline |
| R6 | **Transfer constraints.** Keep the route choice for Stage 1I. Fix the constraints now: outbound from the lab only; SSH to the node with the build-time key; the /32 must match the lab's egress; sha256 compared at both ends; where the node key may live and when it is removed | I-05 | It is a hard prerequisite of every later step, and it decides where a private key is stored |
| R7 | **Encryption at rest and artifact sensitivity.** Encrypt the root volume and set the StorageClass `encrypted` parameter (default `false`, S10), or require account-level EBS default encryption. Record that every disk copy is sensitive data (host private keys, password hashes) | I-12 | The design otherwise stores an unencrypted copy of the server's secrets |
| R8 | **Point-in-time semantics.** State that the first migration imports the Stage 1E point-in-time copy, the source keeps running, nothing written since 1E is carried, and no cutover happens | I-08 | It defines what "migrated" means for the first run and for its report |

## 16. Items That Are Deliberately Deferred

These are acceptable to defer and do not block Stage 1I. They are listed so that deferral stays visible.

| Item | Deferred to | Condition |
|---|---|---|
| Controller executor boundary (lab-side executor vs in-AWS conversion) and the Stage 0 CRD sketch fields (Filesystem, S3, run strategy) | Before any controller design | Must be decided before ADR 005 is implemented |
| REMEDIATE and TRANSFER as Stage 0 state-machine checkpoints | Before any controller design | Documentation update to the Stage 0 model |
| The transfer route itself (from the conversion host directly, or through Windows) | Stage 1I planning | Within the R6 constraints |
| Guest DNS behaviour (U5), OVMF under KubeVirt (U6), force-bind (U10), EBS CSI metadata access (U11), CDI pairing (U12) | First runtime | Observed and recorded, not assumed |
| The guest-agent dependency resolution method (U8) | Image preparation | With a stop rule if guest packages would be upgraded |
| Recording KubeVirt's defaults (machine type, CPU model, varstore) | First runtime | Record, do not pin |
| Post-import block-level comparison (for example `qemu-img compare` against the PVC) | Later | Guest-level checks plus file hashes suffice for one migration |
| Live migration and RWX, Multus and bridge, passt, IP preservation, DNS names, TLS, load balancers, Ingress | Per 1H section 25 | Unchanged |
| EKS, multi-node and HA, bare metal, Secure Boot, CentOS Stream 10, instance types, cloud-init | Per 1H section 25 | Unchanged |
| Snapshots and backup, Beta-gate hardening, monitoring | Per 1H section 25 | Unchanged |
| Warm migration (ADR 003), production design, GitOps | Per 1H section 25 | Unchanged |
| Terminology in Stage 0 (virt-handler "converts" the VMI) and the dashboard label "VM operator" | Next revision of those pages | Cosmetic |
| Long-lived operation (CentOS Stream 9 EOL 2027-05-31 before Kubernetes 1.36 EOL) | Production design | Irrelevant for a rebuilt-per-session lab |

## 17. Stage 1H Review Conclusion

**Classification: REQUIRES ARCHITECTURAL CORRECTIONS.**

What holds:

- The platform choice, version tuple, KubeVirt object model, network model (masquerade, no IP preservation, NodePort validation), storage model (qcow2 in transit, raw on a Block gp3 PVC via a CDI upload) and the placement of guest remediation in image preparation are technically coherent.
- They trace correctly back to what Stages 1A to 1G proved.
- All versions still match upstream on 2026-09-30, and no version change is proposed.
- The design keeps its distinctions straight:
  - format conversion vs guest conversion;
  - network mapping vs guest remediation;
  - platform networking vs a controller that transports no packets;
  - test boots vs a migrated KubeVirt VM.

What must change first:

- **Two errors:**
  - teardown does not remove CSI-provisioned volumes (R1);
  - the identity rule contradicts the design's own guest changes (R2).
- **Four undefined elements that Stage 1I would otherwise have to invent under time and cost pressure:**
  - the address plan (R3);
  - the guest management path (R4);
  - the transfer constraints (R6);
  - encryption at rest (R7).
- **One missing lifecycle step:** the pre-transfer boot test (R5).
- **One unstated semantic:** point-in-time, no cutover (R8).

These corrections are bounded and documentation-only. They refine the design; they do not redesign it.

**Human approval remains the gate.**

- This review does not approve, define or start Stage 1I.
- After R1 to R8 are applied and accepted, the design can be presented as READY FOR HUMAN APPROVAL.
- Stage 1I then still needs, as 1H section 28 already states, the user's explicit approval of objective, scope and change boundary, and working AWS credentials (U15, currently BLOCKED).

### Issue register

| ID | Issue | Section | Severity for Stage 1I |
|---|---|---|---|
| I-01 | Teardown leaves CSI-provisioned EBS volumes; "deleted with the cluster" is inaccurate | 7 | Must fix (R1) |
| I-02 | Workload identity "root filesystem unchanged" contradicts intended guest changes | 12 | Must fix (R2) |
| I-03 | No address plan (VPC, pod, Service, masquerade CIDRs) | 8 | Must fix (R3) |
| I-04 | "SSH through the Service" does not exist in the design | 8 | Must fix (R4) |
| I-05 | Transfer route deferred without constraints | 4, 11 | Must fix constraints (R6) |
| I-06 | Prepared image never booted before transfer | 4, 9 | Must fix (R5) |
| I-07 | DataVolume `Succeeded` treated as sufficient; import verification not stated | 7 | Clarify (part of R2 and R6) |
| I-08 | Point-in-time copy and no-cutover semantics unstated | 4, 10 | Must fix (R8) |
| I-09 | Offline agent: dependency skew (U8); "offline" applies to the guest only | 9 | Clarify at preparation |
| I-10 | First-boot removal should name all five scripts or the service | 9 | Clarify (part of R2) |
| I-11 | Run strategy `Manual` vs the Stage 0 `Halted` -> `Always` | 10 | Clarify; deferred for the controller |
| I-12 | Encryption at rest unset; artifacts not classified as sensitive | 7, 13 | Must fix (R7) |
| I-13 | "Raw at rest" wording; standalone qcow2 (no backing file) unstated | 7 | Clarify |
| I-14 | Controller cannot reach the lab from AWS; executor boundary undefined | 11 | Deferred, before controller design |
| I-15 | Stage 0 CRD sketch: Filesystem, S3 staging, `Always` superseded | 11 | Deferred, before controller design |
| I-16 | Stage 0 state machine lacks REMEDIATE and TRANSFER checkpoints | 10 | Deferred, before controller design |
| I-17 | Guest-agent channel "INFERRED" is now documented upstream (S15) | 6 | Informational |
| I-18 | Stage 0 "virt-handler converts the VMI to domain XML"; dashboard "VM operator" label | 6 | Cosmetic, deferred |
| I-19 | KubeVirt defaults (machine type, CPU model, varstore) unrecorded | 6 | Record at runtime |
| I-20 | CNI prerequisites (pod CIDR to kubeadm, `br_netfilter`, forwarding) not in a checklist | 8 | Clarify (with R3) |
