# Stage 1I: first KubeVirt migration

| Field | Value |
|---|---|
| Project | Project 1.5: VM-to-Kubernetes Migration Platform |
| Stage | 1I, **Gates I1, I2, I3 and I4** (prepared image, pre-transfer boot test, AWS destination platform, first migration). Stage 1I is **not complete** |
| Date | 2026-10-01 (all times UTC; Gate I1 work 01:20 to 01:29; Gate I2 work 01:38 to 01:55; Gate I3 work 01:59 to 02:49; Gate I4 migration 03:47 to 04:07, evidence reconciliation 04:10 to 04:28) |
| Approval | Explicitly approved by the user: Gate I1 only. Prepare a new standalone qcow2 on `conversion-host-01` from the kept Stage 1G virt-v2v output: replace netplan, install qemu-guest-agent offline, remove the virt-v2v first-boot mechanism, validate, hash and protect the result. Not approved: AWS, Terraform, Kubernetes/KubeVirt/CDI, touching `legacy-source-vm` or the Stage 1E golden VMDK, modifying any kept Stage 1G artifact, changing SSH keys or sudo policy, booting the prepared image, Gate I2, committing or pushing. Gate I2 was approved separately afterwards (section 15), Gate I3 after that (section 16), and Gate I4 after that (section 18) |
| Result | **Gate I1 PASS.** All 12 required integrity checks passed (41 individual checks, 0 failed). Prepared image sha256 `2b30e195b50c1241aa14508fe24dd0c024af213ec19b89052ab84c6e6b4f93b2`, mode 0444, `chattr +i`. The source, the source VM and the golden artifact are unchanged. **Gate I2 PASS** (section 15): the exact prepared image booted under QEMU/KVM with UEFI through a disposable overlay. It got a DHCP lease and default route, systemd reported `running`, the guest agent answered over `org.qemu.guest_agent.0`, nginx returned HTTP 200 with the source page hash, and its identity is unchanged (54 of 54 checks). A first run on QEMU user mode with `restrict=on` was blocked only because that network sends no DHCP router; the passing run used an isolated network namespace, approved by the user. The image was never modified. **Gate I3 PASS** (section 16): Terraform built the AWS destination in ap-south-1, one `m8i.xlarge` with nested virtualization running CentOS Stream 9. Its single-node kubeadm cluster runs Kubernetes v1.36.5, CRI-O 1.36.6, flannel v0.28.9, KubeVirt v1.9.0, CDI v1.66.1 and the EBS CSI driver with an encrypted gp3 StorageClass. **Gate I4 runtime migration PASS; evidence reconciliation PASS** (section 18): the prepared qcow2 was transferred to the node with matching sha256 at both ends, imported by CDI into a standalone 40 GiB encrypted gp3 Block DataVolume, and booted as the KubeVirt VM `legacy-source-vm-migrated`. The guest got 10.0.2.2 by DHCP through masquerade, kept its workload identity, answered the guest agent, and served the source page (HTTP 200, 267 bytes, sha256 `b9826e18...0046`) to the operator workstation through NodePort 30080. Gate I5 has not started |
| Related | [Stage 1H feasibility](stage-1h-kubevirt-target-feasibility.md) (sections 15, 17, 18, 19 and 29.2), [ADR 007](../adr/007-kubevirt-target-platform.md) (target platform), [ADR 009](../adr/009-kubevirt-storage-model.md) (storage model), [Terraform](../../infra/terraform/stage-1i-target/main.tf) and [Kubernetes templates](../../infra/kubernetes/stage-1i/kubeadm-config.yaml.tmpl) used by Gate I3, Gate I4 manifests ([DataVolume](../../infra/kubernetes/stage-1i/datavolume-legacy-source-vm-disk.yaml), [VM](../../infra/kubernetes/stage-1i/vm-legacy-source-vm-migrated.yaml), [Service](../../infra/kubernetes/stage-1i/service-legacy-source-vm-http.yaml)), [ADR 010](../adr/010-migration-network-remediation.md) (network remediation), [ADR 006](../adr/006-dedicated-conversion-host.md) (conversion host), [Stage 1G record](stage-1g-controlled-conversion.md) (kept virt-v2v output, first-boot artifact list), [Stage 1F record](stage-1f-conversion-host.md) (protected-input model), [Stage 1 index](README.md) |

Labels: **OBSERVED** = seen in this lab by a command we ran. **INFERRED** = reasoned from observations or documentation, not directly tested. **NOT TESTED** = deliberately not done.

## 1. Objective

Gate I1 produces the exact image that the rest of Stage 1I will boot, transfer and import. It implements the Stage 1H preparation design (section 18 step 1) and writes the preparation record of Stage 1H section 29.2:

- a **new, standalone** qcow2 derived from the kept Stage 1G virt-v2v output, never the output itself;
- intended change C6: netplan replaced with the Stage 1H section 15 design (match `virtio_net`, DHCP);
- intended change C7: `qemu-guest-agent` and its exact dependency closure installed **offline**;
- intended change C5: the virt-v2v first-boot mechanism (five scripts, `firstboot.sh`, the `guestfs-firstboot` service and its links) removed;
- nothing else changed, proven by before/after inspection and an offline `virt-diff`;
- the result hashed, set read-only and immutable.

## 2. Scope

| Item | In Gate I1 |
|---|---|
| Host | `conversion-host-01` only (Ubuntu 24.04.5, kernel 6.8.0-142-generic, qemu-img 8.2.2, guestfish/virt-diff 1.52.0, `LIBGUESTFS_BACKEND=direct`, as root) |
| Input | `/srv/migration-lab/stage-1g/virt-v2v/local-out/legacy-source-vm-sda`, opened read-only (copy source, `guestfish --ro`, `virt-diff`) |
| Output | `/srv/migration-lab/stage-1i/working/legacy-source-vm-prepared.qcow2` |
| Guest network address | Not assigned. 192.168.50.31 is not used and no KubeVirt guest IP is hard-coded; the guest takes its address from DHCP |
| Boot | **NOT TESTED** by design. The prepared image was never booted. The boot test is Gate I2 (Stage 1H section 29.5) |
| Never used | `qemu-img amend`, `resize`, `rebase`, `commit`, `check -r`; any read-write guestfish session on a kept artifact; virt-customize |

## 3. Procedure executed

All scripts ran on `conversion-host-01` as root. Every step that could write touched only the Stage 1I working copy.

| Step | UTC | What ran | Result (OBSERVED) |
|---|---|---|---|
| 0. Precheck | 01:20 | Host identity, source hash and mode, free space (36 GB), tool versions, no qemu processes, ESXi power states | Source hash MATCH; Vmids 1, 2, 3 powered on |
| 1. Copy and inspect | 01:21 to 01:22 | `cp --sparse=always` source to the working path; sha256 of the copy; `qemu-img info --backing-chain` and `check`; read-only guest inspection (`guestfish --ro`) of the copy | Copy sha256 equals source `94bc1cd6...91c6`. Before-state recorded |
| 2. Dry run | 01:22 | Host apt (same release, fresh indexes) simulated against the **guest's own** `/var/lib/dpkg/status`, with and without recommends | 2 new packages, 0 upgraded, 0 removed. Stop rule not triggered |
| 3. Modify | 01:23 | `apt-get download` of the two exact versions on the host; deb sha256 checked against the signed apt index; prepared netplan validated with `netplan generate --root-dir`; one `guestfish --rw` session on the working copy: netplan upload, `dpkg --dry-run -i` then `dpkg -i` inside the guest root, `dpkg --audit`, removal of the temporary debs and of the 14 first-boot entries, `sync` | Hashes MATCH; `netplan generate` OK; dpkg exit 0; audit clean; guestfish exit 0; source hash unchanged |
| 4. Verify and finalize | 01:25 to 01:29 | `qemu-img check`, `info`, backing chain; read-only after-inspection; before/after comparison; `virt-diff` source vs prepared (both read-only); source re-verified; only then sha256, `chmod 0444`, `chattr +i`, write test | 41/41 PASS; finalized |

The offline install used guestfish rather than virt-customize (deviation D2, section 11).

## 4. Source verification

| Item | Value (OBSERVED) |
|---|---|
| Path | `/srv/migration-lab/stage-1g/virt-v2v/local-out/legacy-source-vm-sda` |
| Expected sha256 (Stage 1G) | `94bc1cd6beb730831dd087c6e36dc6ee7d21881f43455ff44d059e55fe1d91c6` |
| sha256 before Gate I1 | identical (MATCH) |
| sha256 after Gate I1 | identical (MATCH) |
| Mode / attributes | 0444 root:root, no immutable flag (the Stage 1G kept-output model); unchanged |
| Format | qcow2, 40 GiB virtual, no backing file, `qemu-img check` clean |

## 5. Prepared image

| Item | Value (OBSERVED) |
|---|---|
| Path | `/srv/migration-lab/stage-1i/working/legacy-source-vm-prepared.qcow2` |
| **sha256 (authoritative)** | **`2b30e195b50c1241aa14508fe24dd0c024af213ec19b89052ab84c6e6b4f93b2`** |
| Format | qcow2, compat 1.1, cluster size 65536, zlib, `corrupt: false` (compat and cluster size equal the source) |
| Virtual size | 42,949,672,960 bytes (40 GiB), unchanged |
| File length / allocated | 2,932,998,144 bytes / 2.67 GiB (source: 2,926,706,688 bytes) |
| `qemu-img check` | `No errors were found on the image.` 44669/655360 clusters allocated (source 44573) |
| Backing chain | **Standalone**: no `backing-filename`, `qemu-img info --backing-chain` lists exactly one image (Stage 1H section 17) |
| Protection | mode 0444 root:root and `chattr +i` (lsattr `----i---------e-------`). sha256 identical before and after protection. A root append attempt was rejected (`Operation not permitted`) |

Protection model: the Stage 1G kept outputs are 0444 only; the Stage 1F protected input was 0444 plus `chattr +i`. The prepared image is the input to every later Stage 1I gate, so it follows the stronger Stage 1F model.

## 6. qemu-guest-agent (intended change C7)

| Package | Version | Origin | deb sha256 (= signed apt index) |
|---|---|---|---|
| `qemu-guest-agent` | `1:8.2.2+ds-0ubuntu1.18` | noble-updates/universe | `62abf54bf34fed34dc65cbd973b4b6b6f4685fef30fbaa3fb3e8865e957fda75` |
| `liburing2` (dependency) | `2.5-1build1` | noble/main | `c2aef62accee92a06263c3ad4ef46132c13e409b54296c44792a20491830a7b0` |

**Dependency closure** (OBSERVED). `qemu-guest-agent` depends on `libc6 (>= 2.38)`, `libglib2.0-0t64 (>= 2.77.3)`, `libnuma1 (>= 2.0.11)`, `libudev1 (>= 183)`, `liburing2 (>= 2.3)` and pre-depends on `init-system-helpers (>= 1.54~)`. The guest already had `libc6 2.39-0ubuntu8.9`, `libglib2.0-0t64 2.80.0-6ubuntu3.9`, `libnuma1 2.0.18-1ubuntu0.24.04.1`, `libudev1 255.4-1ubuntu8.17` and `init-system-helpers 1.66ubuntu1`. Only `liburing2` was missing.

