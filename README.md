# Resolve Platform Guide (Single Source of Truth)

## 60-Second Summary

- This repo runs a self-hosted internal platform on **k3s**.
- **Ansible** bootstraps machines and k3s.
- **Argo CD** is the continuous deploy/reconcile engine.
- **Kubernetes manifests + Helm values** are the desired state.
- **Scripts are helpers**, not the source of truth.
- Current status is **production-like**, not full HA production.

## Quick Paths By Role

### Production Setup From Scratch (Step-by-Step)

This guide assumes a fresh Ubuntu/Debian host and no existing infrastructure.

#### 1. Cloudflare Prerequisite (Manual Step)
1.  **Create a Tunnel:** Go to the Cloudflare Zero Trust dashboard -> Networks -> Tunnels. Create a new tunnel (e.g., `resolve-platform`).
2.  **Get the Token:** Copy the tunnel token provided in the installation instructions.
3.  **Add Public Hostnames:** In the Tunnel configuration, add Public Hostnames for all services listed in the "QA/Security" section (e.g., `projects.thekeepstudios.com`).
    - **Service Type:** `HTTPS`
    - **URL:** `traefik.kube-system.svc.cluster.local` (This internal Kubernetes DNS name allows the tunnel pod to reach the Ingress controller).
    - **No TLS Verify:** In the "Origin Settings" for each hostname, ensure **No TLS Verify** is enabled (since Traefik uses a self-signed certificate internally).

#### 2. Local Environment Preparation
1.  **Clone the Repo:** Ensure you are at the project root.
2.  **Create Production Vars:**
    ```bash
    cp ansible/production_vars.yml.example ansible/production_vars.yml
    ```
3.  **Configure Env:** Edit `ansible/production_vars.yml` and set all required secrets, especially `cloudflare_tunnel_token`.
    **Note:** This file is ignored by git to prevent secret exposure.

#### 3. Host Provisioning (Ansible)
1.  **Inventory:** Create `ansible/inventory.production.ini` from the example and add your host IP.
2.  **Run Playbook:**
    ```bash
    ansible-playbook -K -i ansible/inventory.production.ini ansible/setup_k3s_production.yml
    ```
    This installs k3s, configures the `k3s-admin` user, and sets up isolated kubeconfig.

#### 4. Ansible-First Deployment

1.  **Configure Inventory and Variables:**
    ```bash
    cp ansible/inventory.production.ini.example ansible/inventory.production.ini
    # Edit inventory.production.ini and ansible/production_vars.yml
    ```
2.  **Commit and Push Manifests:** Rendered GitOps manifests under `kubernetes/gitops/root` and `kubernetes/gitops/apps` must match the templates, be committed, and be pushed to the configured `gitops_repo_url` / `gitops_revision` before production deployment. The playbook verifies this before touching the cluster.
3.  **Run Full Deployment:**
    ```bash
    ansible-playbook -K -i ansible/inventory.production.ini ansible/setup_k3s_production.yml
    ```
    This single command provisions k3s, seeds secrets, bootstraps Argo CD, and validates the deployment.

#### 5. Private Repository Access
If your GitOps repository is private, configure Argo CD credentials before bootstrap. Set `gitops_repo_private: true` and provide one of the supported credential forms in `ansible/production_vars.yml`; the playbook will create the Argo CD repository Secret. Without credentials, the playbook fails before bootstrap.
```yaml
gitops_repo_ssh_private_key_path: /path/to/argocd-readonly-key
# or gitops_repo_username/gitops_repo_password for HTTPS repositories
```

### DevOps: Ansible Deployment Flow

1. **Prepare Environment:**
```bash
cp ansible/inventory.production.ini.example ansible/inventory.production.ini
cp ansible/production_vars.yml.example ansible/production_vars.yml
# Update ansible/production_vars.yml with your secrets
# Update ansible/group_vars/all.yml with GitOps settings
```
2. **Execute Deployment:**
```bash
ansible-playbook -K -i ansible/inventory.production.ini ansible/setup_k3s_production.yml
```

