# Project 1.5 — Context Handoff

**VM-to-Kubernetes Migration Platform — ESXi → KubeVirt Migration & VM Modernization**

Handoff created: 2026-09-27 ~11:35 IST (06:05 UTC), from the Cursor session run in the Project 1 workspace
(`C:\Users\kiran\Desktop\Career\Kubernetes Platform Engineering & GitOps Lab`).

Purpose: this file is the authoritative context for continuing Project 1.5 in a fresh Cursor workspace
(`C:\Projects\kubevirt-vm-migration-platform`) without relying on chat history.

## Evidence markers

| Marker | Meaning |
|---|---|
| **OBSERVED** | Taken directly from command output or config files during this session. Last re-verified 2026-09-27 ~11:30 IST unless noted. |
| **INFERRED** | A conclusion drawn from observed facts, not directly reported by a tool. Verify before relying on it for something irreversible. |
| **PLANNED** | Stated intent or a future step. Not built or configured yet. |
| **DEFERRED** | A decision intentionally postponed. |

---

## 1. Project name and objective

| Item | Value | Marker |
|---|---|---|
| Project | Project 1.5, "VM-to-Kubernetes Migration Platform" | OBSERVED (user-stated) |
| Subtitle | ESXi → KubeVirt Migration & VM Modernization | OBSERVED (user-stated) |
| Objective | Build a VMware ESXi **source** environment with legacy VMs, then migrate those VMs to **KubeVirt** on a Kubernetes platform, with the destination on **AWS** (built via Terraform) | PLANNED |
| Predecessor | Project 1: Kubernetes Platform Engineering & GitOps Lab (repo `kubernetes-platform-engineering-gitops`, local path `C:\Users\kiran\Desktop\Career\Kubernetes Platform Engineering & GitOps Lab\kubernetes-platform-engineering-gitops`). Separate project; do not modify. | OBSERVED |
| Current phase | Source-environment preparation (pre-Stage 0 / Stage 0 baseline). Host is prepared; no guest VMs yet. | OBSERVED |

## 2. GitHub repository

| Item | Value | Marker |
|---|---|---|
| GitHub URL | https://github.com/kirandevraaj/kubevirt-vm-migration-platform | OBSERVED (user-stated) |
| Local workspace | `C:\Projects\kubevirt-vm-migration-platform` | OBSERVED |
| Remote `origin` | `git@github.com:kirandevraaj/kubevirt-vm-migration-platform.git` (SSH) | OBSERVED |
| Local state | Branch `main`, **no commits yet**, no files; `origin/main` shows as `[gone]` (remote has no branch yet) | OBSERVED |
| Planned doc location | `docs/stage-0/esxi-source-lab-baseline.md` inside the repo | PLANNED |
| Commit/push policy so far | Nothing committed or pushed for Project 1.5. Every change so far was made only with the user's explicit instruction. | OBSERVED |

## 3. Laptop hardware

| Item | Value | Marker |
|---|---|---|
| CPU | Intel Core i7-14650HX, 16 cores / 24 logical processors (hybrid P/E cores) | OBSERVED |
| RAM | 32 GB installed, 31.71 GB usable | OBSERVED |
| Free RAM (esxi-8-lab running) | ~16.1 GB | OBSERVED |
| Disk | C: ~433.8 GB free (~501 GB used before the ESXi lab) | OBSERVED |
| OS | Windows 11 Home Single Language, 10.0.26200 (build 26200) | OBSERVED |
| Firmware virtualization | VT-x enabled, VMX extensions and SLAT available | OBSERVED |
| Computer name | `LAPTOP-HUAOOKQ0` (taken from the SSH public-key comment) | INFERRED |

## 4. Windows virtualization state

| Item | Value | Marker |
|---|---|---|
| Windows hypervisor at boot | `hypervisorlaunchtype Off` (set by the user; verified by the user with `bcdedit`) | OBSERVED (user-reported) |
| `Win32_ComputerSystem.HypervisorPresent` | `False` | OBSERVED |
| VBS | Status 0 (not enabled) | OBSERVED |
| Memory Integrity (HVCI) | Off (`Enabled = 0`) | OBSERVED |
| Hyper-V role | Not installed (Windows 11 Home) | OBSERVED |
| Optional features still **installed** | VirtualMachinePlatform = Enabled, HypervisorPlatform (WHP) = Enabled, Microsoft-Windows-Subsystem-Linux = Enabled | OBSERVED |
| Why the hypervisor had to go | With it running, VMware Workstation ran in Hyper-V/WHP mode ("IOPL_Init: Hyper-V detected by CPUID"), which **does not support** "Virtualize Intel VT-x/EPT". The hypervisor was being kept on by VirtualMachinePlatform/WHP/WSL2. The VMware installer itself enabled WHP on 2026-02-27. | OBSERVED |
| Effect on WSL2 and Docker Desktop | **WSL2 and Docker Desktop (WSL2 backend) will not run** while the hypervisor is off. Default WSL distro: Ubuntu (WSL 2). | INFERRED |
| How to revert (only with approval) | `bcdedit /set hypervisorlaunchtype auto` and reboot. This **breaks nested virtualization** in esxi-8-lab. | INFERRED |

