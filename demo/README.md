# Demo Scenario

The fictional **Northstar Paperworks** dataset demonstrates a small publisher
tracking a product launch, one opportunity, and one meeting decision.

The CSV files are the demo seed contract. Future app adapters should import them
idempotently using the `demo_*` IDs.

## Walkthrough

1. View the Northstar organization and people.
2. Open the Aurora launch project.
3. Review the bookstore partnership opportunity.
4. Open the launch-review meeting summary.
5. Follow its decision and action back to the project/opportunity.

This is synthetic data. Never seed from production exports.

## Reset

Reset the disposable sandbox with:

```bash
scripts/dev-cluster-down.sh
scripts/dev-smoke.sh platform
```

App-specific seed adapters are not implemented yet. When added, they must run
after cluster creation, upsert by `demo_*` ID, and support this reset path.

Validate the dataset with `scripts/test-demo-data.sh`.

Capture screenshots only after adapters render this scenario; placeholders
would misrepresent current behavior.
