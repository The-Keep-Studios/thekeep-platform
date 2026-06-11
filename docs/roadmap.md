# Public Roadmap

The Keep Platform is a self-hosted operating stack, a reusable engineering
portfolio, and a foundation for internal and client-facing workflows. This
roadmap explains how public planning is organized without turning confidential
operations into public project data.

## Planning Systems

| System | Canonical responsibility | Public? |
| --- | --- | --- |
| GitHub | Source, public roadmap, architecture, implementation, bugs, installability, integrations | Yes |
| Leantime | Private execution, timeboxes, workload, client-specific tasks, sensitive planning | No |
| EspoCRM | Active job, sales, client, consulting, and publishing opportunities | No |
| Baserow | Relationship and organization memory that is not an active opportunity | No |
| Gmail | Communication source and evidence; not a canonical planning database | No |

The same fact should not silently become editable in every system. Integration
work must name the system of record, allowed readers, allowed writers, approval
requirements, and deletion behavior.

## Roadmap States

- **Now:** bounded work that improves the current platform without requiring an
  unresolved architecture or policy decision.
- **Next:** important work with known dependencies or sequencing constraints.
- **Research:** a spike or design task whose output is a decision, not an
  implied production commitment.
- **Later:** valuable work that should not increase current operational risk or
  distract from prerequisite controls.
- **Decision required:** work that needs explicit human product, legal,
  privacy, security, or branding direction.

These states are planning guidance, not delivery-date promises.

## Now

### Platform Clarity And Operability

- #13 documents the architecture and current operating model.
- #21 improves local bootstrap, prerequisites, troubleshooting, and clean
  environment validation.
- #26 isolates the Leantime UI root from its MCP endpoint. The implementation
  has merged; the remaining issue administration should confirm all acceptance
  evidence before closure.

### Public Planning

- #11 defines this planning model, public/private boundaries, and contribution
  expectations.

## Next

### Security And Integration Boundaries

- #18 defines canonical ownership and safe read/write boundaries across
  Leantime, EspoCRM, Baserow, GitHub, and Gmail.
- #20 defines the shared authentication, authorization, secrets, approval, and
  audit baseline.
- #22 defines an isolated synthetic demo dataset, reset model, and onboarding
  walkthrough.

These should be reviewed before enabling broad assistant write access or a
public demo environment.

### AI Platform Foundations

- #15 defines the internal LLM gateway, provider interface, permission model,
  audit events, and tool-call approval boundary.
- #16 defines consent-first meeting ingestion and portable meeting records.
- #17 defines permission-aware organizational memory and retrieval.
- #23 hardens the AI layer after #15 produces a concrete architecture.

Dependency direction:

```text
#18 integration ownership ─┐
#20 security baseline ─────┼─> #15 AI gateway ─> #23 hardening
                           ├─> #16 meeting intelligence
                           └─> #17 knowledge memory

#16 meeting intelligence ─────> #17 knowledge memory
```

## Research

### Call Assistant Backends

- #24 evaluates Vexa as a browser-independent meeting capture backend.
- #25 evaluates Amurex as a deployable component or upstream contribution
  target.

Neither candidate should be installed on production or trusted with meetings
until its licensing, consent model, retention, authentication, dependencies,
resource needs, and update path are understood.

### EspoCRM Assistant Boundary

- #29 compares existing EspoCRM MCP servers and should recommend build, wrap,
  fork, or upstream contribution.
- #28 defines the larger constrained assistant-facing EspoCRM capability.

#29 should inform #28 before a server implementation is selected. A broad
third-party CRUD server must not be exposed directly merely because it speaks
MCP.

## Later

- Highly available k3s control plane and replicated storage.
- Off-cluster immutable backups and scheduled restore drills.
- Encrypted/delegated secret management with SOPS or External Secrets.
- Automated Authentik provider and application reconciliation.
- Public demo hosting after synthetic-data isolation and reset controls exist.
- External/client AI workflows after the gateway and hardening controls are
  implemented and reviewed.

## Decision Required

### Licensing And Brand Policy

#12 proposes `AGPL-3.0-only` for platform source and separate treatment for
trademarks and brand assets. Adding a license changes the legal terms of the
repository and requires explicit maintainer approval of:

- code license and version;
- documentation and example licensing;
- treatment of screenshots and generated artifacts;
- ownership and allowed use of names, logos, and other brand assets;
- whether existing third-party or copied material can be relicensed.

Drafting may proceed, but the final policy should not be represented as adopted
until that decision is made.

## Issue Lifecycle

1. Use a category prefix from `CONTRIBUTING.md`.
2. Define verifiable acceptance criteria and dependencies.
3. Use one branch and pull request per issue.
4. Keep pull requests in draft while decisions or tests are incomplete.
5. Record validation evidence and unresolved operational risk.
6. Merge only after human review.
7. Deploy production changes separately with explicit approval.
8. Close an issue only after its acceptance criteria are actually satisfied.

Follow-up capability issues already exist as #12 through #29. Create additional
issues only when a discovered task is independently actionable; avoid duplicate
backlog entries for work already represented here.
