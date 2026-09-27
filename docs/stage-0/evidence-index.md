# Stage 0 evidence index

Request section 25. This index records **summarized** facts, not raw audit output. It deliberately excludes passwords, private keys, AWS credentials, license serials, SSH key material and VM images. The raw audit file on the laptop (which contains the license serial) is not copied into Git.

Sources of evidence:

- **E-SSH**: read-only commands over `ssh esxi-8-lab` on 2026-09-27 (for example `vmware -vl`, `esxcli system hostname get`, `esxcli network ip interface ipv4 get`, `esxcli network vswitch standard list`, `esxcli storage filesystem list`, `esxcli hardware cpu global get`, `vim-cmd vmsvc/getallvms`, NTP status). Nothing was changed on the host.
- **E-HANDOFF**: [project1-5-context-handoff.md](../project-context/project1-5-context-handoff.md), items marked OBSERVED there (laptop, Windows and Workstation facts that Stage 0 did not re-check).
- **E-DOCS**: current official documentation, linked in each document.

## 1. Current ESXi configuration

| Item | Value | Evidence |
|---|---|---|
| Product / version | VMware ESXi 8.0.3, Update 3 (U3e), Releasebuild-24677879 | E-SSH |
| Image profile | ESXi-8.0U3e-24677879-standard | E-HANDOFF |
| License edition | "vSphere 8 Hypervisor" (free), `vsmp:8`; serial intentionally not recorded | E-HANDOFF |
| Hostname / FQDN | `esxi-8-lab.localdomain` (no DNS record; no hosts-file entry) | E-SSH |
| Management | Standalone host, no vCenter | E-HANDOFF |
| Guest VMs | None (`vim-cmd vmsvc/getallvms` returns no VMs) | E-SSH |
| SSH / ESXi Shell | Enabled; key-based login via the `esxi-8-lab` SSH alias works | E-SSH |
| NTP | Enabled, in sync, `0-3.pool.ntp.org` | E-SSH |
| Maintenance mode | Disabled | E-HANDOFF |

Observation only: the ntpd process runtime at the check suggested a daemon restart roughly one hour earlier. No action taken; recorded for the reboot-persistence follow-up.

## 2. Datastore

| Item | Value | Evidence |
|---|---|---|
| Name / type | `migration-datastore`, VMFS-6 | E-SSH |
| Mount | `/vmfs/volumes/migration-datastore` | E-SSH |
| Capacity | 214,479,929,344 bytes (199.8 GB) | E-SSH |
| Free | 212,962,639,872 bytes (198.3 GB) | E-SSH |
| Contents | Empty (no VMs, no ISOs) | E-SSH |
| Backing | Second virtual disk of the Workstation VM (200 GiB thin VMDK on the laptop) | E-HANDOFF |
| Other volumes | OSDATA, BOOTBANK1, BOOTBANK2 (system only; not for VM files) | E-SSH |

## 3. Management network

| Item | Value | Evidence |
|---|---|---|
| VMkernel interface | `vmk0`, port group "Management Network", VLAN 0 | E-SSH |
| Address | 192.168.50.11/24, STATIC | E-SSH |
| Gateway / DNS | 192.168.50.2 (VMware NAT), DHCP DNS false | E-SSH |
| vSwitch | `vSwitch0`, uplink `vmnic0`, MTU 1500 | E-SSH |
| Port groups | "Management Network" (vmk0), "VM Network" (0 clients) | E-SSH |
| Upstream conflict | 192.168.50.10, .20, .25 answer from the ISP side; avoid them | E-HANDOFF |
| Laptop side | VMnet8 NAT 192.168.50.0/24, host adapter .1, DHCP .128-.254 | E-HANDOFF |

## 4. Nested virtualization

| Layer | Evidence | Source |
|---|---|---|
| L0 laptop CPU | Intel i7-14650HX, VT-x + SLAT enabled | E-HANDOFF |
| Windows | Hypervisor off (`hypervisorlaunchtype Off`), `HypervisorPresent = False`, VBS/HVCI off | E-HANDOFF |
| Workstation | 17.6.4, `Monitor Mode: CPL0`, `hv-vt.vmm` + `gphys-ept.vmm` loaded | E-HANDOFF |
| ESXi VM setting | `vhv.enable = "TRUE"` | E-HANDOFF |
| ESXi view | `esxcli hardware cpu global get` -> `HV Support: 3` (VT-x present and enabled) | E-SSH |
| L2 guest | Not tested (no guest VMs) | - |
| AWS target | Nested virtualization documented for virtual EC2 instances since 2026-02-16; not tested | E-DOCS |

## 5. Host resource constraints

| Resource | Value | Evidence |
|---|---|---|
| Laptop RAM | 32 GB (31.71 GB usable); ~16 GB free with ESXi running | E-HANDOFF |
| Laptop disk | ~434 GB free on C: | E-HANDOFF |
| ESXi VM | 8 vCPU (1 socket x 8 cores), 16 GB RAM, UEFI | E-HANDOFF, E-SSH |
| Nested guest budget | 8 vCPU / ~14 GB shared by all nested VMs; max 8 vCPU per VM (license) | E-HANDOFF, E-DOCS |
| CPU topology | Hybrid P/E cores; vCPU performance varies | E-HANDOFF (INFERRED) |

## 6. Known limitations

| # | Limitation | Impact |
|---|---|---|
| L1 | Windows hypervisor must stay off for VHV | WSL2 and Docker Desktop unavailable; no local Linux tooling for conversion |
| L2 | AWS credentials only in Docker volume `platform-aws-tools-aws` | Cloud work blocked until recovered or re-issued |
| L3 | Free ESXi: API unsupported / possibly read-only; no vCenter; no VADP | MTV/VDDK/CBT paths unreliable; cold via SSH instead |
| L4 | Single flat network on vSwitch0 / VMnet8 | Source VM shares management L2; fine for the lab |
| L5 | 192.168.50.0/24 overlaps the ISP side | Use static-safe addresses only |
| L6 | ESXi config persistence across reboot untested | Test before relying on the host long-term |
| L7 | Nested 64-bit guests untested | Prove with the first source VM |
| L8 | Nested virtualization everywhere | Performance numbers are not representative of production |

## 7. What Stage 0 did not touch

No change was made to ESXi, its datastore, VMware networking, Windows virtualization settings, AWS, or any Kubernetes cluster. No VM, cluster, CRD or AWS resource was created.
