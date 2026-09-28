# VM-to-Kubernetes Migration Platform

ESXi → KubeVirt Migration & VM Modernization

| Item | Value |
|---|---|
| Project | Project 1.5 |
| Purpose | Build a VMware ESXi source environment with legacy VMs and migrate them to KubeVirt on Kubernetes |
| Current phase | Stage 1 (1A to 1G complete; 1H KubeVirt target architecture designed, awaiting review; nothing provisioned) |
| Source platform | Nested ESXi 8 on VMware Workstation |
| Target platform | AWS Kubernetes + KubeVirt: designed as a single-node kubeadm cluster on one nested-virtualization EC2 instance ([ADR 007](docs/adr/007-kubevirt-target-platform.md)); not built yet |
| Migration approach | Cold migration first |
| Warm migration | Study/reference phase |
| Status | Foundation environment ready |

Project context: [docs/project-context/project1-5-context-handoff.md](docs/project-context/project1-5-context-handoff.md)

Stage 0 (theory, architecture, feasibility): [docs/stage-0/README.md](docs/stage-0/README.md)

Stage 1 (source environment build-out): [docs/stage-1/README.md](docs/stage-1/README.md)

Architecture decisions: [docs/adr/README.md](docs/adr/README.md)
