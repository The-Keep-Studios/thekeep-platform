# Public Roadmap

GitHub holds public engineering plans; private execution and operating data stay
in Leantime, EspoCRM, Baserow, and Gmail as described in `CONTRIBUTING.md`.

## Now

- #11 public planning model
- #13 architecture documentation
- #21 local installability
- #26 Leantime UI/MCP routing verification

## Next

- #18 integration ownership and write boundaries
- #20 authentication, authorization, secrets, approval, and audit baseline
- #22 isolated synthetic demo mode

AI work depends on those boundaries:

```text
#18 + #20 -> #15 AI gateway -> #23 hardening
          -> #16 meeting intelligence -> #17 knowledge memory
```

## Research

- #24 Vexa meeting-capture evaluation
- #25 Amurex deployment/contribution evaluation
- #29 EspoCRM MCP comparison before #28 implementation

Research does not authorize installation or production use.

## Later

- highly available k3s and replicated storage;
- off-cluster backups and restore drills;
- encrypted/delegated secret management;
- automated Authentik reconciliation;
- external/client AI workflows after hardening;
- public demo hosting after isolation and reset controls.

## Decision Required

#12 changes repository licensing and brand policy. Drafts are useful, but
adoption requires explicit maintainer approval.

## Lifecycle

1. Define verifiable acceptance criteria and dependencies.
2. Use one branch and PR per issue.
3. Keep incomplete work draft.
4. Merge only after human review.
5. Deploy production changes separately.
6. Close issues only after acceptance evidence exists.

Issues #12 through #29 already represent the current capability tracks. Avoid
creating duplicate backlog entries.
