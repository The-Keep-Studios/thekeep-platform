# Vexa Deployment Evaluation

Status: lab pilot only. Reviewed against Vexa
[`v0.10.6.3.14`](https://github.com/Vexa-ai/vexa/releases/tag/v0.10.6.3.14)
and commit
[`c3fe4ba`](https://github.com/Vexa-ai/vexa/commit/c3fe4ba6d5043e7f22db2a47fee3039c03feea0e)
on 2026-06-11.

## Decision

Use Vexa's upstream Helm chart rather than copying its Compose stack into an
Ansible role. The future `vexa` role should validate operator inputs, seed
secrets, and bootstrap an Argo CD application pinned to a reviewed Vexa tag.
Argo CD should own deployment and upgrades.

Do not deploy Vexa for client or production meetings until the gates below are
closed. The current release is suitable for an isolated synthetic-data pilot.

## Deployment Shape

| Target | Path | Notes |
| --- | --- | --- |
| Local evaluation | Upstream [Vexa Lite](https://github.com/Vexa-ai/vexa/tree/v0.10.6.3.14/deploy/lite) or [Compose](https://github.com/Vexa-ai/vexa/tree/v0.10.6.3.14/deploy/compose) | Follow upstream; do not maintain a fork here. |
| Homelab/k3s | Upstream [`vexa` Helm chart](https://github.com/Vexa-ai/vexa/tree/v0.10.6.3.14/deploy/helm/charts/vexa) via Argo CD | Use `process` orchestration for the first pilot. |
| Future platform | Same chart with external PostgreSQL, Redis, object storage, and transcription | Requires the production gates below. |

The full chart includes API gateway, admin API, meeting API, runtime API, MCP,
TTS, PostgreSQL, Redis, and optional dashboard/storage dependencies. The public
API is port `8000`; other services should remain cluster-internal. Compose uses
host ports `8056`, `8057`, `8090`, `18888`, `3001`, `5458`, `9000`, and `9001`.
See the upstream
[`values.yaml`](https://github.com/Vexa-ai/vexa/blob/v0.10.6.3.14/deploy/helm/charts/vexa/values.yaml)
and
[`docker-compose.yml`](https://github.com/Vexa-ai/vexa/blob/v0.10.6.3.14/deploy/compose/docker-compose.yml)
for the authoritative service contract.

## Role Contract

Proposed structure:

```text
ansible/roles/vexa/
  defaults/main.yml       # non-secret inputs and disabled-by-default flag
  tasks/validate.yml      # reject placeholders, mutable tags, and unsafe exposure
  tasks/main.yml          # secret seeding and GitOps bootstrap only
  templates/values.yml.j2 # minimal operator overlay
```

Minimum inputs:

| Variable | Requirement |
| --- | --- |
| `vexa_enabled` | Default `false`. |
| `vexa_revision` | Immutable reviewed tag or commit. |
| `vexa_image_tag` | Immutable release tag; no `latest` or `dev`. |
| `vexa_hostname` | Internal hostname for pilot; authenticated HTTPS later. |
| `vexa_admin_api_token` | Secret, generated outside Git. |
| `vexa_internal_api_secret` | Secret, generated outside Git. |
| `vexa_transcription_url` | Approved hosted endpoint or self-hosted service. |
| `vexa_transcription_token` | Secret; omit for unauthenticated local service only. |
| `vexa_database_*` | External production database settings or explicit lab defaults. |
| `vexa_redis_url` | External production Redis or explicit lab default. |
| `vexa_storage_*` | S3-compatible endpoint, bucket, credentials, and TLS flag. |
| `vexa_retention_days` | Platform policy; enforcement is not supplied by Vexa. |

Do not add these files until a synthetic meeting proves the pinned chart works
on the local k3s profile. That avoids committing an untested deployment API.

## Meeting Intelligence Flow

1. Vexa emits signed `meeting.completed` webhooks to the ingestion API.
2. The ingestion API verifies signature, timestamp, meeting identity, and
   idempotency key before fetching the stable transcript over authenticated
   REST.
3. Store the immutable source payload and provenance, then enqueue the
   processing defined in [#16](https://github.com/The-Keep-Studios/thekeep-platform/issues/16).
4. Use WebSocket transcript events only for live UI. REST remains the final
   post-meeting source.

This keeps Vexa credentials out of downstream processors and avoids treating
mutable live segments as final records. Relevant upstream contracts:
[transcripts](https://docs.vexa.ai/api/transcripts),
[WebSocket](https://docs.vexa.ai/websocket), and
[integration primitives](https://github.com/Vexa-ai/vexa/blob/v0.10.6.3.14/docs/integrations.mdx).

## Production Gates

- Define participant notice and consent policy before any real meeting.
- Set retention and deletion automation. Vexa deletes artifacts best-effort
  and anonymizes rather than removes all meeting metadata.
- Use external secret management; reject upstream placeholder defaults.
- Pin chart source and every image by reviewed release, preferably digest.
- Disable direct dashboard login and expose only authenticated HTTPS routes.
- Add default-deny network policies and restrict webhook egress.
- Keep runtime orchestration in `process` mode until Kubernetes bot RBAC is
  reviewed. Never use the Compose Docker socket path on a shared host.
- Disable transcript share links unless explicitly required.
- Back up and restore-test PostgreSQL and object storage; Redis is operational
  state, not the transcript archive.
- Verify resource limits, health probes, logs, alerting, upgrade, and rollback
  with synthetic meetings.
- Re-review upstream security posture. Its repository `SECURITY.md` is still a
  template and is not an operational vulnerability policy.

These gates are part of [#20](https://github.com/The-Keep-Studios/thekeep-platform/issues/20)
and [#23](https://github.com/The-Keep-Studios/thekeep-platform/issues/23).
Vexa is Apache-2.0 licensed; legal review is still required for recording,
privacy, consent, and platform terms.

## Pilot Check

Follow the upstream
[Helm quickstart](https://github.com/Vexa-ai/vexa/blob/v0.10.6.3.14/deploy/helm/README.md)
on a disposable local cluster, using synthetic participants and content.
Before installing, require `helm template` and `helm install --dry-run` to pass
with the intended values overlay. Record the pinned image digests and delete
the namespace after the test.
