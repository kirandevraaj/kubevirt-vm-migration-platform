# Stage 1H: KubeVirt destination feasibility and network/storage architecture

| Field | Value |
|---|---|
| Project | Project 1.5: VM-to-Kubernetes Migration Platform |
| Stage | 1H |
| Date | 2026-09-28 (all times UTC; H1 checks at 04:22) |
| Approval | Explicitly approved by the user as **design, feasibility and architecture only**: research current KubeVirt, CDI, Kubernetes and AWS requirements; compare EKS with self-managed Kubernetes; design the network, storage, guest-remediation and guest-agent model; write ADRs and diagrams; make one evidence-based target-platform decision. Not approved: any AWS resource, EC2 instance, EKS or kubeadm cluster, Kubernetes/KubeVirt/CDI installation, Multus, NetworkAttachmentDefinition, StorageClass, PVC, DataVolume or VM; any change to `legacy-source-vm`, the Stage 1E golden artifact or the Stage 1G images; Stage 1I. |
| Result | **Success (H1 to H10 PASS).** Chosen target for the first KubeVirt migration: a **single-node, self-managed kubeadm cluster on one EC2 instance with nested virtualization** (`m8i.xlarge`, ap-south-1), running **CentOS Stream 9 + CRI-O 1.36 + Kubernetes 1.36 + KubeVirt v1.9.0 + CDI v1.66.1** on x86_64 with KVM. The VM uses the **pod network with masquerade binding** (no Multus) and gets its address by DHCP; **192.168.50.31 does not survive** and is replaced by a Kubernetes Service. Storage is **EBS gp3 through the EBS CSI driver, Block volume mode, ReadWriteOnce**; the disk travels as **qcow2** and CDI stores it as **raw** on the PVC. qemu-guest-agent is **installed offline at conversion time**, not at first boot. Nothing was created, installed or migrated. |
| Related | [ADR 007](../adr/007-kubevirt-target-platform.md) (platform), [ADR 008](../adr/008-kubevirt-network-model.md) (network), [ADR 009](../adr/009-kubevirt-storage-model.md) (storage and disk format), [ADR 010](../adr/010-migration-network-remediation.md) (guest network remediation), [Stage 1G record](stage-1g-controlled-conversion.md), [Stage 0 feasibility](../stage-0/feasibility.md), [Stage 1 index](README.md) |
| Post-review corrections | 2026-09-30. The [Stage 1H architecture review](stage-1h-architecture-review.md) (verdict: REQUIRES ARCHITECTURAL CORRECTIONS) required eight documentation corrections, review R1 to R8. With the user's approval they are applied to this record and to ADRs 008, 009 and 010 as **documentation only**. The details are in [section 29](#29-post-review-corrections-review-r1-to-r8). No AWS action, cluster, conversion, boot or other runtime experiment was performed for them. The 2026-09-28 findings, gates H1 to H10 and sources E1 to E49 are kept as recorded. Statements changed by the review are marked "(corrected 2026-09-30, review Rn)" or "(added 2026-09-30, review Rn)". Review R1 to R8 are the review's correction numbers and are unrelated to the risk IDs R1 to R13 in section 27. |

