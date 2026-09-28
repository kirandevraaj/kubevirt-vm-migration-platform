# Stage 1G: controlled VMDK conversion and KVM boot validation

| Field | Value |
|---|---|
| Project | Project 1.5: VM-to-Kubernetes Migration Platform |
| Stage | 1G |
| Date | 2026-09-28 (all times UTC; work 03:16 to 03:59) |
| Approval | Explicitly approved by the user: record the conversion-host decision as an ADR, run controlled conversion experiments with qemu-img and virt-v2v on disposable working data, boot the results in one temporary QEMU/KVM test VM at a time, and apply minimal remediation only to a disposable converted copy. Not approved: modifying or shutting down `legacy-source-vm`, modifying the golden disk, in-place conversion, Kubernetes/KubeVirt/CDI, AWS, a real migration, `virt-v2v -o kubevirt`, using `kvm-learning-01`, Stage 1H. |
| Result | **Success (G1 to G10 PASS).** Both conversion paths produced disks that boot under QEMU/KVM with UEFI (OVMF, Secure Boot off) on virtio storage. Neither path produced a working network: netplan still matches the VMware name `ens192` and the virtio NIC is `enp0s3`. qemu-img changed only the container (images compare identical). virt-v2v removed open-vm-tools, rebuilt the initramfs and added a first-boot service, but left netplan, GRUB configuration and identity alone. One netplan change on a second disposable copy gave a working network, and nginx returned HTTP 200 with the source page hash. The golden artifact and the source VM are unchanged. |
| Related | [ADR 006](../adr/006-dedicated-conversion-host.md) (conversion host), [Stage 1F record](stage-1f-conversion-host.md) (host, toolchain, working copy), [Stage 1E record](stage-1e-cold-acquisition.md) (golden artifact), [Stage 1C record](stage-1c-migration-source.md) (source baseline), [Stage 1 index](README.md) |

Labels: **OBSERVED** = seen in this lab by a command we ran. **INFERRED** = reasoned from observations or documentation, not directly tested. **NOT TESTED** = deliberately not done.

Diagram: [stage-1g-conversion-and-boot.svg](../diagrams/stage-1g-conversion-and-boot.svg).

## 1. Objective

Produce experimental evidence, not assumptions, for the ten Stage 1G questions:

| # | Question | Answer (OBSERVED unless marked) |
|---|---|---|
| 1 | What does container-only conversion do? | `qemu-img convert -f vmdk -O qcow2` rewrote the container in 5 s. `qemu-img compare` reports the guest-visible bytes identical. Nothing inside the guest changed. |
| 2 | What does virt-v2v change? | It purged open-vm-tools, added `bochs` to the initramfs module list and rebuilt the initramfs (the old one kept as `.pre-v2v`), added `alias scsi_hostadapter virtio_blk`, and installed a `guestfs-firstboot` service that tries to install qemu-guest-agent. It did not change netplan, fstab, grub.cfg, the ESP, machine-id, SSH host keys or nginx. |
| 3 | Does the guest boot under QEMU/KVM? | Yes, all three disks: UEFI through the ESP fallback loader, `Hypervisor detected: KVM`, root prompt on serial in 56 to 67 s. |
| 4 | Does storage become VirtIO? | Yes. The disk is `vda` on virtio-blk (built into the kernel), and root and ESP mount by UUID with no change. |
| 5 | What happens to the VMware network config? | Nothing, in either path. netplan still generates `[Match] Name=ens192`, which matches no device. |
| 6 | Does the guest get networking with a VirtIO NIC? | Not without remediation: `enp0s3` is DOWN and unmanaged. After matching by driver on a second copy: routable, 10.0.2.15/24, default route, HTTP 200 from outside the guest. |
| 7 | What happens to open-vm-tools? | qemu-img path: still enabled, but systemd skips it (`ConditionVirtualization=vmware`). virt-v2v path: purged (package state `un`, unit and binaries gone). |
| 8 | Does nginx stay intact? | Yes, in every boot: config and page hashes identical, service active, local HTTP 200 with page sha256 `b9826e18...0046`. |
| 9 | Which changes are automatic, which need remediation? | Automatic: sections 16 and 19. Manual: the netplan interface match (section 20). |
| 10 | What will KubeVirt/CDI need? | Section 22: EFI with Secure Boot off, a virtio disk bus, a network remediation decision, a guest-agent decision, and an explicit target-format decision. |

## 2. Explicit authorization

Authorized by the user for this stage: record the conversion-host decision as an ADR; create disposable working copies and outputs; run controlled VMDK conversion experiments; use qemu-img on working data; use virt-v2v on the working artifact; create one temporary QEMU/KVM validation VM; boot the converted guest; inspect its hardware, filesystem, boot and networking behaviour; apply minimal guest remediation **only** to disposable converted copies; validate nginx on the converted guest.

Not authorized, and not done: modifying or shutting down `legacy-source-vm`; modifying the Stage 1E golden disk; converting the golden disk in place; installing Kubernetes, KubeVirt or CDI; creating AWS infrastructure; performing a VMware -> KubeVirt migration; using `kvm-learning-01` as a conversion host; starting Stage 1H.

## 3. Scope

| Done | Not done (as required) |
|---|---|
| ADR 006 for the conversion host | No change to `legacy-source-vm` (no shutdown, snapshot, config or guest change) |
| Golden artifact re-verified; Windows read-only attribute set on descriptor and flat extent | Golden artifact never opened by any tool except `Get-FileHash` |
| OVMF installed on `conversion-host-01` (one package) | No other package installed or upgraded; virt-v2v stayed at 2.4.0 |
| Path A: `qemu-img convert` of the working copy to a new qcow2 | No in-place conversion, `rebase`, `amend`, `resize`, `commit` or `check -r` |
| Path B: `virt-v2v -i disk ... -o local` to a new directory | No connection to ESXi or vCenter; no `-i vmx`, no `-o kubevirt`; not pointed at the running source |
| Three QEMU/KVM boots (Path A, Path B unmodified, Path B remediated), one at a time, directly with QEMU (no libvirt) | 192.168.50.31 never assigned to a test guest; test guests only on an isolated user-mode network |
| One netplan remediation on a second, full copy of the virt-v2v output | No Kubernetes, KubeVirt, CDI, AWS, controller or migration work; `kvm-learning-01` stayed powered off |

