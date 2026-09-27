# Interview notes

Request section 24. Answers are written to be said out loud in a Kubernetes / platform engineering interview: a short answer first, then the detail an interviewer will probe. Deeper explanations are linked.

---

### 1. "How would you migrate a VMware VM to Kubernetes?"

**Short answer:** Rehost it as a KubeVirt VM: discover and assess the VM, power it off (cold) or precopy with CBT (warm), convert the disk and guest drivers for KVM, import the disk into a PVC with CDI, create a KubeVirt `VirtualMachine` that uses that PVC with network and storage mappings, boot it, and validate the application. At scale, use a tool like MTV/Forklift; the underlying steps are the same.

**Detail:**

- Discovery and assessment: firmware, guest OS support, snapshots, disk sizes, NIC-to-network mapping, datastore-to-StorageClass mapping.
- Disk path: VMDK -> qemu-img or virt-v2v -> CDI DataVolume -> PVC (raw).
- Guest conversion matters: VMware guests use VMXNET3/PVSCSI; KubeVirt presents virtio. virt-v2v installs drivers and removes VMware Tools.
- Networking: pod network with masquerade, or a Multus secondary network if the VM must keep its L2/IP.
- Then decide per workload whether to stop there (VM on KubeVirt) or modernize into containers later.
- See [migration-architecture.md](migration-architecture.md).

### 2. "What is KubeVirt?"

**Short answer:** A Kubernetes add-on that lets you run and manage virtual machines as Kubernetes objects, next to containers, using the Kubernetes API, scheduler, networking and storage.

**Detail:** It adds CRDs (`VirtualMachine`, `VirtualMachineInstance`, and others), cluster controllers (virt-controller, virt-api, virt-operator) and a node daemon (virt-handler). Each running VM is a QEMU process managed by libvirt inside a normal Pod (virt-launcher), accelerated by KVM on the node. It is a CNCF project; OpenShift Virtualization is Red Hat's distribution of it. See [kubevirt-architecture.md](kubevirt-architecture.md).

### 3. "What is the difference between a VM and a VMI?"

**Short answer:** The `VirtualMachine` is the persistent definition and desired run state; the `VirtualMachineInstance` is one running instance of it. Like a StatefulSet with one replica versus its Pod.

**Detail:** The VM survives stop/start and holds `spec.template` and `spec.runStrategy` (`Always`, `RerunOnFailure`, `Manual`, `Halted`). virt-controller creates a VMI from the template when the VM should run and deletes it when the VM stops. The VMI carries live status: phase, node, IPs, guest info. You can create a bare VMI, but nothing restarts it.

### 4. "How does KubeVirt run a VM?"

**Short answer:** `VirtualMachine` -> virt-controller creates a VMI -> virt-controller creates a virt-launcher Pod -> the scheduler places it -> virt-handler on that node tells libvirt inside the Pod to start the domain -> QEMU runs the VM using `/dev/kvm`.

**Detail:** virt-api validates the object at admission. The launcher Pod requests CPU, memory (plus overhead) and the `devices.kubevirt.io/kvm` resource, mounts the disk PVCs, and gets networking from CNI/Multus. virt-handler renders domain XML from the VMI and keeps the domain and VMI status in sync. Status flows back: domain -> VMI phase -> VM printableStatus.

### 5. "Where does QEMU run?"

**Short answer:** In user space, inside the `compute` container of the VM's virt-launcher Pod, on the node where that Pod was scheduled. One QEMU process per VM.

**Detail:** Because it is inside a Pod, it is subject to the Pod's cgroups (CPU/memory limits), network namespace and mounted volumes. The guest's vCPUs are QEMU threads. The kernel part of virtualization is KVM on the node; QEMU talks to it through `/dev/kvm`. If the Pod dies, the VM dies, which is why the VM object and `runStrategy` exist.

### 6. "What is KVM?"

**Short answer:** A Linux kernel module that turns Linux into a hypervisor by using hardware virtualization (Intel VT-x / AMD-V, plus EPT/NPT for memory). It exposes `/dev/kvm`, which QEMU uses to create VMs and run vCPUs.

