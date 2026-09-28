# ADR 008: Pod network with masquerade binding; the VMware IP is not preserved

- **Status:** Accepted (Stage 1H, 2026-09-28). Design decision; nothing has been deployed.

## Context

The source VM serves nginx on a static 192.168.50.31 on VMnet8, a VMware Workstation NAT network on the laptop. Stage 1G showed that the converted guest needs a network remediation, and that the remediation depends on how KubeVirt attaches the NIC. KubeVirt v1.9 offers `masquerade` and `bridge` bindings on the pod network, `bridge` on Multus secondary networks, the `passtBinding` core binding (Beta, on by default in v1.9) and binding plugins [E10, E11, E20]. The target is a single-node kubeadm cluster with flannel on one EC2 instance ([ADR 007](007-kubevirt-target-platform.md)).

## Decision

1. The VM has **one interface on the pod network with the `masquerade` binding**, `model: virtio`, and an explicit port list (80, 22).
2. The guest gets its address from KubeVirt's DHCP: **10.0.2.2/24, gateway 10.0.2.1** (default `vmNetworkCIDR` 10.0.2.0/24) [E21]. Egress is source-NATed to the pod IP, then to the node's VPC address.
3. **No Multus** and no NetworkAttachmentDefinitions: this model does not need them.
4. **192.168.50.31 is not preserved.** Continuity is provided by a Kubernetes **Service** (NodePort 30080, reachable only from the operator's /32 for validation). Workload identity is proven by content (page sha256), not by address.

## Why

| Binding | Verdict for the first cold migration |
|---|---|
| Pod + masquerade | **Chosen.** Works with any CNI, needs no Multus, is allowed to live-migrate later, and is KubeVirt's recommended default over pod bridge [E20, E22] |
| Pod + bridge | Rejected: gives the guest the pod IP anyway, is not allowed to live-migrate, and some CNIs and tools break when the MAC moves [E20, E22] |
| Multus secondary + bridge | Rejected: needs Multus, NADs and an L2 segment. A VPC only accepts ENI-assigned addresses from the subnet range, so a guest-chosen address is not deliverable [E46] |
| Pod + passt | Deferred: Beta, 250 Mi extra memory per VM, no benefit here [E10, E20] |

The VMware IP cannot survive for four independent reasons: VMnet8 is not reachable from AWS; masquerade assigns the address; a VPC drops foreign addresses; and the source keeps running at .31 as the reference and rollback.

## Consequences

- The guest must use DHCP and must not match its NIC by the VMware name. That is [ADR 010](010-migration-network-remediation.md).
- Clients reach the VM through the Service, never by the guest address; pod IP changes (restart, reschedule) do not matter.
- Infrastructure identity changes (IP 192.168.50.31 -> 10.0.2.2 behind the pod IP, MAC, interface name) are recorded as expected, not as failures.
- Guest DNS is expected to be cluster DNS through the DHCP response (INFERRED; to be observed).
- Deferred: DNS names, LoadBalancer or Ingress, Multus, secondary networks, bridge or passt bindings, MAC preservation, any IP preservation.

## Evidence

[Stage 1H record](../stage-1/stage-1h-kubevirt-target-feasibility.md), sections 13, 14 and 20, sources E10, E11, E20 to E22, E46.