## 5. VMware Workstation

| Item | Value | Marker |
|---|---|---|
| Product | VMware Workstation Pro **17.6.4 build-24832109** | OBSERVED |
| Install path | `C:\Program Files (x86)\VMware\VMware Workstation\` | OBSERVED |
| Tools used | `vmrun.exe`, `vmware-vdiskmanager.exe` | OBSERVED |
| Services | VMware Authorization, DHCP, NAT and USB Arbitration: running (automatic). Autostart: stopped (manual). | OBSERVED |
| Monitor mode now | `Monitor Mode: CPL0` (native, not Hyper-V/WHP) | OBSERVED (`vmware.log`) |
| Registered VMs | Exactly one: `esxi-8-lab` (running) | OBSERVED |
| Other virtual networks present (do not touch) | VMnet1 host-only 192.168.56.0/24 (host 192.168.56.1); VMnet2 and VMnet3 exist (host adapters on 169.254.x APIPA) | OBSERVED |

## 6. esxi-8-lab configuration (Workstation VM)

| Setting | Value | Marker |
|---|---|---|
| VM name | `esxi-8-lab` | OBSERVED |
| VMX | `C:\VMs\esxi-8-lab\esxi-8-lab.vmx` | OBSERVED |
| Guest OS type / HW version | `vmkernel8` (VMware ESXi 8) / `virtualHW.version = "21"` | OBSERVED |
| Firmware | UEFI (`firmware = "efi"`), `uefi.secureBoot.enabled = "FALSE"` | OBSERVED |
| vCPU | 8 (`numvcpus = "8"`, `cpuid.coresPerSocket = "8"`), so 1 socket × 8 cores; 1 vNUMA node | OBSERVED |
| Memory | 16384 MB (`memsize = "16384"`), no reservation | OBSERVED |
| Nested virtualization | `vhv.enable = "TRUE"`; `vpmc.enable = "FALSE"` | OBSERVED |
| Disk controller | PVSCSI (`scsi0.virtualDev = "pvscsi"`) | OBSERVED |
| Boot disk | `scsi0:0` = `esxi-8-lab.vmdk`, 100 GiB, monolithicSparse (thin); ~0.65 GB used on host | OBSERVED |
| Data disk | `scsi0:1` = `esxi-8-lab-data.vmdk`, 200 GiB, monolithicSparse (thin); ~0.04 GB used on host | OBSERVED |
| CD/DVD | `sata0:1` = ESXi installer ISO (still attached, connected at power-on) | OBSERVED |
| NIC | `ethernet0`: VMXNET3, NAT, `VMnet8`, generated MAC `00:0c:29:c5:99:2f` | OBSERVED |
| Disabled devices | USB (all controllers), sound, floppy, serial, parallel, printers, 3D; shared folders (`maxNum 0`); HGFS, drag-and-drop, copy, paste disabled | OBSERVED |
| Config backups | `esxi-8-lab.vmx.pre-resize.bak` (before 2→8 vCPU / 8→16 GB), `esxi-8-lab.vmx.pre-datadisk.bak` (before adding the data disk) | OBSERVED |
| ESXi installer ISO | `C:\Users\kiran\Desktop\Kolla_Ansible_Openstack\artifacts\VMware-VMvisor-Installer-8.0U3e-24677879.x86_64.iso`, 648,374,272 bytes, SHA256 `9782C96FFD01CC56DA17EC31573DA69F4CBA2F9402E67C8B55D05D9472C7376A` | OBSERVED |

## 7. Nested virtualization status

| Check | Result | Marker |
|---|---|---|
| Windows hypervisor | Off | OBSERVED |
| Workstation monitor | CPL0 native; modules `hv-vt.vmm` and `gphys-ept.vmm` loaded | OBSERVED |
| VHV | `vhv.enable = "TRUE"` | OBSERVED |
| ESXi view | `esxcli hardware cpu global get`: **HV Support: 3** (VT-x present and enabled) | OBSERVED |
| Nested 64-bit guests inside ESXi | Expected to work; **not yet tested** (no guest VMs) | INFERRED |

## 8. ESXi version and build

| Item | Value | Marker |
|---|---|---|
| Version | VMware ESXi **8.0.3**, 8.0 Update 3 (U3e), patch 70 | OBSERVED |
| Build | **24677879** (`Releasebuild-24677879`) | OBSERVED |
| Image profile | `ESXi-8.0U3e-24677879-standard` | OBSERVED |
| License | "vSphere 8 Hypervisor" (free edition; `esx.hypervisor.cpuPackageCoreLimited`, feature `vsmp:8`). Serial intentionally not recorded here. | OBSERVED |
| Free-edition API limits | The vSphere API is likely read-only for writes (snapshots, CBT). This may affect migration tooling such as Forklift/MTV warm migration. | INFERRED (validate) |
| Host UI / Tools VIBs | `esx-ui 2.18.0`, `tools-light 12.5.1` | OBSERVED |
| Maintenance mode | Disabled | OBSERVED |

## 9. ESXi hostname

| Item | Value | Marker |
|---|---|---|
| Host name | `esxi-8-lab` | OBSERVED |
| Domain | `localdomain` | OBSERVED |
| FQDN | **`esxi-8-lab.localdomain`** (also reported by the hostd API, which the Host Client reads) | OBSERVED |
| DNS record | None. No hosts-file entry on Windows. | OBSERVED |

## 10. ESXi management IP

| Item | Value | Marker |
|---|---|---|
| vmk0 IPv4 | **192.168.50.11**, **STATIC** | OBSERVED |
| Netmask | 255.255.255.0 | OBSERVED |
| Gateway | 192.168.50.2 (default route source **MANUAL**) | OBSERVED |
| DNS | 192.168.50.2, search domain `localdomain`; DHCP DNS = false | OBSERVED |
| Previous address | 192.168.50.137 (DHCP), **retired**; no longer answers | OBSERVED |
| Host Client | https://192.168.50.11/ui (tcp/443 reachable from Windows) | OBSERVED |
| Persistence across reboot | Not yet tested with a controlled reboot | DEFERRED |

**Why .11 and not .10 (important):**

- VMnet8's 192.168.50.0/24 overlaps a network on the upstream ISP side.
- When a VMnet8 address doesn't answer ARP, Windows falls back to the Wi-Fi default route (192.168.29.1 → 27.7.184.1).
- Real devices on the ISP side answer at **192.168.50.10, .20 and .25** (TTL 253). OBSERVED
- **.11, .12, .15, .30, .50, .77, .100 and .120** had no reply anywhere. OBSERVED
- **Avoid .10, .20 and .25** for lab static addresses.

## 11. VMnet8 network architecture

| Item | Value | Marker |
|---|---|---|
| Type | VMware NAT | OBSERVED |
| Subnet | **192.168.50.0/24** | OBSERVED |
| Windows host adapter ("VMware Network Adapter VMnet8") | **192.168.50.1** (ifIndex 23, metric 35) | OBSERVED |
| NAT gateway / DNS proxy | **192.168.50.2** (MAC 00:50:56:fe:c1:c7) | OBSERVED |
| DHCP server | 192.168.50.254 (MAC 00:50:56:f6:7a:88) | OBSERVED |
| DHCP pool | **192.168.50.128 – 192.168.50.254**; lease 1800 s default / 7200 s max | OBSERVED |
| Static-safe range | 192.168.50.3 – 192.168.50.127, **excluding .10, .20, .25** (upstream conflict) | OBSERVED / INFERRED |
| Config files (read-only reference) | `C:\ProgramData\VMware\vmnetdhcp.conf`, `vmnetnat.conf`, `vmnetdhcp.leases` | OBSERVED |
| Stale leases | Expired leases for deleted VMs (.128 – .136: k8s-ctrl-01, k8s-worker-01/02, pxe-server, nebula-*, ubuntu-server) | OBSERVED |
| Laptop uplink | Wi-Fi 192.168.29.107/24, gateway 192.168.29.1 | OBSERVED |

Path from Windows to ESXi management (OBSERVED data; INFERRED explanation):

```
Windows (VMnet8 adapter 192.168.50.1)
   │  same L2 segment (VMnet8); no NAT between host and guests
   ▼