This replaces the legacy script-based flow (`seed-platform-secrets.sh`, `bootstrap-gitops.sh`, `validate-production-gate.sh`).

### Internal Launch Today (Leantime Priority)

For internal usage by end-of-day with minimal risk reduction:

1. Ensure Leantime is healthy:
```bash
sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl get deploy leantime leantime-mariadb
```
2. Take an immediate DB backup before team onboarding:
```bash
bash scripts/backup-leantime-now.sh
```
3. Verify scheduled backups are active:
```bash
sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl get cronjob leantime-db-backup
```
4. Keep restore command ready for incident response:
```bash
bash scripts/restore-leantime-backup.sh /path/to/backup.sql.gz
```

### QA/Security: Validation Path

1. Confirm control plane and pods:
```bash
sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl get nodes
sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl get pods -A
```
2. Run validation via Ansible:
```bash
ansible-playbook -i ansible/inventory.production.ini ansible/setup_k3s_production.yml --tags validation
```
The gate also fails if Prometheus or Alertmanager return unauthenticated `2xx`; they must be behind Cloudflare Access or an equivalent auth boundary.

The public HTTPS endpoints checked by the launch gate are:
- `auth.thekeepstudios.com`
- `projects.thekeepstudios.com`
- `mindmaps.thekeepstudios.com`
- `grafana.thekeepstudios.com`
- `prometheus.thekeepstudios.com`
- `alerts.thekeepstudios.com`
- `argocd.thekeepstudios.com`

For manual Argo inspection:
```bash
sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl get applications -n argocd
```

Live evidence required before claiming GO:
- production playbook output;
- GitOps render/committed-state comparison output;
- clean/staged/untracked GitOps checks;
- `git ls-remote` proof that local `HEAD` matches the configured GitOps target;
- Argo app sync and health output;
- Cloudflare HTTPS endpoint results;
- direct-origin block results, where any HTTP response is a failure;
- in-cluster `PrometheusRule` containing `LeantimeBackupFailed`;
- Leantime backup Job and readable non-empty backup artifact verification.

### App Developers: Architecture You Deploy On

- Your app deployment contract is Kubernetes manifests/Helm values in Git.
- Argo CD continuously reconciles to Git state.
- Runtime secrets come from Kubernetes Secrets (current) and should evolve to external/encrypted secret management.
- Deployments should assume eventual multi-node scheduling, even if current cluster is single-node.

## Architecture Relationship (Plain English)

- `Ansible`: machine provisioning and k3s install.
- `Kubernetes`: runtime orchestration, scheduling, healing, networking.
- `Helm`: packaging/templating format for Kubernetes resources.
- `Argo CD`: cluster-side GitOps controller that applies/reconciles manifests/charts from Git.

Operationally:
1. Ansible creates a healthy cluster.
2. Argo CD owns day-2 reconciliation.
3. Helm charts are consumed through Argo CD apps.

## Current Maturity and Limits

This stack is **not full production HA yet**.

Current constraints:
- Single k3s server/control-plane failure domain.
- Storage and backup strategy not fully hardened for disaster recovery. Backups are currently stored on-cluster (local PVC). Off-cluster replication (e.g., S3/RSYNC) must be configured externally for true DR.
- Secrets are improved but still not at final state (SOPS/External Secrets target).
- Public HTTPS assumes the GitOps-managed `platform-cloudflare-tunnel` app terminates TLS at the Cloudflare edge and forwards to the internal Traefik Ingress.
- **Security Hardening:** Ingress resources and the Cloudflare Tunnel are configured for secure traffic flow. The internal hop between the Tunnel and Traefik uses HTTPS with self-signed certificates (ensure "No TLS Verify" is enabled in Cloudflare for these origins).
- `bootstrap-production.sh` is removed. Production deployment is now fully integrated into Ansible. Use `ansible-playbook -i ansible/inventory.production.ini ansible/setup_k3s_production.yml`.

