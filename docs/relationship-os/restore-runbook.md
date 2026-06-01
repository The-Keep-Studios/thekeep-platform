# Baserow Restore Runbook

This runbook covers the MVP Baserow all-in-one deployment in
`kubernetes/apps/baserow`.

The backup CronJob creates full `/baserow/data` archives on the
`baserow-backup-pvc`. It scales the Baserow Deployment to zero first, waits for
the pod to terminate, archives the data directory, then scales the Deployment
back to one replica.

## Backup Location

Namespace: `baserow`

PVCs:

- `baserow-data`: live Baserow data mounted at `/baserow/data`
- `baserow-backup-pvc`: backup archives mounted at `/backup`

Backup file pattern:

```text
/backup/baserow_data_YYYYMMDDTHHMMSSZ.tar.gz
```

## Check Backup Job Status

```bash
kubectl get cronjob,job,pod,pvc -n baserow | grep -E 'baserow|NAME'
```

Check the latest backup pod logs:

```bash
kubectl logs -n baserow job/$(kubectl get jobs -n baserow \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1:].metadata.name}')
```

## Trigger a Manual Backup

This temporarily takes Baserow offline.

```bash
kubectl create job -n baserow baserow-backup-manual-$(date +%s) \
  --from=cronjob/baserow-backup
```

Wait for completion:

```bash
kubectl wait -n baserow --for=condition=complete --timeout=900s \
  job/$(kubectl get jobs -n baserow \
    --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{.items[-1:].metadata.name}')
```

## Validate an Archive

Create a temporary pod that mounts the backup PVC and lists the archive contents:

```bash
kubectl run -n baserow baserow-backup-validator --rm -i --restart=Never \
  --image=alpine:3.22 \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "validator",
      "image": "alpine:3.22",
      "command": ["sh", "-ceu", "latest=$(ls -t /backup/baserow_data_*.tar.gz | head -1); test -s \"$latest\"; tar -tzf \"$latest\" | head -40"],
      "volumeMounts": [{"name": "backup-data", "mountPath": "/backup"}]
    }],
    "volumes": [{"name": "backup-data", "persistentVolumeClaim": {"claimName": "baserow-backup-pvc"}}]
  }
}'
```

## Restore

Restoring replaces the current Baserow data directory. Take a fresh backup first
unless the PVC is already unusable.

1. Stop Baserow:

```bash
kubectl scale deployment/baserow -n baserow --replicas=0
kubectl wait -n baserow --for=delete pod -l app=baserow --timeout=600s
```

2. Restore the selected archive into the live PVC:

```bash
kubectl run -n baserow baserow-restore --rm -i --restart=Never \
  --image=alpine:3.22 \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "restore",
      "image": "alpine:3.22",
      "command": ["sh", "-ceu", "archive=/backup/REPLACE_WITH_ARCHIVE.tar.gz; rm -rf /baserow/data/*; tar -xzf \"$archive\" -C /baserow"],
      "volumeMounts": [
        {"name": "baserow-data", "mountPath": "/baserow/data"},
        {"name": "backup-data", "mountPath": "/backup"}
      ]
    }],
    "volumes": [
      {"name": "baserow-data", "persistentVolumeClaim": {"claimName": "baserow-data"}},
      {"name": "backup-data", "persistentVolumeClaim": {"claimName": "baserow-backup-pvc"}}
    ]
  }
}'
```

Replace `REPLACE_WITH_ARCHIVE.tar.gz` with the actual filename before running.

3. Start Baserow:

```bash
kubectl scale deployment/baserow -n baserow --replicas=1
kubectl rollout status deployment/baserow -n baserow --timeout=10m
```

4. Verify the app:

```bash
kubectl run -n baserow baserow-curl --rm -i --restart=Never \
  --image=curlimages/curl:8.8.0 -- \
  sh -ceu 'curl -fsS -H "Host: relationships.thekeepstudios.com" -H "X-Forwarded-Proto: https" http://baserow/ | head'
```

## Gaps

This MVP stores backups on-cluster. Off-cluster replication is still required
for real disaster recovery.