esxi-8-lab ethernet0 (VMXNET3, 00:0c:29:c5:99:2f)
   ▼
ESXi vmnic0 (nvmxnet3) ──► vSwitch0 ──► port group "Management Network" (VLAN 0)
   ▼
vmk0 192.168.50.11/24 ──► SSH tcp/22, Host Client/API tcp/443, tcp/902
ESXi outbound: vmk0 ──► 192.168.50.2 (VMware NAT) ──► laptop Wi-Fi ──► internet
```

## 12. ESXi vSwitch, vmk0 and network configuration

| Object | Configuration | Marker |
|---|---|---|
| vmnic0 | PCI 0000:0b:00.0, driver `nvmxnet3` 2.0.0.31, Up/Up, 10000 Mb/s full, MTU 1500, MAC 00:0c:29:c5:99:2f | OBSERVED |
| vSwitch0 | Standard switch, MTU 1500, uplink `vmnic0`, 128 configured ports, CDP listen | OBSERVED |
| Port group "Management Network" | vSwitch0, VLAN 0, 1 client (vmk0) | OBSERVED |
| Port group "VM Network" | vSwitch0, VLAN 0, 0 clients (default for future guest VMs) | OBSERVED |
| vmk0 | Port group Management Network, `defaultTcpipStack`, MTU 1500, MAC 00:0c:29:c5:99:2f, IPv4 static 192.168.50.11/24; IPv6 link-local fe80::20c:29ff:fec5:992f | OBSERVED |
| Routes | default → 192.168.50.2 (MANUAL); 192.168.50.0/24 connected | OBSERVED |
| Firewall | Enabled, default action DROP; `ntpClient` ruleset enabled | OBSERVED |
| Other vmkernel interfaces / vSwitches | None | OBSERVED |

## 13. ESXi storage layout

| Device | Details | Marker |
|---|---|---|
| `mpx.vmhba1:C0:T0:L0` | **Boot disk**, 102,400 MB, PVSCSI (`vmhba1`) target 0, `Is Boot Device: true`, SSD flag true | OBSERVED |
| `mpx.vmhba1:C0:T1:L0` | **Data disk**, 204,800 MB, PVSCSI target 1, `Is Boot Device: false` | OBSERVED |
| `mpx.vmhba0:C0:T1:L0` | CD-ROM (installer ISO), SATA `vmhba0` | OBSERVED |

Boot disk partition table (GPT, 209,715,200 sectors) — OBSERVED:

| # | Sectors | Size | Role |
|---|---|---|---|
| 1 | 64 – 204,863 | 100 MiB | EFI system partition |
| 5 | 208,896 – 8,595,455 | 4 GiB | BOOTBANK1 (vfat, active image) |
| 6 | 8,597,504 – 16,984,063 | 4 GiB | BOOTBANK2 (vfat, empty alternate) |
| 7 | 16,986,112 – 209,715,166 | ~91.9 GiB | **OSDATA** (VMFS-L / `VMFSOS`) |

- OSDATA: `OSDATA-6ab89e71-b81c2094-df49-000c29c5992f`, 91.8 GB, ~88.9 GB free. It holds logs, scratch and the core dump (a 1.36 GB `vmkdump` file). It is **not** usable for VM files. OBSERVED
- Why the boot disk has no datastore: the ESXi 8 installer default (`systemMediaSize`) let OSDATA take all space left after the boot banks on a 100 GB disk. INFERRED
- Boot-disk partition table and host-side VMDK hash were verified unchanged by the data-disk work. OBSERVED

## 14. migration-datastore

| Item | Value | Marker |
|---|---|---|
| Name | **`migration-datastore`** | OBSERVED |
| Type | **VMFS-6** (6.82), 1 MB file block size, unmap granularity 1 MB | OBSERVED |
| UUID / mount | `6ab8a6b9-d245ef9a-5741-000c29c5992f`, `/vmfs/volumes/migration-datastore` | OBSERVED |
| Backing | `mpx.vmhba1:C0:T1:L0` partition 1, GPT, sectors 2,048 – 419,430,366 (1 MiB aligned), VMFS GUID `AA31E02A400F11DB9590000C2911D1B8` | OBSERVED |
| Capacity | 214,479,929,344 bytes (**199.8 GB**) | OBSERVED |
| Free | 212,962,639,872 bytes (**198.3 GB**) | OBSERVED |
| hostd view | `accessible = true`, `type = "VMFS"` | OBSERVED |
| Contents | Empty (no VMs, no ISOs) | OBSERVED |
| Host-side file | `C:\VMs\esxi-8-lab\esxi-8-lab-data.vmdk` (thin; grows as the datastore fills) | OBSERVED |
| ATS | Not supported (expected on virtual disks) | OBSERVED |

## 15. SSH key-authentication setup

| Item | Value | Marker |
|---|---|---|
| Client key | `C:\Users\kiran\.ssh\id_rsa` (RSA 4096, `SHA256:aBSgyOuMEC8RghgGK5XMhkY8EUk7wSNagrljVJkvh8Q`, comment `kiran@LAPTOP-HUAOOKQ0`) | OBSERVED |
| ESXi authorized keys | `/etc/ssh/keys-root/authorized_keys` (3 lines). Installed by the user, not by the agent. | OBSERVED |
| Canonical command | `ssh -o IdentitiesOnly=yes -i "C:\Users\kiran\.ssh\id_rsa" root@192.168.50.11` | OBSERVED (works) |
| ESXi host-key fingerprints | ECDSA `SHA256:+DLN+T16Vg0r9DkAc1G0pqwj+otqb7l6bxZH9atMRTs`; RSA `SHA256:px1iV0AfWOvRd/QmAACu58ro0Q0kYAQAij0FAEAf3JY` | OBSERVED |
| **Known issue** | `C:\Users\kiran\.ssh\known_hosts` line 22 holds a **stale ED25519 key for 192.168.50.11** from an older lab VM. Plain `ssh root@192.168.50.11` fails with "REMOTE HOST IDENTIFICATION HAS CHANGED". User action: `ssh-keygen -R 192.168.50.11`, then accept the ECDSA fingerprint above. Until then, add `-o HostKeyAlias=192.168.50.137` (the ESXi key is trusted under .137). | OBSERVED |
| Server auth methods | `publickey,keyboard-interactive`; the root password is not known to the agent | OBSERVED |
| SSH / ESXi Shell services | Both **enabled** (`chkconfig` on) and running. Intentionally kept on for automation. | OBSERVED |
| Automation tips | (1) Windows PowerShell strips inner double quotes passed to `ssh`. Send multi-line work as a script over stdin instead: `cmd /c "ssh ... root@192.168.50.11 sh -s < script.sh"`. (2) Scripts must have **LF** line endings. (3) The ESXi shell is busybox: `tr` is missing; `awk`, `sed` and `grep` exist. | OBSERVED |

## 16. NTP configuration

| Item | Value | Marker |
|---|---|---|
| Enabled | true; ntpd running; `chkconfig ntpd on` | OBSERVED |
| Servers | `0.pool.ntp.org`, `1.pool.ntp.org`, `2.pool.ntp.org`, `3.pool.ntp.org` | OBSERVED |
| Synchronized | **true** ("NTP is in sync"; peer 13.126.27.131, offset ~3 ms at check) | OBSERVED |
| Firewall | `ntpClient` ruleset enabled (all IPs, udp/123) | OBSERVED |
| Timezone | ESXi runs in UTC (no timezone setting); the Host Client shows the browser's local time | OBSERVED / INFERRED |
| NTP path | Through VMware NAT (192.168.50.2) and the laptop Wi-Fi | INFERRED |

## 17. Local cleanup already performed (before this ESXi work)

From the earlier session "Local lab cleanup before Stage 0" (2026-09-27 ~09:34 IST) — OBSERVED in that session's report:

- **VMware VMs deleted:** `k8s-ctrl-01`, `k8s-worker-01`, `k8s-worker-02` (Project 1 Kubernetes nodes; ~171 GB freed). They were shut down gracefully, removed with `vmrun deleteVM`, and dropped from the library (backup `%TEMP%\inventory.vmls.bak`).
- **Docker containers deleted:** `platform-lab-jenkins-controller-1`, `platform-lab-jenkins-agent-1`, `platform-aws-tools`.
- **Docker images deleted:**
  - `kirandevraaj/platform-lab` 0.1.0 – 0.1.5
  - `platform-lab-jenkins-controller:2.568.3`, `platform-lab-jenkins-agent:1`, `platform-aws-tools:latest`
  - `python:3.14-slim`, `hashicorp/terraform:1.9`, `amazon/aws-cli:2.17.49`
  - dangling and intermediate build layers
  - 4.27 GB of build cache
- **Docker volumes deleted:** `platform-lab-jenkins-home`, the Jenkins agent's anonymous volumes, `platform-aws-tools`.
- **Docker networks deleted:** `platform-lab-jenkins`, `platform-aws-tools_default`.
- **Preserved:**
  - Docker image `alpine:3.20` (used by `Desktop\opennms\k8s\snmp-agents.yaml`)
  - Docker volume **`platform-aws-tools-aws`**, which holds the **only local copy of the AWS CLI `credentials`/`config`** (`%USERPROFILE%\.aws` is empty)
- **Not touched:** software installs, Git repos, SSH keys, AWS resources, and the Ubuntu ISOs in `C:\opentelemetry\Artifacts` (~19 GB). The kubeconfig still has a stale `ckad-lab` context.
- **Follow-ups the user may want:** revoke the Jenkins-stored Docker Hub and GitHub tokens (`dockerhub-platform-lab`, `github-platform-lab`); `docker_data.vhdx` is still 17.6 GB and was not compacted.

INFERRED consequence: with the Windows hypervisor off, Docker Desktop and WSL2 can't start, so the AWS credentials in `platform-aws-tools-aws` are **currently inaccessible**. Copy them to `%USERPROFILE%\.aws` the next time WSL/Docker is available, or re-issue credentials, before any Terraform/AWS work.

## 18. Current source-environment state

| Item | State | Marker |
|---|---|---|
| esxi-8-lab | Powered on, running ESXi 8.0.3 | OBSERVED |
| Guest VMs on ESXi | **None** (`vim-cmd vmsvc/getallvms` is empty) | OBSERVED |
| ISOs on migration-datastore | None | OBSERVED |
| Datastores | `migration-datastore` (VMFS-6, 199.8 GB, 198.3 GB free); OSDATA is system only | OBSERVED |
| Management | 192.168.50.11 static; hostname `esxi-8-lab.localdomain`; NTP in sync; SSH key login works | OBSERVED |
| vCenter | None (standalone host; `vpxa` running idle) | OBSERVED |
| Source VMs to build | e.g. `legacy-source-vm`; possibly `test-vm`, `helper-vm` (names mentioned by the user) | PLANNED |
| Stage 0 baseline doc (outdated) | `C:\VMs\esxi-audit\docs\stage-0\esxi-source-lab-baseline.md` still shows the **pre-preparation** state (no datastore, DHCP .137). Refresh it before copying into the repo. | OBSERVED |

## 19. Planned AWS destination architecture

| Item | Value | Marker |
|---|---|---|
| Destination | AWS, created **later** through **Terraform** | PLANNED (user-stated) |
| Existing AWS resources for Project 1.5 | None created in this session; AWS was never modified | OBSERVED |
| Detailed design (VPC, cluster type, node types, storage) | Not yet specified by the user | DEFERRED |
| Key technical constraint | KubeVirt needs hardware virtualization (`/dev/kvm`) on worker nodes. On AWS that means **bare-metal (`*.metal`) instances** or an instance family that supports nested virtualization. Cost and instance availability must be evaluated. | INFERRED |
| Likely building blocks | VPC + subnets, a Kubernetes cluster (e.g. EKS or self-managed) with KVM-capable workers, KubeVirt + CDI, EBS CSI (`gp3`) for VM disks, S3 for image staging, and a secure path from the lab (VPN or public upload of exported disks) | INFERRED (proposal, not a decision) |
| AWS credentials | Only in Docker volume `platform-aws-tools-aws` (see section 17) | OBSERVED |

## 20. Project 1.5 architecture and migration flow

High level (PLANNED intent; tooling INFERRED as candidates):

```
SOURCE (laptop)                                        DESTINATION (AWS, via Terraform)
Windows 11 ─ VMware Workstation 17.6.4                 Kubernetes cluster with KVM-capable workers
  └─ esxi-8-lab (ESXi 8.0.3, 192.168.50.11)              ├─ KubeVirt (VirtualMachine / VMI)
       └─ migration-datastore (VMFS-6, ~200 GB)          ├─ CDI (DataVolume import → PVC)
            └─ legacy-source-vm (PLANNED)                ├─ EBS CSI storage (VM disks)
                                                         └─ GitOps (Argo CD, from Project 1 practice)
            │
            └── export / convert / transfer ──────────►  import → VirtualMachine → validate → cut over
