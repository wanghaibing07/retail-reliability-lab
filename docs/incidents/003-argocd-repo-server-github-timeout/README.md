# Incident #003: Argo CD repo-server intermittent GitHub timeout

## Status

**Partially mitigated — control-plane comparison recovered; underlying guest-egress fault remains unresolved**

Argo CD currently has a retry mitigation in place:

```text
ARGOCD_GIT_ATTEMPTS_COUNT=3
```

The GitOps comparison path recovered and Argo CD can resolve the latest Git revision again.

The underlying intermittent network fault has not been proven down to a single VMware or Windows networking component.

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

### Confirmed failure mechanism

Argo CD repository operations intermittently failed because HTTPS/Git connections from the Kubernetes VMware guests toward GitHub did not reliably complete.

Most final controlled-test failures occurred before TCP connection establishment completed.

At least one request progressed beyond TLS but stalled before receiving an HTTP response.

### Confirmed failure domain

The failure reproduced on:

- worker1 guest OS
- worker2 guest OS
- Pods running on both workers
- Argo CD repo-server

At the same time, the Windows VMware host completed all 30 requests to the same endpoint successfully.

This rules out the following as sufficient explanations:

- a worker1-only failure
- a repo-server-only failure
- a Kubernetes Pod-only failure
- Flannel being required for the failure
- Git repository URL or branch misconfiguration
- a persistent GitHub-wide outage during the final test window

### Strongly implicated shared path

The evidence strongly implicates the shared VMware guest egress path between the virtual machines and the Windows host uplink, including components such as:

```text
VMware VMnet8 NAT network
VMware NAT Service
Windows host virtual-network forwarding/filtering path
```

### What is not proven

No packet capture was obtained from the failing path.

Therefore the available evidence does not prove which specific component is defective.

It is not currently valid to state that the unique root cause is:

- VMnet8 itself
- VMware NAT Service itself
- Windows NetNat
- a Windows firewall/filter driver
- VPN software
- another host networking component

The most precise root-cause statement is:

> Intermittent failure exists in the shared VMware guest outbound networking path. The failure boundary has been narrowed to the virtualized egress path between the VMware guests and the Windows host network, but the exact networking component has not yet been isolated.

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

The repo-server Deployment was configured with:

```text
ARGOCD_GIT_ATTEMPTS_COUNT=3
```

After the rollout, repo-server was able to successfully resolve the latest Git revision again.

This is a resilience mitigation rather than a root-cause fix.

It reduces the probability that one transient Git transport failure immediately causes repository reconciliation to fail.

It does not repair the underlying VMware guest networking fault.

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

### P0 — Declaratively manage Argo CD retry configuration

Move:

```text
ARGOCD_GIT_ATTEMPTS_COUNT=3
```

from an imperative live-cluster change into repository-managed Argo CD configuration.

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
