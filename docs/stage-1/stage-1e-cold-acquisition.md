# Stage 1E: cold acquisition of the migration source disk

| Field | Value |
|---|---|
| Project | Project 1.5: VM-to-Kubernetes Migration Platform |
| Stage | 1E |
| Date | 2026-09-27 (all times UTC; operation 14:12 to 14:24) |
| Approval | Explicitly approved by the user: cold acquisition of `legacy-source-vm` by the recommended cold `scp` method (M1), graceful shutdown only, hard power-off prohibited, destination `C:\VMs\legacy-source-vm\stage-1e\` |
| Result | **Success.** Disk acquired byte-identical (sha256 `72ca45c7bcb2fc617e53f6286832d6d53d74e9801a18fb295c5fb88de1f9c9e7` on source before copy, destination, and source after copy). Source powered back on and validated. |
| Service downtime | About 10.5 minutes (shutdown request 14:12:38 to HTTP 200 at about 14:23:10) |
| Related | [Stage 1D record](stage-1d-vmware-source-artifacts.md) (procedure and integrity design), [Stage 1C record](stage-1c-migration-source.md) (baseline), [Stage 1 index](README.md) |

Labels: **OBSERVED** = seen in this lab by a command we ran. **INFERRED** = reasoned from observations or documentation, not directly tested.

## 1. Objective

Execute the cold-copy procedure designed in [Stage 1D section 9](stage-1d-vmware-source-artifacts.md#9-recommended-future-cold-copy-procedure):

1. Shut down `legacy-source-vm` gracefully.
2. Prove it is off and its disk lock is released.
3. Copy the VMDK descriptor and flat extent to Windows.
4. Prove that the copy is identical and the source unchanged.
5. Bring the source back and prove it is healthy and unchanged in baseline-relevant state.

## 2. Scope and change boundary

| Done | Not done (as required) |
|---|---|
| One graceful guest shutdown (`vim-cmd vmsvc/power.shutdown 2`) and one power-on of `legacy-source-vm` | No hard power-off; no snapshot; no change to the VM configuration, guest OS, netplan, nginx or VMware Tools |
| Read-only copy of `legacy-source-vm.vmdk` (descriptor) and `legacy-source-vm-flat.vmdk` to `C:\VMs\legacy-source-vm\stage-1e\`, plus reference copies of `.vmx`, `.nvram` and `.vmxf` in `reference\` | No disk conversion, no inspection tooling run against the copy, no copy into Git |
| Two full sha256 passes on ESXi (VM off) and one on Windows | No Kubernetes, KubeVirt, CDI, AWS, conversion host or migration controller; `kvm-learning-01` stayed powered off |
| Read-only guest checks before and after (stdin-fed script, as in Stage 1D) | No Stage 1F work |

## 3. Timeline (OBSERVED)

| Time | Step | Result |
|---|---|---|
| 14:12:24 | 0-1 Preconditions and health | `C:` 405.5 GiB free, destination empty; `kvm-learning-01` off; 0 snapshots; tools running; HTTP 200 + page sha256 from Windows and ESXi |
| 14:12:25 to 14:12:30 | 2 Pre-shutdown baseline | ESXi hashes, descriptor IDs, `vmkfstools -D`, `stat`; guest identifiers (section 4) |
| 14:12:38 | 3 Graceful shutdown requested | vmware.log: `Tools: sending 'OS_Halt'` |
| 14:12:39 to 14:12:41 | 4 Powered off | vmware.log: `VMAutomationPowerOff: Powering off`, `VMX exit (0)`; `power.getstate` = Powered off |
| 14:12:48 | 4 Off verified | `.vmx`: `cleanShutdown = "TRUE"`, `softPowerOff = "TRUE"`; `.vmx.lck` gone; 0 `.vswp` files; flat extent lock `mode 0`, owner all zeros |
| 14:12:49 to 14:15:21 | 4 Pre-copy hash (ESXi) | `72ca45c7...c9e7`, 152 s |
| 14:15:31 to 14:20:09 | 5 Acquisition (`scp`) | Descriptor 541 bytes; flat 42,949,672,960 bytes in 276 s (about 148 MiB/s); `scp` exit 0 |
| 14:20:16 to 14:22:51 | 6 Verification | Windows hash `72ca45c7...c9e7` (44 s); ESXi post-copy hash `72ca45c7...c9e7` (155 s), run in parallel |
| 14:23:01 | 7 Power on | `bootTime 2026-09-27T14:23:01Z` |
| 14:23:10 | 7-9 Up | Tools running, IP 192.168.50.31; `vmkping` 0.40 ms avg; ESXi ARP `00:0c:29:0f:3d:15`; ESXi HTTP page sha256 matches |
| 14:23:31 | 8-9 Windows | Ping OK, ARP `00-0C-29-0F-3D-15`, TCP 22 OK, HTTP 200, 267 bytes, page sha256 matches |
| 14:23:47 | 10 Guest comparison | Identical to the pre-shutdown baseline except timestamp and uptime (section 8) |

The shutdown took about 3 seconds from request to power-off. vmware.log and the `cleanShutdown`/`softPowerOff` flags confirm it was a guest-initiated OS halt through VMware Tools, not a forced power-off.

## 4. Pre-shutdown baseline (OBSERVED 14:12)

It matched the [Stage 1D section 3](stage-1d-vmware-source-artifacts.md#3-current-source-state) values exactly:

- `.vmx` sha256 `19a1a410...9bc3`; descriptor `5b407e06...e9ff`, `CID=7475b330`; `.nvram` `e99a76eb...2646`; `.vmxf` `2905a1b9...e4ab`.
- Flat extent: `Addr <4, 26, 1>`, `len 42949672960`, `nb 3487`, lock `mode 1` (held by the running VM).
- Guest: `system: running`, 0 failed units, same PTUUID, FS UUIDs and PARTUUIDs, `ens192`/`vmxnet3`, same MAC and 192.168.50.31/24, netplan sha256 `bd449fd7...b253`, nginx checksums and page hash, machine-id, SSH host keys, 500 packages.

## 5. Integrity verification

| Check | Source, VM off, before copy (14:12:48) | Destination (Windows) | Source, VM off, after copy (14:20:15) | Result |
|---|---|---|---|---|
| Flat extent sha256 | `72ca45c7bcb2fc617e53f6286832d6d53d74e9801a18fb295c5fb88de1f9c9e7` | Same | Same | **Copy identical; source unchanged** |
| Flat extent size | 42,949,672,960 | 42,949,672,960 | 42,949,672,960 | Equal |
| Descriptor sha256 | `5b407e06ec29cac925a4504978ca3cef5d231398536ab476bcd03acbdc5de9ff` | Same | Same | Equal |
| `.vmx` sha256 (post-shutdown content) | `f3af99e36cbd2dadef8cd55685fd3e5cb4570fc2632729b5bc4f8efd700fb0db` | Same (reference copy) | Same | Equal |
| `.nvram` / `.vmxf` sha256 | `e99a76eb...2646` / `2905a1b9...e4ab` | Same | Same | Equal |
| Flat mtime | 14:12:39 | - | 14:12:39 | Unchanged |
| `vmkfstools -D` | `Addr <4, 26, 1>`, `nb 3487`, lock `mode 0` | - | Same address and allocation, lock `mode 0` | Same file object, not rewritten |
| Power state / snapshots | Powered off / 0 | - | Powered off / 0 | No power-on or snapshot inside the window |

The VMFS lock generation counter rose from 41 to 45 during the window. That is VMFS lock bookkeeping from the read-only opens by `sha256sum` and `scp`, not a content change: the full hash is identical.

What this proves:

- The acquired flat extent is byte-identical to the source disk as it was at shutdown.
- The acquisition did not change the source disk, its descriptor, configuration or firmware state during the powered-off window.
- Following [Stage 1D section 10](stage-1d-vmware-source-artifacts.md#10-integrity-strategy), it does not prove anything about the source after power-on, which legitimately writes to the disk again. It also does not prove filesystem consistency beyond the clean guest shutdown.

## 6. Acquired artifact

Location: `C:\VMs\legacy-source-vm\stage-1e\` on the Windows host, **outside the repository**.

| File | Bytes | sha256 | Role |
|---|---:|---|---|
| `legacy-source-vm.vmdk` | 541 | `5b407e06ec29cac925a4504978ca3cef5d231398536ab476bcd03acbdc5de9ff` | VMDK descriptor (`createType="vmfs"`, extent `legacy-source-vm-flat.vmdk`) |
| `legacy-source-vm-flat.vmdk` | 42,949,672,960 | `72ca45c7bcb2fc617e53f6286832d6d53d74e9801a18fb295c5fb88de1f9c9e7` | Raw disk data (GPT, ESP, ext4 root) |
| `reference\legacy-source-vm.vmx` | 2,456 | `f3af99e36cbd2dadef8cd55685fd3e5cb4570fc2632729b5bc4f8efd700fb0db` | VM configuration, as written at shutdown (reference only) |
| `reference\legacy-source-vm.nvram` | 270,840 | `e99a76ebba91d6e2af591b0cb0909ccea6462f6aa5753125fc142ac8e6b72646` | UEFI variable store (reference only, not migrated) |
| `reference\legacy-source-vm.vmxf` | 47 | `2905a1b9ca9bdc633f432ef26904e11b43e1e9babad0378037617053d89ae4ab` | Extended config (reference only) |

- The descriptor and flat file keep their original names side by side, so the descriptor's extent reference stays valid.
- The flat copy is a normal (non-sparse) 40 GiB NTFS file, as predicted in Stage 1D. `C:` free space dropped from 405.5 GiB to about 365.5 GiB (INFERRED from the file size).
- Raw evidence and the scripts used are in `evidence\` and `scripts\` next to the artifact.
- This is now the only independent copy of the source disk. There is no snapshot.

## 7. Power-on and validation (OBSERVED)

| Check | Result |
|---|---|
| Power state | Powered on at 14:23:01; tools running with IP 192.168.50.31 about 6 s later |
| From ESXi | `vmkping` round trip 0.366/0.399/0.443 ms; ARP entry `00:0c:29:0f:3d:15`; `wget` page sha256 `b9826e18...0046` |
| From Windows | Ping OK; ARP `00-0C-29-0F-3D-15`; TCP 22 OK; `curl.exe` HTTP 200, 267 bytes, page sha256 `b9826e18a06a354d6ba97e3419e266b1453cb2a3b0038d4b3dcd45c96c170046` |
| Snapshots | 0 on both VMs; `kvm-learning-01` still powered off |

## 8. Baseline comparison after power-on

The read-only guest script was run before shutdown (14:12:28) and after power-on (14:23:47), and the outputs were diffed line by line. The **only** differing lines were the header timestamp and `uptime` (31 minutes since 13:41:09, versus 0 minutes since 14:23:04). Everything else was identical:

- hostname and kernel; system `running`, 0 failed units;
- block devices, PTUUID, FS UUIDs and PARTUUIDs, mounts, fstab, kernel command line;
- `ens192` address, MAC, driver `vmxnet3`, default route, DNS;
- nginx enabled/active on :80 with `nginx.conf`, `sites-available/default` and `index.html` checksums, and `curl localhost` 200;
- machine-id and all three SSH host key fingerprints;
- 500 packages, no reboot required, the same APT history; open-vm-tools active, cloud-init disabled;
- netplan sha256 `bd449fd7...b253`.

## 9. Expected changes on the source (not defects)

| Item | Change | Why |
|---|---|---|
| `.vmx` | 2,458 bytes (`cleanShutdown`/`softPowerOff` FALSE) -> 2,456 bytes with both TRUE at shutdown -> 2,458 bytes with both FALSE after power-on; `.vmx~` holds the 2,456-byte version | VMware records the shutdown state in the `.vmx` |
| Runtime files | `.vswp`, VMX swap and `.vmx.lck` deleted at power-off and recreated at power-on; `vmware.log` rotated (`vmware-2.log` is the 13:41 to 14:12 run); new `legacy-source-vm-2.scoreboard` | Normal power cycle |
| Flat extent after power-on | Allocation 3,570,688 -> 3,576,832 KiB (+6 MiB); mtime 14:23 | The booted guest writes (journal, logs). Expected after the verified window. |
| Descriptor mtime | Touched at 14:23 (content not re-hashed after power-on) | Opened by the VMX at power-on |
| Datastore free | 192,509,116,416 -> 192,501,776,384 bytes (about 7 MiB less) | Mainly the new flat-extent blocks and the rotated log |
| Guest uptime / boot time | New boot at 14:23:01 | The approved power cycle |

## 10. Correction to Stage 1D: the descriptor CID is not a write indicator here

Stage 1D assumed that the descriptor's `CID` changes on the first write after the disk is opened, and that the descriptor is updated when the disk is closed. It listed `CID` as a cheap "was the disk written?" check.

Stage 1E observed otherwise:

- The running VM had written to the disk: the flat mtime moved from 13:41 to 14:12:39, and in Stage 1D the live API `contentId` already differed from the on-disk `longContentID`.
- Yet the descriptor still read `CID=7475b330` and `ddb.longContentID = "dc2d48eb...7475b330"` after the clean shutdown, with an unchanged sha256 and an mtime of 13:41:08.

So for this ESXi `vmfs` (descriptor + flat) disk, the on-disk `CID` does **not** track writes. The Stage 1D record, glossary and interview notes were corrected in the same commit as this record. The reliable cheap indicators are the flat file's mtime, size and allocation (`nb`), and the only proof is the full hash.

## 11. What Stage 1E proves

1. A cold, snapshot-free acquisition of the source disk works on this free ESXi host with SSH/`scp` alone, with about 10.5 minutes of service downtime.
2. The acquired descriptor + flat extent are byte-identical to the source disk at shutdown (three matching sha256 values).
3. The acquisition did not modify the source: the full hash, metadata hashes, file identity and allocation are identical before and after the copy, with the VM off throughout.
4. The source returns healthy and unchanged in every baseline-relevant property after the power cycle.

## 12. What Stage 1E does not prove

- That the acquired image boots outside VMware, converts cleanly, or is read correctly by `qemu-img` or CDI. No tool was run against the copy.
- Filesystem-level consistency beyond the clean guest shutdown (no `e2fsck -n` was run; that needs a Linux environment).
- Anything about the Stage 1C network and boot risks on KubeVirt.
- That the copy stays intact over time. Re-hash it before use.

## 13. Stage 1F entry criteria

Stage 1F is not defined here. It may begin only when:

1. The user has reviewed this record and explicitly approved Stage 1F, with objective, scope and change boundary written down.
2. The acquired artifact is still intact: `legacy-source-vm-flat.vmdk` re-hashes to `72ca45c7bcb2fc617e53f6286832d6d53d74e9801a18fb295c5fb88de1f9c9e7`, and the descriptor to `5b407e06...e9ff`. Any work happens on a **copy** of the artifact, never on the only verified copy. Marking the verified files read-only on Windows is recommended.
3. If Stage 1F inspects or converts the image, the **conversion-host decision** (Stage 0 feasibility section 6) is taken in an ADR first. It is not made implicitly by reusing `kvm-learning-01`, which stays powered off.
4. `legacy-source-vm` remains healthy (HTTP 200, page sha256 `b9826e18...0046`) and unchanged in its baseline properties. It is not re-acquired, shut down or snapshotted without a separate approval.
5. Any comparison of a future migrated VM uses guest and application identifiers (FS UUIDs, machine-id, SSH host keys, netplan and nginx checksums, page hash), not disk hashes, because conversion changes bytes.
6. No Kubernetes, KubeVirt, CDI or AWS work starts without its own explicit approval.
7. The ESXi host is still in its recorded state: networking and datastore configuration unchanged, datastore free about 179.3 GB (192,501,776,384 bytes; GB = 2^30 bytes), NTP synchronized, maintenance mode off.
