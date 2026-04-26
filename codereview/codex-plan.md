### Revised Plan to Resolve Production Readiness Blockers

This plan is not approved for implementation until reviewed by the user. The key correction is that Ansible must not mutate GitOps desired-state files during production deployment and then apply those local mutations. Argo CD must reconcile only committed, pushed Git state.

#### 1. Fix Remaining GitOps Template Issues

- Convert remaining monitoring `repoURL` and `targetRevision` entries in `kubernetes/gitops/templates/platform-applications.yaml` to valid Jinja values:
    - `{{ gitops_repo_url }}`
    - `{{ gitops_revision }}`
- Ensure rendered output is quoted consistently where needed.
- Add/keep a hard placeholder check against rendered GitOps output:
    - fail if any `REPLACE_ME_GITOPS_` remains.

#### 2. Correct the GitOps Source-of-Truth Flow

- Stop rendering templates directly into committed GitOps paths during the production deploy role.
- Instead, render GitOps templates to a temporary directory.
- Compare the temporary render against committed files under:
    - `kubernetes/gitops/root`
    - `kubernetes/gitops/apps`
- Fail if rendered desired state differs from committed desired state.
- This means the required flow is:
    1. render/update GitOps files before deploy;
    2. review, commit, and push those files;
    3. run production Ansible deployment;
    4. Ansible verifies committed Git state matches expected render before touching Argo apps.

#### 3. Harden Git State Checks

Update `ansible/roles/platform_gitops/tasks/main.yml` so deployment fails closed when GitOps state is not clean.

Required checks:

- no unstaged changes in GitOps paths;
- no staged changes in GitOps paths via `git diff --cached --exit-code`;
- no untracked files in GitOps paths;
- no unresolved placeholders in committed/rendered GitOps manifests;
- local `HEAD` must match the configured GitOps target:
    - compare against `gitops_repo_url`;
    - compare against `gitops_revision`;
    - handle branch, tag, or explicit commit SHA intentionally;
- remove `ignore_errors: true`.

#### 4. Move Production Preflight Before Cluster Changes

Fix `ansible/setup_k3s_production.yml` so friendly validation happens before Ansible tries to load missing vars.

- Replace `vars_files` loading of `production_vars.yml` with:
    - `stat`;
    - fail if missing;
    - `include_vars` only after existence is confirmed.
- Fail before touching the cluster if:
    - `production_vars.yml` is missing;
    - required secret keys are missing;
    - any required secret is empty or whitespace-only;
    - any required secret is a placeholder such as `CHANGE_ME`, `changeme`, `REPLACE_ME`, `replace_me`, `TODO`, or example values;
    - `require_external_https=true` and `direct_http_urls` is empty.

#### 5. Handle Private GitOps Repository Access Explicitly

Add a hard gate for private GitOps repositories.

- If the GitOps repo is private, Ansible must either:
    - create/configure the Argo CD repository credential Secret; or
    - fail before bootstrap with a clear message explaining the missing credential.
- Do not leave private repo credential setup as optional if `gitops_repo_private=true`.

#### 6. Verify Monitoring Alert Rendering and Reconciliation

- Confirm the `kube-prometheus-stack` chart version `82.14.0` accepts the current top-level `additionalPrometheusRulesMap`.
- Prove it with `helm template`, verifying a rendered `PrometheusRule` contains `LeantimeBackupFailed`.
- After live reconciliation, verify the in-cluster `PrometheusRule` exists and contains the alert.

#### 7. Harden Production Validation

Update `ansible/roles/platform_validation/tasks/main.yml`.

- Direct-origin validation must fail on any HTTP response:
    - timeout / refused / no route = pass;
    - `200`, `301`, `302`, `401`, `403`, `404`, TLS mismatch response, default ingress page, or any other HTTP response = fail.
- Do not use fake accepted Ansible `uri` status codes like `[-1, 0, 403, 404]`.
- Use controlled `curl` behavior or Ansible `block`/`rescue`.
- Add concrete live-cluster checks:
    - Kubernetes API reachable;
    - expected Argo applications exist;
    - Argo apps are `Synced` and `Healthy`;
    - required deployments/resources exist;
    - validation fails if endpoint checks are skipped unintentionally.

#### 8. Make Backup Validation Required

Backup validation should not be optional for the internal pilot.

Required checks:

- `leantime-db-backup` CronJob exists;
- trigger or verify a backup Job;
- confirm a new backup artifact exists;
- confirm the artifact is non-empty;
- ideally confirm the gzip/sql is readable.

Restore can remain a manual same-day verification if needed, but backup creation/readability must be part of the gate.

#### 9. Fix Documentation Drift

Update `README.md` so the migration section no longer tells users to put secrets in `ansible/group_vars/all.yml`.

It should point to:

- `ansible/production_vars.yml`, or
- a future encrypted/ignored production vars file.

Also clarify that rendered GitOps manifests must be committed and pushed before production deployment.

#### 10. Live Evidence Requirement

Do not claim final GO until the live gate has actually run.

Final evidence should include:

- production playbook output;
- Git clean/pushed verification;
- placeholder check output;
- Argo app sync/health output;
- Cloudflare HTTPS endpoint results;
- direct-origin blocked results;
- PrometheusRule verification;
- Leantime backup artifact verification.