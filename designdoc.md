# Design Specification: The Keep Studios Meta-Platform (Open Source Release)

## 1. Executive Summary & Philosophy
This document outlines the architecture and deployment strategy for **The Keep Studios Meta-Platform**, an open-source, private-cloud infrastructure designed to support diverse operational workflows: TTRPG Publishing, Animal Rescue operations, and Local AI/LLM development.

**The core philosophy:**
* **Zero "Bait-and-Switch":** We rely on true open-source tooling (like Leantime) to avoid gated "Enterprise" features (e.g., Jira-like burndowns, epics).
* **Data Sovereignty & Local AI:** Leveraging high-end local hardware (96GB VRAM) to run private LLMs and AI agents without cloud API dependencies.
* **GitOps & Meta-CI/CD:** The infrastructure is self-sustaining. After the initial Ansible bootstrap, an internal GitLab instance acts as the CI/CD engine to deploy and manage all other services on the cluster.
* **AI & Engineer Co-creation:** This spec is written to be parsed by both Senior Engineers and AI Coding Agents (e.g., Cursor, AutoGPT). Directory structures and toolchains are explicitly defined for autonomous scaffolding.

---

## 2. Hardware & Network Topology

The physical layer is heterogeneous, residing entirely on local networks before eventually bursting external traffic via Cloudflare or GCP.

| Node / Device | Role | Specs / OS | Primary Responsibility |
| :--- | :--- | :--- | :--- |
| **Framework Desktop** | Primary Control/Worker | 96GB VRAM, High CPU | Host CI/CD, DBs, Leantime, Local LLMs/Agents. |
| **Raspberry Pi** | Edge / DNS | ARM64 | Local DNS (AdGuard Home), lightweight K3s worker. |
| **Linux Mint Laptop** | Management / Admin | standard x86 | Initial Ansible execution, local testing. |

### Networking & DNS Rules
* **Local Domain:** `*.rochester.thekeepstudios.com`
* **Public Domains:** `thekeepstudios.com`, `fullheartsroc.org`
* **Production-Like App FQDNs:** `auth.thekeepstudios.com`, `projects.thekeepstudios.com`, `gitlab.thekeepstudios.com`, `mindmaps.thekeepstudios.com`, `grafana.thekeepstudios.com`, `prometheus.thekeepstudios.com`, `alerts.thekeepstudios.com`
* **DNS Resolution:** The Raspberry Pi runs **AdGuard Home** acting as the local network's primary DNS. A wildcard rewrite routes `*.rochester.thekeepstudios.com` to the MetalLB IP pool of the K3s cluster.
* **IP Management:** DHCP reservations on the router for physical MAC addresses; **MetalLB** handles Layer 2 routing for K8s LoadBalancer services.

---

## 3. Core Infrastructure Architecture (K3s + Ansible)

We utilize **Ansible** strictly for the "Hardware to Kubernetes" layer. Once K3s is alive, Ansible's job is largely done, and GitOps takes over.

* **Orchestration:** **K3s** (Lightweight Kubernetes).
* **Isolation & Security:** A dedicated system user `k3s-admin` and group `k3s` are created to manage the cluster. The `kubeconfig` is owned by this user, and `kubectl` commands are executed via `sudo -u k3s-admin` to ensure management isolation from the primary user account.
* **Container Runtime:** containerd (with `nvidia-container-toolkit` installed on the Framework Desktop via Ansible for GPU passthrough).
* **Storage (CSI):** **Longhorn**. Deployed immediately after K3s. It provides distributed, highly available block storage for databases and persistent volumes. Replicas should be configured based on the final node count.

---

## 4. Platform Services (The K8s Foundation)

Before workloads are deployed, the following services must be instantiated in the cluster:

1.  **Ingress & Routing:**
    * **Nginx Ingress Controller:** Handles incoming HTTP/S traffic.
    * **Cert-Manager:** Automates SSL certificate provisioning via Let's Encrypt (DNS-01 challenge for local/internal domains via Cloudflare API).
