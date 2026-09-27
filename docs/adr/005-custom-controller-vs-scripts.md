# ADR 005: Custom migration controller vs scripts

- **Status:** Accepted (direction); implementation deferred to a later stage

## Context

A migration is long-running, multi-step, touches external systems (ESXi, staging storage, CDI, KubeVirt) and can fail halfway. Scripts are the fastest way to learn each step, but they keep state in a terminal, are hard to resume safely, and do not integrate with Kubernetes RBAC, status or GitOps. MTV solves this with controllers and CRs, but we are building a learning platform, not copying MTV.

## Decision

The migration workflow will be owned by a **custom Kubernetes controller** reconciling a namespaced **`VirtualMachineMigration`** CR (`migration.platform.example/v1alpha1`) through an explicit state machine. Scripts are allowed as **learning tools and as the building blocks** the controller calls (for example a conversion Job), not as the orchestrator.

## Clarification (Stage 0 refinement)

- The controller owns a **declarative** migration workflow. The state machine represents **reconciliation checkpoints, not a procedural script**: each phase names a desired state; every reconcile re-observes actual state and takes the idempotent action that closes the gap.
- `status.phase` is the controller's **current reconciliation state**, not a log of what ran.
- Required properties: idempotency, resumability, retry safety, with desired and observed state kept distinct ([migration-state-machine.md](../stage-0/migration-state-machine.md#1-reconciliation-checkpoints-not-a-procedural-script)).
- Implementation remains **deferred**.

## Comparison (conceptual)

| | Scripts | Controller |
|---|---|---|
| State | Terminal/logs | CR `status` in etcd |
| Resume after crash | Manual | Reconcile re-observes the system from the current checkpoint |
| Retries | Hand-written | Work queue with backoff + retry budget |
| Concurrency | Unprotected | One worker per object key |
| Access control | SSH/shell | Kubernetes RBAC |
| Cleanup | Manual | Finalizers + owner references |

## Consequences

- Every step must be idempotent (deterministic names, create-if-absent, evidence recorded before advancing).
- More upfront design: CRD schema, state machine, conditions. Stage 0 covers this conceptually.
- Language/framework (for example Go + controller-runtime/kubebuilder, or Python + kopf) is **deferred**.
- Nothing is implemented or applied in Stage 0.

## Evidence

Design in [crd-controller-fundamentals.md](../stage-0/crd-controller-fundamentals.md), [migration-state-machine.md](../stage-0/migration-state-machine.md), [migration-architecture.md](../stage-0/migration-architecture.md). References: [Kubernetes controllers](https://kubernetes.io/docs/concepts/architecture/controller/), [Custom resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/), [Operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/).
