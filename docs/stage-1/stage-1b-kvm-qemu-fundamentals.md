# Stage 1B: KVM / QEMU / VirtIO fundamentals and nested KVM feasibility

| Field | Value |
|---|---|
| Project | Project 1.5: VM-to-Kubernetes Migration Platform |
| Stage | 1B |
| Date | 2026-09-27 |
| Result | **All gates B1 to B10 PASS**. Nested KVM classified **KVM accelerated** (functional, high exit cost) |
| Detail documents | [kvm-learning-lab.md](kvm-learning-lab.md) (the VM), [nested-kvm-feasibility.md](nested-kvm-feasibility.md) (the nested test) |
| Diagram | [lab-nested-kvm-layers.svg](../diagrams/lab-nested-kvm-layers.svg) |

Labels: **OBSERVED** = seen in this lab. **INFERRED** = reasoned from observations or documentation. **NOT TESTED** = deliberately not done.

## 1. Objective

Create one small Linux VM on the prepared ESXi source host. Use it to learn how KVM, QEMU, libvirt and VirtIO fit together, and determine whether nested KVM actually works inside an ESXi guest.

## 2. Scope and change boundary

| Allowed and done | Not done (as required) |
|---|---|
| Created ONE ESXi guest VM, `kvm-learning-01` | No AWS, Kubernetes, KubeVirt, CDI or migration controller |
| Uploaded one ISO to `migration-datastore/iso/` (plus temporary seed ISOs, since deleted) | No Windows virtualization, VMnet, ESXi networking, datastore or host CPU/RAM changes |
| Changed files inside that guest (packages, one password reset, test artifacts) | No snapshots, extra disks, extra NICs or unneeded devices |
| Project documentation and this Git repository | No KVM module parameter changes; no downloads to Windows |
| | No change to Stage 0 decisions; no new SSH keys on ESXi or GitHub |

The VM has `vhv.enable = "TRUE"`. This is a per-VM setting of the new guest, not a host CPU change, and without it the nested KVM question cannot be tested.

## 3. What was done (timeline, UTC, OBSERVED)