### Resource impact

| Point in time (UTC) | Windows free RAM | ESXi memory used | Datastore free (bytes) | conversion-host-01 memory available |
|---|---:|---:|---:|---:|
| Before experiments (03:16 to 03:20) | 6.2 GiB | 11,299 MB | 176,174,399,488 | 7,386 MiB of 7,940 |
| During test-guest boots (03:27 to 03:56) | 5.7 to 5.9 GiB | - | - | 6,459 MiB minimum (QEMU RSS 634 to 988 MB) |
| Final (03:58) | 5.8 GiB | 11,301 MB | 166,960,562,176 | 7,402 MiB |

- ESXi memory did not change measurably. Test guests run inside the conversion host's already-allocated 8 GB.
- Datastore free space fell by 9,213,837,312 bytes (8.58 GiB). That is the kept artifacts (8.7 GB in the guest filesystem) after `fstrim` returned 961 MiB of deleted overlays and temporary files.
- The 2 GiB Windows stop threshold was never approached. Only one QEMU guest ran at a time, and none runs now.

## 4. Non-goals

- Choosing the KubeVirt target disk format, or proving a CDI import.
- Performance measurement. Test guests are L3 (Windows -> ESXi -> conversion host -> guest).
- A production-quality network design. The remediation shows what is needed; it does not decide the cutover policy.
- Testing Secure Boot on, BIOS boot, `-i vmx`, `-o kubevirt` or virt-v2v's handling of a networked first boot.
- Filesystem checking (`fsck`) of any image.

## 5. ADR reference

[ADR 006](../adr/006-dedicated-conversion-host.md) records that `conversion-host-01` is the dedicated lab host for disk inspection, conversion and QEMU/KVM boot validation, separate from `legacy-source-vm` and `kvm-learning-01`. It fixes the operating rules used here: golden read-only, working copy as the only tool input, new output paths, disposable overlays, one test guest at a time, no connection from conversion tools to ESXi. It explicitly does not decide the KubeVirt target format, where production conversion runs, or the cutover network policy.

## 6. Toolchain versions

OBSERVED on `conversion-host-01` (Ubuntu 24.04.5, kernel 6.8.0-142-generic) at 03:19 (G3):

| Component | Version |
|---|---|
| qemu-img, qemu-system-x86_64 | 8.2.2 (packages `qemu-utils`, `qemu-system-x86` 1:8.2.2+ds-0ubuntu1.18) |
| libguestfs, guestfish, virt-inspector | 1.52.0 (`libguestfs0t64` 1:1.52.0-5ubuntu3, `guestfs-tools` 1.52.0-2ubuntu5) |
| virt-v2v | 2.4.0 (`virt-v2v` 2.4.0-2build4) |
| nbdkit / supermin | 1.36.3 / 5.2.2 |
| ovmf | 2024.02-2ubuntu0.9 (installed in this stage, section 7) |
| ipxe-qemu / seabios | 1.21.1+git-20220113.fbbdc3926-0ubuntu2 / 1.16.3-2 (already present) |
| python3 | 3.12.3 (serial and monitor test harness) |

KVM: `/dev/kvm` present (`root:kvm`), `kvm_intel` loaded with `nested=Y`, `kvm-ok`: "KVM acceleration can be used". virt-v2v 2.4.0 needed no upgrade: it handled the guest completely.

## 7. UEFI/OVMF setup

Before G3, the host had no usable UEFI firmware: `ovmf` was not installed and neither `/usr/share/OVMF` nor `/usr/share/qemu/firmware/` existed. The source VM boots UEFI with Secure Boot off (Stage 1C), so a BIOS boot would not be an equivalent test and was not used.

| Step (OBSERVED) | Result |
|---|---|
| `apt-get -s install --no-install-recommends ovmf` | One package: `ovmf` 2024.02-2ubuntu0.9, no dependencies |
| Install | Exit 0, no errors or warnings |
| Firmware used | `/usr/share/OVMF/OVMF_CODE_4M.fd` (sha256 `949bfa53...a446`), read-only pflash |
| Variable-store template | `/usr/share/OVMF/OVMF_VARS_4M.fd` (sha256 `5d2ac383...5d1e`), copied fresh for each boot, deleted afterwards |
| Descriptor that matches | `/usr/share/qemu/firmware/60-edk2-x86_64.json`: "UEFI firmware for x86_64, without Secure Boot, optional SMM, empty varstore" |
| Also installed, not used | `OVMF_CODE_4M.secboot.fd` (with `.ms` and `.snakeoil` links), `OVMF_VARS_4M.ms.fd`, `OVMF_VARS_4M.snakeoil.fd`; descriptors `40-...-secure-enrolled`, `50-...-secure`, `60-...-amdsev` |

**Boot path, OBSERVED identically in all three boots:**

1. With an empty varstore, OVMF auto-created `Boot0001 "UEFI Misc Device" PciRoot(0x0)/Pci(0x2,0x0)` (the virtio-blk disk). It loaded the removable-media fallback `\EFI\BOOT\BOOTX64.EFI`, which is shim (same sha256 as `EFI/ubuntu/shimx64.efi`).
2. A `Boot0003 "Ubuntu" HD(1,GPT,408d91cb-...)/File(\EFI\ubuntu\shimx64.efi)` entry existed after boot and led `BootOrder: 0003,0001,0000,0002`, while `BootCurrent` was `0001`. That shim's fallback (`fbx64.efi` with `BOOTX64.CSV`) created it is INFERRED. No reset was seen in the serial log.
3. GRUB loaded the kernel. The kernel logged `efi: EFI v2.7 by Ubuntu distribution of EDK II`, `secureboot: Secure boot disabled`, `DMI: QEMU Standard PC (Q35 + ICH9, 2009), BIOS 2024.02-2ubuntu0.9`. `/sys/firmware/efi` was present.

