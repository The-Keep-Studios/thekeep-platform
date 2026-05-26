---
apply: always
---

# Engineering Best Practices

These rules apply to human engineers and AI agents working in this repository. They are intentionally practical: keep changes understandable, reversible, observable, and aligned with GitOps.

For purpose, tradeoff, sequencing, and organizational judgment, also follow `Senior Engineering Judgment.md`.

## Working Principles

- Read the nearby code, manifests, playbooks, and docs before changing them.
- Prefer the smallest durable change that solves the current problem.
- Follow existing repository patterns unless there is a clear reason to change them.
- Keep the operational path boring: predictable commands, explicit inputs, and reviewable output.
- Distinguish facts from assumptions. If production state matters, verify it directly.
- Do not hide important work behind clever automation.

## Scope And Ownership

- One branch should have one purpose.
- Do not mix hotfixes, feature work, cleanup, documentation rewrites, and project-management artifacts unless the user explicitly asks for that bundle.
- Leave unrelated files alone, especially when the worktree is already dirty.
- Never revert or overwrite another person's changes without explicit approval.
- If a task uncovers a separate issue, document it and decide whether it belongs in this branch.

## Git And Branch Hygiene

- Check the current branch and worktree state before editing.
- Use clear branch names that describe the reason for the change.
- Keep commits reviewable. A reviewer should be able to tell what changed and why without reconstructing the whole conversation.
- Before merge, confirm that generated GitOps manifests and rendered templates agree.
- Do not leave feature branch `targetRevision` values in manifests intended for `main`.
- Avoid committing local scratch files unless they are intentionally part of the repo.

## Infrastructure And GitOps

- Git is the long-term source of truth. Manual cluster changes are temporary unless reconciled into Git.
- Treat `kubectl`, Argo CD syncs, Helm operations, and production Ansible playbooks as live infrastructure changes.
- State the target user, host, kubeconfig context, namespace, and application before giving or running live commands.
- Prefer dry runs, diffs, and read-only inspection before applying changes.
- For stateful workloads, identify persistence, backup, restore, and migration impact before changing storage, selectors, names, or chart families.
- Do not delete or recreate stateful resources without confirming data ownership, PVC behavior, and rollback.
- If an immutable Kubernetes field blocks a rollout, explain the migration path instead of forcing through it blindly.

## Secrets And Credentials

- Never commit secrets, tokens, passwords, kubeconfigs, private keys, or provider credentials.
- Do not paste secrets into logs, issue comments, PR descriptions, screenshots, or AI prompts.
- Redact secrets when showing command output.
- Keep production vars local unless the repository has an approved encrypted secret workflow.
- Do not invent credential workflows. Use documented provider, Kubernetes, or Ansible secret paths.

## Testing And Evidence

- Tests should match the risk of the change.
- Before changing behavior, identify the failing check, reproduction, or observation that should prove the issue exists.
- After changing behavior, run the smallest relevant test first, then broader checks when risk justifies them.
- For static IaC changes, run the repository static checks when available.
- For Ansible changes, run syntax checks or the relevant playbook path before claiming readiness.
- For app changes, run local k3d smoke tests or observation checks when practical.
- For production validation, capture evidence: Argo CD sync and health, pod readiness, service endpoints, logs, and user-visible behavior.
- Report what was tested and what was not tested.
- Do not treat a successful apply as proof that the feature works. Verify the user-facing behavior.

## Compatibility And Dependencies

- Before changing public APIs, schemas, config keys, CLI behavior, environment variables, or persisted data formats, check callers and migration paths.
- Prefer backward-compatible changes unless a breaking change is intentional, documented, and coordinated.
- Do not add production dependencies without a clear reason.
- Prefer the standard library, existing dependencies, or small local code when they solve the problem cleanly.
- If a dependency is added, explain its operational cost, update path, and ownership.

## Observability And Operations

- Every user-facing service should have a practical way to answer: is it up, is it healthy, and what failed?
- Prefer structured dashboards, log queries, and alerts over ad-hoc debugging commands.
- When fixing an outage, preserve the useful investigation trail in docs or runbooks.
- Add or update validation checks when a failure mode is likely to recur.
- Plan rollback before rollout for changes that affect ingress, auth, storage, email, or observability.

## AI Agent Safety Rules

- Ask before running destructive commands, privileged commands, live cluster mutations, production playbooks, or anything that writes outside the repository.
- Ask before creating executable scripts that can mutate production systems, SaaS APIs, databases, or project-management tools.
- Prefer reviewable scratch artifacts, JSON payloads, dry-run commands, and explicit copy/paste instructions for one-time operational work.
- Do not directly write application data into production databases unless the human explicitly approves the exact command and rollback plan.
- Do not assume a local machine is a control plane node. State where a command must run.
- Do not silently use `sudo`, switch users, or rely on shell state that the human cannot easily audit.
- When uncertain, stop and ask a narrow question instead of expanding the implementation.

## Human Engineer Expectations

- Bring judgment about product intent, risk, and tradeoffs. Tools can propose, but humans own the decision.
- Review generated changes as if they came from a junior engineer with high output and uneven context.
- Verify live commands before running them, including user, host, namespace, branch, and target revision.
- Protect production secrets and customer data from unnecessary exposure.
- Prefer reversible, observable changes over fast hidden fixes.

## Definition Of Done

A change is ready when:

- The implementation is committed to the right layer: Ansible, GitOps manifests, Helm values, app config, or docs.
- The branch scope is clear.
- Relevant checks were run and results are known.
- User-visible behavior was verified when the change affects users.
- Rollout and rollback paths are understood.
- Documentation or runbooks were updated when behavior, commands, or operations changed.
- The diff was reviewed by the author or agent before handoff, including accidental changes, naming, formatting, and hidden assumptions.

## Anti-Patterns

- Applying a live fix and never reconciling it into Git.
- Mixing unrelated production fixes into a feature branch.
- Adding a dependency because it is convenient rather than because it is worth owning.
- Treating generated files, local scratch data, or copied secrets as harmless.
- Replacing a clear manual runbook with opaque automation for a one-time task.
- Declaring success from Kubernetes health alone when the app UI or workflow still fails.
- Debugging only from the command line when the actual user experience is broken.
