# Feasibility: what must be validated before Stage 1

Stage 0 document for request section 20. Version-sensitive facts were checked against current official documentation on 2026-09-27. Status values:

- **VALIDATED**: observed in our lab, or stated plainly by current official docs for our exact case.
- **DOCUMENTED, NOT TESTED**: official docs say it should work; we have not run it.
- **UNVALIDATED**: unknown or risky; needs a test.
- **BLOCKER**: must be resolved before the stage that needs it.

## 1. Summary

| # | Question | Finding | Status | Needed by |
|---|---|---|---|---|
| F1 | KubeVirt / Kubernetes version compatibility | KubeVirt v1.9 supports Kubernetes 1.36, 1.35, 1.34. Kubernetes 1.34 is EOL on 2026-10-27; 1.37 is outside the v1.9 window. Choose **1.35 or 1.36**. EKS standard support covers 1.34-1.36. | DOCUMENTED, NOT TESTED | Stage 1 |
| F2 | CDI compatibility | CDI v1.66.1 is current. CDI and KubeVirt release separately; the pairing for KubeVirt v1.9 must be confirmed from the CDI release notes before install. | UNVALIDATED | Stage 1 |
| F3 | Hardware virtualization on the target | AWS supports nested virtualization on virtual instances since 2026-02-16 (C8i/M8i/R8i families and others; KVM is a supported L1 hypervisor). Bare metal is the fallback. | DOCUMENTED, NOT TESTED | Cloud stage |
| F4 | `/dev/kvm` in the Kubernetes node | Must exist on the worker, and `virt-host-validate qemu` must pass (`/dev/kvm`, `/dev/vhost-net`, `/dev/net/tun`). Depends on F3 and the node AMI. | UNVALIDATED | Cloud stage |
| F5 | Nested virt with EKS managed nodes | The EC2 launch template API has a `NestedVirtualization` CPU option. Whether EKS managed node groups accept it, and which node AMI works, is not confirmed. Fallback: self-managed nodes or kubeadm on EC2. | UNVALIDATED | Cloud stage |
| F6 | Host kernel vs virt-launcher userland | KubeVirt docs recommend host kernels compatible with the Enterprise Linux userland in virt-launcher. EKS AMIs are Amazon Linux 2023 / Bottlerocket (not EL). | UNVALIDATED (risk) | Cloud stage |
| F7 | Kubernetes API requirements | `--allow-privileged=true` is required. It is the default on EKS and kubeadm. | DOCUMENTED, NOT TESTED | Stage 1 |
| F8 | Privileged workloads | virt-handler is a privileged DaemonSet. Pod Security Admission must allow privileged Pods in the KubeVirt namespace. | DOCUMENTED, NOT TESTED | Stage 1 |
| F9 | Container runtime | containerd or CRI-O are supported. EKS and kubeadm default to containerd. | DOCUMENTED, NOT TESTED | Stage 1 |
| F10 | Storage requirements | EBS gp3 via the EBS CSI driver: RWO, AZ-scoped, typically `WaitForFirstConsumer`. Fine for cold migration and running VMs; no live migration across nodes. CDI may need scratch space. | DOCUMENTED, NOT TESTED | Cloud stage |
| F11 | Networking requirements | Pod network + masquerade is enough for the demo. Multus is not required. | DOCUMENTED, NOT TESTED | Stage 1 |
| F12 | Free ESXi API | Broadcom: API use "is not supported, and may only provide read-only information". Blocks confidence in MTV, API snapshots and CBT (warm). SSH + `vim-cmd` works today. | VALIDATED (docs + SSH observed) | Now |
| F13 | Source disk acquisition without API | virt-v2v `-i vmx -it ssh` reads `.vmx` + disks over SSH; guest must be off; no snapshots. A plain SSH/scp copy of the flat VMDK is also possible. | DOCUMENTED, NOT TESTED | Migration stage |
| F14 | Conversion host | qemu-img / virt-v2v / libguestfs need Linux. Locally, WSL/Docker cannot run while the Windows hypervisor is off. Options: Linux helper VM on ESXi, or conversion in AWS. | BLOCKER (decision deferred) | Migration stage |
| F15 | Available disk space | `migration-datastore` has 198.3 GB free; laptop C: ~434 GB free. Enough for a 20 GB source VM plus copies. | VALIDATED | Source VM stage |
| F16 | Source -> destination connectivity | Cold migration needs only outbound HTTPS from the lab to S3 (or the CDI upload proxy). No VPN required. | INFERRED | Migration stage |
| F17 | AWS credentials | Only copy is in Docker volume `platform-aws-tools-aws`, unreadable while Docker is down. | BLOCKER | Cloud stage |
| F18 | Nested 64-bit guest on ESXi | ESXi reports `HV Support: 3`; no L2 guest has been run yet. | UNVALIDATED | Source VM stage |
| F19 | ESXi config persistence across reboot | Static IP, route, DNS, hostname, NTP not yet verified after a controlled reboot. | UNVALIDATED | Source VM stage |
| F20 | Guest boots on virtio after qemu-img-only conversion | Likely for a modern Linux guest; virt-v2v is the safer path. | UNVALIDATED | Migration stage |

