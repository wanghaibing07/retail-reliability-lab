# Release Failure Recovery

## Trigger

`KubernetesDeploymentRolloutStalled` fires when Kubernetes reports:

- `Progressing=False`
- `Reason=ProgressDeadlineExceeded`

for a Deployment in the `retail` namespace.

This alert indicates a failed rollout. It does not necessarily mean the user-facing service is unavailable.

## Triage

Confirm the affected Deployment and rollout state:

```bash
kubectl -n retail get deployment <deployment>
kubectl -n retail describe deployment <deployment>
kubectl -n retail get rs
kubectl -n retail get pods -o wide
kubectl -n retail get events --sort-by=.lastTimestamp
```

Check whether existing healthy Pods are still serving through the Service and EndpointSlices before changing anything.

## Recovery

Git is the source of truth.

For a bad release committed to `main`:

1. Identify the bad Git commit.
2. Create a recovery branch from current `main`.
3. Revert only the bad desired-state change.
4. Inspect the revert diff.
5. Open a recovery PR.
6. Require CI to pass.
7. Merge the recovery PR.
8. Allow Argo CD to reconcile the cluster from Git.

Do not treat `kubectl rollout undo`, live patches, or `kubectl set image` as the authoritative GitOps recovery path.

If reverting a merge commit, verify its parents before choosing the `git revert -m` mainline parent.

## Recovery Validation

Require:

- Argo CD `Synced / Healthy`
- Deployment desired/ready/available replicas restored
- healthy Service endpoints restored
- user-facing HTTP validation passes
- `scripts/verify.sh` passes
- rollout-stalled alert is no longer firing

Stage 6 evidence should record the bad revision, failure-detection time, recovery revision, and healthy completion time.
