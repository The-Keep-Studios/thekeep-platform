# Resolve + K3s Platform Bootstrap

Current priority is the production-like path: central in-cluster identity (Authentik) + app integrations.
Design source of truth: [designdoc.md](designdoc.md). README is an operator runbook.

## Production-Like Path (Recommended)

This path bootstraps a single-node K3s stack that mirrors the production architecture direction:
- `auth.thekeepstudios.com` -> Authentik (identity hub)
- `projects.thekeepstudios.com` -> Leantime
- `gitlab.thekeepstudios.com` -> GitLab
- `mindmaps.thekeepstudios.com` -> Wisemapping
- `grafana.thekeepstudios.com` -> Grafana
- `prometheus.thekeepstudios.com` -> Prometheus UI
- `alerts.thekeepstudios.com` -> Alertmanager UI

### 1. Configure secrets and URLs

```bash
cp scripts/production.env.example scripts/production.env
```

Edit `scripts/production.env` and set required values (do not commit this file).
Monitoring is enabled by default and requires `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`.

### 2. Bootstrap

```bash
./bootstrap-production.sh
```

Equivalent:

```bash
./scripts/bootstrap-production.sh
```

K3s is managed by systemd and enabled at boot, so workloads should recover after host reboot without interactive user login.

### 3. Optional Cloudflare Tunnel

If you are using Cloudflare Tunnel for ingress transport, set:

```bash
export CLOUDFLARE_TUNNEL_TOKEN=<your-token>
./bootstrap-production.sh
```

Cloudflare Access is not used as the primary auth plane in this architecture.

### 4. Monitoring Stack (Built-In)

`bootstrap-production.sh` deploys:
- `kube-prometheus-stack` (Prometheus operator, Prometheus, Alertmanager, Grafana)
- `loki-stack` (Loki + Promtail for cluster/app logs)

Logs from all pods are shipped by Promtail to Loki, and Grafana is preconfigured with a Loki datasource (`http://loki:3100`).

## Authentik Integration Flow

### Google as upstream identity

Configure Google once in Authentik as a social/federated source.

Authentik admin bootstrap note:
- `AUTHENTIK_BOOTSTRAP_PASSWORD` is only read on first startup of a fresh Authentik DB.
- If login fails after changing env values later, reset directly in-cluster:
  `sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl exec -it deployment/authentik-server -n identity -- ak changepassword akadmin`

### App providers in Authentik

Create OAuth2/OIDC providers in Authentik for each app with callback URLs:
- Leantime: `https://projects.thekeepstudios.com/oidc/callback`
- GitLab: `https://gitlab.thekeepstudios.com/users/auth/openid_connect/callback`
- Wisemapping: `https://mindmaps.thekeepstudios.com/login/oauth2/code/google`

Then copy provider values into `scripts/production.env`:
- Leantime -> `LEAN_OIDC_*`
- GitLab -> `OIDC_*`
- Wisemapping -> `OAUTH_GOOGLE_*` + `WISEMAPPING_OAUTH_ENABLED=true`

Re-run:

```bash
./bootstrap-production.sh
```

Break-glass local login can stay enabled during rollout:
- Leantime: `LEAN_DISABLE_LOGIN_FORM=false`
- GitLab: local root account retained

GitLab manifest ships with a lightweight single-node profile (reduced resources + reduced Puma/Sidekiq concurrency). Increase sizing before multi-user/high-throughput use.

## Manifest Locations

- Authentik: `kubernetes/platform/authentik/standalone.yaml`
- Leantime production: `kubernetes/apps/leantime/production.yaml`
- GitLab: `kubernetes/apps/gitlab/standalone.yaml`
- Wisemapping production: `kubernetes/apps/wisemapping/production.yaml`
- Monitoring values: `kubernetes/platform/monitoring/*.values.yaml`
- Optional Cloudflare tunnel: `kubernetes/platform/cloudflare-tunnel.yaml`

## 1-Hour Demo Path (Legacy Fast Validation)

```bash
./bootstrap.sh
```

Then open:
- `https://localhost`
- `http://localhost:30082` (Mailpit inbox)

Teardown:

```bash
./teardown-cluster.sh
```

## Legacy Ansible Roles (Still Supported)

Resolve install:

```bash
ansible-playbook -K site.yml --tags resolve
```

K3s + LocalAI + Wisemapping standalone:

```bash
ansible-playbook -K site.yml --tags k3s,localai,wisemapping
```