Labels: **OBSERVED** = seen in this lab by a command we ran. **DOCUMENTED** = stated by an official source listed in [Sources](#sources) (retrieved 2026-09-28, or 2026-09-30 where stated). **INFERRED** = reasoned from observations or documentation, not tested. **NOT TESTED** = deliberately not done. Decision states: **DECIDED**, **DEFERRED**, **UNKNOWN**, **BLOCKED**. Section 29 uses the review's four labels:

- **PROJECT-DERIVED FACT** corresponds to OBSERVED, or to an earlier stage's record.
- **CURRENT UPSTREAM DOCUMENTATION** corresponds to DOCUMENTED.
- **ENGINEERING INFERENCE** corresponds to INFERRED.
- **PROPOSED DESIGN** is a design value that has not been observed at runtime.

Source references such as [E5] point to the numbered table in [Sources](#sources), which records URL, title, retrieval date, the exact requirement and its implication.

Diagrams: [stage-1h-target-platform.svg](../diagrams/stage-1h-target-platform.svg), [stage-1h-migration-data-path.svg](../diagrams/stage-1h-migration-data-path.svg), [stage-1h-network-model.svg](../diagrams/stage-1h-network-model.svg).

## 1. Objective

Answer fifteen design questions with evidence, so that a later, separately approved stage can build the target without guessing:

| # | Question | Answer | State |
|---|---|---|---|
| 1 | Kubernetes distribution / environment | Upstream Kubernetes bootstrapped with kubeadm, one node (control plane and worker together), on one EC2 instance | DECIDED |
| 2 | Kubernetes version | 1.36 (latest patch at build time; v1.36.5 was current on 2026-09-28 [E25]) | DECIDED |
| 3 | KubeVirt version | v1.9.0 [E1, E2] | DECIDED |
| 4 | CDI version | v1.66.1 [E13] | DECIDED (no official KubeVirt-to-CDI matrix exists; section 8) |
| 5 | Worker node host OS | CentOS Stream 9 x86_64 (EL9 kernel, aligned with the virt-launcher userland) [E6, E7, E31] | DECIDED |
| 6 | Node virtualization capability | EC2 nested virtualization (Intel VT-x passed through by Nitro) on `m8i.xlarge`; KVM (`kvm_intel`) in the node kernel [E32] | DECIDED (to be proven on the node) |
| 7 | EKS vs self-managed vs local vs other | Self-managed on EC2. EKS deferred, local VMware-hosted rejected as the primary target, bare metal only a documented fallback (sections 10 to 12) | DECIDED |
| 8 | Storage model for the first cold migration | EBS CSI driver, gp3, `volumeMode: Block`, `ReadWriteOnce`, 40 GiB, one AZ; CDI upload DataVolume [E14, E40] | DECIDED |
| 9 | Network model | Pod network with `masquerade` binding; flannel CNI; no Multus [E20] | DECIDED |
| 10 | Can the VM retain 192.168.50.31? | **No** (section 14) | DECIDED |
| 11 | What replaces IP continuity? | Service continuity: a Kubernetes Service in front of the VM, plus workload-identity checks (page hash) instead of address identity | DECIDED |
| 12 | nginx validation after migration | The same 12 checks as Stages 1C to 1G, run inside the guest and from outside the cluster through the Service (section 21) | DECIDED |
| 13 | Guest network remediation | netplan: match the NIC by driver `virtio_net`, `dhcp4: true`; applied offline to a disposable converted copy (section 15, ADR 010) | DECIDED |
| 14 | Guest-agent strategy | Pre-install `qemu-guest-agent` offline during conversion; remove the virt-v2v first-boot install; agent is useful but not a pass/fail requirement (section 19) | DECIDED |
| 15 | What stays deferred | Live migration, RWX storage, Multus, bridge and passt bindings, IP preservation, DNS names, HA, EKS comparison, Secure Boot, production design (section 25) | DEFERRED |

## 2. Scope

In scope, all done as desk research and design:

- Official KubeVirt, CDI, Kubernetes, CRI-O, CentOS and AWS documentation, release metadata and CI definitions, read on 2026-09-28.
- Public AWS price files for ap-south-1 (no account, no credentials).
- One read-only health check of the lab (H1): Git state, source VM HTTP and hash, ESXi VM states, golden artifact hashes, local tooling.
- Architecture decisions, four ADRs (007 to 010), three diagrams and this record.

## 3. Explicit non-goals

Not done, by instruction: creating any AWS resource (VPC, EC2, EBS, IAM, EKS); installing Kubernetes, KubeVirt, CDI, Multus, a CNI or a CSI driver; creating NetworkAttachmentDefinitions, StorageClasses, PVCs, DataVolumes or VMs; running `virt-host-validate`; changing, shutting down or snapshotting `legacy-source-vm`; touching the golden artifact or the Stage 1G images; installing qemu-guest-agent anywhere; creating credentials or SSH keys; starting Stage 1I.

Also not done: no AWS CLI call was made (the CLI is not installed, and the AWS credential volume was not touched), and no Kubernetes API was contacted. Two pre-existing kubeconfig contexts on the workstation (`ckad-lab`, `docker-desktop`) belong to unrelated work and were only listed by name.

## 4. Current source workload

OBSERVED at H1 (04:22), unchanged since Stage 1C:

| Item | Value |
|---|---|
| VM | `legacy-source-vm`, Vmid 2 on `esxi-8-lab`, powered on, 0 snapshots |
| Guest | Ubuntu 24.04.5 LTS, kernel 6.8.0-142-generic (Stage 1G), UEFI, 2 vCPU / 4096 MB, 40 GiB disk (PVSCSI), one VMXNET3 NIC |
| Network | Static 192.168.50.31/24 on VMnet8 (a VMware Workstation NAT network on the laptop), gateway and DNS 192.168.50.2, MAC `00:0c:29:0f:3d:15` |
| Application | nginx on :80; HTTP 200, 267 bytes, page sha256 `b9826e18a06a354d6ba97e3419e266b1453cb2a3b0038d4b3dcd45c96c170046` from Windows and from ESXi |
| Other VMs | `conversion-host-01` (Vmid 3) on at .32; `kvm-learning-01` (Vmid 1) off |

## 5. Current converted workload findings

From the [Stage 1G record](stage-1g-controlled-conversion.md), which this stage relies on and does not repeat:

- virt-v2v 2.4.0 (`-i disk -o local -of qcow2`) produced a qcow2 (40 GiB virtual, 2.73 GiB file) that boots under QEMU/KVM with OVMF, Secure Boot off, through the ESP fallback loader, on virtio-blk (`vda`) and virtio-net.
- It purged open-vm-tools and rebuilt the initramfs, but left netplan matching `ens192`. The virtio NIC was `enp0s3`, so the guest came up with no network.
- It added `guestfs-firstboot` scripts that run `apt-get update` and install qemu-guest-agent. On an isolated network this stalled boot completion (`starting` for over 4 minutes).
- One netplan change on a disposable copy (match by driver `virtio_net`, static test address) produced a routable guest serving the source page hash.
- machine-id, SSH host keys, filesystem UUIDs, hostname and nginx were preserved.
- The generated libvirt XML said 1 vCPU / 2 GiB (defaults), not the source's 2 vCPU / 4096 MB.

Stage 1H consequences: the KubeVirt design must supply EFI (Secure Boot off), a virtio disk bus and a virtio NIC; the netplan remediation has to fit the chosen network binding; and the guest-agent install must not depend on first-boot internet access.

## 6. Current KubeVirt compatibility

| Fact | Evidence | State |
|---|---|---|
| Newest stable release | v1.9.0, published 2026-07-30 (a promotion of v1.9.0-rc.2) [E1]; the project's `stable.txt` returns `v1.9.0` [E2] | DOCUMENTED |
| Newer releases | Only `v1.10.0-alpha.0`, marked pre-release [E1]. Not used. | DOCUMENTED |
| Kubernetes range | "KubeVirt v1.9 is built for Kubernetes v1.36 and additionally supported for the previous two versions" [E3]; the support matrix lists 1.36, 1.35, 1.34 for v1.9 and no 1.37 [E4]. The user-supplied statement is confirmed. | DOCUMENTED |
| Upstream CI on release-1.9 | Presubmit lanes run on k8s-1.33 to k8s-1.36, including sig-compute, sig-network and sig-storage on k8s-1.36 [E8] | DOCUMENTED |
| CI node platform for 1.36 | kubevirtci `k8s/1.36`: Kubernetes 1.36.5, base `centos9`, CRI-O 1.36, flannel, kubeadm, systemd cgroup driver, container-selinux [E9] | DOCUMENTED |
| virt-launcher userland | Built on CentOS Stream 9 by default: libvirt `11.10.0-12.el9`, QEMU `10.1.0-20.el9` [E6] | DOCUMENTED |
| Beta features | From v1.9 all Beta feature gates are on by default [E11]; v1.9.0 Beta gates include `PasstBinding` and `Snapshot` [E10] | DOCUMENTED |
| cgroup v1 | Deprecated in v1.9.0, removal planned for the next release [E12] | DOCUMENTED |
| Architectures | Operator install supports x86_64 and Arm64 [E5] | DOCUMENTED |

## 7. Kubernetes compatibility

| Fact | Evidence | Implication |
|---|---|---|
| Maintained upstream minors | 1.37, 1.36, 1.35 [E25] | 1.37 is out (1.37.0 on 2026-08-26) but **not** supported by KubeVirt v1.9 [E4] |
| Current patches | `stable-1.36.txt` = v1.36.5, `stable.txt` = v1.37.1 [E25] | Pin the 1.36 patch at build time |
| End of life | 1.36: 2027-06-28; 1.35: 2027-02-28; 1.34: 2026-10-27 [E25] | 1.34 expires in a month: rejected. 1.36 has the longest window and is the version KubeVirt v1.9 is built for |
| kubeadm packages | Per-minor repositories on `pkgs.k8s.io`; generic Red Hat instructions (dnf, `exclude=` pinning) [E26] | CentOS Stream 9 is a supported install path |
| Privileged API server | kubeadm writes `--allow-privileged=true` into the kube-apiserver manifest by default [E48] | KubeVirt's requirement [E5] is met by default and is inspectable |
| Single node | Remove the control-plane taint for a single-machine cluster [E27] | VMs can schedule on the only node |
| cgroups | cgroup v1 deprecated since Kubernetes 1.35; kubelet does not start on cgroup v1 by default; RHEL 9-like distributions use v2 [E28] | CentOS Stream 9 (cgroup v2) is correct for both Kubernetes and KubeVirt |

## 8. KubeVirt/CDI compatibility tuple

The tuple was chosen as one unit, not component by component: it is the platform KubeVirt's own CI uses for its Kubernetes 1.36 lanes [E8, E9], moved onto an EC2 instance.

| Field | Value | Evidence |
|---|---|---|
| Kubernetes | 1.36 (v1.36.5 observed; pin at build) | [E3, E4, E25] |
| KubeVirt | v1.9.0 | [E1, E2] |
| CDI | v1.66.1 (2026-09-06) | [E13] |
| Node OS | CentOS Stream 9, x86_64, EL9 kernel (5.14 line) | [E6, E7, E30, E31] |
| Container runtime | CRI-O 1.36.x (v1.36.6 on 2026-09-21), systemd cgroup driver, `device_ownership_from_security_context = true` | [E5, E9, E18, E29] |
| Pod network (CNI) | flannel (v0.28.9 current) | [E9, E47] |
| CPU architecture | x86_64 (Intel; every nested-virtualization family is Intel) | [E32] |
| Virtualization | EC2 nested virtualization, KVM as the L1 hypervisor | [E32, E34] |
| CSI | AWS EBS CSI driver (v1.66.0 current), gp3 | [E40, E41] |

**CDI pairing evidence.** No official KubeVirt-to-CDI compatibility matrix exists (also recorded in [ADR 004](../adr/004-kubevirt-vm-destination.md)). What does exist: CDI v1.66.0 added Kubernetes 1.36 CI lanes [E13]; KubeVirt's CI deploys the latest CDI release (kubevirtci `fetch-latest-cdi.sh`, `KUBEVIRT_DEPLOY_CDI=true`) [E9]; KubeVirt v1.9.0 compiles against CDI API types v1.64.0, and DataVolume stays at `cdi.kubevirt.io/v1beta1` [E19]. So v1.66.1 is the best-evidenced choice, and it stays a **candidate** until the Stage 0 runtime validation gate ([feasibility section 3](../stage-0/feasibility.md#3-compatibility-tuple-and-runtime-validation-gate)) passes on the real node.

## 9. Host requirements

What a worker node must provide, from [E5] unless noted, and how the chosen node meets it. `virt-host-validate qemu` is the planned check. It was **not run** in this stage.

| Requirement | Why | How the chosen node meets it | Planned proof (future stage) |
|---|---|---|---|
| CPU virtualization (VT-x) | KVM needs it | EC2 nested virtualization enabled at launch (`CpuOptions NestedVirtualization=enabled`) on a listed family [E32] | `grep -c vmx /proc/cpuinfo` > 0 |
| `/dev/kvm` | QEMU acceleration | Appears only on bare metal or with nested virtualization on; missing means it was not enabled [E34] | `ls -l /dev/kvm`; `virt-host-validate qemu` |
| `/dev/vhost-net` | virtio-net data path | `vhost_net` module of the CentOS Stream 9 kernel | `virt-host-validate qemu` |
| `/dev/net/tun` | Tap devices for VM NICs | `tun` module | `virt-host-validate qemu` |
| Kernel modules | `kvm`, `kvm_intel`, `vhost_net`, `tun`, plus `overlay`, `br_netfilter` for Kubernetes | Standard in the EL9 kernel; loaded explicitly and persisted in `/etc/modules-load.d` | `lsmod` |
| Privileged workloads | virt-handler is a privileged DaemonSet | kubeadm sets `--allow-privileged=true` [E48]; the `kubevirt` namespace gets no restrictive Pod Security label | virt-handler Running |
| Container runtime | containerd or CRI-O [E5] | CRI-O 1.36 (the runtime KubeVirt CI uses [E9]) | `kubectl get nodes -o wide` |
| Block device ownership | CDI writes block PVCs as non-root | CRI-O `device_ownership_from_security_context = true` [E18] | CDI upload to a block PVC succeeds |
| Kernel/userspace alignment | virt-launcher ships EL userland; divergent (especially newer non-EL) kernels are "not recommended" [E5]; upstream builds and tests only EL9 kernels [E7] | CentOS Stream 9: the same distribution base and kernel line as the userland | `uname -r`; boot a VM |
| AppArmor | Host libvirtd profiles can block virt-handler [E5] | Not applicable: CentOS Stream 9 uses SELinux, and no host libvirt is installed | - |
| SELinux | Needs container-selinux >= 2.170.0 [E5] | Enforcing, with container-selinux from the distribution (as kubevirtci installs it [E9]) | `rpm -q container-selinux`; no AVC denials |
| cgroups | cgroup v2 required in practice [E12, E28] | CentOS Stream 9 default is cgroup v2 | `stat -fc %T /sys/fs/cgroup` = `cgroup2fs` |
| CPU architecture | x86_64 or Arm64 [E5] | x86_64 | `uname -m` |
| Emulation fallback | `useEmulation: true` exists for hosts without KVM [E5] | **Not used.** If `/dev/kvm` is missing, the build stops instead | - |

## 10. EKS feasibility

The question was not "does EC2 support KVM" but whether an EKS worker architecture meets every row of section 9. Findings:

| Aspect | Finding | State |
|---|---|---|
| Kubernetes version | EKS standard support offers 1.36, 1.35, 1.34; 1.36 on EKS since 2026-06-02 [E35] | Met |
| Privileged API server | The EKS control plane is managed, so the `--allow-privileged` flag cannot be inspected. EKS's default Pod Security Admission level is `privileged` for all namespaces [E38] | INFERRED met |
| `/dev/kvm` on workers | Needs the node's launch template to set `CpuOptions NestedVirtualization=enabled`. The EKS list of settings prohibited in managed-node-group launch templates (subnet, IAM instance profile, shutdown/hibernate behaviour) does not include CPU options [E36]. AWS does not document EKS + nested virtualization + KubeVirt as a path. | UNKNOWN until tested |
| Nested virtualization | Same instance families as plain EC2 [E32] | Available |
| Privileged DaemonSets | Allowed by the default PSA level [E38] | INFERRED met |
| Node OS / kernel | EKS-optimized AMIs are Amazon Linux, Bottlerocket, Ubuntu and Windows [E37]; none is Enterprise Linux. KubeVirt upstream builds on CentOS Stream 9 and validates only EL9 host kernels; non-EL hosts are outside upstream CI [E7] | **Not aligned** without a custom AMI |
| Kernel / module control | Possible on AL2023 and Ubuntu, restricted on Bottlerocket; a custom EL9 node AMI would be self-built and self-bootstrapped | Possible, at high effort |
| Networking | Amazon VPC CNI gives each pod a VPC address from an ENI [E39]. Masquerade works with any CNI (INFERRED), but VPC CNI is not a KubeVirt CI platform | Workable, untested upstream |
| Storage | EBS CSI driver available (as an add-on or self-installed) [E40] | Met |
| Multus | Not needed by the chosen network model (section 13) | N/A |
| KubeVirt / CDI install | Operator manifests; nothing EKS-specific documented | INFERRED workable |
| Cost | Adds USD 0.10 per cluster-hour in ap-south-1 [E44], about 42% on top of the single node (section 22) | Higher |

**Conclusion.** EKS is **not rejected**: it may well run KubeVirt on nested-virtualization nodes. But it meets the kernel-alignment requirement only through a custom EL9 node image, which removes most of the benefit of a managed node group. Its `/dev/kvm` path is undocumented, its CNI is outside KubeVirt's CI, and it costs more. EKS is therefore **DEFERRED** to a later comparison stage.

## 11. Self-managed Kubernetes feasibility

| Aspect | Finding | State |
|---|---|---|
| Bootstrap | kubeadm 1.36 from `pkgs.k8s.io`, Red Hat instructions [E26]; single-node taint removal [E27] | Met |
| Node OS | CentOS Stream 9 official AMI, x86_64, ap-south-1 `ami-0e7930d02f47291cb` on 2026-09-28, login user `ec2-user` [E31]; EOL 2027-05-31 [E30] | Met (re-resolve the AMI at build) |
| Kernel control | Full: the kernel is EL9, matching virt-launcher [E6, E7]; kernel updates are controlled by us | Met |
| KVM availability | Nested virtualization at launch on `m8i.xlarge` [E32] | Met on paper; prove at build |
| Privileged workloads | kubeadm default `--allow-privileged=true` [E48] | Met |
| Runtime | CRI-O 1.36 from the `isv:cri-o` stable v1.36 repository [E29] | Met |
| Networking | flannel, as in KubeVirt CI [E9]; pod network plus masquerade needs nothing else | Met |
| Storage | EBS CSI driver self-installed, IAM through an instance profile (no static keys) [E40] | Met |
| Observability | kubectl, virtctl, node journal, VMI status; no monitoring stack needed for the first migration | Sufficient |
| Teardown | Two ownership domains (corrected 2026-09-30, review R1). **Terraform-managed AWS infrastructure** (VPC, subnet, internet gateway, route table, security group, instance profile, the instance and its root volume) is destroyed through the Terraform state. **EBS volumes created by the EBS CSI driver** (the VM disk, the CDI scratch volume) are **not** in the Terraform state; they are deleted through Kubernetes before the destroy and checked for afterwards. Ordered sequence: section 29.1 | Simple, but ordered |
| Terraform suitability | All resources are plain EC2/VPC/IAM resources; nested virtualization is a launch CPU option | Suitable (ADR 002 requires Terraform) |

**Conclusion.** Self-managed kubeadm on EC2 meets every requirement in section 9 that can be settled on paper. It reproduces the exact platform KubeVirt tests on, and its only unproven element, `/dev/kvm` through nested virtualization, is shared with EKS.

## 12. Target platform decision

Recorded in [ADR 007](../adr/007-kubevirt-target-platform.md).

**Chosen target for the first KubeVirt migration:** one EC2 instance, `m8i.xlarge` (4 vCPU, 16 GiB, Intel, nested virtualization enabled), in **ap-south-1**, single AZ, running CentOS Stream 9 with a single-node kubeadm Kubernetes 1.36 cluster, CRI-O 1.36, flannel, the EBS CSI driver, KubeVirt v1.9.0 and CDI v1.66.1. Built and destroyed with Terraform (ADR 002). Not a claim about production suitability.

| Alternative | Outcome | Reason |
|---|---|---|
| EKS with nested-virtualization nodes | DEFERRED | Section 10: kernel alignment needs a custom AMI; `/dev/kvm` path undocumented; +USD 0.10/h |
| Local VMware-hosted Kubernetes | Rejected as the primary target | See below |
| Bare-metal EC2 (`m7i.metal-24xl`, USD 5.0904/h in ap-south-1 [E42]) | Fallback only | About 23 times the chosen instance's cost. Used only if nested virtualization fails, and only after a new decision |
| `m7i.xlarge` (USD 0.2121/h) | Alternate instance | Same shape and also listed [E32]; used if `m8i` is unavailable. 8th-generation Intel has had nested virtualization since the February 2026 launch; 7th generation since June [E33] |
| Multi-node cluster | DEFERRED | Nothing in a single cold migration needs a second node; live migration is deferred |

**Why local VMware-hosted Kubernetes is not the primary target:**

- A Kubernetes node on ESXi would run KubeVirt guests four layers deep (Windows, ESXi, node VM, guest). Stage 1B/1G showed L3 is already only functional.
- The laptop has about 6 GiB of free Windows memory and ESXi is at 11.3 of 16 GB used (H1). A 16 GiB node does not fit.
- ADR 002 already fixed AWS as the disposable target, and VMnet8 is not reachable from AWS.
- Keeping the VM on VMnet8 would make keeping .31 technically possible, which is exactly the artificial IP preservation this stage must not design around.

## 13. Network architecture

Analysis of every current binding [E20, E21, E22, E10]. "Static guest IP" means the guest could keep a self-configured address; "reachable" is a separate property.

| Property | Pod network + masquerade | Pod network + bridge | Multus secondary + bridge | Pod network + passt (core `passtBinding`) |
|---|---|---|---|---|
| Guest IP allocation | DHCP from virt-launcher: `10.0.2.2/24` by default, gateway `10.0.2.1` (from `vmNetworkCIDR` default 10.0.2.0/24) | The pod IP is delegated to the guest by DHCP; the pod keeps no IP | From the NAD's IPAM, or static in the guest if the NAD has no IPAM | DHCP from passt; the guest gets the pod's address (INFERRED from the documented IP-sync behaviour) |
| NAT | Yes, nftables SNAT/DNAT in the pod, to and from the pod IP | No | No | Yes, userspace L2-to-L4 translation |
| External reachability | Through a Service to the pod IP, then DNAT to the guest | Pod IP (CNI-dependent) | Whatever the L2 network reaches | Through a Service |
| Static guest IP | No (DHCP expected) | No (must match the pod IP) | Possible | No |
| MAC control | `macAddress` settable (guest-side only) | Settable, but some CNIs reject custom MACs | Passed to the CNI; bridge and OVS support it natively | - |
| Live migration | Allowed; reach the VM through a Service because the pod IP changes | **Not allowed** on the pod network | Depends on the network; not assumed | Supported; guest keeps its old IP until it renews |
| CNI dependency | Any CNI | CNI must tolerate the MAC move; Istio-type tools break | Needs a CNI plugin for the secondary L2 (bridge, OVS; not macvlan/ipvlan) | Any CNI |
| Multus dependency | None | None | **Required**, plus NetworkAttachmentDefinitions | None |
| AWS suitability | Good: VM traffic leaves as the pod/node address, which the VPC accepts | Workable, but the VM gets a pod IP anyway | **Poor**: a VPC only accepts addresses assigned to an ENI from the subnet range, and source/destination checks drop others [E46]. A guest-chosen address such as .31 is not deliverable | Good |
| Suits first cold migration | **Yes** | Weak (no benefit over masquerade, loses live migration) | No (needs Multus, NADs, an L2 design and ENI IP management) | Possible, but a Beta feature with 250 Mi extra memory per VM |
| Complexity | Low | Low to medium | High | Medium |

**Decision ([ADR 008](../adr/008-kubevirt-network-model.md)): pod network + masquerade, one interface, `model: virtio`, with an explicit port list (80, 22).** No Multus is installed because this model does not need it.

The two ports serve different purposes (clarified 2026-09-30, review R4):

- **Port 80** is reached externally through the NodePort Service (30080) for HTTP validation.
- **Port 22** is declared only so that guest management over the Kubernetes API path (`virtctl ssh` or `virtctl port-forward`) can reach the guest's sshd inside the pod. No Service exposes it, and the AWS security group does not open it.

See section 29.4.

**What 10.0.2.0/24 is, and what it is not** (clarified 2026-09-30):

- 10.0.2.0/24 is the masquerade binding's **guest-side network**, inside the VM's own virt-launcher pod. The binding puts the gateway 10.0.2.1 in the pod and hands the guest 10.0.2.2 by DHCP; traffic leaves the pod only after NAT to the pod IP (CURRENT UPSTREAM DOCUMENTATION [E20, E21]).
- It is **not** an AWS VPC subnet, not a Kubernetes pod or Service range, and not a network that VMs share. Nothing outside the pod routes to 10.0.2.2.
- "Guest = 10.0.2.2/24" therefore does **not** mean that all VMs in the cluster sit on one global L2 segment and compete for one global 10.0.2.2. With several VMs, each has its own 10.0.2.0/24 inside its own pod, so each guest can be 10.0.2.2 without conflict. Clients and other VMs reach a VM through its pod IP or a Service, never through 10.0.2.2. (ENGINEERING INFERENCE from the documented per-pod masquerade design and the Kubernetes pod network model; to be observed when more than one VM runs.)
- 10.0.2.2 is the address the guest sees, not a cluster-wide identity. A VM is identified by its VMI and pod, not by 10.0.2.2.

Traffic paths (INFERRED from [E20, E21]; to be observed on the node):

- **Outbound:** guest 10.0.2.2 -> virt-launcher pod (SNAT to the pod IP, flannel range) -> node (flannel masquerade to the node's VPC private IP) -> internet gateway (public IPv4). DNS: the virt-launcher DHCP response is expected to carry the pod's resolver, which is cluster DNS (CoreDNS). INFERRED.
- **Inbound HTTP validation:** operator workstation -> node public IPv4 on a fixed NodePort (30080), allowed only from the operator's /32 -> Service -> pod IP:80 -> DNAT -> guest 10.0.2.2:80.
- **Management:** SSH to the node from the operator /32; the Kubernetes API through an SSH tunnel; the guest through `virtctl console`, `virtctl vnc`, and `virtctl ssh` or `virtctl port-forward`, all over the API. Guest management never uses the NodePort (section 29.4).

## 14. Network IP continuity decision

**192.168.50.31 cannot survive the migration, and the design does not try to keep it.** Four independent reasons:

1. **Different network.** .31 lives on VMnet8, a NAT network inside VMware Workstation on the laptop. Nothing in AWS can route to it or extend it.
2. **The binding assigns the address.** Masquerade hands the guest 10.0.2.2 by DHCP; a static .31 in the guest would not match the pod's NAT and would be unreachable [E20, E21].
3. **The VPC rejects foreign addresses.** An ENI carries only addresses from its subnet range, and source/destination checking drops traffic for other addresses [E46]. Carrying .31 would need a purpose-built 192.168.50.0/24 VPC, secondary ENI addresses and Multus bridging: all artifice, and still not the same network.
4. **The source keeps running.** The first migration is a cold copy with the source left on as the reference and rollback. The same address on both would be a conflict, even in theory. More precisely (added 2026-09-30, review R8), it is a cold, point-in-time migration of the Stage 1E copy, with no cutover (section 29.8).

**What replaces IP continuity:**

| Continuity type | Mechanism |
|---|---|
| Service address | A Kubernetes Service (ClusterIP inside the cluster, NodePort 30080 for the validation client) survives VM restarts and pod IP changes [E20] |
| Client-facing name | DEFERRED: no DNS name in the first migration. The validation client uses node-public-IP:30080 |
| Workload identity | Proven by content, not by address: filesystem UUIDs, nginx package/config hashes, HTTP 200, page sha256 `b9826e18...0046`. The guest is unchanged except for the enumerated migration and preparation changes (corrected 2026-09-30, review R2; section 29.2) |
| Guest address | Changes from 192.168.50.31 (static) to 10.0.2.2 (DHCP, inside the pod). Recorded as an **infrastructure identity** change |

## 15. Guest network remediation design

Recorded in [ADR 010](../adr/010-migration-network-remediation.md). Requirements: no dependency on VMXNET3 or the VMware interface name, suitable for VirtIO, persistent, and consistent with masquerade (DHCP).

**DESIGN ONLY. Not applied to any disk in Stage 1H.** Target content of `/etc/netplan/50-cloud-init.yaml` (owner root:root, mode 0600, the file the guest already uses):

```yaml
# DESIGN (Stage 1H) - KubeVirt target network config for legacy-source-vm.
# Match by driver so the config does not depend on the interface name or MAC.
# Address, route and DNS come from the KubeVirt masquerade DHCP server.
network:
  version: 2
  ethernets:
    primary:
      match:
        driver: virtio_net
      dhcp4: true
      dhcp6: false
```

| Property | How the design meets it |
|---|---|
| VMXNET3 independence | No `vmxnet3` or `ens192` reference; the match is the driver the target provides |
| VirtIO suitability | `virtio_net` is the driver of KubeVirt's `model: virtio` NIC; Stage 1G proved driver matching works (`[Match] Driver=virtio_net`) |
| Persistence | A normal netplan file in the guest image, not a runtime tweak |
| No VMware naming | No name match, no `set-name`, no MAC match (the MAC changes unless set) |
| Chosen network model | DHCP, as masquerade expects [E20] |

How and where it is applied (a future, separately approved stage): offline with guestfish or virt-customize, on a **new disposable copy** of the virt-v2v output, on `conversion-host-01`. Never on the golden artifact, the working copy or the kept Stage 1G images. The prepared image must pass the pre-transfer boot test on `conversion-host-01` before it leaves the lab (added 2026-09-30, review R5; section 29.5). Known limits: with more than one virtio NIC the match would configure all of them (fine for the single-NIC design). The inert `ens192` in `/etc/cloud/cloud.cfg.d/90-installer-network.cfg` is left alone because cloud-init is disabled.

## 16. Storage architecture

Recorded in [ADR 009](../adr/009-kubevirt-storage-model.md).

| Item | Decision | Evidence |
|---|---|---|
| Provisioner | AWS EBS CSI driver (`ebs.csi.aws.com`), installed by us on the self-managed cluster; IAM through the instance profile with `AmazonEBSCSIDriverPolicyV2`; IMDSv2 with hop limit 2 so the driver pods can reach instance metadata | [E40] |
| Volume type | gp3: 3,000 IOPS and 125 MiB/s baseline included, 1 GiB to 64 TiB | [E41] |
| StorageClass (design) | `type: gp3`, `encrypted: "true"` (added 2026-09-30, review R7), `volumeBindingMode: WaitForFirstConsumer`, `reclaimPolicy: Delete`, `allowVolumeExpansion: true` | INFERRED design; `encrypted` defaults to `false` in the driver [E50] |
| Encryption at rest | Every CSI-created volume (VM disk and CDI scratch) is encrypted through the StorageClass parameter, not through an assumed default (added 2026-09-30, review R7; section 29.7) | [E50] |
| Volume mode | **Block** for the VM disk: KubeVirt consumes the raw device directly, with no `disk.img` file or filesystem overhead [E23] | [E23, E40] |
| Scratch space | CDI always requests scratch as **Filesystem, ReadWriteOnce**, and upload always needs scratch; the same gp3 class serves both modes | [E17] |
| Access mode | ReadWriteOnce. EBS is RWO and AZ-scoped; the VM is therefore not live-migratable, which is accepted for a cold migration | [E22], ADR 002 |
| Disk bus | `virtio` (proven in Stage 1G; KubeVirt's standard bus) | [E23] |
| Size | 40 GiB, exactly the source's virtual size (42,949,672,960 bytes). Never smaller. Keeping it equal avoids CDI growing the virtual disk on import [E15] | Stage 1G |
| Import mechanism | CDI upload DataVolume (`source: upload`), filled by `virtctl image-upload` | [E14, E16] |
| Lifecycle | A standalone DataVolume, not a `dataVolumeTemplate`. CDI creates the PVC for it and manages it through the DataVolume [E55]; the VM only references that PVC, so deleting the VM does not delete the migrated disk. Deleting the disk is therefore a deliberate teardown step: delete the DataVolume, then verify that the PVC, the PV and the EBS volume are gone. The EBS volume is outside the Terraform state (added 2026-09-30, review R1; clarified 2026-09-30; section 29.1) | [E23, E55] |
| CRI setting | `device_ownership_from_security_context = true` in CRI-O, required for CDI on block PVCs | [E18] |

**Cold versus live migration.** Live migration needs a shared ReadWriteMany volume and rules out pod-network bridge binding [E22]. The first migration is a cold copy of a powered-off disk into a new VM, so it needs neither shared storage nor live migration. The design is deliberately not shaped around live migration. RWX storage (EFS, or a clustered block solution) is DEFERRED.

## 17. Disk-format decision

| Stage of the path | Format | Why |
|---|---|---|
| Input (golden, read only) | VMDK: vmfs descriptor + 40 GiB flat extent | What cold acquisition produced (Stage 1E). Never converted in place |
| Conversion output / transfer format | **qcow2** (virt-v2v `-of qcow2`, then remediation and agent install on a copy) | Guest-aware conversion is required (netplan, VMware Tools, first-boot jobs). qcow2 carries only allocated data: about 2.7 GiB to move instead of 40 GiB. CDI accepts qcow2 for upload and import [E14] |
| Target representation | **raw on a Block-mode PVC** | CDI converts every supported format to raw [E14, E15]; KubeVirt reads raw block devices directly [E23] |

**What "raw at rest" means here** (clarified 2026-09-30):

- On a Block PVC there is no raw file. CDI writes the guest disk bytes directly onto the EBS block device.
- Along the path, only the **container** changes: VMDK, then qcow2, then no container at all.
- The guest's partition table and filesystems (GPT, the vfat ESP, the ext4 root with the same UUIDs) travel as they are. **No guest filesystem is converted.**
- The only guest-content changes are the enumerated ones in section 29.2.
- EBS bills the provisioned 40 GiB whatever the guest has allocated. The thinness of qcow2 exists only in transit (INFERRED).

**The uploaded qcow2 must be standalone** (added 2026-09-30):

- It must have no backing file: `qemu-img info --backing-chain` must show exactly one image.
- An overlay would carry only its own clusters.
- Stage 1F recorded this check for the input VMDK (no backing file). The check has **not** yet been recorded for the virt-v2v output or for a prepared image, so that evidence is pending future image preparation (section 29.2).

Not chosen:

- **VMDK straight into CDI.** CDI accepts VMDK [E14], but a direct import would skip the guest adaptation that Stage 1G showed is required. The vmfs descriptor plus flat extent pair is also not a single upload file (NOT TESTED).
- **raw as the transfer format.** It is 40 GiB to move and gives no advantage, since CDI converts anyway.
- **A qcow2 kept on a filesystem PVC.** KubeVirt filesystem PVCs need a raw `disk.img` [E23].
- **A containerDisk.** It is ephemeral, and a migrated server needs persistent storage [E23].

## 18. CDI workflow

Design, in order. Nothing was run.

1. **Prepare the image** (future stage, on `conversion-host-01`):
   - Copy the kept virt-v2v output.
   - Apply the section 15 netplan design and the section 19 agent install to the copy.
   - Run `qemu-img check`, sha256 the result and make it read-only.
   - Confirm the result is a standalone qcow2 (section 17).
   - Write the preparation record of section 29.2 (added 2026-09-30, review R2).
2. **Pre-transfer boot test** (added 2026-09-30, review R5): a mandatory gate. Boot the exact prepared qcow2 once on `conversion-host-01` as defined in section 29.5, and transfer nothing until it passes.
3. **Transfer**: move the qcow2 (about 2.7 GiB) to the node over SSH and verify the sha256 on both ends.
   - The route (directly from the conversion host, or through Windows with only about 5.8 GiB free) is a Stage 1I detail (DEFERRED).
   - Any route must meet the mandatory constraints of section 29.6 (added 2026-09-30, review R6).
   - Inbound transfer into AWS carries no data-transfer charge (INFERRED from AWS pricing practice; not priced here).
4. **Upload** on the node, so the upload proxy is never exposed: `kubectl port-forward -n cdi service/cdi-uploadproxy 8443:443` [E16], then `virtctl image-upload dv legacy-source-vm-disk --size=40Gi --volume-mode=block --access-mode=ReadWriteOnce --storage-class=<gp3 class> --image-path=<qcow2> --uploadproxy-url=https://127.0.0.1:8443 --insecure --force-bind` (flags from the v1.9.0 source [E49]; `--force-bind` avoids waiting for a consumer under `WaitForFirstConsumer`).
5. **CDI processing**: an upload server receives the qcow2 into Filesystem scratch space, `qemu-img` converts it to raw onto the Block PVC, and the scratch PVC is removed [E17]. Confirm that the scratch PVC is actually gone (added 2026-09-30, review R1). If a scratch volume is created, record its EBS volume ID from its PV while it exists (clarified 2026-09-30; section 29.1).
6. **Verify**: DataVolume phase `Succeeded`, PVC `Bound`, size 40Gi, `volumeMode: Block`. Record the EBS volume ID of the migrated disk from its PV (clarified 2026-09-30; section 29.1).
   - `Succeeded` proves that CDI finished writing. It does **not** prove that the right image was imported, or that the guest workload is correct (clarified 2026-09-30).
   - That proof comes from two further checks:
     - the artifact check before upload: the file's sha256 equals the preparation record;
     - the guest-level checks of section 21, run after boot.
7. **VM**: a `VirtualMachine` referencing the PVC with `bus: virtio`, EFI with `secureBoot: false`, 2 vCPU / 4096 Mi (from the `.vmx`, not the virt-v2v defaults), one masquerade interface, `runStrategy: Manual` so start and stop are explicit.
   - Machine type, CPU model and EFI variable-store persistence are left at KubeVirt's defaults.
   - The values actually applied are **recorded at runtime**, not treated as fixed design values (clarified 2026-09-30).
   - **Disk lifecycle** (clarified 2026-09-30). The chain is: `VirtualMachine` -> references the standalone PVC -> the PVC is managed by the standalone DataVolume from step 4 -> the EBS volume behind its PV. The VM does **not** own the migrated disk's lifecycle; the standalone DataVolume is the lifecycle object for the migration disk. CDI's completed-DataVolume garbage-collection setting was removed in v1.62 [E56], so the DataVolume is expected to remain after `Succeeded` (ENGINEERING INFERENCE; to be observed). The disk is removed only by deliberately deleting the DataVolume in teardown, followed by verification that the PVC, the PV and the EBS volume are gone (section 29.1).
8. **Runtime**: virt-launcher pod -> libvirt -> QEMU with `/dev/kvm` -> Ubuntu -> nginx.
9. **Evidence and teardown** (added 2026-09-30, review R1): capture the evidence, delete the qcow2 from the node, and tear down in the order of section 29.1.

## 19. Guest-agent strategy

| Question | Answer |
|---|---|
| Required for boot? | No. KubeVirt calls the guest agent "an optional component" [E24]; Stage 1G booted without it |
| What it adds | The VMI condition `AgentConnected`, guest OS info and guest-reported interfaces in `status`, and the `guestosinfo`, `userlist` and `filesystemlist` subresources [E24] |
| Needed for the first migration? | No. It is an extra, non-blocking observation. The pass/fail checks (section 21) do not depend on it |
| Offline install without internet on first boot? | Yes, by design: install it before import |
| Install during conversion? | Yes: on a disposable copy of the virt-v2v output. Fetch `qemu-guest-agent` and any missing dependencies as `.deb` files on `conversion-host-01` (the same Ubuntu 24.04 release) with `apt-get download`, upload them into the image, and run `dpkg -i` offline with virt-customize (guestfs-tools 1.52.0 is installed, ADR 006). Then delete the virt-v2v `guestfs-firstboot` scripts that run `apt-get update`/install and start the agent, so first boot never touches the network for packages. Refined 2026-09-30 (review R2): see the notes below this table |
| Install offline before import? | Yes, that is the same step: the image leaves the conversion host with the agent installed and no pending first-boot package work |
| How KubeVirt detects and uses it | Through the QEMU guest-agent virtio-serial channel (virt-v2v's own XML also declares `org.qemu.guest_agent.0`); presence is reported as `AgentConnected` [E24]. That the channel is added automatically is INFERRED |

Rule kept: no agent installation depends on uncontrolled internet access at first boot, and nothing is installed into the source VM or the kept Stage 1G images.

**Refinements to the install step** (added 2026-09-30, review R2):

- **Remove all five first-boot scripts** named in the Stage 1G record (section 14): `5000-0001-wait-online`, `5000-0002-setenforce-0`, `5000-0003-install-qga`, `5000-0004-setenforce-restore`, `5000-0005-start-qga`. Removing only the apt scripts would leave the 30-second wait-online script.
- **Also remove the `guestfs-firstboot` service** with its enablement links, and `firstboot.sh`. All of these were added by virt-v2v, and none exists in the source.
- **"Offline" refers to the guest only.** The guest never needs network access for this install; `conversion-host-01` does need access to the Ubuntu archive for `apt-get download`.
- **Stop rule.** Record the dependency set after a dry run against the guest's own package state (U8). If installing it would upgrade packages already installed in the guest, stop for a human decision rather than silently widening the guest change.
- The installed package set is an intended guest change recorded in the preparation record (section 29.2).

## 20. First-migration architecture

End to end (see [stage-1h-migration-data-path.svg](../diagrams/stage-1h-migration-data-path.svg) and [stage-1h-target-platform.svg](../diagrams/stage-1h-target-platform.svg)):

ESXi `legacy-source-vm` -> cold acquisition (Stage 1E, done) -> golden VMDK on Windows (read only) -> working copy on `conversion-host-01` (immutable) -> virt-v2v guest-aware conversion to qcow2 (Stage 1G, done) -> disposable copy with netplan remediation and offline guest agent (future) -> pre-transfer boot test on `conversion-host-01` (future gate, section 29.5) -> transfer to the EC2 node -> CDI upload DataVolume -> raw Block PVC on EBS gp3 -> `VirtualMachine` -> virt-launcher pod -> QEMU/KVM on `/dev/kvm` (nested virtualization) -> Ubuntu 24.04 -> nginx.

Network path (see [stage-1h-network-model.svg](../diagrams/stage-1h-network-model.svg)): guest virtio NIC (DHCP 10.0.2.2) -> masquerade binding in the virt-launcher pod (**NAT here**) -> pod network (flannel) -> node ENI (VPC private IP) -> public IPv4. The original VMware IP 192.168.50.31 stays on VMnet8 with the running source. **IP continuity: none, by design.** DNS: cluster DNS for the guest (INFERRED), no public name (DEFERRED). **External HTTP validation point:** node public IPv4, NodePort 30080, from the operator /32.

**Migration semantics** (added 2026-09-30, review R8):

- This is a **cold, point-in-time migration demonstration** of the Stage 1E copy.
- The source VM has kept running since that copy, and nothing it wrote afterwards is carried.
- There is **no cutover**. The source continues to run independently at 192.168.50.31. Details are in section 29.8.

## 21. Application validation model

The same 12 checks used since Stage 1C, adapted to KubeVirt. Access (corrected 2026-09-30, review R4):

- **Guest shell for checks 1 to 8:** through the Kubernetes API (over the node SSH tunnel), using `virtctl console` (serial), `virtctl vnc`, or `virtctl ssh` / `virtctl port-forward` to the guest's port 22.
- **External HTTP checks:** `curl` from outside to the NodePort.

There is no guest SSH Service: NodePort 30080 is HTTP validation only (section 29.4).

| # | Check | How on KubeVirt | Pass condition |
|---|---|---|---|
| 1 | Boot | VMI phase `Running`; console shows a login prompt | Reaches multi-user target |
| 2 | Mounts | `findmnt /`, `findmnt /boot/efi` | Mounted by UUID, as the baseline |
| 3 | OS identity | `/etc/os-release`, `uname -r` | Ubuntu 24.04.5, kernel `6.8.0-142-generic` |
| 4 | Filesystem UUIDs | `blkid` | Equal to the Stage 1C baseline |
| 5 | Application files | sha256 of the page and nginx config | Equal to the baseline |
| 6 | nginx package | `dpkg -s nginx` | Same version |
| 7 | nginx config | `nginx -t`, config hash | Valid, unchanged |
| 8 | nginx service | `systemctl is-active nginx` | `active` |
| 9 | HTTP 200 | `curl` guest-local, then through the Service | 200 |
| 10 | Page hash | sha256 of the response body | `b9826e18...0046` |
| 11 | Application content | Page marker `p15-stage1c-source-v1` | Present |
| 12 | Network reachability | From outside: operator -> node-public-IP:30080; from the guest: gateway 10.0.2.1, DNS lookup | 200 from outside; gateway reachable |

Extra, non-blocking observations: `AgentConnected`, `guestosinfo`, `systemctl is-system-running` = `running` (no pending first boot).

**Infrastructure identity (expected to change, recorded not failed):** hypervisor and Vmid (ESXi Vmid 2 -> KubeVirt VMI UID), MAC (`00:0c:29:0f:3d:15` -> KubeVirt-generated), disk (PVSCSI `sda` -> virtio `vda`, VMDK -> raw PVC), interface name (`ens192` -> a virtio name), SMBIOS/firmware IDs and NVRAM, IP (192.168.50.31 -> 10.0.2.2 behind the pod IP).

**Workload identity: unchanged except for the explicitly enumerated migration and preparation changes** (corrected 2026-09-30, review R2).

- **Must stay unchanged:**
  - filesystem UUIDs;
  - nginx package and configuration;
  - the validation page and its hash;
  - application state.
- **Also unchanged:** machine-id, SSH host keys and hostname. This is acceptable because the source and target never share a network.
- **The root filesystem is not byte-for-byte unchanged, by design.** virt-v2v and image preparation change it in the ways enumerated in section 29.2, and only in those ways.
- **Any difference outside that list is a finding, not an expected change.**

The original 2026-09-28 wording, which listed the Ubuntu root filesystem content among the things that stay the same, contradicted the design's own guest changes and is superseded.

## 22. AWS resource model

Designed, not provisioned. Region **ap-south-1 (Asia Pacific, Mumbai)**, on-demand Linux, public price files retrieved 2026-09-28 ([E42] published 2026-09-25, [E43] 2026-09-25, [E44] 2026-09-18, [E45] 2026-09-17).

| Resource | Design |
|---|---|
| Network | One VPC, one public subnet in one AZ, internet gateway, route table. No NAT gateway. Proposed ranges: VPC 10.40.0.0/16, subnet 10.40.1.0/24 (added 2026-09-30, review R3; address plan in section 29.3) |
| Security group | Inbound only from the operator's /32: TCP 22 (SSH to the **node's** own sshd, not to the guest) and TCP 30080 (HTTP validation NodePort). The API (6443) is reached through the SSH tunnel. Outbound: all. Guest port 22 is never opened here (clarified 2026-09-30, review R4) |
| Instance | 1 x `m8i.xlarge` (4 vCPU, 16 GiB), `CpuOptions NestedVirtualization=enabled`, CentOS Stream 9 AMI, IMDSv2 required with hop limit 2 |
| Root volume | 50 GiB gp3, **encrypted** (added 2026-09-30, review R7) (OS, container images, the uploaded qcow2). Terraform-managed |
| VM disk | 40 GiB gp3 (dynamic, from the EBS CSI driver), plus a temporary scratch volume of about 40 GiB during import. Both **encrypted** through the StorageClass (review R7). Both **outside the Terraform state** (review R1) |
| IAM | Instance profile with `AmazonEBSCSIDriverPolicyV2` only [E40] |
| Public IPv4 | One (auto-assigned) |
| Lifecycle | Terraform apply for a session, destroy afterwards (ADR 002), in the teardown order of section 29.1, which deletes the CSI-created volumes first and checks for leftovers after the destroy (corrected 2026-09-30, review R1) |

Minimum footprint: 1 node, 4 vCPU, 16 GiB RAM, 90 GiB of gp3 steady state (plus about 40 GiB for the length of the import), nested virtualization (no extra charge [E32]), 1 public IPv4.

**Cost, calculated only from the stated assumptions** (730 hours per month; gp3 at list price with baseline performance; data transfer not priced, since it is expected to be negligible: inbound image and package traffic plus KB-sized HTTP responses):

| Item | Unit price | Per hour | 730 h |
|---|---|---|---|
| `m8i.xlarge` | USD 0.2227/h | 0.2227 | 162.57 |
| gp3 root 50 GiB | USD 0.0912/GB-month | 0.0062 | 4.56 |
| gp3 VM disk 40 GiB | USD 0.0912/GB-month | 0.0050 | 3.65 |
| Public IPv4 | USD 0.005/h | 0.0050 | 3.65 |
| **Total, self-managed** | | **about 0.239** | **about 174.43** |
| EKS control plane (if EKS were used) | USD 0.10/h | +0.1000 | +73.00 |
| Bare-metal fallback `m7i.metal-24xl` instead of `m8i.xlarge` | USD 5.0904/h | +4.8677 | - |

A 4-hour working session costs about USD 0.96, plus the scratch volume for under an hour (about USD 0.005). Left running for a month, it would cost about USD 174, which is why teardown is part of the design.

## 23. Security model

| Area | Design |
|---|---|
| Privileged KubeVirt workloads | virt-handler and parts of CDI run privileged; the whole node is therefore trusted infrastructure. No other workloads, no multi-tenancy |
| Node isolation | One disposable node in its own VPC; nothing else in the account depends on it |
| SSH | A new, dedicated key pair created at build time on the workstation, never committed. Security group limited to the operator /32. Password login off (AMI default) |
| AWS credentials | None in the repository, manifests or the node. Terraform runs with the operator's own credentials (still BLOCKED, see section 26). The node uses its instance profile only. The Docker volume `platform-aws-tools-aws` is untouched |
| Instance metadata | IMDSv2 only; hop limit 2 is needed by the EBS CSI driver [E40], which also lets any pod read the instance role. Mitigation: the role holds only the EBS CSI policy, and the node runs only our workloads |
| RBAC | kubeadm admin kubeconfig kept on the workstation outside Git; no extra users. KubeVirt's default roles unchanged |
| Network exposure | Only 22 (node sshd) and 30080 (HTTP validation) from one /32. The upload proxy is used through `port-forward` on the node and never exposed. Guest management goes through the Kubernetes API, never through a Service (clarified 2026-09-30, review R4) |
| Storage permissions | The EBS CSI policy is scoped to volumes tagged `ebs.csi.aws.com/cluster: true` [E40]. Corrected 2026-09-30 (review R1): the original text said that `reclaimPolicy: Delete` removes the volumes together with the cluster, which is inaccurate. `reclaimPolicy: Delete` acts only when a PVC is deleted while the CSI driver still runs. Terminating the instance leaves CSI-created volumes behind as billed, `available` volumes, outside the Terraform state. They are deleted through their DataVolume before the destroy and verified gone by their recorded volume IDs. After the destroy, that tag is used for detection only: an unrecognized volume is never deleted automatically, because the tag is not unique to this project (clarified 2026-09-30; section 29.1) |
| Encryption at rest | Root volume and all CSI-created volumes encrypted (added 2026-09-30, review R7; section 29.7) |
| Disk artifacts | Every copy of the guest disk (VMDK, qcow2, EBS volume) is sensitive data: it contains SSH host private keys, password hashes, machine identity, logs and application data. Handling rules in section 29.7 (added 2026-09-30, review R7) |
| Secrets | No Kubernetes Secrets with cloud credentials. Kubeconfig, SSH private key and Terraform state stay outside Git (`.gitignore`) |
| SELinux | Enforcing (as in KubeVirt CI [E9]). Any denial is recorded, and the stage stops rather than silently switching to permissive |
| Feature gates | v1.9 enables all Beta gates by default [E11]. Accepted for a disposable lab; disabling unused ones is DEFERRED hardening |
| Guest identity | The migrated guest keeps the source's SSH host keys and machine-id. It never shares a network with the source |

## 24. Decisions

| # | Decision | Value | State |
|---|---|---|---|
| 1 | Kubernetes environment | Self-managed, kubeadm, single node on EC2 | DECIDED (ADR 007) |
| 2 | Kubernetes version | 1.36 (patch pinned at build) | DECIDED |
| 3 | KubeVirt version | v1.9.0 | DECIDED |
| 4 | CDI version | v1.66.1 | DECIDED (candidate until the runtime gate passes) |
| 5 | Node OS | CentOS Stream 9 x86_64 | DECIDED |
| 6 | Container runtime | CRI-O 1.36 | DECIDED |
| 7 | EC2 instance strategy | `m8i.xlarge`, nested virtualization, on demand, single AZ; `m7i.xlarge` alternate; metal only after a new decision | DECIDED |
| 8 | Storage model | EBS CSI, gp3, Block, RWO, 40 GiB, standalone upload DataVolume | DECIDED (ADR 009) |
| 9 | Target disk format | qcow2 in transit, raw on a Block PVC | DECIDED (ADR 009) |
| 10 | Network model | Pod network, masquerade, flannel, no Multus | DECIDED (ADR 008) |
| 11 | Guest network remediation | netplan driver match `virtio_net`, DHCP, offline on a disposable copy | DECIDED (ADR 010) |
| 12 | Guest-agent approach | Offline pre-install at conversion, remove first-boot install, non-blocking | DECIDED |
| - | Pod network CNI | flannel | DECIDED |
| - | Region | ap-south-1 | DECIDED |
| - | SELinux mode | Enforcing | DECIDED |
| - | IP continuity | Not preserved; Service continuity instead | DECIDED |

## 25. Deferred decisions

| Item | Why deferred |
|---|---|
| Live migration and RWX storage | Not needed for a cold migration; EBS is RWO |
| Multus, secondary networks, bridge binding | Not needed by masquerade; poor fit for a VPC |
| passt binding | Beta; no benefit for the first migration |
| Any form of IP preservation | Rejected by design (section 14) |
| DNS name, Route 53, LoadBalancer, Ingress | NodePort from one /32 is enough for validation |
| EKS comparison | Section 10; a later comparison stage |
| Multi-node or HA cluster, multiple AZs | Nothing in the first migration needs them |
| Bare-metal instances | Only if nested virtualization fails |
| Secure Boot on | Not proven in Stage 1G |
| CentOS Stream 10 nodes | When KubeVirt's default userland moves to CS10 |
| MAC preservation, cloud-init enablement, instancetypes/preferences | Not needed |
| Snapshots, backup, Beta-gate hardening, monitoring stack | After the first migration works |
| The route for moving the qcow2 to AWS | Stage 1I detail (section 18). Any route must meet the mandatory constraints of section 29.6 (added 2026-09-30, review R6). S3 staging is not part of this design |
| Terraform code, GitOps, the custom controller (ADR 005), warm migration (ADR 003) | Later stages |
| Production design | Out of scope. Not a claim about production suitability |

## 26. Unknowns

| # | Unknown | How it will be resolved |
|---|---|---|
| U1 | Whether `m8i.xlarge` reports `nested-virtualization` in ap-south-1. AWS says nested virtualization is in all commercial Regions [E33], and the family is sold there [E42], but no `describe-instance-types` call was made | Pre-flight `aws ec2 describe-instance-types` before any launch |
| U2 | KubeVirt stability and performance on EC2 nested virtualization (L2 guests on Nitro) | First boot; AWS itself recommends bare metal for performance-sensitive work [E32] |
| U3 | The EKS nested-virtualization path | Only if EKS is revisited |
| U4 | container-selinux version on current CentOS Stream 9 (needs >= 2.170.0) | `rpm -q` on the node |
| U5 | Guest DNS through masquerade DHCP (resolver handed to the guest) | Observe in the guest |
| U6 | This guest's EFI boot with KubeVirt's OVMF build and fallback loader (proven only with Ubuntu's OVMF) | First boot |
| U7 | The virtio NIC name inside the KubeVirt guest | Irrelevant with the driver match; observe |
| U8 | The offline dependency set of `qemu-guest-agent` for the guest's package state | `apt-get download` plus a dry run on the conversion host |
| U9 | Whether virt-v2v's first-boot scripts skip the agent install when it is already present | Inspect the scripts on the copy; remove them regardless. 2026-09-30: moot for the design. The Stage 1G record shows all five scripts serve the agent install, and the design now removes all five plus the service (section 29.2) |
| U10 | CDI upload under `WaitForFirstConsumer` on a single node with `--force-bind` | First upload |
| U11 | EBS CSI metadata access through flannel with hop limit 2 | Driver logs |
| U12 | Formal KubeVirt-to-CDI compatibility | Not published; the runtime gate decides |
| U13 | Data-transfer charges | Not priced; expected to be negligible |
| U14 | The CentOS Stream 9 AMI ID at build time | Re-resolve from centos.org |
| U15 | **AWS credentials** (ADR 002 blocker) | BLOCKED for any build; not needed for this design stage |

## 27. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | EC2 nested virtualization is new (February 2026) and slower than metal | Functional goals only; metal fallback costed; stop if `/dev/kvm` is missing (no emulation) |
| R2 | CentOS Stream 9 reaches EOL on 2027-05-31 | Disposable lab; plan the CS10 move with KubeVirt |
| R3 | A kernel update on the node could diverge from the virt-launcher userland | Record `uname -r`; do not update the kernel mid-session |
| R4 | Single node is a single point of failure | Disposable; the source of truth is the conversion artifact plus Git |
| R5 | Pods can read the instance role through IMDS (hop limit 2) | Minimal IAM policy; no other workloads |
| R6 | Public exposure of SSH and the NodePort | Operator /32 only; teardown after the session |
| R7 | The guest boots unreachable if DHCP or the netplan design fails | `virtctl console`/`vnc` for diagnosis; the design was proven in principle in Stage 1G |
| R8 | CDI scratch space temporarily doubles storage | Budgeted (section 22) |
| R9 | Forgotten teardown leaks about USD 174 per month | Session checklist; Terraform destroy. Corrected 2026-09-30 (review R1): also the post-destroy check for CSI-created volumes (section 29.1), because the destroy alone does not remove them |
| R10 | SELinux enforcing blocks a component | Record AVC, stop, decide explicitly |
| R11 | All Beta feature gates on by default | Accepted for a lab; hardening deferred |
| R12 | Duplicate guest identity (machine-id, host keys, hostname) | The source and target never share a network |
| R13 | EBS is AZ-scoped; no live migration | Accepted: cold migration only |

## 28. Stage 1I entry criteria

Stage 1I is not defined or started here. Status at the end of Stage 1H:

| Criterion | Status |
|---|---|
| Target environment chosen | Met: section 12, ADR 007 |
| Compatible tuple | Met on paper: section 8 (candidate until the runtime gate) |
| Worker requirements defined | Met: section 9 |
| Node OS chosen | Met: CentOS Stream 9 |
| Hardware virtualization path defined | Met: EC2 nested virtualization, `m8i.xlarge` (U1 open) |
| Network model chosen | Met: masquerade, ADR 008 |
| Guest remediation defined | Met: section 15, ADR 010 |
| IP continuity decision | Met: not preserved; Service continuity (section 14) |
| Storage class/model defined | Met: EBS CSI gp3 Block RWO, ADR 009 |
| Target format | Met: qcow2 transfer, raw on PVC |
| CDI workflow | Met: section 18 |
| Guest-agent strategy | Met: section 19 |
| AWS footprint defined without provisioning | Met: section 22 |
| Source healthy | Met: H1 and final check |
| Golden protected | Met: hashes, size, timestamps and ReadOnly attribute unchanged |
| No Kubernetes/KubeVirt/CDI resources exist | Met: nothing created |
| No migration occurred | Met |

Stage 1I also requires the user's explicit approval, with objective, scope and change boundary written down, and working AWS credentials (U15).

**Added 2026-09-30.** The [Stage 1H architecture review](stage-1h-architecture-review.md) found that the "Met" statuses above were not sufficient on their own, and required corrections review R1 to R8. They are now documented in section 29:

| Criterion (review) | Status |
|---|---|
| Teardown and EBS lifecycle defined (R1) | Defined: section 29.1 (not executed) |
| Guest identity and intended changes defined (R2) | Defined: section 29.2; preparation evidence pending future image preparation |
| Address plan defined (R3) | Defined as proposed design: section 29.3; nothing runtime-confirmed |
| Guest management path defined (R4) | Defined: section 29.4 |
| Pre-transfer boot test gate defined (R5) | Defined: section 29.5 (not executed) |
| Transfer constraints defined (R6) | Defined: section 29.6; route still deferred |
| Encryption and artifact handling defined (R7) | Defined: section 29.7 |
| Point-in-time, no-cutover semantics stated (R8) | Stated: section 29.8 |

Stage 1I remains **not started**. Whether the corrected design is ready for approval is a **human decision**. Documenting these corrections does not approve Stage 1I.

## 29. Post-review corrections (review R1 to R8)

Added 2026-09-30 from the [Stage 1H architecture review](stage-1h-architecture-review.md), section 15, with the user's approval.

- These are documentation corrections. **Nothing in this section was executed.**
- Every sequence, check and value here is a PROPOSED DESIGN for a future, separately approved stage, unless it is labelled otherwise.
- **No value in this section is runtime-confirmed.**
- Labels are as defined at the top of this record.

### 29.1 Review R1: teardown and EBS lifecycle

The original record said that Terraform destroys the instance "and its volumes", and that `reclaimPolicy: Delete` removes the volumes with the cluster. That conflated two different ownership domains.

| Domain | Resources | Created by | Removed by | Basis |
|---|---|---|---|---|
| **Terraform-managed AWS infrastructure** | VPC, subnet, internet gateway, route table, security group, IAM role and instance profile, the EC2 instance and its root volume | `terraform apply` (ADR 002) | `terraform destroy`, which only knows what is in its state | PROPOSED DESIGN (ADR 002) |
| **Kubernetes / EBS CSI-provisioned storage** | The 40 GiB VM disk volume; the roughly 40 GiB CDI scratch volume (normally removed by CDI after the import) | The EBS CSI driver, when a PVC is bound. It tags the volume `ebs.csi.aws.com/cluster = true`; the IAM policy only lets it manage volumes with that tag (or with `kubernetes.io/created-for/pvc/name`) [E40, E51] | Deleting the standalone DataVolume, which removes its PVC, while the driver still runs (`reclaimPolicy: Delete`); otherwise only an explicit deletion of a volume positively identified as this session's | CURRENT UPSTREAM DOCUMENTATION [E51, E55]; ENGINEERING INFERENCE |

Why this matters (ENGINEERING INFERENCE):

- CSI-created volumes are not in the Terraform state, so a destroy neither deletes nor lists them.
- Terminating the instance detaches them.
- EBS volumes are not VPC resources, so nothing blocks the destroy: it completes and the volumes remain, billed as `available`.
- Each leftover holds a copy of the guest disk, which is sensitive data (section 29.7).
- The CSI tags are generic (clarified 2026-09-30). Every EBS CSI driver in the same AWS account and Region applies them, so a tag match alone does not show that a volume belongs to this migration session. Cleanup therefore works from the exact volume IDs recorded during the session, not from a tag scan.

**Session volume record** (PROPOSED DESIGN; clarified 2026-09-30). During the migration session, record the exact EBS volume IDs created for:

- the migrated VM disk, from its PV once the DataVolume has succeeded (section 18, step 6);
- the CDI scratch volume, if one is present, from its PV while it exists (section 18, step 5).

No volume ID exists yet, and none is invented here.

**Disk lifecycle** (clarified 2026-09-30). The `VirtualMachine` references the standalone PVC, and the PVC is managed by the standalone DataVolume. The VM does not own the migrated disk's lifecycle: the DataVolume is the lifecycle object. The normal workflow is to delete the DataVolume deliberately, then verify that the PVC and PV are gone, then verify that the underlying EBS volume is deleted. Deleting the PVC directly is not part of the normal workflow (step 3).

**Teardown sequence** (PROPOSED DESIGN; not executed; performed by the operator, and needs the AWS credentials that are still BLOCKED, U15):

1. **Capture validation evidence.** Record, as text:
   - the 12 check results and the recorded KubeVirt runtime defaults;
   - VMI status and conditions, and events;
   - DataVolume, PVC and PV descriptions, including the recorded session volume IDs.

   Never capture disk content.
2. **Stop and delete the KubeVirt workload.** Stop the VM, then delete the `VirtualMachine` and the validation Service. This does not delete the migrated disk, because the VM does not own it.
3. **Delete the migration disk through its DataVolume.**
   - Deliberately delete the standalone DataVolume. Its PVC is removed with it, and with `reclaimPolicy: Delete` the EBS CSI driver then deletes the PV and the EBS volume (ENGINEERING INFERENCE from [E55] and the StorageClass design; verified in step 4).
   - If the PVC is still present after the DataVolume is gone, record that as a finding, then delete the PVC deliberately. This is an exception path, not an equivalent alternative.
4. **Verify that the PVC, the PV and the known EBS volumes are gone** (mandatory before step 5):
   - the migration PVC no longer exists;
   - its PV no longer exists;
   - each recorded session volume ID (VM disk, and scratch if recorded) is reported deleted by AWS;
   - no scratch PVC or PV remains.

   Do not run the Terraform destroy until all of these hold.
5. **Run the Terraform destroy** for the infrastructure.
6. **Run the post-destroy EBS check** (mandatory; **detection only**):
   - List volumes in the account and Region tagged `ebs.csi.aws.com/cluster = true` or `kubernetes.io/created-for/pvc/name`.
   - Confirm that none of the recorded session volume IDs still exists.
   - Confirm that the root volume went with the instance.

   This step deletes nothing. Expected result: no volume belonging to this session.
7. **Handle a detected volume only after positive identification.**
   - Record its ID, size, creation time and tags (no content).
   - Delete it only if it is **positively identified as belonging to this migration session**: its ID is one of the recorded session volume IDs, or the recorded evidence otherwise ties it unambiguously to this session. Record the basis for the identification, delete it, and confirm the deletion.
   - **An unknown or unrecognized EBS volume is NOT deleted automatically**, and not by this procedure at all. It may belong to another cluster in the same account and Region. Record it and stop for a human decision.
   - Never attach a volume to another instance to inspect it.
8. **Delete the temporary qcow2 from the AWS node.**
   - Normally this is already done right after a successful import (section 29.6, item 9).
   - If not, do it before step 5, because after the destroy the node no longer exists. At that point this step reduces to confirming that the encrypted root volume was deleted with the instance.
9. **Retain only intentionally preserved evidence:**
   - text evidence kept outside Git, or redacted per the standing repository rules;
   - no disk content left in AWS;
   - the authoritative disk copies stay in the lab (the golden VMDK, and the prepared qcow2 on `conversion-host-01`).

The goal is unchanged: no orphaned storage and no storage deliberately left billed. The post-destroy verification remains mandatory; it detects, and deletion is limited to volumes positively identified as this session's.

### 29.2 Review R2: guest identity and intended changes

**Definition:** the migrated guest is **unchanged except for the explicitly enumerated migration and preparation changes** below. Anything else that differs is a finding.

| # | Intended change | Introduced by | Evidence status |
|---|---|---|---|
| C1 | open-vm-tools purged: binaries, libraries, plugins, `/etc/vmware-tools/`, `/etc/pam.d/vmtoolsd`, units, rc links, udev rules `60-open-vm-tools.rules` and `99-vmware-scsi-udev.rules` | virt-v2v | PROJECT-DERIVED FACT ([Stage 1G](stage-1g-controlled-conversion.md) section 14, `virt-diff`) |
| C2 | `/etc/initramfs-tools/modules` gains the virt-v2v comment and `bochs`; the initramfs for `6.8.0-142-generic` is rebuilt; the old one is kept as `/boot/initrd.img-6.8.0-142-generic.pre-v2v` | virt-v2v | PROJECT-DERIVED FACT (Stage 1G section 14) |
| C3 | New `/etc/modprobe.d/virt-v2v-added.conf`: `alias scsi_hostadapter virtio_blk` | virt-v2v | PROJECT-DERIVED FACT (Stage 1G section 14) |
| C4 | `/var/lib/dpkg/status` rewritten by the purge. Incidental: `/etc/ld.so.cache`, `/run/blkid`, `/run/needrestart` | virt-v2v | PROJECT-DERIVED FACT (Stage 1G section 14) |
| C5 | The first-boot mechanism that virt-v2v added is removed again: `/usr/lib/systemd/system/guestfs-firstboot.service` with its SysV links, `/usr/lib/virt-sysprep/firstboot.sh`, and its five scripts `5000-0001-wait-online`, `5000-0002-setenforce-0`, `5000-0003-install-qga`, `5000-0004-setenforce-restore`, `5000-0005-start-qga`. **Net effect after preparation: none of these present** | virt-v2v adds; preparation removes | Addition: PROJECT-DERIVED FACT (Stage 1G section 14). Removal: PROPOSED DESIGN; the exact removed-file list is pending future image preparation |
| C6 | `/etc/netplan/50-cloud-init.yaml` replaced with the section 15 content, owner root:root, mode 0600 | Preparation (ADR 010) | Content: PROPOSED DESIGN (section 15). File hash: pending future image preparation |
| C7 | `qemu-guest-agent` and its exact dependency set installed: the files owned by those packages (including their systemd and udev units), plus the dpkg database and dpkg log entries the install causes | Preparation (section 19) | Package names, versions and hashes: **pending future image preparation** (U8). None are invented here |

**Explicitly not intended to change** (PROJECT-DERIVED FACT: checksum-identical after virt-v2v in Stage 1G section 14):

- `/etc/fstab`;
- the GRUB configuration and the ESP loaders;
- `/etc/machine-id`;
- the SSH host keys;
- the hostname;
- the nginx package and configuration;
- `/var/www/html/index.html`;
- the cloud-init disabled marker.

Runtime state written after the guest boots (logs, journal, timestamps) is not an identity change (ENGINEERING INFERENCE).

**Preparation record** (PROPOSED DESIGN; written during future image preparation; **no hash below exists yet, and none is invented**):

- **Input image:** path and sha256 of the virt-v2v output used as input. It must match the kept output's recorded hash `94bc1cd6...91c6` (PROJECT-DERIVED FACT, Stage 1G) before the copy.
- **Output image:**
  - sha256 of the prepared qcow2;
  - the `qemu-img check` result;
  - `qemu-img info --backing-chain` showing exactly one image (standalone, section 17).
- **Netplan:** exact content, sha256, owner and mode of the file placed in the guest.
- **Guest agent:**
  - name, version and sha256 of every `.deb`;
  - the dry-run result against the guest's package state;
  - the dpkg state of those packages afterwards;
  - the stop-rule outcome (section 19).
- **First boot:** the list of removed files as found in the image, and confirmation that none remain.
- **Offline difference:** an offline comparison (for example `virt-diff`, as in Stage 1G) of the virt-v2v output against the prepared image, showing only C5 to C7.
- **Boot test:** the result of the pre-transfer boot test (section 29.5).

### 29.3 Review R3: address plan

**The AWS subnet is intentionally contained within the VPC**: 10.40.1.0/24 lies inside 10.40.0.0/16. That containment is required, not an overlap to avoid (clarified 2026-09-30).

The **independent address domains** must not overlap:

- VPC/subnet address space versus Pod CIDR;
- VPC/subnet address space versus Service CIDR;
- VPC/subnet address space versus the KubeVirt masquerade CIDR;
- Pod CIDR versus Service CIDR;
- Pod CIDR versus the KubeVirt masquerade CIDR;
- Service CIDR versus the KubeVirt masquerade CIDR;
- each of these versus CRI-O's default bridge network.

The masquerade CIDR is a per-VM, guest-side network inside each virt-launcher pod, not a shared subnet (section 13).

Status meanings:

- **default**: an upstream default value;
- **selected for the lab**: this design's choice;
- **proposed**: not yet built;
- **runtime-confirmed**: observed on a running system. **Nothing in this table is runtime-confirmed.**

| Network | Value | Status | Basis |
|---|---|---|---|
| AWS VPC CIDR | 10.40.0.0/16 | Proposed; selected for the lab | PROPOSED DESIGN, chosen to stay clear of every independent domain below (the subnet is carved from it) |
| AWS subnet CIDR (one public subnet, one AZ) | 10.40.1.0/24 | Proposed; selected for the lab | PROPOSED DESIGN |
| Kubernetes Pod CIDR | 10.244.0.0/16 | Default (flannel v0.28.9 `net-conf.json`, VXLAN backend); selected for the lab. kubeadm must be given the same value | CURRENT UPSTREAM DOCUMENTATION [E52] |
| Kubernetes Service CIDR | 10.96.0.0/12 (10.96.0.0 to 10.111.255.255); cluster DNS 10.96.0.10 | Default (kubeadm); selected for the lab | CURRENT UPSTREAM DOCUMENTATION [E53] |
| KubeVirt masquerade `vmNetworkCIDR` | 10.0.2.0/24: gateway 10.0.2.1, guest 10.0.2.2, inside each VM's virt-launcher pod (section 13) | Default; selected for the lab; unchanged from the 2026-09-28 design | CURRENT UPSTREAM DOCUMENTATION [E21] |
| Kept clear of | CRI-O's default bridge network 10.85.0.0/16 [E54]; the lab network 192.168.50.0/24, which is not routed to AWS and is avoided so records stay unambiguous | Constraint | CURRENT UPSTREAM DOCUMENTATION [E54]; PROJECT-DERIVED FACT |

Overlap check (ENGINEERING INFERENCE, by arithmetic):

- The independent domains share no addresses: VPC/subnet 10.40.0.0/16 (containing the subnet 10.40.1.0/24), Pod 10.244.0.0/16, Service 10.96.0.0/12 (up to 10.111.255.255), masquerade 10.0.2.0/24, and CRI-O's bridge 10.85.0.0/16.
- None of them contains 192.168.50.0/24.

Why it matters (ENGINEERING INFERENCE):

- The guest treats 10.0.2.0/24 as on-link. If the node's subnet were, for example, 10.0.2.0/24, the guest could not reach the node's own subnet.
- Pod and Service ranges that overlap the VPC break routing on the node.

**Future pre-flight checklist.** CNI prerequisites and the pod and Service CIDR selections belong in the future implementation pre-flight checklist, which is **not written in this task**. That checklist includes:

- passing the pod CIDR (and, if not the default, the Service CIDR) to kubeadm;
- flannel's configured network matching the pod CIDR;
- `br_netfilter` loaded and IPv4 forwarding enabled;
- confirming which CNI configuration CRI-O actually uses once flannel is installed.

### 29.4 Review R4: guest management path

The original access line in section 21 offered guest SSH via the Service as an alternative to `virtctl ssh`. That was inaccurate: the design has one Service, and it exposes HTTP on NodePort 30080 only.

| Path | Purpose | Transport | Opened in the AWS security group? |
|---|---|---|---|
| Node SSH, TCP 22 on the node's public IPv4 | Node administration, the API tunnel, the transfer target (section 29.6) | SSH to the node's own sshd | Yes, from the operator /32 only |
| Kubernetes API, TCP 6443 | `kubectl`, `virtctl` | Through the node SSH tunnel | No |
| `virtctl console` | Serial console of the guest | Kubernetes API, then KubeVirt to the virt-launcher pod | No |
| `virtctl vnc` | Graphical console, where applicable | Kubernetes API | No |
| `virtctl ssh` or `virtctl port-forward` to guest port 22 | Guest shell over SSH | Kubernetes API forwarding into the virt-launcher pod, then to the guest's port 22 | No |
| **NodePort 30080** | **External HTTP validation only** | Node public IPv4, then Service, then pod port 80, then masquerade DNAT to guest port 80 | Yes, from the operator /32 only |

- Guest port 22 is declared in the masquerade `ports` list so that the API-path forwarding can reach the guest's sshd. That port is **inside KubeVirt's guest networking model**: it is not exposed by the AWS security group and has no Service. That the forwarding needs the port to be declared is ENGINEERING INFERENCE from the documented masquerade behaviour [E20], to be observed at runtime.
- **NodePort 30080 is HTTP validation. It is not guest management SSH.**
- Guest login uses the source guest's own accounts, whose credentials stay outside Git. This design creates no credentials.

### 29.5 Review R5: pre-transfer boot test (mandatory gate)

**This test proves the exact prepared artifact before paid-cloud transfer.** It is a mandatory gate between image preparation and transfer (section 18, step 2). It is **documented only and was not performed**.

| Element | Requirement |
|---|---|
| Where | `conversion-host-01` (ADR 006) |
| What | The exact prepared qcow2 whose sha256 is in the preparation record (section 29.2). It is opened read-only as the backing file of a disposable overlay, as in Stage 1G section 9, so its bytes cannot change. Its sha256 is re-verified after the test and must still equal the record. Any test-harness instrumentation (such as Stage 1G's serial autologin) lives only in the overlay, never in the prepared image |
| Hypervisor | QEMU/KVM, as in Stage 1G |
| Firmware | UEFI with OVMF, Secure Boot off, a fresh copy of the variable-store template for this boot, as in Stage 1G section 7 |
| Disk | virtio-blk |
| Network | virtio-net on QEMU user-mode networking, isolated (`restrict=on`, as in Stage 1G), using its built-in DHCP server; host port forwards for HTTP (and SSH, if used) |
| Guest agent | A virtio-serial port named `org.qemu.guest_agent.0`, the channel name KubeVirt uses |

Pass conditions (all required):

1. The guest reaches the multi-user target.
2. **DHCP netplan works.** The NIC matched by driver `virtio_net` obtains a DHCP lease from the user-mode network and has a default route. The address itself is QEMU's, not the KubeVirt 10.0.2.2, and is not a pass condition.
3. `systemctl is-system-running` reports `running`: no pending first-boot job and no failed unit.
4. **The guest agent responds** on the virtio-serial channel (for example, to a ping command of the agent protocol).
5. nginx answers through the host port forward with HTTP 200.
6. **The page sha256 equals** `b9826e18...0046`.
7. Identity spot checks match the baseline: filesystem UUIDs, machine-id, SSH host key fingerprints. None of the removed first-boot files is present.

Not proven by this test:

- DNS and outbound access (the network is isolated);
- KubeVirt's OVMF build (U6);
- masquerade specifics;
- performance.

On failure:

- Transfer nothing.
- Fix the problem in a new preparation cycle, starting again from the virt-v2v output.
- Never patch the prepared image in place.

Cleanup:

- Delete the overlay, the variable-store copy, and the QEMU sockets and pid files.
- Confirm that no QEMU process remains.
- Record the deletion list.
- The prepared image stays read-only and re-verified.
- Evidence is kept as text outside Git, as in Stage 1G.

### 29.6 Review R6: transfer constraints

The route remains **DEFERRED** to Stage 1I: directly from `conversion-host-01`, or through Windows. **S3 is not part of this design.** Whatever the route, the transfer must satisfy all of the following (PROPOSED DESIGN):

1. **Outbound-only initiation** from the lab side. There is no inbound connection into the laptop, VMnet8 or the lab VMs.
2. **SSH transport** to the node's own sshd (for example `scp` or `rsync` over SSH). There is no public upload endpoint and no exposed CDI upload proxy.
3. **Build-time node key, never committed.**
   - The node holds only the public key.
   - If the transfer starts from a host other than the operator workstation (for example `conversion-host-01`), where any copy of the private key lives is recorded, and that copy is removed at the end of the session.
4. **Operator /32 restriction.** The security group admits only the transfer's source address. Through Workstation NAT, that is normally the operator's public address (ENGINEERING INFERENCE). It is never widened.
5. **SHA-256 verification at both ends.** The hash is taken on the source side (in the preparation record) and recomputed on the node. They must match before any upload.
6. **The authoritative artifact stays on the controlled source side** (read-only on `conversion-host-01`). The transfer never moves or deletes it.
7. **A partial or corrupt destination file is discarded.** A file that is partial or has a mismatched hash is deleted and the transfer repeated. It is never uploaded.
8. **AWS-side handling is explicit.**
   - The qcow2 sits in one recorded path on the encrypted root volume, readable only by the administrative user.
   - No private key is placed on the node.
9. **Deletion after import.** After a successful import (DataVolume `Succeeded`), the qcow2 is deleted from the node, unless it is explicitly retained as evidence (for example, until the guest checks pass). A retained copy is deleted in teardown step 8 (section 29.1) and never outlives the session.

### 29.7 Review R7: encryption and artifact sensitivity

**Encryption at rest** (PROPOSED DESIGN):

- **EC2 root volume:** encrypted at launch.
- **EBS CSI volumes** (VM disk and CDI scratch): encrypted through the StorageClass parameter `encrypted: "true"`.
  - The driver's default is `false` [E50], so the design never relies on the default.
  - With `kmsKeyId` unset, AWS uses the Region's default EBS KMS key [E50].
  - A customer-managed key would need extra KMS permissions for the instance role (ENGINEERING INFERENCE). It is deferred.
- **Account-level EBS encryption by default:** may be enabled as defence in depth, but the design does not depend on it. Its state in the account is unknown and cannot be checked without credentials (U15).

**Disk artifacts are sensitive data** (ENGINEERING INFERENCE from the guest's contents; PROJECT-DERIVED FACT that host keys and machine-id are preserved, Stage 1G). Every VMDK, qcow2 and EBS copy of this guest may contain:

- SSH host private keys (anyone holding a copy can impersonate the server);
- `/etc/shadow` password hashes;
- machine identity (`/etc/machine-id`, hostname);
- logs;
- application data.

Handling requirements:

- Never commit to Git. This is already a standing repository rule; the repository holds no disk, ISO or log artifacts.
- Never place in public or shared artifact storage.
- Restrict access to the operator and the lab hosts that need the copy.
- Verify hashes at every copy (sections 29.2 and 29.6).
- Delete temporary copies deliberately and record the deletion (sections 29.1, 29.5 and 29.6).
- Encrypt cloud storage at rest (above).
- Introduce no credentials. This design introduces none.

### 29.8 Review R8: point-in-time and no-cutover semantics

PROJECT-DERIVED FACT (Stage 1E, Stage 1H H1):

- **The migration source artifact is the Stage 1E point-in-time copy.** It was taken after one graceful guest shutdown, then the VM was powered on again ([Stage 1E record](stage-1e-cold-acquisition.md)).
- **The source VM has kept running since**, and has legitimately written to its disk again. It is still serving 192.168.50.31.

Consequences (ENGINEERING INFERENCE):

- **Nothing written to the source after Stage 1E is included** in the migrated VM.
- **There is no cutover** in this first migration:
  - no address moves;
  - no DNS or client traffic is switched;
  - the source is not stopped;
  - the source is not decommissioned.
- **The source continues to run independently** as the reference and rollback. The migrated VM and the source never share a network (section 23).
- The first migration is therefore a **cold, point-in-time migration demonstration**: a persistent KubeVirt VM created from the Stage 1E copy. It is not a production cutover and not a synchronized migration.
- The validation page hash remains a meaningful check for this static page: the hash was re-verified on the running source at H1 and has not changed since Stage 1C.
- A real cutover would need either a fresh cold acquisition at cutover time, or warm migration. **Warm migration is deferred** (ADR 003).

### 29.9 Related clarifications applied with these corrections

- **CDI `Succeeded` is not proof of a correct guest.** It is not by itself proof that the guest workload image is correct; artifact-level and guest-level validation are still required (section 18, step 6).
- **"Raw at rest" does not mean guest filesystem conversion** (section 17).
- **The uploaded qcow2 must be standalone**, with no backing file (section 17). The evidence is pending future image preparation.
- **"Offline guest preparation" refers to the guest only.** The conversion host needs Ubuntu archive access (section 19).
- **The five virt-v2v first-boot scripts** are named from the Stage 1G record (section 19 and C5 above).
- **KubeVirt defaults are recorded, not fixed.** Machine type, CPU model and EFI variable-store persistence are recorded at runtime, not treated as fixed (section 18, step 7).
- **The pre-flight checklist is future work.** CNI prerequisites and the pod and Service CIDR selections belong in the future implementation pre-flight checklist (section 29.3), which is not written here.

## Gates

| Gate | Evidence | Result |
|---|---|---|
| H1 Repository and lab state | `main` = `origin/main` = `a7aa1f54e7b033f9619a46057063c8a3121796c8` (Stage 1G), clean tree; source HTTP 200, 267 bytes, page sha256 `b9826e18...0046` from Windows and ESXi; Vmid 1 off, Vmid 2 and 3 on, 0 snapshots; golden descriptor and flat hashes, sizes, timestamps and ReadOnly attribute unchanged | PASS |
| H2 Official compatibility | Sections 6 to 8: KubeVirt v1.9.0, Kubernetes 1.34 to 1.36, CDI v1.66.1, runtimes, architecture; one tuple from KubeVirt CI | PASS |
| H3 Host requirements | Section 9, with `virt-host-validate qemu` as the planned (not executed) check | PASS |
| H4 EKS vs self-managed | Sections 10 to 12, with the AWS nested-virtualization list read from AWS docs [E32] and EKS evaluated on its own evidence | PASS |
| H5 Platform decision | ADR 007 | PASS |
| H6 Network analysis | Section 13 (four bindings), section 14 (.31 does not survive), ADR 008 | PASS |
| H7 Guest netplan design | Section 15 (DESIGN only), ADR 010 | PASS |
| H8 Storage and format | Sections 16 and 17, ADR 009 | PASS |
| H9 Guest agent | Section 19 | PASS |
| H10 End-to-end design and documentation | Section 20, three diagrams, this record, index updates, validation, commit | PASS |

## Sources

E1 to E49 retrieved on **2026-09-28**. E50 to E56 retrieved on **2026-09-30** for the post-review corrections (section 29). Local evidence (outside Git): `C:\VMs\conversion-host-01\stage-1h\H1.txt` and `h1.ps1`.

| # | Source (URL) | Title | Exact requirement or fact | Implication |
|---|---|---|---|---|
| E1 | https://github.com/kubevirt/kubevirt/releases | Releases - kubevirt/kubevirt | v1.9.0 published 2026-07-30, promotion of v1.9.0-rc.2; newer only v1.10.0-alpha.0 (pre-release) | Target v1.9.0 |
| E2 | https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt | KubeVirt stable release pointer | Returns `v1.9.0` | Confirms the stable release |
| E3 | https://kubevirt.io/user-guide/release_notes/ | Release notes - KubeVirt user guide | "KubeVirt v1.9 is built for Kubernetes v1.36 and additionally supported for the previous two versions." | Kubernetes 1.34 to 1.36 |
| E4 | https://github.com/kubevirt/sig-release/blob/main/releases/k8s-support-matrix.md | KubeVirt to Kubernetes version support matrix | 1.9: 1.36, 1.35, 1.34; not 1.37 | 1.37 excluded |
| E5 | https://kubevirt.io/user-guide/cluster_admin/installation/ | Installation - KubeVirt user guide | Latest three Kubernetes releases at KubeVirt release time; apiserver `--allow-privileged=true`; runtimes containerd, crio; AppArmor caveats; `virt-host-validate qemu` checks /dev/kvm, /dev/vhost-net, /dev/net/tun; EL-based virt-launcher userland, divergent non-EL kernels not recommended; SELinux needs container-selinux; `useEmulation` fallback | Host checklist (section 9) |
| E6 | https://github.com/kubevirt/kubevirt/blob/v1.9.0/hack/rpm-deps.sh | kubevirt v1.9.0 `hack/rpm-deps.sh` | Default CentOS Stream 9; libvirt `0:11.10.0-12.el9`, QEMU `17:10.1.0-20.el9` | EL9 host kernel is the aligned choice |
| E7 | https://github.com/kubevirt/kubevirt.github.io/blob/main/_posts/2026-09-03-understanding-kubevirt-host-kernel-userspace-dependencies.md | Understanding KubeVirt's Host Kernel and Userspace Dependencies (kubevirt.io blog) | Release images built on CentOS Stream 9; upstream CI runs on EL9 host kernels (5.14); non-EL hosts are not covered by upstream CI (issue #16386) | CentOS Stream 9 nodes; EKS AMIs misaligned |
| E8 | https://github.com/kubevirt/project-infra/blob/main/github/ci/prow-deploy/files/jobs/kubevirt/kubevirt/kubevirt-presubmits-1.9.yaml | KubeVirt release-1.9 presubmit jobs | Lanes on k8s-1.33 to 1.36, incl. sig-compute, sig-network, sig-storage on 1.36 | Kubernetes 1.36 is CI-proven for v1.9 |
| E9 | https://github.com/kubevirt/kubevirtci/tree/main/cluster-provision/k8s/1.36 | kubevirtci `cluster-provision/k8s/1.36` | version 1.36.5; base centos9; CRI-O 1.36; flannel; kubeadm; `cgroupDriver: systemd`; container-selinux; `fetch-latest-cdi.sh` | The tuple mirrors KubeVirt CI |
| E10 | https://github.com/kubevirt/kubevirt/releases/download/v1.9.0/feature-gates.json | v1.9.0 feature-gates.json | `PasstBinding` Beta, `Snapshot` Beta; no `BlockVolume` gate listed | passt is Beta; block volumes not gated |
| E11 | https://github.com/kubevirt/kubevirt.github.io/blob/main/_posts/2026-07-10-Beta-Features-On-By-Default-In-v1-9.md | Beta Features Enabled by Default in KubeVirt v1.9 | All Beta feature gates enabled by default from v1.9 | Security note (section 23) |
| E12 | https://github.com/kubevirt/kubevirt/releases/tag/v1.9.0 | KubeVirt v1.9.0 release notes | cgroup v1 deprecated, removal planned next release | cgroup v2 node |
| E13 | https://github.com/kubevirt/containerized-data-importer/releases | Releases - containerized-data-importer | v1.66.1 2026-09-06 (latest); v1.66.0 2026-08-05 "Update kubevirtci, 1.36 lanes" | CDI v1.66.1 |
| E14 | https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/supported_operations.md | CDI supported operations | Formats qcow2, VMDK, VDI, VHD, VHDX, raw (xz/gz) all converted to raw; sources incl. upload | qcow2 upload, raw target |
| E15 | https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/README.md | CDI README | `kubevirt` content type: convert qcow2 to raw, resize to all available space; NFSv3 not supported | Size PVC = virtual size |
| E16 | https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/upload.md | CDI upload | `cdi-uploadproxy` must be reachable; `kubectl port-forward -n cdi service/cdi-uploadproxy 8443:443`; `virtctl image-upload` | Upload on the node via port-forward |
| E17 | https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/scratch-space.md | CDI scratch space | Upload needs scratch; scratch always Filesystem, RWO | Class must serve Filesystem too |
| E18 | https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/block_cri_ownership_config.md | device_ownership_from_security_context CRI configurable | Required for block PVCs; CRI-O `[crio.runtime] device_ownership_from_security_context = true` | CRI-O setting |
| E19 | https://github.com/kubevirt/kubevirt/blob/v1.9.0/go.mod | kubevirt v1.9.0 go.mod | `kubevirt.io/containerized-data-importer-api v1.64.0` | DataVolume API compatibility evidence |
| E20 | https://kubevirt.io/user-guide/network/interfaces_and_networks/ | Interfaces and Networks - KubeVirt user guide | Bindings bridge, sriov, masquerade (nftables NAT), passtBinding; masquerade only on the pod network; guest should use DHCP; expose via a Service to survive restarts; bridge on pod network: no live migration; Multus needed for secondary networks; macvlan/ipvlan invalid for bridge; passt +250Mi, feature gate | Section 13 |
| E21 | https://github.com/kubevirt/kubevirt/blob/v1.9.0/staging/src/kubevirt.io/api/core/v1/schema.go and https://github.com/kubevirt/kubevirt/blob/v1.9.0/pkg/network/link/address.go | KubeVirt v1.9.0 API schema and masquerade address code | `vmNetworkCIDR` default 10.0.2.0/24; gateway = 2nd address, guest = 3rd (10.0.2.1, 10.0.2.2) | Guest address 10.0.2.2 |
| E22 | https://kubevirt.io/user-guide/compute/live_migration/ | Live Migration - KubeVirt user guide | PVCs must be RWX to live migrate; bridge on pod network not allowed | Cold migration needs neither |
| E23 | https://kubevirt.io/user-guide/storage/disks_and_volumes/ | Disks and Volumes - KubeVirt user guide | `bus: virtio`; filesystem PVC needs raw `disk.img`; block PVC consumed as raw device; DataVolume behaviour; containerDisk | Block PVC, virtio |
| E24 | https://kubevirt.io/user-guide/user_workloads/guest_agent_information/ | Guest Agent information - KubeVirt user guide | GA is optional; `AgentConnected` condition; guestosinfo, userlist, filesystemlist | Agent non-blocking |
| E25 | https://kubernetes.io/releases/ and https://dl.k8s.io/release/stable-1.36.txt | Releases - Kubernetes; stable-1.36 pointer | Maintained 1.37, 1.36, 1.35; EOL 1.36 2027-06-28, 1.34 2026-10-27; stable-1.36 = v1.36.5; stable = v1.37.1 | Kubernetes 1.36 |
| E26 | https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/ | Installing kubeadm | Red Hat instructions via pkgs.k8s.io per minor; runtime sockets (CRI-O `/var/run/crio/crio.sock`); swap handling; SELinux note | kubeadm on CentOS Stream 9 |
| E27 | https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/ | Creating a cluster with kubeadm | Single machine: `kubectl taint nodes --all node-role.kubernetes.io/control-plane-` | Single-node scheduling |
| E28 | https://kubernetes.io/docs/concepts/architecture/cgroups/ | About cgroup v2 | cgroup v1 deprecated since 1.35; kubelet fails on v1 by default; RHEL 9-like distros use v2 | cgroup v2 |
| E29 | https://github.com/cri-o/packaging and https://github.com/cri-o/cri-o/releases | cri-o/packaging README; CRI-O releases | Packages from `download.opensuse.org/repositories/isv:/cri-o` per minor; v1.36.6 on 2026-09-21 | CRI-O 1.36 |
| E30 | https://www.centos.org/download/ | Download - The CentOS Project | CentOS Stream 9 EOL 2027-05-31; Stream 10 EOL 2030-05-31 | Lab lifetime fits |
| E31 | https://www.centos.org/download/aws-images/ | CentOS AWS AMI Cloud Images | CentOS Stream 9 x86_64 ap-south-1 `ami-0e7930d02f47291cb`; cloud user `ec2-user` | Node image exists in the Region |
| E32 | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html | Use nested virtualization to run hypervisors in Amazon EC2 instances | Families M7i, M7i-flex, M8i, M8id, M8i-flex, C7i, C7i-flex, C8i, C8id, C8i-flex, R7i, R7iz, R8i, R8id, R8i-flex, X8i, I7i, I7ie; KVM and Hyper-V as L1; no additional cost; enable at launch or on a stopped instance; check with `describe-instance-types`; bare metal recommended for performance-sensitive work | `m8i.xlarge` with nested virtualization |
| E33 | https://aws.amazon.com/about-aws/whats-new/2026/06/nested-virtualization-intel-us-gov-cloud/ | Nested virtualization is now available on additional Intel platforms and AWS GovCloud (US) regions | 2026-06-18: 7th-gen families added; support in all commercial Regions | ap-south-1 in scope (U1) |
| E34 | https://docs.aws.amazon.com/linux/al2023/ug/virtualization-getting-started.html | Get started with virtualization on Amazon Linux 2023 | Processor extensions only on bare metal or with nested virtualization on; missing `/dev/kvm` almost always means it was not enabled | `/dev/kvm` check |
| E35 | https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html | Understand the Kubernetes version lifecycle on EKS | Standard support 1.36, 1.35, 1.34; 1.36 on EKS 2026-06-02 | EKS version fine |
| E36 | https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html | Customize managed nodes with launch templates | Prohibited: subnet, IAM instance profile, shutdown/hibernate behaviour (CPU options not listed) | EKS `/dev/kvm` path plausible, undocumented |
| E37 | https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-amis.html | Create nodes with pre-built optimized images | Amazon Linux, Bottlerocket, Ubuntu, Windows AMIs; custom AMIs possible | No EL-aligned EKS AMI |
| E38 | https://docs.aws.amazon.com/eks/latest/best-practices/pod-security.html and https://aws.amazon.com/blogs/containers/implementing-pod-security-standards-in-amazon-eks/ | Pod Security (EKS best practices); Implementing Pod Security Standards in Amazon EKS (AWS Containers blog) | Privileged PSS level; EKS default PSA configuration is `privileged` for all modes | EKS admits privileged DaemonSets |
| E39 | https://docs.aws.amazon.com/eks/latest/userguide/pod-multiple-network-interfaces.html | Attach multiple network interfaces to Pods | By default the VPC CNI assigns one IP per pod from an ENI | EKS pod networking model |
| E40 | https://github.com/kubernetes-sigs/aws-ebs-csi-driver (README, docs/install.md, releases) | Amazon Elastic Block Store (EBS) CSI driver | Raw block volumes; compatible with all upstream-supported Kubernetes versions; IAM `AmazonEBSCSIDriverPolicyV2` scoped to tag `ebs.csi.aws.com/cluster: true`; IMDSv2 needs hop limit >= 2 unless host network; v1.66.0 on 2026-09-10 | Storage design |
| E41 | https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html | General Purpose SSD volumes | gp3 baseline 3,000 IOPS and 125 MiB/s; 1 GiB to 64 TiB | gp3 sizing |
| E42 | https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/ec2/USD/current/ec2-ondemand-without-sec-sel/Asia%20Pacific%20(Mumbai)/Linux/index.json | AWS public price file, EC2 on-demand Linux, Mumbai (published 2026-09-25) | m8i.xlarge 0.2227, m7i.xlarge 0.2121, m7i.metal-24xl 5.0904 USD/h; all listed nested families sold in the Region | Cost model |
| E43 | https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/ec2/USD/current/ebs.json | AWS public price file, EBS (published 2026-09-25) | gp3 storage in Mumbai 0.0912 USD/GB-month | Cost model |
| E44 | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEKS/current/ap-south-1/index.json | AWS Price List, AmazonEKS ap-south-1 (published 2026-09-18) | 0.10 USD per cluster-hour; extended support 0.50 USD/h | EKS cost |
| E45 | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/ap-south-1/index.json | AWS Price List, AmazonVPC ap-south-1 (published 2026-09-17) | Public IPv4 0.005 USD/h (in use or idle) | Cost model |
| E46 | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html | Elastic network interfaces | ENI IPv4 addresses come from the subnet range; source/destination checks (on by default) ensure the instance is the source or destination of its traffic | .31 cannot appear in a VPC |
| E47 | https://github.com/flannel-io/flannel/releases | Releases - flannel-io/flannel | v0.28.9 on 2026-08-07 | CNI version |
| E48 | https://github.com/kubernetes/kubernetes/blob/release-1.36/cmd/kubeadm/app/phases/controlplane/manifests.go | kubeadm control-plane manifests (release-1.36) | `{Name: "allow-privileged", Value: "true"}` | Privileged API server by default |
| E49 | https://github.com/kubevirt/kubevirt/blob/v1.9.0/pkg/virtctl/imageupload/imageupload.go | virtctl image-upload (v1.9.0) | Flags `--volume-mode`, `--access-mode`, `--storage-class`, `--uploadproxy-url`, `--insecure`, `--force-bind`, `--size` | Upload command design |
| E50 | https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/v1.66.0/docs/parameters.md | AWS EBS CSI driver v1.66.0 StorageClass parameters | `encrypted`: `true`/`false`, default `false`; `kmsKeyId`: if not specified, AWS uses the default KMS key for the Region | Explicit `encrypted: "true"` (section 29.7) |
| E51 | https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEBSCSIDriverPolicyV2.html | AmazonEBSCSIDriverPolicyV2 (AWS managed policy) | Create, modify and delete limited to volumes tagged `ebs.csi.aws.com/cluster = true` (or `kubernetes.io/created-for/pvc/name` for migrated volumes) | Post-destroy orphan check by tag (section 29.1) |
| E52 | https://github.com/flannel-io/flannel/releases/download/v0.28.9/kube-flannel.yml | flannel v0.28.9 deployment manifest | `net-conf.json`: `"Network": "10.244.0.0/16"`, backend `vxlan` | Pod CIDR (section 29.3) |
| E53 | https://github.com/kubernetes/kubernetes/blob/release-1.36/cmd/kubeadm/app/apis/kubeadm/v1beta4/defaults.go | kubeadm v1beta4 defaults (release-1.36) | `DefaultServicesSubnet = "10.96.0.0/12"`, `DefaultClusterDNSIP = "10.96.0.10"` | Service CIDR (section 29.3) |
| E54 | https://github.com/cri-o/cri-o/blob/release-1.36/contrib/cni/11-crio-ipv4-bridge.conflist | CRI-O release-1.36 default bridge CNI configuration | Bridge network `crio` with subnet `10.85.0.0/16` | Range kept clear (section 29.3) |
| E55 | https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/datavolumes.md | Data Volumes - CDI v1.66.1 documentation | "Data Volumes(DV) are an abstraction on top of Persistent Volume Claims(PVC)"; the DV "will monitor and orchestrate the import/upload/clone of the data into the PVC"; the `pvc` and `storage` sections both "result in CDI creating a PVC resource" | The standalone DataVolume is the migration disk's lifecycle object (sections 16, 18, 29.1) |
| E56 | https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/staging/src/kubevirt.io/containerized-data-importer-api/pkg/apis/core/v1beta1/types.go | CDI v1.66.1 API types | `DataVolumeTTLSeconds`: "the time in seconds after DataVolume completion it can be garbage collected"; "Deprecated: Removed in v1.62" | The DataVolume is expected to remain after `Succeeded` (INFERRED; section 18) |