**Detail:** KVM does CPU and memory virtualization; QEMU does device emulation; libvirt does management. Unlike ESXi, where VMkernel is a purpose-built hypervisor OS, KVM is part of a general-purpose Linux kernel, so the same node can run containers and VMs. In the cloud you need bare metal or nested virtualization to get `/dev/kvm`.

### 7. "How would you import a VMDK into KubeVirt?"

**Short answer:** With CDI. Either put the VMDK (or a qcow2 converted from it) at an HTTP/S3 URL and create a DataVolume with an `http` or `s3` source, or push it with `virtctl image-upload`. CDI converts it to raw in a new PVC, and the VM references that PVC.

**Detail:**

- Make sure the VMDK is consistent (VM off, no snapshot chain, or consolidated) and that you copied every file its layout needs. Layouts differ: a VMFS disk is usually a descriptor plus a flat extent, while a Workstation `monolithicSparse` disk is one file. Copying only the descriptor gives you nothing.
- CDI accepts VMDK directly, but converting to qcow2 first reduces size and lets you check it with `qemu-img check`.
- A format conversion does not fix guest drivers. Use virt-v2v if the guest lacks virtio drivers (always for Windows).
- For direct import from vCenter/ESXi, CDI has a `vddk` source (needs the VDDK image and API access; not viable on free ESXi).
- Watch StorageClass binding mode, size (virtual size, not file size), and scratch space.

### 8. "What does CDI do?"

**Short answer:** It populates PVCs with VM disk data: import from URLs, registries, S3 or VMware (VDDK); upload from a client; clone from another PVC or snapshot; or create blank disks. It converts images to raw and reports progress through the `DataVolume` CR.

**Detail:** CDI ends when the DataVolume is `Succeeded` and the PVC holds a bootable raw disk. KubeVirt begins when a VM references that PVC. CDI knows nothing about CPUs or NICs. See [cdi-storage-model.md](cdi-storage-model.md).

### 9. "How would you design a migration CRD?"

**Short answer:** One namespaced CR per VM migration, with a declarative `spec` (source, destination, strategy, storage mapping, network mapping, validation) and a controller-owned `status` (phase, conditions, progress, frozen source inventory, created destination objects, errors, timestamps). Credentials by Secret reference only.

**Detail:**

- Keep spec intent-level and mostly immutable once the migration starts.
- `status.phase` drives the state machine; conditions give independent, typed facts.
- `observedGeneration` shows whether status reflects the latest spec.
- A finalizer enables cleanup of staging data and partial imports.
- Owner references from DataVolumes/VM to the migration CR.
- Explicit `powerOffPolicy`, because powering off the source is the only action that affects production.
- See the sketch in [migration-architecture.md](migration-architecture.md).

### 10. "How does a Kubernetes controller execute the migration?"

**Short answer:** It watches `VirtualMachineMigration` objects and their children, and for each one runs a reconcile: read the current phase, perform the next idempotent step for that phase (power off, convert, create DataVolume, create VM), observe the result, update status, and requeue until a terminal phase.

**Detail:** Events go to a work queue keyed by `namespace/name`, which deduplicates and ensures one worker per object. Long steps are not awaited in-process; the controller creates Jobs or DataVolumes and requeues or reacts to watch events when their status changes. Status updates go through the status subresource. See [crd-controller-fundamentals.md](crd-controller-fundamentals.md).

### 11. "What happens when migration fails halfway?"

**Short answer:** The CR keeps the phase where it failed and records the error. Transient errors are retried with backoff in the same phase; permanent or ambiguous errors go to `Failed` or `ManualInterventionRequired`. Because the source disk is only read after power-off, the source is intact and can be powered back on.

**Detail:**

- The controller never restarts from scratch; it resumes the recorded phase.
- Partial destination objects (DataVolumes, VM) are owned by the CR, so deletion (with the finalizer) cleans them up.
- The controller must not automatically power the source back on once the target VM has started, to avoid two live copies with the same identity.
- Retry budget prevents infinite loops. See [migration-state-machine.md](migration-state-machine.md).

### 12. "How would you make the migration controller idempotent?"