| Time | Step |
|---|---|
| ~12:20 | ISO candidates hashed; stock Ubuntu 24.04.4 chosen ([why](kvm-learning-lab.md#2-iso-selection)) |
| 12:21 | ISO uploaded to `migration-datastore/iso/`; SHA256 re-checked on ESXi |
| 12:22 | 40 GB thin VMDK created, `.vmx` written, VM registered (Vmid 1) |
| 12:27:36 | Unattended install confirmed (free license blocks console API; see [install method](kvm-learning-lab.md#4-installation-method-unattended-no-console-input)) |
| 12:34:58 | Install finished and powered off |
| 12:35 | First boot: **B1 gate passed**; baseline and pre-package virtualization checks |
| ~12:40 | sudo password problem fixed via one rescue boot ([incident](kvm-learning-lab.md#5-incident-unusable-sudo-password-and-the-rescue)) |
| ~12:46 | Minimal package set installed (34 packages) |
| 12:47 to 12:52 | L3 nested VM runs: direct QEMU with KVM, TCG control, then through libvirt |
| 12:53 to 12:55 | Resource snapshots (L3 running, idle) |
| ~12:58 | Final host, guest and security state checks |

## 4. Gates

| Gate | Requirement | Result | Evidence (OBSERVED) |
|---|---|---|---|
| B1 | 64-bit Linux boots | **PASS** | Ubuntu 24.04.4 LTS, `uname -m` = `x86_64`, 2 CPUs, 3.8 GiB, 40G disk, VMXNET3 at 192.168.50.30 with gateway, ESXi and internet reachable. Closes Stage 0 N1. |
| B2 | CPU virtualization capability observed | **PASS** | `vmx`, `ept`, `vpid`, `unrestricted_guest` flags; `lscpu` `Virtualization: VT-x` |
| B3 | `/dev/kvm` exists or absence explained | **PASS** | `crw-rw---- root kvm 10, 232` before any package install |
| B4 | KVM module state understood | **PASS** | `kvm_intel` + `kvm` autoloaded; `nested=Y`, `ept=Y`; no parameters changed |
| B5 | QEMU installed and tested | **PASS** | QEMU 8.2.2 (Ubuntu 1:8.2.2+ds-0ubuntu1.18); `-accel help` lists `tcg`, `kvm`; L3 guest booted |
| B6 | KVM acceleration tested | **PASS: KVM accelerated** | `kvm-ok` OK; QEMU thread `CPU 0/KVM`; `/dev/kvm` + `kvm-vm` + `kvm-vcpu` fds; L3 `Hypervisor detected: KVM`. TCG used only as a labelled control. Caveat: high exit cost at L3. |
| B7 | libvirt / virsh relationship demonstrated | **PASS** | `virsh define` / `start` of `l3-libvirt-demo`; libvirtd spawned QEMU as `libvirt-qemu` with `-accel kvm`, AppArmor enforcing |
| B8 | VirtIO observed and explained | **PASS** | L2 has 0 VirtIO devices (PVSCSI + VMXNET3). L3 shows virtio-blk (`vda`), virtio-scsi (`sda`), virtio-net (`eth0`), transitional and modern PCI IDs |
| B9 | Nested result recorded | **PASS (recorded)** | [nested-kvm-feasibility.md](nested-kvm-feasibility.md): functional at L3; CPU-bound near-native, exit-heavy work slow |
| B10 | Resource observations recorded | **PASS** | Section 9 below: Windows, Workstation, ESXi and Linux views, idle and under L3 load |

B3 and B6 passed on hardware-assisted KVM. No gate relied on software emulation.

## 5. QEMU and KVM

### 5.1 Two components, one VM

**KVM** is a Linux kernel feature: the modules `kvm` and `kvm_intel` (or `kvm_amd`). It turns the Linux kernel into a hypervisor. It exposes the character device `/dev/kvm`, and a program uses `ioctl()` calls on it to:

- create a VM (`KVM_CREATE_VM`, which returns an `anon_inode:kvm-vm` fd);
- create vCPUs (`KVM_CREATE_VCPU`, which returns `anon_inode:kvm-vcpu:N` fds);
- map memory into the guest;
- run a vCPU (`KVM_RUN`).

KVM uses VT-x to enter the guest (VMLAUNCH/VMRESUME) and handles the VM exits it can deal with in the kernel. It emulates no disks, NICs or firmware. See the [KVM API](https://docs.kernel.org/virt/kvm/api.html).

**QEMU** is a normal user-space program (`qemu-system-x86_64`). It is the VMM and device model. It:

- builds the virtual machine: chipset, firmware, PCI bus and devices;
- allocates guest RAM in its own address space;
- implements every device the guest sees (virtio-blk, virtio-net, serial port, and so on);
- decides how guest instructions execute, which is the **accelerator**. See [QEMU introduction](https://www.qemu.org/docs/master/system/introduction.html).

They are separate projects and separate components. QEMU can run without KVM (TCG). KVM does nothing without a user-space VMM such as QEMU, and in KubeVirt it is still QEMU, inside a Pod.

### 5.2 What each part of a QEMU VM is (OBSERVED on the L3 guest)

| Concept | What it is here | How it was seen |
|---|---|---|
| QEMU process | One Linux process per VM: `qemu-system-x86_64` | `ps` in L2: PID, RSS ~176 MB for a 256 MiB guest |
| vCPU | One host **thread** per virtual CPU, named `CPU <n>/KVM` (or `CPU <n>/TCG`) | `/proc/<pid>/task/*/comm` with `-name ...,debug-threads=on` |
| Virtual (guest physical) memory | Anonymous memory mapped in the QEMU process and registered with KVM as guest-physical RAM. Pages become resident only when touched | `-m 256`; L3 `MemTotal` 211,564 kB (the kernel reserves some); RSS below 256 MiB |
| Disk | A backend file (qcow2 here) plus a frontend device model (virtio-blk, or virtio-scsi + scsi-hd) | `-drive`/`-blockdev` + `-device`; L3 sees `vda` and `sda` |
| NIC | A backend (`-netdev user`, i.e. QEMU's built-in user-mode NAT) plus a frontend (`virtio-net-pci`) | L3 `eth0`, driver `virtio_net` |
| Machine model | The emulated chipset and board: `q35` (ICH9, PCIe) or `pc` (i440FX). Ubuntu ships versioned aliases, for example `pc-q35-noble` | `-machine q35`; libvirt chose `pc-q35-noble` |
| Accelerator | How guest code runs: `kvm` (hardware, through `/dev/kvm`) or `tcg` (software translation) | `-accel kvm` versus `-accel tcg` |

### 5.3 QEMU alone versus QEMU + KVM (OBSERVED)

| | QEMU only (TCG) | QEMU + KVM |
|---|---|---|
| Who executes guest instructions | QEMU translates blocks of guest code into host code in software | The real CPU runs guest code directly in VT-x non-root mode |
| Needs `/dev/kvm` / VT-x | No | Yes |
| vCPU thread | `CPU 0/TCG` | `CPU 0/KVM` (a loop around `ioctl(KVM_RUN)`) |
| Guest sees | `-cpu max` emulated model; no `vmx`; no KVM detection | `-cpu host`; `Hypervisor detected: KVM`; `kvm-clock` |
| CPU-bound speed at L3 | 2.05 s (`md5sum`), 5.09 s (loop) | 0.22 s, 0.33 s (L2 itself: 0.26 s, 0.29 s) |
| Device emulation | QEMU | still QEMU (KVM only handles CPU, memory and a few in-kernel devices) |

### 5.4 What happens when QEMU uses KVM

1. QEMU opens `/dev/kvm`, creates a VM and one vCPU fd per vCPU, and registers guest RAM regions.
2. Each vCPU thread calls `ioctl(vcpu_fd, KVM_RUN)`. KVM loads the vCPU state into a VMCS and executes VMLAUNCH/VMRESUME. The guest now runs natively.
3. When the guest does something the CPU must not let it do directly (port or MMIO access, some MSRs, `HLT`, an EPT fault), the CPU performs a **VM exit** back to KVM.
4. KVM handles what it can in the kernel (for example the local APIC and timers). For device I/O it returns from `KVM_RUN` to QEMU with an exit reason. QEMU's device model performs the I/O and calls `KVM_RUN` again.

In this lab step 2 runs on virtual VT-x. The L2 kernel's VMLAUNCH is trapped by ESXi (L1), which emulates it on top of the virtual VT-x that Workstation (L0) emulates on the real CPU. That is why exits are so expensive here ([details](nested-kvm-feasibility.md#33-performance-observed-indicative-only)).

## 6. libvirt and virsh

| Piece | What it is | Observed here |
|---|---|---|
| libvirt | A management API and library that controls hypervisors (QEMU/KVM, Xen, LXC and others) through one model | libvirt 10.0.0 |
| `libvirtd` / `virtqemud` | The daemon that owns the VMs: it generates the QEMU command line, starts QEMU, talks to it over QMP, and sets up security labels, cgroups and logging. Newer setups split it into modular daemons (`virtqemud` and others). Ubuntu 24.04 runs the monolithic `libvirtd` ([libvirt daemons](https://libvirt.org/daemons.html)) | `libvirtd.service` + `virtlogd.service` active; no `virtqemud` |
| `virsh` | A command-line client of the libvirt API; it does not run VMs itself | `virsh version`: library 10.0.0, running hypervisor QEMU 8.2.2 |
| Connection URI | Chooses the driver and instance. `qemu:///system` is the system daemon (root-owned VMs, run as `libvirt-qemu`); `qemu:///session` is a per-user instance ([URIs](https://libvirt.org/uri.html)) | `virsh uri` as labadmin gives `qemu:///session`; as root, `qemu:///system` |
| Domain | libvirt's name for a VM | `l3-libvirt-demo` |
| Domain XML | The persistent, declarative VM definition: CPU, memory, OS boot, devices ([format](https://libvirt.org/formatdomain.html)) | Hand-written, about 30 lines; `virsh dumpxml` returns the libvirt-expanded version |

Demonstration (OBSERVED), with the same L3 kernel, initramfs and disks as in section 5:

1. `virsh -c qemu:///system list --all` showed an empty list.
2. `virsh define l3-libvirt-demo.xml` registered the domain, state `shut off`.
3. `virsh start l3-libvirt-demo`. libvirtd started `qemu-system-x86_64` as user `libvirt-qemu`, under AppArmor profile `libvirt-<uuid>` (enforcing), with thread `CPU 0/KVM` and a `/dev/kvm` fd.
4. The L3 guest ran its checks and powered off. With `on_poweroff=destroy` the domain returned to `shut off` 27.3 s after start.
5. libvirt turned the short XML into a long QEMU command line, including:
   - `-accel kvm -cpu host,migratable=on`, `-machine pc-q35-noble`
   - `-nodefaults`, a QMP monitor socket and `-sandbox on,...`
   - `-blockdev` storage nodes
   - five `pcie-root-port`s plus `qemu-xhci` and SATA controllers that the XML never asked for (libvirt defaults for q35)
6. The domain was left **defined and shut off** as a reference.

VMware analogy: domain XML is like a `.vmx`; libvirtd is like hostd; virsh is like `vim-cmd`. The QEMU process is closest to the per-VM VMX process. The analogy is imperfect: ESXi's VMM runs inside VMkernel, whereas QEMU is an ordinary process on top of the KVM kernel module.

## 7. VirtIO versus VMware paravirtual devices

VirtIO is an OASIS-standard family of paravirtual devices ([VirtIO 1.2](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html)). The guest knows it is virtual and exchanges requests with the hypervisor through shared-memory rings (virtqueues) instead of emulated hardware registers.

| Device | What it is | Guest driver / name | Observed |
|---|---|---|---|
| virtio-blk | One simple block device per PCI function | `virtio_blk` -> `/dev/vdX` | L3 `vda`, PCI `1af4:1001` (transitional) / `1af4:1042` (modern) |
| virtio-scsi | A SCSI host adapter; disks, CD-ROMs and LUNs appear as SCSI targets behind it | `virtio_scsi` + `sd` -> `/dev/sdX` | L3 `sda` behind `virtio1/host0/target0:0:0`, PCI `1af4:1004` / `1af4:1048` |
| virtio-net | Paravirtual Ethernet NIC | `virtio_net` -> `eth0` / `enpXsY` | L3 `eth0`, PCI `1af4:1000` / `1af4:1041` |

`kvm-learning-01` itself has **no** VirtIO devices, because it runs on ESXi. It uses VMware's own paravirtual devices (OBSERVED):

| | VMware device (in L2) | Nearest VirtIO device (in L3) | Same role | Not identical because |
|---|---|---|---|---|
| Storage | PVSCSI `15ad:07c0`, driver `vmw_pvscsi` | virtio-scsi (SCSI HBA). For a plain disk, KubeVirt usually uses virtio-blk | Paravirtual SCSI HBA; disks appear as `sdX` | Different PCI vendor/device IDs, different ring and register protocol, different drivers. The guest must have the other driver, and device names can change (`sda` to `vda` with virtio-blk) |
| Network | VMXNET3 `15ad:07b0`, driver `vmxnet3` | virtio-net | Paravirtual NIC with multiqueue | Different device and driver, different MAC vendor prefix (`00:0c:29` vs `52:54:00`), different interface name (`ens192` vs `enp1s0`/`eth0`) |

Migration consequence (OBSERVED in this guest, INFERRED for conversion):

- `/etc/fstab` and `root=` use UUIDs, so they survive the disk bus change.
- netplan matches `driver: "vmxnet3"` and would leave a virtio-net NIC unconfigured.
- Ubuntu's kernel has the VirtIO drivers built in (`CONFIG_VIRTIO_BLK=y`, `CONFIG_VIRTIO_NET=y`, `CONFIG_SCSI_VIRTIO=y`).

This is exactly the class of fix-ups virt-v2v exists for.

## 8. Two execution paths

**KVM path, as used in this lab:**

```text
Linux application (virsh)
  -> libvirt (libvirtd: domain XML -> QEMU command line, QMP, AppArmor, cgroups)
    -> QEMU (user-space process: vCPU threads, guest RAM, virtio device models)
      -> KVM (kernel module: /dev/kvm, ioctl KVM_RUN, VM exit handling)
        -> VT-x (VMLAUNCH/VMRESUME, EPT)
          -> physical CPU
```

In this lab the VT-x under L2 KVM is **virtual**. ESXi's VHV emulates it for `kvm-learning-01`, on top of the virtual VT-x that Workstation's VHV emulates for ESXi. Only Workstation touches the real VT-x.

**VMware path, as used for `kvm-learning-01` itself:**

```text
VMware application (vim-cmd / host client -> hostd)
  -> ESXi VMkernel (schedules the VM's VMX world, owns memory and devices)
    -> VMware virtualization (per-VM VMM: hv-vt + gphys-ept modules, Monitor Mode CPL0;
                              PVSCSI / VMXNET3 device emulation in the VMX process)
      -> VT-x / EPT (virtual here, provided by Workstation)
        -> physical CPU
```

| Role | KVM stack | VMware stack |
|---|---|---|
| Management API and daemon | libvirt / libvirtd | vSphere API / hostd |
| CLI | virsh | vim-cmd, esxcli |
| VM definition | domain XML | `.vmx` |
| Hypervisor kernel | Linux + KVM module | VMkernel |
| Per-VM user-space process | QEMU | VMX process |
| CPU and memory virtualization | KVM using VT-x/EPT | VMM using VT-x/EPT |
| Paravirtual disk and NIC | virtio-blk / virtio-scsi, virtio-net | PVSCSI, VMXNET3 |

## 9. Resource observations

Three different quantities are easy to confuse:

- **Configured**: what the layer below promised (the `.vmx` or QEMU arguments).
- **Guest-visible**: what the guest OS reports as its hardware.
- **Actively consumed**: what the layer below has actually backed with real memory or CPU time.

Idle means after all tests with nothing running in L3. "L3 running" is sampled while the KVM L3 guest was booting. All values OBSERVED.

| Layer (tool) | Configured | Guest-visible | Consumed, idle | Consumed, L3 running |
|---|---|---|---|---|
| Windows (perf counters, `Get-Process`) | - | 31.7 GiB RAM, 24 logical CPUs | 12.2 GiB free; total CPU 5.0%; `vmware-vmx` 0.0% CPU, working set 8.43 GiB, private bytes 0.08 GiB | total CPU 9.0%; `vmware-vmx` 97.8% |
| Workstation (`esxi-8-lab.vmx`, read-only) | 8 vCPU (1 socket x 8 cores), 16384 MB, `vhv.enable = TRUE` | - | - | - |
| ESXi host (`esxcli hardware memory get`, `vim-cmd hostsvc/hostsummary`) | - | 16 GiB (17,178,800,128 B), 8 cores @ 2419 MHz | 281 MHz CPU, 3386 MB memory | 1009 MHz, 3401 MB |
| ESXi, `kvm-learning-01` quickStats (`vim-cmd vmsvc/get.summary 1`) | 2 vCPU, 4096 MB | - | 209 MHz; guestMemoryUsage 942 MB; hostMemoryUsage 1574 MB; overhead 42 MB; balloon and swap 0 | 940 MHz; guest 1433 MB; host 1574 MB |
| Linux L2 (`free -m`, `ps`) | - | 3915 MiB total, 2 CPUs | used 478, buff/cache 830, available 3436 MiB; load 0.19 | used 637 MiB; `qemu-system-x86` 100% CPU, RSS 182 MB |
| L3 guest | 1 vCPU, 256 MiB | MemTotal 211,564 kB, 1 CPU | - | - |

How to read this:

- **Configured is not consumed.**
  - ESXi was given 16 GiB, but Windows shows about 8.4 GiB in the `vmware-vmx` working set: only pages ESXi has touched are backed.
  - `kvm-learning-01` was given 4096 MB, but ESXi backs 1574 MB (`hostMemoryUsage`): pages the guest has touched since power-on (install-time and boot-time page cache included).
  - ESXi does not reclaim those pages without memory pressure (balloon 0, swap 0).
- **Guest-visible is less than configured.**
  - Linux sees 3915 MiB of 4096 MB, and L3 sees 207 MiB of 256 MiB. Firmware and early kernel reservations are taken before the OS counts memory.
  - ESXi sees a full 16 GiB because the memory map comes from Workstation's virtual firmware.
- **"Active" estimates are samples.** `guestMemoryUsage` is ESXi's statistical estimate of recently touched memory, not "used" in the Linux sense. That is why it moves (942 to 1433 MB) while `hostMemoryUsage` stays at 1574.
- **CPU percent depends on the scale.**
  - Windows' per-process counter uses 100% = one logical CPU, so `vmware-vmx` at 97.8% means about one of 24 logical CPUs busy. The `_Total` counter averages over all 24, so the same load shows as 9%.
  - That one busy CPU is the single L3 vCPU: L2's QEMU thread at 100%, carried by one ESXi vCPU, carried by one Workstation vCPU thread.
- **ESXi CPU numbers lag.** quickStats are averages over a sampling interval, so 940 MHz for the VM understates a short burst that was pinning one vCPU.
- **Do not over-interpret Task Manager** (INFERRED):
  - Its CPU column is normalized to all 24 logical CPUs, so one fully busy vCPU shows as about 4%.
  - Its default Memory column is the private working set. For `vmware-vmx` this is tiny (0.08 GiB private bytes here) because guest RAM is mapped memory, not private heap.
  - On a hybrid P/E-core CPU, a percentage does not map to a fixed amount of work.
  - The Windows view can say that the VMware stack is busy or idle, but not which nested guest is doing what.

## 10. Lessons learned

1. **Nested KVM works on VMware VHV, twice nested.** Everything a KVM host needs appeared in the ESXi guest with no module tuning: `vmx`, EPT, `/dev/kvm`, `nested=Y`.
2. **Prove acceleration from more than one angle.** Check the thread name, the `/dev/kvm` fds and the guest's hypervisor detection. `kvm-ok` alone only shows that KVM could be used.
3. **Nested performance is bimodal.** CPU-bound code is near-native; exit-heavy code (firmware, boot, device probing) is dramatically slower, and at L3 even slower than TCG. Never quote lab timings as capacity numbers.
4. **The free ESXi license blocks console automation through the API** (`RestrictedVersion` on screenshot and key injection). Unattended installs need a seed ISO plus a non-interactive confirmation path.
5. **Secrets generated on Windows must not pass through a PowerShell pipe** into Unix tools, because a trailing CR silently changes them. Verify a password hash before using it.
6. **libvirt adds a lot to what the XML says**: PCIe root ports, a USB controller, security labels, a sandbox and QMP. Reading the generated QEMU command line is the fastest way to learn both tools.
7. **The same VirtIO device can show two PCI IDs** (transitional versus modern), depending on where it sits on the PCI topology.
8. **Device-specific guest configuration is the migration risk.** UUID-based mounts survive a disk bus change; a netplan `match: driver: vmxnet3` does not.

## 11. Stage 1C entry criteria

Stage 1C has not been defined yet. Following the Stage 0 plan, the natural next step is the actual migration source VM, `legacy-source-vm` (INFERRED). Stage 1C may begin only when:

1. The user has reviewed this Stage 1B result and explicitly approved Stage 1C.
2. Stage 1C objective, scope and change boundary are written down. If it creates `legacy-source-vm`, the following must be fixed:
   - guest OS and ISO (the verified 24.04.4 ISO on `migration-datastore/iso/` can be reused);
   - sizing, a static-safe IP (not .10, .11, .20, .25 or .30), the application (nginx per Stage 0) and its validation checks.
3. A decision is recorded on what happens to `kvm-learning-01` during Stage 1C: keep it running, power it off, or keep it as a conversion-helper candidate. That keeps the nested budget clear.
   - ESXi has 8 vCPU and 16 GiB.
   - `kvm-learning-01` is configured with 2 vCPU and 4 GB, and ESXi currently backs about 1.6 GB of it.
4. The conversion-host decision (Stage 0 feasibility section 6) is either still explicitly deferred or taken as an ADR. It must not be decided implicitly by reusing `kvm-learning-01`.
5. The host is still in its recorded state:
   - maintenance mode disabled, NTP synchronized, SSH key access working, Windows hypervisor off;
   - one VM (`kvm-learning-01`), no snapshots;
   - `migration-datastore` at about 186.5 GB free (200,268,578,816 bytes).
6. Still out of scope unless explicitly approved: AWS, Kubernetes, KubeVirt, CDI and the migration controller.

## 12. Sources

- Linux kernel: [KVM API](https://docs.kernel.org/virt/kvm/api.html), [Running nested guests with KVM](https://docs.kernel.org/virt/kvm/x86/running-nested-guests.html)
- QEMU: [Introduction to system emulation](https://www.qemu.org/docs/master/system/introduction.html), [system emulation docs](https://www.qemu.org/docs/master/system/index.html), [disk images](https://www.qemu.org/docs/master/system/images.html)
- libvirt: [daemons](https://libvirt.org/daemons.html), [connection URIs](https://libvirt.org/uri.html), [domain XML](https://libvirt.org/formatdomain.html), [QEMU driver](https://libvirt.org/drvqemu.html)
- Ubuntu: [libvirt on Ubuntu Server](https://documentation.ubuntu.com/server/how-to/virtualisation/libvirt/), [autoinstall reference](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html), [24.04 SHA256SUMS](https://releases.ubuntu.com/24.04/SHA256SUMS)
- OASIS: [VirtIO 1.2 specification](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html)
- Broadcom: [KB 399823 (free ESXi API limits)](https://knowledge.broadcom.com/external/article/399823)
