# Codex Follow-Up Remediation Report

Date: 2026-05-09

## Summary

The latest review blockers have been addressed in the worktree. Cloudflare Tunnel is now the accepted production edge strategy for this light-production launch because it keeps setup simple: create a Cloudflare tunnel, put its token in `scripts/production.env`, seed secrets, and let Argo CD deploy the `cloudflared` connector. The production GitOps path now deploys that edge connector, the tunnel token is required during secret seeding, and GitOps bootstrap fails if the root application does not become Synced and Healthy. A launch-gate validation script was added for Argo health, Cloudflare Tunnel status, HTTPS endpoint checks, protected monitoring endpoints, and backup resource presence.

This is ready for another code-level review. Final launch approval still requires live environment evidence from the production cluster.

## Addressed Review Blockers

### Cloudflare Tunnel Is Now In Production GitOps

- Added `platform-cloudflare-tunnel` to the rendered GitOps application set:
  - `kubernetes/gitops/apps/platform-applications.yaml`
  - `kubernetes/gitops/templates/platform-applications.yaml`
- Added the renderable Cloudflare Tunnel kustomization root:
  - `kubernetes/platform/cloudflared/kustomization.yaml`
  - `kubernetes/platform/cloudflared/deployment.yaml`
- Added `kube-system` as an allowed destination in the platform AppProject:
  - `kubernetes/gitops/root/platform-project.yaml`
  - `kubernetes/gitops/templates/platform-project.yaml`
- Updated the demo bootstrap path to use the same `kubernetes/platform/cloudflared` kustomization.

The previous optional manifest path `kubernetes/platform/cloudflare-tunnel.yaml` was replaced by the GitOps-managed kustomization root under `kubernetes/platform/cloudflared`.

### Cloudflare Token Is Required For Production

- `scripts/seed-platform-secrets.sh` now requires `CLOUDFLARE_TUNNEL_TOKEN`.
- `scripts/production.env.example` now treats `CLOUDFLARE_TUNNEL_TOKEN` as required for the production GitOps path.
- The tunnel token secret is always reconciled into `kube-system/cloudflare-tunnel-token`.

Operational setup is intentionally narrow:

1. Create/configure the Cloudflare Tunnel and public hostname routes in Cloudflare.
2. Set `CLOUDFLARE_TUNNEL_TOKEN` in `scripts/production.env`.
3. Run `scripts/seed-platform-secrets.sh`.
4. Run `scripts/bootstrap-gitops.sh`.
5. Run `scripts/validate-production-gate.sh`.

### GitOps Bootstrap No Longer Masks Root Reconciliation Failure

- Removed the non-fatal `|| true` root health wait.
- `scripts/bootstrap-gitops.sh` now waits for:
  - `platform-root` sync status `Synced`
  - `platform-root` health status `Healthy`
- A failure in either wait now exits non-zero and prevents a false "bootstrap complete" signal.

### Launch Gate Validation Added

Added `scripts/validate-production-gate.sh`, which checks:

- Cluster access as `k3s-admin`.
- Cloudflare tunnel token secret exists.
- `deployment/cloudflared` is available in `kube-system`.
- Expected Argo applications are present, Synced, and Healthy.
- Leantime backup CronJob exists.
- Public HTTPS endpoints answer over TLS.
- Prometheus and Alertmanager do not return unauthenticated `2xx` responses.
- Optional direct HTTP origin URLs do not answer when provided through `DIRECT_HTTP_URLS`.

README now includes this script in the production deployment and QA/Security validation paths.

## Validation Performed

Static/local validation passed:

```bash
find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n
bash -n bootstrap.sh
bash -n bootstrap-production.sh
git diff --check
```

Ansible syntax validation passed:

```bash
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check site.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check ansible/site.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i ansible/inventory.ini ansible/setup_k3s_demo.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i ansible/inventory.production.ini.example ansible/setup_k3s_production.yml
```

Kustomize validation passed:

```bash
kubectl kustomize kubernetes/apps/leantime
kubectl kustomize kubernetes/apps/gitlab
kubectl kustomize kubernetes/apps/wisemapping
kubectl kustomize kubernetes/platform/authentik
kubectl kustomize kubernetes/platform/cloudflared
kubectl kustomize kubernetes/platform/argocd
```

Targeted static scans passed for:

- No rendered GitOps placeholders under `kubernetes/gitops/root` or `kubernetes/gitops/apps`.
- `platform-cloudflare-tunnel` present in rendered GitOps apps.
- `kube-system` allowed by the platform AppProject.
- No stale `kubernetes/platform/cloudflare-tunnel.yaml` references in active README/scripts/manifests.
- No root-app `|| true` masking in `scripts/bootstrap-gitops.sh`.
- No `latest` image tags under `kubernetes/apps` or `kubernetes/platform`.
- No old Leantime placeholder DB passwords under production manifests or scripts.
- No broad `namespace: "*"` / `kind: "*"` AppProject policy.

## Production Launch Gate

```bash
bash scripts/validate-production-gate.sh
```

If origin HTTP URLs or IPs are known, prove they do not answer directly:

```bash
DIRECT_HTTP_URLS="http://<origin-ip> http://<origin-host>" bash scripts/validate-production-gate.sh
```

The launch gate must pass on the live cluster before launch.

## Remaining Launch Evidence Required

These items still require live environment execution and recorded output:

- Clean-host production k3s bootstrap.
- Secret seeding from real `scripts/production.env`.
- Argo CD install and full application sync.
- `scripts/validate-production-gate.sh` passing.
- Leantime login/onboarding smoke test.
- Backup creation and restore drill.
- Confirmation that direct plaintext HTTP access to the origin is blocked outside the trusted Cloudflare boundary.

## Current Gate

Code-level blockers from the latest review are remediated and ready for re-review. The remaining gate is operational proof from the live production environment.
