# Architecture Decision Records (ADRs)

| ADR | Decision | Status | Evidence |
|---|---|---|---|
| [001](001-local-esxi-migration-source.md) | Local nested ESXi as the migration source | Accepted | Stage 0 evidence index; Broadcom free-edition KB |
| [002](002-aws-disposable-target.md) | AWS as the disposable, Terraform-built target (topology and instance family deferred) | Accepted | AWS nested virtualization docs; KubeVirt install requirements |
| [003](003-cold-before-warm.md) | Cold migration before warm; warm stays reference/study work | Accepted | MTV 2.11 warm-migration docs; free ESXi API limits |
| [004](004-kubevirt-vm-destination.md) | Upstream KubeVirt + CDI as the VM destination; versions as a runtime-validated tuple | Accepted | KubeVirt release notes, install docs; CDI releases / API reference |
| [005](005-custom-controller-vs-scripts.md) | Custom Kubernetes controller owns the declarative migration workflow | Accepted (implementation deferred) | Stage 0 CRD / controller / state-machine design |
| [006](006-dedicated-conversion-host.md) | `conversion-host-01` is the dedicated lab host for disk inspection, conversion and QEMU/KVM boot validation, separate from the source and learning VMs (target format and production conversion location not decided) | Accepted | Stage 1F and Stage 1G records |

ADRs 001 to 005 were made in **Stage 0** (2026-09-27) and clarified in the Stage 0 technical refinement. ADR 006 was added in **Stage 1G** (2026-09-28).
