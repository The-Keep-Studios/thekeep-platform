# App Support Contract

This contract defines the smallest repeatable pattern for adding or changing a supported app in The Keep Platform.

The goal is not to template every app into sameness. The goal is to make the expected shape explicit so humans and agents can add services without inferring the pattern from several near-copies.

## Scope

Use this contract for apps managed by this repository through Kubernetes manifests, Helm values, Ansible-rendered secrets, Argo CD applications, or local dev smoke/observe scripts.

Do not use this contract to justify broad rewrites. Existing app manifests can remain explicit when that makes security, storage, or runtime behavior easier to review.

## Required App Shape

Each supported app should define these boundaries deliberately:

- Purpose: why the app belongs on the platform and whether it is internal, public, optional, demo-only, or production-supported.
- Runtime owner: whether day-2 operation is GitOps-only, Ansible-seeded, or still partly manual.
- Namespace: the Kubernetes namespace that owns the app resources.
- Workloads: Deployments, StatefulSets, Jobs, or CronJobs the app needs.
- Storage: PVCs, backup targets, restore expectations, and whether data is disposable.
- Secrets: secret names, required keys, source of truth, and whether values are operator-provided.
- Config: ConfigMaps, environment variables, rendered templates, and which values are public support config versus private installation config.
- Networking: Services, Ingresses, hostnames, Cloudflare assumptions, and auth boundary.
- Health: startup, readiness, and liveness probes with paths that prove the real backend is healthy.
- Backups: CronJob or documented reason backups are not required.
- Validation: local render/static checks, dev smoke target, observe target, and production validation evidence.
- Rollback: what to revert if the app breaks after merge or deploy.

## File Layout

Prefer this shape when adding a Kubernetes-managed app:

```text
kubernetes/apps/<app>/
  kustomization.yaml
  production.yaml
  backup-cronjob.yaml       # when the app has durable data
  secret.example.yaml       # when operators must provide Kubernetes secrets

scripts/
  dev-<app>-smoke.sh        # wrapper to scripts/dev-smoke.sh <app>
  dev-<app>-observe.sh      # wrapper to scripts/dev-observe.sh <app>
```

Use `standalone.yaml` only when the app is intentionally demo/lab-only or not yet production-supported.

If an app needs Ansible support, keep that boundary explicit:

```text
ansible/roles/<app>_*/      # app-specific host or Kubernetes setup
ansible/*_vars.yml.example  # operator-visible configuration examples
```

## Configuration Boundaries

Keep public app support configuration separate from private installation configuration.

Public support configuration belongs in tracked files when it is safe and reusable:

- Kubernetes manifests and Helm values.
- `*.example` files that document required secret keys without real values.
- README or docs explaining expected hostnames, auth boundaries, and validation steps.
- Ansible defaults that are not secrets and are safe for every installation.

Private installation configuration does not belong in Git:

- production passwords, tokens, kubeconfigs, and private keys;
- local inventory and production vars files;
- one-off hostnames or customer-specific values not intended as the platform default;
- generated artifacts, screenshots, browser captures, and local agent memory.

When a value is required but private, add an example key and document where the operator sets it.

## Manifest Rules

Kubernetes manifests should be explicit enough for review:

- Use one namespace per app unless the app is intentionally part of a shared platform namespace.
- Pin third-party app image tags. Avoid mutable tags for production-supported workloads.
- Set resource requests and limits for long-running workloads.
- Prefer named ports and reference them from probes and Services.
- Use readiness probes that validate the app's real serving path, not only that a container accepts TCP.
- Make hostnames and public URLs obvious in the manifest or documented config.
- Keep Ingress auth and Cloudflare assumptions visible.
- Add backup CronJobs for durable app databases or document why the data is disposable.

Do not introduce Helm, generators, or custom templating only to reduce line count. Add abstraction only when it reduces repeated mistakes and keeps review easy.

## Dev Smoke And Observe Contract

Apps that can run in the local dev cluster should have both:

- `scripts/dev-<app>-smoke.sh`: deploys or validates the app through `scripts/dev-smoke.sh <app>`.
- `scripts/dev-<app>-observe.sh`: opens or captures local observation through `scripts/dev-observe.sh <app>`.

The shared smoke/observe implementation should know:

- namespace;
- primary deployment;
- service and port;
- expected host header;
- probe path;
- response pattern that proves the real app is responding;
- any dev-only secret defaults needed for a disposable local cluster.

Wrappers may remain small aliases for ergonomics. Put reusable target behavior in shared scripts rather than duplicating case logic across wrappers.

## Validation Checklist

Before opening a PR for an app-support change, include the relevant evidence in the PR body:

- `scripts/test-iac-static.sh` for static render and Ansible syntax coverage.
- App-specific dev smoke command when local cluster validation is practical.
- App-specific observe command or captured artifact when UI/routing behavior matters.
- `kubectl kustomize kubernetes/apps/<app>` output check for manifest changes.
- Ansible syntax check when playbooks, roles, or vars examples change.
- Backup/restore evidence when the change touches durable data.
- Rollback notes that another engineer can follow.

If a check is not practical, state why and name the next best evidence.

## Example: Baserow

The current Baserow app follows the intended pattern:

| Contract item | Baserow location |
| --- | --- |
| Namespace and workloads | `kubernetes/apps/baserow/production.yaml` |
| Kustomize entrypoint | `kubernetes/apps/baserow/kustomization.yaml` |
| Secret example | `kubernetes/apps/baserow/secret.example.yaml` |
| Durable data backup | `kubernetes/apps/baserow/backup-cronjob.yaml` |
| Dev smoke wrapper | `scripts/dev-baserow-smoke.sh` |
| Dev observe wrapper | `scripts/dev-baserow-observe.sh` |
| Shared smoke behavior | `scripts/dev-smoke.sh` |
| Shared observe behavior | `scripts/dev-observe.sh` |

This does not mean every app must copy Baserow line-for-line. It means each app should make the same boundaries visible.

## Agent PR Rules

Agent-authored app-support PRs should stay narrow:

- Link the issue they address.
- State whether the PR changes runtime behavior, documentation only, or validation only.
- Preserve existing app entrypoints unless the issue explicitly asks to remove them.
- Do not bundle unrelated app cleanup with feature work.
- Do not claim an issue is closed unless every acceptance criterion is satisfied.
- Leave follow-up issues for deferred validation, hardening, or abstraction work.