2.  **Observability & Monitoring (Grafana Stack):**
    * **Deployment:** `kube-prometheus-stack` (Helm).
    * **Components:** Prometheus (metrics scraper), Alertmanager (routing alerts), **Grafana** (Visualization), and Loki + Promtail for centralized log aggregation.
    * **Dashboards:** Pre-load dashboards for K3s node health, Longhorn volume health, and GPU utilization (via DCGM exporter).
3.  **Local Load Balancing:**
    * **MetalLB:** Configured in L2 mode to broadcast the cluster's presence to the local router.

---

## 5. The "Meta-CI/CD" Bootstrap Sequence

This is the most critical logic flow for the implementing team/agents to understand to avoid the "Chicken and Egg" paradox.

1.  **Phase 1: Admin Bootstrap:** Engineer runs Ansible from the Linux Mint Laptop against the Framework Desktop. K3s, Longhorn, and Nginx Ingress spin up.
2.  **Phase 2: The Seed Deploy:** Engineer uses `kubectl` or Helm to manually deploy **GitLab CE** to the cluster.
3.  **Phase 3: The Handoff:** The IaC repository (containing this spec) is pushed to the local GitLab instance.
4.  **Phase 4: Automation:** GitLab K8s Runners are deployed. From this point forward, committing code to the GitLab repo triggers pipelines that deploy/update Leantime, AI Agents, and web frontends.

---

## 6. Application Workloads

### A. Leantime (Project Management)
Chosen for its modal-based UX, native Agile/Scrum capabilities (Burndowns), and lack of paywalled features.
* **Architecture:** PHP-FPM / Nginx sidecar pattern + MariaDB + PVC (for attachments like Cat Rescue photos).
* **Config Needs:** Enable Scrum modules by default.

### B. Meta-CI/CD (GitLab CE)
* **Architecture:** Omnibus Helm Chart or decoupled microservices (Postgres/Redis). Needs a large resource limit (8GB+ RAM).
* **Storage:** Requires robust Longhorn PVCs and automated backups to external S3.

### C. Local AI & Agents
* **Architecture:** Pods requesting `nvidia.com/gpu` resources.
* **Stack:** Ollama / vLLM for model serving; Python/LangChain containers for custom agents acting on TTRPG publishing data or analyzing rescue operations.

---

## 7. Directory Structure & Implementation Blueprint

**For AI Agents:** Use the following scaffolding to generate the repository.

```text
infrastructure-as-code/
├── README.md                 # Project entry point
├── ARCHITECTURE.md           # This document
├── ansible/                  # Bare-metal provisioning
│   ├── ansible.cfg
│   ├── inventory.ini         # Map Framework, Pi, Laptop
│   ├── site.yml              # Master playbook
│   └── roles/
│       ├── system_hardening/ # Disable swap, configure firewall
│       ├── nvidia_drivers/   # Install GPU toolkit
│       └── k3s_setup/        # K3s installation via k3s-ansible
├── kubernetes/               # GitOps / Helm manifestations
│   ├── base/
│   │   ├── namespaces.yaml
│   │   ├── metallb-config.yaml
│   │   └── cert-manager-issuer.yaml
│   ├── platform/             # Core cluster services
│   │   ├── longhorn/
│   │   ├── ingress-nginx/
│   │   └── monitoring/       # kube-prometheus-stack (Grafana)
│   └── apps/                 # Application workloads
│       ├── gitlab/
│       ├── leantime/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   └── mariadb.yaml
│       └── ai-agents/
└── scripts/                  # Helper utilities
    ├── bootstrap.sh          # Wraps ansible-playbook execution
    └── teardown-cluster.sh   # For local laptop testing/cleanup
```

## 8. Development Team Directives & Guardrails