Target for full production:
- Multi-server k3s (etcd quorum).
- Replicated persistent storage and tested restore runbooks.
- Encrypted/externally managed secrets.
- Routine failure drills.

## Planned Hardening Features (CRITICAL PRIORITY)

This is the agreed backlog for moving from production-like to full HA production:

- 3-node k3s control plane (etcd quorum) plus separate workers.
- Backup immutability and off-cluster replication for etcd + databases.
- Admission policies to block deletes in critical namespaces by default.
- Strict RBAC with break-glass admin flow and short-lived elevated access.
- Branch protections and mandatory reviews for infrastructure paths.
- Scheduled restore drills with defined RPO/RTO targets.
- Secret management migration to SOPS/External Secrets.

## Migration From Legacy Script-Managed Cluster

If cluster was previously deployed via the legacy `bootstrap-production.sh` or standalone scripts, migrate to the Ansible-first flow:

1. Copy `ansible/production_vars.yml.example` to the ignored `ansible/production_vars.yml` file and set current production secrets there.
2. Run the production playbook:
   `ansible-playbook -i ansible/inventory.production.ini ansible/setup_k3s_production.yml`

Migration safety:
- Existing resources are reused/adopted.
- Monitoring apps reuse release names `kube-prometheus-stack` and `loki`.
- `prune: false` is set in GitOps app definitions to reduce accidental deletion risk during migration.
- `bootstrap-production.sh` is removed. Day-2 changes happen through Git and Argo CD.

## OIDC Notes (Authentik Hub)

- Configure Google once in Authentik upstream.
- Callback URLs:
  - Leantime: `https://projects.thekeepstudios.com/oidc/callback`
  - Wisemapping: `https://mindmaps.thekeepstudios.com/login/oauth2/code/google`
- Issuer format:
  - `https://auth.thekeepstudios.com/application/o/<provider-slug>/`
- Apply auth changes without full redeploy:
```bash
bash scripts/reconcile-oidc.sh
```

Authentik bootstrap behavior:
- `AUTHENTIK_BOOTSTRAP_PASSWORD` is only read on first startup with a fresh Authentik DB.
- Reset admin password later with:
```bash
sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config \
kubectl exec -it deployment/authentik-server -n identity -- ak changepassword akadmin
```

## Destructive Operations Policy

`teardown-cluster.sh` is demo/lab only.

Lab teardown:
```bash
TEARDOWN_CONFIRM=destroy-k3s ./teardown-cluster.sh --force
```

Production-like guard override (explicitly dangerous):
```bash
ALLOW_PRODUCTION_TEARDOWN=true TEARDOWN_CONFIRM=destroy-k3s ./teardown-cluster.sh --force
```

## File Map

- k3s production bootstrap playbook: `ansible/setup_k3s_production.yml`
- Argo platform install: `kubernetes/platform/argocd/*`
- Cloudflare Tunnel edge deployment: `kubernetes/platform/cloudflared/*`
- GitOps apps/root: `kubernetes/gitops/*`
- Leantime backup CronJob: `kubernetes/apps/leantime/backup-cronjob.yaml`
- Runtime env template: `scripts/production.env.example`
- GitOps manifest renderer (deprecated): `scripts/render-gitops-apps.sh`
- GitOps bootstrap helper (deprecated): `scripts/bootstrap-gitops.sh`
- Production launch gate (deprecated): `scripts/validate-production-gate.sh`
- Secrets seed helper (deprecated): `scripts/seed-platform-secrets.sh`
- OIDC reconcile helper: `scripts/reconcile-oidc.sh`
- Leantime on-demand backup: `scripts/backup-leantime-now.sh`
- Leantime restore helper: `scripts/restore-leantime-backup.sh`