So the VMware `.nvram` is not needed: a fresh variable store boots this disk through the fallback loader.

## 8. Golden artifact protection

The golden artifact is `C:\VMs\legacy-source-vm\stage-1e\` on the Windows host, outside Git.

| File | sha256 | Size (bytes) | LastWriteTimeUtc | Attributes at G2 start | After G2 | At G10 |
|---|---|---:|---|---|---|---|
| `legacy-source-vm-flat.vmdk` | `72ca45c7bcb2fc617e53f6286832d6d53d74e9801a18fb295c5fb88de1f9c9e7` | 42,949,672,960 | 2026-09-27T14:20:09.0410349Z | Archive | ReadOnly, Archive | same hash, size, time; ReadOnly, Archive |
| `legacy-source-vm.vmdk` | `5b407e06ec29cac925a4504978ca3cef5d231398536ab476bcd03acbdc5de9ff` | 541 | 2026-09-27T14:15:32.6800994Z | Archive | ReadOnly, Archive | same hash, size, time; ReadOnly, Archive |

- The hashes matched the Stage 1E record before anything else was done. A mismatch would have stopped the stage.
- Setting `IsReadOnly` changed only the attribute: hash, size and `LastWriteTimeUtc` stayed identical. A test open for writing was then refused ("Access ... is denied").
- No tool other than `Get-FileHash` touched these files in this stage. The source VM was never pointed at any converted image.

### Source VM safety

| Check | G1 (03:16) | G10 (03:58) |
|---|---|---|
| Vmid 2 power state / snapshots | Powered on / 0 | Powered on / 0 |
| Guest IP and tools (ESXi) | 192.168.50.31, tools running | 192.168.50.31, tools running |
| HTTP from Windows | 200, 267 bytes | 200, 267 bytes |
| Page sha256 (Windows and ESXi) | `b9826e18...0046` | `b9826e18...0046` |
| Vmid 1 `kvm-learning-01` | Powered off | Powered off |

The source was only probed over HTTP and through ESXi status queries.

## 9. Working-copy model

```text
GOLDEN (Windows, read-only attribute)         never opened by tools
  |  Stage 1F scp (earlier, hash-verified)
PROTECTED INPUT  /srv/migration-lab/working/  0444 + chattr +i, sha256 checked before and after every step
  |-- qemu-img convert  -> stage-1g/qemu-img/legacy-source-vm.qcow2            0444, hashed
  |-- virt-v2v -o local -> stage-1g/virt-v2v/local-out/legacy-source-vm-sda    0444, hashed
                              + legacy-source-vm.xml
                           cp --sparse=always -> stage-1g/virt-v2v/remediated/legacy-source-vm-netfix.qcow2
                              (netplan changed, then 0444, hashed)
  each boot: stage-1g/boot-tests/<name>/overlay.qcow2 (backing = an output) + OVMF_VARS.fd copy  -> deleted
```

Directories used: `/srv/migration-lab/stage-1g/{source-verification,qemu-img,virt-v2v,boot-tests,evidence}`. Boot overlays are qcow2 files whose backing file is a read-only output. QEMU opens the backing file read-only, so the conversion outputs never change while a guest runs. Each output was re-hashed after every boot and at the end.

| Kept artifact (outside Git) | Size (bytes) | sha256 |
|---|---:|---|
| `qemu-img/legacy-source-vm.qcow2` | 3,444,572,160 | `08c62ac514d28f4b29ad22df342d5b9b5a701fdb3a2081f8a484dfc50fa45447` |
| `virt-v2v/local-out/legacy-source-vm-sda` (qcow2) | 2,926,706,688 | `94bc1cd6beb730831dd087c6e36dc6ee7d21881f43455ff44d059e55fe1d91c6` |
| `virt-v2v/local-out/legacy-source-vm.xml` | 1,795 | `a22033cea792d8d08d0bbfab2c6b5b62dd15a0155b8b2ea76e7d5665482cca84` |
| `virt-v2v/remediated/legacy-source-vm-netfix.qcow2` | 2,926,837,760 | `5326b13091bbc0302628b9dbf9f778ce5ff1371955bd93c8a99527a94e39d3d6` |
| `virt-v2v/remediated/50-cloud-init.yaml.remediated` | 463 | `90e0ed3c1d21846499149f042213739312bdee6387c8d2472cf377c94573181d` |

**Test-harness instrumentation (overlays only, not remediation).** To get a shell on guests that have no network, each boot overlay received the same two additions through guestfish before boot: `serial-getty@ttyS0.service` enabled, and a drop-in giving it root autologin. These existed only in the overlays, which were deleted, and never in a conversion output or in the remediated copy. The file-level diffs in sections 14 and 17 were taken on the outputs, not on the overlays. No guest password was copied to the conversion host.

**Cleanup (G10, recorded in `evidence/cleanup-deleted.txt`):** three `overlay.qcow2` files (12,386,304; 146,407,424; 31,129,600 bytes), three `OVMF_VARS.fd` copies (540,672 bytes each), QEMU sockets and pid files, and temporary script and evidence copies in `/tmp`. Kept: the five artifacts above, the Stage 1F working copy, all text evidence and the harness scripts. `fstrim -v /` then trimmed 961.1 MiB. No QEMU process is running.

## 10. qemu-img conversion experiment

| Item | OBSERVED (G5, 03:24) |
|---|---|
| Input | `/srv/migration-lab/working/legacy-source-vm.vmdk` (vmdk, create type vmfs, 40 GiB virtual, 3.14 GiB on disk); sha256 check OK before |
| `qemu-img measure -f vmdk -O qcow2` | required 3,448,897,536 bytes; fully allocated 42,956,488,704 |
| Command | `qemu-img convert -f vmdk -O qcow2 /srv/migration-lab/working/legacy-source-vm.vmdk /srv/migration-lab/stage-1g/qemu-img/legacy-source-vm.qcow2` |
| Duration | 5 s, exit 0 |
| Output format | qcow2, compat 1.1, cluster 65,536, compression type zlib available but **0.00% compressed clusters** (no `-c`), lazy refcounts off |
| Size | virtual 42,949,672,960 bytes; file 3,444,572,160 bytes (3.21 GiB); 52,522 of 655,360 clusters allocated (8.01%) |
| Sparsity (`qemu-img map`) | 3,442,081,792 bytes data; 39,507,591,168 bytes read as zero and not stored |
| `qemu-img check` | "No errors were found on the image." |
| `qemu-img compare -f vmdk -F qcow2` (default) | **"Images are identical."** (5 s) |
| `qemu-img compare -s` (strict) | "Offset 4096 block status mismatch!": strict mode also compares allocation. Zero ranges are unallocated in the qcow2 but present in the flat extent. Not a content difference. |
| Input after | sha256 check OK, `chattr +i` still set |

Conclusion: the container changed (VMDK descriptor + flat extent -> one sparse qcow2 file), and every guest-visible byte stayed the same. qcow2 was used as a temporary experimental format only. It is not the KubeVirt target decision.

## 11. qemu-img boot result

The boot was run directly with QEMU, without libvirt (G6, 03:27 to 03:31):

```text
qemu-system-x86_64 -name path-a,process=qemu-path-a -machine q35,accel=kvm -cpu host -smp 2 -m 2048 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=<boot dir>/OVMF_VARS.fd \
  -drive file=<boot dir>/overlay.qcow2,format=qcow2,if=none,id=disk0 -device virtio-blk-pci,drive=disk0,bootindex=1 \
  -netdev user,id=net0,restrict=on,hostfwd=tcp:127.0.0.1:18080-:80,hostfwd=tcp:127.0.0.1:12222-:22 \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:1a:00:01 \
  -chardev socket,id=ser0,path=<boot dir>/serial.sock,server=on,wait=off,logfile=<boot dir>/serial.log -serial chardev:ser0 \
  -monitor unix:<boot dir>/monitor.sock,server=on,wait=off -display none -daemonize -pidfile <boot dir>/qemu.pid
