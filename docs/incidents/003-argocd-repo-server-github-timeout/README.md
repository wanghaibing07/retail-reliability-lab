# Incident #003: Argo CD repo-server intermittent GitHub timeout

## Status

**Mitigated — repository-specific proxy validated; direct GitHub path remains unresolved**

The original retry mitigation remains enabled:

```text
ARGOCD_GIT_ATTEMPTS_COUNT=3
```

A stronger mitigation is now also validated for the Retail repository:

```text
Argo CD repository-specific HTTP proxy
→ http://192.168.88.1:7890
```

The proxy path was validated from worker nodes and from inside `argocd-repo-server`.

The direct GitHub path remains intermittently unreliable and its exact external failure point has not been proven.

## Summary

During Stage 3 GitOps validation, the `retail` Argo CD Application intermittently entered:

```text
Sync Status: Unknown
Health Status: Progressing
```

The relevant error was:

```text
ComparisonError:
Failed to load target state:
failed to generate manifest:
failed to list refs:
Get "https://github.com/wanghaibing07/retail-reliability-lab.git/info/refs?service=git-upload-pack":
context deadline exceeded
(Client.Timeout exceeded while awaiting headers)
```

Argo CD `repo-server` was intermittently unable to resolve Git refs from GitHub.

When Git access succeeded again, Argo CD correctly resolved the latest commit and changed from `Unknown` to `OutOfSync`, proving that target-state generation had recovered.

## Impact

The incident affected the GitOps control path rather than directly crashing the already-running Retail workload.

Affected functions included:

- resolving the Git `main` revision
- fetching repository state
- generating Kustomize manifests
- comparing Git desired state against Kubernetes live state

During the failure window:

```text
Git latest revision:
23f582e544b831f4ef663cf694e1feb8489950a9

Previously synced revision:
437b6ba97d31080ada64d086a0a5fa0f3d31ae25
```

Git already declared:

```text
UI replicas = 2
```

while the live cluster still had:

```text
UI replicas = 1
```

The live replica count remaining at `1` must not be interpreted as an automatic-deployment failure.

The Application was intentionally using Manual Sync, so even after repository access recovered, Argo CD was expected to report `OutOfSync` until an operator performed the next Manual Sync.

## Detection

The incident was detected through:

- Argo CD Application `Sync Status = Unknown`
- `ComparisonError`
- repo-server Git timeout logs
- repeated `git ls-remote` failures
- repo-server Git metrics
- controlled network probes from hosts and Pods

## Key Evidence

### Argo CD error

repo-server intermittently reported:

```text
failed to list refs
context deadline exceeded
```

and Git operations failed while accessing:

```text
https://github.com/wanghaibing07/retail-reliability-lab.git
```

### Argo CD metrics

Observed repo-server metrics included:

```text
argocd_git_request_total{request_type="ls-remote"} 22
argocd_git_lsremote_fail_total 5
argocd_git_request_total{request_type="fetch"} 1
```

The cumulative `ls-remote` request duration was approximately:

```text
242.86 seconds
```

repo-server gRPC observations also included:

```text
GenerateManifest OK      9
GenerateManifest Unknown 5
```

These metrics demonstrate that the failure affected Argo CD's own repository operations rather than only manual test commands.

## Investigation

### 1. Application and Git revision

The Git repository contained the merged UI scaling change.

After a successful hard refresh:

```text
Git HEAD:
23f582e544b831f4ef663cf694e1feb8489950a9

Argo .status.sync.revision:
23f582e544b831f4ef663cf694e1feb8489950a9
```

The Application then reported:

```text
OutOfSync / Progressing
```

This confirmed that Argo CD had recovered its ability to read the latest desired state.

### 2. Single repo-server Pod test

Tests from inside `argocd-repo-server` were intermittent:

- some requests succeeded
- some exceeded the request deadline
- at least one later test returned:

```text
FAIL rc=124 duration=20s
```

Therefore the incident was still reproducible during investigation and was not only historical.

### 3. Host and Pod matrix test