* **To the Senior Engineers:** Resist the urge to rewrite the PHP backend of Leantime. Containerize it, put it behind the Nginx proxy, and treat it as a black box. Your time is better spent building custom AI agents in Python/TS that interface with Leantime's API.
* **To the AI Agents:** When generating the Ansible roles, ensure idempotency. When generating K8s manifests, utilize `values.yaml` paradigms for Helm charts to allow easy overriding of local vs. production environment variables. Always request PersistentVolumeClaims (PVCs) mapping to the `longhorn` storage class.
* **Manifest-First Rule:** Workload source of truth lives under `kubernetes/apps/*/*.yaml`. Ansible roles should apply these files directly; avoid role-local Jinja manifest templates to reduce drift and improve editor tooling.
* **Security Posture:** Do not commit secrets. Use Kubernetes Secrets or external secret management (e.g., SOPS with Age, or HashiCorp Vault if scaled later) within the GitLab CI/CD pipelines.
* **Future Scope (Cloud Bursting):** GCP/Terraform is explicitly out of scope for the local cluster provisioning. If public landing pages migrate to GCP, Terraform will be executed by GitLab Runners targeting GCP APIs, completely segregated from this Ansible local-hardware logic.

---

## 9. Addendum: The 1-Hour Demo Plan (Phase 1)

### A. Purpose and Intent
The explicit purpose of this phase is to execute a **Quick technical demo and proof of concept which can be cleanly torn down.** Before committing hardware resources, configuring complex network routing, or establishing the Meta-CI/CD pipelines, the engineering team must validate the core hypothesis: *Does the Leantime application provide the necessary Scrum/Agile capabilities with the required "Modal-based" User Experience?* This demo provides a rapid, isolated sandbox to evaluate the application UI/UX and validate the foundational Ansible-to-K3s execution path.

### B. Time Constraints and Scope Reduction
To ensure this deployment can be provisioned, tested, and destroyed within a **60-minute window**, the "Production Grade" requirements from the main architecture have been aggressively scoped down:

* **Hardware Reduction:** The Framework Desktop and Raspberry Pi are completely excluded. The demo will execute entirely on the **Linux Mint Laptop**.
* **Storage Simplification:** Longhorn CSI is out of scope. The demo will utilize the default K3s `local-path` provisioner. Data will not survive a node teardown.
* **Database Simplification:** External HA database architecture is out of scope. For demo reliability, Leantime runs with a single in-cluster **MariaDB** pod + PVC.
* **Networking & Edge:** MetalLB, Cert-Manager, and custom AdGuard DNS routing are excluded. Access will be via K3s's built-in Klipper LoadBalancer and localhost/IP port binding.
* **Infrastructure & Observability:** GitLab (Meta-CI/CD), Grafana, Prometheus, and GPU passthrough configurations are entirely omitted. Workloads will be applied directly via local `kubectl` commands.
* **Email Handling (Demo):** A local SMTP sink (Mailpit) is included so invite/reset flows are testable without external mail infrastructure.

### C. Demo Architecture Spec

**1. Target Node:**
* `test-laptop` (Linux Mint).
* Ansible connection: `local` (bypassing network SSH complexities for the demo).
* **Management User:** `k3s-admin` (Isolated system account).

**2. Kubernetes (K3s) Configuration:**
* Single "Server" node deployment.
* Default Traefik Ingress enabled.
* **HTTPS Support:** Self-signed certificates generated for `localhost` and managed via K8s TLS secrets.

**3. Leantime Workload Manifest:**
* Single Leantime Deployment (`leantime/leantime:latest`) plus a single MariaDB Deployment.
* Environment variables inject MySQL connectivity (`LEAN_DB_DEFAULT_CONNECTION=mysql`, host/user/password/database).
* Exposed via `Service` and `Ingress` for HTTPS routing on port 443.

### D. Execution & Teardown Protocol

**For AI Agents & Engineers:** The execution must strictly follow this isolated path to ensure the host operating system remains unpolluted.

1.  **Bootstrap:** Execute `scripts/bootstrap.sh`. This script handles host prep, k3s-admin user creation, certificate generation, and Leantime deployment.
2.  **Evaluate:** Stakeholders access `https://localhost`, initialize Leantime, enable Scrum modules, and test the Backlog-to-Sprint drag-and-drop UX.
3.  **Teardown (Crucial Step):** Once the evaluation is complete, execute `scripts/teardown-cluster.sh`. This ensures all networking tables, containers, and the `k3s-admin` user are cleanly wiped from the Linux Mint laptop.
