# Codex Production Readiness Review

Date: 2026-05-09

Verdict: **NO-GO. Do not launch the internal pilot from this state.**

This remediation fixes several prior issues. Secrets were moved out of tracked `group_vars`, `direct_http_urls` is now required when HTTPS validation is enabled, `python3-kubernetes` is installed by the host role, and most GitOps templates now use Jinja.

Still no-go. The new Ansible-first path still cannot complete safely: the GitOps templates are only partially converted and the latest commits are not pushed to the configured remote branch.

## Blocking Findings

### 1. GitOps template rendering is still broken for monitoring apps

Most template placeholders were converted to Jinja, but two source entries still contain literal placeholders:

- `kubernetes/gitops/templates/platform-applications.yaml:103-104`
- `kubernetes/gitops/templates/platform-applications.yaml:132-133`

Current template content still includes:

```yaml
repoURL: REPLACE_ME_GITOPS_REPO_URL
targetRevision: REPLACE_ME_GITOPS_REVISION
```

I rendered the template with Ansible into `/tmp`. The app sources rendered correctly, but the Prometheus and Loki value-source entries still contained unresolved placeholders:

```text
103:  - repoURL: REPLACE_ME_GITOPS_REPO_URL
104:    targetRevision: REPLACE_ME_GITOPS_REVISION
132:  - repoURL: REPLACE_ME_GITOPS_REPO_URL
133:    targetRevision: REPLACE_ME_GITOPS_REVISION
```

The new guard catches this:

- `ansible/roles/platform_gitops/tasks/main.yml:123-128`

That is good, but the result is still a failed production playbook. This must be fixed before launch.

### 2. Latest remediation is not pushed to the GitOps remote

Local `HEAD`:

```text
a341f9d586e1e9b09c0ecff5faf67a1559a00c40
```

Configured remote branch:

```text
6849ac36ed35d020d483209c7a52718ed6b8be58 refs/heads/feature/productionReadyK8s
```

Argo CD reconciles the remote branch, not the local checkout. The remote is missing the latest Ansible remediation commits.

This alone is a no-go. Even if the local code were perfect, Argo would not fetch it.

### 3. The GitOps source-of-truth guard is ineffective

The role claims to enforce committed/pushed manifests, but the check is weak:

- `ansible/roles/platform_gitops/tasks/main.yml:130-140`

Problems:

- It uses `git diff --exit-code`, which only checks local tracked working-tree differences.
- It does not check staged changes.
- It does not check whether `HEAD` is pushed to the configured remote.
- It has `ignore_errors: true`, so even a detected diff does not stop deployment.

This does not preserve GitOps source of truth. For a production gate, this should fail if rendered manifests differ, if the tree is dirty, or if `HEAD` is not present on the configured remote target revision.

### 4. No live launch evidence exists

Still missing:

- production Ansible run on the target host
- secrets loaded from real non-placeholder `ansible/production_vars.yml`
- Argo repo credentials configured and verified
- all expected Argo apps `Synced` and `Healthy`
- Cloudflare Tunnel connected with correct public hostname origin settings
- public HTTPS endpoints passing through Cloudflare
- direct origin HTTP blocked using real origin URLs
- Leantime login/write smoke test
- backup creation and restore test

Static checks are not live release evidence.

## Resolved Since Last Review

- Active production Ingresses remain at `serversscheme: http`, so the prior HTTPS-to-HTTP-backend regression is fixed.
- `cloudflared` no longer carries the ineffective `--no-tls-verify`.
- README points Cloudflare at `traefik.kube-system.svc.cluster.local`, not pod-local `localhost`.
- `ansible/production_vars.yml` is ignored by Git and `ansible/production_vars.yml.example` is tracked.
- `platform_secrets` were removed from tracked `ansible/group_vars/all.yml`.
- The production playbook checks for `"CHANGE_ME"` secret values: `ansible/setup_k3s_production.yml:21-27`.
- `direct_http_urls` now fails closed when HTTPS validation is enabled: `ansible/roles/platform_validation/tasks/main.yml:72-78`.
- `python3-kubernetes` is installed by `k3s_host`: `ansible/roles/k3s_host/tasks/main.yml:14-20`.

## Validation Performed

Passed:

```bash
git diff --check
find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

Passed:

```bash
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check site.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check ansible/site.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i ansible/inventory.ini ansible/setup_k3s_demo.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i ansible/inventory.production.ini.example ansible/setup_k3s_production.yml
```

Passed:

```bash
kubectl kustomize kubernetes/apps/leantime
kubectl kustomize kubernetes/apps/wisemapping
kubectl kustomize kubernetes/apps/gitlab
kubectl kustomize kubernetes/platform/authentik
kubectl kustomize kubernetes/platform/cloudflared
kubectl kustomize kubernetes/platform/argocd
```

Failed gate checks:

- Ansible rendering of `platform-applications.yaml` still leaves `REPLACE_ME_GITOPS_*` placeholders.
- Configured remote branch does not contain current `HEAD`.

## Minimum Conditions To Change Verdict

1. Convert the remaining monitoring repo/revision placeholders in `platform-applications.yaml` to Jinja variables.
2. Re-run the Ansible render and prove no `REPLACE_ME_GITOPS_` tokens remain.
3. Replace the ignored `git diff` check with a real fail-closed source-of-truth check.
4. Push current `HEAD` to the configured GitOps remote branch and prove it with `git ls-remote`.
5. Run the production playbook on the real target host with real `production_vars.yml`.
6. Attach live proof: Argo apps `Synced/Healthy`, Cloudflare connected, direct-origin HTTP blocked, Leantime smoke test passed, and backup creation/restore completed.

Final position: **NO-GO.** This is close structurally, but the current Ansible path still fails before it can safely launch.