```

The other two boots used the same command, differing only in name, overlay and MAC (`52:54:00:1b:00:01`, `52:54:00:1c:00:01`).

| Item | Path A result (OBSERVED) |
|---|---|
| Boot | Success: root shell on serial 67 s after launch; `systemd-analyze`: 20.6 s kernel + 10.5 s userspace = 31.1 s; `is-system-running`: running, 0 failed units |
| Firmware | UEFI (OVMF 2024.02), Secure Boot disabled, fallback boot path (section 7) |
| CPU / memory | 2 vCPU, Intel Core i7-14650HX (host model passed through), 1,961 MiB visible |
| Kernel | 6.8.0-142-generic, `root=UUID=db8b3bb3-e776-42e8-902e-89124606b2f6 ro` (unchanged command line) |
| Block device | `vda` (virtio-blk `1af4:1001`); `vda1` vfat `C340-CD01` on `/boot/efi`, `vda2` ext4 `db8b3bb3-...` on `/` |
| NIC | `enp0s3` (virtio-net `1af4:1000`, driver `virtio_net`), renamed from `eth0` at 16.8 s |
| Network | None: link DOWN, unmanaged, no address, no route (section 13) |
| nginx | enabled, active, listening on :80 and [::]:80; guest-local curl HTTP 200, 267 bytes, sha256 `b9826e18...0046` |
| Host-side HTTP / SSH via port forward | No answer (the guest had no address) |
| Shutdown | ACPI `system_powerdown` via the monitor; QEMU exited, none left running |

### KVM validation for each guest

| Evidence | Path A | Path B unmodified | Path B remediated |
|---|---|---|---|
| QEMU process fds | `/dev/kvm`, `kvm-vm`, `kvm-vcpu:0`, `kvm-vcpu:1` | same | same |
| HMP `info kvm` | kvm support: enabled | enabled | enabled |
| Guest `systemd-detect-virt` | kvm | kvm | kvm |
| Guest dmesg | "Hypervisor detected: KVM", kvm-clock | same | same |
| Virtio block / net PCI devices | `1af4:1001` / `1af4:1000` | same | same |

All three guests ran KVM-accelerated. No software-emulation (TCG) boot was run in this stage, so none is compared.

## 12. VirtIO storage findings

- The disk appears as `/dev/vda` instead of the VMware `/dev/sda` (PVSCSI). Nothing in the guest depends on the name: fstab mounts `/` and `/boot/efi` by UUID, GRUB finds root by UUID, and swap is the file `/swap.img` (OBSERVED in all three boots).
- `virtio_blk`, `virtio_net`, `virtio_scsi` and `virtio_pci` are built into the kernel (`modules.builtin`). Path A, with an unchanged initramfs, booted from virtio-blk, so no initramfs rebuild was needed for storage on this guest.
- `vmw_pvscsi` and `vmxnet3` were not loaded in any boot. Both are still present as modules, and still in the initramfs after virt-v2v (`lsinitramfs`).
- q35 adds an AHCI controller and an empty `sr0`, which are unused. Filesystem and partition UUIDs are unchanged in all images.

## 13. VirtIO network findings

OBSERVED identically in Path A and Path B unmodified:

- The only NIC is `enp0s3` (virtio_net, PCI `00:03.0`). The kernel logged `virtio_net virtio1 enp0s3: renamed from eth0`. `ens192` does not exist.
- netplan (`/etc/netplan/50-cloud-init.yaml`, unchanged) generated `/run/systemd/network/10-netplan-ens192.network` with `[Match] Name=ens192`, static 192.168.50.31/24, gateway and DNS 192.168.50.2.
- `networkctl`: `enp0s3 ether off unmanaged`. There was no IPv4 address, no route, no DHCP attempt (`dhcp4: false`, and no configuration matched anyway). `ping 10.0.2.2`: "Network is unreachable".
- `systemd-networkd-wait-online` was skipped by its netplan condition, so the boot did not stall. The guest looked healthy (`running`, nginx active) while it was unreachable.

**Confirmed migration risk:** the Stage 1C/1F prediction holds. A VMware-to-KVM move leaves this guest without network, because the configuration is keyed to the VMware interface name. The new name reflects the PCI slot the NIC gets (`enp0s3` here). A different virtual hardware layout, such as KubeVirt's, may produce a different name (INFERRED).

## 14. virt-v2v conversion experiment

**Documentation read first (G8, local, version-exact):** `virt-v2v --help`, `--machine-readable`, man pages `virt-v2v(1)`, `virt-v2v-input-vmware(1)`, `virt-v2v-output-local(1)` and `virt-v2v-support(1)`. From them:

- `-i disk` reads "a virtual machine disk image with no metadata" (single disk only). `-if` gives its format.
- `-o local -os DIR` writes `NAME-sda` plus a libvirt `NAME.xml`.
- `-of`: "If not specified, then the input format is used" (here: vmdk).
- Supported inputs: `disk`, `libvirt`, `libvirtxml`, `ova`, `vmx`. Outputs include `local`, `qemu`, `libvirt`, `kubevirt`, `openstack`. Ubuntu 10.04 and later are listed as supported, and UEFI guests are supported on libvirt/qemu with OVMF.
- `-i list` and `-o list` are not accepted by 2.4.0 ("unknown -i option: list"). The machine-readable feature list was used instead. In-place conversion is not an option of this command.

**Choices:** `-i disk -if vmdk` on the protected working copy, because it is local, needs no `.vmx` and no connection. `-o local` gives local files. `-of qcow2` was set explicitly: the default would have re-emitted VMDK, and qcow2 matches Path A's container, so differences between the paths are guest-level only.

| Item | OBSERVED (03:33 to 03:35) |
|---|---|
| Command | `virt-v2v -v -x -i disk -if vmdk /srv/migration-lab/working/legacy-source-vm.vmdk -o local -os /srv/migration-lab/stage-1g/virt-v2v/local-out -of qcow2` (as root, `LIBGUESTFS_BACKEND=direct`, debug log 1,337,026 bytes) |
| Before | virt-v2v 2.4.0; input vmdk 40 GiB; sha256 check OK; `chattr +i` set |
| Duration | 136 s, exit 0 |
| Stages | 0.0 set up source; 1.0 open; 42.4 inspect; 49.3 free-space check; 49.3 "Converting Ubuntu 24.04.5 LTS to run on KVM"; 121.2 map filesystem data; 125.9 close overlay; 127.0 assign buses, BIOS/UEFI check; 128.1 copy disk 1/1; 136.3 metadata, finish |
| Warnings | One: "virt-v2v: warning: could not determine a way to update the configuration of Grub2" (it looked for `grub2-mkconfig` and `grub-mkconfig` and found neither; bootloader detected at `/boot/efi/EFI/ubuntu/grub.cfg`) |
| Produced files | `legacy-source-vm-sda`: qcow2, 40 GiB virtual, 2,926,706,688 bytes (2.73 GiB), 44,573 clusters (6.80%), `check` clean. `legacy-source-vm.xml`: 1,795 bytes. |
| Input after | sha256 check OK, `chattr +i` still set: virt-v2v read the input without modifying it |
| `qemu-img compare` vs input | "Content mismatch at offset 1128268800!" (expected: the guest was changed) |

The output is smaller than Path A (2.73 vs 3.21 GiB) because virt-v2v maps filesystem data and skips unused blocks ("Mapping filesystem data to avoid copying unused and blank areas").

**Generated libvirt XML (summary):** `domain type='kvm'`, libosinfo `ubuntu/24.04`, **2 GiB memory, 1 vCPU**, `cpu mode='host-model'`, machine `q35`, `loader readonly='yes' type='pflash'` `/usr/share/OVMF/OVMF_CODE_4M.fd` with `nvram template` `OVMF_VARS_4M.fd`, disk `qcow2` on `target dev='vda' bus='virtio'`, interface `network='default'` model `virtio`, VGA video, virtio RNG, virtio balloon, vsock, a virtio-serial controller with the `org.qemu.guest_agent.0` channel. The memory and vCPU values are `-i disk` defaults, not the source's 2 vCPU / 4096 MB. Metadata has to come from the `.vmx`, not from this output.

**What changed in the guest (`virt-diff` input vs output, 396 lines, confirmed from the debug log):**

| Change | Detail |
|---|---|
| open-vm-tools purged | `dpkg --purge open-vm-tools`: binaries (`vmtoolsd`, `vmware-*`, `VGAuthService`, `vmhgfs-fuse`), libraries, plugins, `/etc/vmware-tools/`, `/etc/pam.d/vmtoolsd`, units, rc links, udev rules `60-open-vm-tools.rules` and `99-vmware-scsi-udev.rules` removed |
| initramfs | `/etc/initramfs-tools/modules`: comment "The following modules were added by virt-v2v" + `bochs` (virtio already built in); `update-initramfs -v -c -k 6.8.0-142-generic`; old image kept as `/boot/initrd.img-6.8.0-142-generic.pre-v2v` (75,988,137 bytes; new 75,984,098) |
| Module alias | New `/etc/modprobe.d/virt-v2v-added.conf`: `alias scsi_hostadapter virtio_blk` |
| First-boot service | `/usr/lib/systemd/system/guestfs-firstboot.service` (oneshot, `After=network.target`) + SysV links; `/usr/lib/virt-sysprep/firstboot.sh` with scripts `5000-0001-wait-online`, `5000-0002-setenforce-0`, `5000-0003-install-qga` (`apt-get update` + `apt-get install qemu-guest-agent`), `5000-0004-setenforce-restore`, `5000-0005-start-qga` |
| Package database | `/var/lib/dpkg/status` rewritten by the purge (other packages' conffile records normalized; no package files changed) |
| Incidental | `/etc/ld.so.cache` (libc trigger), `/run/blkid`, `/run/needrestart` |

**Unchanged (checksum-identical to the source reference, OBSERVED with `guestfish --ro`):** `/etc/netplan/50-cloud-init.yaml`, `/etc/fstab`, `/boot/grub/grub.cfg`, `/boot/efi/EFI/ubuntu/grub.cfg`, `/boot/efi/EFI/BOOT/BOOTX64.EFI`, `/boot/efi/EFI/ubuntu/shimx64.efi`, `/etc/machine-id`, all three SSH host public keys, `/etc/nginx/nginx.conf`, `/etc/nginx/sites-available/default`, `/var/www/html/index.html`, the cloud-init disabled marker. No udev or systemd-networkd rules were added.

## 15. virt-v2v boot result

Path B unmodified: the untouched virt-v2v output under an overlay (03:43 to 03:45).

| Item | OBSERVED |
|---|---|
| Boot | Success: root shell on serial 58 s after launch. `is-system-running`: **starting**, because `guestfs-firstboot` was still running (section 17) |
| Firmware | UEFI, Secure Boot disabled, same fallback path and boot entries as Path A |
| Kernel / cmdline | 6.8.0-142-generic, `root=UUID=db8b3bb3-...` (unchanged) |
| Storage | `vda1` / `vda2`, mounts by UUID, same as Path A; initramfs contains `bochs` |
| NIC / network | `enp0s3` DOWN, unmanaged; netplan `ens192` unchanged: **same failure as Path A** |
| open-vm-tools | `not-found` (package `un`, no `/usr/bin/vmtoolsd`) |
| qemu-guest-agent | Not installed; the first-boot script was waiting (`systemd-networkd-wait-online --timeout=30`), and `nmcli: not found` was logged by the wait-online script |
| cloud-init | disabled by marker file (unchanged) |
| machine-id, SSH host keys | sha256 identical to the source; fingerprints ECDSA `9z1UPwZW...`, ED25519 `7Nw9FkUR...`, RSA `UXiyMja/...` identical |
| nginx | enabled, active, :80; config and page hashes identical; local HTTP 200 with sha256 `b9826e18...0046` |

## 16. VMware guest adaptation findings

| VMware-specific item (Stage 1F list) | After qemu-img (Path A) | After virt-v2v (Path B) |
|---|---|---|
| PVSCSI disk controller | Not needed: virtio-blk built in, `vda`, boots | Same; plus `alias scsi_hostadapter virtio_blk` and a rebuilt initramfs |
| VMXNET3 NIC | Replaced by virtio-net `enp0s3`, which gets no configuration | Same |
| netplan keyed on `ens192` | Unchanged, fails | Unchanged, fails |
| `ens192` in `/etc/cloud/cloud.cfg.d/90-installer-network.cfg` | Unchanged (cloud-init disabled, so inert) | Unchanged |
| open-vm-tools | Installed and enabled, skipped at boot by `ConditionVirtualization=vmware` | Purged |
| VMware udev rules | Present | Removed with the package |
| Guest agent for the new hypervisor | None | None yet; first boot tries to install qemu-guest-agent from the Ubuntu archive |
| UEFI boot without VMware NVRAM | Works via fallback loader | Works via fallback loader; grub.cfg not regenerated (warning), not needed here |
| Identity (machine-id, SSH keys, FS UUIDs, hostname) | Preserved | Preserved |

## 17. Network remediation experiment

The unmodified virt-v2v result was recorded first (section 15). Then a **second disposable copy** was made and changed (G9, 03:46):

1. `cp --sparse=always` of `local-out/legacy-source-vm-sda` to `remediated/legacy-source-vm-netfix.qcow2`. The copy's sha256 before any change equalled the output's (`94bc1cd6...91c6`).
2. With guestfish on the copy only: upload a replacement `/etc/netplan/50-cloud-init.yaml`, then set owner 0:0 and mode 0600 (the original's).
3. `qemu-img check` clean; mode 0444; new sha256 `5326b130...d3d6`. The original output still verified afterwards.

**Design of the change.** The guest's own configuration structure was kept: one ethernet, static address, static default route, one nameserver, `dhcp4: false`. Only two things changed:

- **Interface matching.** Instead of the hard-coded VMware name, the NIC is matched by driver (`match: driver: virtio_net`, netplan ID `primary`), so it no longer depends on which PCI slot names the interface.
- **Addresses.** The source addresses were replaced with test addresses on the isolated QEMU network, because the live source owns 192.168.50.31.

`virt-diff` between the virt-v2v output and the remediated copy lists exactly one changed file:

```text
= - 0600        235 /etc/netplan/50-cloud-init.yaml
+# Stage 1G remediation (disposable converted test copy only): match the NIC by driver instead of
+# the VMware-specific name ens192. Test address on the isolated QEMU user network, not 192.168.50.31.
 network:
   version: 2
   ethernets:
-    ens192:
+    primary:
+      match:
+        driver: virtio_net
       addresses:
-      - "192.168.50.31/24"
+      - "10.0.2.15/24"
       nameservers:
         addresses:
-        - 192.168.50.2
+        - 10.0.2.3
       dhcp4: false
       routes:
       - to: "default"
-        via: "192.168.50.2"
+        via: "10.0.2.2"
```

**Boot of the remediated copy (03:50 to 03:56), OBSERVED:**

| Proof | Result |
|---|---|
| Generated config | `/run/systemd/network/10-netplan-primary.network` with `[Match] Driver=virtio_net` |
| Interface up | `enp0s3` UP, LOWER_UP; `networkctl`: routable, configured; `netplan status`: "enp0s3 ethernet UP (networkd: primary)" |
| Test address | 10.0.2.15/24 on `enp0s3` |
| Default route | `default via 10.0.2.2 dev enp0s3 proto static`; `ping 10.0.2.2`: 2/2 replies |
| wait-online | `systemd-networkd-wait-online` active (exited), status 0 |
| DNS | Configured (10.0.2.3 on the link, systemd-resolved stub), but lookups failed ("All attempts to contact name servers or networks failed"). The isolated network (`restrict=on`) does not forward DNS, so DNS was **not proven**. |
| nginx listening | :80 and [::]:80, service active |
| HTTP from outside the guest | `curl http://127.0.0.1:18080/` on the conversion host (user-network port forward to guest :80): **HTTP 200, 267 bytes, sha256 `b9826e18a06a354d6ba97e3419e266b1453cb2a3b0038d4b3dcd45c96c170046`** (= source page) |
| SSH | `ssh-keyscan` through the :22 forward returned the source's three host key fingerprints (identical) |
| 192.168.50.31 | Never assigned to any test guest |

