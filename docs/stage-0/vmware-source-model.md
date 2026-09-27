# The VMware source model

Stage 0 learning document for request section 8. It uses our real ESXi lab as the example. All lab values are OBSERVED read-only (see [evidence-index.md](evidence-index.md)). No VM exists on the host yet, so the per-VM examples are illustrative.

---

## 1. The objects, using our lab

```
esxi-8-lab.localdomain  (ESXi 8.0.3, build 24677879, free "vSphere 8 Hypervisor" license, standalone, no vCenter)
|
|- VMkernel: the hypervisor OS (CPU scheduler, memory, storage stack, networking)
|
|- Networking
|   vmnic0 (physical uplink as seen by ESXi; really a VMXNET3 NIC of the Workstation VM)
|     -> vSwitch0 (standard switch, MTU 1500)
|          |- port group "Management Network" (VLAN 0) -> vmk0 192.168.50.11/24 (VMkernel interface)
|          |- port group "VM Network"         (VLAN 0) -> future guest vNICs
|
|- Storage
|   migration-datastore (VMFS-6, 199.8 GB, 198.3 GB free, empty)
|     -> future: /vmfs/volumes/migration-datastore/legacy-source-vm/
|           legacy-source-vm.vmx          (VM configuration)
|           legacy-source-vm.vmdk         (disk descriptor)          } typical ESXi/VMFS layout;
|           legacy-source-vm-flat.vmdk    (flat data extent)         } to be observed, not assumed
|           legacy-source-vm.nvram, vmware.log, ...
|   OSDATA (system only, not for VMs)
|
|- VMs: none yet (vim-cmd vmsvc/getallvms is empty)
```