## 2. Details and sources

### F1, F7, F8, F9: KubeVirt install requirements

- Support matrix: [kubevirt/sig-release k8s-support-matrix](https://github.com/kubevirt/sig-release/blob/main/releases/k8s-support-matrix.md); release notes: [KubeVirt release notes](https://kubevirt.io/user-guide/release_notes/) ("KubeVirt v1.9 is built for Kubernetes v1.36 and additionally supported for the previous two versions").
- Kubernetes releases and EOL dates: [kubernetes.io/releases](https://kubernetes.io/releases/).
- EKS versions: [Amazon EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html).
- Requirements (privileged, runtime, `virt-host-validate`, emulation fallback, node placement): [KubeVirt installation](https://kubevirt.io/user-guide/cluster_admin/installation/).

### F2: CDI

- [CDI releases](https://github.com/kubevirt/containerized-data-importer/releases) (v1.66.1, 2026-09-06). Stage 1 action: read the v1.66.x notes for the tested KubeVirt/Kubernetes versions and pin both.

### F3, F4, F5: nested virtualization on AWS

- [Use nested virtualization to run hypervisors in Amazon EC2 instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html): Nitro passes VT-x to the instance; L0/L1/L2; supported instance families; KVM and Hyper-V as L1; enable at launch or on a stopped instance.
- [What's New, 2026-02-16](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual/).
- [LaunchTemplateCpuOptionsRequest: NestedVirtualization](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_LaunchTemplateCpuOptionsRequest.html) (also notes that Virtual Secure Mode is disabled when nested virtualization is enabled).
- Validation plan (later stage, with approval): `aws ec2 describe-instance-types` filter for `nested-virtualization`; launch one instance with `NestedVirtualization=enabled`; check `grep -c vmx /proc/cpuinfo`, `ls -l /dev/kvm`, `virt-host-validate qemu`; then terminate.

### F6: host kernel

- [KubeVirt installation](https://kubevirt.io/user-guide/cluster_admin/installation/) notes the Enterprise Linux basis of the virt-launcher image. Test plan: try the default EKS AL2023 AMI first; if VMs fail to start, fall back to a self-managed node with an EL-compatible distribution.

### F10: storage

- [KubeVirt: Containerized Data Importer](https://kubevirt.io/user-guide/storage/containerized_data_importer/), [CDI scratch space](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/scratch-space.md), [Amazon EBS CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html).

### F12, F13: source side

- [Broadcom KB 399823: ESXi 8.0 Update 3e now available as a Free Hypervisor](https://knowledge.broadcom.com/external/article/399823) and [ESXi 8.0 Update 3e release notes](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/release-notes/esxi-update-and-patch-release-notes/vsphere-esxi-80u3e-release-notes.html): non-production, no support, no vCenter, 8 vCPU per VM, no vMotion/HA/DRS/VADP, API unsupported and possibly read-only.
- [virt-v2v-input-vmware(1)](https://libguestfs.org/virt-v2v-input-vmware.1.html): `-i vmx -it ssh` requirements.

## 3. Prerequisites for Stage 1 (proposed)

Stage 1 scope is for the user to confirm. Whatever it is, these must be true first:

1. Decide Stage 1's target: cluster first (KubeVirt install on AWS) or source VM first (create `legacy-source-vm` on ESXi).
2. If the cluster comes first: recover or re-issue AWS credentials (F17); pick Kubernetes 1.35 or 1.36 and pin KubeVirt v1.9.x + CDI v1.66.x (F1, F2); decide EKS vs self-managed (F5, F6); prove `/dev/kvm` on one disposable instance (F3, F4).
3. If the source VM comes first: controlled ESXi reboot test (F19); choose guest OS and ISO; create the VM and prove a nested 64-bit guest boots (F18); install nginx.
4. Decide where conversion runs (F14).
5. Keep the constraints: nothing created without explicit approval; AWS only through Terraform.
