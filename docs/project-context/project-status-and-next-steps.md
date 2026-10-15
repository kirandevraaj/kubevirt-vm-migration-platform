# Project status and next steps

**Project 1.5: VM-to-Kubernetes Migration Platform (VMware ESXi -> KubeVirt)**

A navigation and reference sheet: where the project is, what really exists, what was really tested, and what could come next. It adds no new facts, decisions or status. Every statement comes from the repository records. When this sheet and a record disagree, the record wins.

- Authoritative current status for Stage 1: [Stage 1 README](../stage-1/README.md). The full Stage 1I result: [Stage 1I record](../stage-1/stage-1i-first-kubevirt-migration.md).
- Historical evidence: the individual stage records under [docs/stage-0/](../stage-0/README.md) and [docs/stage-1/](../stage-1/README.md), and the [ADRs](../adr/README.md).
- **Updated 2026-10-15** to reflect the completion of Stage 1I (2026-10-01). The first version of this sheet recorded the status at the end of Stage 1H (2026-09-28), when nothing had been deployed. That version is preserved in Git history (commit `a9511b6`), and its pictures remain in the [visual status page](project-status-visual.html). This update was written without touching the lab, so live power states were **not re-observed** for it.

Labels, exactly as the records use them:

| Label | Meaning |
|---|---|
| **OBSERVED** | Seen in this lab by a command we ran |
| **PROVEN** | Used in this sheet only for capabilities with OBSERVED evidence in a PASS stage record |
| **DOCUMENTED** | Stated by an official source; not run by us |
| **INFERRED** | Reasoned from observations or documentation; not tested |
| **NOT TESTED** | Deliberately not done |
| **DESIGNED** | Written down as a design (Stage 0 or Stage 1H); not built |
| **DESTROYED** | Built and validated in Stage 1I, then deliberately removed in Gate I5 |
| **DECIDED** / **DEFERRED** / **UNKNOWN** / **BLOCKED** | Stage 1H decision states |
| **PROPOSED** | A suggestion in this sheet. **Not official, not approved, not a stage.** |

---

## Section 1. Where We Are Now

**One line:** Stages 0 and 1A to 1I are complete. Stage 1I migrated one VM, cold, from VMware ESXi to KubeVirt on a temporary single-node kubeadm cluster on AWS EC2, validated it end to end, and destroyed the target (2026-10-01). No Kubernetes, KubeVirt, CDI or Stage 1I AWS resource exists now. No stage after 1I is defined.

