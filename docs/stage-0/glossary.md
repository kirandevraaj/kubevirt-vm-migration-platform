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

## Migration source terms (Stage 1C)

Terms as observed on the migration source VM `legacy-source-vm` (see [Stage 1C record](../stage-1/stage-1c-migration-source.md)). The last column is INFERRED: nothing has been migrated yet.

| Term | Definition | Seen in the lab | After a VMware -> KubeVirt migration |
|---|---|---|---|
| **Migration source VM** | The VM whose workload is to be moved, kept in its genuine source-platform configuration so the migration has something real to solve. | `legacy-source-vm`, Vmid 2, 192.168.50.31 | Stays on ESXi; the target is a new KubeVirt VM |
| **Pre-migration baseline** | A recorded set of platform and guest facts (identifiers, config checksums, service state, HTTP response) that the migrated copy is later compared against. | [Stage 1C sections 6 to 10](../stage-1/stage-1c-migration-source.md#10-baseline-evidence) | Used as the acceptance reference |
| **Validation page** | A static page with fixed content and a known checksum, so "the app works" becomes a byte-exact test instead of "some page loads". | `index.html`, 267 bytes, marker `p15-stage1c-source-v1` | Same sha256 expected over HTTP |
| **Predictable interface name** | systemd/udev naming of NICs from firmware or bus position (`ens<slot>`, `enp<bus>s<slot>`, `enx<MAC>`) instead of `eth0`. | `ens192` (slot 192), altname `enp11s0` | Name changes with the new PCI position (typically `enp1s0`) |
| **netplan match** | How a netplan entry selects its NIC. A bare key (for example `ens192:`) matches by interface name; a `match:` block can match by `macaddress` or `driver`. Unmatched NICs get no configuration. | Bare key `ens192`, rendered as networkd `[Match] Name=ens192` | New NIC does not match: no IP until adapted |
| **Filesystem UUID** | Identifier stored inside the filesystem (ext4 superblock, vfat volume ID). Used by `fstab`, `root=UUID=` and GRUB `search --fs-uuid`. | root `db8b3bb3-...`, ESP `C340-CD01` | Survives (disk contents are copied) |
| **PARTUUID** | GPT partition entry GUID, independent of the filesystem inside it. | `408d91cb-...` (ESP), `b701fe8c-...` (root) | Survives |
| **PTUUID (disk GUID)** | GUID of the whole GPT partition table. | `ebeb0ebf-f2f7-4507-b842-6db77a2d14a1` | Survives |
| **SMBIOS system UUID** | Machine UUID reported by virtual firmware (`/sys/class/dmi/id/product_uuid`). VMware derives it from `uuid.bios`. | `ac4d4d56-...-17bc250f3d15` | Changes unless pinned (`firmware.uuid`) |
| **machine-id** | Per-installation ID in `/etc/machine-id`, used by systemd and journald. Lives on disk, not in firmware. | `d90f169b...8324` | Survives unless reset on purpose |
| **UEFI NVRAM boot entry** | `Boot####` variable in the firmware's variable store naming the loader to start. On VMware it lives in the `.nvram` file next to the `.vmx`. | Boot0005 "Ubuntu" -> `\EFI\ubuntu\shimx64.efi` | Lost; not part of the disk |
| **UEFI fallback boot path** | `\EFI\BOOT\BOOTX64.EFI` on the ESP, which firmware tries when no NVRAM entry works. On Ubuntu it is shim, which runs `fbx64.efi` to recreate entries. | Present; identical to `shimx64.efi` | What makes the migrated disk bootable |
| **open-vm-tools** | Open-source VMware Tools for Linux: guest info, graceful shutdown, time and quiescing. VMware-only. | 13.0.10, running, `guestToolsUnmanaged` | Useless on KVM; replaced by qemu-guest-agent |
| **cloud-init disabled marker** | The file `/etc/cloud/cloud-init.disabled`, which stops cloud-init from running at boot. The Ubuntu installer writes it after an install without a real datasource. | `status: disabled`, DataSourceNone | Keeps network config and SSH keys from being regenerated |

## VMware source artifact terms (Stage 1D)

Terms as observed in the datastore folder of `legacy-source-vm` (see [Stage 1D record](../stage-1/stage-1d-vmware-source-artifacts.md)). General VMDK terms (descriptor, extent, sparse) are in [Disks and conversion](#disks-and-conversion).

| Term | Definition | Seen in the lab |
|---|---|---|
| **.vmx** | Text file with the VM's configuration: CPU, memory, firmware, controllers, NICs, MAC, UUIDs, and which descriptor each virtual disk uses. Metadata only; it holds no disk data. | 2,458 bytes; `scsi0:0.fileName = "legacy-source-vm.vmdk"` |
| **.nvram** | Binary file holding the VM's firmware variable store (for UEFI: boot entries, Secure Boot mode). Separate from the virtual disk, so it does not travel with a disk copy. | 270,840 bytes, header `MRVN` |
| **.vmxf / .vmsd** | Extended configuration file and snapshot database. Both are VMware metadata. | 47-byte empty XML / 0 bytes (no snapshots) |
| **.vswp** | Swap file backing the VM's memory, created at power-on and deleted at power-off. Runtime only. | 4 GiB guest swap plus 82 MiB VMX swap |
| **createType** | Descriptor field naming the VMDK layout: `vmfs` (ESXi descriptor + flat extent), `monolithicSparse`, `twoGbMaxExtentSparse`, `streamOptimized` and others. | `createType="vmfs"` |
| **Flat extent** | The `-flat.vmdk` data file of a `vmfs` VMDK: raw disk sectors from byte 0, with no header. | `legacy-source-vm-flat.vmdk`, 42,949,672,960 bytes |
| **CID / parentCID** | Content ID of a VMDK; the child's `parentCID` links a delta disk to its parent's `CID`. `parentCID=ffffffff` means no parent (no snapshot chain). Not a reliable "was it written?" indicator: on this ESXi `vmfs` disk the descriptor `CID` stayed the same across a run that wrote to the disk (Stage 1E). | `CID=7475b330`, `parentCID=ffffffff` |
| **Thin (on VMFS)** | Unwritten regions of the flat file are VMFS holes that read as zeros. Logical size is the full capacity; allocated blocks are what `du` and `vmkfstools -D` (`nb`) show. A plain file copy writes the zeros. | 40 GiB logical, 3,487 x 1 MiB blocks allocated |
| **2gbsparse** | `vmkfstools -d 2gbsparse` output (`twoGbMaxExtentSparse`): descriptor plus sparse extents of at most 2 GB that store only written grains. A portable, compact export format. | Scratch test: 24 MiB written -> 25 MB extent, lossless round trip |
| **VMFS file lock** | On-disk lock that VMFS takes on open files. A running VM holds an exclusive lock (`mode 1`) on its disk, so even a read-only open from the shell fails. | Hot `dd` read: "Device or resource busy" |
| **Cold copy** | Copying a VM's disk after a clean guest shutdown, when the disk is closed and consistent. The only snapshot-free way to acquire a VMware disk. | Designed in Stage 1D; executed in [Stage 1E](../stage-1/stage-1e-cold-acquisition.md): 40 GiB in 276 s, sha256 identical on both ends |
| **Datastore file service (`/folder`)** | hostd HTTPS endpoint for datastore file download and upload: `/folder/<path>?dcPath=ha-datacenter&dsName=<datastore>`. Needs an authenticated session. | 401 without a session; 200 for the descriptor with one; 500 for the locked extent |

## Conversion lab terms (Stage 1F)

Terms as used on `conversion-host-01` (see [Stage 1F record](../stage-1/stage-1f-conversion-host.md)). The tools themselves (qemu-img, libguestfs, virt-v2v) are defined in [Disks and conversion](#disks-and-conversion).

| Term | Definition | Seen in the lab |
|---|---|---|
| **Conversion host** | A Linux machine that holds disk copies and runs offline disk tooling (qemu-img, libguestfs, virt-v2v). It has a single role, separate from the source VM and from learning or experiment VMs. | `conversion-host-01`, Vmid 3, 192.168.50.32 |
| **Golden artifact** | The verified original acquisition, kept unmodified as the reference. It is only ever read (hashed or copied), never inspected or converted in place. | `C:\VMs\legacy-source-vm\stage-1e\`, sha256 `72ca45c7...c9e7` |
| **Working copy** | A hash-verified copy of the golden artifact that tools are allowed to open. It can be locked, re-made or discarded without risk to the original. | `/srv/migration-lab/working/`, mode 0444 + `chattr +i` |
| **libguestfs appliance** | The small Linux VM (host kernel + minimal userspace, built by `supermin`) that libguestfs boots with the disk image attached. It reads partitions and filesystems with real kernel drivers, without booting the guest's own OS. | 403 MB cached in `/var/tmp/.guestfs-0`; ran as an L3 guest |
| **libguestfs backend** | How libguestfs launches the appliance. `direct` starts qemu itself; `libvirt` goes through libvirtd. | `direct` (default here; no libvirt daemon installed) |
| **TCG / `force_tcg`** | QEMU's Tiny Code Generator: software CPU emulation used when KVM is not available. `LIBGUESTFS_BACKEND_SETTINGS=force_tcg` makes libguestfs use it even when KVM is. | Appliance under TCG: 19.3 s, versus 34.3 s under KVM three hypervisors deep |
| **`guestfish --ro` / `-i`** | `--ro` opens every disk read-only. `-i` runs OS inspection and mounts the guest's filesystems as its own fstab describes. Without `-i`, only block devices and partitions are visible. | Guest root mounted with `ST_RDONLY` inside the appliance |
| **OS inspection (`virt-inspector`)** | libguestfs heuristics that find the root filesystem and read the OS type, distro, version, hostname and installed packages from files, without booting. | ubuntu 24.04, hostname `legacy-source-vm`, 500 packages |
| **`qemu-img map`** | Lists which ranges of a virtual disk hold data and which read as zeros (or are unallocated). It reflects the image as it is stored, so a copy's holes can differ from the original storage's. | 2,112 non-zero extents, 3,219 MiB |
| **Re-sparsify (`fallocate --dig-holes`)** | Deallocate all-zero blocks of a file in place, making it sparse again without changing its content. Used after a transfer method that writes every byte. | 40 GiB allocated -> 3.14 GiB; sha256 unchanged |
| **`fstrim` / UNMAP (thin VMDK)** | `fstrim` tells the storage which filesystem blocks are free. On a thin VMDK on VMFS-6 this lets ESXi reclaim the space. | 46.7 GiB trimmed; the conversion host's disk shrank to 7.5 GiB allocated |
| **Immutable flag (`chattr +i`)** | ext4 file attribute that blocks writes, renames and deletion, even by root, until it is removed. | Append as root: "Operation not permitted" |
| **virt-v2v input / output mode** | `-i` selects where the source guest comes from (`disk`, `vmx`, `ova`, `libvirt`, `libvirtxml`), and `-o` selects where the converted guest goes (`local`, `qemu`, `libvirt`, `kubevirt`, `openstack`, ...). | virt-v2v 2.4.0; `-o kubevirt` is marked experimental |
| **nbdkit / NBD** | A pluggable Network Block Device server. virt-v2v uses it internally to expose source disks (local files, SSH, VDDK) to qemu and libguestfs. | nbdkit 1.36.3, installed as a virt-v2v dependency |

## Conversion and boot validation terms (Stage 1G)

Terms as observed in the Stage 1G experiments (see [Stage 1G record](../stage-1/stage-1g-controlled-conversion.md)).

| Term | Definition | Seen in the lab |
|---|---|---|
| **Container conversion** | Rewriting a disk image into another format (VMDK to qcow2 or raw) without changing any guest-visible byte. | `qemu-img convert` in 5 s; `qemu-img compare`: "Images are identical." |
| **Guest-aware conversion** | Converting the container and also changing the guest OS so it runs on the target hypervisor (drivers, initramfs, agents, metadata). | virt-v2v purged open-vm-tools, rebuilt the initramfs, added a first-boot job; netplan untouched |
| **`qemu-img compare` (strict vs default)** | Default mode compares guest-visible content, treating unallocated and zero ranges as equal. `-s` (strict) also requires the same allocation status, so a sparse copy "differs" even with identical content. | Default: identical; `-s`: "Offset 4096 block status mismatch!" |
| **qcow2 overlay (backing file)** | A qcow2 file that stores only changed clusters and reads everything else from a read-only backing image. Used to boot a disk without ever writing to it. | One overlay per boot, deleted afterwards; the conversion outputs' hashes never changed |
| **OVMF CODE / VARS** | QEMU's UEFI firmware is split into a read-only code image and a writable variable store (NVRAM). Each VM needs its own VARS copy. | `OVMF_CODE_4M.fd` (no Secure Boot) + a fresh copy of `OVMF_VARS_4M.fd` per boot |
| **UEFI fallback (removable-media) boot path** | With no boot entries, UEFI firmware loads `\EFI\BOOT\BOOTX64.EFI` from the ESP. On Ubuntu this is shim, whose fallback helper can recreate the OS boot entry. | `Boot0001 "UEFI Misc Device"` booted the disk; a `Boot0003 "Ubuntu"` entry appeared afterwards |
| **Predictable interface name** | systemd/udev names a NIC after its hardware location, for example `ens192` (VMware slot) or `enp0s3` (PCI bus 0, slot 3). A different virtual hardware layout gives a different name. | VMXNET3 `ens192` on ESXi became virtio-net `enp0s3` under QEMU q35 |
| **netplan `match: driver`** | Selects the interface by kernel driver instead of by name, so the configuration survives renaming. The netplan ID becomes a label (for example `primary`). | `driver: virtio_net` produced `[Match] Driver=virtio_net`; the link became routable |
| **virt-v2v first boot (`guestfs-firstboot`)** | A oneshot service virt-v2v installs to run scripts on the converted guest's first boot, for example installing qemu-guest-agent. | Stalled in `apt-get update` on the isolated network; the system stayed `starting` |
| **User-mode networking (slirp), `restrict=on`, `hostfwd`** | QEMU's built-in NAT network (10.0.2.0/24, gateway .2, DNS .3). `restrict=on` isolates the guest from everything outside; `hostfwd` still forwards chosen host ports into the guest. | Guest :80 reached through 127.0.0.1:18080 on the conversion host; DNS not available |
| **`virt-diff`** | libguestfs tool that lists file-level differences between two disk images, with inline diffs for changed text files, without booting either. | 396 lines input vs virt-v2v output; exactly 1 file for the netplan remediation |

## KubeVirt target architecture terms (Stage 1H)

Terms used in the Stage 1H design (see [Stage 1H record](../stage-1/stage-1h-kubevirt-target-feasibility.md)). Nothing here was built; the right-hand column is the design, not an observation.

| Term | Definition | In the Stage 1H design |
|---|---|---|
| **EC2 nested virtualization** | An EC2 CPU option (`NestedVirtualization=enabled`) on selected non-metal instance families that exposes VT-x to the instance, so the guest OS gets a working `/dev/kvm`. Bare-metal instances have VT-x without it. | `m8i.xlarge` with the option enabled; `m7i.metal-24xl` only as a fallback after a new decision |
| **Kernel/userspace alignment** | KubeVirt ships QEMU and libvirt inside the virt-launcher image, built on one distribution, and recommends a host kernel from the same family, because QEMU relies on kernel features (KVM, vhost, security modules). | virt-launcher is CentOS Stream 9 based, so the node runs CentOS Stream 9 |
| **kubevirtci** | KubeVirt's own CI cluster tooling. Its provider definitions show which Kubernetes, runtime and OS versions KubeVirt is actually tested on. | The chosen tuple mirrors its `k8s-1.36` provider (CentOS Stream 9, CRI-O 1.36) |
| **Single-node kubeadm cluster** | A cluster whose one node is both control plane and worker, made schedulable by removing the control-plane `NoSchedule` taint. | One EC2 instance, no HA; disposable |
| **`device_ownership_from_security_context`** | CRI-O (and containerd) setting that gives devices mounted into a container the container's user and group instead of root, which KubeVirt needs for non-root virt-launcher access to block PVCs. | `true` in the CRI-O configuration |
| **passt binding** | KubeVirt network binding using the userspace passt process to translate between the guest's L2 and the pod's sockets; supports live migration and needs a Beta feature gate in v1.9. | Deferred; masquerade chosen |
| **NAT location** | Each place an address is rewritten on the path to or from the guest. | Three: masquerade in the virt-launcher pod, flannel egress masquerade on the node, and the internet gateway's public IPv4 mapping |
| **IP continuity vs service continuity** | IP continuity keeps the guest's address; service continuity keeps the service reachable and correct at some (possibly new) address or name. They are independent. | No IP continuity (.31 stays on VMnet8); service continuity proven by HTTP 200 and the page sha256 through NodePort 30080 |
| **NodePort Service** | A Service exposed on a fixed port on every node's address, forwarded to the selected pods. | NodePort 30080 to the virt-launcher pod's port 80, reachable only from the operator's /32 |
| **Upload DataVolume** | A DataVolume with source `upload`: CDI creates the PVC and an upload server, and the client (`virtctl image-upload`) streams the image through `cdi-uploadproxy`. | qcow2 streamed from the node through a `kubectl port-forward`, converted to raw on a Block PVC |
| **`--force-bind`** | `virtctl image-upload` flag that makes CDI bind a WaitForFirstConsumer PVC before any VM consumes it, so the upload can start. | Required with the gp3 StorageClass |
| **Standalone DataVolume** | A DataVolume created on its own and referenced by a VM, instead of a `dataVolumeTemplate` owned by the VM; deleting the VM does not delete the disk. | The migrated disk survives VM deletion and re-creation |
| **IMDSv2 hop limit** | Number of network hops an EC2 instance metadata response may travel. 1 blocks pods on the pod network from reaching it; 2 allows it. | 2, so the EBS CSI controller pod can use the instance profile |

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