**Short answer:** Make every step "ensure", not "do": deterministic names for created objects, create-if-absent and update-if-different, check external state before acting, record evidence (checksums, URLs, object names) in status before advancing the phase, and treat "already done" and "not found on delete" as success.

**Detail:**

- DataVolume name `<migration>-disk-<n>`; staging key `<migration-uid>/disk-<n>.qcow2`.
- Power-off: check power state first; "already off" is success; record the timestamp once.
- Use optimistic concurrency (`resourceVersion`) on status updates and requeue on conflict.
- Never keep progress only in memory; a controller restart must be safe at any line of code.
- Guard irreversible actions behind validated conditions.

### 13. "What is the difference between VM migration and application modernization?"

**Short answer:** Migration (rehost) moves the whole VM, guest OS included, to a new platform without changing the app. Modernization changes how the app is packaged and run, for example as a container image in a Deployment, which removes the VM and guest OS.

**Detail:** KubeVirt migration is fast and low-risk and puts VMs on the same platform as containers, but you still patch and operate a guest OS. Modernization needs assessment and app changes but gives horizontal scaling, rolling updates and image-based delivery. A good program migrates first and modernizes selectively. Project 1.5 shows both on the same nginx workload. See [modernization-model.md](modernization-model.md).

---

## Stage 1B additions: KVM, QEMU, libvirt and VirtIO, from the lab

Answers below are backed by what was actually run in Stage 1B on `kvm-learning-01` (see [Stage 1B record](../stage-1/stage-1b-kvm-qemu-fundamentals.md), [nested KVM feasibility](../stage-1/nested-kvm-feasibility.md)). Question 6 above gives the short definition of KVM; question 14 adds the lab view.

### 14. "What is KVM?" (lab view)

**Short answer:** The hypervisor built into the Linux kernel: the modules `kvm` and `kvm_intel` (or `kvm_amd`). It uses VT-x/AMD-V and EPT/NPT to run guest code directly on the CPU, and exposes `/dev/kvm` so a user-space program can create VMs and vCPUs.

**Detail:** KVM handles CPU and memory virtualization and a few latency-critical devices (local APIC, timers), and it handles VM exits. It emulates no disks, NICs or firmware. In the lab, Ubuntu autoloaded `kvm_intel` inside an ESXi guest as soon as the (virtual) CPU showed the `vmx` flag, with `nested=Y` and `ept=Y`; no tuning was needed.

### 15. "What is QEMU?"

**Short answer:** A user-space machine emulator and virtual machine monitor. One `qemu-system-x86_64` process per VM provides the chipset, firmware, PCI bus and every virtual device, and runs guest code either through KVM or with its own software emulator (TCG).

**Detail:** Each vCPU is a thread of the QEMU process (`CPU 0/KVM`, or `CPU 0/TCG` without KVM). Guest RAM is ordinary memory in the QEMU process. Disks and NICs are split into a backend (qcow2 file, user-mode network) and a frontend device model (virtio-blk, virtio-net). The machine model (`q35`, `pc`) picks the chipset. In KubeVirt, the same QEMU runs inside the virt-launcher Pod.

### 16. "Why do we need both KVM and QEMU?"

**Short answer:** They do different jobs. KVM makes the CPU run guest code safely at native speed but cannot build a whole machine; QEMU builds the whole machine but, alone, has to emulate the CPU in software. Together you get a full VM at near-native CPU speed.

**Detail:** In the lab, the same tiny guest ran a 128 MiB `md5sum` in 0.22 s with QEMU + KVM, versus 2.05 s with QEMU alone (TCG), and a shell loop in 0.33 s versus 5.09 s. Device emulation was QEMU's job in both runs. KVM cannot do anything useful without a user-space VMM; QEMU without KVM works, only slowly. They are separate components from separate projects.

### 17. "What is /dev/kvm?"

**Short answer:** The character device (major 10, minor 232) through which user space talks to KVM. QEMU opens it and uses `ioctl()` calls to create a VM, create vCPUs, register memory and run vCPUs (`KVM_RUN`).

