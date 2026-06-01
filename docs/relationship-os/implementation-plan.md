# Relationship OS Implementation Plan

This plan implements the Relationship OS MVP from `docs/newappsplan.md` and the
research export. The goal is a usable strategic relationship map, not a rescue
operations database and not a cross-system automation project.

## Decision

Use one self-hosted Baserow instance on The Keep Platform.

Initial operating model:

- Workspace: `TKS Relationship OS`
- Workspace: `Full Hearts Strategic Relationships`
- Manual record entry and manual promotion only
- No sync workers
- No ETL
- No webhooks
- No rescue medical, adoption, foster, or volunteer operations schema

GetBuddy remains a written-diligence candidate for rescue operations only.

## MVP Scope

Included:

- Baserow all-in-one Kubernetes Deployment
- PVC mounted at `/baserow/data`
- Internal service and Traefik Ingress for `relationships.thekeepstudios.com`
- Argo CD app registration as `platform-baserow`
- Daily quiet-window backup CronJob
- Restore runbook
- Schema and data-boundary docs
- GetBuddy diligence checklist

Excluded:

- External PostgreSQL
- External Redis
- S3/object storage
- automated imports
- API sync jobs
- public intake apps
- advanced RBAC design
- rescue operations workflow
- donor management workflows

## Rollout Checklist

1. Create the Cloudflare Tunnel public hostname:
   - Hostname: `relationships.thekeepstudios.com`
   - Service type: `HTTPS`
   - Service URL: `traefik.kube-system.svc.cluster.local`
   - Origin setting: `No TLS Verify`
2. Add Cloudflare Access in front of `relationships.thekeepstudios.com`.
3. Apply or sync the `platform-baserow` Argo CD application.
4. Wait for:
   - `application/platform-baserow` to become `Synced Healthy`
   - `deployment/baserow` to become available in namespace `baserow`
5. Open Baserow and create the first admin account.
6. Create the two workspaces.
7. Build the tables from `baserow-schema.md`.
8. Enter 5 to 10 real convention or partner contacts manually.
9. Review the data-boundary policy before adding Full Hearts records.
10. Confirm the backup CronJob exists.

## Day-One Success Criteria

The MVP is usable when:

- Baserow loads through Cloudflare Access.
- The two workspaces exist.
- Core tables exist in each workspace.
- At least one strategic contact can be entered manually.
- Follow-up dates and opportunity stages can be viewed without custom code.
- Backup and restore instructions are documented.

## Non-Goals

The Relationship OS is not the system of record for animal care, adoption,
foster screening, medical history, donor receipts, or legal compliance records.

The first version is intentionally boring. If the team uses it consistently for
30 to 60 days, then evaluate whether Baserow is still enough or whether the
schema should graduate into a more governed platform.
