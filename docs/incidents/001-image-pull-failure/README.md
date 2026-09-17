# Incident #001: Public registry image-pull instability

## Status

Resolved for the Retail deployment path; long-term reliability was improved through controlled pre-pull and cluster-local registry routing.

## Summary

During the initial deployment of AWS Retail Store Sample App v1.6.2, containerd image pulls from public registries intermittently stalled or timed out.

The failure was most visible on larger image layers and became easier to reproduce when multiple layers were downloaded concurrently. Kubernetes manifests were valid, but the workloads could not converge predictably because image acquisition remained on the critical deployment path.

## Impact

Observed impact included:

- Pods remaining in image-pull failure states
- delayed application startup
- deployments failing to converge within a predictable time
- repeated manual pulls being required
- public registry connectivity becoming a deployment dependency

## Detection

The problem was detected through Kubernetes Pod events, containerd and CRI image-pull failures, direct `crictl pull` tests, repeated registry connectivity tests, and comparison of serial and concurrent downloads.

## Key Evidence

The investigation showed that:

- small or already-cached images could succeed
- large layer transfers were less reliable
- concurrent downloads increased the probability of stalls
- retrying an individual pull could succeed
- a successful registry homepage request did not prove that large layers were transferable

The investigation therefore separated DNS, authentication and manifest resolution from large-layer transfer reliability.

## Root Cause Assessment

The evidence is consistent with intermittent instability on the virtual-machine guest outbound path toward public registry and CDN endpoints.

Containerd download concurrency and its image-pull progress timeout increased the operational impact of that unstable path. The evidence does not prove that one VMware or host-networking component was the unique root cause.

## Mitigation

The deployment path was changed to reduce sensitivity to public registry instability:

1. containerd image-download concurrency was reduced
2. the image-pull progress timeout was increased
3. required images were pre-pulled serially on every worker
4. a cluster-local TLS registry was introduced for lab recovery
5. deployment verification was extended to workloads, endpoints and business HTTP

The pre-pull workflow is maintained in:

- [image pull reliability runbook](../../runbooks/image-pull-reliability.md)
- [containerd registry routing runbook](../../runbooks/containerd-registry-routing.md)

## Recovery

After the required images were available on both workers:

- Deployments converged
- StatefulSets became Ready
- Pods became Ready
- Services regained Ready endpoints
- business HTTP returned 200

Two later destroy → deploy → verify rebuilds completed without manual intervention.

## Follow-up Hardening

The lab registry is a single-replica learning environment with node-local retained storage. It is not presented as production-grade high availability.

Future hardening includes reviewed immutable digests, registry availability monitoring and a repeatable cold-pull verification.

## What Was Ruled Out

The investigation did not support the following as the primary explanation:

- invalid Kubernetes workload manifests
- permanently broken DNS
- registry authentication being the general cause
- insufficient local disk space as the main cause
- one specific application image being corrupt

## Lessons Learned

- Registry reachability is not equivalent to large-layer transfer reliability.
- Image acquisition should be validated before rollout begins.
- Concurrency can amplify an unstable network path.
- Runtime configuration must be verified from the active containerd configuration.
- Deployment verification must extend beyond Pod creation to Ready endpoints and business HTTP.
- Public image availability should not remain an uncontrolled dependency in a reproducible lab.

## Follow-up Actions

| Priority | Action | Success criteria | Status |
| --- | --- | --- | --- |
| P0 | Deterministic image pre-pull | Required images verified on every worker before deploy | Done |
| P0 | Business validation after recovery | Workloads Ready, endpoints present, HTTP 200 | Done |
| P1 | Maintain registry routing runbook | Recovery procedure remains reproducible | Done |
| P1 | Use the controlled internal registry for lab recovery | Cold pull succeeds without host proxy dependency | Done |
| P2 | Move application image references to reviewed digests | Release manifest records immutable image identity | Planned |
