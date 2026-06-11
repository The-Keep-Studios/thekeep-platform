# Amurex Deployment Evaluation

Status: contribution-only research target. Do not deploy.

Reviewed on 2026-06-11:

- extension commit [`7c52bbc`](https://github.com/thepersonalaicompany/amurex/commit/7c52bbc77f7e9722465ecb901993a91154c4e0f4)
- backend commit [`9f16a5b`](https://github.com/thepersonalaicompany/amurex-backend/commit/9f16a5b93c19c4d07435a72ad39507913e09edba)
- web commit [`52e7870`](https://github.com/thepersonalaicompany/amurex-web/commit/52e7870191da0f7453f3078517cd2b21b24422ba)

## Decision

Do not create an Ansible role yet. Amurex is a Chrome extension plus separate
backend and web repositories, not a browser-independent call-assistant backend.
Its self-host contract is incomplete and currently unsafe for meeting data.

This matches upstream's open
[self-hosting issue](https://github.com/thepersonalaicompany/amurex/issues/139).
Re-evaluate only after upstream supplies complete migrations, authenticated
APIs, configurable service URLs, deletion/retention controls, and a tested
single-host deployment.

## Current Shape

| Component | Requirement or limitation |
| --- | --- |
| Capture | Chrome Manifest V3 extension reads Google Meet and Teams captions. |
| Firefox | Unsupported; the open [WIP PR](https://github.com/thepersonalaicompany/amurex/pull/96) does not have working background scripts. |
| Backend | Python/Robyn API and WebSocket on `8080`; no authentication is enforced. |
| Web | Next.js application on `3000`; no Dockerfile or complete deployment path. |
| Database | Supabase Auth, PostgreSQL, Storage, and pgvector. Published migrations are incomplete. |
| Local state | Backend also writes `meetings.db`; no persistent volume is defined. |
| Queue/cache | Redis, with a hard-coded `rediss://` connection shape. |
| Local AI | Ollama plus FastEmbed, but FastEmbed is commented out of requirements and cloud clients are still initialized. |
| Cloud AI | OpenAI, Groq, Gemini, and Mistral are referenced. |
| Other SaaS | Resend is required; the web app also includes Vercel Analytics, Speed Insights, and Intercom. |

The extension duplicates backend/web configuration in multiple files and still
contains hard-coded `api.amurex.ai` URLs. Its background worker sends at least
one `/track` event without checking `ANALYTICS_ENABLED`. Upstream tracks this in
[#138](https://github.com/thepersonalaicompany/amurex/issues/138).

The backend's `.env.example` and Compose file omit variables used by the code,
including `SUPABASE_SERVICE_ROLE_KEY`. This is independently reported in
[#63](https://github.com/thepersonalaicompany/amurex-backend/issues/63), while
[#67](https://github.com/thepersonalaicompany/amurex-backend/issues/67)
documents missing database migrations.

## Security Blockers

- WebSocket clients select `meeting_id` and `user_id` through query parameters
  without authentication.
- HTTP endpoints, including transcript processing and tracking, have no
  authorization layer.
- CORS allows every origin.
- The backend uses a Supabase service-role key rather than a scoped user token.
- Transcript objects are returned through public storage URLs.
- No complete account, transcript, analytics, or object deletion workflow
  exists; retention is undefined.
- Analytics are enabled by default across the extension and web application.
- Self-hosted extension URLs are not reliably configurable.
- The backend exposes internal exception text and lacks startup validation.

These must be resolved before the controls in
[#20](https://github.com/The-Keep-Studios/thekeep-platform/issues/20) and
[#23](https://github.com/The-Keep-Studios/thekeep-platform/issues/23) can be
meaningfully applied.

## Future Role Contract

If upstream closes the blockers, use a disabled-by-default role that only:

```text
ansible/roles/amurex/
  defaults/main.yml       # pinned revisions and non-secret endpoints
  tasks/validate.yml      # reject missing keys, mutable refs, and public access
  tasks/main.yml          # seed secrets and bootstrap GitOps
  templates/values.yml.j2 # minimal platform-owned overlay
```

The deployable unit would need pinned extension, backend, and web revisions;
Supabase/PostgreSQL/storage; Redis; persistent SQLite storage or its removal;
model/embedding endpoints; email settings; analytics disabled by default; and
authenticated HTTPS origins. Do not put service-role, model, OAuth, or email
credentials in Git.

## Upstream Contribution

The smallest useful upstream PR is extension configuration cleanup:

1. Generate one config file used by background, content, and side-panel scripts.
2. Default analytics off for self-hosting.
3. Guard every `/track` call with that setting.
4. Add a static test that fails on hard-coded `amurex.ai` service URLs.

This is narrower and more reviewable than attempting the existing all-in-one
self-hosting PR. A follow-up can add strict environment validation and a
complete Compose stack after the missing schema is published.

## Meeting Intelligence

Amurex currently has no trustworthy export contract for
[#16](https://github.com/The-Keep-Studios/thekeep-platform/issues/16). Do not
read public Supabase transcript URLs or connect directly to its unauthenticated
WebSocket.

A viable future integration is an authenticated, signed `meeting.completed`
webhook carrying a stable meeting ID and transcript checksum. The platform
ingestion service would verify it, fetch the transcript through a scoped API,
store source provenance, and process it idempotently.

## License

The extension and backend are AGPL-3.0. The web repository has no detected
license file. Obtain legal review before distributing modifications or
providing a network service, and publish corresponding source where AGPL
requires it.
