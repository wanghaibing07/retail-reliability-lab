# GitOps Auto Prune Evidence

## Goal

Verify that Argo CD can automatically prune a resource removed from Git without
requiring a Manual Sync or an imperative kubectl delete.

## Safety Boundary

The experiment intentionally used a disposable ConfigMap:

`ConfigMap/gitops-prune-probe`

It did not modify or delete Deployments, StatefulSets, Services, or application
data.

Stateful workloads remain protected with:

`argocd.argoproj.io/sync-options: Prune=confirm`

## Experiment

PR #20 added the disposable ConfigMap to Git.

After merge, Argo CD automatically created it from the repository desired state.

PR #21 removed the ConfigMap from Git.

No Manual Sync was performed.

No `kubectl delete ConfigMap` command was used.

Argo CD automatically removed the live ConfigMap after detecting the updated
desired state.

## Final Validation

The Stage 3 final validation confirmed:

- Application: Synced / Healthy
- automated sync: enabled
- selfHeal: enabled
- prune: enabled
- allowEmpty: false
- `gitops-prune-probe`: absent
- three stateful workloads: `Prune=confirm`
- Retail verification: PASS
- business HTTP check: PASS
- Argo CD platform diff: 0

## Result

PASS.

This demonstrates automatic pruning through:

Git desired-state removal
→ protected main
→ Argo CD reconciliation
→ live disposable resource removal

The experiment does not claim that stateful data deletion is safe.
Stateful workloads remain explicitly guarded by `Prune=confirm`.