**Side finding: virt-v2v first boot on an isolated network.** `guestfs-firstboot` ran `apt-get update` for the qemu-guest-agent install. With no DNS, the apt retries were still running after more than 4 minutes, so the unit stayed `activating` and `systemctl is-system-running` reported `starting` for the whole test. nginx and SSH were already up. The scripts not yet run (`5000-0004`, `5000-0005`) remained queued. The oneshot has no start timeout in its unit, so how long it takes to give up was not measured (NOT TESTED).

## 18. qemu-img vs virt-v2v comparison

Only what was observed is listed.

| Aspect | Path A: qemu-img | Path B: virt-v2v (unmodified) |
|---|---|---|
| Nature | Container conversion | Guest-aware conversion + container conversion |
| Time | 5 s | 136 s |
| Output | qcow2 3.21 GiB, identical guest content | qcow2 2.73 GiB (unused blocks skipped) + libvirt XML |
| Guest-visible bytes vs input | Identical | Different (files below) |
| Boots under QEMU/KVM, UEFI | Yes | Yes |
| Disk naming | `vda`, mounts by UUID | Same |
| FS / partition UUIDs | Unchanged | Unchanged |
| initramfs | Unchanged, works | Rebuilt (`bochs` added), backup kept |
| grub.cfg / ESP | Unchanged | Unchanged (warning: could not update Grub2 config) |
| UEFI boot path | Fallback loader, fresh varstore | Same |
| netplan | Unchanged (`ens192`) | Unchanged (`ens192`) |
| Network result | No network | No network |
| VMware Tools | Present, enabled, skipped by condition | Purged |
| Guest agent | None | Install attempted at first boot (needs repository access) |
| machine-id | Unchanged | Unchanged |
| SSH host keys | Unchanged | Unchanged |
| nginx package, config, page, service | Unchanged, HTTP 200 locally | Unchanged, HTTP 200 locally |
| Boot state at check | `running` | `starting` (first-boot service still active) |
| VM metadata | None | XML: q35, OVMF, virtio disk and NIC, 1 vCPU / 2 GiB defaults |