| Object | What it is | In our lab |
|---|---|---|
| **VM** | A set of files (config + disks) plus, when powered on, a running VMX process | None yet. `legacy-source-vm` is planned. |
| **VMX** | The `.vmx` text file: virtual hardware version, guest OS type, CPU, memory, firmware, devices, disk and NIC wiring. Also the name of the per-VM process. | Will live next to the disks on `migration-datastore`. |
| **VMDK** | The virtual disk. Its file layout depends on format and provisioning: on VMFS usually a descriptor + flat extent; on Workstation often one monolithic sparse file; plus delta disks if snapshots exist (see [cdi-storage-model.md](cdi-storage-model.md#vmdk-vmware)) | Future. Likely thin on VMFS. The Workstation disks that hold ESXi itself are `monolithicSparse`. |
| **Virtual NIC** | A device in the VM (VMXNET3 or E1000e) with a MAC address, connected to a port group | Future guest NIC on "VM Network". |
| **vSwitch** | A software L2 switch in VMkernel with physical uplinks | `vSwitch0`, uplink `vmnic0`. |
| **Port group** | A named set of ports on a vSwitch with a policy (VLAN, security, teaming). VMs connect to port groups, not to vSwitches directly. | "Management Network", "VM Network" (both VLAN 0). |
| **Datastore** | A storage container (VMFS, NFS, vSAN) that holds VM files | `migration-datastore`, VMFS-6. |
| **VMkernel** | The ESXi kernel. Also used for "VMkernel adapters" (`vmk0`), which are the host's own IP interfaces. | `vmk0` = 192.168.50.11 static. |

## 2. What a migration platform must discover from a VMware VM

The platform must answer three questions: **what is it** (so we can recreate it), **where is its data** (so we can copy it), and **what state is it in** (so we can do it safely).

How we can read this on a free standalone host (INFERRED, to validate):

- **SSH + `vim-cmd`** (works today): `vim-cmd vmsvc/getallvms`, `vim-cmd vmsvc/get.summary <vmid>`, `vim-cmd vmsvc/get.config <vmid>`, `vim-cmd vmsvc/power.getstate <vmid>`, `vim-cmd vmsvc/get.guest <vmid>`, `vim-cmd vmsvc/snapshot.get <vmid>`.
- **Read the `.vmx` file** over SSH (`cat`), and each VMDK descriptor, to learn the disk's actual layout, extents, provisioning and snapshot chain.
- **`esxcli`** for host-level network and storage facts.
- **vSphere API (pyVmomi / govc)**: Broadcom states that for the free edition, "usage of APIs to manage hosts is not supported, and may only provide read-only information" ([Broadcom KB 399823](https://knowledge.broadcom.com/external/article/399823)). Read-only discovery through the API may work, but it is unsupported, and write operations (snapshots, power, CBT) are expected to fail.

## 3. Example inventory model

A conceptual record for one source VM. Field names are illustrative. This would become `status.sourceInventory` in our CRD.

```yaml
sourceInventory:
  # --- VM identity ---
  identity:
    name: legacy-source-vm
    vmid: "1"                         # ESXi-local managed object ID (vim-cmd)
    biosUuid: "564d...."              # stable across renames
    instanceUuid: "5299...."
    vmxPath: "[migration-datastore] legacy-source-vm/legacy-source-vm.vmx"
    host: esxi-8-lab.localdomain
    hardwareVersion: vmx-21
    firmware: efi                     # bios | efi (decides KubeVirt firmware)
    secureBoot: false
  # --- CPU / memory ---
  cpu:
    sockets: 1
    coresPerSocket: 2
    vcpus: 2
  memoryMiB: 2048
  # --- guest OS ---
  guest:
    guestIdConfigured: ubuntu64Guest  # from .vmx guestOS
    guestFullNameReported: "Ubuntu Linux (64-bit)"   # from VMware Tools, if running
    toolsStatus: toolsOk
    hostname: legacy-source-vm
    ipAddresses: ["192.168.50.40"]    # illustrative
  # --- controllers ---
  controllers:
    - key: scsi0
      type: pvscsi                    # target: virtio-scsi or virtio-blk
    - key: sata0
      type: ahci
  # --- disks ---
  disks:
    - key: scsi0:0
      boot: true
      fileName: "[migration-datastore] legacy-source-vm/legacy-source-vm.vmdk"
      capacityBytes: 21474836480      # 20 GiB provisioned
      allocatedBytes: 3221225472      # ~3 GiB actually used (thin)
      provisioning: thin
      diskMode: persistent
      snapshotChain: []               # must be empty for virt-v2v -i vmx
  # --- NICs and networks ---
  nics:
    - key: ethernet0
      model: vmxnet3                  # target: virtio
      macAddress: "00:0c:29:aa:bb:cc"
      portGroup: "VM Network"
      vlan: 0
      connected: true
  networks:
    - portGroup: "VM Network"
      vswitch: vSwitch0
      vlan: 0
  # --- power state ---
  runtime:
    powerState: poweredOn             # poweredOn | poweredOff | suspended
    connectionState: connected
    hasSnapshots: false
    observedAt: "2026-10-01T10:00:00Z"
```

## 4. Metadata vs disk data vs runtime state

These three kinds of information behave very differently and must be handled differently by the platform.

| Kind | Examples | Size | How it changes | How we move it |
|---|---|---|---|---|
| **Source metadata** | Name, UUID, firmware, vCPU, memory, controllers, NIC models, MACs, port groups, disk sizes, guest OS type | Kilobytes | Rarely (only when someone edits the VM) | **Translated**, not copied. We read `.vmx` / API data and write a KubeVirt `VirtualMachine` spec. Some things have no equivalent (for example VMware-specific advanced settings). |
| **Source disk data** | The bytes inside the VMDK: OS, packages, nginx config, website files | Gigabytes | Constantly while the VM runs | **Copied and converted.** Cold: power off, then copy once. Warm (theory): copy, then copy changed blocks (CBT), then final copy after power off. |
| **Runtime state** | Power state, guest memory contents, open TCP connections, current IP lease, running processes, snapshot state, VMware Tools status | RAM-sized for memory; tiny for flags | Every millisecond | **Not migrated** in a cold migration. We only *observe* it (to decide if it is safe to proceed) and *control* it (power off). Live migration across hypervisors is out of scope. |

A good rule for the controller: **metadata is read at discovery and frozen into status; disk data is only read after the VM is confirmed powered off; runtime state is re-checked immediately before every destructive or irreversible step.**

## 5. Source-side constraints in our lab

| Constraint | Effect | Marker |
|---|---|---|
| Free "vSphere 8 Hypervisor" license | 8 vCPU per VM max; no vCenter; no vMotion/HA/DRS/VADP; API use unsupported and may be read-only | DOCUMENTED ([release notes](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/release-notes/esxi-update-and-patch-release-notes/vsphere-esxi-80u3e-release-notes.html), [KB 399823](https://knowledge.broadcom.com/external/article/399823)) + OBSERVED (`vsmp:8`) |
| No vCenter | vCenter-based tooling (MTV vSphere provider in vCenter mode, virt-v2v `vpx://`) does not apply | OBSERVED |
| SSH and ESXi Shell enabled with key auth | Discovery via `vim-cmd` and disk read via SSH/scp are possible | OBSERVED |
| Single flat network on vSwitch0 | Source VM and management share one L2 segment on VMnet8 | OBSERVED |
| ~198 GB free on `migration-datastore` | Plenty for a small source VM plus a temporary exported copy | OBSERVED |
| Nested 64-bit guest not yet tested | Must be proven when the source VM is created | INFERRED |
