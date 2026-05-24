# Local IaC Testing

This repo should catch infrastructure breakage before changes hit the live k3s cluster.

The local path has three layers:

1. Static checks that do not need a cluster.
2. A disposable k3d cluster for workload smoke tests.
3. Browser observation against the running local app.

## Prerequisites

- Docker or a compatible container runtime.
- `kubectl`
- `k3d`
- `ansible-playbook`
- Enough free disk for k3d image storage and local PVCs. The default preflight
  requires at least 80 GiB and 8% free on the repo filesystem.
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

By default this runs the `platform` profile:

- static IaC checks;
- Docker/k3d preflight checks;
- local k3d cluster creation or reuse;
- app smoke tests.

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

Supported profiles:

```text
static       Static IaC checks only.
wisemapping  Static checks, k3d cluster, WiseMapping smoke test.
leantime     Static checks, k3d cluster, Leantime smoke test.
platform     Static checks, k3d cluster, all local app smoke tests.
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

The local scripts fail early when the workstation is low on disk or when the
k3d node already has `disk-pressure`, `memory-pressure`, or `pid-pressure`
taints. k3d/k3s uses the host filesystem as node ephemeral storage, so a nearly
full workstation can cause Kubernetes to evict otherwise healthy local app pods.

For constrained single-app testing, lower the disk guard explicitly:

```bash
DEV_MIN_FREE_GIB=50 scripts/dev-smoke.sh wisemapping
```

Skip the guard only when you intentionally want to continue against a degraded
local cluster:

```bash
DEV_SKIP_DISK_PREFLIGHT=true DEV_SKIP_NODE_PRESSURE_PREFLIGHT=true scripts/dev-smoke.sh platform
```

## App Smoke Tests

Use the generic target-based smoke entrypoint:

```bash
scripts/dev-smoke.sh wisemapping
scripts/dev-smoke.sh leantime
scripts/dev-smoke.sh platform
```

Compatibility wrappers are also available:

```bash
scripts/dev-wisemapping-smoke.sh
scripts/dev-leantime-smoke.sh
scripts/dev-platform-smoke.sh
```

The smoke scripts:

- Creates the disposable k3d cluster if it does not exist.
- Create stable dev-only secrets for the target app.
- Apply the app manifests.
- Wait for database and app rollouts.
- Probe an app-specific endpoint from inside the cluster.

WiseMapping probes `http://wisemapping/api/restful/app/config` with:

```text
Host: mindmaps.thekeepstudios.com
X-Forwarded-Proto: https
```

That endpoint is intentionally used because the WiseMapping nginx frontend can serve `/` even when the Spring API process is down.

Leantime probes `http://leantime/auth/login` with:

```text
Host: projects.thekeepstudios.com
X-Forwarded-Proto: https
```

The dev secrets are intentionally deterministic so repeated runs do not desync apps from existing local database PVCs. Override them only when you are also deleting the dev cluster or PVC:

```bash
WISEMAPPING_DEV_POSTGRES_PASSWORD=dev-pass scripts/dev-wisemapping-smoke.sh
LEANTIME_DEV_DB_PASSWORD=dev-pass scripts/dev-leantime-smoke.sh
```

## App Manual Observation

After smoke tests pass, open the actual running app:

```bash
scripts/dev-observe.sh wisemapping
scripts/dev-observe.sh leantime
scripts/dev-observe.sh platform
```

Compatibility wrappers are also available:

```bash
scripts/dev-wisemapping-observe.sh
scripts/dev-leantime-observe.sh
scripts/dev-platform-observe.sh
```

The observe scripts:

- patch local dev-cluster app config to a localhost base URL where needed;
- port-forward the target service;
- verify an app-specific probe path through the port-forward;
- open the app in your desktop browser when `xdg-open` is available;
- capture browser artifacts under `.artifacts/dev-observe/`.

Default local URLs:

```text
WiseMapping: http://localhost:18081
Leantime:    http://localhost:18080
```

The artifacts include:

- `probe-response.html`
- `<target>-home.png`
- `<target>-home.html`
- Chromium capture logs when Chromium is available
- `port-forward.log`

This gives both a human inspection path and a shareable artifact path for agent/debug review.

The config patches are local-cluster only. They prevent the browser from following production base URLs while inspecting apps through localhost port-forwards.

If a page loaded and then stops loading, first check whether the observe command
is still running. The localhost URLs depend on its port-forwards. If the command
is still running but pods are `Pending` or `Unknown`, check node pressure:

```bash
kubectl get nodes
kubectl describe node k3d-thekeep-dev-server-0 | grep -A8 '^Taints:\|^Conditions:'
```

If the node is under disk pressure, free host disk space and recreate the
disposable local cluster:

```bash
scripts/dev-cluster-down.sh
scripts/dev-smoke.sh platform
```

For a non-interactive capture that exits immediately:

```bash
DEV_OBSERVE_OPEN=false DEV_OBSERVE_HOLD=false scripts/dev-observe.sh platform
```

Useful overrides:

```bash
WISEMAPPING_OBSERVE_PORT=18082 scripts/dev-observe.sh wisemapping
LEANTIME_OBSERVE_PORT=18083 scripts/dev-observe.sh leantime
DEV_OBSERVE_ARTIFACT_ROOT=/tmp/platform-observe scripts/dev-observe.sh platform
DEV_OBSERVE_PATCH_CONFIG=false scripts/dev-observe.sh wisemapping
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