**Detail:** It exists only when a KVM module is loaded, which requires VT-x/AMD-V visible to the kernel. Permissions come from the `kvm` group (`crw-rw---- root kvm`). In the lab it appeared inside the ESXi guest before any package was installed. The running QEMU process held `/dev/kvm` plus `anon_inode:kvm-vm` and `anon_inode:kvm-vcpu:0` file descriptors. In KubeVirt, virt-handler advertises it to the scheduler as the `devices.kubevirt.io/kvm` resource.

### 18. "What happens when QEMU uses KVM?"

**Short answer:** QEMU sets up the VM through `/dev/kvm`, then each vCPU thread calls `ioctl(KVM_RUN)`. KVM enters the guest with VMLAUNCH/VMRESUME and the guest runs natively until a VM exit. KVM handles the exit in the kernel if it can; otherwise it returns to QEMU, which emulates the device access and calls `KVM_RUN` again.

**Detail:** Typical exits are port or MMIO I/O, some MSR accesses, `HLT`, interrupts and EPT faults. The cost of a VM exit is what separates good from bad virtual performance. In the lab, three hypervisors deep, one exit travels through Workstation, ESXi and KVM. CPU-bound work in the L3 guest was as fast as in L2, but the exit-heavy firmware and boot phase took about 17 s under KVM, compared with about 6 s under TCG.

### 19. "What is nested virtualization?"

**Short answer:** Running a hypervisor inside a virtual machine. The outer hypervisor must expose (emulate) the CPU's virtualization extensions, VT-x and EPT, to the inner one, so that the inner hypervisor can run its own hardware-accelerated guests.

**Detail:** VMware calls the setting VHV (`vhv.enable = "TRUE"`). KVM calls it the `nested` parameter of `kvm_intel`. AWS enables it per instance on supported instance types. It works, but every exit of the innermost guest is handled by the outermost hypervisor first and reflected inward, so it costs performance. The lab stacks three hypervisors: Workstation, ESXi, KVM.

### 20. "Explain L0, L1 and L2."

**Short answer:** L0 is the hypervisor on the physical hardware. L1 is a guest hypervisor running as a VM on L0. L2 is a VM run by L1. That is the Linux kernel's naming for nested guests.

**Detail:** In our lab: L0 is the VMware Workstation VMM on the laptop, L1 is ESXi, L2 is `kvm-learning-01`, and because L2 runs KVM there is also an L3 test VM. Windows is the host OS of a type-2 hypervisor and has no level number. On AWS with nested virtualization, Nitro is L0, the EC2 worker node running KVM is L1, and the KubeVirt VM is L2. On a `.metal` instance, the node's own KVM becomes L0.

### 21. "What is libvirt?"

**Short answer:** A management layer for hypervisors: an API, a daemon (`libvirtd`, or modular daemons such as `virtqemud`) and a declarative VM format (domain XML). For QEMU/KVM it generates the QEMU command line, starts and monitors the QEMU process, and applies security labels, cgroups and logging.

**Detail:** In the lab, a hand-written 30-line domain XML became a QEMU command line with `-accel kvm -cpu host,migratable=on`, a QMP monitor socket, `-sandbox`, `-blockdev` nodes, five PCIe root ports and a USB controller the XML never mentioned. QEMU ran as user `libvirt-qemu` under an enforcing AppArmor profile. KubeVirt runs one libvirtd per VM inside the virt-launcher Pod and generates the domain XML from the VMI.

### 22. "What is virsh?"

**Short answer:** The command-line client for the libvirt API. It sends requests to the libvirt daemon (`define`, `start`, `shutdown`, `destroy`, `list`, `dumpxml`); it does not run VMs itself.

**Detail:** The connection URI matters. `qemu:///system` talks to the system daemon (root-owned VMs); `qemu:///session` is a per-user instance. In the lab, `virsh uri` returned `qemu:///session` for the normal user and `qemu:///system` for root. The VMware counterpart is roughly `vim-cmd` talking to hostd.

### 23. "What is VirtIO?"

**Short answer:** An OASIS-standard family of paravirtual devices for VMs. The guest knows it is virtual and exchanges requests with the hypervisor through shared-memory queues (virtqueues) rather than through emulated hardware registers. Main types: virtio-net, virtio-blk, virtio-scsi.

