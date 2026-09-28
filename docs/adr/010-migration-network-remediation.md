# ADR 010: Guest network remediation by netplan driver match and DHCP, applied offline at conversion time

- **Status:** Accepted (Stage 1H, 2026-09-28). Design decision; not applied to any disk.

## Context

The source guest's netplan matches the VMware interface name `ens192` and configures a static 192.168.50.31. On a virtio NIC the interface gets a different name, so the guest boots healthy but unreachable (Stage 1C risk, confirmed in Stage 1G for both conversion paths). Stage 1G proved on a disposable copy that matching by driver fixes the interface problem. [ADR 008](008-kubevirt-network-model.md) now fixes the addressing: masquerade hands out 10.0.2.2 by DHCP, and .31 is not kept.

This deserves its own record because it is a policy for changing the guest during migration, with real alternatives, and not just a consequence of the binding.

## Decision

1. Replace the content of the guest's only netplan file, `/etc/netplan/50-cloud-init.yaml` (root:root, 0600), with one ethernet `primary` that uses **`match: driver: virtio_net`**, **`dhcp4: true`** and `dhcp6: false`. There is no name match, MAC match, static address, route or nameserver. (The exact design text is in section 15 of the Stage 1H record.)
2. Apply it **offline** (guestfish or virt-customize) on a **new disposable copy** of the virt-v2v output on `conversion-host-01`, together with the offline guest-agent install. Hash the result and make it read-only.
3. Never apply it to the source VM, the golden artifact, the working copy or the kept Stage 1G images.

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

[Stage 1G record](../stage-1/stage-1g-controlled-conversion.md), sections 13, 17 and 20 (driver match proven); [Stage 1H record](../stage-1/stage-1h-kubevirt-target-feasibility.md), sections 14 and 15.
