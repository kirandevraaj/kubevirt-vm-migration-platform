# Stage 1A: controlled ESXi reboot and post-reboot validation

**Project 1.5: VM-to-Kubernetes Migration Platform**

| Item | Value |
|---|---|
| Date | 2026-09-27 |
| Host | `esxi-8-lab.localdomain` (nested ESXi on VMware Workstation Pro 17.6.4 build-24832109) |
| Stage 0 baseline commit | `1c4fc4b` |
| Result | **PASS**. All required configuration persisted across a graceful reboot. |

Labels used in this document:

- **OBSERVED**: seen directly in command output during this stage.
- **INFERRED**: a conclusion drawn from observed facts, not directly measured.
- **NOT TESTED**: deliberately outside this stage, or not measurable here.

Times are given in UTC. The laptop runs IST (UTC+5:30); the Windows-side monitor logged IST and is converted here.

## 1. Objective

Prove that the prepared ESXi source host survives a controlled reboot and that all required configuration persists: identity, management networking, storage, time, nested virtualization, services and remote access.

This closes the Stage 0 items that were open for the source host:

- [feasibility.md](../stage-0/feasibility.md#not-yet-proven) item N2 (ESXi network/hostname/NTP config survives a controlled reboot) and feasibility row F8 (ESXi reboot persistence).
- [evidence-index.md](../stage-0/evidence-index.md) limitation L6 (ESXi config persistence across reboot untested).
- Source-side entry criterion 1 in the [Stage 0 README](../stage-0/README.md#stage-1-entry-criteria).

Stage 0 documents were not edited; this document supersedes those open items.

## 2. Scope

Allowed and performed:

- Read-only inspection before and after the reboot (`esxcli`, `vim-cmd`, `/etc/init.d/<service> status`, `chkconfig --list`, log reads).
- ESXi maintenance mode: entered before the reboot, exited after validation.
- One graceful ESXi reboot with `esxcli system shutdown reboot`.
- Windows-side reachability checks (ping, SSH, TCP/443, HTTPS GET, GitHub SSH).
- Documentation in this repository.

Not done (unchanged): no guest VM was created; the datastore, disks, VMnet8, Windows hypervisor settings, Workstation VM CPU/RAM, ESXi networking, hostname, NTP configuration, SSH keys and SSH configuration were not modified. No AWS, Kubernetes, KVM/QEMU or KubeVirt work was done. Windows and VMware Workstation were not restarted.

## 3. Pre-reboot state

Captured 2026-09-27 12:06:43 UTC over `ssh esxi-8-lab`. All values **OBSERVED**.

The `esxi-8-lab` alias resolved through the existing Windows SSH config to host 192.168.50.11, user root, port 22 (checked with `ssh -G`; the config file itself is not reproduced). Key-based login worked non-interactively (`BatchMode=yes`).

| Area | Pre-reboot value |
|---|---|
| Identity | `hostname` and `hostname -f` = `esxi-8-lab.localdomain` |
| Version | VMware ESXi 8.0.3 build-24677879, Update 3, patch 70 |
| CPU / memory | 1 package, 8 cores, 8 threads; HV Support 3; 17,178,800,128 bytes physical memory (16 GiB) |
| Management | `vmk0` 192.168.50.11 / 255.255.255.0, STATIC, gateway 192.168.50.2, DHCP DNS false |
| Routes | default -> 192.168.50.2 via vmk0 (MANUAL); 192.168.50.0/24 on vmk0 (MANUAL) |
| DNS | 192.168.50.2 |
| vSwitch | `vSwitch0`, uplink `vmnic0`, MTU 1500, port groups "Management Network" (1 client, VLAN 0) and "VM Network" (0 clients, VLAN 0) |
| NIC | `vmnic0`, nvmxnet3, admin Up, link Up, 10000 Mb/s full duplex |
| Datastore | `migration-datastore`, VMFS-6, mounted, 214,479,929,344 bytes total, 212,962,639,872 bytes free; single extent on `mpx.vmhba1:C0:T1:L0` partition 1 |
| NTP | enabled, servers 0-3.pool.ntp.org, ntpd running, Time Synchronized true, stratum 3 |
| Services | hostd running, rhttpproxy running, vpxa running, SSH started, ESXi Shell enabled, ntpd running |
| Boot policy | `chkconfig --list`: hostd, rhttpproxy, vpxa, SSH, ESXShell and ntpd all `on` (start at boot) |
| Guest VMs | `vim-cmd vmsvc/getallvms`: 0 registered; `esxcli vm process list`: 0 processes |
| Maintenance mode | Disabled |
| Uptime | 1 h 44 min |

Windows-side check before the reboot (**OBSERVED**, 2026-09-27 12:07:01 UTC):

| Check | Result |
|---|---|
| `ping 192.168.50.11` | 4/4 replies, 0% loss, <1 ms |
| `ssh esxi-8-lab "hostname"` | `esxi-8-lab.localdomain` |
| `ssh esxi-8-lab "esxcli storage filesystem list"` | `migration-datastore` mounted, VMFS-6 |
| `Test-NetConnection 192.168.50.11 -Port 443` | TcpTestSucceeded = True |

Management connectivity was healthy before the reboot.

The boot-policy check mattered: SSH is the only remote access path used here. If SSH had been set to "start and stop manually", it would not have come back after the reboot, and restoring it would have required the ESXi console and a configuration change. It was `on`, so the reboot was safe to perform.

## 4. Reboot procedure

| Step | Time (UTC) | Command / action | Outcome |
|---|---|---|---|
| 1 | before 12:07:36 | Re-checked zero registered VMs and zero VM processes | 0 and 0 (**OBSERVED**) |
| 2 | 12:07:36 | `esxcli system maintenanceMode set --enable true --timeout 120` | rc 0; `maintenanceMode get` = Enabled (**OBSERVED**) |
| 3 | 12:07:38 | Started a Windows-side monitor probing ICMP, TCP/443 and TCP/22 every 5 s (2 s TCP timeout) | Logged all-up before the reboot |
| 4 | 12:07:47 | `esxcli system shutdown reboot -d 10 -r "Stage 1A validation"` | rc 0; SSH session closed (**OBSERVED**) |
| 5 | 12:08:38 | Monitor saw ICMP, 443 and 22 all up; stopped after 3 consecutive all-up probes (12:08:48) | See section 5 |
| 6 | 12:09:03 | `ssh esxi-8-lab` login; `uptime` = 48 s; hostd `bootTime` = 2026-09-27T12:08:14.88Z | Proves a real reboot occurred (**OBSERVED**) |
| 7 | 12:09:24 onward | Full post-reboot validation (section 6) | All pass; NTP converged at 12:12:05 |
| 8 | 12:12:18 | Re-checked zero VMs; `esxcli system maintenanceMode set --enable false --timeout 120` | rc 0; `maintenanceMode get` = Disabled (**OBSERVED**) |

The monitor used a moderate interval (5 s) so the host was not flooded with connection attempts. It was not treated as proof by itself: a recovery that looked fast was cross-checked against the host's uptime, hostd `bootTime` and `/var/log/vmksummary.log`.

## 5. Downtime observed

Windows-side monitor (**OBSERVED**; each row is one probe; 1 = reachable):

| Time (UTC) | ICMP | TCP/443 | TCP/22 | Interpretation |
|---|---|---|---|---|
| 12:07:59 | 1 | 1 | 1 | Last all-up probe before shutdown |
| 12:08:04 | 1 | 0 | 0 | Services stopped; vmkernel still answering ping |
| 12:08:13 | 0 | 0 | 0 | Host fully down (the only probe without a ping reply) |
| 12:08:22 | 1 | 0 | 1 | Network and SSH back; HTTPS not yet |
| 12:08:31 | 1 | 0 | 1 | HTTPS still not ready |
| 12:08:38 | 1 | 1 | 1 | Management fully restored |

Host-side log `/var/log/vmksummary.log` (**OBSERVED**):

```text
2026-09-27T12:07:57.378Z bootstop: Host is rebooting
2026-09-27T12:08:37.621Z bootstop: Host has booted
```

| Measurement | Value | Label |
|---|---|---|
| Reboot command accepted | 12:07:47 UTC (17:37:47 IST) | OBSERVED |
| Reboot started (host log, after the 10 s delay) | 12:07:57.378 UTC | OBSERVED |
| Host reboot cycle (host log, "rebooting" to "has booted") | 40.2 s | OBSERVED |
| Management unavailable (any of ICMP/443/22 failing) | first failing probe 12:08:04, last failing probe 12:08:31: at least 27 s. Last good 12:07:59, first all-good 12:08:38: at most 39 s | OBSERVED (bounded by 5 s probe interval) |
| ICMP unavailable | one probe only (12:08:13); less than 18 s | OBSERVED (bounded) |
| SSH (TCP/22) restored | by 12:08:22 | OBSERVED |
| HTTPS (TCP/443) restored | 12:08:38; about 16 s after SSH | OBSERVED |
| ESXi management restored | 12:08:38 UTC (17:38:38 IST), matching the host log's "Host has booted" at 12:08:37.6 | OBSERVED |
| NTP synchronized again | between 12:11:05 (not synced, ntpd runtime 154 s) and 12:12:05 (synced, runtime 215 s) | OBSERVED (bounded by 60 s polling) |

The reboot was a normal reboot, not an ESXi Quick Boot: `/var/log/loadESX.log` recorded "LoadESX is not enabled. Skipping preparation." at 12:07:58Z (**OBSERVED**). The short boot time is **INFERRED** to come from a small nested host with no VMs, fast laptop storage and virtual firmware; it is not representative of physical servers.

## 6. Post-reboot state

Captured 2026-09-27 12:09:24 UTC (uptime 1 min 9 s), with NTP rechecked until 12:12:05 and a final check at 12:12:40 after exiting maintenance mode. All values **OBSERVED**.

| Area | Post-reboot value | Same as before? |
|---|---|---|
| Identity | `hostname` and `hostname -f` = `esxi-8-lab.localdomain` | Yes |
| Version | `vmware -vl`: VMware ESXi 8.0.3 build-24677879, 8.0 Update 3; `esxcli system version get`: 8.0.3, Releasebuild-24677879, Update 3, Patch 70 | Yes |
| CPU / memory | 1 package, 8 cores; HV Support 3; 17,178,800,128 bytes | Yes |
| vmk0 | 192.168.50.11, netmask 255.255.255.0, broadcast 192.168.50.255, STATIC, gateway 192.168.50.2, DHCP DNS false, enabled, MTU 1500, port group "Management Network" on vSwitch0 | Yes |
| Routes | default -> 192.168.50.2 via vmk0 (MANUAL); 192.168.50.0/24 on vmk0 | Yes |
| DNS | 192.168.50.2 | Yes |
| vSwitch0 | uplink vmnic0, MTU 1500, port groups "VM Network" and "Management Network" | Yes |
| Management Network | vSwitch0, VLAN 0, 1 active client (vmk0) | Yes |
| VM Network | vSwitch0, VLAN 0, 0 active clients | Yes |
| vmnic0 | nvmxnet3, admin Up, link Up, 10000 Mb/s full duplex | Yes |
| Datastore | `migration-datastore` mounted, VMFS-6, same VMFS UUID and extent (`mpx.vmhba1:C0:T1:L0` partition 1) | Yes |
| Capacity / free | 214,479,929,344 bytes (199.8 GB) / 212,962,639,872 bytes (198.3 GB) | Yes, byte-identical |
| Accessibility | `/vmfs/volumes/migration-datastore` symlink resolves; directory lists only VMFS system files (`.fbb.sf`, `.sbc.sf`, ...); no VM folders or ISOs | Yes |
| NTP | enabled, ntpd running; not synced at 52 s and 154 s of ntpd runtime; **synced at 215 s**; `ntp test`: "NTP is in sync", stratum 3 | Yes, after convergence |
| hostd / rhttpproxy / vpxa | running / running / running | Yes |
| SSH / ESXi Shell | SSH login started / ESX shell login enabled | Yes |
| Guest VMs | `vim-cmd vmsvc/getallvms`: 0; `esxcli vm process list`: 0 | Yes |
| Maintenance mode | Enabled after boot (it persists across reboot); Disabled after the explicit exit | Restored |

Windows-side check after the reboot (**OBSERVED**, 12:09:31 UTC onward):

| Check | Result |
|---|---|
| `ping 192.168.50.11` | 4/4 replies, 0% loss, <1 ms |
| `ssh esxi-8-lab` | key login OK; `hostname` = `esxi-8-lab.localdomain` |
| `Test-NetConnection 192.168.50.11 -Port 443` | TcpTestSucceeded = True (also True at 12:12:40 after exiting maintenance mode) |
| `curl.exe -k https://192.168.50.11/` | HTTP 200 |
| `ssh -T git@github.com` | "Hi kirandevraaj! You've successfully authenticated, but GitHub does not provide shell access." (exit code 1 is normal for this command) |

## 7. Validation matrix

| Check | Expected | Observed after reboot | Result |
|---|---|---|---|
| ESXi version | 8.0.3 build 24677879 | 8.0.3 build 24677879, U3, patch 70 | PASS |
| hostname | `esxi-8-lab.localdomain` | `esxi-8-lab.localdomain` (short and FQDN) | PASS |
| vmk0 IP | 192.168.50.11 STATIC | 192.168.50.11 STATIC | PASS |
| subnet | 255.255.255.0 | 255.255.255.0 | PASS |
| default route | 0.0.0.0/0 -> 192.168.50.2 via vmk0 | same, MANUAL | PASS |
| DNS | 192.168.50.2 | 192.168.50.2 | PASS |
| vSwitch0 + vmnic0 | vSwitch0 with uplink vmnic0, link Up | same | PASS |
| Management Network | on vSwitch0, vmk0 attached | same | PASS |
| VM Network | on vSwitch0, 0 clients | same | PASS |
| NTP | enabled, ntpd running, synchronized | enabled, running, synchronized within 215 s of ntpd start | PASS |
| migration-datastore | mounted and accessible | mounted, browsable | PASS |
| VMFS6 | VMFS-6 | VMFS-6 | PASS |
| datastore capacity / free | 199.8 GB / 198.3 GB | byte-identical to pre-reboot | PASS |
| nested HV Support | 3 | 3 | PASS |
| CPU / memory | 8 cores / 16 GiB | 8 cores / 17,178,800,128 bytes | PASS |
| hostd | running | running | PASS |
| rhttpproxy | running | running | PASS |
| vpxa | running | running | PASS |
| SSH | service started, key login works | started; key login from Windows works | PASS |
| ESXi Shell | enabled | enabled | PASS |
| HTTPS 443 | TcpTestSucceeded True | True; HTTP 200 | PASS |
| zero guest VMs | 0 registered, 0 processes | 0 and 0 | PASS |
| maintenance mode (final) | Disabled | Disabled | PASS |
| Windows -> ESXi ping | replies | 4/4, 0% loss | PASS |
| Windows -> ESXi SSH | key login works | works | PASS |
| GitHub SSH | authenticates | authenticates | PASS |

Timing summary:

| Item | Value |
|---|---|
| Reboot started at | 12:07:57.378 UTC (host log); command issued 12:07:47 UTC with a 10 s delay |
| ESXi management unavailable interval | 27 s to 39 s (Windows monitor, 5 s probes); host reboot cycle 40.2 s (host log) |
| ESXi management restored at | 12:08:38 UTC (ICMP, TCP/22 and TCP/443 all reachable) |
| NTP re-synchronized | between 12:11:05 and 12:12:05 UTC |

## 8. Evidence

Raw command output was saved on the laptop **outside the repository** in `C:\VMs\stage1a-evidence\` and is intentionally not committed. It is plain `esxcli`/`vim-cmd` output with no passwords, keys, AWS credentials or license serials, but the project rule is to commit summaries rather than raw audit output. This document is the summary.

| File (local only) | Content |
|---|---|
| `01-pre-reboot-baseline.txt` | Pre-reboot identity, CPU, memory, storage, network, NTP, VMs, maintenance mode |
| `02-pre-reboot-services.txt` | Service status and `chkconfig` boot policy |
| `03-pre-reboot-windows.txt` | Windows ping, SSH, filesystem list, TCP/443 |
| `04-reboot-monitor.log` | Windows-side ICMP / TCP/443 / TCP/22 probes during the reboot |
| `05-enter-maintenance.txt`, `06-reboot-command.txt` | Maintenance mode entry and reboot command output |
| `07-post-reboot-validation.txt` | Full post-reboot validation |
| `08-post-reboot-windows.txt` | Windows ping, SSH, TCP/443, HTTPS, GitHub SSH |
| `09-post-reboot-ntp.txt` | NTP convergence polling |
| `10-exit-maintenance.txt`, `11-final-state.txt` | Final NTP test, VM recheck, maintenance mode exit, final health |
| `12-boot-log-check.txt` | `vmksummary.log` and `loadESX.log` excerpts |

## 9. Result

**PASS (OBSERVED).** The ESXi source host survived a graceful, controlled reboot. Identity, version, static management networking, routes, DNS, vSwitch and port groups, the uplink, the VMFS-6 datastore (byte-identical free space), nested virtualization support, services and their boot policy, and SSH key access all persisted. NTP re-synchronized automatically within about 3.5 minutes. HTTPS management returned. No guest VM exists. Maintenance mode was exited and the host is back in its normal operating state.

What this does **not** prove (**NOT TESTED**):

- A 64-bit nested guest (L2) booting on this host (Stage 0 item N1). That is the first check of Stage 1B.
- Behavior after a laptop reboot, a Windows update, a VMware Workstation restart, or an unclean power-off. Only a graceful ESXi reboot was tested.
- Anything on the destination side (AWS, Kubernetes, KubeVirt, CDI).

## 10. Lessons learned

1. **Check service boot policy before rebooting a host you reach only by SSH.** `chkconfig --list` showed SSH `on`. Had it been manual, the reboot would have cut off remote access.
2. **Ping is not readiness.** The host answered ping while its services were already stopped (12:08:04), and after boot ping and SSH returned about 16 s before HTTPS/443 (hostd and rhttpproxy). Readiness needs ICMP, TCP/22, TCP/443 and a real login.
3. **A fast recovery must be proven to be a real reboot.** The ~40 s cycle looked too quick, so it was cross-checked with `uptime`, hostd `bootTime` and `vmksummary.log`, and `loadESX.log` confirmed it was not a Quick Boot.
4. **NTP needs time after boot.** An immediate check reports "Time Synchronized: false" and "NTP never was synchronized", which is normal. It synced between 154 s and 215 s of ntpd runtime. Post-boot validation should poll NTP for several minutes before failing it.
5. **Maintenance mode survives a reboot.** The host came back in maintenance mode and needed an explicit exit. Leaving it enabled would block powering on VMs in Stage 1B.
6. **Windows PowerShell 5.1 has no `Invoke-WebRequest -SkipCertificateCheck`.** Use `curl.exe -k` for an HTTPS check against a self-signed ESXi certificate.
7. **Nested boot timing is not production timing.** About 40 s here; physical servers with firmware POST and more devices take much longer.

## 11. Stage 1B entry criteria

Stage 1B (the first source VM) may begin only when all of the following hold:

1. The user has reviewed this Stage 1A result and explicitly approved starting Stage 1B.
2. Stage 1B scope and change boundary are written down. Creating a VM and uploading an ISO to `migration-datastore` are changes that Stage 1A did not allow; Stage 1B must allow them explicitly.
3. Guest OS, version, ISO source and checksum, and VM sizing are chosen, within the nested budget (at most 8 vCPU per VM; about 14 GB RAM shared by all nested VMs).
4. The ISO upload path on `migration-datastore` and the VM's port group ("VM Network" on vSwitch0) are agreed, and a static-safe IP for the guest is chosen (avoid 192.168.50.10, .20 and .25).
5. The first Stage 1B check is a nested 64-bit guest boot (Stage 0 item N1). If it fails, stop and report before any other work.
6. The host remains in the state recorded here: maintenance mode disabled, zero guest VMs, NTP synchronized, SSH key access working, Windows hypervisor still off.