```

Candidate migration paths (INFERRED; choose later):

1. **Cold export.** Power off the source VM, export VMDK/OVF (`ovftool`, datastore download, or `vmkfstools` clone), convert if needed (`qemu-img`/`virt-v2v`), stage in S3 or HTTP, import with a CDI `DataVolume`, then create the KubeVirt `VirtualMachine`.
2. **Forklift / MTV (Konveyor).** Uses the ESXi or vCenter provider with VDDK. The free "vSphere 8 Hypervisor" license and the lack of vCenter may block it, especially warm migration. **Validate first.**
3. **virt-v2v direct from ESXi** (`-i vmx` over SSH, or `-ic esx://`), writing into a PVC.

Modernization steps after migration (PLANNED at intent level): guest driver changes (VMware Tools/vmxnet3/pvscsi → virtio), networking in KubeVirt (pod network or Multus), and GitOps-managed VM definitions.

## 21. Decisions already made

| Decision | Marker |
|---|---|
| Source hypervisor: nested ESXi 8.0 U3e in VMware Workstation, VM `esxi-8-lab` in `C:\VMs\esxi-8-lab` (not in Desktop, Downloads or any repo) | OBSERVED |
| Use the exact ISO `VMware-VMvisor-Installer-8.0U3e-24677879.x86_64.iso` (SHA256 above); don't download another | OBSERVED |
| Disable the Windows hypervisor at boot to allow VHV (done by the user) | OBSERVED |
| esxi-8-lab sizing: 8 vCPU (1×8), 16 GB RAM, 100 GB thin boot disk, UEFI, VMXNET3 on VMnet8 NAT | OBSERVED |
| ESXi installation completed interactively by the user | OBSERVED |
| Add a second 200 GB thin disk for VM storage instead of reinstalling ESXi with a smaller OSDATA | OBSERVED |
| Datastore name `migration-datastore`, VMFS-6 | OBSERVED |
| Management IP 192.168.50.11 static (chosen over .10/.20 because of the upstream conflict); gateway/DNS 192.168.50.2 | OBSERVED |
| Hostname `esxi-8-lab.localdomain`; no invented public domain | OBSERVED |
| NTP via `0–3.pool.ntp.org` | OBSERVED |
| Keep SSH and ESXi Shell enabled for automation; use the existing RSA key only; add no new keys | OBSERVED |
| Destination on AWS via Terraform, later | PLANNED |
| Stage docs live under `docs/stage-0/` in the repo | PLANNED |

