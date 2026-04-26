# Codex Production Readiness Review

Date: 2026-05-09

Verdict: **NO-GO**

The latest remediation is better than the previous Ansible attempt, but it still does not clear the bar.

Several prior issues were partially addressed:

- GitOps templates now appear to use Jinja rendering rather than literal `REPLACE_ME_GITOPS_` placeholders.
- `production_vars.yml` was moved out of tracked configuration and an example file was added.
- The playbook now checks that `production_vars.yml` exists.
- The playbook now rejects `CHANGE_ME` secret values.
- `direct_http_urls` is now required when external HTTPS validation is enabled.
- `python3-kubernetes` is now installed by the host role.
- The bad blanket HTTPS backend annotation approach appears to have been backed away from.

Those are real improvements.

But the system is still not approved. The validation logic remains unsafe, the GitOps source-of-truth guarantee is not actually enforced, and no live evidence exists.

## Blocking Findings

### 1. Direct-origin validation still accepts exposed origins

The new Ansible validation attempts to verify that direct HTTP origins are blocked.

It uses:

Junie explicitly states verification was done pre-deployment without a live cluster connected to the session.

That is not enough for final approval.

There is no attached proof that:

- the production Ansible playbook completed on the actual host;
- secrets were seeded successfully;
- Argo CD can fetch the rendered repo URL from inside the cluster;
- all active Argo applications are `Synced` and `Healthy`;
- Cloudflare Tunnel is connected;
- public hostnames route correctly;
- direct-origin HTTP is blocked;
- Prometheus and Alertmanager are actually protected;
- Leantime login works;
- Leantime can perform at least one write-path operation;
- a backup was created;
- a restore was tested.

For a final production/pilot gate, static review is not proof. The system must be run.

**Required before go:**

Run the launch gate on the real target and attach complete output.

### 2. The backup failure alert appears incorrectly placed

Junie claims `LeantimeBackupFailed` was added to `kubernetes/platform/monitoring/kube-prometheus-stack.values.yaml`.

It exists, but it appears under the `alertmanager:` block:

### 6. GitOps rendering inside Ansible is risky and likely not equivalent to the old script

The new role renders GitOps manifests with Ansible `template`.

That may work only if the GitOps template files are valid Jinja templates. The prior renderer likely performed placeholder substitution intentionally. This needs proof.

There is also a deeper process issue: rendering GitOps desired state locally during deployment means the cluster may apply manifests that are not committed/pushed. That undermines GitOps as the source of truth.

**Impact:** Argo can be pointed at Git state that does not contain what Ansible just applied.

**Required fix:** Preserve the rule: render, review, commit, push, then bootstrap Argo against committed desired state. If Ansible renders manifests, it must either fail unless the rendered files are committed/pushed or stop pretending this is GitOps.

### 7. The Ansible validation is weaker than the old script

The old script had explicit logic and printed clear pass/fail lines.

The new Ansible role:

- does not assert `direct_http_urls` is required;
- does not prove endpoint content or app correctness;
- does not run a Leantime functional smoke test;
- does not trigger a backup;
- does not verify backup restore/readability;
- does not verify the PrometheusRule exists after reconciliation;
- does not prove Cloudflare Access headers/challenge behavior;
- does not prove Argo can refetch repo after repo-server restart.

**Impact:** The new gate is more convenient but less convincing.

### 8. No live evidence exists

Junie’s report again describes static verification and role review. It does not attach real deployment output.

Still missing:

- Ansible production playbook output from target host;
- Argo applications all `Synced` and `Healthy`;
- cloudflared connected and routing;
- external HTTPS endpoint results;
- direct-origin block results;
- protected monitoring auth proof;
- Leantime login/write smoke test;
- backup creation;
- restore or dump verification.

No live proof, no approval.

## Positive Notes

The direction is not worthless:

- Ansible-first workflow is the right operator interface.
- GitLab removal remains a good scope reduction.
- Reverting the bad blanket HTTPS backend annotations was correct.
- Backup alert placement was previously corrected.
- Deprecating legacy scripts is reasonable once Ansible reaches parity.

But this implementation is not at parity.

## Required Fixes Before Reconsideration

1. Add Ansible preflight assertions for all required variables and secrets.
2. Fail if any required secret is unset or equal to `CHANGE_ME`.
3. Move real secrets out of tracked `group_vars/all.yml` into Ansible Vault/SOPS/ignored vault files.
4. Make `direct_http_urls` mandatory when external HTTPS is required.
5. Rewrite direct-origin checks so connection failure is pass and any HTTP response is fail.
6. Integrate Argo private repo credentials into Ansible or make it a hard required pre-step.
7. Prove rendered GitOps manifests match committed/pushed Git state before applying root apps.
8. Run the full playbook on the target host.
9. Attach complete validation output.
10. Prove Leantime works and backups are usable.

## Final Position

**NO-GO.**

This latest remediation improves ergonomics but breaks the safety model. Convenience is not a substitute for a correct launch gate.

I would reconsider only after the Ansible workflow fails closed, secrets are handled safely, GitOps source-of-truth semantics are preserved, and live target-cluster evidence is provided.