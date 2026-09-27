# Architecture Decision Records (ADRs)

| ADR | Decision | Status | Evidence |
|---|---|---|---|
| [001](001-local-esxi-migration-source.md) | Local nested ESXi as the migration source | Accepted | Stage 0 evidence index; Broadcom free-edition KB |
| [002](002-aws-disposable-target.md) | AWS as the disposable, Terraform-built target | Accepted | AWS nested virtualization docs; EKS versions |
| [003](003-cold-before-warm.md) | Cold migration before warm; no custom warm engine | Accepted | MTV 2.11 warm-migration docs; free ESXi API limits |
| [004](004-kubevirt-vm-destination.md) | Upstream KubeVirt + CDI as the VM destination | Accepted | KubeVirt architecture, install and support matrix |
| [005](005-custom-controller-vs-scripts.md) | Custom Kubernetes controller owns the migration workflow | Accepted (implementation deferred) | Stage 0 CRD / controller / state-machine design |

All decisions were made in **Stage 0** (2026-09-27) and are subject to review before Stage 1.