## 22. Decisions intentionally deferred

- Source guest OS for `legacy-source-vm` (and whether to add `test-vm` / `helper-vm`), its sizing, and ISO choice.
- Migration tooling (cold export vs Forklift/MTV vs virt-v2v) and whether the free ESXi license is sufficient.
- Whether to use an evaluation/paid vSphere license or add vCenter.
- AWS design: region, VPC layout, cluster type (EKS vs self-managed), KVM-capable instance type (`.metal` vs nested-virt-capable), storage, and connectivity from the lab.
- Additional lab networks: separate ESXi port groups or vSwitches for nested VMs or migration traffic, isolated or host-only networks.
- Reboot-persistence test of the ESXi network, hostname and NTP config.
- Detaching the ESXi installer ISO from esxi-8-lab.
- Hardening: disabling ESXi Shell/SSH, lockdown, certificate replacement.
- Windows hosts-file entry for `esxi-8-lab.localdomain`.
- Restoring WSL2/Docker (requires the hypervisor back on, which conflicts with VHV).

## 23. Current limitations

1. **Windows hypervisor must stay off** for nested ESXi, so WSL2 and Docker Desktop are unavailable while working on the source lab. INFERRED
2. **AWS credentials are trapped** in the Docker volume `platform-aws-tools-aws` while Docker is down. INFERRED
3. **Free ESXi license** ("vSphere 8 Hypervisor", `vsmp:8`): guest VMs are capped at 8 vCPU, and the vSphere API is probably restricted for writes. OBSERVED / INFERRED
4. **No vCenter**, so vCenter-dependent tooling won't work. OBSERVED
5. **Single flat network**: management and "VM Network" share vSwitch0, vmnic0 and VMnet8. OBSERVED
6. **Upstream IP overlap**: 192.168.50.0/24 also exists on the ISP side. Avoid .10, .20, .25. If an address doesn't answer on VMnet8, Windows traffic falls back to Wi-Fi. OBSERVED
7. **Resource headroom**: with ESXi using its full 16 GB, Windows keeps ~15–16 GB. Nested VMs share ESXi's 8 vCPU / ~14 GB free. OBSERVED / INFERRED
8. **Hybrid CPU**: vCPUs float across P-cores and E-cores, so performance varies. INFERRED
9. **ESXi config persistence across reboot is untested.** OBSERVED
10. **Stale `known_hosts` entry** for 192.168.50.11 (see section 15). OBSERVED
11. **Stage 0 baseline doc is outdated** (see section 18). OBSERVED

