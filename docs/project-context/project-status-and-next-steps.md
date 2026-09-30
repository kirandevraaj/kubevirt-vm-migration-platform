# Project status and next steps

**Project 1.5: VM-to-Kubernetes Migration Platform (ESXi -> KubeVirt Migration & VM Modernization)**

A navigation and reference sheet: where the project is, what really exists, what was really tested, and what comes next. It adds no new facts, decisions or status. Every statement comes from the repository records. When this sheet and a record disagree, the record wins.

- Authoritative current status for Stage 1: [Stage 1 README](../stage-1/README.md).
- Historical evidence: the individual stage records under [docs/stage-0/](../stage-0/README.md) and [docs/stage-1/](../stage-1/README.md), and the [ADRs](../adr/README.md).
- Status as recorded at the end of Stage 1H (2026-09-28). This document was written without touching the lab, so live power states were **not re-observed** for it.

Labels, exactly as the records use them:

| Label | Meaning |
|---|---|
| **OBSERVED** | Seen in this lab by a command we ran |
| **PROVEN** | Used in this sheet only for capabilities with OBSERVED evidence in a PASS stage record |
| **DOCUMENTED** | Stated by an official source; not run by us |
| **INFERRED** | Reasoned from observations or documentation; not tested |
| **NOT TESTED** | Deliberately not done |
| **DESIGNED** | Written down as a design (Stage 0 or Stage 1H); nothing built |
| **DECIDED** / **DEFERRED** / **UNKNOWN** / **BLOCKED** | Stage 1H decision states |
| **PROPOSED** | A suggestion in this sheet. **Not official, not approved, not a stage.** |

---

## Section 1. Where We Are Now

**One line:** Stages 0 and 1A to 1G are complete. Stage 1H (KubeVirt target design) is done and awaiting your review. Stage 1I is not yet defined. No Kubernetes, KubeVirt, CDI or AWS resource exists.

| Item | Value | Source |
|---|---|---|
| Project | Project 1.5: VM-to-Kubernetes Migration Platform | [README](../../README.md) |
| Current phase | Stage 1 (source environment build-out) | [README](../../README.md) |
| Completed stages | Stage 0; Stage 1A, 1B, 1C, 1D, 1E, 1F, 1G (all **Complete (PASS)**) | [Stage 1 README](../stage-1/README.md) |
| Current stage | **Stage 1H: "Done: H1 to H10 PASS, awaiting user review"** (design only) | [Stage 1 README](../stage-1/README.md) |
| Next stage | **Stage 1I: "Not yet defined"; "Not started; awaiting user approval"** | [Stage 1 README](../stage-1/README.md) |
| Infrastructure state | Local lab only: nested ESXi with 3 guest VMs. **No AWS resource, cluster or Kubernetes object exists.** Stage 1H changed nothing in the lab. | [Stage 1 README](../stage-1/README.md), [Stage 1H record](../stage-1/stage-1h-kubevirt-target-feasibility.md) |
| Repository state | Public docs, ADRs, diagrams and the GitHub Pages learning portal (`docs/index.html`, Stage 0 and Stage 1 visual pages). No disk images, credentials or raw evidence in Git. | Repository |

### Stage status table