Twenty repeated `git ls-remote` tests produced:

| Source | PASS | FAIL |
| --- | ---: | ---: |
| worker1 guest OS | 7 | 13 |
| worker2 guest OS | 7 | 13 |
| Pod pinned to worker1 | 17 | 3 |
| Pod pinned to worker2 | 17 | 3 |

The host-level failures prove that Flannel and Kubernetes Pod networking are not required for the fault to occur.

The similar behavior across both workers also argues against a worker1-only failure.

The Pod tests were performed later than the guest-host tests, so their higher success rate must not be interpreted as proof that Pod networking was more reliable.

### 4. Simultaneous Windows/Guest test

A final controlled test was performed during:

```text
2026-09-17 07:41:43–07:45:18 UTC
```

The same Git smart-HTTP endpoint was tested simultaneously:

```text
https://github.com/wanghaibing07/retail-reliability-lab.git/info/refs?service=git-upload-pack
```

Results:

| Source | PASS | FAIL |
| --- | ---: | ---: |
| Windows VMware host | 30 | 0 |
| worker1 VMware guest | 0 | 30 |
| worker2 VMware guest | 1 | 29 |

Windows responses consistently returned HTTP 200 in approximately:

```text
0.54–1.38 seconds
```

worker1 failures were:

```text
curl rc=28
HTTP code=000
time_connect=0
approximately 5-second connection timeout
```

worker2 showed nearly the same behavior.

One worker2 request succeeded, and one failed request had completed TLS but received no HTTP first byte within the test timeout.

This is the strongest localization evidence collected during the incident.

## Root Cause Assessment

### Updated evidence from the Kubernetes 1.36.4 rebuild

Incident #003 reproduced again after the cluster was rebuilt.

The failure was observed from:

* Kubernetes nodes
* temporary Pods
* Argo CD repo-server
* the Windows host path toward GitHub

During failure windows, packet capture showed TCP SYN packets leaving toward GitHub without a returned SYN/ACK.

The same environment could successfully reach other HTTPS destinations.

The investigation also confirmed:

```text
CoreDNS                    healthy
Flannel                    healthy
Pod cross-node networking  healthy
Linux SNAT/MASQUERADE      working
MTU configuration          consistent
conntrack                  not exhausted
firewalld                  inactive
```

Therefore the current evidence no longer supports describing the unique fault domain as VMware guest networking alone.

### Confirmed failure boundary

The most precise statement currently supported by evidence is:

> Direct HTTPS connectivity toward GitHub is intermittently unreliable somewhere beyond the validated Kubernetes/guest SNAT path. The available evidence cannot uniquely distinguish the local upstream router, ISP/transit path, or GitHub edge.

No single local component has been proven as the root cause.

### Proxy comparison

A separate HTTP proxy path was tested:

```text
http://192.168.88.1:7890
```

Validation results:

```text
worker2 HTTPS through proxy       10/10 PASS
worker2 git ls-remote             10/10 PASS
repo-server git ls-remote         10/10 PASS
```

All successful Git tests returned:

```text
3c5e7c088cc93402d4b947443738a342b0fe863d
```

This establishes a stable mitigation path without claiming that the original direct path has been repaired.

## Contributing Factors

### External Git dependency

Argo CD must regularly access the remote Git repository to resolve revisions and generate desired state.

### Default Git request timeout

No explicit `reposerver.git.request.timeout` was configured, so the default timeout remained in use.

### Transient network behavior

The failure was intermittent, which allowed individual manual tests to occasionally succeed and made one-shot connectivity tests misleading.

## What Was Ruled Out

The investigation did not find evidence supporting:

- incorrect GitHub repository URL
- incorrect Argo CD source path
- incorrect target revision
- repository authentication failure
- DNS being permanently broken
- an Egress NetworkPolicy blocking repo-server
- a single failed Kubernetes worker
- Flannel as the sole cause
- containerd metadata corruption as the cause
- Retail application process failure as the cause of `ComparisonError`

## Mitigation