## 19. What was automatically transformed

By virt-v2v, all OBSERVED:

1. VMware Tools removed as a package, including its udev rules and service links.
2. The initramfs rebuilt for the target, with `bochs` added. The virtio drivers were already built in, as virt-v2v itself detected (`virtio: blk=true net=true rng=true balloon=true`).
3. A `scsi_hostadapter` alias set to `virtio_blk`.
4. A first-boot mechanism installed to add qemu-guest-agent.
5. The disk container converted to qcow2 without its unused blocks.
6. Target metadata generated (libvirt XML with UEFI firmware, q35, virtio devices).

By qemu-img: only the container, transparently to the guest.

By the platform, in both paths (not by any tool): OVMF created boot entries for the new disk, udev named the disk `vda` and the NIC `enp0s3`, and systemd skipped VMware-only units by virtualization condition.

## 20. What required manual remediation

- **Only the network configuration:** replacing the name match `ens192` with a hardware-independent match (driver `virtio_net`) in `/etc/netplan/50-cloud-init.yaml`, plus an address valid for the network the guest lands on. Without it the guest boots healthy but unreachable, in both paths.
- Not needed on this guest: bootloader changes, fstab changes, driver injection or initramfs changes (Path A booted without them).
- Not remediation: the serial-getty autologin instrumentation lived only in disposable boot overlays for evidence collection (section 9). The remediated image does not contain it.

## 21. What remains unknown

- Behaviour on KubeVirt: virtual hardware layout, NIC name, firmware settings, pod-network addressing. No cluster exists.
- Boot with **Secure Boot on** (signed shim 15.8 and GRUB are present, NOT TESTED).
- DNS resolution in the converted guest, and whether the virt-v2v first boot completes successfully with repository access (qemu-guest-agent installed and started). NOT TESTED.
- Whether the Grub2 configuration warning matters on other kernels or after a kernel update (grub.cfg was simply left as is).
- `virt-v2v -i vmx` with the reference `.vmx` (would carry 2 vCPU / 4096 MB and the MAC), and `-o kubevirt`. Not run.
- Filesystem consistency beyond a clean boot (no `fsck`).
- Performance of conversion or of the guest (L3 lab, not representative).
- The production cutover: when and how 192.168.50.31 moves, and how the duplicate identity (same machine-id, host keys, hostname) is kept away from the running source.

## 22. KubeVirt/CDI implications

All INFERRED from the Stage 1G observations and the Stage 0 design. Nothing was deployed.

| Topic | Implication |
|---|---|
| Firmware | The VM spec needs EFI boot with **Secure Boot off** to match what was proven. A fresh NVRAM is fine: the fallback loader works. Secure Boot on is a separate test. |
| Disk bus | virtio works without guest changes. Keep KubeVirt's virtio disk bus; SATA or SCSI emulation is unnecessary for this guest. |
| Disk format | Both conversion outputs are qcow2. CDI stores VM disks as raw on a PVC and converts supported formats on import. Whether to hand CDI a qcow2, a raw image or the flat extent is still an **explicit decision**; nothing here chooses it. |
| Network | The single biggest blocker. Without a netplan change the VM boots unreachable. The driver-based match proven here is independent of the interface name, but addressing depends on the KubeVirt network binding: a pod network typically hands out an address by DHCP, while a bridged/secondary network could keep a static address. The remediation and the binding must be designed together. |
| Guest agent | virt-v2v's first boot tries to install qemu-guest-agent from the internet. In an isolated or air-gapped cluster that stalls (observed on the isolated network). Either pre-install the agent during conversion, provide a mirror, or remove the first-boot job. |
| VMware Tools | Path A would carry an idle open-vm-tools into KubeVirt; Path B removes it. |
| Metadata | `-i disk` guesses 1 vCPU / 2 GiB. The `VirtualMachine` spec must take CPU, memory, firmware and MAC policy from the `.vmx` facts recorded in Stage 1C/1D. |
| Identity | machine-id, SSH host keys and hostname survive conversion. Good for continuity, but the migrated VM and the source must never run on the same network with the same address. |
| Tooling | virt-v2v 2.4.0 handled this guest fully from a local disk, which is the same pattern MTV/Forklift uses in its conversion pod (industry reference, not tested here). `-o kubevirt` remains unused and experimental. |

