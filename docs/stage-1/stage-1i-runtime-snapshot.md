# Stage 1I: pre-I5 runtime learning snapshot

| Field | Value |
|---|---|
| Project | Project 1.5: VM-to-Kubernetes Migration Platform |
| Stage | 1I, after Gate I4 and **before Gate I5**. Stage 1I was not complete when this snapshot was taken; Gate I5 passed later the same day and Stage 1I is complete (2026-10-01) |
| Date | 2026-10-01, 11:04:45 to 11:05:57 UTC |
| Nature | **Read-only learning snapshot.** It is not a gate and not an I5 result. Gate I5-A (final runtime validation) ran separately afterwards, at 11:19 UTC ([Stage 1I record, section 19](stage-1i-first-kubevirt-migration.md#19-i5--final-validation-and-controlled-teardown)) |
| Changed | Nothing in AWS, Kubernetes, KubeVirt, the node's network or the VM. No create, patch or delete; no rule, route, link or Service change; no `qemu-agent-command` and no `qemu-monitor-command` |
| Evidence | `kvm-learning-01:~/stage-1i/evidence/stage-1i-pre-i5-runtime-snapshot.txt` (817 lines, sha256 `366dd345afcd9d198dd7160e6dbdb7d8d8ab4de620a9cd643248bc1f5ed06f94`), with a copy on the operator workstation. Outside Git |
| Related | [Stage 1I record](stage-1i-first-kubevirt-migration.md) (Gate I4: section 18), [Stage 1I visual](stage-1i-visual-learning.html), [ADR 008](../adr/008-kubevirt-network-model.md), [ADR 009](../adr/009-kubevirt-storage-model.md) |

Labels: **OBSERVED** = seen in this snapshot by a command we ran. **INFERRED** = reasoned from observations or documentation, not directly tested.

## 1. Method

| Viewpoint | Access path | Commands (all read-only) |
|---|---|---|
| Kubernetes, KubeVirt, libvirt | `kvm-learning-01`, `kubectl` through the loopback tunnel (`~/.kube/config-stage1i`) | `get`, `virtctl guestosinfo`, and `kubectl exec ... -c compute` for `virsh` queries, `ps`, `ip`, `ls`, `stat`, `blockdev --getsize64` |
| Node | `kvm-learning-01`, then `ssh stage1i-node`, with `sudo` | `crictl ps/inspect`, `ps`, `/proc` reads, `lsblk`, `ip`, `bridge link`, `ss`, `iptables-save -c`, and `nft list ruleset` in the launcher's network namespace through the virt-handler container |
| Guest | Windows SSH through `virtctl port-forward --stdio` (Gate I4 section 18.4), as `labadmin`, **no sudo** | `ip`, `networkctl`, `lsblk`, `systemctl is-active`, `ss`, `curl 127.0.0.1`, `sha256sum`, and the nginx access log (client field only) |
| Application | Operator workstation | `curl http://3.6.94.104:30080/` (one request, 11:05:43.226) |

Scripts were piped over SSH on stdin, so no file was written to the node or the guest. The operator /32 does not appear in the evidence, which was scanned for it and for credential patterns (0 hits).

## 2. VM and VMI (OBSERVED)

| Item | Value |
|---|---|
| VirtualMachine | `default/legacy-source-vm-migrated`, uid `4332b0ee-1f50-4faa-85d4-6c49762e4791`, `runStrategy: Manual`, `printableStatus: Running`, `ready: true`. **No ownerReferences** (top of the chain) |
| VM conditions | Ready=True, DataVolumesReady=True (`AllDVsReady`), LiveMigratable=False (`DisksNotLiveMigratable`), StorageLiveMigratable=True, AgentConnected=True |
| VirtualMachineInstance | uid `a12db97b-c453-4923-a07e-e80e23705b6e` (same as Gate I4), phase `Running` on `ip-10-40-1-10.ap-south-1.compute.internal`, machine `pc-q35-rhel9.8.0`, QoS Burstable, launcher image `virt-launcher:v1.9.0` |
| VMI owner | `VirtualMachine/legacy-source-vm-migrated` (uid `4332b0ee-...`), `controller=true`, `blockOwnerDeletion=true` |
| VMI phases | Pending and Scheduling 04:04:35, Scheduled 04:04:38, Running 04:04:40. No restart since |
| VMI interface | `default` / `enp1s0`, MAC `c6:ce:0d:f5:88:35`, IP `10.244.0.30` (the Pod IP, as KubeVirt reports for masquerade), info source `domain, guest-agent` |
| Topology / memory | 1 socket x 2 cores x 1 thread; guest 4Gi at boot, current and requested; overhead 276Mi |
| Guest agent | `virtctl guestosinfo`: agent 8.2.2, 41 enabled commands, host name `legacy-source-vm`, Ubuntu 24.04.5 LTS, kernel `6.8.0-142-generic`, timezone UTC, `fsFreezeStatus: thawed` |

## 3. virt-launcher Pod (OBSERVED)

| Item | Value |
|---|---|
| Pod | `default/virt-launcher-legacy-source-vm-migrated-nqq8c`, uid `2d5418a6-60a2-4634-ad31-214ed77794a0`, 2/2 Running, 0 restarts, created 04:04:35 |
| Pod IP / host IP | `10.244.0.30` / `10.40.1.10` (not host network) |
| Controlled by | `VirtualMachineInstance/legacy-source-vm-migrated` (uid `a12db97b-...`), `controller=true`, `blockOwnerDeletion=true`. Label `kubevirt.io/created-by` = the VMI uid |
| Identity | Runs as uid/gid 107 (`qemu`), `runAsNonRoot: true`, `fsGroup: 107`, service account `default` with token automount **off** |
| Native sidecar | Init container `guest-console-log` with `restartPolicy: Always` (a Kubernetes native sidecar): `/usr/bin/virt-tail`, all capabilities dropped, limits 15m CPU and 60M memory, mounts `/var/run/kubevirt-private` read-only. Running, 0 restarts |
| Main container | `compute`: `/usr/bin/virt-launcher-monitor --qemu-timeout 342s ...`; drops all capabilities and adds only `NET_BIND_SERVICE`; no privilege escalation |
| Device access | Requests and limits `devices.kubevirt.io/kvm: 1`, `devices.kubevirt.io/tun: 1`, `devices.kubevirt.io/vhost-net: 1` (device plugins on the node advertise 1k of each). Inside `compute`: `/dev/kvm` (10,232), `/dev/net/tun` (10,200), `/dev/vhost-net` (10,238), all owned by `qemu` |
| Root disk | Pod volume `rootdisk` = PVC `legacy-source-vm-disk`, attached as **`volumeDevice` `/dev/rootdisk`** (block 259:3, 42,949,672,960 bytes), not as a mounted filesystem |
| Other volumes | `emptyDir` only: `private`, `public`, `sockets`, `virt-bin-share-dir`, `libvirt-runtime`, `ephemeral-disks`, `hotplug-disks` |
| Requests | `compute`: 200m CPU, 4372Mi memory, 50M ephemeral storage |

Processes in `compute` (OBSERVED, `ps`): `virt-launcher-monitor` (PID 1), `virt-launcher` (8), `virtqemud` (17), `virtlogd` (18) and `qemu-kvm` (73, about 960 MiB RSS), all as `qemu`, up 7 h. A `sh` process (PID 123) has been running since about 04:36 UTC. It was most likely left by an earlier interactive `kubectl exec`; its origin was not determined, and it was not touched (observation O2).

## 4. QEMU and libvirt runtime (OBSERVED)

`virsh` ran inside `compute` with its default connection, query commands only:

| Command | Result |
|---|---|
| `virsh dominfo` | Id 1, `default_legacy-source-vm-migrated`, UUID `763e1c9e-9197-4459-9561-7e1ac4d7786e`, `hvm`, running, 2 CPUs, 4,194,304 KiB, persistent, security model `none`. Message: `tainted: custom guest agent control commands issued` (observation O1) |
| `virsh domstate --reason` | `running (booted)` |
| `virsh domiflist` | `tap0`, type `ethernet`, model `virtio-non-transitional`, MAC `c6:ce:0d:f5:88:35` |
| `virsh domblklist --details` | `block disk vda /dev/rootdisk` |
| `virsh domifaddr --source agent` | `lo` 127.0.0.1/8; **`enp1s0` `c6:ce:0d:f5:88:35` 10.0.2.2/24**, fe80::c4ce:dff:fef5:8835/64 |
| `virsh domhostname` | `legacy-source-vm` |
| `virsh domfsinfo` | `/` on `vda2` ext4, `/boot/efi` on `vda1` vfat, both on target `vda` |

Live domain XML (`virsh dumpxml`; full text in the evidence):

| Element | Value |
|---|---|
| Domain type | `kvm` |
| Firmware | `OVMF_CODE.secboot.fd`, pflash, read-only, **`secure='no'`**; NVRAM from `OVMF_VARS.fd` in `/var/run/kubevirt-private/...` (an `emptyDir`, so not persistent) |
| Machine / CPU | `pc-q35-rhel9.8.0`; `cpu mode='custom'` model `GraniteRapids` (the resolved host-model), `vmx` required; vCPUs current 2, maximum 8 (sockets 4 x cores 2, hotplug headroom); memory 4 GiB, `maxMemory` 16 GiB |
| Disk | `type='block'`, `raw`, `cache='none'`, `io='native'`, `discard='unmap'`, `error_policy='stop'`, source `/dev/rootdisk`, target `vda` on virtio, boot order 1, PCI bus 0x07 |
| NIC | `type='ethernet'`, `tap0` (`managed='no'`), virtio-non-transitional, MTU 8951, PCI bus 0x01 |
| Guest agent channel | `org.qemu.guest_agent.0`, `state='connected'` |
| Other devices | `isa-serial` console with log file, VNC on a unix socket, bochs video, `itco` watchdog with `action='reset'`, virtio balloon with `freePageReporting='on'` and 10 s stats; `on_crash` destroy |

**qemu-kvm process** (OBSERVED):

- Inside `compute`: PID 73, `/usr/libexec/qemu-kvm -name guest=default_legacy-source-vm-migrated`.
- Arguments that matter here:
  - `-accel kvm`;
  - `-machine pc-q35-rhel9.8.0,...`;
  - `-cpu GraniteRapids,vmx=on,...`;
  - `-m size=4194304k,maxmem=16777216k`;
  - `-smp 2,maxcpus=8`;
  - `-blockdev {"driver":"host_device","filename":"/dev/rootdisk","aio":"native","cache":{"direct":true}}`;
  - `-device virtio-blk-pci-non-transitional` (bus `pci.7`, `bootindex` 1);
  - `-netdev tap,fd=21,vhost=true,vhostfd=23`;
  - `-device virtio-net-pci-non-transitional,host_mtu=8951,mac=c6:ce:0d:f5:88:35`;
  - `virtserialport name=org.qemu.guest_agent.0`;
  - `virtio-balloon-pci-non-transitional,free-page-reporting=true`;
  - `-sandbox on,...`.
- On the node: PID 48109, uid 107, child of the `compute` container's PID 1 (47951). Its cgroup is the `compute` container scope under `kubepods-burstable-pod2d5418a6...`. SELinux label `system_u:system_r:container_t:s0:c306,c428`.
- Threads: 6, including two vCPU threads, `CPU 0/KVM` and `CPU 1/KVM`.

**KVM acceleration confirmed** (OBSERVED):

- The domain is `type='kvm'` and QEMU runs with `-accel kvm`.
- The QEMU process holds `/dev/kvm`, `anon_inode:kvm-vm`, `anon_inode:kvm-vcpu:0` and `kvm-vcpu:1`, plus two `kvm-vcpu-stats` descriptors.
- On the node, `kvm_intel` is loaded with `nested=Y` and `ept=Y`, and `vmx` appears in all CPU flag sets.
- Inside the guest, `systemd-detect-virt` returns `kvm`.
- The process also holds `/dev/net/tun` and `/dev/vhost-net`, so the virtio-net data path uses vhost-net.

## 5. Network (OBSERVED)

| Place | Interface | Address / role |
|---|---|---|
| Node | `eth0` | 10.40.1.10/24, default via 10.40.1.1 (VPC). Public 3.6.94.104 is the AWS public IPv4 mapped to it (not configured on the node) |
| Node | `cni0` | 10.244.0.1/24, the flannel bridge for this node's pod CIDR 10.244.0.0/24 |
| Node | `flannel.1` | 10.244.0.0/32 (vxlan backend; unused on a single node) |
| Node | `vethdc326847` (ifindex 33) | Member of `cni0`; peer of the pod's `eth0@if33` |
| Pod netns | `eth0` | **10.244.0.30/24**, MAC `c6:ce:0d:f5:88:35`, MTU 8951, default via 10.244.0.1 |
| Pod netns | `k6t-eth0` | Linux bridge, **10.0.2.1/24** (the guest's gateway and DHCP server), `nf_call_iptables 0` |
| Pod netns | `tap0` | Port of `k6t-eth0`; tap device owned by uid/gid 107, `vnet_hdr on`, no IP address |
| Pod netns | routing | `10.0.2.0/24 dev k6t-eth0 src 10.0.2.1`; `ip_forward=1` |
| Guest | `enp1s0` | **10.0.2.2/24**, driver `virtio_net`, the same MAC `c6:ce:0d:f5:88:35`, MTU 8951 |
| Guest | routing | `default via 10.0.2.1 dev enp1s0 proto dhcp`; DNS 10.96.0.10 via 10.0.2.1; `networkd` state `routable`; the gateway answers ping (2/2) |

| Kubernetes object | Value |
|---|---|
| Service | `default/legacy-source-vm-http`, type NodePort, ClusterIP **10.108.249.186**, port 80, targetPort 80, **nodePort 30080**, TCP, `externalTrafficPolicy: Cluster`, selector `project15/vm=legacy-source-vm-migrated` |
| EndpointSlice | `legacy-source-vm-http-4l5jh`: endpoint **10.244.0.30**, ready and serving, target `Pod/virt-launcher-legacy-source-vm-migrated-nqq8c` |
| kube-proxy | v1.36.5, `mode: ""` (the iptables default on Linux); chains `KUBE-SVC-CUH6W56T6REYHCCZ`, `KUBE-EXT-CUH6W56T6REYHCCZ`, `KUBE-SEP-5ZPMA3TJSODRA262` |
| Exposure | The only NodePort or LoadBalancer Service in the cluster is `legacy-source-vm-http` 30080. Nothing on the node listens on a socket for 30080; the port exists only as NAT rules |
| Successful request | From the operator workstation at 11:05:43.226: **HTTP/1.1 200 OK**, `Server: nginx/1.24.0 (Ubuntu)`, 267 bytes, sha256 **`b9826e18a06a354d6ba97e3419e266b1453cb2a3b0038d4b3dcd45c96c170046`**, page marker `p15-stage1c-source-v1` present, 46.7 ms |

## 6. Storage chain (OBSERVED)

```text
DataVolume default/legacy-source-vm-disk    phase Succeeded, source upload, no ownerReferences
  | owns (controller=true, blockOwnerDeletion=true)
PVC default/legacy-source-vm-disk           Bound, 40Gi, volumeMode Block, RWO, ebs-gp3-encrypted
  | spec.volumeName
PV pvc-87c920c1-44c5-4296-83d1-7daef98bc813 Bound, csi ebs.csi.aws.com, reclaim Delete, zone ap-south-1a, no fsType
  | csi.volumeHandle
EBS vol-0d94fba4ddd3d84d2                   VolumeAttachment attached=true, devicePath /dev/xvdaa
  | NVMe on the node
/dev/nvme1n1  259:3  40G  serial vol0d94fba4ddd3d84d2  "Amazon Elastic Block Store"
  | Pod volumeDevice "rootdisk" (Block mode: the node never mounts it)
/dev/rootdisk  block 259:3 in the compute container, 42,949,672,960 bytes
  | libvirt <disk type='block'> raw, cache=none, io=native, discard=unmap
qemu-kvm -blockdev host_device /dev/rootdisk (QEMU fd 14) -> virtio-blk-pci-non-transitional (bus pci.7)
  | guest kernel virtio_blk, PCI 0000:07:00.0
vda 253:0 40G  ->  vda1 vfat /boot/efi (C340-CD01), vda2 ext4 / (db8b3bb3-e776-42e8-902e-89124606b2f6)
```

- The exact migration EBS volume is **`vol-0d94fba4ddd3d84d2`**, taken from the PV's `volumeHandle` and matched on the node by NVMe serial and major:minor 259:3.
- The node's root volume is `vol-0077e3fb0d4c877a1` (`nvme0n1`, 50G).
- The StorageClass is `ebs-gp3-encrypted`: `type: gp3`, `encrypted: "true"`, WaitForFirstConsumer, reclaim Delete, expansion allowed.
- Counts: 1 VM, 1 VMI, 1 DataVolume, 1 PVC, 1 PV. No Warning event in `default`.
- The node's `lsblk` also lists `loop0` (40G), and `/dev/disk/by-id` shows `-part1`/`-part2` links for the migration volume: the host kernel reads the guest's GPT. The loop device is kubelet's usual pinning of a Block-mode volume (INFERRED, not traced).

## 7. Guest (OBSERVED, as `labadmin`)

| Item | Value |
|---|---|
| OS / kernel | Ubuntu 24.04.5 LTS (noble), `6.8.0-142-generic` x86_64; DMI vendor `KubeVirt`; `systemd-detect-virt`: `kvm` |
| Boot | 2026-10-01 04:04:47, up 7 h 1 min; `systemctl is-system-running`: `running`, 0 failed units |
| Identity | Host name `legacy-source-vm`, machine-id `d90f169b005444be82a1d703193f8324`, root UUID `db8b3bb3-...`, ESP `C340-CD01` (all as in Stage 1C) |
| Interface / IP / route | `enp1s0` (virtio_net), 10.0.2.2/24, default via 10.0.2.1 (section 5) |
| qemu-guest-agent | `1:8.2.2+ds-0ubuntu1.18`, active since 04:04:49; `/dev/virtio-ports/org.qemu.guest_agent.0` present |
| nginx | `1.24.0-2ubuntu7.18`, active and enabled, listening on `0.0.0.0:80` and `[::]:80` |
| Content | Page on disk and local HTTP: 200, 267 bytes, sha256 `b9826e18...0046`; `/etc/nginx` tree `f6766240...9c8f` (equal to Gate I1) |
| Packages | 0 dpkg entries since Gate I1. `apt-daily-upgrade` last ran 06:44:00 and installed nothing; `apt-daily` (package-list refresh) next due 11:56:40 (observation O5) |

## 8. Packet flow: workstation to nginx

Counters were read immediately before (11:05:42) and after (11:05:43) the single request. NAT rules count only the first packet of a connection, a 52-byte TCP SYN here.

| # | Hop | Evidence (OBSERVED) | Before | After |
|---|---|---|---|---|
| 1 | Workstation to `3.6.94.104:30080` | `curl` remote `3.6.94.104:30080`; the security group admits 30080 only from the operator /32 (Gate I4 section 18.10). The AWS public IPv4 is translated to 10.40.1.10 before the node sees it (INFERRED from the AWS model; the node has no public address) | | |
| 2 | Node: NodePort match | `KUBE-NODEPORTS -p tcp --dport 30080 -j KUBE-EXT-CUH6W56T6REYHCCZ` | [0:0] | **[1:52]** |
| 3 | Node: mark for masquerade | `KUBE-EXT-...` `-j KUBE-MARK-MASQ` ("masquerade traffic for ... external destinations") | [0:0] | **[1:52]** |
| 4 | Node: Service to endpoint | `KUBE-SEP-5ZPMA3TJSODRA262 -j DNAT --to-destination 10.244.0.30:80` | [0:0] | **[1:52]** |
| 5 | Node to Pod | `ip route get 10.244.0.30`: `dev cni0 src 10.244.0.1`; `cni0` port `vethdc326847` (ifindex 33) is the peer of the pod's `eth0@if33` | | |
| 6 | Pod: masquerade DNAT to the guest | `KUBEVIRT_PREINBOUND`: `tcp dport 80 counter ... dnat to 10.0.2.2` | 4 packets | **5 packets** |
| 7 | Pod: toward the bridge | `postrouting oifname "k6t-eth0" jump KUBEVIRT_POSTINBOUND` (its SNAT rules match only source 127.0.0.1 and stayed at 0) | 13 | **14** |
| 8 | Bridge, tap, QEMU | Packets on pod `eth0` RX 898 to 903, `k6t-eth0` TX 747 to 752, `tap0` TX 768 to 773; `tap0` is held by QEMU through `/dev/net/tun` with vhost-net, and becomes the guest's virtio NIC | | |
| 9 | Guest nginx | Access log: `10.244.0.1 [01/Oct/2026:11:05:43 "GET / 200 267` | | |

What this shows:

- **Every hop counted exactly this one connection.** Since the launcher Pod started, the pod's port 80 DNAT has seen only five connections. The four earlier ones include the Gate I4 request (04:06:15) and its re-collection (04:26:34), plus a request at 10:31:38 that the access log shows and that was not part of this snapshot.
- **The guest sees the client as 10.244.0.1, the `cni0` gateway, not the workstation.** kube-proxy masquerades external NodePort traffic because `externalTrafficPolicy` is `Cluster`. The pod-level DNAT then changes only the destination.
- **The return path** follows the connection-tracking entries of the two NAT layers in reverse: guest to 10.0.2.1, pod un-DNAT, `eth0` to `cni0`, node un-DNAT and un-masquerade, then `eth0` and AWS back to the workstation (INFERRED). Connection-tracking tables were deliberately not listed, because they would show the operator address. The pod's rule `ip saddr 10.0.2.2 masquerade` stayed at 43: it applies to new connections the guest starts, not to replies.
- **Why `curl 10.0.2.2` from the jump host is not the same test:** 10.0.2.0/24 exists only inside this one Pod's network namespace. It is not routed in the VPC, the pod network or the lab network, and every launcher Pod reuses the same addresses. The only way in from outside the Pod is through the Pod IP (10.244.0.30), and so through the Service, the NodePort or a `virtctl port-forward`.

## 9. Observations

| # | Observation | Effect |
|---|---|---|
| O1 | `virsh dominfo` reports `tainted: custom guest agent control commands issued`. This comes from the Gate I4 direct `qemu-agent-command` queries (section 18.7). This snapshot used only `virsh domifaddr/domhostname/domfsinfo` and `virtctl guestosinfo` | Informational. libvirt marks the domain once and keeps the flag until the domain stops; behaviour is unchanged |
| O2 | A long-lived `sh` (PID 123 in `compute`, started about 04:36 UTC), most likely from an earlier interactive `kubectl exec`; origin not determined | Not touched. It ended with the Pod in Gate I5-C (Pod gone at 11:22:00 UTC) |
| O3 | kube-proxy rewrites its chains on sync, so its NAT counters were [0:0] at rest; they were readable only right after a request | Counters were taken immediately around the request |
| O4 | libvirt reports security model `none`: confinement comes from the container (SELinux `container_t` with MCS categories, seccomp `-sandbox on`, uid 107, dropped capabilities), not from libvirt sVirt | Expected for KubeVirt (INFERRED from the observed labels) |
| O5 | The guest's `apt-daily` refresh is due at 11:56:40 UTC; a later `apt-daily-upgrade` could install updates in the migrated guest (Gate I4 section 18.9) | Closed by Gate I5-A (11:19 to 11:20 UTC): 0 dpkg entries since Gate I1, and the guest was stopped at 11:21:49, before the refresh was due |
| O6 | The guest's nginx access log, journal and `auth.log`, and the node's sshd log, record this snapshot's SSH sessions and three HTTP requests (one external, two to 127.0.0.1) | The only side effects. Nothing else was written |

## 10. Resource impact

| Resource | Impact |
|---|---|
| AWS, Terraform, security group | **None** |
| Kubernetes, KubeVirt, CDI objects | **None** (read and exec of query commands only) |
| Node network, nftables, iptables, routes, interfaces | **None** (listed only) |
| Migrated VM and guest | **None**, apart from the log lines in O6 |
| `legacy-source-vm`, golden VMDK, prepared qcow2 | **None** (not contacted) |
| Files | Evidence file and the three scripts on the operator workstation (`C:\VMs\kvm-learning-01\stage-1i\i5pre\`) and the evidence file plus its `.sha256` on `kvm-learning-01:~/stage-1i/evidence/` |
