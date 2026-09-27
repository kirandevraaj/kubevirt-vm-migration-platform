# Feasibility: what is proven, what is not, and what must be validated

Stage 0 document for request section 20, refined after technical review. Version-sensitive facts were checked against current official documentation on 2026-09-27.

## Status categories

| Category | Meaning |
|---|---|
| **Validated** | Observed working in **our** lab by a command we ran. |
| **Documented** | Current official documentation says it exists or should work. **We have not run it.** Documented is never the same as validated. |
| **Unvalidated** | Unknown, risky, or not yet tested. Needs a real test. |
| **Blocked by current lab mode** | Not possible while the laptop runs in its current mode (Windows hypervisor off so nested ESXi can use VMware's native virtualization). |
| **Deferred decision** | A choice intentionally not made in Stage 0. |

---

## 1. What is proven and what is not

### PROVEN IN OUR LAB

Each row was observed by a read-only command or recorded as OBSERVED in the handoff. See [evidence-index.md](evidence-index.md).

| # | Proven fact | Evidence |
|---|---|---|
| P1 | Nested ESXi runs on VMware Workstation on this laptop | ESXi boots and answers; Workstation in native CPL0 mode with `vhv.enable = TRUE` |
| P2 | ESXi 8.0.3 build 24677879 works | `vmware -vl` over SSH |
| P3 | ESXi sees hardware virtualization | `esxcli hardware cpu global get` -> `HV Support: 3` |
| P4 | A VMFS-6 datastore works | `migration-datastore` mounted, 199.8 GB, 198.3 GB free |
| P5 | Static management IP on vmk0 works | 192.168.50.11/24 STATIC, gateway 192.168.50.2 |
| P6 | SSH key authentication to ESXi works | `ssh esxi-8-lab` (batch mode, no password) |
| P7 | NTP works | ntpd running, in sync with `pool.ntp.org` servers |
| P8 | Read-only discovery via `vim-cmd` works | `vim-cmd vmsvc/getallvms` returns (currently empty) |
| P9 | GitHub push over SSH works | Commits `3579f64`, `cb51c5c` on `origin/main` |

### NOT YET PROVEN

Nothing in this table may be described as working until it has been tested.

| # | Not yet proven | Why it matters | Category |
|---|---|---|---|
| N1 | A nested 64-bit guest (L2) boots under our ESXi | The source VM depends on it | Unvalidated |
| N2 | ESXi network/hostname/NTP config survives a controlled reboot | Lab stability | Unvalidated |
| N3 | KVM and `/dev/kvm` on the AWS target node | KubeVirt needs hardware virtualization | Documented (AWS), Unvalidated (us) |
| N4 | KubeVirt installs and becomes `Available` on the chosen AWS node architecture | Core of the destination | Unvalidated |
| N5 | The CDI/KubeVirt/Kubernetes runtime combination works | No official pairing found; must be tested | Unvalidated |
| N6 | VMDK acquisition from this free ESXi host (SSH copy or `virt-v2v -i vmx -it ssh`) | Only non-API path we have | Documented (virt-v2v), Unvalidated (us) |
| N7 | virt-v2v conversion of this source VM | Guest must boot on virtio | Unvalidated |
| N8 | The migrated target VM boots on KubeVirt | Proves conversion + import | Unvalidated |
| N9 | End-to-end migration, including application validation | The project's goal | Unvalidated |
| N10 | EKS worker nodes satisfy KubeVirt host requirements | Decides EKS vs self-managed | Unvalidated |
| N11 | A self-managed Kubernetes node satisfies KubeVirt host requirements | The parallel option | Unvalidated |
| N12 | Outbound transfer lab -> S3 is fast enough for a disk image | Migration duration | Unvalidated |

---

## 2. Feasibility table

| # | Item | Finding | Category | Needed by |
|---|---|---|---|---|
| F1 | Nested ESXi | Runs; VT-x exposed to ESXi (`HV Support: 3`) | **Validated** | Now |
| F2 | ESXi storage | `migration-datastore` VMFS-6, 198.3 GB free | **Validated** | Now |
| F3 | ESXi management network | vmk0 192.168.50.11 static on vSwitch0 | **Validated** | Now |
| F4 | ESXi SSH | Key-based `ssh esxi-8-lab` works | **Validated** | Now |
| F5 | Free ESXi API | Broadcom: API use "is not supported, and may only provide read-only information" | **Documented** | Now |
| F6 | Source VM (`legacy-source-vm`) | Not created. Guest OS, version and sizing not chosen | **Unvalidated** + **Deferred decision** | Source-VM work |
| F7 | Nested L2 guest boot | Not tested | **Unvalidated** | Source-VM work |
| F8 | ESXi reboot persistence | Not tested | **Unvalidated** | Source-VM work |
| F9 | Source disk acquisition without the API | `virt-v2v -i vmx -it ssh` reads `.vmx` and disks over SSH; guest must be shut down; no snapshots; key auth via `ssh-agent` + `/etc/ssh/keys-root/authorized_keys` | **Documented** | Migration work |
| F10 | KubeVirt/Kubernetes version alignment | KubeVirt v1.9 is built for Kubernetes 1.36 and also supported on the previous two minors (1.35, 1.34). Kubernetes 1.34 is EOL 2026-10-27 | **Documented** | Cluster work |
| F11 | CDI compatibility tuple | CDI v1.66.1 observed as newest. No official KubeVirt-to-CDI matrix found. Tuple chosen and tested at deployment time (section 3) | **Unvalidated** | Cluster work |
| F12 | AWS nested virtualization capability | Available on supported non-bare-metal instances since 2026-02-16; KVM and Hyper-V as L1; no additional cost (section 4) | **Documented** | Cloud work |
| F13 | Instance family, size, Region, AMI | Not chosen | **Deferred decision** | Cloud work |
| F14 | EKS host-requirement compatibility | Not rejected; unproven until a real node is tested (section 5) | **Unvalidated** | Cloud work |
| F15 | Self-managed Kubernetes host compatibility | Parallel option; unproven (section 5) | **Unvalidated** | Cloud work |
| F16 | Kubernetes topology (EKS vs self-managed) | Not chosen | **Deferred decision** | Cloud work |
| F17 | Conversion host | Local Linux tooling unavailable in current lab mode; location not chosen (section 6) | **Blocked by current lab mode** (local option) + **Deferred decision** | Migration work |
| F18 | Target storage | EBS gp3 via EBS CSI: RWO, AZ-scoped, typically `WaitForFirstConsumer`; CDI may need scratch space | **Documented** | Cloud work |
| F19 | Target networking | Pod network + masquerade is sufficient for the demo; Multus not required | **Documented** | Cluster work |
| F20 | AWS credentials | Only copy is in Docker volume `platform-aws-tools-aws`, unreadable while Docker cannot run | **Blocked by current lab mode** | Cloud work |
| F21 | Source -> destination connectivity | Cold migration needs only outbound HTTPS lab -> S3 (or CDI upload proxy); no VPN (INFERRED) | **Unvalidated** | Migration work |
| F22 | Local disk space | Datastore 198.3 GB free; laptop C: ~434 GB free | **Validated** | Now |

---

## 3. Compatibility tuple and runtime validation gate

### Principle

**Do not hard-code CDI (or KubeVirt) solely because it is the latest release at documentation time.** Select the CDI release explicitly validated for the chosen KubeVirt/Kubernetes combination **at deployment time**.

What the official sources say today:

- KubeVirt: "Kubernetes cluster ... based on one of the latest three Kubernetes releases that are out at the time the KubeVirt release is made" ([KubeVirt installation](https://kubevirt.io/user-guide/cluster_admin/installation/)); v1.9 "is built for Kubernetes v1.36 and additionally supported for the previous two versions" ([release notes](https://kubevirt.io/user-guide/release_notes/)).
- CDI: newest observed release v1.66.1 ([CDI API reference](https://kubevirt.io/cdi-api-reference/), [CDI releases](https://github.com/kubevirt/containerized-data-importer/releases)). The KubeVirt CDI page installs "the latest CDI release" ([KubeVirt: CDI](https://kubevirt.io/user-guide/storage/containerized_data_importer/)). No official KubeVirt-to-CDI pairing statement was found in the sources reviewed.
- Therefore **no specific CDI/KubeVirt pairing is claimed to be officially supported** in this project's documentation.

### The compatibility tuple

Recorded once, at deployment time, and used everywhere afterwards (Terraform variables, install manifests, docs):

| Field | Stage 0 observation (not a decision) | Chosen at deployment |
|---|---|---|
| Kubernetes version | 1.35 or 1.36 are inside the KubeVirt v1.9 window; 1.34 is EOL 2026-10-27 | _to be recorded_ |
| KubeVirt version | v1.9 is the newest release | _to be recorded_ |
| CDI version | v1.66.1 is the newest release | _to be recorded_ |
| Evidence for the tuple | - | release notes / upstream CI / test result links |

### Runtime validation gate

Before the actual lab deployment is considered usable, **all** of these must pass and be recorded as evidence. Until then the tuple is a candidate, not a fact.

| Gate | Check | Pass condition |
|---|---|---|
| G1 KubeVirt release | Release exists, notes read, Kubernetes range recorded | Chosen Kubernetes version is inside the documented range |
| G2 Kubernetes release | `kubectl version` | Server version equals the tuple and is not EOL |
| G3 CDI release | Release notes read for Kubernetes/KubeVirt statements | No documented incompatibility with the tuple |
| G4 API compatibility | `kubectl api-resources` / `kubectl explain` for `virtualmachines.kubevirt.io/v1`, `virtualmachineinstances.kubevirt.io/v1`, `datavolumes.cdi.kubevirt.io/v1beta1` | All served at the expected versions |
| G5 Installation health | `kubectl -n kubevirt wait kv kubevirt --for condition=Available`; CDI CR `Available`; all Pods Running | Both operators report Available |
| G6 Host capability | `virt-host-validate qemu` (or equivalent) on each VM node | `/dev/kvm`, `/dev/vhost-net`, `/dev/net/tun` PASS |
| G7 Functional smoke test | Import a small test image with a DataVolume, boot a test VM from it | DataVolume `Succeeded`; VMI `Running`; console reachable |

---

## 4. AWS nested virtualization capability

Source: [Use nested virtualization to run hypervisors in Amazon EC2 instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html) (read 2026-09-27); announcement: [What's New, 2026-02-16](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual/).

- AWS announced the capability on **2026-02-16**. Nested virtualization is available on supported **non-bare-metal** ("virtual") EC2 instances. The Nitro System passes processor extensions such as Intel VT-x to the instance. Layers: Nitro (L0), your instance running a hypervisor (L1), nested VMs (L2).
- Supported L1 hypervisors: **KVM** and **Hyper-V**.
- Cost: "There is no additional cost for using nested virtualization."
- Enabling: at launch with CPU options (`NestedVirtualization=enabled`), or on a **stopped** instance with `modify-instance-cpu-options`. Discover per Region with `describe-instance-types` filtered on `processor-info.supported-features = nested-virtualization`.
- AWS recommends evaluating bare metal for workloads that are performance-sensitive or have strict latency requirements.

Supported instance families listed by AWS at time of reading:

| Category | Families |
|---|---|
| General Purpose | M7i, M7i-flex, M8i, M8id, M8i-flex |
| Compute Optimized | C7i, C7i-flex, C8i, C8id, C8i-flex |
| Memory Optimized | R7i, R7iz, R8i, R8id, R8i-flex, X8i |
| Storage Optimized | I7i, I7ie |

**This is not a recommendation.** Instance family, exact size, Region, AMI and Kubernetes topology all remain **deferred decisions**.

Status: **Documented**. Not validated by us (no instance has been launched).

---

## 5. EKS host-requirement compatibility

### The question, stated precisely

Not "does EKS support KubeVirt?", but:

> **Can an EKS-managed worker architecture satisfy all host-level requirements required by the selected KubeVirt release?**

KubeVirt runs as ordinary Kubernetes workloads, so the question is about the **worker nodes** (instance, AMI, kernel, runtime, security settings, storage and network plugins), not about the managed control plane.

### Requirement checklist

The same checklist applies to a self-managed node. Sources: [KubeVirt installation](https://kubevirt.io/user-guide/cluster_admin/installation/), [KubeVirt: CDI](https://kubevirt.io/user-guide/storage/containerized_data_importer/), [AWS nested virtualization](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html).

| # | Requirement | Why | How to validate on a real node | EKS status | Self-managed status |
|---|---|---|---|---|---|
| H1 | CPU nested virtualization | KVM needs VT-x at L1 | Instance launched with `NestedVirtualization=enabled`; `grep -c vmx /proc/cpuinfo` > 0 | Unvalidated (does the node group/launch template path pass the CPU option?) | Unvalidated |
| H2 | `/dev/kvm` | QEMU acceleration | `ls -l /dev/kvm`; `virt-host-validate qemu` | Unvalidated | Unvalidated |
| H3 | `/dev/vhost-net` | Fast virtio-net data path | `virt-host-validate qemu` | Unvalidated | Unvalidated |
| H4 | `/dev/net/tun` | Tap devices for VM NICs | `virt-host-validate qemu` | Unvalidated | Unvalidated |
| H5 | Privileged DaemonSets | virt-handler is privileged; apiserver needs `--allow-privileged=true`; Pod Security must allow it in the KubeVirt namespace | virt-handler Pods reach Running | Unvalidated | Unvalidated |
| H6 | Host kernel / userspace alignment | virt-launcher ships an Enterprise Linux (CentOS Stream / RHEL) libvirt + QEMU userland; KubeVirt recommends an aligned host kernel; mismatches can cause device feature-negotiation problems | Record node OS and kernel; boot a test VM; check virt-launcher logs | Unvalidated (EKS-optimized AMIs are not Enterprise Linux: a documented risk, not a rejection) | Unvalidated (can choose an EL-aligned OS) |
| H7 | Supported container runtime | KubeVirt targets containerd and CRI-O | `kubectl get nodes -o wide` (CONTAINER-RUNTIME) | Unvalidated | Unvalidated |
| H8 | Device ownership / security context | CDI docs: the CRI may need to handle device ownership through the security context (block devices, `/dev/kvm`) | Runtime config reviewed; CDI import to a block-mode PVC works | Unvalidated | Unvalidated |
| H9 | Node-image compatibility | AMI must include KVM modules and allow the above; AppArmor/SELinux policies must not block virt-handler | virt-handler healthy; test VM boots | Unvalidated | Unvalidated |
| H10 | Storage requirements | CSI StorageClass for DataVolumes (EBS gp3: RWO, AZ-scoped); scratch space | DataVolume import `Succeeded` | Unvalidated | Unvalidated |
| H11 | Networking requirements | Pod network works with masquerade; optional Multus later | VM reachable through a Service | Unvalidated | Unvalidated |

### Position in Stage 0

- **EKS is NOT rejected by design in Stage 0.** It remains an **unvalidated option** until a real node is tested against H1-H11.
- **Self-managed Kubernetes** (for example kubeadm on EC2) is kept as a **parallel option** with the same checklist.
- **Neither is chosen.** The choice is a deferred decision, to be made from test evidence.

---

## 6. Conversion host (deferred decision)

Conversion tools (qemu-img, virt-v2v, libguestfs) need a Linux environment. **Where conversion runs is not decided.** The three conceptual options stay open:

| Option | Description | Considerations |
|---|---|---|
| A. Local helper Linux environment | A Linux environment on the lab side, for example a small Linux VM on ESXi next to the source VM | Close to the source disk; uses ESXi's limited CPU/RAM budget; image then uploaded to AWS |
| B. AWS conversion helper | A disposable Linux instance or Job in AWS that pulls the source disk | Plenty of resources; source disk must be transferred first; part of the Terraform-managed environment |
| C. Conversion in another controlled Linux runtime | Conversion integrated into another controlled Linux runtime, for example a Kubernetes Job in the target cluster (as MTV does with its conversion Pod) | Fits the controller model; needs the source disk reachable from the cluster |

### Current lab constraint

- Windows is **intentionally** running **without the Windows hypervisor** (`hypervisorlaunchtype Off`), so that nested ESXi can run in VMware Workstation's native virtualization mode (VHV needs it).
- Therefore **WSL2 and Docker Desktop are not available** in that mode, and they cannot host conversion tools on the laptop.
- This is a **lab architecture constraint**, not a permanent production limitation. In production, conversion would run on dedicated Linux infrastructure or inside the target platform.

Status: **Blocked by current lab mode** for a WSL/Docker-based local option; **Deferred decision** overall.

---

## 7. Sources

- KubeVirt: [user guide](https://kubevirt.io/user-guide/), [release notes](https://kubevirt.io/user-guide/release_notes/), [installation](https://kubevirt.io/user-guide/cluster_admin/installation/), [support matrix](https://github.com/kubevirt/sig-release/blob/main/releases/k8s-support-matrix.md).
- CDI: [KubeVirt: Containerized Data Importer](https://kubevirt.io/user-guide/storage/containerized_data_importer/), [CDI API reference](https://kubevirt.io/cdi-api-reference/), [CDI releases](https://github.com/kubevirt/containerized-data-importer/releases), [scratch space](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/scratch-space.md).
- Kubernetes: [releases](https://kubernetes.io/releases/).
- AWS: [nested virtualization](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html), [What's New 2026-02-16](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual/), [LaunchTemplateCpuOptionsRequest](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_LaunchTemplateCpuOptionsRequest.html), [EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html), [EBS CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html).
- VMware/Broadcom: [KB 399823](https://knowledge.broadcom.com/external/article/399823), [ESXi 8.0 U3e release notes](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/release-notes/esxi-update-and-patch-release-notes/vsphere-esxi-80u3e-release-notes.html).
- virt-v2v: [virt-v2v-input-vmware(1)](https://libguestfs.org/virt-v2v-input-vmware.1.html).

## 8. Stage 1 entry criteria

See [README.md](README.md#stage-1-entry-criteria).