**Dry run** (OBSERVED, against the guest's package state, with and without recommends): `0 upgraded, 2 newly installed, 0 to remove`. The "27 not upgraded" in the same output describes packages already in the guest that have newer versions available; none of them was touched. The stop rule (Stage 1H section 19) was **not** triggered.

**Install method**: offline for the guest. The host downloaded the two debs; guestfish uploaded them into a temporary guest directory; `dpkg -i` ran inside the guest root with no guest network, no apt in the guest, and no first-boot job. The temporary debs were removed from the guest afterwards. Maintainer scripts ran in the chroot: `update-rc.d` added the SysV links, `systemctl`/`invoke-rc.d` reported `Running in chroot, ignoring request`, and the `libc-bin` trigger ran `ldconfig`.

**State after** (OBSERVED): both packages `install ok installed`; `dpkg --audit` clean; package diff before/after: exactly these 2 added, 0 removed, 0 version changes (499 installed before, 501 after). `qemu-guest-agent.service` is present and listed by `systemctl list-unit-files` as `static`. The package ships `60-qemu-guest-agent.rules`, which starts the service when the `org.qemu.guest_agent.0` virtio-serial port appears (INFERRED from the package contents; observed only at boot, Gate I2 and later).

## 7. First-boot cleanup (intended change C5)

Removed, exactly the entries virt-v2v added according to the Stage 1G `virt-diff` (all 14 were present before):

| Entry | Type |
|---|---|
| `/usr/lib/virt-sysprep/scripts/5000-0001-wait-online` | script |
| `/usr/lib/virt-sysprep/scripts/5000-0002-setenforce-0` | script |
| `/usr/lib/virt-sysprep/scripts/5000-0003-install-qga` | script |
| `/usr/lib/virt-sysprep/scripts/5000-0004-setenforce-restore` | script |
| `/usr/lib/virt-sysprep/scripts/5000-0005-start-qga` | script |
| `/usr/lib/virt-sysprep/scripts`, `/usr/lib/virt-sysprep` | directories (empty when removed) |
| `/usr/lib/virt-sysprep/firstboot.sh` | runner |
| `/usr/lib/systemd/system/guestfs-firstboot.service` | unit |
| `/etc/systemd/system/multi-user.target.wants/guestfs-firstboot.service` | enablement link |
| `/etc/init.d/guestfs-firstboot` | SysV link |
| `/etc/rc2.d/S99guestfs-firstboot`, `/etc/rc3.d/...`, `/etc/rc5.d/...` | SysV links |

After (OBSERVED): 14/14 absent; a whole-root search for `*guestfs-firstboot*` and `*virt-sysprep*` finds nothing; `systemctl list-unit-files` no longer knows `guestfs-firstboot.service`. No other unit or package was removed.

## 8. Netplan (intended change C6)

| | Before (virt-v2v output) | After (prepared) |
|---|---|---|
| File | `/etc/netplan/50-cloud-init.yaml` (only file in `/etc/netplan`) | same file, same directory listing |
| Owner / mode / size | root:root, 0600, 235 bytes | root:root, 0600, 404 bytes |
| sha256 | `bd449fd7afbc5e0dc47205da3c54f5ccd96099717e12fba11c45fa28f6f4b253` | `89ea1ea3897dfcdc5bbd5889dddca1ae5b51462e5e751db27aec99f650e46a3b` |
| Content | `ens192`, static 192.168.50.31/24, DNS and default route via 192.168.50.2, `dhcp4: false` | match `driver: virtio_net`, `dhcp4: true`, `dhcp6: false` |

Content placed in the guest:

```yaml
# Stage 1I prepared image (Gate I1): KubeVirt target network config for legacy-source-vm.
# Design: Stage 1H section 15 / ADR 010. Match by driver so the config does not depend on
# the interface name or MAC. Address, route and DNS come from the KubeVirt masquerade DHCP server.
network:
  version: 2
  ethernets:
    primary:
      match:
        driver: virtio_net
      dhcp4: true
      dhcp6: false
```

Validation (OBSERVED): `netplan generate --root-dir` in a temporary directory on the host produced `[Match] Driver=virtio_net` with `DHCP=ipv4`. The guest file contains no address, gateway, route, nameserver, interface name or MAC.

## 9. Integrity checks

All OBSERVED. "Unchanged" means the read-only before and after inspections of the working copy are identical.

| # | Check | Result |
|---|---|---|
| 1 | `qemu-img check` | PASS: no errors |
| 2 | `qemu-img info` | PASS: qcow2, 42,949,672,960 bytes, compat 1.1 and cluster size unchanged, not corrupt |
| 3 | No backing file | PASS: chain length 1 |
| 4 | Partition and filesystem structure | PASS: disk size, GPT, both partition types and GUIDs (`408D91CB-...5364`, `B701FE8C-...63CE`), filesystem list, `/etc/fstab`, `/boot` listing and `os-release` unchanged |
| 5 | Netplan | PASS: guest sha256 equals the prepared file, 0600 root:root, no static 192.168.50.31 |
| 6 | qemu-guest-agent installed | PASS: `1:8.2.2+ds-0ubuntu1.18`, unit present, `dpkg --audit` clean, only 2 packages added |
| 7 | Five first-boot scripts absent | PASS |
| 8 | `guestfs-firstboot` service and artifacts absent | PASS: all 14 entries absent, nothing found by search |
| 9 | nginx hashes unchanged | PASS: `nginx.conf` `48c6a4ec...0aa2`, `sites-available/default` `ce090135...b03f`, `index.html` `b9826e18...0046`, whole `/etc/nginx` tree `f6766240...9c8f`, `sites-enabled` listing |
| 10 | machine-id unchanged | PASS: `d90f169b005444be82a1d703193f8324` (hostname `legacy-source-vm` also unchanged) |
| 11 | Filesystem UUIDs unchanged | PASS: ESP `C340-CD01`, root `db8b3bb3-e776-42e8-902e-89124606b2f6` |
| 12 | SSH host key fingerprints unchanged | PASS: ECDSA `SHA256:9z1UPw...WHe8`, ED25519 `SHA256:7Nw9Fk...6mY`, RSA 3072 `SHA256:UXiyMj...niYg` (full values as in the [Stage 1C record](stage-1c-migration-source.md)) |

Supporting checks, also PASS: after-inspection guestfish exit 0; `virt-diff` ran read-only and lists none of `/etc/machine-id`, `/etc/hostname`, the SSH host keys, `/etc/nginx`, `/var/www` or `/etc/fstab`; source sha256 and mode unchanged; protection checks of section 5.

## 10. Offline difference: source vs prepared

`virt-diff` of the kept virt-v2v output against the prepared image (both opened read-only; 69 added, 51 removed, 9 changed lines). Every entry maps to Stage 1H section 29.2:

| Difference (OBSERVED) | Intended change |
|---|---|
| Removed: the 14 first-boot entries of section 7 | C5 |
| Changed: `/etc/netplan/50-cloud-init.yaml` | C6 |
| Added: `/usr/sbin/qemu-ga`, `/etc/init.d/qemu-guest-agent`, `/etc/qemu/` (`fsfreeze-hook`, `fsfreeze-hook.d`), `qemu-guest-agent.service`, `60-qemu-guest-agent.rules`, `liburing.so.2.5` and `liburing-ffi.so.2.5` with their links, docs | C7: files owned by the two packages |
| Added: seven SysV links to `../init.d/qemu-guest-agent`: `S01qemu-guest-agent` in `rc2.d` to `rc5.d`, `K01qemu-guest-agent` in `rc0.d`, `rc1.d`, `rc6.d` (from `update-rc.d` in the postinst) | C7: package maintainer script |
| Added: `/var/lib/dpkg/info/{liburing2:amd64,qemu-guest-agent}.*`, `/var/lib/systemd/deb-systemd-helper-enabled/qemu-guest-agent.service.dsh-also`. Changed: `/var/lib/dpkg/status`, `status-old`, lock files, `triggers/Lock`, `/var/log/dpkg.log` | C7: dpkg database and log entries the install causes |
| Changed: `/etc/ld.so.cache`, `/var/cache/ldconfig/aux-cache` (the `libc-bin` trigger) | C7 incidental, the same class as C4 |
| Added: `/run/needrestart/unpacked` on the root filesystem | C7 incidental, the same class as C4 (observation O1) |

Nothing outside C5 to C7 differs.

## 11. Deviations and observations

| # | Item | Effect |
|---|---|---|
| D1 | The netplan comment lines differ from the Stage 1H section 15 design comment (they name Stage 1I Gate I1 and reference the design). The YAML keys and values are identical to the design | None on behaviour; the hash above is for this exact content |
| D2 | Stage 1H section 19 named virt-customize for the offline install. guestfish was used instead, so that the only guest writes are the explicit ones listed here (virt-customize performs its own default operations, for example seeding the random seed file) | None on the result; same libguestfs appliance, smaller and fully enumerated change set |
| O1 | The needrestart dpkg hook wrote `/run/needrestart/unpacked` into the on-disk `/run` directory. At boot a tmpfs is mounted over `/run`, so the file is hidden (INFERRED). Stage 1G already recorded `/run/needrestart` as an incidental virt-v2v change (C4) | None expected; not removed, to avoid an unlisted write |
| O2 | `qemu-guest-agent.service` is `static` (no enablement link); it is started by its udev rule when the guest-agent channel exists (INFERRED) | To be observed at boot (Gate I2 and later) |
| O3 | The two debs and the prepared netplan file remain on the host under `/srv/migration-lab/stage-1i/working/` as inputs to this record | None on the image |

No check failed, nothing was repaired after a failure, and no stop condition was reached.

## 12. Evidence

Raw evidence stays on `conversion-host-01` under `/srv/migration-lab/stage-1i/` and is not copied into this repository:

| File | Content |
|---|---|
| `evidence/stage-1i-gate-i1-evidence.txt` | Consolidated record: timestamp, host identity, source and prepared paths and hashes, qemu-img results, UUIDs, machine-id, SSH fingerprints and netplan before/after, package versions and method, dry-run summary, removed first-boot entries, nginx hashes, permissions, immutable status, scope statement |
| `evidence/verification-results.txt` | The 41 PASS/FAIL lines |
| `evidence/before-inspect.txt`, `after-inspect.txt` (+ package lists, dpkg status, nginx checksum lists) | Read-only guest inspections |
| `evidence/image-before.txt`, `image-after.txt` | `qemu-img info` (text and JSON), backing chain, `check` |
| `evidence/package-dryrun.txt`, `debs.sha256`, `package-diff.txt` | Dependency resolution and package proof |
| `evidence/modification-log.txt` | The single write step, including deb contents and maintainer scripts |
| `evidence/virt-diff-source-vs-prepared.txt` | Full offline difference |
| `evidence/legacy-source-vm-prepared.qcow2.sha256` | Authoritative hash |
| `source-verification/source-before.txt` | Source hash, mode, qemu-img info and check before the copy |

## 13. Resource impact

| Resource | Impact |
|---|---|
| AWS | **None.** No AWS CLI call, no Terraform, no EC2/VPC/EBS/KMS/IAM resource |
| Kubernetes / KubeVirt / CDI | **None.** Nothing installed, no cluster contacted |
| `legacy-source-vm` (ESXi Vmid 2) | **None.** Not contacted; still powered on |
| Stage 1E golden VMDK | **None.** Not opened |
| Stage 1G kept artifacts | Read only; source sha256 and mode unchanged |
| `conversion-host-01` | New directory `/srv/migration-lab/stage-1i/` (about 2.8 GiB); host apt indexes refreshed; temporary scripts removed from `/tmp`; no qemu process left running |
| SSH keys, sudo policy | Unchanged |

## 14. Status and next gate

- **Gate I1: PASS.** The prepared image above is the only image later Stage 1I gates may use, identified by its sha256.
- **Gate I2: PASS** (section 15), on the second run. The first run was blocked by a limitation of its test network, not by the image.
- **Gate I3: PASS** (section 16). The AWS destination platform is built, validated and left running for Gate I4.
- **Gate I4 runtime migration: PASS** (section 18). The first migrated VM runs on the AWS node and passed boot, identity, guest-agent and end-to-end HTTP validation. The VM, its DataVolume, PVC and EBS volume are kept for Gate I5.
- **Gate I4 evidence reconciliation: PASS** (section 18.12). Every required evidence section is populated. One original log (the destination-file hash check) is not reproducible and is covered by two surviving records (section 18.1).
- **Stage 1I: not complete.** Gate I5 has not started and needs explicit approval.
- The Stage 1H section 29.2 preparation record is now complete for the local gates: preparation (sections 4 to 12) and boot test (section 15).

## 15. Gate I2: pre-transfer boot test

Approval: explicitly authorized by the user, Gate I2 only. Boot the exact prepared qcow2 on `conversion-host-01` through a disposable overlay (Stage 1H section 29.5). No AWS, no Kubernetes/KubeVirt/CDI, no transfer, and no change to the prepared image.

**Result: PASS** (run 2, 54 of 54 checks).

| Run | UTC | Test network | Result |
|---|---|---|---|
| 1 | 01:40 to 01:44 | QEMU user mode, `restrict=on`, host forward 127.0.0.1:18080 to guest :80 (as specified) | **BLOCKED**: 49 of 50 checks passed; no IPv4 default route (section 15.6) |
| 2 | 01:51 to 01:55 | Isolated network namespace with a tap device and a DHCP server that offers a router, approved by the user after run 1 (section 15.7) | **PASS**: 54 of 54, including the default route; cleanup done |

Both runs used the same image, overlay model, firmware, machine, disk and guest-agent channel. They differ only in the network. Run 1 stopped under the failure rule: nothing was patched, and run 2 started only after the user chose the isolated-network option.

### 15.1 Image protection before and after

| Check | Before run 1 (01:40) | Before run 2 (01:51) | After run 2 and cleanup (01:54) |
|---|---|---|---|
| Path | `/srv/migration-lab/stage-1i/working/legacy-source-vm-prepared.qcow2` | same | same |
| sha256 | `2b30e195b50c1241aa14508fe24dd0c024af213ec19b89052ab84c6e6b4f93b2` (= I1) | identical | identical |
| Mode / owner | 0444 root:root | 0444 root:root | 0444 root:root |
| Immutable | `----i---------e-------` | same | same |
| `qemu-img info` | qcow2, 40 GiB virtual, compat 1.1, not corrupt, **no backing file** (one image in the chain) | same | file unchanged by hash |

In both runs, QEMU held the prepared image read-only (`O_RDONLY`, fd flags `02100000`) and only the overlay read-write (OBSERVED in `/proc/<pid>/fdinfo`). The image hash was also identical after each overlay instrumentation and after each power-off.

### 15.2 Test platform (both runs)

| Item | Value (OBSERVED) |
|---|---|
| Overlay | `boot-tests/<run>/overlay.qcow2`, qcow2, backing file = the prepared image (`-F qcow2`), chain depth 1; a new overlay for each run |
| Harness instrumentation (overlay only) | `serial-getty@ttyS0.service` enabled with a root-autologin drop-in, written into the overlay with guestfish, the Stage 1G model. Never written to the prepared image |
| Firmware | OVMF 2024.02-2ubuntu0.9: `OVMF_CODE_4M.fd` read-only pflash (sha256 `949bfa53...a446`); a fresh copy of `OVMF_VARS_4M.fd` (`5d2ac383...5d1e`) for each boot |
| Machine | `-machine q35,accel=kvm -cpu host -smp 2 -m 4096`, the Stage 1G pattern; no KubeVirt-specific machine or CPU pinning |
| Disk | `virtio-blk-pci`, bootindex 1 |
| NIC | `virtio-net-pci` (run 1 MAC `52:54:00:1d:00:01`, run 2 `52:54:00:1e:00:01`); no bridge to the VMware network; 192.168.50.31 never used |
| Guest agent channel | `virtio-serial-pci` + `virtserialport name=org.qemu.guest_agent.0` on a host unix socket |
| Console / control | serial on a unix socket with a log file; HMP monitor on a unix socket; `-display none -daemonize` |

Run 2 network, in full:

- Namespace `stage1i-i2` containing only `lo` and the tap device `tap-i2` (10.0.2.1/24). No route other than 10.0.2.0/24, no default route, and IPv4 forwarding off.
- QEMU ran inside the namespace with `-netdev tap,ifname=tap-i2,script=no,downscript=no`.
- DHCP came from busybox `udhcpd` (already installed, from `busybox-static` 1:1.36.1-6ubuntu3.1), offering exactly one address, 10.0.2.2, with the options subnet 255.255.255.0, router 10.0.2.1 and lease 3600 s, and **no DNS**.
- The addressing mirrors the KubeVirt masquerade guest-side network: guest 10.0.2.2/24, gateway 10.0.2.1 ([ADR 008](../adr/008-kubevirt-network-model.md)).
- The host's root network namespace (links, addresses, routes, `ip_forward=0`) was identical before and after, so the host's own networking was not changed. No package was installed.

### 15.3 Boot validation (run 2)

| # | Check | Result (OBSERVED) |
|---|---|---|
| B1 | UEFI boot | PASS: `/sys/firmware/efi` present, `efi: EFI v2.7 by Ubuntu distribution of EDK II`, `secureboot: Secure boot disabled`, `BootCurrent: 0001` (UEFI Misc Device, fallback loader as in Stage 1G) |
| B2 | multi-user reached | PASS: `multi-user.target` active (default target `graphical.target`) |
| B3 | `systemctl is-system-running` | PASS: `running` |
| B4 | Failed units | PASS: 0 |
| B5 | No `guestfs-firstboot` service runs | PASS: `Unit guestfs-firstboot.service could not be found`; 0 journal lines mention it |
| B6 | No first-boot scripts | PASS: all paths absent; whole-root search empty |
| B7 | qemu-guest-agent installed | PASS: `1:8.2.2+ds-0ubuntu1.18`, `install ok installed` |
| B8 | Agent operational over the channel | PASS: section 15.4 |
| B9 | DHCP lease | PASS: `enp0s3: DHCPv4 address 10.0.2.2/24, gateway 10.0.2.1 acquired from 10.0.2.1`. The lease has `ROUTER=10.0.2.1` and the address is flagged `dynamic`. The server logged `sending OFFER` / `sending ACK to 10.0.2.2` for MAC `52:54:00:1e:00:01`, host name `legacy-source-vm` |
| B10 | Default route | PASS: `default via 10.0.2.1 dev enp0s3 proto dhcp src 10.0.2.2 metric 100` |
| B11 | Interface up and routable | PASS: `enp0s3` (virtio_net, renamed from `eth0`, the only NIC) is up; networkd reports `routable (configured)` from `/run/systemd/network/10-netplan-primary.network` (`[Match] Driver=virtio_net`, `DHCP=ipv4`); `systemd-networkd-wait-online` succeeded; gateway 10.0.2.1 answers ping |
| B12 | No dependency on external DNS/Internet | PASS: boot reached `running`; external name resolution failed (`Could not resolve host: archive.ubuntu.com`); a probe to the lab network (`curl http://192.168.50.32/`) timed out, so the guest could not reach it |
| B13 | nginx active on :80 | PASS: enabled, active, listening on `0.0.0.0:80` and `[::]:80` |
| B14 | Host HTTP to the guest | PASS: a host process in the test namespace ran `curl http://10.0.2.2/`: `HTTP/1.1 200 OK`, `nginx/1.24.0 (Ubuntu)`, 267 bytes. Run 1 also returned 200 through the user-mode forward on 127.0.0.1:18080 |
| B15 | Response body sha256 | PASS: `b9826e18a06a354d6ba97e3419e266b1453cb2a3b0038d4b3dcd45c96c170046` (also in run 1) |

Platform evidence, OBSERVED in both runs:

- **KVM:** the QEMU process held `/dev/kvm`, `kvm-vm`, `kvm-vcpu:0` and `kvm-vcpu:1`; HMP `info kvm` reported enabled; in the guest, `systemd-detect-virt` returned `kvm` and the kernel logged `Hypervisor detected: KVM`.
- **CPU and memory:** 2 vCPU (i7-14650HX, host model) and about 4,003,700 kB MemTotal.
- **Kernel:** 6.8.0-142-generic with the unchanged command line `root=UUID=db8b3bb3-... ro`.
- **Devices:** root on `vda2` through `virtio_blk`; PCI `1af4:1001` (block), `1af4:1000` (network), `1af4:1003` (virtio console carrying the agent channel).

### 15.4 qemu-guest-agent

Inside the guest: `qemu-guest-agent.service` is `static` and `active (running)` (main process `qemu-ga`). It was started by its udev rule once `/dev/virtio-ports/org.qemu.guest_agent.0` appeared, which confirms Gate I1 observation O2.

From the host, over the `org.qemu.guest_agent.0` channel, all 8 requests were answered in each run (OBSERVED):

| Request | Response (abridged) |
|---|---|
| `guest-sync` (random id) | same id returned, first attempt |
| `guest-ping` | `{}` |
| `guest-info` | version `8.2.2`, 41 enabled commands |
| `guest-get-host-name` | `legacy-source-vm` |
| `guest-get-osinfo` | Ubuntu 24.04.5 LTS, kernel `6.8.0-142-generic`, x86_64 |
| `guest-get-fsinfo` | `vda1` vfat on `/boot/efi`, `vda2` ext4 on `/`, both on bus type `virtio` (PCI slot 2) |
| `guest-network-get-interfaces` | `enp0s3` with its MAC and DHCP address (run 2: 10.0.2.2/24) |
| `guest-get-time`, `guest-get-vcpus` | guest time; 2 vCPUs online |

### 15.5 Identity, first boot and package activity

The same results were seen in both runs (OBSERVED):

| Item | Observed in the booted guest | Baseline (I1 evidence / Stage 1C) |
|---|---|---|
| Root filesystem UUID | `db8b3bb3-e776-42e8-902e-89124606b2f6` | same |
| EFI filesystem UUID | `C340-CD01` | same |
| GPT | `gpt`; p1 `408D91CB-...5364` type EFI System; p2 `B701FE8C-...63CE` type Linux filesystem | same |
| machine-id / hostname | `d90f169b005444be82a1d703193f8324` / `legacy-source-vm` | same |
| SSH host keys | ECDSA `SHA256:9z1UPw...WHe8`, ED25519 `SHA256:7Nw9Fk...6mY`, RSA `SHA256:UXiyMj...niYg` | same |
| nginx | `nginx.conf` `48c6a4ec...0aa2`, `sites-available/default` `ce090135...b03f`, all 13 files under `/etc/nginx` identical to I1 | same |
| Page | on disk and over HTTP (guest-local and host) `b9826e18...0046` | same |
| netplan | `89ea1ea3...6a3b` | the I1 prepared file |

First boot and packages (OBSERVED):

- `guestfs-firstboot.service` not found; no enablement link; none of the five scripts; no `/usr/lib/virt-sysprep`.
- The only unit file with "firstboot" in its name is systemd's own `systemd-firstboot.service`.
- `/var/log/dpkg.log` and `/var/log/apt/history.log` were not written during either boot. The last dpkg entry is the Gate I1 install at 01:23:49.
- The boot journal contains no apt, dpkg or qemu-guest-agent install. One line matched the search pattern, and it was multipathd's `setting up paths and maps`; run 2 excluded it explicitly and counted 0.
- The stock Ubuntu `apt-daily.timer` and `apt-daily-upgrade.timer` were started, but `apt-daily.service` and `apt-daily-upgrade.service` never ran in either test.
- The guest reached `running` without contacting any package repository.

Other observations:

- **O4.** The only `err` journal lines come from the harness autologin `login` process: `PAM unable to dlopen(pam_lastlog.so)`. Ubuntu 24.04 no longer ships that module. This is harness-related, not boot-relevant.
- **O5.** In KubeVirt the guest will have a real default route and DNS. The stock apt timers and unattended-upgrades can then reach the network, for example `apt-daily-upgrade` at its next randomized time. That is outside these gates (INFERRED).

### 15.6 Run 1 blocker: no IPv4 default route under `restrict=on`

OBSERVED in run 1:

- The guest requested DHCP and received 10.0.2.15/24 from 10.0.2.2.
- The lease had no `ROUTER` and no DNS option, so systemd-networkd installed only the on-link route.
- All other run-1 checks passed.

Cause: with `restrict=on`, QEMU user-mode networking (libslirp 4.7.0-1ubuntu3.1 on this host) leaves the gateway (`RFC1533_GATEWAY`) and DNS options out of its DHCP replies; `bootp.c` adds them only `if (!slirp->restricted)` (PROJECT-DERIVED FACT from the libslirp v4.7.0 source). That test network could never satisfy the default-route check, whatever the image contained.

Gate I2 was therefore declared BLOCKED and the run stopped. No image defect was found, so a new preparation cycle was not indicated. The user then chose a host-only isolated network with a DHCP router for a second run.

### 15.7 Shutdown and cleanup

Shutdown (OBSERVED, both runs):

- ACPI `system_powerdown`, then logind `Power key pressed short` and `Powering off`, then `Reached target final.target` and `Journal stopped`.
- QEMU exited by itself with no forced quit: run 1 after 90 s of total runtime, run 2 after 87 s.
- In run 2, `udhcpd` was then stopped and the namespace deleted, which removed the tap device with it.

Cleanup after the PASS (OBSERVED):

- Deleted: both overlays (95,092,736 and 95,027,200 bytes), both OVMF variable-store copies (540,672 bytes each), the DHCP configuration, leases and log, and the run directories. QEMU had already removed its sockets and pid files on exit.
- Temporary harness files were removed from `/tmp`.
- `boot-tests/` is empty; no QEMU process, no `udhcpd` and no test namespace remain.
- The prepared image afterwards: sha256 `2b30e195...93b2`, 0444 root:root, immutable.
- ESXi Vmids 1, 2 and 3 are still powered on.

### 15.8 Evidence and resource impact

Raw evidence stays on `conversion-host-01` and is not in this repository:

| File | Content |
|---|---|
| `evidence/stage-1i-gate-i2-evidence.txt` | Final record (run 2, PASS). It covers the timestamp, host identity, image path and hashes, `qemu-img info`, QEMU parameters, firmware, test network, KVM evidence, guest kernel, CPU, memory, block and network devices, DHCP lease, default route, systemd state, guest-agent transcript, first-boot absence, HTTP result, page hash, identity, shutdown, cleanup, check results and scope |
| `evidence/stage-1i-gate-i2-run1-blocked-evidence.txt` | Run 1 record (BLOCKED) with its analysis |
| `evidence/i2-*`, `evidence/i2b-*` | Raw run files: guest serial output, guest-agent transcript, QEMU command line, monitor output, KVM file descriptors, HTTP result and page, serial log, and for run 2 the namespace state, DHCP server log and host-namespace snapshots |

| Resource | Impact |
|---|---|
| AWS / Terraform | **None** |
| Kubernetes / KubeVirt / CDI | **None** |
| Image transfer | **None** |
| `legacy-source-vm`, Stage 1E golden VMDK, Stage 1G artifacts | **None** |
| Prepared image | **Not modified**: read-only backing file only; sha256, mode and immutable flag unchanged |
| `conversion-host-01` | `scripts/i2/` (harness) and `evidence/i2*` kept; disposable test state deleted; a temporary namespace created and deleted; root network namespace unchanged; no package installed |
| SSH credentials, sudo policy | Unchanged |

## 16. Gate I3: AWS destination platform

Approval: explicitly authorized by the user, Gate I3 only. Build and validate the AWS, Kubernetes, KubeVirt, CDI and EBS CSI platform of [ADR 007](../adr/007-kubevirt-target-platform.md) with Terraform. Not approved: transferring the qcow2, creating the migrated VM, or creating its 40 GiB DataVolume or PVC (all Gate I4).

**Result: PASS.** Every check in the evidence record passed. Section 16.11 lists the deviations; none of them is open.

### 16.1 What was built

| Layer | Value (OBSERVED) |
|---|---|
| Region / AZ | ap-south-1 / ap-south-1a |
| Instance | `m8i.xlarge` (Intel Xeon 6975P-C, 4 vCPU, 16 GiB), `NestedVirtualization=enabled`, on demand |
| Node OS | CentOS Stream 9, kernel `5.14.0-754.el9.x86_64` after one `dnf update` and reboot (launched on `5.14.0-687.el9`) |
| Runtime | CRI-O 1.36.6 (crun, `cgroup_manager = "systemd"`, `selinux = true`, `device_ownership_from_security_context = true`), cri-tools 1.36.0 |
| Kubernetes | kubeadm v1.36.5 (current `stable-1.36` at build time), single node, control plane also schedulable |
| CNI | flannel v0.28.9, vxlan, pod CIDR 10.244.0.0/16; Service CIDR 10.96.0.0/12 |
| KubeVirt | v1.9.0 |
| CDI | v1.66.1 |
| CSI | AWS EBS CSI driver: release manifests of tag v1.66.0, driver image v1.65.0 (see W5); IAM through the instance profile |
| StorageClass | `ebs-gp3-encrypted` ([manifest](../../infra/kubernetes/stage-1i/storageclass-ebs-gp3-encrypted.yaml)) |

### 16.2 Terraform

- The repository had no Terraform layout yet. Gate I3 added `infra/terraform/stage-1i-target/` (`versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `user-data.yaml.tftpl`, `.terraform.lock.hcl`). These files are **not committed**, by instruction. The evidence records their sha256 against base commit `fb49917`.
- Terraform 1.16.4 with provider `hashicorp/aws` v6.67.0 ran on `kvm-learning-01` with the operator's credentials. The state is local on that host, outside Git. The AMI ID, the operator /32 and the node's public SSH key came from a variables file there, also outside Git.
- `terraform fmt -check` was clean, `validate` passed, and the plan showed 10 resources to add. Before applying, I checked the planned instance options, root volume, security-group rules, subnet and route against the approval.
- Terraform owns exactly these resources: the VPC, subnet, internet gateway, route table, route-table association, security group, IAM role and its policy attachment, instance profile, and the EC2 instance with its root volume.
  - There is no key pair resource. The node's dedicated public key is delivered by cloud-init user data.
  - No migration EBS volume is in the state.
- The final `terraform plan -detailed-exitcode` returned `No changes`.

**Attempt 1 and its replacement.** The newest AMI named `CentOS Stream 9 x86_64 20260930` (`ami-0e4f0869385c2cc95`, owner 125523088429, created 2026-10-01 01:13) booted a different system: **CentOS Stream 10** in image mode (bootc from `quay.io/testing-farm/centos-bootc:stream10`, composefs root, read-only `/usr`, default user `cloud-user`).

- This was found on the node before anything was installed.
- That image is not on the [centos.org AWS image list](https://www.centos.org/download/aws-images/), which still names `ami-0e7930d02f47291cb` (`CentOS Stream 9 x86_64 20260316`, created 2026-03-17, the AMI recorded in Stage 1H) for ap-south-1.
- Terraform replaced only `aws_instance.node` with that AMI (1 added, 1 destroyed).
- The attempt-1 instance `i-0cd317743e7f0fc5f` is terminated, and its root volume `vol-0d56abbb3c8663bc4` returns `InvalidVolume.NotFound`.
- Nothing was created outside Terraform.

### 16.3 AWS resources

| Resource | ID / value (OBSERVED) |
|---|---|
| VPC | `vpc-09a62a2c5c9563e98`, 10.40.0.0/16 |
| Subnet | `subnet-0894337e12645fb9e`, 10.40.1.0/24, ap-south-1a, no automatic public IP |
| Internet gateway | `igw-05bc20d58b9fa30bb` |
| Route table / association | `rtb-0f25f81158b1f4179` (10.40.0.0/16 local, 0.0.0.0/0 to the internet gateway) / `rtbassoc-0dcf800f209d51a57` |
| Security group | `sg-06b562ca7eacb63cb` (`stage1i-node`) |
| IAM role / instance profile | `stage1i-node` / `stage1i-node`; trust `ec2.amazonaws.com`; only `AmazonEBSCSIDriverPolicyV2` attached; no inline policy |
| EC2 instance | `i-012921f12ca5f9cfe`, `m8i.xlarge`, running, launched 02:08:10 |
| AMI | `ami-0e7930d02f47291cb`, created 2026-03-17T07:01:06Z |
| Private / public IPv4 | 10.40.1.10 (fixed in Terraform, equal to the IMDS value) / 3.6.94.104 (auto-assigned, changes if the instance is stopped) |
| Root volume | `vol-0077e3fb0d4c877a1`, 50 GiB gp3 (3000 IOPS, 125 MiB/s), **encrypted** with the `aws/ebs` key, deleted on termination. Account-level EBS default encryption is off, so encryption is explicit |
| Instance metadata | IMDSv2 required (IMDSv1 returns 401 on the node), hop limit 2 |

AWS also creates a main route table, a default security group and a default network ACL in the VPC. Terraform does not manage them, and the subnet does not use them.

There is no NAT gateway, load balancer, Elastic IP, EKS cluster or second instance.

### 16.4 Security group and exposure

| Rule | Port | Source |
|---|---|---|
| Ingress: SSH to the node's sshd | TCP 22 | operator /32 only |
| Ingress: HTTP validation NodePort | TCP 30080 | operator /32 only |
| Egress | all | 0.0.0.0/0 (packages, images, AWS APIs) |

No rule exists for 6443, guest port 22 or the CDI upload proxy.

Probes from the operator's address (OBSERVED; the Windows workstation and `kvm-learning-01` share one egress address):

- TCP 22 was open.
- TCP 6443 timed out, because the security group drops it.
- TCP 30080 was refused: the security group admits it, but no Service listens on it yet.
- TCP 10250 and 2379 were not reachable.

The Kubernetes API answered through an SSH local forward to 10.40.1.10:6443, verified with the cluster CA: `/readyz` returned `ok` and `/version` returned v1.36.5. The apiserver certificate includes 127.0.0.1 for this path.

The node accepts a dedicated ed25519 key generated on `kvm-learning-01`. That key never left the host, and no AWS credentials exist on the node.

### 16.5 Node and nested virtualization

| Check | Result (OBSERVED) |
|---|---|
| VT-x | `vmx` in all 8 CPU flag sets; `Virtualization: VT-x`, hypervisor vendor KVM (Nitro) |
| `/dev/kvm` | `crw-rw-rw- root kvm 10,232`. Present at first boot, after the reboot and at the end, so the stop condition did not apply |
| `kvm_intel` | loaded; `nested=Y`, `ept=Y`, `enable_apicv=Y` |
| `/dev/vhost-net`, `/dev/net/tun` | present (`vhost_net` and `tun` loaded and persisted) |
| `virt-host-validate qemu` | PASS for hardware virtualization (VMX), `/dev/kvm` exists and is accessible, `/dev/vhost-net`, `/dev/net/tun`, and cgroup cpu, cpuacct, cpuset, memory, devices and blkio. WARN for IOMMU (no DMAR table) and secure guest (no SEV/TDX); neither is needed here |
| cgroup | `cgroup2fs`; kubelet `cgroupDriver: systemd`; CRI-O `cgroup_manager "systemd"`; virt-handler runs in a cgroup v2 kubepods slice |
| SELinux | Enforcing, `selinux-policy-targeted-38.1.86`, `container-selinux-2.250.0` (Stage 1H required at least 2.170.0). 0 AVC denials since boot. Privileged components run as `spc_t` (virt-handler, flanneld, kube-apiserver, EBS node plugin); other pods run as `container_t` |
| Swap / forwarding | no swap; `net.ipv4.ip_forward=1`, `bridge-nf-call-iptables=1`, `bridge-nf-call-ip6tables=1`; `overlay` and `br_netfilter` loaded |
| CRI-O / kubelet | both active; RuntimeReady and NetworkReady true; kubelet `/healthz` ok |

### 16.6 Kubernetes

- `kubeadm init` used [this template](../../infra/kubernetes/stage-1i/kubeadm-config.yaml.tmpl), with the node IP filled in from the Terraform output.
  - It was initialized at 02:24:00 with the CRI-O socket, pod subnet 10.244.0.0/16 and Service subnet 10.96.0.0/12.
  - The join token was not printed.
  - The kubeconfig is set up for `ec2-user`.
- Node `ip-10-40-1-10.ap-south-1.compute.internal` is `Ready` on v1.36.5 with `cri-o://1.36.6`, and `/readyz?verbose` reports `readyz check passed`.
- flannel and both CoreDNS replicas became Ready by 02:24:37. A pod resolved `kubernetes.default.svc.cluster.local` to 10.96.0.1 and resolved `quay.io` externally, both through 10.96.0.10.
- The control-plane taint was removed at 02:27, after the node was Ready, CoreDNS had 2/2 replicas and `/readyz` passed. The node now has no taints.
- kube-apiserver runs with `--allow-privileged=true`, `--authorization-mode=Node,RBAC` and `--enable-admission-plugins=NodeRestriction`. The `kubevirt` namespace carries `pod-security.kubernetes.io/enforce=privileged`.
- These address domains don't overlap one another: VPC 10.40.0.0/16, pods 10.244.0.0/16, Services 10.96.0.0/12, masquerade 10.0.2.0/24 and the CRI-O bridge 10.85.0.0/16. CRI-O's bridge configuration ships disabled.
- All pods are Running. The 3 restarts are explained in W8.

### 16.7 KubeVirt v1.9.0

- Installed from the release's `kubevirt-operator.yaml` and `kubevirt-cr.yaml`, with no `useEmulation` and no feature gates. KubeVirt was Available at 02:31:19.
- The KubeVirt CR shows phase `Deployed`, with Available=True, Progressing=False and Degraded=False (`AllComponentsReady`). Observed and target versions are both v1.9.0.
- Components: virt-operator 2/2, virt-controller 2/2, virt-api 1/1 and the virt-handler DaemonSet 1/1. v1.9.0 also deploys virt-exportproxy 2/2 and virt-template v0.2.2.
- All 22 `kubevirt.io` CRDs are established.
- The virt-launcher image is `quay.io/kubevirt/virt-launcher:v1.9.0`.
- The node is labelled `kubevirt.io/schedulable=true` and advertises `devices.kubevirt.io/kvm`, `tun` and `vhost-net`.
- **No VirtualMachine or VirtualMachineInstance exists.**

### 16.8 CDI v1.66.1

- Installed from the release's `cdi-operator.yaml` and `cdi-cr.yaml` (feature gate `HonorWaitForFirstConsumer`). CDI was Available at 02:33:01.
- The CDI CR shows phase `Deployed`, Available=True (`DeployCompleted`), with observed and target versions both v1.66.1.
- Components: cdi-operator, cdi-apiserver, cdi-uploadproxy and cdi-deployment (the `cdi-controller` image), each 1/1.
- All 12 `cdi.kubevirt.io` CRDs are established.
- `cdi-uploadproxy` is a ClusterIP Service and is not exposed.
- **No DataVolume or PVC exists.** No image was uploaded.

### 16.9 Storage and CSI smoke test

- The EBS CSI controller (2 replicas, 6/6) and node plugin (3/3) are running. Both log `Retrieved metadata from IMDS`.
- The CSINode reports the instance ID and 31 attachable volumes.
- The manifest's optional `aws-secret` does not exist, so the driver uses only the instance profile.
- StorageClass `ebs-gp3-encrypted`:
  - provisioner `ebs.csi.aws.com`;
  - parameters `type: gp3` and `encrypted: "true"`;
  - `volumeBindingMode: WaitForFirstConsumer`, `reclaimPolicy: Delete`, `allowVolumeExpansion: true`;
  - not marked as the default class.
- CDI's StorageProfile recognized the class and reports **Block, ReadWriteOnce**, which matches ADR 009.

The CSI smoke test was temporary, small and is now deleted. It is **not** the migration disk:

| PVC (namespace `stage1i-csi-smoke`) | Mode | EBS volume | Observed |
|---|---|---|---|
| `smoke-block` | Block | `vol-091a2d3e641182187` | 1 GiB gp3, encrypted (`aws/ebs`), attached to the node |
| `smoke-fs` | Filesystem (ext4) | `vol-0f27cbe31512206bb` | 1 GiB gp3, encrypted (`aws/ebs`), attached to the node |

- Both PVCs stayed Pending until their pod was scheduled (WaitForFirstConsumer), then bound in ap-south-1a.
- One 4 MiB random payload hashed identically on the raw block device and on the filesystem.
- Deletion ran from 02:35:20 to 02:35:43: the pod, PVCs and namespace were removed, PVs and VolumeAttachments dropped to 0, and both volume IDs now return `InvalidVolume.NotFound`.
- No volume tagged `ebs.csi.aws.com/cluster` remains. The region's only volume is the node's root volume (rechecked at 02:47).

### 16.10 KubeVirt runtime defaults (observed for Gate I4, not pinned)

| Item | Observed |
|---|---|
| Machine type | Not set in the KubeVirt CR. The default `q35` is an alias of `pc-q35-rhel9.8.0` in this virt-launcher; the node advertises `pc-q35-rhel7.6.0` to `pc-q35-rhel9.8.0` |
| CPU model | Not set, so host-model applies: `host-model-cpu.node.kubevirt.io/GraniteRapids`; TSC 2.7 GHz, scalable |
| virt-launcher userland | CentOS Stream 9; virtqemud (libvirt) 11.10.0; QEMU 10.1.0 (`qemu-kvm-10.1.0-20.el9`), as Stage 1H expected |
| EFI | The image ships `OVMF_CODE.secboot.fd`, `OVMF_VARS.fd` and `OVMF_VARS.secboot.fd`. NVRAM persistence is not enabled (no feature gates). The Gate I4 VM must set `secureBoot: false` explicitly to match the Gate I2 test (INFERRED) |

The versions came from a short-lived pod running the virt-launcher image, not from a VM. That pod and its namespace were deleted.

### 16.11 Warnings and deviations

| # | Observation | Handling |
|---|---|---|
| W1 | The newest AMI named "CentOS Stream 9" booted CentOS Stream 10 in bootc image mode | Replaced through Terraform with the centos.org-listed CS9 AMI; attempt-1 resources confirmed gone (section 16.2) |
| W2 | The CS9 AMI prints no SSH host-key fingerprints to the console | Host key accepted on first use (port 22 is open only to the operator /32 and the instance was minutes old), then strict checking; fingerprint in the evidence |
| W3 | The cloud-config `hostname` line did not take effect; the hostname stays `ip-10-40-1-10...` | Harmless; not changed, because changing user data would replace the instance |
| W4 | kubeadm preflight warns that kernel `5.14.0-754.el9` is "unsupported" | A generic version-number check; EL9 is the kernel line KubeVirt's CI uses |
| W5 | The EBS CSI `stable` overlay at tag v1.66.0 deploys driver image v1.65.0 (the chart's appVersion at that tag is also 1.65.0) | Kept as published; recorded as is |
| W6 | The KubeVirt operator manifest triggers a deprecation warning for `node-role.kubernetes.io/master` | Upstream manifest; no effect |
| W7 | The first DNS test pod could not schedule while the control-plane taint was present | Harness ordering; re-run after taint removal passed |
| W8 | virt-api and both virt-controller pods restarted once at 02:32:17, exit code 0 (`Completed`), after logging "cdi api has been introduced" | KubeVirt's designed re-initialization when the CDI APIs appear; no probe failures or warning events; KubeVirt stayed Available |
| W9 | The virt-launcher image's rpm database was not readable from the observation pod | Versions taken from `virtqemud --version` and `qemu-kvm --version` |
| W10 | A harness `ausearch` call waited on stdin | Killed and re-run with `--input-logs` (read-only check) |
| W11 | IMDS hop limit 2 lets pods reach the instance role | The trade-off documented in Stage 1H section 23; the role holds only the EBS CSI policy |

### 16.12 Cost, teardown, evidence and impact

- **Running and billed:** one `m8i.xlarge`, one 50 GiB gp3 volume and one public IPv4, about USD 0.24 per hour (Stage 1H estimate). The attempt-1 instance ran about 5 minutes; the smoke volumes existed for seconds.
- **Not created:** NAT gateway, load balancer, Elastic IP, EKS, RDS, second instance or key pair.
- **Teardown** is not part of Gate I3. When it happens, follow Stage 1H section 29.1:
  1. Delete any CSI-created volumes through Kubernetes.
  2. Run `terraform destroy` in the state directory on `kvm-learning-01`.
  3. Run the detection-only check for `ebs.csi.aws.com/cluster`-tagged volumes.

Evidence is outside this repository:

| File | Content |
|---|---|
| `conversion-host-01:/srv/migration-lab/stage-1i/evidence/stage-1i-gate-i3-evidence.txt` | Gate I3 record, with a copy on `kvm-learning-01`. It covers timestamps, account and Region, Terraform version, ref and file hashes, AMI, resource IDs, security-group rules, nested virtualization, `/dev/kvm`, `virt-host-validate`, cgroup, SELinux, all component versions, StorageClass, node, KubeVirt and CDI status, smoke-test IDs and deletion, exposure probes, runtime defaults, warnings, check results and the raw logs |

| Resource | Impact |
|---|---|
| AWS | 10 Terraform-managed resources created (section 16.3); attempt-1 instance and its volume removed; smoke-test volumes created and deleted |
| `kvm-learning-01` | Terraform working directory and state, dedicated node SSH key and pinned host key under the operator's home; the operator's AWS credentials unchanged and not copied anywhere |
| Image transfer, migrated VM, migration DataVolume, migration PVC | **None** |
| `legacy-source-vm`, Stage 1E golden VMDK, Stage 1G artifacts, Stage 1I prepared qcow2 | **None** (the prepared image is still 0444 and immutable) |
| `conversion-host-01` | Only the evidence file added |

## 17. Jump-host kubectl access

Approval: explicitly requested by the user after Gate I3, as an access task only. Not part of any gate. Stage 1I is still not complete. Done on 2026-10-01 from 03:36 to 03:38 UTC.

### 17.1 Design

```text
kvm-learning-01: kubectl (KUBECONFIG=~/.kube/config-stage1i)
   |
   | https://127.0.0.1:16443   (loopback only)
   v
ssh -L 127.0.0.1:16443:127.0.0.1:6443  (systemd user service, dedicated node key)
   |
   | SSH over TCP 22, allowed only from the operator /32
   v
stage1i-node: kube-apiserver on 127.0.0.1:6443
```

- **Tunnel:** the systemd user unit `stage1i-k8s-tunnel.service` on `kvm-learning-01` runs `ssh -N -T -a -x -o ExitOnForwardFailure=yes -L 127.0.0.1:16443:127.0.0.1:6443 stage1i-node`.
  - It uses the existing Gate I3 SSH configuration: the dedicated ed25519 node key, the pinned host key, `StrictHostKeyChecking yes` and `BatchMode yes`.
  - The unit uses `Restart=always` with `RestartSec=10`, and is enabled.
  - Lingering is enabled for the operator account, so the tunnel survives logout and reboot.
- **Kubeconfig:** `~/.kube/config-stage1i` (directory mode 700, file mode 600) is a copy of the node's `/etc/kubernetes/admin.conf`. Only the cluster `server` changed, from `https://10.40.1.10:6443` to `https://127.0.0.1:16443`.
  - The rest of the file is byte-identical after normalising that line.
  - TLS is still verified against the cluster CA, because the API server certificate includes `127.0.0.1` (section 16.5).
  - No other kubeconfig existed on the host. A marked block in the operator's `~/.bashrc` exports `KUBECONFIG` for interactive shells.
- **Unchanged:** the security group, Terraform, the kubeadm configuration, KubeVirt and CDI. No software was installed; `kubectl` v1.36.5 was already present.

### 17.2 Verification (OBSERVED)

| Check | Result |
|---|---|
| Identity | `kubectl auth whoami`: `kubernetes-admin`, groups `kubeadm:cluster-admins` and `system:authenticated` |
| Node | `Ready`, v1.36.5, `cri-o://1.36.6`; client and server both v1.36.5 |
| Pods | 25 pods Running across `cdi`, `kube-flannel`, `kube-system` and `kubevirt` |
| API | `kubectl get --raw='/readyz?verbose'`: `readyz check passed` |
| KubeVirt | `kubevirt/kubevirt` phase `Deployed`, observed v1.9.0, Available=True |
| CDI | `cdi` phase `Deployed`, observed v1.66.1, Available=True |
| Migration objects | `kubectl get vm,vmi,datavolumes,pvc -A` and `kubectl get pv`: no resources |
| Listener | `127.0.0.1:16443` only, owned by the tunnel's `ssh` process; nothing on `0.0.0.0` or `[::]`; the jump host's LAN address refused 16443 (probed from the jump host and the Windows workstation) |
| Public 6443 | Node public IP port 6443 timed out from the jump host (TCP probe and `curl`, exit 28) and from the Windows workstation; port 22 open |
| Credential | The node's sshd logged `Accepted publickey for ec2-user ... ED25519` with the dedicated key's fingerprint for the tunnel sessions |
| Resilience | Killing the tunnel process led systemd to restart it (NRestarts=1); `/readyz` returned `ok` afterwards |
| AWS credentials on the node | None: no `~/.aws` for root or `ec2-user`, no `AWS_*` variables, no AWS CLI, no AWS-named Kubernetes secrets. The EBS CSI driver still uses the instance profile (section 16.9) |
| Infrastructure | Security group rules identical before and after (22 and 30080 from the operator /32, egress all); read-only `terraform plan`: `No changes` |

### 17.3 Security implications

- `~/.kube/config-stage1i` holds a **cluster-admin** client certificate, valid until 2027-10-01. Anyone who can read the operator's home on `kvm-learning-01` has full control of the cluster. Only file mode 600 and the host's own access control protect it.
  - Revoke it by deleting the file, then rotating it on the node (`kubeadm kubeconfig user` or `kubeadm certs renew admin.conf`). Removing the `kubeadm:cluster-admins` binding would revoke every admin certificate at once.
- The tunnel listens on loopback only, so any local process on `kvm-learning-01` can reach the API. It still needs a valid client certificate to authenticate.
- The tunnel is not hardened against a changed public IP. `stage1i-node` in `~/stage-1i/ssh_config` names 3.6.94.104, and stopping the instance would change that address; the unit would then keep retrying every 10 seconds.
- Gate I3's teardown should also stop and disable the unit, then delete the kubeconfig.

## 18. Gate I4: first migration to KubeVirt

Approval: explicitly authorized by the user, Gate I4 only. Transfer the prepared qcow2 to the AWS node, import it with CDI into a standalone DataVolume, create exactly one KubeVirt VM, and validate boot, guest identity, guest agent and the application end to end. Not approved: a migration controller, Forklift, application changes, a native nginx Deployment, more VMs, any change to `legacy-source-vm`, the Stage 1E golden VMDK, the Stage 1G artifacts or the prepared qcow2, a public 6443 or CDI upload proxy, committing or pushing.

| Result | Value |
|---|---|
| Gate I4 runtime migration | **PASS** |
| Evidence reconciliation | **PASS**: every required section below is populated; the one non-reproducible original record is stated in section 18.1 |

This is a cold, point-in-time migration of the Stage 1E copy with no cutover (Stage 1H section 29.8). The source VM kept running on ESXi throughout and was not contacted.

| Time (UTC) | Step |
|---|---|
| 03:47 | Pre-import cluster check; source hash re-verified on `conversion-host-01` |
| 03:51:00 to 03:56:21 | Transfer `conversion-host-01` to the node (321 s) |
| 03:56:22 to 03:56:49 | Destination sha256 check (original log lost, see section 18.1) |
| 03:56:49 to 03:56:53 | Temporary credential removed |
| 03:57:01 | DataVolume created |
| 03:58:33 | Headlamp installed by a separate operator session (section 18.11) |
| 03:57:34 to 04:03:27 | `virtctl image-upload` (21 s upload, then CDI conversion) |
| 04:04:21 | CDI scratch EBS volume deleted (CloudTrail `DeleteVolume`) |
| 04:04:35 | VM started; VMI `Running` 04:04:40; `AgentConnected` 04:04:51 |
| 04:05:59 to 04:06:35 | Guest validation, guest agent, external HTTP |
| 04:06:51 | Temporary qcow2 deleted from the node |
| 04:10 to 04:28 | Evidence reconciliation: re-collections, apt timer observation, final inventory, Terraform plan, security checks (section 18.12) |

### 18.1 Transfer

| Item | Value (OBSERVED) |
|---|---|
| Source | `conversion-host-01:/srv/migration-lab/stage-1i/working/legacy-source-vm-prepared.qcow2` (0444 root:root, immutable; read as `labadmin`, never written) |
| Destination | `stage1i-node:/var/lib/stage1i/migration/legacy-source-vm-prepared.qcow2` on the encrypted root volume; directory 0700 and file 0600, owner `ec2-user` |
| Method | Outbound SFTP from `conversion-host-01` straight to the node's sshd (egress address = the operator /32). Uploaded as `.partial`, then `chmod 600` and rename. No relay through Windows or the jump host |
| Source sha256 | `2b30e195b50c1241aa14508fe24dd0c024af213ec19b89052ab84c6e6b4f93b2`, verified immediately before and again after the transfer |
| Destination sha256 | `2b30e195b50c1241aa14508fe24dd0c024af213ec19b89052ab84c6e6b4f93b2`, 2,932,998,144 bytes, in the surviving pre-upload and pre-deletion records (see below) |
| Duration | 03:51:00.752 to 03:56:21.984, 321 s, about 9 MB/s |

**Destination hash evidence and its limitation.** The destination qcow2 was intentionally deleted after successful import. The original destination-file verification log was accidentally removed before final evidence assembly and cannot be reproduced after deletion. Surviving pre-upload and pre-deletion records independently record the same SHA-256:

| Record | When | What it recorded |
|---|---|---|
| `n-i4-06-upload` | 03:57:27, on the node, immediately before `virtctl image-upload` | `sha256=2b30e195b50c1241aa14508fe24dd0c024af213ec19b89052ab84c6e6b4f93b2` |
| `n-i4-07` | 04:06:49, on the node, immediately before deletion | `sha256 before deletion: 2b30e195b50c1241aa14508fe24dd0c024af213ec19b89052ab84c6e6b4f93b2` |

Both are original observations from the time of the action. The original check at 03:56 is not reproducible and is not presented here as a new observation.

Temporary transfer credential:

- A new ed25519 key was generated on `conversion-host-01` in `~/.stage1i-transfer/` (mode 0700, fingerprint `SHA256:fTFwkL...dh0A`). That was the only copy of the private key.
- The node received only the public key, in `ec2-user`'s `authorized_keys`, restricted to `from="<operator /32>",restrict,command="internal-sftp"`.
  - A shell command with it was refused (`This service allows sftp connections only`).
  - A local port forward through it was refused (curl exit 35).
- The client pinned the node host key (`SHA256:YTnn9B...+w8`).
- After the hash check, the public key was removed; the node's `authorized_keys` is byte-identical to its state before Gate I4. The private key was shredded and its directory removed; no key file remains on `conversion-host-01`.
- The security group was not changed (22 and 30080 from the operator /32 only).

Two transfer attempts failed before any data moved, and neither needed a fix to the image:

1. A 256 KiB SFTP buffer exceeded the node's internal-sftp message limit.
2. The 0-byte `.partial` left by attempt 1 had inherited mode 0444 from the source.

The third attempt removed the stale partial first.

### 18.2 CDI import

The data path stayed inside the cluster:

- `virtctl` v1.9.0 (release asset digest verified, equal to the server version) ran on the node as `ec2-user`, with the node's own kubeconfig, because the file was there.
- `kubectl port-forward -n cdi service/cdi-uploadproxy 18443:443 --address 127.0.0.1`; `/healthz` answered 200.
- `virtctl image-upload dv legacy-source-vm-disk --no-create --image-path=<qcow2> --uploadproxy-url=https://127.0.0.1:18443 --insecure`. `--insecure` skips verification of the proxy certificate on this loopback hop only; the forwarded stream itself runs through the authenticated API server.
- `cdi-uploadproxy` stayed ClusterIP. 18443, 8443, 443 and 6443 on the node's public IP are filtered.

The DataVolume and PVC were created and checked from `kvm-learning-01` through `~/.kube/config-stage1i`. The [DataVolume manifest](../../infra/kubernetes/stage-1i/datavolume-legacy-source-vm-disk.yaml) is standalone (`source: upload`), 40Gi, `volumeMode: Block`, ReadWriteOnce, StorageClass `ebs-gp3-encrypted`, with `cdi.kubevirt.io/storage.bind.immediate.requested: "true"` because the class is WaitForFirstConsumer.

CDI v1.66.1 used its volume-populator flow:

1. It created a prime PVC (40Gi Block) and a scratch PVC (43Gi Filesystem: 40Gi plus the 6% filesystem overhead).
2. The upload server wrote the qcow2 to scratch (read 2,932,998,144 bytes), validated it, then ran `qemu-img convert -t writeback -p -O raw /scratch/tmpimage /dev/cdi-block-volume` (03:57:57 to 04:03:23) and exited successfully.
3. The PV was rebound to the target PVC, and the prime and scratch PVCs were deleted.

| Object | Value (OBSERVED) |
|---|---|
| DataVolume | `default/legacy-source-vm-disk`, phase `Succeeded`, Bound=True, Ready=True, Running=False (`Completed`, "Upload Complete"), no restarts. It remains after success |
| PVC | `default/legacy-source-vm-disk`, `Bound`, 40Gi, Block, RWO, `ebs-gp3-encrypted`; owner reference `DataVolume/legacy-source-vm-disk` |
| PV | `pvc-87c920c1-44c5-4296-83d1-7daef98bc813`, `Bound` to `default/legacy-source-vm-disk`, reclaim `Delete`, zone ap-south-1a |
| **Migration EBS volume** | **`vol-0d94fba4ddd3d84d2`**: 40 GiB gp3 (3000 IOPS, 125 MiB/s), **encrypted** with the `aws/ebs` key, ap-south-1a, created 03:57:03. Recorded from the PV's `volumeHandle`, not from tags |
| Scratch EBS volume | `vol-0d141c818de318d0d` (43 GiB). Deleted at 04:04:21 (CloudTrail `DeleteVolume`). Its PV no longer exists, and AWS returns `InvalidVolume.NotFound` (re-collected 04:22:42 and again 04:24) |

`Succeeded` only proves that CDI finished writing. The image was proven correct by the matching transfer hash, and the guest by the checks in sections 18.4 to 18.7.

Warning events during the import, all transient and explained:

- Two `FailedScheduling` events at 03:57:01 (the scratch PVC did not exist yet; a PVC update conflict). The pod was scheduled at 03:57:06.
- `ClaimMisbound` on the prime PVC at 04:03:35, during the populator's PV rebind; the prime PVC was then deleted.
- `VolumeFailedDelete` for the scratch PV ("still attached"), which was retried until the volume detached.
- CDI emits the DataVolume `Completed` / "Upload Complete" event with type Warning.

### 18.3 VirtualMachine and Service

- **VM** [manifest](../../infra/kubernetes/stage-1i/vm-legacy-source-vm-migrated.yaml): `default/legacy-source-vm-migrated`, `runStrategy: Manual`, 1 socket x 2 cores (from the source `.vmx`), `memory.guest: 4096Mi`, EFI with `secureBoot: false`, disk `rootdisk` on the PVC with `bus: virtio`, one `model: virtio` interface with `masquerade: {}` on the pod network, ports 80 and 22. It references the PVC only, so the DataVolume owns the disk lifecycle.
- **Service** [manifest](../../infra/kubernetes/stage-1i/service-legacy-source-vm-http.yaml): `default/legacy-source-vm-http`, NodePort 80:30080 selecting the VM's launcher pod. There is no Service for guest SSH.
- Machine type, CPU model and EFI variable store were not pinned. Applied at runtime:

| Item | Observed |
|---|---|
| Machine | `pc-q35-rhel9.8.0` |
| CPU | `host-model`, resolved to `GraniteRapids`; 2 vCPUs online (libvirt allows up to 8 for hotplug: `maxSockets: 4`) |
| Memory | guest 4Gi, overhead 276Mi; launcher requests 4372Mi memory and 200m CPU (QoS Burstable) |
| Firmware | `OVMF_CODE.secboot.fd` with `secure='no'`, NVRAM from the `OVMF_VARS.fd` template (not persistent) |
| Disk | `virtio-non-transitional` block device `vda`, `cache=none`, `io=native`, `discard=unmap` |
| Interface | `tap0` into the launcher's bridge `k6t-eth0` (10.0.2.1/24); MAC `c6:ce:0d:f5:88:35` (KubeVirt-generated) |

KubeVirt runtime (OBSERVED):

- VM `Running`, `Ready=True`. VMI `Running` on the node, phases Pending to Running in 5 s; conditions Ready, DataVolumesReady, AgentConnected and StorageLiveMigratable True.
- `LiveMigratable=False` (`DisksNotLiveMigratable`: RWO disk), as designed.
- `virt-launcher-legacy-source-vm-migrated-nqq8c`: 2/2 Running, 0 restarts, pod IP 10.244.0.30, image `virt-launcher:v1.9.0`.
- No VM-related Warning event; no CrashLoopBackOff.
- The masquerade nftables rules in the pod (read through the virt-handler container) DNAT TCP 80 and 22 to 10.0.2.2 and masquerade traffic from 10.0.2.2. Their counters showed the external HTTP request and the SSH sessions.

### 18.4 Guest access path

Guest checks ran over SSH as the guest's own `labadmin`, through the Kubernetes API, with no Service and no AWS rule for port 22:

- Windows ran `ssh` with `ProxyCommand` = SSH to `kvm-learning-01`, which runs `virtctl port-forward --stdio=true vmi/legacy-source-vm-migrated/default 22`.
- The Windows private key never left Windows, and the jump host only relayed encrypted bytes.
- The guest host key was checked strictly against the ED25519 key pinned at Stage 1C (`HostKeyAlias`): an identity proof in itself.
- Root checks used `sudo -S` with the local password file over the same encrypted stream. Nothing was written to the guest disk by the harness.

### 18.5 Guest boot and network (36 of 36 checks PASS)

The 36-check validation ran at 04:05:59 with 36 passed and 0 failed. That original log file was later lost (section 18.12), so the same read-only script was re-run unchanged at 04:10:44 over the same access path, again with 36 passed and 0 failed. The values below are from the retained 04:10:44 re-collection; boot-time journal lines in it are from the single boot at 04:04:48.

| Check | Observed |
|---|---|
| UEFI boot | `/sys/firmware/efi` present; `efi: EFI v2.7 by EDK II` |
| Secure Boot | `SecureBoot` EFI variable 0; kernel `secureboot: Secure boot disabled` |
| Kernel / OS | `6.8.0-142-generic`, Ubuntu 24.04.5 LTS, `systemd-detect-virt`: `kvm`, cmdline `root=UUID=db8b3bb3-... ro` |
| systemd | `running`; `multi-user.target` active (default `graphical.target`); 0 failed units; 0 journal entries at priority err; boot 5.2 s |
| Mounts | `/` = `vda2` ext4 `db8b3bb3-e776-42e8-902e-89124606b2f6`; `/boot/efi` = `vda1` vfat `C340-CD01`; PARTUUIDs equal to Stage 1C |
| NIC | One NIC, **`enp1s0`**, driver `virtio_net`, PCI `0000:01:00.0` (renamed from `eth0`); configured by `/run/systemd/network/10-netplan-primary.network`; netplan hash `89ea1ea3...6a3b` unchanged |
| DHCP | `DHCPv4 address 10.0.2.2/24, gateway 10.0.2.1 acquired from 10.0.2.1`; lease `ROUTER=10.0.2.1`, `DNS=10.96.0.10`, search domains `ap-south-1.compute.internal`, `default.svc.cluster.local`, `svc.cluster.local`, `cluster.local`; address flagged `dynamic` |
| Default route | `default via 10.0.2.1 dev enp1s0 proto dhcp src 10.0.2.2 metric 100` |
| Gateway | 10.0.2.1 answers ping (3/3) |
| Kubernetes network | `kubernetes.default.svc.cluster.local` resolves to 10.96.0.1; `https://10.96.0.1/readyz` returns 200 from the guest |
| Internet (informational) | `archive.ubuntu.com` resolves; not required for the check |
| qemu-guest-agent | `1:8.2.2+ds-0ubuntu1.18`, `active`; channel `/dev/virtio-ports/org.qemu.guest_agent.0` present |
| First boot | No `/usr/lib/virt-sysprep`, no `guestfs-firstboot.service`; 0 dpkg entries after Gate I1 at validation time |

**Interface name: `enp1s0`, not `enp0s3`.** The requested check "enp0s3 exists" was **not met as worded**:

- In KubeVirt's q35 layout, the NIC sits behind a PCIe root port on bus 1.
- In Gate I2's plain QEMU machine, it sat on bus 0, slot 3.
- The prepared netplan matches by driver (Stage 1H section 15) precisely so that the name does not matter.
- The interface was configured, got its lease and route, and carried all traffic.

The name is recorded as a platform identity that differs.

### 18.6 Application

Inside the guest:

- `nginx` and `nginx-common` 1.24.0-2ubuntu7.18 are installed (the Stage 1C version), enabled and active.
- nginx listens on `0.0.0.0:80` and `[::]:80`, and `nginx -t` succeeds.
- All 13 files under `/etc/nginx` are identical to the Gate I1 list (combined `f6766240...9c8f`), and `sites-enabled/default` links to `sites-available/default`.
- `curl http://127.0.0.1/` returns `HTTP/1.1 200 OK`, `Server: nginx/1.24.0 (Ubuntu)`, 267 bytes, sha256 `b9826e18...0046`, and the page marker `p15-stage1c-source-v1`.

**End to end** (the primary proof): from the operator workstation, `curl http://3.6.94.104:30080/` went through NodePort, Service, the launcher pod, masquerade DNAT, guest :80 and nginx. It returned:

- **HTTP 200**, `Server: nginx/1.24.0 (Ubuntu)`, `Content-Length: 267`;
- **267 bytes**;
- sha256 **`b9826e18a06a354d6ba97e3419e266b1453cb2a3b0038d4b3dcd45c96c170046`**, with the page marker present.

### 18.7 Guest agent

KubeVirt reached the guest agent (`AgentConnected=True` 16 s after start):

- `virtctl guestosinfo`: agent 8.2.2, 41 enabled commands, host name `legacy-source-vm`, Ubuntu 24.04.5 LTS, kernel `6.8.0-142-generic`, timezone UTC, `fsFreezeStatus: thawed`.
- `virtctl fslist`: `vda1` vfat `/boot/efi` and `vda2` ext4 `/`, bus `virtio`. `virtctl userlist` returned no logged-in users.
- VMI `status.interfaces` reports source `domain, guest-agent`, `enp1s0`, the MAC, and the pod IP 10.244.0.30 (KubeVirt reports the pod address for masquerade).
- Direct agent commands through libvirt in the launcher (read-only queries) all answered:
  - `guest-ping`: `{}`;
  - `guest-get-host-name`: `legacy-source-vm`;
  - `guest-get-osinfo`;
  - `guest-get-vcpus`: 2 online;
  - `guest-get-fsinfo`: `/dev/vda1`, `/dev/vda2`;
  - `guest-network-get-interfaces`: `enp1s0` 10.0.2.2/24;
  - `guest-get-time` and `guest-get-timezone`.

### 18.8 Identity comparison

| Identity | Stage 1C / I1 / I2 | Gate I4 guest | Result |
|---|---|---|---|
| Hostname | `legacy-source-vm` | same | identical |
| machine-id | `d90f169b005444be82a1d703193f8324` | same | identical |
| Root / ESP filesystem UUID | `db8b3bb3-...` / `C340-CD01` | same | identical |
| Partition GUIDs | `408d91cb-...5364`, `b701fe8c-...63ce` | same | identical |
| SSH host keys | ED25519 `7Nw9Fk...6mY`, ECDSA `9z1UPw...WHe8`, RSA `UXiyMj...niYg` | same (also proven by strict host-key checking) | identical |
| nginx package / config | 1.24.0-2ubuntu7.18; 13 files, `f6766240...9c8f` | same | identical |
| Page | `b9826e18...0046` | same, on disk and over HTTP | identical |
| netplan | `89ea1ea3...6a3b` (prepared, C6) | same | identical |

Platform identities that naturally differ:

| Identity | Before | Gate I4 |
|---|---|---|
| Platform | ESXi Vmid 2 (source); QEMU on `conversion-host-01` (I2) | KubeVirt VMI UID `a12db97b-c453-4923-a07e-e80e23705b6e` on the AWS node |
| SMBIOS | VMware | `KubeVirt`, product UUID `763e1c9e-...786e` |
| MAC | `00:0c:29:0f:3d:15` (source) | `c6:ce:0d:f5:88:35` |
| NIC name | `ens192` (source), `enp0s3` (I2) | `enp1s0` |
| Disk | PVSCSI `sda`, VMDK | virtio `vda`, raw on EBS `vol-0d94fba4ddd3d84d2` |
| CPU | i7-14650HX (I2) | Intel Xeon GraniteRapids (host-model) |
| IP | 192.168.50.31 static (source) | 10.0.2.2 by DHCP inside the pod; pod IP 10.244.0.30; external path node:30080 |

**No IP continuity is claimed.** 192.168.50.31 still belongs to the running source VM.

### 18.9 Guest package timers (observation)

The guest's stock apt timers came with it from the source image. At 04:05:59 `apt-daily-upgrade.timer` was due at 04:18:55: a catch-up run, because the timer is `Persistent=true` and the disk carried the source VM's last-run stamp. It was left to fire and observed read-only at 04:23:10. No timer was disabled, masked or changed, no package was touched, and the VM was not rebooted.

| Timer | Present | State | Last trigger | Next trigger | Schedule |
|---|---|---|---|---|---|
| `apt-daily.timer` | yes | enabled, active | Sun 2026-09-27 13:41:16 UTC (stamp carried from the source VM) | Thu 2026-10-01 11:56:40 UTC | `6,18:00`, `RandomizedDelaySec=12h`, `Persistent=true` |
| `apt-daily-upgrade.timer` | yes | enabled, active | **Thu 2026-10-01 04:19:00 UTC** | Thu 2026-10-01 06:43:57 UTC | `6:00`, `RandomizedDelaySec=60m`, `Persistent=true` |

What the 04:19 run did (OBSERVED):

- `apt-daily-upgrade.service` ran 04:19:00 to 04:19:01 with result `success` and exit 0.
- unattended-upgrades logged `No packages found that can be upgraded unattended and no pending auto-removals`.
- No dpkg entries after Gate I1, no apt history entry, no reboot-required flag.
- Afterwards the kernel (`6.8.0-142-generic`), nginx 1.24.0-2ubuntu7.18, the page and local HTTP (200, 267 bytes, `b9826e18...0046`), the nginx tree, machine-id, hostname and root UUID were unchanged. systemd was `running` with 0 failed units.

INFERRED: `apt-daily.service` (the package-list refresh) has not run since this boot, so unattended-upgrades checked the package lists carried in the image. When `apt-daily` runs (next 11:56:40), a later `apt-daily-upgrade` may install security updates inside the migrated guest. That would make the guest drift from the Stage 1C package set. Whether to allow that is a Gate I5 or operations decision, not something Gate I4 changed.

### 18.10 Cleanup, inventory and impact

- **Temporary qcow2:** re-hashed (still `2b30e195...93b2`) and deleted from the node at 04:06:51. The empty `/var/lib/stage1i` tree was removed, and no qcow2 remains anywhere on the node's root filesystem.
- **Kept for Gate I5, by instruction:** the VM (running), the Service, the DataVolume, its PVC and PV, and EBS `vol-0d94fba4ddd3d84d2`.
- **Authoritative image:** stays on `conversion-host-01`, unchanged (0444, immutable, same sha256).
- **Left behind:** `virtctl` v1.9.0 in `/usr/local/bin` on the node and on `kvm-learning-01`.

Final AWS inventory, read-only, 04:23 to 04:25 (OBSERVED):

| AWS item | Value |
|---|---|
| Instance | `i-012921f12ca5f9cfe`, `m8i.xlarge`, running, ap-south-1a, private 10.40.1.10, public 3.6.94.104. Non-terminated instances in the region: **1** |
| Root volume | `vol-0077e3fb0d4c877a1`, 50 GiB gp3, encrypted (Terraform-managed) |
| Migration volume | `vol-0d94fba4ddd3d84d2`, 40 GiB gp3 (3000 IOPS, 125 MiB/s), encrypted, `in-use` on the instance at `/dev/xvdaa`, `DeleteOnTermination=false`. Created by the EBS CSI driver, **not in Terraform state** |
| CSI-created volumes | Only `vol-0d94fba4ddd3d84d2` remains. The scratch volume `vol-0d141c818de318d0d` is `InvalidVolume.NotFound` (CloudTrail `DeleteVolume` 04:04:21) |
| Security group | `sg-06b562ca7eacb63cb`: ingress TCP 22 and TCP 30080 from the operator /32 only, egress all. Identical to the rule set saved before the kubectl-access task |
| NAT gateways / Elastic IPs / load balancers | 0 / 0 / 0 |
| Created during I4 | Only the two CSI volumes (VM disk kept, scratch deleted). CloudTrail since 00:00 shows no other create call after Gate I3 |

**Terraform:** `terraform plan -detailed-exitcode` at 04:24 returned `No changes. Your infrastructure matches the configuration.` (exit 0). No apply, no destroy.

Final network security check (OBSERVED):

| Check | Result |
|---|---|
| Public TCP 22 | Allowed only from the operator /32; reachable from the operator network |
| Public TCP 30080 | Allowed only from the operator /32; HTTP 200 from the operator workstation (re-collected 04:26:34: 267 bytes, `b9826e18...0046`) |
| Public TCP 6443 | Not reachable (no rule) |
| CDI upload proxy | `cdi-uploadproxy` is ClusterIP 10.102.150.105:443, with no NodePort or external IP; 18443, 8443 and 443 on the public IP not reachable |
| Headlamp | ClusterIP 80 only; no NodePort, LoadBalancer or Ingress; 4466 and 80 on the public IP not reachable |
| Cluster exposure | The only NodePort is `legacy-source-vm-http` 30080. No LoadBalancer Service, no Ingress |
| New public security-group rules | **None**. CloudTrail since 00:00 shows one `CreateSecurityGroup` (02:02:34) and one `AuthorizeSecurityGroupIngress` (02:02:36), both from the Gate I3 Terraform apply, and no revoke or modify calls |

The region also holds 10 older ingress rules open to `0.0.0.0/0`, on four groups (`launch-wizard-1/2/3` and `default`) in a different VPC (`vpc-03da1af16f74334f2`). They have no attached network interfaces and pre-date Stage 1I; they were not touched. Removing them is outside Gate I4.

Cost while the VM runs: the Gate I3 baseline (about USD 0.24 per hour) plus a 40 GiB gp3 volume (INFERRED, roughly USD 0.005 per hour).

Teardown, when approved, follows Stage 1H section 29.1:

1. Stop and delete the VM and Service.
2. Delete the DataVolume.
3. Verify that the PVC, the PV and `vol-0d94fba4ddd3d84d2` are gone.
4. Then destroy with Terraform.

Evidence (outside this repository): `conversion-host-01:/srv/migration-lab/stage-1i/evidence/stage-1i-gate-i4-evidence.txt`, with a copy on `kvm-learning-01`.

| Resource | Impact |
|---|---|
| `legacy-source-vm`, Stage 1E golden VMDK, Stage 1G artifacts | **None** (not contacted or opened) |
| Prepared qcow2 | **Not modified**: read only for the hash and the transfer |
| Public exposure | 6443, the CDI upload proxy and Headlamp not exposed; security group unchanged |
| Kubernetes | Gate I4 created one DataVolume, PVC and PV, one VM and VMI, and one NodePort Service. Final counts: VM 1, VMI 1, DataVolume 1, PVC 1, PV 1. No change to KubeVirt, CDI or kubeadm configuration. Headlamp (section 18.11) is the only other workload added during this period, by a separate session |
| Credentials | Temporary transfer key created and destroyed; no AWS credentials or private keys on the node |

Final safety check, 04:25:18 to 04:25:48 (OBSERVED):

- VM `Running`, ready; VMI `Running` (same UID `a12db97b-...`); launcher `Running` with 0 restarts.
- DataVolume `Succeeded`; PVC and PV `Bound`; `vol-0d94fba4ddd3d84d2` `in-use`.
- No additional VM, DataVolume or PVC exists.
- At evidence install (04:28), the prepared qcow2 on `conversion-host-01` was still 0444 root:root, immutable, 2,932,998,144 bytes, sha256 `2b30e195...93b2`.

### 18.11 Headlamp (timing and role)

[Headlamp](https://headlamp.dev/) v0.45.0 was installed into namespace `headlamp` by a separate, parallel operator session. It is not part of Gate I4. Verified read-only:

- **Timing.** Namespace created 03:58:33, Deployment and Service 03:58:34; a rollout restart at 04:04:33 produced the current pod. Headlamp was therefore deployed **after** the migration DataVolume and PVC already existed (03:57:01), but **before** the VM, VMI and HTTP Service were created (04:04:35).
- **Headlamp did not create the migration VM/DataVolume/PVC.** The objects' field managers:
  - DataVolume: `kubectl-client-side-apply` and `cdi-controller`;
  - PVC: `cdi-controller` and `kube-controller-manager`;
  - PV: `csi-provisioner`, `csi-attacher`, `kube-controller-manager` and `cdi-controller`;
  - VM: `kubectl-client-side-apply` and `virt-controller`;
  - VMI: `virt-controller` and `virt-handler`;
  - Service: `kubectl-client-side-apply`.

  No Headlamp manager appears on any of them.
- **Permissions.** Headlamp runs as `headlamp:headlamp-viewer`, bound to ClusterRole `headlamp-viewer` (`get`, `list`, `watch` on all resources, plus `get pods/log`). `kubectl auth can-i` for that account returns `no` for creating VMs, DataVolumes or PVCs, and for deleting or patching VMs.
- **Exposure.** Service `headlamp` is ClusterIP port 80 only, with no NodePort, LoadBalancer or Ingress, and no AWS rule.

### 18.12 Evidence reconciliation

**What was lost.** About 04:10, while checking this section against the logs, a PowerShell helper named `rd` was used on the operator workstation. `rd` is a built-in alias of `Remove-Item`, and aliases take precedence over functions, so five local log files were deleted:

- `n-i4-04-verify-dest`
- `i4-06-runtime`
- `i4-04-postimport`
- `i4-04b-scratch`
- `g01-guest-validate`

The runners keep output only locally, so no other copy existed. Nothing on the guest, the cluster, AWS or any host was affected.

**How each record was reconciled:**

| Record | Class | Resolution |
|---|---|---|
| Guest validation (`g01`) | RE-COLLECTED | Same read-only script re-run at 04:10:44: 36 passed, 0 failed |
| Post-import, scratch deletion, KubeVirt runtime (`i4-04`, `i4-04b`, `i4-06`) | RE-COLLECTED | First attempt at 04:11:00 failed without reaching the cluster. The scripts had CRLF line endings, so `KUBECONFIG` ended in a carriage return and kubectl fell back to `localhost:8080`. They were converted to LF, `KUBECONFIG=/home/labadmin/.kube/config-stage1i` was set explicitly, the sanity checks passed, and they were re-run at 04:22:30 to 04:22:56. The upload-server log in it comes from the copy the import monitor captured during the import |
| Destination-file hash (`n-i4-04`) | NOT REPRODUCIBLE | Covered by the two surviving original records (section 18.1) |
| External HTTP | OBSERVED ORIGINAL plus RE-COLLECTED | The 04:06:15 console output was never saved to a file, but the response body it saved is retained (267 bytes, `b9826e18...0046`). Re-collected at 04:26:34 with the same result |
| apt timers, final AWS and Kubernetes inventory, Terraform plan, security checks, Headlamp, safety check | New read-only observations | 04:23:10 to 04:25:48 |

Every other Gate I4 log is an original observation. The evidence file labels each record as OBSERVED ORIGINAL, RE-COLLECTED, INFERRED or NOT REPRODUCIBLE, and no missing original is reconstructed.

Evidence file: `conversion-host-01:/srv/migration-lab/stage-1i/evidence/stage-1i-gate-i4-evidence.txt` (root:root 0644, 2,420 lines, sha256 `14adfb4f36d930eca64a0c731be36bea68975a2d88905ed1dccfceaf842f7db3`), with a copy in `kvm-learning-01:~/stage-1i/evidence/`.

