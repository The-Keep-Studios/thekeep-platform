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

## App Support Versus App Instances

TKP public app support and private app instances are different artifacts.

Public app support belongs in this repository. It answers: can TKP deploy and
operate this type of app safely? Public support can include Kubernetes
manifests, Helm values, validation scripts, example secret keys, backup shape,
access-boundary guidance, and docs for operators.

Private app instances belong in an installation repository, ignored local vars,
or another private operator-controlled source. They answer: which concrete
instances run for this installation? Instance config includes real hostnames,
secret names, storage/database bindings, account identifiers, provider
credentials, and client-specific policy.

The first model is documentation and naming convention only. Add Ansible vars,
Helm values, Kustomize overlays, or generated Applications later only when at
least two supported apps need the same concrete instance machinery.

### Minimal Instance Schema

Use this shape when documenting or privately configuring an instance. Examples
must use fake domains and fake secret names only.

```yaml
app_instances:
  - app_type: baserow
    instance_name: example-client-baserow
    namespace: example-client-baserow
    hostname: data.example-client.invalid
    access_policy: internal-authenticated
    exposure:
      public_ingress: true
      cloudflare_tunnel_route: true
    storage:
      pvc_prefix: example-client-baserow
      database_binding: example-client-baserow-db
    secrets:
      app_secret_ref: example-client-baserow-app-secret
      oidc_secret_ref: example-client-baserow-oidc-secret
    backups:
      enabled: true
      schedule: "17 3 * * *"
      retention: 14d
```

Required fields:

- `app_type`: supported app family, such as `baserow`, `postiz`, `mixpost`, or `dmarc-monitor`.
- `instance_name`: DNS-safe instance identifier used as the resource prefix.
- `namespace`: Kubernetes namespace for the instance.
- `hostname`: concrete route for the instance, kept private unless it is a safe fake example.
- `access_policy`: intended boundary, such as `internal-only`, `internal-authenticated`, or `public-readonly`.
- `storage` / `database_binding`: names or references that keep PVCs and databases unique per instance.
- `secrets`: references to Kubernetes Secrets or external secret objects, never literal secret values.
- `backups`: whether durable data is backed up, on what schedule, and with what retention expectation.

Optional fields can include resource sizing, ingress class, OAuth client refs,
mailbox refs, alert routing, restore runbook, or service-specific feature flags.

### Naming And Isolation Rules

- Use one namespace per externally meaningful app instance unless there is a documented reason to share.
- Prefix Deployments, Services, PVCs, database names, backup jobs, and secret refs with `instance_name`.
- Never reuse a PVC, database, hostname, OAuth client, mailbox, or social-provider credential across unrelated instances.
- Keep secret values in platform secret storage or a private installation repo; public examples may document keys and fake refs only.
- Public app support may define `secret.example.yaml` files with required keys, but concrete secret names and values are installation-level decisions.
- If an app supports multiple organizations inside one runtime, still document whether TKP treats that as one shared instance or several isolated instances.

### Candidate Consumers

Postiz (#50), Mixpost (#51), and DMARC monitoring (#67) should consume this
model before adding real deployment support. Their public app support can define
runtime requirements and validation commands here, while concrete domains,
mailboxes, social-provider credentials, and client-specific settings stay in
private installation configuration.

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