**Detail:** VirtIO devices appear as PCI devices with vendor `1af4`: transitional IDs (`1000` net, `1001` blk, `1004` scsi) or modern IDs (`1041`, `1042`, `1048`). The lab saw both, depending on where QEMU or libvirt placed the device. Linux ships the drivers in the kernel (`virtio_blk`, `virtio_scsi`, `virtio_net`). Windows needs the virtio-win drivers. KubeVirt presents VirtIO devices by default.

### 24. "VirtIO versus VMXNET3?"

**Short answer:** Both are paravirtual NICs with the same job, but they are different devices. VMXNET3 is VMware's (PCI `15ad:07b0`, driver `vmxnet3`); virtio-net is the KVM/QEMU standard (PCI `1af4:1000` or `1041`, driver `virtio_net`). A guest must have the right driver, and its network configuration must not be tied to the old device.

**Detail:** After conversion the NIC changes driver, MAC vendor prefix (`00:0c:29` to `52:54:00`) and usually its interface name (`ens192` to `enp1s0`). In the lab VM, netplan matches the NIC by `driver: "vmxnet3"`, so after a naive disk move the VM would boot with no configured network. virt-v2v or a pre-migration step must fix that.

### 25. "VirtIO versus PVSCSI?"

**Short answer:** PVSCSI is VMware's paravirtual SCSI controller (PCI `15ad:07c0`, driver `vmw_pvscsi`). The VirtIO equivalents are virtio-scsi (also a SCSI controller, disks stay `/dev/sdX`) and virtio-blk (a simpler per-disk device, disks become `/dev/vdX`). Same role, different devices and drivers.

**Detail:** KubeVirt uses virtio-blk by default for disks, so a migrated Linux guest usually goes from `/dev/sda` to `/dev/vda`. The lab VM mounts `/` and `/boot/efi` by UUID and boots with `root=UUID=...`, so it survives the rename. A guest with `/dev/sda1` in `/etc/fstab` would not. The Ubuntu kernel has the VirtIO storage drivers built in, so no initramfs rebuild is needed; older or custom kernels may need one.

### 26. "What happens if /dev/kvm does not exist?"

**Short answer:** QEMU cannot use hardware acceleration. `-accel kvm` fails, and QEMU can only run with TCG software emulation, which is roughly 10x slower for CPU-bound work (9x to 15x in the lab). KubeVirt will not schedule VMs on that node unless software emulation is explicitly enabled, which is only for testing.

**Detail:** Diagnose from the bottom up:

- Does the CPU expose `vmx`/`svm` in `/proc/cpuinfo`? If not, virtualization is disabled in firmware, or on a VM the outer hypervisor is not exposing it (VHV off, or a cloud instance without nested virtualization).
- Is the module loaded (`lsmod | grep kvm`)? Does `dmesg` show an error such as "disabled by bios"?
- Is the user in the `kvm` group?

`kvm-ok` summarizes these checks. Never treat a TCG run as proof that KVM works: check for the `CPU n/KVM` thread, the `/dev/kvm` file descriptor, or `Hypervisor detected: KVM` in the guest.

---

## Stage 1C additions: the migration source VM

Answers below are backed by the Stage 1C source VM `legacy-source-vm` (see [Stage 1C record](../stage-1/stage-1c-migration-source.md)). Statements about the KubeVirt side are INFERRED; nothing has been migrated yet.

### 27. "How do you baseline a VM before migrating it?"

**Short answer:** Record three things before touching it: the platform view (hypervisor config), the guest view (OS, devices, identifiers, network, services), and a deterministic application check. Then the migrated copy can be compared fact by fact instead of "it seems to work".

**Detail:** For `legacy-source-vm` the baseline covers:

- **ESXi side:** Vmid, `.vmx` path, CPU/RAM, thin 40 GB disk, PVSCSI, VMXNET3, MAC, firmware, snapshots.
- **Guest side:** OS and kernel, `lsblk`/`blkid` UUIDs, fstab, kernel command line, interface name and driver, netplan, routes, DNS, loaded drivers, EFI boot entries, cloud-init state.
- **Application:** nginx version, unit state, listening sockets, config file checksums, and the sha256 of a static validation page fetched from another machine.