## 24. What must NOT be changed (without explicit user approval)

- Windows: boot configuration (`hypervisorlaunchtype`), Hyper-V/VBS/Memory Integrity, optional features (VMP/WHP/WSL), security policy, BIOS.
- VMware Workstation: the virtual networks (VMnet1, VMnet2, VMnet3, VMnet8), their DHCP/NAT config, and global preferences.
- esxi-8-lab:
  - don't delete, recreate, rename or move it
  - leave the boot VMDK alone
  - don't change `vhv.enable`, UEFI firmware, the NIC or its MAC
  - keep the disabled-device settings
- ESXi:
  - the vmk0 IP, gateway, DNS and hostname
  - NTP
  - vSwitch0 and its port groups
  - OSDATA, the boot banks and the system partitions
  - `migration-datastore` (don't reformat it)
  - SSH/ESXi Shell state and authorized keys (add no new keys)
- Docker volume `platform-aws-tools-aws` (AWS credentials). Never run Docker Desktop "Clean / Purge data" or `docker system prune --volumes`.
- AWS: no resources until the Terraform stage is explicitly started.
- GitHub and repos: no commits or pushes unless requested; Project 1 repo untouched.
- Don't create guest VMs, install Kubernetes/KubeVirt/Docker workloads, or upload ISOs until explicitly asked.

## 25. Exact next steps

1. **User:** fix the stale host key with `ssh-keygen -R 192.168.50.11`, then `ssh -o IdentitiesOnly=yes -i "C:\Users\kiran\.ssh\id_rsa" root@192.168.50.11` and accept ECDSA `SHA256:+DLN+T16Vg0r9DkAc1G0pqwj+otqb7l6bxZH9atMRTs`.
2. **Recommended:** a controlled ESXi reboot, then re-verify vmk0 192.168.50.11 static, the MANUAL default route, DNS, the hostname, NTP sync, `migration-datastore` mounted, and SSH key login.
3. **Repo bootstrap** (when the user asks): in `C:\Projects\kubevirt-vm-migration-platform`, add `docs/stage-0/esxi-source-lab-baseline.md`, refreshed to the current state in this handoff (don't copy the outdated version as-is). Optionally add this handoff and a README. Commit and push only on request. Never commit raw audit output that contains the ESXi license serial (`C:\VMs\esxi-audit\esxi-baseline-audit.txt`).
4. **Decide the source VM:** guest OS and version, sizing within ESXi limits (≤ 8 vCPU; suggested 2 vCPU / 2–4 GB / 20–40 GB thin), and the network ("VM Network" for now).
5. **Upload the chosen ISO** to `migration-datastore` (Host Client datastore browser, or `scp` to `/vmfs/volumes/migration-datastore/iso/`).
6. **Create `legacy-source-vm`** on ESXi and install the guest OS interactively. Confirm nested 64-bit guests run (validates VHV end to end).
7. **Validate the migration-tooling assumptions** against the free license (API write access, snapshot/CBT, VDDK/NFC export) before choosing a path.
8. **Plan the AWS destination** (Terraform): KVM-capable node type, cluster type, storage, connectivity. Recover AWS credentials from `platform-aws-tools-aws` or re-issue them before any `terraform plan`.

---

## Appendix A — Artifact locations

| Path | Content |
|---|---|
| `C:\VMs\esxi-8-lab\` | VM files: `.vmx`, `esxi-8-lab.vmdk` (boot), `esxi-8-lab-data.vmdk` (datastore), `nvram`, `vmware.log`, `.vmx` backups |
| `C:\VMs\esxi-audit\esxi-baseline-audit.sh` / `.txt` | Read-only baseline audit script and raw output (**`.txt` contains the license serial; don't commit**) |
| `C:\VMs\esxi-audit\verify-disks.sh`, `create-datastore.sh`, `ip-precheck.sh`, `ip-change.sh`, `persist-route-dns.sh`, `hostname-ntp.sh` | Scripts used for host preparation (already executed; don't re-run blindly) |
| `C:\VMs\esxi-audit\final-validation.sh` / `.txt` | Final validation script and output (post-preparation state) |
| `C:\VMs\esxi-audit\docs\stage-0\esxi-source-lab-baseline.md` | Stage 0 baseline (**outdated**: pre-preparation) |
| `C:\VMs\esxi-audit\PROJECT-1.5-CONTEXT-HANDOFF.md` | This file |

## Appendix B — Session timeline (2026-09-27, IST)

| Time | Event | Marker |
|---|---|---|
| ~09:34 | Local cleanup of the Project 1 VMware and Docker lab | OBSERVED |
| ~09:46 | Host validation. Nested virtualization blocked by the Windows hypervisor, so stopped before creating the VM. | OBSERVED |
| ~09:56 | User disabled the hypervisor. esxi-8-lab created (2 vCPU / 8 GB / 40 GB), VHV on, installer reached. | OBSERVED |
| ~10:05 | Resized to 8 vCPU / 16 GB / 100 GB (disk expanded in place); installer reached again | OBSERVED |
| ~10:18 | User installed ESXi 8.0.3 interactively (DHCP 192.168.50.137) | OBSERVED |
| ~10:29 | Read-only baseline audit: no datastore; OSDATA fills the boot disk | OBSERVED |
| ~10:43–11:05 | Host preparation: 200 GB data disk → `migration-datastore`; static IP .11; hostname; NTP | OBSERVED |
| ~11:35 | This handoff created | OBSERVED |
