# ADR 010: Guest network remediation by netplan driver match and DHCP, applied offline at conversion time

- **Status:** Accepted (Stage 1H, 2026-09-28). Design decision; not applied to any disk.
- **Amended:** 2026-09-30, documentation only, from the [Stage 1H architecture review](../stage-1/stage-1h-architecture-review.md):
  - review R2: intended guest changes and the preparation record;
  - review R5: pre-transfer boot test gate;
  - the meaning of "offline".

  Not applied to any disk, and no boot test was performed.

## Context

The source guest's netplan matches the VMware interface name `ens192` and configures a static 192.168.50.31. On a virtio NIC the interface gets a different name, so the guest boots healthy but unreachable (Stage 1C risk, confirmed in Stage 1G for both conversion paths). Stage 1G proved on a disposable copy that matching by driver fixes the interface problem. [ADR 008](008-kubevirt-network-model.md) now fixes the addressing: masquerade hands out 10.0.2.2 by DHCP, and .31 is not kept.

This deserves its own record because it is a policy for changing the guest during migration, with real alternatives, and not just a consequence of the binding.

## Decision

1. Replace the content of the guest's only netplan file, `/etc/netplan/50-cloud-init.yaml` (root:root, 0600), with one ethernet `primary` that uses **`match: driver: virtio_net`**, **`dhcp4: true`** and `dhcp6: false`. There is no name match, MAC match, static address, route or nameserver. (The exact design text is in section 15 of the Stage 1H record.)
2. Apply it **offline** (guestfish or virt-customize) on a **new disposable copy** of the virt-v2v output on `conversion-host-01`, together with the offline guest-agent install. Hash the result and make it read-only.
3. Never apply it to the source VM, the golden artifact, the working copy or the kept Stage 1G images.
4. **"Offline" refers to the guest** (clarified 2026-09-30). The guest never needs network access for this change or for the agent install. `conversion-host-01` does need Ubuntu archive access to download the agent packages.
5. **The netplan replacement is an enumerated, intended guest change** (added 2026-09-30, review R2). The others are:
   - the virt-v2v changes recorded in Stage 1G;
   - the qemu-guest-agent install with its exact dependency set;
   - removal of all five virt-v2v first-boot scripts and their service.

   They are recorded, with hashes, in a preparation record. The guest is otherwise unchanged. See the [Stage 1H record, section 29.2](../stage-1/stage-1h-kubevirt-target-feasibility.md#292-review-r2-guest-identity-and-intended-changes). The file hash and package evidence are pending future image preparation.
6. **The prepared image must pass the pre-transfer boot test** on `conversion-host-01` before it is transferred (added 2026-09-30, review R5). The test boots it under QEMU/KVM with OVMF (Secure Boot off), virtio disk and NIC, user-mode DHCP and the guest-agent channel, through a disposable overlay. It checks that DHCP works, `systemctl is-system-running`, the agent, and the nginx page hash. See the [Stage 1H record, section 29.5](../stage-1/stage-1h-kubevirt-target-feasibility.md#295-review-r5-pre-transfer-boot-test-mandatory-gate). Stage 1G proved only a static test address, so this gate is the first test of the DHCP design.

## Alternatives

| Alternative | Why not |
|---|---|
| Keep static 192.168.50.31 | Not deliverable on masquerade or in a VPC (ADR 008) |
| Match by the MAC and set `macAddress: 00:0c:29:0f:3d:15` on the KubeVirt interface | Works, but couples the guest to a VMware-OUI MAC for no benefit, and still needs DHCP |
| KubeVirt `cloudInitNoCloud` network data at first boot | cloud-init is disabled in this guest (Stage 1F); enabling it is a bigger, riskier change than one netplan file |
| Fix it after boot through the console | Manual, not reproducible, and leaves the first boot unreachable |
| Rely on virt-v2v | virt-v2v 2.4.0 left netplan untouched (Stage 1G) |

## Consequences

- The guest config no longer depends on VMXNET3, `ens192`, PCI slot naming or the MAC, and it works with any single virtio NIC on a DHCP network.
- With several virtio NICs the match would configure all of them. That is acceptable for the single-NIC design and would need revisiting if Multus is ever added.
- The guest's address is now whatever the platform assigns. Monitoring and clients must use the Service, not the guest IP.
- Rollback is trivial: the source VM is unchanged and still serves .31.

## Evidence

[Stage 1G record](../stage-1/stage-1g-controlled-conversion.md), sections 13, 14, 17 and 20 (driver match proven; virt-v2v changes and first-boot scripts recorded); [Stage 1H record](../stage-1/stage-1h-kubevirt-target-feasibility.md), sections 14, 15 and 29; [Stage 1H architecture review](../stage-1/stage-1h-architecture-review.md), section 9.