Collect it with commands whose output can be diffed. Label what was observed versus inferred.

### 28. "Which identifiers survive a VMware to KubeVirt migration, and which change?"

**Short answer:** Everything stored on the disk survives: filesystem UUIDs, PARTUUIDs, the GPT disk GUID, machine-id, SSH host keys, hostname, config files. Everything the platform presents changes: controller and NIC drivers, device names, PCI paths, interface name, MAC, SMBIOS UUID and serial, and UEFI NVRAM entries.

**Detail:** In the lab, `/dev/sda` behind PVSCSI becomes `/dev/vda` on virtio-blk, `ens192`/`vmxnet3` becomes something like `enp1s0`/`virtio_net`, and the VMware MAC `00:0c:29:0f:3d:15` is replaced unless the KubeVirt spec sets `macAddress`. Some platform identifiers can be pinned in KubeVirt if the guest depends on them: MAC, `firmware.uuid`, `firmware.serial`. Device names cannot and should never be treated as identity.

### 29. "Why does a migrated Linux VM often boot but have no network?"

**Short answer:** Its network config is tied to the old NIC. Here, netplan configures the interface named `ens192`. On KubeVirt the virtio-net NIC gets a different name, nothing matches it, and the interface stays unconfigured.

**Detail:** The rendered networkd file contains `[Match] Name=ens192`, and the name comes from VMware's PCI slot 192. The Stage 1B VM had the same problem with `match: driver: vmxnet3`. Fixes belong to the migration design, not the source: match by MAC and preserve the MAC, rewrite the config during conversion (virt-v2v does some of this), or supply target-side config. Even with a matching interface, a static 192.168.50.x address does not fit KubeVirt's default masquerade pod network. Keeping the address needs a bridged secondary network.

### 30. "Why use UUIDs in fstab?"

**Short answer:** Because device names depend on the controller and discovery order, while filesystem UUIDs are stored inside the filesystem and travel with the disk.

**Detail:** `legacy-source-vm` mounts `/` and `/boot/efi` by `/dev/disk/by-uuid/...`, boots with `root=UUID=db8b3bb3-...`, and GRUB finds its files with `search --fs-uuid`. The switch from PVSCSI (`sda`) to virtio-blk (`vda`) therefore needs no edit. `/dev/disk/by-path` changes with the PCI topology, and `/dev/disk/by-id` is empty on this VMware disk, so neither is a good anchor. A guest with `/dev/sda1` in fstab would drop to an emergency shell after migration.

### 31. "What is special about migrating a UEFI VM?"

**Short answer:** The boot entries are not on the disk. VMware keeps them in the VM's `.nvram` file, so the target starts with an empty or different variable store and must find the loader through the removable-media fallback path `\EFI\BOOT\BOOTX64.EFI`.

**Detail:** On `legacy-source-vm` that file exists and is identical to `shimx64.efi`. On a fallback boot, shim runs `fbx64.efi`, which recreates the "Ubuntu" entry from `BOOTX64.CSV`. Two more things to settle in the target spec:

- KubeVirt's EFI firmware defaults to Secure Boot on, and the source had it off. Signed Ubuntu components should boot either way, but the choice should be explicit, and Secure Boot needs SMM.
- NVRAM persistence is off by default in KubeVirt.

A BIOS-to-UEFI or UEFI-to-BIOS mismatch is a different, harder failure.

### 32. "Why keep the learning VM, the source VM and the conversion host separate?"

**Short answer:** Each has a different job and a different blast radius. The source VM must stay a clean, unmodified reference. The learning VM is where experiments and package installs happen. A conversion host needs disk access and conversion tooling. Mixing them contaminates the baseline or quietly makes an architecture decision.

**Detail:** In the lab, `kvm-learning-01` (KVM/QEMU/libvirt installed, nested virtualization on) was powered off after the source baseline and never touched `legacy-source-vm`. The conversion-host decision stays explicitly deferred (local helper, AWS helper or another runtime) instead of being made implicitly by reusing the learning VM.

---

## Stage 1D additions: VMware source artifacts

Answers below are backed by the read-only Stage 1D investigation of `legacy-source-vm` (see [Stage 1D record](../stage-1/stage-1d-vmware-source-artifacts.md)).

