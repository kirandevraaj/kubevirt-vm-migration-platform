# Glossary

Request section 23. Terms are grouped by area; each includes the closest VMware analogy where one helps. Links point to the Stage 0 document that explains the term in depth.

## Virtualization stack

| Term | Definition | VMware analogy |
|---|---|---|
| **Hypervisor** | Software that runs virtual machines. Type 1 runs on hardware (ESXi, KVM-enabled Linux); type 2 runs on a host OS (Workstation). | ESXi |
| **KVM** | Kernel-based Virtual Machine. A Linux kernel module that uses VT-x/AMD-V and EPT/NPT to run guest code directly on the CPU. Exposed as `/dev/kvm`. See [virtualization-fundamentals.md](virtualization-fundamentals.md). | The VMM inside VMkernel |
| **QEMU** | User-space machine emulator. With KVM it provides firmware and virtual devices (disks, NICs) for one VM per process. | VMX process |
| **libvirt** | Management API/daemon that turns domain XML into a running QEMU process. In KubeVirt, one libvirtd runs inside each virt-launcher Pod. | hostd (per VM, loosely) |
| **Domain XML** | libvirt's VM definition (CPU, memory, disks, interfaces). KubeVirt generates it from the VMI. | `.vmx` file |
| **VirtIO** | Standard for paravirtualized devices (virtio-net, virtio-blk, virtio-scsi) using shared-memory queues. Needs guest drivers. | VMXNET3, PVSCSI |
| **QEMU guest agent** | Daemon inside the guest that reports IPs and OS info and supports graceful shutdown and filesystem freeze. | VMware Tools |
| **VT-x / AMD-V** | CPU extensions for hardware-assisted virtualization. | - |
| **EPT / NPT (SLAT)** | Hardware second-level page tables for guest-physical to host-physical translation. | - |
| **Nested virtualization** | Running a hypervisor inside a VM. L0 = hardware hypervisor, L1 = guest hypervisor, L2 = its guests. | VHV ("Virtualize Intel VT-x/EPT") |
| **VHV** | VMware's setting to expose VT-x/EPT to a VM (`vhv.enable`). | - |
| **VMkernel** | The ESXi kernel. Also the name for ESXi host IP interfaces (`vmk0`). | - |
| **VMX** | The `.vmx` config file of a VMware VM, and its per-VM process. Not to be confused with Intel VMX, the CPU extension behind VT-x (see [KVM lab terms](#kvm-lab-terms-stage-1b)). | - |

## KVM lab terms (Stage 1B)

Terms as observed in the Stage 1B learning VM `kvm-learning-01` (see [Stage 1B record](../stage-1/stage-1b-kvm-qemu-fundamentals.md) and [nested KVM feasibility](../stage-1/nested-kvm-feasibility.md)). Level numbers refer to that lab: L0 Workstation, L1 ESXi, L2 `kvm-learning-01`, L3 its test VM.

| Term | Definition | Seen in the lab | VMware analogy |
|---|---|---|---|
| **KVM** | The Linux kernel's hypervisor: modules `kvm` + `kvm_intel`/`kvm_amd`. It creates VMs and vCPUs, maps guest memory, enters the guest with VT-x and handles VM exits. It emulates no devices. | `kvm_intel` autoloaded in L2 with `nested=Y`, `ept=Y` | VMM inside VMkernel |
| **QEMU** | User-space VMM and device model: one `qemu-system-x86_64` process per VM, providing chipset, firmware and devices. Uses KVM (`-accel kvm`) or its own software CPU emulator (`-accel tcg`). A separate component from KVM. | QEMU 8.2.2 running the L3 guest | VMX process |
| **libvirt** | Management API and daemon (`libvirtd`, or modular `virtqemud`) that turns a domain XML definition into a QEMU process and manages its lifecycle, security labels, cgroups and logs. | libvirt 10.0.0, monolithic `libvirtd` on Ubuntu 24.04 | hostd |
| **virsh** | Command-line client of the libvirt API (`define`, `start`, `list`, `dumpxml`, `destroy`). It does not run VMs itself; the daemon does. | `virsh -c qemu:///system list --all` | vim-cmd |
| **virtio-blk** | VirtIO paravirtual block device: one disk per PCI function, seen as `/dev/vdX`. Driver `virtio_blk`. | L3 `vda`, PCI `1af4:1001`/`1af4:1042` | PVSCSI disk (role only) |
| **virtio-scsi** | VirtIO paravirtual SCSI host adapter; disks behind it appear as `/dev/sdX`. Drivers `virtio_scsi` + `sd`. | L3 `sda`, PCI `1af4:1004`/`1af4:1048` | PVSCSI controller (role only) |
| **virtio-net** | VirtIO paravirtual Ethernet NIC. Driver `virtio_net`. | L3 `eth0`, PCI `1af4:1000`/`1af4:1041` | VMXNET3 (role only) |
| **/dev/kvm** | Character device (major 10, minor 232) through which user space talks to KVM with `ioctl()`. Present only when a KVM module is loaded and the CPU offers VT-x/AMD-V. Access is controlled by the `kvm` group. | `crw-rw---- root kvm 10, 232` in L2 | - |
| **VMX (Intel)** | Virtual Machine Extensions, Intel's CPU instruction set for VT-x (VMXON, VMLAUNCH, VMRESUME, VMCS). The `vmx` flag in `/proc/cpuinfo` means the CPU (real or virtual) offers it. | `vmx` flag in L2 and in L3 | The `.vmx` file is unrelated |
| **L0** | The hypervisor that runs on the physical CPU and owns the real VT-x. | VMware Workstation VMM | - |
| **L1** | A guest hypervisor running inside an L0 VM. | ESXi 8.0.3 | Nested ESXi |
| **L2** | A VM run by the L1 hypervisor. In this lab L2 is itself a KVM host, which creates an L3. | `kvm-learning-01` | VM on nested ESXi |
| **Nested virtualization** | Running a hypervisor inside a VM, with the outer hypervisor exposing (emulating) VT-x/EPT to the inner one. Every VM exit of the innermost guest is taken by L0 first and reflected inward. | Three hypervisors deep: Workstation, ESXi, KVM | VHV |
| **Hardware-assisted virtualization** | Guest code runs directly on the CPU in VT-x non-root mode, with EPT translating guest-physical to host-physical memory; the hypervisor steps in only on VM exits. | L3 with `-accel kvm`: thread `CPU 0/KVM` | ESXi's hv-vt + gphys-ept VMM mode |
| **Software emulation** | The hypervisor itself interprets or translates every guest instruction (QEMU TCG). Works without VT-x but is much slower for CPU-bound work. | L3 with `-accel tcg`: 9x to 15x slower | Old binary translation mode |
| **TCG** | Tiny Code Generator, QEMU's software CPU emulator. | `CPU 0/TCG` thread, used only as a control | - |
| **vCPU** | A virtual CPU. In QEMU/KVM each vCPU is one host thread looping on `ioctl(KVM_RUN)`; the host scheduler places it on real CPUs. | Thread `CPU 0/KVM` in the L3 QEMU process | vCPU world |
| **Guest physical memory** | The address space the guest believes is its RAM. QEMU allocates it as ordinary process memory and registers it with KVM; EPT maps it to host memory, which is backed only when touched. | L3 `-m 256`: MemTotal 211,564 kB, QEMU RSS ~176 MB | VM memory vs. consumed host memory |
| **L3** | A VM run by an L2 hypervisor. Specific to this lab. | busybox test VM under KVM | - |

## Disks and conversion

| Term | Definition |
|---|---|
| **VMDK** | VMware virtual-disk representation. Its on-disk layout depends on format and provisioning: some layouts use a text descriptor plus extent files (for example ESXi's descriptor + `-flat.vmdk`), others a single monolithic sparse file (for example Workstation `monolithicSparse`). Snapshots add delta disks to a chain. See [cdi-storage-model.md](cdi-storage-model.md#vmdk-vmware). |
| **Descriptor (VMDK)** | Text metadata of a VMDK (geometry, CID/parentCID, extent list); a separate file or embedded in a sparse extent. |
| **Extent (VMDK)** | A file holding a VMDK's data bytes; flat (preallocated layout) or sparse (grain-allocated). |
| **QCOW2** | QEMU copy-on-write v2. Thin by nature; supports snapshots, compression and backing files. |
| **RAW** | Plain byte-for-byte disk image. No metadata; can be sparse on the filesystem. CDI stores imported disks as raw. |
| **Thin provisioning** | Allocating storage only as it is written. |
| **Sparse file** | A file with unallocated holes, so its apparent size exceeds its allocated size. |
| **Snapshot (disk)** | Point-in-time state, stored as a delta on top of a base image. |
| **Backing file** | Read-only base image under a qcow2 overlay. |
| **qemu-img** | Tool to inspect, create, convert, check and resize disk images (`info`, `convert`, `check`, `rebase`, `resize`). |
| **libguestfs** | Library and tools that open disk images in a small appliance to read or modify files inside a guest safely. |
| **virt-v2v** | Converts a whole guest from VMware (and others) to KVM: copies disks, installs/enables virtio drivers, removes VMware Tools, fixes boot config. Built on libguestfs. |
| **VDDK** | VMware Virtual Disk Development Kit. Proprietary library for reading VMware disks over the network; used by CDI's `vddk` source, virt-v2v and MTV. |
| **NFC** | VMware Network File Copy protocol for disk transfer; an alternative to VDDK in some tools. |
| **OVA / OVF** | VMware export formats: OVF (descriptor + disks), OVA (single tar archive). |

## Kubernetes extension model

| Term | Definition |
|---|---|
| **CRD** | CustomResourceDefinition. Registers a new resource type (group, version, kind, schema) with the API server. See [crd-controller-fundamentals.md](crd-controller-fundamentals.md). |
| **Custom Resource** | One object of a CRD-defined type, for example one `VirtualMachine`. |
| **Controller** | A loop that watches objects and acts to make actual state match desired state. |
| **Operator** | A controller (with its CRDs) that encodes operational knowledge for one application, for example virt-operator. |
| **Reconcile loop** | The controller function that, for one object, reads desired state, observes actual state, takes one idempotent step, and writes status. It may run any number of times. |
| **Desired state** | What the user asks for, in `spec`. |
| **Observed state** | What the controller last saw, in `status`. |
| **Status subresource** | Separate API endpoint for `status`, so users edit `spec` and controllers edit `status`. |
| **Condition** | Typed status entry (`type`, `status`, `reason`, `message`, `lastTransitionTime`). |
| **Finalizer** | Key in `metadata.finalizers` that blocks deletion until the controller cleans up and removes it. |
| **Owner reference** | Link from a child object to its parent; enables garbage collection. |
| **Informer / work queue** | Client-side watch + cache, and the deduplicating, rate-limited queue of object keys to reconcile. |
| **Idempotency** | Property that repeating an operation has the same effect as doing it once. |
| **Resumability** | After any interruption, the next reconcile continues from the observed state instead of starting over. |
| **Retry safety** | A failed step can be retried without corrupting data or duplicating objects, because partial results are detected first. |
| **Reconciliation checkpoint** | A phase understood as "the desired state the controller is currently making true", re-evaluated on every reconcile; not a step in a script. See [migration-state-machine.md](migration-state-machine.md). |
| **Compatibility tuple** | The (KubeVirt, Kubernetes, CDI) versions chosen together at deployment time and accepted only after runtime validation. See [feasibility.md](feasibility.md). |

## KubeVirt

| Term | Definition | VMware analogy |
|---|---|---|
| **KubeVirt** | Kubernetes add-on that runs VMs as Kubernetes objects, using KVM/QEMU/libvirt inside Pods. See [kubevirt-architecture.md](kubevirt-architecture.md). | vSphere, as a Kubernetes add-on |
| **VM (`VirtualMachine`)** | Persistent KubeVirt object: VM template + `runStrategy`. Exists while stopped. | VM in inventory |
| **VMI (`VirtualMachineInstance`)** | One running instance of a VM. Created on start, deleted on stop. | A powered-on VM |
| **runStrategy** | VM field: `Always`, `RerunOnFailure`, `Manual`, `Halted`. | Power state policy + HA restart |
| **virt-operator** | Installs and upgrades KubeVirt from the `KubeVirt` CR. | vCenter installer / lifecycle manager |
| **virt-api** | KubeVirt API webhooks (defaulting, validation) and subresources (start, stop, console, migrate). | - |
| **virt-controller** | Cluster-wide controller: VM -> VMI -> virt-launcher Pod, migrations. | vCenter (orchestration part) |
| **virt-handler** | Privileged DaemonSet on each node; drives virt-launcher/libvirt so the domain matches the VMI; reports status. | hostd on each host |
| **virt-launcher** | The Pod (one per VMI) whose compute container runs libvirtd and QEMU for that VM. | The VM's VMX world |
| **virtctl** | KubeVirt CLI for start/stop, console, VNC, image upload, and more. | Host Client actions |
| **Live migration** | Moving a running VMI between nodes (`VirtualMachineInstanceMigration`). Not the same as VMware -> KubeVirt migration. | vMotion |
| **Instancetype / Preference** | Reusable VM sizing and device preference objects. | VM templates (partly) |

## CDI and storage

| Term | Definition |
|---|---|
| **CDI** | Containerized Data Importer. Kubernetes add-on that fills PVCs with VM disk images (import, upload, clone), converting them to raw. See [cdi-storage-model.md](cdi-storage-model.md). |
| **DataVolume** | CDI CR: "create a PVC and populate it from this source". Reports phase and progress. |
| **PVC** | PersistentVolumeClaim: a request for storage. Holds the VM's disk. |
| **PV** | PersistentVolume: the actual volume (for example an EBS volume) bound to a PVC. |
| **StorageClass** | Policy for dynamically provisioning PVs (provisioner, parameters, binding mode). Closest to a datastore + storage policy. |
| **CSI** | Container Storage Interface; the plugin standard storage drivers implement (for example the EBS CSI driver). |
| **Access mode** | RWO (one node), RWX (many nodes), ROX. Live migration needs RWX or storage migration. |
| **Volume mode** | `Filesystem` (disk as `disk.img` file) or `Block` (raw block device). |
| **WaitForFirstConsumer** | StorageClass binding mode that delays PV creation until a Pod is scheduled (keeps EBS in the right AZ). |
| **Scratch space** | Temporary PVC CDI uses during some imports and conversions. |
| **Upload proxy** | `cdi-uploadproxy`, the endpoint `virtctl image-upload` sends images to. |

## Networking

| Term | Definition | VMware analogy |
|---|---|---|
| **Pod network** | The cluster's default network (CNI); one IP per Pod. | A routed network, not a port group |
| **CNI** | Container Network Interface; plugins that give Pods network interfaces. | vSwitch implementation |
| **masquerade binding** | Guest gets a private IP via in-pod DHCP; traffic NATed to the pod IP. | NAT network |
| **bridge binding** | Guest NIC bridged to the pod (or secondary) interface; guest takes that IP/L2. | vNIC on a port group |
| **Multus** | Meta-CNI plugin that attaches additional networks to a Pod. | Extra port groups for a VM |
| **NetworkAttachmentDefinition (NAD)** | CRD describing one additional network (CNI config) for Multus. | Port group definition |
| **Secondary network** | Any non-default network attached through Multus. | Additional port group / VLAN |
| **Port group / vSwitch / vNIC** | See [vmware-source-model.md](vmware-source-model.md) and [networking-model.md](networking-model.md). | - |

## Migration

| Term | Definition |
|---|---|
| **Cold migration** | Power off the source, copy all disks, start the target. Consistent; downtime covers the whole copy. |
| **Warm migration** | Copy disks while the source runs (precopy), repeat with changed blocks, then short cutover. |
| **Precopy** | The warm-migration phase that transfers data while the source keeps running. |
| **CBT** | Changed Block Tracking. VMware feature that reports which disk blocks changed since a change ID/snapshot. Needs API access. |
| **Cutover** | Stopping the source and switching to the target; in warm migration, triggers the final delta copy. |
| **Rehost** | Move the VM as-is to a new platform (our KubeVirt path). |
| **Replatform / refactor** | Change how the application is packaged or built (our container path). See [modernization-model.md](modernization-model.md). |
| **MTV** | Red Hat Migration Toolkit for Virtualization; product for migrating VMs into OpenShift Virtualization. |
| **Forklift** | Upstream open-source project behind MTV. |
| **Provider / NetworkMap / StorageMap / Plan / Migration / Hook** | MTV CRs; see [migration-architecture.md](migration-architecture.md). |
| **`VirtualMachineMigration`** | Our conceptual CR (`migration.platform.example/v1alpha1`); not implemented. |
| **Inventory** | Normalized record of a source VM's identity, hardware, disks, NICs, guest and power state. |
