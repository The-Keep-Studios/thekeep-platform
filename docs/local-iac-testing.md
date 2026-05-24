# Local IaC Testing

This repo should catch infrastructure breakage before changes hit the live k3s cluster.

The local path has two layers:

1. Static checks that do not need a cluster.
2. A disposable k3d cluster for workload smoke tests.

## Prerequisites

- Docker or a compatible container runtime.
- `kubectl`
- `k3d`
- `ansible-playbook`
- Optional: `kubeconform` or `kubeval` for stricter rendered manifest validation.

## Static Checks

Run:

```bash
scripts/test-iac-static.sh
```

This checks:

- Git whitespace with `git diff --check`.
- Shell syntax for `scripts/*.sh`.
- Kustomize rendering for every `kubernetes/**/kustomization.yaml`.
- Optional schema validation if `kubeconform` or `kubeval` is installed.
- Ansible syntax for `ansible/setup_k3s_production.yml`.

Kustomizations with remote bases are skipped by default so the check works without network access. To include remote bases:

```bash
IAC_STATIC_INCLUDE_REMOTE=true scripts/test-iac-static.sh
```

This is the first check to run before committing an IaC change.

## Ansible Workstation Setup

Use the Ansible entrypoint when you want one command to prepare and validate a local development environment:

```bash
ansible-playbook -i ansible/inventory.ini ansible/setup_dev_environment.yml
```

By default this runs the `wisemapping` profile:

- static IaC checks;
- Docker/k3d preflight checks;
- local k3d cluster creation or reuse;
- WiseMapping smoke test.

If `k3d` is not installed, either install it yourself or allow Ansible to install it with the upstream k3d install script:

```bash
ansible-playbook -K -i ansible/inventory.ini ansible/setup_dev_environment.yml \
  -e local_dev_install_k3d=true
```

The playbook does not install Docker. Docker installation and group membership differ enough by workstation that this should remain an explicit developer setup step.

For static checks only:

```bash
ansible-playbook -i ansible/inventory.ini ansible/setup_dev_environment.yml \
  -e local_dev_profile=static
```

For workstation-specific overrides:

```bash
cp ansible/dev_vars.yml.example ansible/dev_vars.yml
```

`ansible/dev_vars.yml` is ignored by Git.

## Disposable k3s Cluster

Create or reuse a local k3d cluster:

```bash
scripts/dev-cluster-up.sh
```

Delete it when finished:

```bash
scripts/dev-cluster-down.sh
```

Defaults:

```text
K3D_CLUSTER_NAME=thekeep-dev
K3S_VERSION=v1.35.3+k3s1
K3D_IMAGE=rancher/k3s:v1.35.3-k3s1
```

Override any of those values in the environment if a workstation needs a different k3s image.

## WiseMapping Smoke Test

Run:

```bash
scripts/dev-wisemapping-smoke.sh
```

The smoke test:

- Creates the disposable k3d cluster if it does not exist.
- Creates stable dev-only WiseMapping secrets.
- Applies `kubernetes/apps/wisemapping`.
- Waits for Postgres and WiseMapping rollouts.
- Probes `http://wisemapping/api/restful/app/config` from inside the cluster with:

```text
Host: mindmaps.thekeepstudios.com
X-Forwarded-Proto: https
```

That endpoint is intentionally used because the WiseMapping nginx frontend can serve `/` even when the Spring API process is down.

The dev secrets are intentionally deterministic so repeated runs do not desync the app from an existing local Postgres PVC. Override them only when you are also deleting the dev cluster or PVC:

```bash
WISEMAPPING_DEV_POSTGRES_PASSWORD=dev-pass scripts/dev-wisemapping-smoke.sh
```

## Limits

This local path does not replace production validation.

It does not test:

- Cloudflare Tunnel.
- External DNS.
- Real TLS edge behavior.
- Authentik integration.
- Argo CD app-of-apps reconciliation.
- Production backup and restore gates.

Use it to catch render errors, startup failures, and service-level smoke test failures before pushing a branch to Argo CD.