| Item | Value | Source |
|---|---|---|
| Project | Project 1.5: VM-to-Kubernetes Migration Platform | [README](../../README.md) |
| Current phase | Stage 1 complete (1A to 1I). No later stage defined | [Stage 1 README](../stage-1/README.md) |
| Completed stages | Stage 0; Stage 1A to 1G (**Complete (PASS)**); 1H (**Done (design)**, H1 to H10 PASS); 1I (**Complete**, I1 to I5 PASS) | [Stage 1 README](../stage-1/README.md) |
| Most recent stage | **Stage 1I: first KubeVirt migration**, completed 2026-10-01 | [Stage 1I record](../stage-1/stage-1i-first-kubevirt-migration.md) |
| Next stage | **None defined.** Any further work needs its own definition and approval | [Stage 1 README](../stage-1/README.md#next-stage) |
| Infrastructure state | Local lab only: nested ESXi with 3 guest VMs. The Stage 1I AWS target (10 Terraform-managed resources, the cluster, the migrated VM and its EBS volume) was destroyed and verified gone in Gate I5. In AWS, only the account's default VPC and its pre-existing security groups remain | [Stage 1I section 19.5](../stage-1/stage-1i-first-kubevirt-migration.md#195-final-outcome) |
| Repository state | Public docs, ADRs, diagrams and the GitHub Pages learning portal (`docs/index.html` and the visual pages). Since Stage 1I it also holds the Terraform configuration for the AWS layer (`infra/terraform/stage-1i-target/`) and the Kubernetes manifests and templates used (`infra/kubernetes/stage-1i/`). No disk images, Terraform state, variables files, credentials or raw evidence in Git | Repository |

### Stage status table

| Stage | Status (as recorded) | What it means |
|---|---|---|
| Stage 0 | Complete, with a technical refinement pass (2026-09-27). Its README still says "pending user review"; Stage 1 was later started with explicit approvals. | Theory, architecture, feasibility, ADRs 001 to 005. Nothing installed. |
| 1A | Complete (PASS), 2026-09-27 | ESXi survives a controlled reboot with its configuration intact |
| 1B | Complete (PASS), 2026-09-27 | `kvm-learning-01`: 64-bit nested guest, nested KVM, QEMU, libvirt, VirtIO learned hands-on |
| 1C | Complete (PASS), 2026-09-27 | Real VMware source VM `legacy-source-vm` built and baselined (nginx, static .31) |
| 1D | Complete (PASS), 2026-09-27 | Source VMDK characterized; cold acquisition designed (not executed) |
| 1E | Complete (PASS), 2026-09-27 | Cold copy of the source disk to Windows; byte-identical (sha256) golden artifact; about 10.5 min source downtime |
| 1F | Complete (PASS), 2026-09-27 | `conversion-host-01` built; hash-verified, immutable working copy; read-only inspection |
| 1G | Complete (PASS), 2026-09-28 | qemu-img and virt-v2v conversions; temporary QEMU/KVM test boots; network remediation on a disposable copy; ADR 006 |
| 1H | Done (design): H1 to H10 PASS, 2026-09-28; architecture review corrections 2026-09-30 | KubeVirt target designed; ADRs 007 to 010 |
| 1I | **Complete**: I1 to I5 PASS, 2026-10-01 | Prepared image, pre-transfer boot test, AWS target build, first migration to KubeVirt, final validation and controlled teardown |

No stage numbers after 1I exist in the repository.

---

## Section 2. Four Questions

### 1. What stage are we in?

**Stage 1 is complete, including Stage 1I.** The design of Stage 1H was built, a VM was migrated to it and validated, and everything was torn down again. No later stage has been defined.

### 2. Is the VMware VMDK -> KVM QCOW2 conversion complete?

**YES.** Stage 1G converted the protected working copy two ways as a controlled experiment, and both results booted under QEMU/KVM. Those Stage 1G outputs are kept as reference artifacts. Stage 1I Gate I1 then made the **migration artifact**: a new standalone copy of the virt-v2v output with the netplan DHCP fix, an offline-installed guest agent and the virt-v2v first-boot scripts removed (`/srv/migration-lab/stage-1i/working/legacy-source-vm-prepared.qcow2`, sha256 `2b30e195...93b2`, 0444, immutable). That image is what was migrated.

The Stage 1G conversion experiment (all OBSERVED in the [Stage 1G record](../stage-1/stage-1g-controlled-conversion.md), sections 8 to 17):

| | Path A: qemu-img | Path B: virt-v2v |
|---|---|---|
| What it is | Container conversion only | Guest-aware conversion plus container conversion |
| Input | `/srv/migration-lab/working/legacy-source-vm.vmdk` (protected working copy, `0444` + `chattr +i`) | Same input |
| Command | `qemu-img convert -f vmdk -O qcow2 ...` (5 s) | `virt-v2v -i disk -if vmdk ... -o local -os /srv/migration-lab/stage-1g/virt-v2v/local-out -of qcow2` (136 s) |
| Output | `/srv/migration-lab/stage-1g/qemu-img/legacy-source-vm.qcow2` (sha256 `08c62ac5...5447`) | `/srv/migration-lab/stage-1g/virt-v2v/local-out/legacy-source-vm-sda` (qcow2, sha256 `94bc1cd6...91c6`) plus `legacy-source-vm.xml` (libvirt XML) |
| Guest changed? | No. `qemu-img compare`: "Images are identical." | Yes. open-vm-tools purged, initramfs rebuilt, virtio alias, first-boot job for qemu-guest-agent. netplan, fstab, GRUB config and identity untouched. |
| Remediated result | - | `/srv/migration-lab/stage-1g/virt-v2v/remediated/legacy-source-vm-netfix.qcow2` (sha256 `5326b130...d3d6`): a second copy with **one** netplan change (match by driver `virtio_net`, test address 10.0.2.15) |

- **Where they live:** on **`conversion-host-01`** (a VM on ESXi), in `/srv/migration-lab/stage-1g/` and `/srv/migration-lab/stage-1i/working/`. Their space is inside the conversion host's virtual disk on `migration-datastore`.
- **Git:** **not committed.** Disk images are outside Git by design.
- **Protection:** each kept output is mode `0444` and hashed; the prepared image is also immutable. Boots used disposable overlays, so the outputs never changed.
- **The source VMDK was not modified** by any conversion. The Stage 1E golden artifact was only hashed.
- **Format:** qcow2 in transit; CDI wrote it as **raw** onto a Block PVC in Stage 1I (ADR 009).

### 3. Did we deploy a VM using the converted disk?

**Yes, once, temporarily, in Stage 1I.** The prepared image was transferred to the EC2 node, imported by CDI into a 40 GiB encrypted gp3 Block DataVolume, and booted as the KubeVirt VM `legacy-source-vm-migrated`. It was validated and then deliberately deleted with its disk in Gate I5. **No KubeVirt VM exists now.**

| # | Thing | Was it created from the converted disk? |
|---|---|---|
| A | **VMware source VM** (`legacy-source-vm`, ESXi Vmid 2) | No. It is the original source, unchanged, still on ESXi. It was never pointed at any converted image and was not contacted during Stage 1I. |
| B | **`conversion-host-01`** (ESXi Vmid 3) | No. It is the Ubuntu workbench VM that holds the tools and the disks. |
| C | **Temporary QEMU/KVM test guests** (Stage 1G: three boots; Stage 1I Gate I2: the prepared image) | **Yes, each deleted afterwards.** Details below. |
| D | **KubeVirt VM `legacy-source-vm-migrated`** (Stage 1I Gate I4) | **Yes.** Ran on the AWS node from 04:04 to 11:22 UTC on 2026-10-01, then deleted in Gate I5 with its DataVolume, PVC, PV and EBS volume. |
| - | New persistent ESXi VM from the converted disk | **No.** None was created. |
| - | libvirt-managed VM outside KubeVirt | **No.** The test boots used plain QEMU. Inside KubeVirt, virt-launcher drives QEMU through libvirt. |

Facts about the Stage 1G temporary test guests (OBSERVED, Stage 1G sections 7, 9, 11, 13, 15, 17):

| Question | Answer |
|---|---|
| Where did it run? | Inside `conversion-host-01`, three hypervisors deep (Windows -> ESXi -> conversion host -> guest, "L3") |
| What launched it? | A `qemu-system-x86_64` process started directly from the command line (`-machine q35,accel=kvm`, `-daemonize`) |
| Which disk? | A disposable `overlay.qcow2` whose read-only backing file was a 1G output. Three boots: Path A, Path B unmodified, Path B remediated. |
| Firmware | UEFI, OVMF 2024.02 (`OVMF_CODE_4M.fd`), Secure Boot **off**, a fresh variable store each boot, ESP fallback loader `\EFI\BOOT\BOOTX64.EFI` |
| Disk interface | `virtio-blk-pci`, so the guest saw `/dev/vda` |
| Network interface | `virtio-net-pci` on an isolated QEMU user-mode network (`restrict=on`), with port forwards to 127.0.0.1 on the conversion host |
| Did it boot? | **Yes, all three** (root shell on serial in 56 to 67 s; KVM acceleration confirmed) |
| Did nginx work? | **Yes, locally in every boot** (HTTP 200, page sha256 `b9826e18...0046`). From outside the guest, only in the remediated boot. |
| Did networking fail at first? | **Yes, in both unmodified paths.** The NIC was `enp0s3`, but netplan still matched `ens192`, so the guest was healthy but had no address. |
| Remediation | On a second disposable copy only: netplan match by driver `virtio_net`, test address 10.0.2.15/24. Result: routable, and HTTP 200 with the source page hash through the port forward. DNS was **not proven** in 1G (isolated network); it was later observed working in Stage 1I. |
| Retained or deleted? | **Deleted.** Overlays, variable-store copies, sockets and pid files were removed, and "No QEMU process is running." Only the conversion outputs and text evidence were kept. |

The Stage 1I KubeVirt VM, by contrast (OBSERVED, [Stage 1I section 18](../stage-1/stage-1i-first-kubevirt-migration.md#18-gate-i4-first-migration-to-kubevirt)): 2 vCPU, 4096Mi, EFI with Secure Boot off, virtio disk and NIC, masquerade networking. The guest NIC was `enp1s0` and got 10.0.2.2 by DHCP; `AgentConnected` was true; 36 of 36 guest checks passed; and the operator workstation received HTTP 200 with the 267-byte source page through NodePort 30080. The final check in Gate I5-A repeated that result before teardown.

### 4. What is next?

**No next stage is defined.** Stage 1I closed with a clean teardown. Anything further needs a new stage definition with an objective, a scope and a change boundary, and the user's explicit approval. [Section 9](#section-9-next-stage) lists candidate directions drawn from existing designs; they are **PROPOSED, NOT OFFICIAL**.

---

## Section 3. The Complete Lab

```text
CURRENT LAB (as last recorded, Stage 1I, 2026-10-01)

Windows 11 host (laptop, Windows hypervisor off)
   |
   v
VMware Workstation 17.6.4  (VMnet8 NAT 192.168.50.0/24)
   |
   v
Nested ESXi 8.0.3 build 24677879   esxi-8-lab   192.168.50.11   migration-datastore (VMFS-6)
   |
   +-- legacy-source-vm    Vmid 2   POWERED ON    192.168.50.31   nginx :80
   |
   +-- conversion-host-01  Vmid 3   POWERED ON    192.168.50.32   qemu-img / libguestfs / virt-v2v / QEMU+OVMF
   |
   +-- kvm-learning-01     Vmid 1   POWERED ON    192.168.50.30   Stage 1I Terraform and kubectl jump host
```

| VM | Role | Recorded power state | What it is for |
|---|---|---|---|
| `legacy-source-vm` | **Migration source** | Powered on; HTTP 200 with the source page after the Gate I5 teardown | Ubuntu 24.04.5 + nginx; 2 vCPU, 4096 MB, 40 GB thin, UEFI, PVSCSI, VMXNET3, static .31; the unaltered "before" state and the rollback reference (Stage 1C, ADR 006) |
| `conversion-host-01` | **Conversion / inspection environment** | Powered on | Holds the working copy, the 1G artifacts, the Stage 1I prepared image and the Stage 1I text evidence; runs qemu-img, libguestfs, virt-v2v and temporary QEMU/KVM test guests (Stage 1F, ADR 006) |
| `kvm-learning-01` | **KVM/QEMU learning environment; Stage 1I jump host** | Powered on at the Stage 1I Gate I1 precheck | Stage 1B learning VM. In Stage 1I it ran Terraform and kubectl; it keeps the Terraform configuration with an empty state, the retained evidence and `virtctl` (ADR 006) |

Power states are the documented state from the [Stage 1 README](../stage-1/README.md). Live states can differ after operations outside the stages.

```text
STAGE 1I TARGET (BUILT AND VALIDATED 2026-10-01, THEN DESTROYED)

AWS ap-south-1a, one VPC, one public subnet                       (Terraform, 10 resources)
   |
   v
EC2 m8i.xlarge with nested virtualization, CentOS Stream 9 (kernel 5.14.0-754.el9)
   |
   v
Kubernetes v1.36.5 (kubeadm, single node, CRI-O 1.36.6, flannel v0.28.9, EBS CSI)
   |
   v
KubeVirt v1.9.0 + CDI v1.66.1, StorageClass ebs-gp3-encrypted
   |
   v
VirtualMachine legacy-source-vm-migrated (Ubuntu + nginx), NodePort 30080 to the operator /32
```

---

## Section 4. The Disk Journey

```text
VMware VMDK (on ESXi)
  /vmfs/volumes/migration-datastore/legacy-source-vm/
  legacy-source-vm.vmdk (541-byte descriptor) + legacy-source-vm-flat.vmdk (40 GiB thin flat extent)
   |
   v
cold acquisition (Stage 1E): graceful shutdown, scp, sha256 before / copy / after, power back on
   |
   v
Windows golden artifact   C:\VMs\legacy-source-vm\stage-1e\   (GOLDEN, read-only attribute, outside Git)
   |
   v  scp (Stage 1F), hash-verified
conversion-host working copy   /srv/migration-lab/working/   (WORKING, 0444 + chattr +i)
   |
   v
virt-v2v -i disk -if vmdk -o local -of qcow2          (Stage 1G, Path B; Path A was qemu-img)
   |
   v
converted QCOW2   /srv/migration-lab/stage-1g/virt-v2v/local-out/legacy-source-vm-sda   (CONVERTED, 0444)
   |
   v  new copy + netplan DHCP + offline guest agent + first-boot scripts removed   (Stage 1I Gate I1)
prepared QCOW2   /srv/migration-lab/stage-1i/working/legacy-source-vm-prepared.qcow2   (0444 + chattr +i)
   |
   v  QEMU/KVM boot test through a disposable overlay   (Gate I2, 54/54)
   |
   v  SFTP to the EC2 node, sha256 recorded on the node   (Gate I4)
CDI upload -> DataVolume -> 40 GiB gp3 Block PVC, stored raw   (Gate I4; deleted in Gate I5)
   |
   v
KubeVirt VM legacy-source-vm-migrated   (Gate I4; deleted in Gate I5)
```

Three different things. Do not merge them:

| | DISK ARTIFACT | TEST VM | TARGET KUBEVIRT VM |
|---|---|---|---|
| What | A file holding the guest's disk bytes (VMDK or qcow2) | A temporary `qemu-system-x86_64` process booting a disposable overlay of a disk artifact | A Kubernetes `VirtualMachine` object that runs the guest from a PVC through virt-launcher |
| Where | Windows (golden), `conversion-host-01` (working, converted, prepared) | Inside `conversion-host-01` | On the Stage 1I EC2 node |
| Exists now? | **Yes** (OBSERVED, hashed) | **No.** All test boots were deleted. | **No.** Ran in Stage 1I, then DESTROYED in Gate I5. |
| Persistent? | Yes, kept read-only | No | Yes while it existed (standalone DataVolume); removed deliberately |

---

## Section 5. What We Have Actually Proven

Only OBSERVED evidence from PASS stage records counts as PROVEN. Everything here was proven for **one** Linux VM in a lab, on a single temporary node. It is functional evidence, not performance or production evidence.

| Capability | Status | Evidence | Stage |
|---|---|---|---|
| ESXi reboot persistence | **PROVEN** | Controlled reboot; vmk0, route, DNS, vSwitch, datastore, SSH, NTP all persisted ([1A](../stage-1/stage-1a-esxi-reboot-validation.md)) | 1A |
| 64-bit nested Linux guest | **PROVEN** | `kvm-learning-01` booted 64-bit on ESXi (closed Stage 0 N1) | 1B |
| Nested KVM | **PROVEN** | `/dev/kvm`, `kvm_intel nested=Y` in `kvm-learning-01`, and again in `conversion-host-01` | 1B, 1F |
| QEMU | **PROVEN** | A tiny L3 guest booted KVM-accelerated with QEMU 8.2.2; 1G and 1I boot tests used QEMU directly | 1B, 1G, 1I |
| libvirt | **PROVEN** | libvirt 10.0.0 booted the tiny L3 guest in `kvm-learning-01`; in Stage 1I, virt-launcher's libvirt ran the migrated VM | 1B, 1I |
| VirtIO | **PROVEN** | virtio-blk, virtio-scsi, virtio-net seen in 1B; converted guest on virtio-blk and virtio-net in 1G and 1I | 1B, 1G, 1I |
| Real VMware source VM | **PROVEN** | `legacy-source-vm` built, baselined, serves the 267-byte page at .31 ([1C](../stage-1/stage-1c-migration-source.md)) | 1C |
| Cold VMDK acquisition | **PROVEN** | Graceful shutdown, `scp` in 276 s, source back on and re-validated; about 10.5 min downtime ([1E](../stage-1/stage-1e-cold-acquisition.md)) | 1E |
| Byte-identical artifact | **PROVEN** | Flat extent sha256 `72ca45c7...c9e7` equal on source before, copy, and source after | 1E |
| Conversion host | **PROVEN** | `conversion-host-01` with qemu-img 8.2.2, libguestfs 1.52.0, virt-v2v 2.4.0; ADR 006 ([1F](../stage-1/stage-1f-conversion-host.md)) | 1F, 1G |
| qemu-img conversion | **PROVEN** | VMDK -> qcow2 in 5 s; `compare`: identical ([1G](../stage-1/stage-1g-controlled-conversion.md) section 10) | 1G |
| virt-v2v conversion | **PROVEN** | 136 s, exit 0, input unchanged; guest changes recorded (1G section 14) | 1G |
| KVM boot | **PROVEN** | 3 boots with `/dev/kvm` fds, `info kvm` enabled, guest "Hypervisor detected: KVM" | 1G |
| UEFI boot | **PROVEN** (Secure Boot off) | OVMF, fresh variable store, fallback loader; again on KubeVirt. Secure Boot on: NOT TESTED. | 1G, 1I |
| Network remediation | **PROVEN** | 1G: netplan driver match on an isolated network. 1I: netplan `virtio_net` + DHCP baked into the prepared image; DHCP lease and DNS on KubeVirt | 1G, 1I |
| Offline guest preparation | **PROVEN** | Gate I1: guest agent installed offline, 14 first-boot entries removed, 41/41 checks, image hashed and immutable | 1I |
| Pre-transfer boot test | **PROVEN** | Gate I2: the exact prepared image booted under QEMU/KVM, 54/54 checks (second run) | 1I |
| Terraform-built AWS node with nested virtualization | **PROVEN** | Gate I3: 10 resources; `m8i.xlarge` with VT-x, `/dev/kvm` and `kvm_intel nested=Y` | 1I |
| kubeadm + KubeVirt + CDI on that node | **PROVEN** for one version set | Kubernetes v1.36.5, CRI-O 1.36.6, flannel v0.28.9, KubeVirt v1.9.0, CDI v1.66.1, EBS CSI | 1I |
| CDI upload into a Block PVC | **PROVEN** | Gate I4: qcow2 converted to raw on a 40 GiB encrypted gp3 Block PVC | 1I |
| KubeVirt VM from the migrated disk | **PROVEN** | Gate I4: VM Running and Ready, `AgentConnected` true, 36/36 guest checks, identity matches the Stage 1C baseline | 1I |
| End-to-end application check | **PROVEN** | HTTP 200, 267 bytes, source page sha256 from the operator workstation through NodePort 30080 (Gate I4 and Gate I5-A) | 1I |
| Lifecycle-ordered teardown | **PROVEN** | Gate I5: VM, then DataVolume, PVC, PV and EBS; `terraform destroy` of 10 resources; AWS verification; orphan scan found nothing | 1I |

---

## Section 6. What Is NOT Implemented

| Item | Status | Notes / source |
|---|---|---|
| Migration controller / `VirtualMachineMigration` CRD | **NOT IMPLEMENTED**. Direction accepted, implementation deferred; Stage 1I ran by hand under approval gates | ADR 005 |
| Forklift / MTV | **NOT USED** (excluded from Gate I4) | Stage 1I section 18 |
| Repeatable cluster installation | **NOT IN GIT**. Terraform covers only the AWS layer; kubeadm, CRI-O, flannel, KubeVirt, CDI and EBS CSI were installed step by step as the record documents, and the helper scripts were archived outside Git | ADR 002 post-implementation note |
| Cutover | **NOT PERFORMED**. Cold, point-in-time copy; the source kept serving. A production cutover and rollback procedure is not designed | Stage 1H section 29.8, 1G section 21 |
| Compatibility runtime gate G1 to G7 as written | Stage 1I recorded equivalent checks but did not report results against the G1 to G7 labels | [Stage 0 feasibility, status after Stage 1I](../stage-0/feasibility.md#status-after-stage-1i) |
| GitOps delivery | **DEFERRED** ("Later stages") | 1H section 25 |
| Warm migration | **DEFERRED**: reference and study only; no design until ADR 003 is superseded | ADR 003 |
| Live migration, RWX storage | **DEFERRED** (the VM reported `DisksNotLiveMigratable`, as designed) | 1H section 25, ADR 009 |
| Multus / bridge / passt, IP preservation | **DEFERRED** (IP preservation rejected by design) | 1H sections 14, 25 |
| Multi-node / HA / multi-AZ | **DEFERRED** | 1H section 25 |
| Monitoring stack, snapshots, backup, Beta-gate hardening | **DEFERRED** ("After the first migration works") | 1H section 25 |
| Secure Boot on | **NOT TESTED / DEFERRED** | 1G section 21, 1H section 25 |
| EKS comparison | **DEFERRED** (not rejected) | ADR 007 |
| Application modernization (container + Deployment) | **DESIGNED** (Stage 0 concept), **NOT STARTED** | [modernization-model.md](../stage-0/modernization-model.md) |
| `virt-v2v -i vmx`, `-o kubevirt` | **NOT TESTED** | 1G sections 4, 21 |
| S3 staging | **NOT USED**: the image moved over SFTP | Stage 1I section 18.1 |

---

## Section 7. Current Artifact Inventory

### Local lab (OUTSIDE GIT, LOCAL ONLY)

| Artifact | Location | Created by | Purpose | Status |
|---|---|---|---|---|
| Source VM `legacy-source-vm` | ESXi `esxi-8-lab`, Vmid 2; files in `/vmfs/volumes/migration-datastore/legacy-source-vm/` | Stage 1C | Migration source; reference and rollback | **SOURCE**, powered on, disk unchanged since 1E |
| Stage 1E golden VMDK | `C:\VMs\legacy-source-vm\stage-1e\` on Windows: `legacy-source-vm.vmdk` (541 bytes) + `legacy-source-vm-flat.vmdk` (42,949,672,960 bytes, sha256 `72ca45c7...c9e7`) | Stage 1E (`scp`) | Trusted, never-modified copy of the source disk | **GOLDEN**. Windows read-only attribute since 1G; only hashed, never opened by tools. |
| Reference VM metadata | `C:\VMs\legacy-source-vm\stage-1e\reference\` (`.vmx`, `.nvram`, `.vmxf` copies) | Stage 1E | Source facts (CPU, memory, MAC, firmware); not migrated | **REFERENCE** |
| Stage 1F working VMDK | `/srv/migration-lab/working/` on `conversion-host-01` (tool input `legacy-source-vm.vmdk`) | Stage 1F (`scp` from golden) | The only input any conversion tool reads | **WORKING**. `0444` + `chattr +i`. |
| qemu-img QCOW2 | `/srv/migration-lab/stage-1g/qemu-img/legacy-source-vm.qcow2` | Stage 1G, Path A | Container-only conversion proof | **CONVERTED** (experimental), `0444`, sha256 `08c62ac5...5447` |
| virt-v2v QCOW2 | `/srv/migration-lab/stage-1g/virt-v2v/local-out/legacy-source-vm-sda` | Stage 1G, Path B | Guest-aware conversion; source of the prepared image | **CONVERTED**, `0444`, sha256 `94bc1cd6...91c6`, unchanged by Stage 1I |
| virt-v2v XML | `/srv/migration-lab/stage-1g/virt-v2v/local-out/legacy-source-vm.xml` | Stage 1G, Path B | libvirt metadata (q35, OVMF, virtio; 1 vCPU / 2 GiB defaults, not source values) | **CONVERTED** metadata, inspected, not used |
| Network-remediated QCOW2 | `/srv/migration-lab/stage-1g/virt-v2v/remediated/legacy-source-vm-netfix.qcow2` | Stage 1G (copy + one netplan change) | Proof that one netplan change restores networking | **DISPOSABLE test copy** (kept, `0444`, sha256 `5326b130...d3d6`). Test address 10.0.2.15, **not** the migrated config. |
| Prepared migration image | `/srv/migration-lab/stage-1i/working/legacy-source-vm-prepared.qcow2` | Stage 1I Gate I1 | The image that was boot-tested, transferred and imported | **PREPARED**, `0444` + `chattr +i`, sha256 `2b30e195...93b2`. The authoritative copy of what was migrated |
| `conversion-host-01` | ESXi Vmid 3, 192.168.50.32 | Stage 1F | Conversion, inspection and QEMU/KVM boot validation host (ADR 006) | **INFRASTRUCTURE**, powered on |
| `kvm-learning-01` | ESXi Vmid 1, 192.168.50.30 | Stage 1B | Stage 1I jump host | Holds the Terraform configuration and empty state, retained evidence and `virtctl`. Stage 1I credentials and tunnels removed in Gate I5-J |
| Raw evidence and scripts | For example `/srv/migration-lab/stage-1i/evidence/` on `conversion-host-01`, copies on `kvm-learning-01` and the operator workstation (paths recorded in each stage record) | Stages 1A to 1I | Command output, logs, harness scripts | **PRIVATE**, never committed |

### Destroyed in Stage 1I Gate I5 (verified absent)

| Artifact | Stage 1I identifier | Removed by |
|---|---|---|
| KubeVirt VM, VMI, launcher Pod | `default/legacy-source-vm-migrated` | I5-C |
| NodePort Service 30080 | `default/legacy-source-vm-http` | I5-C |
| DataVolume, PVC, PV, migration EBS volume | `default/legacy-source-vm-disk`, `pvc-87c920c1-...`, `vol-0d94fba4ddd3d84d2` | I5-D (owner reference, reclaim policy, CSI driver); verified I5-E |
| 10 Terraform-managed AWS resources and the cluster software on the instance | VPC, subnet, internet gateway, route table and association, security group, IAM role and attachment, instance profile, `m8i.xlarge` instance with its root volume | I5-G; verified I5-H and I5-I |
| Temporary Stage 1I credentials and access paths | Cluster-admin kubeconfig, viewer token, node SSH key, tunnels, variables file and saved plans | I5-J |

### Public repository (GIT, PUBLIC)

| Artifact | Location | Status |
|---|---|---|
| Stage 0 docs | `docs/stage-0/` | PUBLIC |
| Stage 1 docs, learning summary, Stage 1I record and runtime snapshot | `docs/stage-1/` | PUBLIC |
| ADRs 001 to 010 | `docs/adr/` | PUBLIC |
| Diagrams | `docs/diagrams/` (including `stage-0-visual/`, `stage-1-visual/` and the Stage 1I set) | PUBLIC |
| Visual learning pages | `docs/stage-0/stage-0-visual-learning.html`, `docs/stage-1/stage-1-visual-learning.html`, `docs/stage-1/stage-1i-visual-learning.html`, portal `docs/index.html` | PUBLIC (GitHub Pages) |
| Terraform (AWS layer only) | `infra/terraform/stage-1i-target/` | PUBLIC. Committed after Gate I3 in `c13329e`. No state or variables file |
| Kubernetes manifests and templates | `infra/kubernetes/stage-1i/` (kubeadm template, CRI-O drop-in, StorageClass, DataVolume, VM, Service) | PUBLIC |
| This sheet and the context handoff | `docs/project-context/` | PUBLIC. The handoff is historical: it predates Stage 0. |

---

## Section 8. Stage 1H Design and What Stage 1I Built

**What question did Stage 1H answer?** "If we move this converted guest into Kubernetes, what exactly should the target look like, so that the build stage does not have to guess?" It was **design, feasibility and architecture only**. Stage 1I then built it. Differences between design and build are recorded in the "Post-implementation validation" sections of ADRs 007 to 010.

| Area | Stage 1H design | Stage 1I result (OBSERVED) |
|---|---|---|
| Target platform (ADR 007) | Self-managed single-node kubeadm on one EC2 instance with nested virtualization (`m8i.xlarge`, ap-south-1), CentOS Stream 9, CRI-O 1.36, flannel, EBS CSI. EKS deferred, not rejected | Built as designed; Kubernetes v1.36.5, CRI-O 1.36.6, flannel v0.28.9. The newest AMI named "CentOS Stream 9" booted Stream 10 and was replaced through Terraform |
| Versions | KubeVirt v1.9.0; CDI v1.66.1 as a candidate until tested | Both ran; the pairing worked for this migration |
| Storage (ADR 009) | gp3 through EBS CSI, Block, ReadWriteOnce, 40 GiB; qcow2 in transit, CDI upload, raw on the PVC; standalone DataVolume | As designed, through CDI's prime and 43Gi scratch PVCs. The transfer route was left open in 1H; 1I used SFTP with a restricted temporary key |
| Network (ADR 008) | Pod network, masquerade, one virtio NIC, DHCP 10.0.2.2, NodePort 30080 from the operator /32; 192.168.50.31 not preserved | As designed. The guest NIC was `enp1s0`; DNS through 10.96.0.10 worked |
| Guest remediation (ADR 010) | Netplan match `virtio_net` + DHCP on a new copy; guest agent offline; first-boot install removed | Done in Gate I1 with guestfish rather than virt-customize; guest agent connected on KubeVirt |
| AWS footprint | One VPC, one public subnet, internet gateway, security group with TCP 22 and 30080 from the operator /32, instance profile with only the EBS CSI policy, IMDSv2 hop limit 2, destroy after each session. About USD 0.24 per hour (estimate) | 10 Terraform-managed resources, as designed; destroyed in Gate I5 |
| Validation | The 12 checks used since Stage 1C | 36/36 guest checks in Gate I4, external HTTP check repeated in Gate I5-A |

**Nothing from Stage 1I is deployed now.**

---

## Section 9. Next Stage

**No stage after 1I is defined.** The repository does not contain a Stage 1J or later plan, and this sheet does not create one. Any further work needs:

| # | Requirement | Source |
|---|---|---|
| 1 | A written stage definition: objective, scope and change boundary | Same pattern as every Stage 1 sub-stage |
| 2 | The user's explicit approval, per gate where infrastructure is created or destroyed | Stage 1I approval model |
| 3 | For any AWS work: working credentials outside Git, Terraform as the creation path, a reviewed destroy plan and an orphan-volume check | ADR 002, Stage 1H section 29.1, Stage 1I section 19 |

### Candidate directions (PROPOSED, NOT OFFICIAL)

These come from existing designs and from limitations recorded in Stage 1I. Whether any of them is pursued is **your decision**.

- Make the target rebuild repeatable: put the cluster installation steps under version control, next to the Terraform configuration (ADR 002's unmet automation consequence).
- Implement the migration workflow as code: the `VirtualMachineMigration` CRD and controller of ADR 005, starting from the manual Stage 1I sequence.
- Design a real cutover and rollback procedure (not covered in Stage 1).
- Application modernization: the same nginx content as a container, Deployment and Service (Stage 0 modernization model).
- Compare EKS with the self-managed target (ADR 007 deferral).

---

## Section 10. PROPOSED -- Future Project Roadmap

> **PROPOSED. NOT OFFICIAL.** This is not project status and not an approved plan. Each step below is drawn from architecture already documented in Stage 0, Stage 1H or the ADRs. No stage numbers are assigned after 1I.

```text
DONE (Stage 1I, 2026-10-01)
Target platform build + first KubeVirt migration + validation + teardown
   |
   v
Repeatable target build: Terraform + versioned cluster install   (ADR 002 automation consequence)
   |
   v
Migration workflow: discovery/inventory, storage and   (Stage 0 migration-architecture, vmware-source-model,
network mapping, validation, cutover/rollback policy    cdi-storage-model, networking-model)
   |
   v
Controller: VirtualMachineMigration CRD + reconcile    (ADR 005, crd-controller-fundamentals)
   |
   v
Failure/recovery: Retryable, ManualInterventionRequired, (migration-state-machine; rollback = power the
idempotent checkpoints                                   source back on, never silently)
   |
   v
GitOps: Terraform + Git-managed VM definitions         (ADR 002; 1H "later stages"; handoff: Argo CD)
   |
   v
Observability: monitoring stack, phase timings         (1H: "after the first migration works";
                                                        Stage 0 demo criterion 4)
   |
   v
Security hardening: Beta feature gates, IAM, exposure  (1H sections 23, 25)
   |
   v
Application modernization: same nginx content as a     (modernization-model; demo criterion 3)
container -> Deployment -> Service
```

| Area | Status today | What it means | Depends on |
|---|---|---|---|
| A. KubeVirt target build | **DONE once** in Stage 1I (Terraform for AWS, manual cluster install), then destroyed | Terraform-built node, kubeadm, KubeVirt | - |
| B. CDI / storage | **DONE once** in Stage 1I | EBS CSI, gp3 Block PVC, upload DataVolume | A |
| C. First VMware -> KubeVirt migration | **DONE once** in Stage 1I, by hand | The prepared image booted as a KubeVirt VM and passed the checks | A, B, G |
| D. Migration controller / operator | DEFERRED (ADR 005 direction accepted) | `VirtualMachineMigration` CR owns the workflow | C (done by hand) |
| E. Source discovery / inventory | DESIGNED (Stage 0 vmware-source-model); discovery done by hand in 1C/1D | Automated SSH + `vim-cmd` + `.vmx` discovery into `status.sourceInventory` | D |
| F. Storage mapping | DESIGNED (cdi-storage-model); done by hand for one VM | Datastore -> StorageClass rules | B, D |
| G. Network mapping | DESIGNED (networking-model); done by hand for one VM (ADR 008, ADR 010) | Port group -> pod network/masquerade; guest remediation | A |
| H. Validation | Run by hand in 1G (QEMU) and 1I (KubeVirt) | Same checks, automated | C |
| I. Cutover / rollback | Partly DESIGNED (rollback = power source back on); production cutover UNKNOWN; no cutover performed in 1I | When and how traffic moves; source never runs alongside with the same identity | C |
| J. Failure engineering | DESIGNED (state machine) | Retryable versus manual versus terminal transitions, idempotency | D |
| K. Warm migration study | DEFERRED (ADR 003): study only | Precopy, CBT, cutover as theory | Superseding ADR 003; free ESXi API limits |
| L. Application modernization | DESIGNED (modernization-model) | Container image + Deployment + Service with the same content | C (for the comparison) |
| M. GitOps | DEFERRED (1H) | Git-managed manifests; Argo CD named only in the historical handoff and modernization model | A, C |
| N. Observability | DEFERRED (1H: monitoring stack after first migration) | Metrics, logs, phase durations | A, C |
| O. Security | Applied for the lab in 1I (least-privilege instance role, /32 exposure, SELinux enforcing, encrypted volumes, IMDSv2); hardening DEFERRED | Beta gates, API exposure, credentials lifecycle | A |
| P. Portfolio / interview prep | Material exists (Stage 0 interview notes including Stage 1I answers, visual pages, README) | Package the story and evidence | Any of the above |

---

## Section 11. What I Should Learn Before the Next Implementation

Organized for someone fluent in VMware and new to KVM/KubeVirt. Each topic points to the repository page that teaches it.

### MUST UNDERSTAND NOW

| Topic | Why it matters | Read |
|---|---|---|
| VM vs disk | Only the disk bytes move; `.vmx` and `.nvram` are reference only | [learning summary section 7](../stage-1/stage-1-learning-summary.md#7-do-not-confuse-these), [vmware-source-model](../stage-0/vmware-source-model.md) |
| VMDK (descriptor + flat extent) | What the golden artifact physically is | [1D](../stage-1/stage-1d-vmware-source-artifacts.md) |
| KVM / QEMU / libvirt | Three layers: kernel engine, per-VM process, manager. virt-launcher runs libvirt + QEMU. | [virtualization-fundamentals](../stage-0/virtualization-fundamentals.md), [1B](../stage-1/stage-1b-kvm-qemu-fundamentals.md) |
| VirtIO | Replaces PVSCSI and VMXNET3; the reason the NIC name changes | [1G sections 12, 13](../stage-1/stage-1g-controlled-conversion.md) |
| qemu-img vs virt-v2v | Container conversion vs guest conversion; 1H chose virt-v2v output | [1G section 18](../stage-1/stage-1g-controlled-conversion.md) |
| UEFI boot details | OVMF, Secure Boot off, fresh NVRAM, fallback loader; the VM spec must match | [1G section 7](../stage-1/stage-1g-controlled-conversion.md) |
| The netplan problem and fix | `ens192` -> virtio name; match by driver, DHCP | [ADR 010](../adr/010-migration-network-remediation.md) |
| KubeVirt objects | `VirtualMachine` -> `VirtualMachineInstance` -> virt-launcher Pod -> QEMU/KVM | [kubevirt-architecture](../stage-0/kubevirt-architecture.md), [Stage 1I runtime snapshot](../stage-1/stage-1i-runtime-snapshot.md) |
| CDI, DataVolume, PVC | CDI ends at the PVC; KubeVirt starts at the VM; upload vs import; raw at rest | [cdi-storage-model](../stage-0/cdi-storage-model.md), [ADR 009](../adr/009-kubevirt-storage-model.md) |
| Masquerade networking and Services | Why .31 cannot survive; how the NodePort check works | [networking-model](../stage-0/networking-model.md), [ADR 008](../adr/008-kubevirt-network-model.md) |
| CRD and controller basics | KubeVirt and CDI are themselves CRDs + controllers; reading `status` and conditions | [crd-controller-fundamentals](../stage-0/crd-controller-fundamentals.md) |
| Network mapping and storage mapping | Every source NIC and disk needs an explicit target decision | [networking-model section 4](../stage-0/networking-model.md), [cdi-storage-model section 3](../stage-0/cdi-storage-model.md) |
| Lifecycle-ordered teardown | CSI-created volumes are outside Terraform state; delete through the owning layer first | [Stage 1I section 19](../stage-1/stage-1i-first-kubevirt-migration.md#19-i5--final-validation-and-controlled-teardown) |
| Evidence labels | DECIDED is not PROVEN; a design is not a deployment | This sheet, header table |

### GOOD TO KNOW

- kubeadm single-node basics, CRI-O, flannel (ADR 007).
- EBS CSI, gp3, `WaitForFirstConsumer`, Block vs Filesystem volume mode, CDI scratch space (1H section 16).
- `virtctl` (`image-upload`, `console`, `port-forward`) and `kubectl port-forward` to the upload proxy (Stage 1I section 18.2).
- EC2 nested virtualization and why performance is functional-only (Stage 0 feasibility section 4, 1H risk R1).
- The runtime validation gate G1 to G7 and host checklist H1 to H11 (Stage 0 feasibility).
- qemu-guest-agent and the `AgentConnected` condition (1H section 19, Stage 1I section 18.7).
- libguestfs tools used on copies: `guestfish`, `virt-customize`, `virt-diff` (1F, 1G, 1I).
- Terraform plan/apply/destroy discipline for a disposable environment (ADR 002, Stage 1I section 19).

### DEEP DIVE LATER

- The `VirtualMachineMigration` CRD, reconcile loop, finalizers, idempotency (ADR 005, migration-state-machine).
- MTV/Forklift as the industry reference: Provider, NetworkMap, StorageMap, Plan (Stage 0 migration-architecture).
- Warm migration, CBT, snapshots (ADR 003).
- Live migration, RWX storage, Multus, bridge and passt bindings (1H section 25).
- Secure Boot, instancetypes and preferences, MAC preservation.
- GitOps delivery, observability stack, security hardening.
- VM exit mechanics and TCG internals (1B).

---

## Section 12. The Five Most Important Mental Models

### 1. VMware VM anatomy

```text
ESXi host (esxi-8-lab)
+-- migration-datastore (VMFS-6)
    +-- legacy-source-vm/
        +-- legacy-source-vm.vmx          CONFIG     (CPU, memory, NIC, firmware)   -> translated, not copied
        +-- legacy-source-vm.nvram        FIRMWARE   (UEFI variables)               -> not needed (fresh NVRAM boots)
        +-- legacy-source-vm.vmdk         DESCRIPTOR (541-byte text)                -> copied
        +-- legacy-source-vm-flat.vmdk    DISK DATA  (40 GiB thin, locked while on) -> copied COLD
Runtime state (power, IP, running processes)                                         -> only observed

Rule: metadata is translated, disk data is copied, runtime state is only observed.
```

### 2. VMDK -> converted disk -> KubeVirt disk

```text
source VMDK (ESXi, locked while running)
   | cold scp, sha256 before / copy / after                  Stage 1E
   v
GOLDEN   C:\VMs\legacy-source-vm\stage-1e\                  never modified
   | scp, sha256                                            Stage 1F
   v
WORKING  /srv/migration-lab/working/                        0444 + immutable, only tool input
   | new output paths only                                  Stage 1G
   v
CONVERTED  /srv/migration-lab/stage-1g/...                  0444, hashed, outside Git
   | new copy + netplan DHCP + offline agent                Stage 1I Gate I1
   v
PREPARED  /srv/migration-lab/stage-1i/working/...           0444 + immutable, sha256 2b30e195...93b2
   | SFTP to the node, CDI upload                           Stage 1I Gate I4
   v
raw on a 40 GiB Block PVC (EBS gp3, encrypted)              DESTROYED in Gate I5
```

### 3. qemu-img vs virt-v2v

```text
                 qemu-img convert                      virt-v2v
                 ----------------                      --------
changes          the box (container)                   the box AND what is inside (guest)
VMDK -> qcow2    yes                                   yes (-of qcow2)
guest bytes      identical ("Images are identical.")   changed
VMware Tools     left installed (skipped at boot)      purged
initramfs        unchanged                             rebuilt (+ backup)
first-boot job   none                                  installs qemu-guest-agent (needs internet)
netplan ens192   unchanged -> NO NETWORK               unchanged -> NO NETWORK
metadata         none                                  libvirt XML (1 vCPU / 2 GiB defaults)
time             5 s                                   136 s
1H choice        -                                     base for the prepared image

Neither tool fixed networking. One netplan change did.
```

### 4. KubeVirt VM architecture (as run in Stage 1I, then destroyed)

```text
you (kubectl / virtctl)
   |
   v
VirtualMachine  (2 vCPU, 4096Mi, EFI Secure Boot off, virtio disk + NIC, runStrategy Manual)
   |  virt-controller
   v
VirtualMachineInstance  (one running instance)
   |  scheduler + kubelet
   v
virt-launcher Pod  ---- PVC (raw, Block, gp3)  <- DataVolume <- CDI upload <- qcow2
   |  virt-handler
   v
libvirt -> QEMU -> KVM (/dev/kvm, EC2 nested virtualization)
   |
   v
Ubuntu 24.04.5 + nginx  (NIC enp1s0, guest 10.0.2.2 by DHCP)
   |
   v
masquerade NAT in the pod -> pod network (flannel) -> Service NodePort 30080 -> operator /32
```

### 5. Complete migration pipeline

```text
SOURCE                 VMware VM legacy-source-vm (ESXi)           PROVEN   1C
   |
   v
VMDK                   descriptor + flat extent                    PROVEN   1D
   |
   v
cold acquisition       graceful shutdown, scp, sha256              PROVEN   1E
   |
   v
golden artifact        C:\VMs\legacy-source-vm\stage-1e\           PROVEN   1E
   |
   v
working copy           /srv/migration-lab/working/                 PROVEN   1F
   |
   +---- qemu-img ----> QCOW2 (container only)                     PROVEN   1G
   |
   +---- virt-v2v ----> KVM-ready guest (qcow2 + XML)              PROVEN   1G
                          |
                          v
                       prepared image (netplan DHCP + agent)       PROVEN   1I (I1, I2)
                          |
                          v
                       Kubernetes on AWS (Terraform + kubeadm)     PROVEN   1I (I3), DESTROYED
                          |
                          v
                       CDI -> PVC -> KubeVirt VM -> NodePort       PROVEN   1I (I4), DESTROYED
```

---

## Section 13. 30-Second Project Summary

```text
+--------------------------------------------------------------------------+
| We started with a nested ESXi lab and one real VMware VM running nginx.  |
|                                                                          |
| We proved the host is stable, nested KVM works, the disk can be copied   |
| cold and byte-identical, and both qemu-img and virt-v2v conversions boot |
| under QEMU/KVM (UEFI, virtio). One netplan change restores the network.  |
|                                                                          |
| In Stage 1I we prepared the image offline, boot-tested it, built a       |
| temporary single-node kubeadm cluster with KubeVirt and CDI on one AWS   |
| EC2 instance with Terraform, imported the disk through CDI, and ran it   |
| as a KubeVirt VM that served the same page (HTTP 200, same sha256).      |
| Then we tore it all down in lifecycle order and verified nothing was     |
| left in AWS.                                                             |
|                                                                          |
| Limits: one VM, cold copy (about 10.5 min source downtime in 1E), no     |
| cutover, single temporary node, manual workflow, no controller yet.      |
+--------------------------------------------------------------------------+
```

---

## Section 14. One-Page Status Card

```text
PROJECT STATUS AT A GLANCE                         (as recorded after Stage 1I, 2026-10-01)
---------------------------------------------------------------------------------------------
Source             VMware ESXi 8.0.3 (nested, esxi-8-lab, 192.168.50.11)
Source VM          legacy-source-vm (Vmid 2), powered on, 192.168.50.31, nginx, disk unchanged
Golden artifact    created (Stage 1E), C:\VMs\legacy-source-vm\stage-1e\, read-only, outside Git
Working copy       /srv/migration-lab/working/ on conversion-host-01, immutable
Conversion host    conversion-host-01 (Vmid 3), powered on, ADR 006
KVM conversion     proven (Stage 1G): qemu-img + virt-v2v, temporary QEMU/KVM test boots
Prepared image     Stage 1I Gate I1, sha256 2b30e195...93b2, immutable, on conversion-host-01
KubeVirt / CDI     v1.9.0 / v1.66.1 ran in Stage 1I on Kubernetes v1.36.5; DESTROYED
AWS                10 Terraform-managed resources in ap-south-1 (m8i.xlarge); DESTROYED and
                   verified absent; orphan scan clean
Migration          one cold migration performed and validated (I4, I5-A); no cutover
Current stage      Stage 1 complete (1A to 1I PASS)
Next               none defined; needs a new stage definition and explicit approval
---------------------------------------------------------------------------------------------
```