Two mitigations are now in place.

### Git retry

The repo-server keeps:

```text
ARGOCD_GIT_ATTEMPTS_COUNT=3
```

This remains a resilience control for transient failures.

### Repository-specific proxy

The Retail Git repository is configured through an Argo CD repository Secret with:

```text
proxy: http://192.168.88.1:7890
```

This limits the workaround to the affected Git repository instead of setting a global proxy for the Kubernetes cluster or all Argo CD traffic.

The proxy dependency is specific to this lab environment.

No Git credentials are stored in this repository Secret.

## Recovery

After Git connectivity succeeded again and the Application was hard-refreshed:

```text
Argo revision:
23f582e544b831f4ef663cf694e1feb8489950a9
```

and Application status moved from:

```text
Unknown
```

to:

```text
OutOfSync
```

This transition is considered recovery of the repository-comparison path.

The later UI replica deployment was completed through the planned GitOps Manual Sync workflow: the UI reached `2/2`, Argo CD reached `Synced/Healthy`, and `verify.sh` plus the business HTTP check passed. This is release validation, not evidence that the underlying guest-egress fault was fixed.

## Validation

Recovery was validated by confirming:

- repo-server could again resolve Git refs
- Argo CD recognized the latest `main` revision
- `ComparisonError` disappeared
- the Application could calculate desired/live differences
- Argo correctly identified the UI replica difference

## Lessons Learned

- Host connectivity and Pod connectivity must be tested separately.
- A single successful `curl` or `git ls-remote` is insufficient evidence for an intermittent network fault.
- Controlled repeated tests are more useful than isolated connectivity checks.
- Tests intended to compare paths should run in the same time window.
- `Application = Unknown` does not mean the business workload itself is unavailable.
- `OutOfSync` is not necessarily an incident; in Manual Sync mode it can be the expected result after a Git change.
- Retry improves control-plane resilience but must not be confused with root-cause remediation.
- Incident conclusions should stop at the boundary supported by evidence.

## Follow-up Actions

### Completed — Declaratively manage Argo CD retry configuration

The retry mitigation:

```text
ARGOCD_GIT_ATTEMPTS_COUNT=3
```

has been moved from an imperative live-cluster change into repository-managed
Argo CD platform configuration.

The Argo platform desired state was applied with server-side apply and later
validated with:

```text
kubectl diff --server-side -k infra/argocd/platform
rc=0
```

This closes the configuration-management follow-up, but does not change the
incident root-cause assessment.

### P0 — Preserve the recovered control-plane state

The planned UI replica change was completed through the normal GitOps Manual Sync
workflow and validated as:

```text
UI Deployment 2/2
Argo Synced/Healthy
verify.sh PASS
HTTP 200
```

This closes the release action, but it does not close the network incident. The
repo-server retry remains a mitigation, and the underlying VMware guest-egress
fault still requires a separate infrastructure investigation.

### P1 — Monitor Argo repository access

Collect and alert on repo-server metrics including:

```text
argocd_git_request_total
argocd_git_request_duration_seconds
argocd_git_fetch_fail_total
```

and Application conditions such as `ComparisonError`.

### P1 — Preserve evidence on recurrence

If the failure becomes reproducible again, capture traffic at the Windows/VMware virtual-network layer to distinguish:

- TCP connection failure
- TLS handshake failure
- post-TLS HTTP response stall
- retransmission/reset behavior

### P2 — Investigate VMware host networking separately

Perform a separate infrastructure investigation of the VMware NAT path without changing Kubernetes or Argo CD configuration at the same time.

Potential components should be tested independently rather than changed together.

## References

- Argo CD repo-server documentation: repo-server uses `git ls-remote` to resolve revisions and supports retry through `ARGOCD_GIT_ATTEMPTS_COUNT`.
- Argo CD metrics documentation: repo-server exposes Git request counts, durations and failure metrics.
- VMware Workstation networking documentation: NAT networking uses the VMnet8 NAT network by default on Windows-hosted Workstation environments.
