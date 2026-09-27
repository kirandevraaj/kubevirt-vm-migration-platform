# Interview notes

Request section 24. Answers are written to be said out loud in a Kubernetes / platform engineering interview: a short answer first, then the detail an interviewer will probe. Deeper explanations are linked.

---

### 1. "How would you migrate a VMware VM to Kubernetes?"

**Short answer:** Rehost it as a KubeVirt VM: discover and assess the VM, power it off (cold) or precopy with CBT (warm), convert the disk and guest drivers for KVM, import the disk into a PVC with CDI, create a KubeVirt `VirtualMachine` that uses that PVC with network and storage mappings, boot it, and validate the application. At scale, use a tool like MTV/Forklift; the underlying steps are the same.

**Detail:**

- Discovery and assessment: firmware, guest OS support, snapshots, disk sizes, NIC-to-network mapping, datastore-to-StorageClass mapping.
- Disk path: VMDK -> qemu-img or virt-v2v -> CDI DataVolume -> PVC (raw).
- Guest conversion matters: VMware guests use VMXNET3/PVSCSI; KubeVirt presents virtio. virt-v2v installs drivers and removes VMware Tools.
- Networking: pod network with masquerade, or a Multus secondary network if the VM must keep its L2/IP.
- Then decide per workload whether to stop there (VM on KubeVirt) or modernize into containers later.
- See [migration-architecture.md](migration-architecture.md).

### 2. "What is KubeVirt?"

**Short answer:** A Kubernetes add-on that lets you run and manage virtual machines as Kubernetes objects, next to containers, using the Kubernetes API, scheduler, networking and storage.

**Detail:** It adds CRDs (`VirtualMachine`, `VirtualMachineInstance`, and others), cluster controllers (virt-controller, virt-api, virt-operator) and a node daemon (virt-handler). Each running VM is a QEMU process managed by libvirt inside a normal Pod (virt-launcher), accelerated by KVM on the node. It is a CNCF project; OpenShift Virtualization is Red Hat's distribution of it. See [kubevirt-architecture.md](kubevirt-architecture.md).

### 3. "What is the difference between a VM and a VMI?"

**Short answer:** The `VirtualMachine` is the persistent definition and desired run state; the `VirtualMachineInstance` is one running instance of it. Like a StatefulSet with one replica versus its Pod.

**Detail:** The VM survives stop/start and holds `spec.template` and `spec.runStrategy` (`Always`, `RerunOnFailure`, `Manual`, `Halted`). virt-controller creates a VMI from the template when the VM should run and deletes it when the VM stops. The VMI carries live status: phase, node, IPs, guest info. You can create a bare VMI, but nothing restarts it.

### 4. "How does KubeVirt run a VM?"

**Short answer:** `VirtualMachine` -> virt-controller creates a VMI -> virt-controller creates a virt-launcher Pod -> the scheduler places it -> virt-handler on that node tells libvirt inside the Pod to start the domain -> QEMU runs the VM using `/dev/kvm`.

**Detail:** virt-api validates the object at admission. The launcher Pod requests CPU, memory (plus overhead) and the `devices.kubevirt.io/kvm` resource, mounts the disk PVCs, and gets networking from CNI/Multus. virt-handler renders domain XML from the VMI and keeps the domain and VMI status in sync. Status flows back: domain -> VMI phase -> VM printableStatus.

### 5. "Where does QEMU run?"

**Short answer:** In user space, inside the `compute` container of the VM's virt-launcher Pod, on the node where that Pod was scheduled. One QEMU process per VM.

**Detail:** Because it is inside a Pod, it is subject to the Pod's cgroups (CPU/memory limits), network namespace and mounted volumes. The guest's vCPUs are QEMU threads. The kernel part of virtualization is KVM on the node; QEMU talks to it through `/dev/kvm`. If the Pod dies, the VM dies, which is why the VM object and `runStrategy` exist.

### 6. "What is KVM?"

**Short answer:** A Linux kernel module that turns Linux into a hypervisor by using hardware virtualization (Intel VT-x / AMD-V, plus EPT/NPT for memory). It exposes `/dev/kvm`, which QEMU uses to create VMs and run vCPUs.

**Detail:** KVM does CPU and memory virtualization; QEMU does device emulation; libvirt does management. Unlike ESXi, where VMkernel is a purpose-built hypervisor OS, KVM is part of a general-purpose Linux kernel, so the same node can run containers and VMs. In the cloud you need bare metal or nested virtualization to get `/dev/kvm`.

### 7. "How would you import a VMDK into KubeVirt?"

**Short answer:** With CDI. Either put the VMDK (or a qcow2 converted from it) at an HTTP/S3 URL and create a DataVolume with an `http` or `s3` source, or push it with `virtctl image-upload`. CDI converts it to raw in a new PVC, and the VM references that PVC.