| Stage | Status (as recorded) | What it means |
|---|---|---|
| Stage 0 | Complete, with a technical refinement pass (2026-09-27). Its README still says "pending user review"; Stage 1 was later started with explicit approvals. | Theory, architecture, feasibility, ADRs 001 to 005. Nothing installed. |
| 1A | Complete (PASS), 2026-09-27 | ESXi survives a controlled reboot with its configuration intact |
| 1B | Complete (PASS), 2026-09-27 | `kvm-learning-01`: 64-bit nested guest, nested KVM, QEMU, libvirt, VirtIO learned hands-on |
| 1C | Complete (PASS), 2026-09-27 | Real VMware source VM `legacy-source-vm` built and baselined (nginx, static .31) |
| 1D | Complete (PASS), 2026-09-27 | Source VMDK characterized; cold acquisition designed (not executed) |
| 1E | Complete (PASS), 2026-09-27 | Cold copy of the source disk to Windows; byte-identical (sha256) golden artifact |
| 1F | Complete (PASS), 2026-09-27 | `conversion-host-01` built; hash-verified, immutable working copy; read-only inspection |
| 1G | Complete (PASS), 2026-09-28 | qemu-img and virt-v2v conversions; temporary QEMU/KVM test boots; network remediation on a disposable copy; ADR 006 |
| 1H | Done: H1 to H10 PASS, **awaiting user review** | KubeVirt target designed on paper; ADRs 007 to 010. Nothing provisioned. |
| 1I | **Not yet defined**; not started; awaiting user approval | Only entry criteria exist ([1H section 28](../stage-1/stage-1h-kubevirt-target-feasibility.md#28-stage-1i-entry-criteria)) |

No stage numbers after 1I exist in the repository.

---

## Section 2. Four Questions

### 1. What stage are we in?

**Stage 1H is complete as design work and awaiting your review.** Stage 1I has not been defined or started. Everything that could be proven without a Kubernetes cluster has been proven (Stages 1A to 1G). The Kubernetes/KubeVirt target is designed, but nothing is built.

### 2. Is the VMware VMDK -> KVM QCOW2 conversion complete?

**YES, as a controlled experiment. NO, not as a migration.** Stage 1G converted the protected working copy two ways, and both results booted under QEMU/KVM. These are **experimental KVM conversion proofs**, kept as reference artifacts. They are **not the final migration artifact**, and no KubeVirt import has happened. Stage 1H designs a future, new disposable copy (netplan DHCP plus an offline guest agent) as the image to import ([ADR 009](../adr/009-kubevirt-storage-model.md), [ADR 010](../adr/010-migration-network-remediation.md)).

Where everything is (all OBSERVED in the [Stage 1G record](../stage-1/stage-1g-controlled-conversion.md), sections 8 to 17):

| | Path A: qemu-img | Path B: virt-v2v |
|---|---|---|
| What it is | Container conversion only | Guest-aware conversion plus container conversion |
| Input | `/srv/migration-lab/working/legacy-source-vm.vmdk` (protected working copy, `0444` + `chattr +i`) | Same input |
| Command | `qemu-img convert -f vmdk -O qcow2 ...` (5 s) | `virt-v2v -i disk -if vmdk ... -o local -os /srv/migration-lab/stage-1g/virt-v2v/local-out -of qcow2` (136 s) |
| Output | `/srv/migration-lab/stage-1g/qemu-img/legacy-source-vm.qcow2` (sha256 `08c62ac5...5447`) | `/srv/migration-lab/stage-1g/virt-v2v/local-out/legacy-source-vm-sda` (qcow2, sha256 `94bc1cd6...91c6`) plus `legacy-source-vm.xml` (libvirt XML) |
| Guest changed? | No. `qemu-img compare`: "Images are identical." | Yes. open-vm-tools purged, initramfs rebuilt, virtio alias, first-boot job for qemu-guest-agent. netplan, fstab, GRUB config and identity untouched. |
| Remediated result | - | `/srv/migration-lab/stage-1g/virt-v2v/remediated/legacy-source-vm-netfix.qcow2` (sha256 `5326b130...d3d6`): a second copy with **one** netplan change (match by driver `virtio_net`, test address 10.0.2.15) |

- **Where they live:** on **`conversion-host-01`** (a VM on ESXi), in `/srv/migration-lab/stage-1g/`. They are **not** on the Windows host and not in a datastore folder of their own. Their space is inside the conversion host's virtual disk on `migration-datastore`.
- **Git:** **not committed.** They are outside Git by design.
- **Protection:** each kept output is mode `0444` and hashed. Outputs were re-hashed after every boot and at the end. Boots used disposable overlays, so the outputs never changed.
- **The source VMDK was not modified.** `legacy-source-vm` was never shut down or touched in 1G (0 snapshots, .31, HTTP 200 before and after).
- **The Stage 1E golden artifact was not modified.** Only `Get-FileHash` read it. It was given the Windows read-only attribute, with hash, size and timestamp unchanged.
- qcow2 was used as an experimental working format in 1G. The later **target format decision** (Stage 1H, ADR 009) is: qcow2 in transit, raw on a Block PVC. DESIGNED, not done.

### 3. Did we deploy a VM using the converted disk?

**No persistent VM was deployed from the converted disk. NO KubeVirt VM has been deployed.**

What happened is narrower: the converted disks were booted in **temporary QEMU/KVM test guests** inside `conversion-host-01`.

| # | Thing | Was it created from the converted disk? |
|---|---|---|
| A | **VMware source VM** (`legacy-source-vm`, ESXi Vmid 2) | No. It is the original source, unchanged, still running on ESXi. It was never pointed at any converted image. |
| B | **`conversion-host-01`** (ESXi Vmid 3) | No. It is the Ubuntu workbench VM that holds the tools and the disks. It hosted the test guests; it did not become the migrated VM. |
| C | **Temporary QEMU/KVM test guest** | **Yes, three times, one at a time, each deleted afterwards.** Details below. |
| - | New persistent ESXi VM from the converted disk | **No.** None was created. |
| - | libvirt-managed VM | **No.** The boots used plain QEMU "directly with QEMU (no libvirt)". virt-v2v's XML was inspected, not used. (Stage 1B used libvirt with a tiny test image in `kvm-learning-01`; that was never the converted disk.) |
| - | KubeVirt VM | **No.** No cluster exists. |

Facts about the temporary test guests (OBSERVED, Stage 1G sections 7, 9, 11, 13, 15, 17):

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
| Remediation | On a second disposable copy only: netplan match by driver `virtio_net`, test address 10.0.2.15/24. Result: routable, and HTTP 200 with the source page hash through the port forward. DNS was **not proven** (isolated network). |
| Retained or deleted? | **Deleted.** Overlays, variable-store copies, sockets and pid files were removed (listed in the evidence), and "No QEMU process is running." Only the conversion outputs and text evidence were kept. |

**Remember:** the Stage 1G test guests were **temporary validation guests running inside conversion-host-01**, not the eventual KubeVirt VM. **NO KubeVirt VM has been deployed.**

### 4. What is next?

**Repository's next step:** review Stage 1H, which is recorded as "awaiting user review". **Stage 1I: Not yet defined.** It is "Not started; awaiting user approval". Stage 1I needs your explicit approval with objective, scope and change boundary written down, and working AWS credentials (1H unknown U15, **BLOCKED**). See [Section 9](#section-9-next-stage).

**Likely next progression (PROPOSED, NOT OFFICIAL):** after 1H is approved, define Stage 1I around building the designed single-node target and running the first real KubeVirt boot of the prepared image. That is what the 1H design and the [Stage 1 learning summary](../stage-1/stage-1-learning-summary.md) point toward ("building the target and running the first real KubeVirt boot"). Nothing about 1I's scope is decided.

---

## Section 3. The Complete Lab

```text
CURRENT LAB (as recorded after Stage 1H)

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
   +-- kvm-learning-01     Vmid 1   POWERED OFF   192.168.50.30 when running
```

| VM | Role | Recorded power state | What it is for |
|---|---|---|---|
| `legacy-source-vm` | **Migration source** | Powered on | Ubuntu 24.04.5 + nginx; 2 vCPU, 4096 MB, 40 GB thin, UEFI, PVSCSI, VMXNET3, static .31; the unaltered "before" state and the rollback reference (Stage 1C, ADR 006) |
| `conversion-host-01` | **Conversion / inspection environment** | Powered on | Holds the working copy and the 1G artifacts; runs qemu-img, libguestfs, virt-v2v and temporary QEMU/KVM test guests (Stage 1F, ADR 006) |
| `kvm-learning-01` | **KVM/QEMU learning environment** | Powered off | Stage 1B learning VM for nested KVM, QEMU, libvirt and VirtIO; not used for conversion (ADR 006) |

All three: no snapshots. Power states are the documented state from the [Stage 1 README](../stage-1/README.md). The [learning summary](../stage-1/stage-1-learning-summary.md#11-current-lab-state) notes that live states can differ after ad-hoc operations outside the stages.

```text
FUTURE TARGET (DESIGNED in Stage 1H, NOT YET BUILT)

AWS ap-south-1, one VPC, one public subnet
   |
   v
EC2 m8i.xlarge with nested virtualization, CentOS Stream 9
   |
   v
Kubernetes 1.36 (kubeadm, single node, CRI-O 1.36, flannel, EBS CSI)
   |
   v
KubeVirt v1.9.0 + CDI v1.66.1
   |
   v
VirtualMachine legacy-source-vm (Ubuntu + nginx)
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
qemu-img convert -f vmdk -O qcow2          (Stage 1G, Path A)
   |
   v
QCOW2   /srv/migration-lab/stage-1g/qemu-img/legacy-source-vm.qcow2   (CONVERTED, 0444)
```

```text
VMware working copy   /srv/migration-lab/working/legacy-source-vm.vmdk
   |
   v
virt-v2v -i disk -if vmdk -o local -of qcow2          (Stage 1G, Path B)
   |
   v
converted QCOW2   /srv/migration-lab/stage-1g/virt-v2v/local-out/legacy-source-vm-sda  (+ legacy-source-vm.xml)
   |                                                          (CONVERTED, 0444)
   +--> copy + one netplan change --> /srv/migration-lab/stage-1g/virt-v2v/remediated/legacy-source-vm-netfix.qcow2
   |                                                          (CONVERTED + remediated test copy, 0444)
   v
QEMU/KVM test boot   (disposable overlay on top of an output; deleted after each boot)
```

Three different things. Do not merge them:

| | DISK ARTIFACT | TEST VM | TARGET KUBEVIRT VM |
|---|---|---|---|
| What | A file holding the guest's disk bytes (VMDK or qcow2) | A temporary `qemu-system-x86_64` process booting a disposable overlay of a disk artifact | A Kubernetes `VirtualMachine` object that runs the guest from a PVC through virt-launcher |
| Where | Windows (golden), `conversion-host-01` (working and converted) | Inside `conversion-host-01` | Designed for an EC2 node in AWS |
| Exists now? | **Yes** (OBSERVED, hashed) | **No.** Three ran in 1G, all deleted. | **No.** DESIGNED only (Stage 1H). |
| Persistent? | Yes, kept read-only | No | Would be; not built |

---

## Section 5. What We Have Actually Proven

Only OBSERVED evidence from PASS stage records counts as PROVEN.

| Capability | Status | Evidence | Stage |
|---|---|---|---|
| ESXi reboot persistence | **PROVEN** | Controlled reboot; vmk0, route, DNS, vSwitch, datastore, SSH, NTP all persisted ([1A](../stage-1/stage-1a-esxi-reboot-validation.md)) | 1A |
| 64-bit nested Linux guest | **PROVEN** | `kvm-learning-01` booted 64-bit on ESXi (closed Stage 0 N1) | 1B |
| Nested KVM | **PROVEN** | `/dev/kvm`, `kvm_intel nested=Y` in `kvm-learning-01`, and again in `conversion-host-01` | 1B, 1F |
| QEMU | **PROVEN** | A tiny L3 guest booted KVM-accelerated with QEMU 8.2.2; 1G boots used QEMU directly | 1B, 1G |
| libvirt | **PROVEN** (learning image only) | libvirt 10.0.0 booted the tiny L3 guest in `kvm-learning-01`. Not used with the converted disk. | 1B |
| VirtIO | **PROVEN** | virtio-blk, virtio-scsi, virtio-net seen in 1B; converted guest on virtio-blk and virtio-net in 1G | 1B, 1G |
| Real VMware source VM | **PROVEN** | `legacy-source-vm` built, baselined, serves the 267-byte page at .31 ([1C](../stage-1/stage-1c-migration-source.md)) | 1C |
| Cold VMDK acquisition | **PROVEN** | Graceful shutdown, `scp` in 276 s, source back on and re-validated; about 10.5 min downtime ([1E](../stage-1/stage-1e-cold-acquisition.md)) | 1E |
| Byte-identical artifact | **PROVEN** | Flat extent sha256 `72ca45c7...c9e7` equal on source before, copy, and source after | 1E |
| Conversion host | **PROVEN** | `conversion-host-01` with qemu-img 8.2.2, libguestfs 1.52.0, virt-v2v 2.4.0; ADR 006 ([1F](../stage-1/stage-1f-conversion-host.md)) | 1F, 1G |
| qemu-img conversion | **PROVEN** | VMDK -> qcow2 in 5 s; `compare`: identical ([1G](../stage-1/stage-1g-controlled-conversion.md) section 10) | 1G |
| virt-v2v conversion | **PROVEN** | 136 s, exit 0, input unchanged; guest changes recorded (1G section 14) | 1G |
| KVM boot | **PROVEN** | 3 boots with `/dev/kvm` fds, `info kvm` enabled, guest "Hypervisor detected: KVM" | 1G |
| UEFI boot | **PROVEN** (Secure Boot off) | OVMF, fresh variable store, fallback loader. Secure Boot on: NOT TESTED. | 1G |
| VirtIO disk boot | **PROVEN** | Root on `vda` (virtio-blk), mounts by UUID, no initramfs change needed on Path A | 1G |
| Network remediation | **PROVEN** (isolated test network) | netplan driver match gave a routable `enp0s3`, 10.0.2.15, default route. DNS not proven. | 1G |
| nginx validation | **PROVEN** (under QEMU/KVM) | HTTP 200 with the source page sha256, locally in all boots, and from outside the guest in the remediated boot | 1G |
| KubeVirt target architecture | **DESIGN ONLY** | ADRs 007 to 010, 1H record; H1 to H10 PASS as documentation gates | 1H |

**Not in this table on purpose:** KubeVirt deployment, CDI import, AWS deployment. None has happened.

---

## Section 6. Important Things NOT Yet Implemented

| Item | Status | Notes / source |
|---|---|---|
| AWS target environment (VPC, EC2 node) | **DESIGNED, NOT STARTED**. Build BLOCKED on AWS credentials (U15). | 1H section 22, ADR 007, ADR 002 |
| Kubernetes cluster (1.36, kubeadm, single node) | **DESIGNED, NOT STARTED** | ADR 007 |
| KubeVirt installation (v1.9.0) | **DESIGNED, NOT STARTED** | ADR 007 |
| CDI installation (v1.66.1) | **DESIGNED, NOT STARTED**. The pairing is a "candidate until the runtime gate passes". | 1H section 8 |
| Compatibility runtime gate G1 to G7 | **NOT STARTED** | [Stage 0 feasibility section 3](../stage-0/feasibility.md#3-compatibility-tuple-and-runtime-validation-gate) |
| StorageClass / PVC (gp3, Block, RWO, 40 GiB) | **DESIGNED, NOT STARTED** | ADR 009 |
| DataVolume (CDI upload) | **DESIGNED, NOT STARTED** | 1H section 18 |
| KubeVirt `VirtualMachine` | **DESIGNED, NOT STARTED** | 1H sections 18, 20 |
| Final import image (netplan DHCP + offline qemu-guest-agent on a new disposable copy) | **DESIGNED, NOT STARTED** | ADR 010, 1H sections 15, 19 |
| Route for moving the qcow2 to AWS | **DEFERRED** ("a Stage 1I detail") | 1H sections 18, 25 |
| Actual VMware -> KubeVirt migration | **NOT STARTED** | 1H: "No migration occurred" |
| Target network implementation (masquerade, NodePort 30080) | **DESIGNED, NOT STARTED** | ADR 008 |
| Target storage implementation (EBS CSI) | **DESIGNED, NOT STARTED** | ADR 009 |
| Migration controller / `VirtualMachineMigration` CRD | **DEFERRED**. Direction accepted, implementation deferred; language/framework deferred. | ADR 005 |
| Terraform code | **DEFERRED** ("Later stages") | 1H section 25, ADR 002 |
| GitOps delivery | **DEFERRED** ("Later stages") | 1H section 25 |
| Warm migration | **DEFERRED**: reference and study only; no design until ADR 003 is superseded | ADR 003 |
| Live migration, RWX storage | **DEFERRED** | 1H section 25 |
| Multus / bridge / passt, IP preservation | **DEFERRED** (IP preservation rejected by design) | 1H sections 14, 25 |
| Multi-node / HA / multi-AZ | **DEFERRED** | 1H section 25 |
| Monitoring stack, snapshots, backup, Beta-gate hardening | **DEFERRED** ("After the first migration works") | 1H section 25 |
| Secure Boot on | **NOT TESTED / DEFERRED** | 1G section 21, 1H section 25 |
| EKS comparison | **DEFERRED** (not rejected) | ADR 007 |
| Application modernization (container + Deployment) | **DESIGNED** (Stage 0 concept), **NOT STARTED** | [modernization-model.md](../stage-0/modernization-model.md) |
| `virt-v2v -i vmx`, `-o kubevirt` | **NOT TESTED** | 1G sections 4, 21 |

---

## Section 7. Current Artifact Inventory

### Local lab (OUTSIDE GIT, LOCAL ONLY)

| Artifact | Location | Created by | Purpose | Status |
|---|---|---|---|---|
| Source VM `legacy-source-vm` | ESXi `esxi-8-lab`, Vmid 2; files in `/vmfs/volumes/migration-datastore/legacy-source-vm/` | Stage 1C | Migration source; reference and rollback | **SOURCE**, powered on, unchanged since 1E |
| Stage 1E golden VMDK | `C:\VMs\legacy-source-vm\stage-1e\` on Windows: `legacy-source-vm.vmdk` (541 bytes) + `legacy-source-vm-flat.vmdk` (42,949,672,960 bytes, sha256 `72ca45c7...c9e7`) | Stage 1E (`scp`) | Trusted, never-modified copy of the source disk | **GOLDEN**. Windows read-only attribute since 1G; only hashed, never opened by tools. |
| Reference VM metadata | `C:\VMs\legacy-source-vm\stage-1e\reference\` (`.vmx`, `.nvram`, `.vmxf` copies) | Stage 1E | Source facts (CPU, memory, MAC, firmware); not migrated | **REFERENCE** |
| Stage 1F working VMDK | `/srv/migration-lab/working/` on `conversion-host-01` (tool input `legacy-source-vm.vmdk`) | Stage 1F (`scp` from golden) | The only input any tool reads | **WORKING**. `0444` + `chattr +i`, hash-checked before and after every step. |
| qemu-img QCOW2 | `/srv/migration-lab/stage-1g/qemu-img/legacy-source-vm.qcow2` | Stage 1G, Path A | Container-only conversion proof | **CONVERTED** (experimental), `0444`, sha256 `08c62ac5...5447` |
| virt-v2v QCOW2 | `/srv/migration-lab/stage-1g/virt-v2v/local-out/legacy-source-vm-sda` | Stage 1G, Path B | Guest-aware conversion proof; source of the future import copy | **CONVERTED** (experimental), `0444`, sha256 `94bc1cd6...91c6` |
| virt-v2v XML | `/srv/migration-lab/stage-1g/virt-v2v/local-out/legacy-source-vm.xml` | Stage 1G, Path B | libvirt metadata (q35, OVMF, virtio; 1 vCPU / 2 GiB defaults, not source values) | **CONVERTED** metadata, inspected, not used |
| Network-remediated QCOW2 | `/srv/migration-lab/stage-1g/virt-v2v/remediated/legacy-source-vm-netfix.qcow2` | Stage 1G (copy + one netplan change) | Proof that one netplan change restores networking | **DISPOSABLE test copy** (kept, `0444`, sha256 `5326b130...d3d6`). Test address 10.0.2.15, **not** the target config. |
| Boot overlays, variable-store copies | Were in `/srv/migration-lab/stage-1g/boot-tests/<name>/` | Stage 1G | Disposable layers for test boots | **DELETED** |
| `conversion-host-01` | ESXi Vmid 3, 192.168.50.32 | Stage 1F | Conversion, inspection and QEMU/KVM boot validation host (ADR 006) | **INFRASTRUCTURE**, powered on |
| Raw evidence and scripts | For example `C:\VMs\conversion-host-01\stage-1g\` and `C:\VMs\conversion-host-01\stage-1h\` (paths recorded in the 1G and 1H records) | Stages 1A to 1H | Command output, logs, harness scripts | **PRIVATE**, never committed |
| Final import image (netplan DHCP + offline guest agent) | Not created | Future (1H design) | What CDI would receive | **FUTURE** |
| DataVolume / PVC / `VirtualMachine` | Not created | Future (1H design) | Target disk and VM | **FUTURE** |

### Public repository (GIT, PUBLIC)

| Artifact | Location | Status |
|---|---|---|
| Stage 0 docs | `docs/stage-0/` | PUBLIC |
| Stage 1 docs and learning summary | `docs/stage-1/` | PUBLIC |
| ADRs 001 to 010 | `docs/adr/` | PUBLIC |
| Diagrams | `docs/diagrams/` (including `stage-0-visual/` and `stage-1-visual/`) | PUBLIC |
| Visual learning pages | `docs/stage-0/stage-0-visual-learning.html`, `docs/stage-1/stage-1-visual-learning.html`, portal `docs/index.html` | PUBLIC (GitHub Pages) |
| This sheet and the context handoff | `docs/project-context/` | PUBLIC. The handoff is historical: it predates the Stage 1 build-out. |

---

## Section 8. Stage 1H in Simple Words

**What question did Stage 1H answer?** "If we move this converted guest into Kubernetes, what exactly should the target look like, so that the build stage does not have to guess?" It was **design, feasibility and architecture only**.

- **Target Kubernetes choice (DECIDED, ADR 007):** a self-managed, single-node kubeadm cluster on one EC2 instance with nested virtualization (`m8i.xlarge`, ap-south-1), CentOS Stream 9, CRI-O 1.36, flannel, the EBS CSI driver. EKS was investigated and **deferred**, not rejected. Bare metal is only a costed fallback.
- **KubeVirt version:** v1.9.0. **CDI:** v1.66.1, a candidate until the runtime gate passes, because no official KubeVirt-to-CDI matrix exists.
- **Kubernetes version:** 1.36 (patch pinned at build time).
- **Storage (ADR 009):** EBS gp3 through the EBS CSI driver, **Block** volume mode, **ReadWriteOnce**, 40 GiB (the source's exact size). The disk travels as **qcow2** (about 2.7 GiB) and is uploaded through a CDI upload DataVolume. CDI stores it as **raw** on the PVC. The DataVolume is standalone, so deleting the VM does not delete the disk. Not live-migratable, which is accepted for a cold migration.
- **Network (ADR 008):** pod network with the **masquerade** binding, one virtio NIC, no Multus. The guest gets 10.0.2.2 by DHCP. **192.168.50.31 is not preserved.** A NodePort Service (30080), reachable only from the operator's /32, is the external check. Continuity is proven by content (same page hash), not by address.
- **Guest network remediation (ADR 010):** the Stage 1G fix, but with DHCP: netplan matches driver `virtio_net`, `dhcp4: true`. Applied offline to a **new disposable copy** of the virt-v2v output, never to the golden, working or kept 1G images.
- **Guest agent:** pre-install `qemu-guest-agent` offline at conversion time and remove virt-v2v's first-boot internet install. Useful but not a pass/fail requirement.
- **AWS design:** one VPC, one public subnet, an internet gateway, a security group allowing only TCP 22 and 30080 from the operator /32, an instance profile with only the EBS CSI policy, IMDSv2 (hop limit 2), Terraform apply and destroy per session. About USD 0.24 per hour while running, about USD 174 if left on for a month.
- **Validation:** the same 12 checks used since Stage 1C, run inside the guest and through the Service.

**Nothing has been deployed yet.**

---

## Section 9. Next Stage

**Stage 1I is not yet defined.** The repository records it as "Not yet defined" and "Not started; awaiting user approval". No official Stage 1I plan exists, and this sheet does not create one.

### REQUIRED BEFORE 1I (from the repository)

| # | Requirement | Status | Source |
|---|---|---|---|
| 1 | User review of Stage 1H | **Pending** ("awaiting user review") | [Stage 1 README](../stage-1/README.md) |
| 2 | The user's explicit approval of Stage 1I, with **objective, scope and change boundary written down** | **Not given** | [1H section 28](../stage-1/stage-1h-kubevirt-target-feasibility.md#28-stage-1i-entry-criteria) |
| 3 | **Working AWS credentials** (U15) | **BLOCKED** | 1H sections 26, 28; ADR 002 |
| 4 | Technical entry criteria from 1H section 28 (target, tuple on paper, node OS, virtualization path, network, remediation, IP decision, storage, format, CDI workflow, agent strategy, AWS footprint, source healthy, golden protected, no Kubernetes resources, no migration) | **Met** at the end of 1H | 1H section 28 |

Stage 0's destination-track criteria also still describe any AWS or Kubernetes work ([Stage 0 README](../stage-0/README.md#stage-1-entry-criteria)): credentials verified with a read-only call and stored outside Git; Terraform as the only creation path, with a destroy plan and cost guardrails; the runtime gate G1 to G7 as the acceptance test; the host-requirement checklist H1 to H11. Instance family, Region and AMI were chosen in 1H (the AMI ID is re-resolved at build time, U14).

### LIKELY WORK IN 1I (PROPOSED, NOT OFFICIAL)

These items are what the 1H record says a "future, separately approved stage" would do. Only the transfer route is explicitly called "a Stage 1I detail". Whether 1I contains all, some or none of this is **your decision**.

- Recover or re-issue AWS credentials, stored outside Git (U15).
- Pre-flight check that `m8i.xlarge` reports nested virtualization in ap-south-1 (U1).
- Prepare the import image on `conversion-host-01`: a new copy of the virt-v2v output, the netplan DHCP design, the offline guest agent, first-boot scripts removed, hashed, read-only (1H sections 15, 18, 19).
- Decide the qcow2 transfer route (DEFERRED to 1I).
- Build the AWS node and single-node cluster with Terraform, then install KubeVirt and CDI (ADR 007).
- Run the host checks (`virt-host-validate qemu`) and the runtime gate G1 to G7.
- CDI upload into the Block PVC, create the `VirtualMachine`, run the 12 validation checks through the Service.
- Tear down (ADR 002).

---

## Section 10. PROPOSED -- Future Project Roadmap

> **PROPOSED. NOT OFFICIAL.** This is not project status and not an approved plan. Only 1I is an official stage name, and it is still undefined. Each step below is drawn from architecture already documented in Stage 0, Stage 1H or the ADRs. No stage numbers are assigned after 1I.

```text
1I  (official name, not yet defined)
Target platform build + first KubeVirt boot          (ADR 007, 1H sections 18-22)
   |
   v
KubeVirt/CDI validation: runtime gate G1-G7            (Stage 0 feasibility section 3)
   |
   v
First migrated VM: legacy-source-vm on KubeVirt,       (1H section 21; Stage 0 demo success criteria 1, 2)
same page hash through the Service
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
   |
   v
Portfolio / interview packaging                         (interview-notes, visual learning pages)
```

| Area | Status today | What it means | Depends on |
|---|---|---|---|
| A. KubeVirt target build | DESIGNED (ADR 007); build BLOCKED on credentials | Terraform-built node, kubeadm, KubeVirt | 1I definition and approval; AWS credentials |
| B. CDI / storage | DESIGNED (ADR 009) | EBS CSI, gp3 Block PVC, upload DataVolume | A |
| C. First VMware -> KubeVirt migration | DESIGNED (1H section 20) | The prepared image boots as a KubeVirt VM and passes the 12 checks | A, B, G, prepared image |
| D. Migration controller / operator | DEFERRED (ADR 005 direction accepted) | `VirtualMachineMigration` CR owns the workflow | C working by hand first (INFERRED ordering) |
| E. Source discovery / inventory | DESIGNED (Stage 0 vmware-source-model); discovery done by hand in 1C/1D | Automated SSH + `vim-cmd` + `.vmx` discovery into `status.sourceInventory` | D |
| F. Storage mapping | DESIGNED (cdi-storage-model; ADR 009 for one VM) | Datastore -> StorageClass rules | B, D |
| G. Network mapping | DESIGNED (networking-model; ADR 008, ADR 010 for one VM) | Port group -> pod network/masquerade; guest remediation | A |
| H. Validation | DESIGNED (1H section 21, 12 checks); run under QEMU in 1G | Same checks on KubeVirt | C |
| I. Cutover / rollback | Partly DESIGNED (rollback = power source back on); production cutover UNKNOWN (1G section 21) | When and how traffic moves; source never runs alongside with the same identity | C |
| J. Failure engineering | DESIGNED (state machine) | Retryable versus manual versus terminal transitions, idempotency | D |
| K. Warm migration study | DEFERRED (ADR 003): study only | Precopy, CBT, cutover as theory | Superseding ADR 003; free ESXi API limits |
| L. Application modernization | DESIGNED (modernization-model) | Container image + Deployment + Service with the same content | C (for the comparison) |
| M. GitOps | DEFERRED (1H) | Git-managed manifests; Argo CD named only in the historical handoff and modernization model | A, C |
| N. Observability | DEFERRED (1H: monitoring stack after first migration) | Metrics, logs, phase durations | A, C |
| O. Security | DESIGNED for the lab (1H section 23); hardening DEFERRED | Least-privilege IAM, /32 exposure, SELinux enforcing, Beta gates | A |
| P. Portfolio / interview prep | Material exists (Stage 0 interview notes, visual pages) | Package the story and evidence | Any of the above |

---

## Section 11. What I Should Learn Before the Next Implementation

Organized for someone fluent in VMware and new to KVM/KubeVirt. Each topic points to the repository page that teaches it.

### MUST UNDERSTAND NOW

| Topic | Why it matters for 1I | Read |
|---|---|---|
| VM vs disk | Only the disk bytes move; `.vmx` and `.nvram` are reference only | [learning summary section 7](../stage-1/stage-1-learning-summary.md#7-do-not-confuse-these), [vmware-source-model](../stage-0/vmware-source-model.md) |
| VMDK (descriptor + flat extent) | What the golden artifact physically is | [1D](../stage-1/stage-1d-vmware-source-artifacts.md) |
| KVM / QEMU / libvirt | Three layers: kernel engine, per-VM process, manager. virt-launcher runs libvirt + QEMU. | [virtualization-fundamentals](../stage-0/virtualization-fundamentals.md), [1B](../stage-1/stage-1b-kvm-qemu-fundamentals.md) |
| VirtIO | Replaces PVSCSI and VMXNET3; the reason the NIC name changes | [1G sections 12, 13](../stage-1/stage-1g-controlled-conversion.md) |
| qemu-img vs virt-v2v | Container conversion vs guest conversion; 1H chose virt-v2v output | [1G section 18](../stage-1/stage-1g-controlled-conversion.md) |
| UEFI boot details | OVMF, Secure Boot off, fresh NVRAM, fallback loader; the VM spec must match | [1G section 7](../stage-1/stage-1g-controlled-conversion.md) |
| The netplan problem and fix | `ens192` -> virtio name; match by driver, DHCP | [ADR 010](../adr/010-migration-network-remediation.md) |
| KubeVirt objects | `VirtualMachine` -> `VirtualMachineInstance` -> virt-launcher Pod -> QEMU/KVM | [kubevirt-architecture](../stage-0/kubevirt-architecture.md) |
| CDI, DataVolume, PVC | CDI ends at the PVC; KubeVirt starts at the VM; upload vs import; raw at rest | [cdi-storage-model](../stage-0/cdi-storage-model.md), [ADR 009](../adr/009-kubevirt-storage-model.md) |
| Masquerade networking and Services | Why .31 cannot survive; how the NodePort check works | [networking-model](../stage-0/networking-model.md), [ADR 008](../adr/008-kubevirt-network-model.md) |
| CRD and controller basics | KubeVirt and CDI are themselves CRDs + controllers; reading `status` and conditions | [crd-controller-fundamentals](../stage-0/crd-controller-fundamentals.md) |
| Network mapping and storage mapping | Every source NIC and disk needs an explicit target decision | [networking-model section 4](../stage-0/networking-model.md), [cdi-storage-model section 3](../stage-0/cdi-storage-model.md) |
| Evidence labels | DECIDED is not PROVEN; a design is not a deployment | This sheet, header table |

### GOOD TO KNOW

- kubeadm single-node basics, CRI-O, flannel (ADR 007).
- EBS CSI, gp3, `WaitForFirstConsumer`, Block vs Filesystem volume mode, CDI scratch space (1H section 16).
- `virtctl` (`image-upload`, `console`, `vnc`) and `kubectl port-forward` to the upload proxy (1H section 18).
- EC2 nested virtualization and why performance is functional-only (Stage 0 feasibility section 4, 1H risk R1).
- The runtime validation gate G1 to G7 and host checklist H1 to H11 (Stage 0 feasibility).
- qemu-guest-agent and the `AgentConnected` condition (1H section 19).
- libguestfs tools used on copies: `guestfish`, `virt-customize`, `virt-diff` (1F, 1G).
- Terraform plan/apply/destroy discipline for a disposable environment (ADR 002).

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

### 2. VMDK -> converted disk

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
   | (future) new disposable copy + netplan DHCP + offline agent   DESIGNED (1H)
   v
IMPORT IMAGE (qcow2)  ->  CDI  ->  raw on Block PVC         DESIGNED, not built
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
1H choice        -                                     base for the future import image

Neither tool fixed networking. One netplan change did.
```

### 4. KubeVirt VM architecture (DESIGNED, NOT DEPLOYED)

```text
you (kubectl / virtctl)
   |
   v
VirtualMachine  (desired state: 2 vCPU, 4096 Mi, EFI Secure Boot off, virtio disk + NIC, runStrategy Manual)
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
Ubuntu 24.04.5 + nginx  (guest 10.0.2.2 by DHCP)
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
                       QEMU/KVM temporary test boot                PROVEN   1G
                       (UEFI, virtio, nginx HTTP 200)
                          |
                          v
                       import image (netplan DHCP + agent)         DESIGNED 1H
                          |
                          v
                       CDI -> PVC -> KubeVirt VM                   DESIGNED 1H, NOT BUILT
                          |
                          v
                       Kubernetes on AWS                           DESIGNED 1H, NOT PROVISIONED
```

---

## Section 13. 30-Second Project Summary

```text
+--------------------------------------------------------------------------+
| We started with a nested ESXi lab and one real VMware VM running nginx.  |
|                                                                          |
| We proved the host is stable, nested KVM works, the disk can be copied   |
| cold and byte-identical, and both qemu-img and virt-v2v conversions boot |
| under QEMU/KVM (UEFI, virtio). One netplan change restores the network   |
| and nginx serves the same page.                                          |
|                                                                          |
| We now have a protected golden disk, converted qcow2 images on           |
| conversion-host-01, and a written KubeVirt target design (ADRs 007-010). |
|                                                                          |
| We have not yet built AWS, Kubernetes, KubeVirt or CDI, and have not     |
| migrated anything. No KubeVirt VM exists.                                |
|                                                                          |
| Next: review Stage 1H, then define and approve Stage 1I (needs AWS       |
| credentials).                                                            |
+--------------------------------------------------------------------------+
```

---

## Section 14. One-Page Status Card

```text
PROJECT STATUS AT A GLANCE                         (as recorded after Stage 1H, 2026-09-28)
---------------------------------------------------------------------------------------------
Source             VMware ESXi 8.0.3 (nested, esxi-8-lab, 192.168.50.11)
Source VM          legacy-source-vm (Vmid 2), powered on, 192.168.50.31, nginx, unchanged
Golden artifact    created (Stage 1E), C:\VMs\legacy-source-vm\stage-1e\, read-only, outside Git
Working copy       /srv/migration-lab/working/ on conversion-host-01, immutable
Conversion host    conversion-host-01 (Vmid 3), powered on, ADR 006
KVM conversion     proven as an experiment (Stage 1G): qemu-img + virt-v2v, temporary QEMU/KVM
                   test boots, UEFI + virtio; network needed one netplan change
Test guests        temporary, inside conversion-host-01, deleted; not a deployment
KubeVirt           designed (v1.9.0, ADR 007-010), NOT deployed
CDI                designed (v1.66.1 candidate, upload DataVolume, raw Block PVC), NOT deployed
AWS                designed (m8i.xlarge, ap-south-1, Terraform), NOT provisioned;
                   credentials BLOCKED (U15)
Migration          NOT yet performed; no KubeVirt VM exists
Current stage      Stage 1H done (H1-H10 PASS), awaiting user review
Next               Stage 1I: not yet defined; needs definition, explicit approval
                   (objective, scope, change boundary) and working AWS credentials
---------------------------------------------------------------------------------------------
```