## 23. Stage 1G limitations

- **L3 nesting.** The test guests ran three hypervisors deep. Boot times (56 to 67 s to a shell) are functional evidence only.
- **Isolated user-mode network.** It proves interface configuration, routing to the gateway and inbound HTTP/SSH through port forwards. It does not prove LAN reachability, DNS or outbound access.
- **Test addresses, not production.** The remediation used 10.0.2.15 instead of 192.168.50.31, deliberately.
- **One guest, one OS.** Ubuntu 24.04 with virtio built in and UUID mounts is a favourable case. Guests with LVM, `/dev/sdX` fstab entries, other distributions or Windows would behave differently.
- **Serial access used harness instrumentation** (overlay-only root autologin). A production VM would be reached through its real network or console, not through this.
- **Plain QEMU, not libvirt or KubeVirt.** The XML from virt-v2v was inspected, not used.
- **qcow2 was a working format**, chosen for comparability, not a target decision.
- The first-boot guest-agent install could not complete by design of the isolated network, so its end state is unknown.

## 24. Stage 1H entry criteria

Stage 1H is not defined here. Status of each criterion at the end of Stage 1G:

| Criterion | Status |
|---|---|
| Converted KVM boot path understood | Met: UEFI fallback boot on virtio-blk, three KVM boots (sections 7, 11, 15) |
| qemu-img vs virt-v2v behaviour documented | Met: sections 10, 14, 18 |
| Guest hardware adaptation understood | Met: sections 12, 16, 19 |
| Network migration risk understood | Met: confirmed failure and a proven, minimal remediation (sections 13, 17, 20) |
| One reproducible converted working image exists | Met: `virt-v2v/remediated/legacy-source-vm-netfix.qcow2`, sha256 `5326b130...d3d6`, reproducible from the working copy with the recorded commands |
| Golden copy untouched | Met: identical hashes, sizes and timestamps; only the read-only attribute added (section 8) |
| Source VM healthy | Met: powered on, .31, HTTP 200, page sha256 unchanged, 0 snapshots |
| Conversion host documented | Met: ADR 006 and section 6 |
| KubeVirt target format still an explicit decision | Met: not chosen (section 22) |
| KubeVirt/CDI not implemented | Met: nothing installed |

Stage 1H also requires the user's explicit approval, with objective, scope and change boundary written down. No Kubernetes, KubeVirt, CDI or AWS work starts without it.

## Gates

| Gate | Evidence | Result |
|---|---|---|
| G1 Repository and source state | `main` = `origin/main` = `aeb7661f59038d6ca222e587ba0a034ed46c67be` (Stage 1F commit), clean tree; source on, .31, HTTP 200, page sha256 from Windows and ESXi | PASS |
| G2 Golden artifact verified and protected | Descriptor and flat sha256, size, timestamps match Stage 1E; ReadOnly attribute set with content unchanged; write-open refused (section 8) | PASS |
| G3 Conversion host ready | KVM, `/dev/kvm`, qemu-img, libguestfs, guestfish, virt-v2v versions; OVMF installed and paths recorded (sections 6, 7) | PASS |
| G4 Working input baseline | `qemu-img info/check`, GPT layout, FS UUIDs and sizes, OS, ESP, netplan `ens192` static .31, open-vm-tools enabled, cloud-init disabled, UUID mounts, vmxnet3/pvscsi modules, reference checksums; input hash OK before and after | PASS |
| G5 Path A qemu-img conversion | Command, formats, sizes, sparsity, hash; `check` clean; `compare`: identical (section 10) | PASS |
| G6 Path A boot | QEMU command, KVM evidence, UEFI, CPU, `vda`, `enp0s3`, kernel, mounts, nginx (section 11) | PASS |
| G7 Path A network | `ens192` absent, `enp0s3` unmanaged, no address, no DHCP; migration risk confirmed; .31 not used (section 13) | PASS |
| G8 Path B virt-v2v conversion | Local docs read; `-i disk -if vmdk -o local -of qcow2`; input unchanged; files, hashes, format, XML, warning and guest changes recorded (section 14) | PASS |
| G9 Path B boot and remediation | Unmodified boot recorded; second copy with one netplan change; interface up, 10.0.2.15, default route, nginx, HTTP 200 with source page hash (sections 15, 17) | PASS |
| G10 Documentation, evidence, cleanup | This record, ADR 006, diagram, index updates; final golden/source/working-copy/output checks; overlays deleted and listed; no QEMU running | PASS |

## Sources

- Local, version-exact documentation on `conversion-host-01`: `virt-v2v --help`, `--machine-readable`, man pages `virt-v2v(1)`, `virt-v2v-input-vmware(1)`, `virt-v2v-output-local(1)`, `virt-v2v-support(1)` (virt-v2v 2.4.0); `/usr/share/qemu/firmware/*.json` (ovmf 2024.02-2ubuntu0.9).
- Ubuntu package metadata from `apt-cache policy/show` against the noble archive, 2026-09-28.
- Raw evidence and scripts on the Windows host, outside Git: `C:\VMs\conversion-host-01\stage-1g\` (G1 to G10 outputs, test harness, collected text evidence including the virt-v2v debug log, virt-diff outputs and serial logs). The disk artifacts stay on `conversion-host-01` in `/srv/migration-lab/stage-1g/`.