**Detail:**

- Make sure the VMDK is consistent (VM off, no snapshot chain, or consolidated) and that you copied every file its layout needs. Layouts differ: a VMFS disk is usually a descriptor plus a flat extent, while a Workstation `monolithicSparse` disk is one file. Copying only the descriptor gives you nothing.
- CDI accepts VMDK directly, but converting to qcow2 first reduces size and lets you check it with `qemu-img check`.
- A format conversion does not fix guest drivers. Use virt-v2v if the guest lacks virtio drivers (always for Windows).
- For direct import from vCenter/ESXi, CDI has a `vddk` source (needs the VDDK image and API access; not viable on free ESXi).
- Watch StorageClass binding mode, size (virtual size, not file size), and scratch space.

### 8. "What does CDI do?"

**Short answer:** It populates PVCs with VM disk data: import from URLs, registries, S3 or VMware (VDDK); upload from a client; clone from another PVC or snapshot; or create blank disks. It converts images to raw and reports progress through the `DataVolume` CR.

**Detail:** CDI ends when the DataVolume is `Succeeded` and the PVC holds a bootable raw disk. KubeVirt begins when a VM references that PVC. CDI knows nothing about CPUs or NICs. See [cdi-storage-model.md](cdi-storage-model.md).

### 9. "How would you design a migration CRD?"

**Short answer:** One namespaced CR per VM migration, with a declarative `spec` (source, destination, strategy, storage mapping, network mapping, validation) and a controller-owned `status` (phase, conditions, progress, frozen source inventory, created destination objects, errors, timestamps). Credentials by Secret reference only.

**Detail:**

- Keep spec intent-level and mostly immutable once the migration starts.
- `status.phase` drives the state machine; conditions give independent, typed facts.
- `observedGeneration` shows whether status reflects the latest spec.
- A finalizer enables cleanup of staging data and partial imports.
- Owner references from DataVolumes/VM to the migration CR.
- Explicit `powerOffPolicy`, because powering off the source is the only action that affects production.
- See the sketch in [migration-architecture.md](migration-architecture.md).

### 10. "How does a Kubernetes controller execute the migration?"

**Short answer:** It watches `VirtualMachineMigration` objects and their children, and for each one runs a reconcile: read the current phase, perform the next idempotent step for that phase (power off, convert, create DataVolume, create VM), observe the result, update status, and requeue until a terminal phase.

**Detail:** Events go to a work queue keyed by `namespace/name`, which deduplicates and ensures one worker per object. Long steps are not awaited in-process; the controller creates Jobs or DataVolumes and requeues or reacts to watch events when their status changes. Status updates go through the status subresource. See [crd-controller-fundamentals.md](crd-controller-fundamentals.md).

### 11. "What happens when migration fails halfway?"

**Short answer:** The CR keeps the phase where it failed and records the error. Transient errors are retried with backoff in the same phase; permanent or ambiguous errors go to `Failed` or `ManualInterventionRequired`. Because the source disk is only read after power-off, the source is intact and can be powered back on.

**Detail:**

- The controller never restarts from scratch; it resumes the recorded phase.
- Partial destination objects (DataVolumes, VM) are owned by the CR, so deletion (with the finalizer) cleans them up.
- The controller must not automatically power the source back on once the target VM has started, to avoid two live copies with the same identity.
- Retry budget prevents infinite loops. See [migration-state-machine.md](migration-state-machine.md).

### 12. "How would you make the migration controller idempotent?"

**Short answer:** Make every step "ensure", not "do": deterministic names for created objects, create-if-absent and update-if-different, check external state before acting, record evidence (checksums, URLs, object names) in status before advancing the phase, and treat "already done" and "not found on delete" as success.

**Detail:**

- DataVolume name `<migration>-disk-<n>`; staging key `<migration-uid>/disk-<n>.qcow2`.
- Power-off: check power state first; "already off" is success; record the timestamp once.
- Use optimistic concurrency (`resourceVersion`) on status updates and requeue on conflict.
- Never keep progress only in memory; a controller restart must be safe at any line of code.
- Guard irreversible actions behind validated conditions.

### 13. "What is the difference between VM migration and application modernization?"

**Short answer:** Migration (rehost) moves the whole VM, guest OS included, to a new platform without changing the app. Modernization changes how the app is packaged and run, for example as a container image in a Deployment, which removes the VM and guest OS.

**Detail:** KubeVirt migration is fast and low-risk and puts VMs on the same platform as containers, but you still patch and operate a guest OS. Modernization needs assessment and app changes but gives horizontal scaling, rolling updates and image-based delivery. A good program migrates first and modernizes selectively. Project 1.5 shows both on the same nginx workload. See [modernization-model.md](modernization-model.md).