### 33. "What files make up a VMware VM, and which ones does a migration need?"

**Short answer:** A `.vmx` (configuration), an `.nvram` (firmware variables), the virtual disk (a descriptor `.vmdk` plus its data extent), a few small metadata files (`.vmxf`, `.vmsd`), and runtime files (`.vswp`, locks, logs). A migration needs the disk **contents**. The `.vmx` is only a reference for writing the target VM definition, and the `.nvram` is not moved at all.

**Detail:** In the lab folder there are 14 files, 7.5G in total. About 4.1 GiB of that is swap that exists only while the VM runs, and 3.4 GiB is the allocated disk data. The target KubeVirt VM is a new object: its spec is written from the `.vmx` facts (CPU, RAM, EFI, disk bus, NIC, optionally MAC), its disk is imported from the extent, and its firmware state is created fresh. It then boots through the ESP fallback loader.

### 34. "What is inside a VMDK on ESXi?"

**Short answer:** Usually two files. A small text descriptor (`createType="vmfs"`, CID, extent list, `ddb.*` bookkeeping) and a `-flat.vmdk` extent that is simply the raw disk sectors. Thin provisioning is done by VMFS (holes in the flat file), not by the VMDK format.

**Detail:** The lab disk's descriptor is 541 bytes and names one extent of 83,886,080 sectors. The flat file has a logical size of 40 GiB but only 3,487 1 MiB blocks allocated (`vmkfstools -D`: `nb 3487`). `parentCID=ffffffff` shows there is no snapshot chain. The descriptor's `adapterType` and `virtualHWVersion` are creation-time hints and do not describe the running VM. Other layouts exist: Workstation's `monolithicSparse`, the `2gbsparse` export format, OVF's `streamOptimized`. Never assume one; read the descriptor.

### 35. "How do you get a VM's disk off a free ESXi host?"

**Short answer:** Without vCenter and with a restricted API, use the host's SSH: power the VM off cleanly, then `scp` the descriptor and flat extent, or first `vmkfstools -i ... -d 2gbsparse` to a staging folder and copy the compact result. Verify with a checksum on both ends.

**Detail:** In the lab, `scp` streamed at about 137 MiB/s, so the raw 40 GiB copy takes about 5 minutes. A `2gbsparse` export would move only about 3.5 GiB, but it re-encodes the container and needs a VMDK-aware tool to verify. The HTTPS `/folder` file service also works with an authenticated session, but brings no advantage over the existing SSH key. OVF export depends on the API and was not pursued. Tools like MTV/Forklift use VDDK or NFC and assume vCenter or a licensed API.

### 36. "Why can't you just copy a running VM's disk?"

**Short answer:** Two reasons. VMFS holds an exclusive lock on an open disk, so you cannot even read it. And if you could, the copy would be taken from a live, changing filesystem: crash-consistent at best. Hot copies need a snapshot, which freezes the base disk and redirects writes to a delta.

**Detail:** In the lab, a 1 MiB `dd` read of the running flat file failed with "Device or resource busy", and the HTTPS file service returned HTTP 500 for it. Snapshots are forbidden for this source VM, so the only consistent option is a cold copy after a graceful guest shutdown. Warm migration tools use snapshots plus changed block tracking (CBT); CBT is off on this VM.

### 37. "How do you prove that acquiring the disk did not change the source?"

**Short answer:** With the VM powered off, hash the flat extent on the host before and after the copy, and compare the copy's hash with it. Cheap supporting checks: descriptor checksum and CID, file size and mtime, VMFS allocation (`nb`), `.vmx`/`.nvram` checksums, power-state history and snapshot count.

**Detail:** A full 40 GiB hash costs about 5.5 minutes per pass on the lab host. The cheap checks are strong indicators but not proof. The hash proves copy fidelity, not filesystem consistency; that comes from the clean shutdown. Once the source is powered on again, its disk changes legitimately (journal, logs), so "unchanged" can only be claimed for the powered-off window. After conversion, disk hashes no longer apply: verify the migrated VM at guest and application level (FS UUIDs, machine-id, SSH host keys, the nginx page hash).
