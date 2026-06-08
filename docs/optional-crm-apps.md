# Optional CRM Apps

Baserow remains the core relationship-management app for now. Twenty and
EspoCRM stay in the repo as optional apps that can be tested locally or enabled
explicitly through GitOps.

Use fake or low-risk sample data while comparing the CRMs. Do not import rescue,
medical, adoption, private convention, or client data until an app has been
deliberately chosen for that data class.

## Local Test

Run one candidate at a time:

```bash
scripts/dev-smoke.sh twenty
scripts/dev-observe.sh twenty
```

```bash
scripts/dev-smoke.sh espocrm
scripts/dev-observe.sh espocrm
```

Run both candidates when the workstation has enough disk and memory:

```bash
scripts/dev-smoke.sh optional-crm
scripts/dev-observe.sh optional-crm
```

The old `crm-bakeoff` target remains as a compatibility alias for local
comparison:

```bash
scripts/dev-smoke.sh crm-bakeoff
scripts/dev-observe.sh crm-bakeoff
```

Default local URLs:

```text
Twenty:  http://localhost:18083
EspoCRM: http://localhost:18084
```

The smoke scripts create deterministic dev-only Kubernetes secrets in each app
namespace. Override them only when also deleting the disposable cluster or PVCs.

## GitOps Enablement

Both apps are disabled by default:

```yaml
platform_optional_apps:
  twenty:
    enabled: false
  espocrm:
    enabled: false
```

Enable either app, or both, in `ansible/production_vars.yml`:

```yaml
platform_optional_apps:
  twenty:
    enabled: true
  espocrm:
    enabled: false
```

Add only the secrets required by the enabled app.

EspoCRM can optionally manage `emailServerAllowedAddressList` from
`ansible/production_vars.yml`. Entries must be exact `host:port` pairs;
wildcards are rejected.

```yaml
platform_optional_apps:
  espocrm:
    enabled: true
    email_server_allowed_address_list:
      - "imap.example.com:993"
      - "smtp.example.com:587"
```

Omit `email_server_allowed_address_list` to leave the EspoCRM setting
unmanaged. Set it to `[]` to explicitly clear an allowlist previously managed
through this playbook.

Twenty:

```yaml
platform_secrets:
  twenty_pg_database_password: "CHANGE_ME"
  twenty_encryption_key: "CHANGE_ME"
  twenty_app_secret: "CHANGE_ME"
```

EspoCRM:

```yaml
platform_secrets:
  espocrm_db_root_password: "CHANGE_ME"
  espocrm_db_password: "CHANGE_ME"
  espocrm_admin_password: "CHANGE_ME"
```

If external HTTPS validation is enabled, include the enabled host in
`direct_http_urls` so the direct-origin exposure check covers it too.

```yaml
direct_http_urls:
  - "http://twenty.thekeepstudios.com"
```

or:

```yaml
direct_http_urls:
  - "http://espocrm.thekeepstudios.com"
```

## Hostnames

The optional app manifests use these external hosts:

```text
Twenty:  https://twenty.thekeepstudios.com
EspoCRM: https://espocrm.thekeepstudios.com
```

Wire only enabled hosts through Cloudflare Tunnel.

## Backups

Each optional app includes its own backup CronJob:

```text
Twenty:  twenty/twenty-backup
EspoCRM: espocrm/espocrm-backup
```

The backup jobs write compressed database dumps and app-local data archives to
app-specific backup PVCs. Validate backups manually before putting real business
data into either CRM.

Manual backup examples:

```bash
kubectl create job -n twenty twenty-backup-manual-$(date +%s) \
  --from=cronjob/twenty-backup
```

```bash
kubectl create job -n espocrm espocrm-backup-manual-$(date +%s) \
  --from=cronjob/espocrm-backup
```

## Cleanup

Local cleanup:

```bash
kubectl delete namespace twenty
kubectl delete namespace espocrm
```

Disposable-cluster cleanup:

```bash
scripts/dev-cluster-down.sh
```

Trial cleanup:

1. Set the app's `platform_optional_apps.<app>.enabled` value to `false`.
2. Re-render/apply GitOps.
3. Confirm the selected Argo CD app disappears or is pruned intentionally.
4. Delete app PVCs only after deciding no trial data needs to be kept.
