# Decision 002: Rebuild the lab cluster on Kubernetes 1.36.4

Status: Accepted

## Context

The lab cluster previously ran Kubernetes 1.28.

The project had already demonstrated:

- reproducible application deployment
- Git-based desired state
- Argo CD reconciliation
- automated workload/service/business verification

A direct in-place jump from Kubernetes 1.28 to 1.36 is not a supported upgrade path.

The Retail databases still use `emptyDir`, so this project does not claim business-data persistence or disaster recovery at this stage.

The internal Registry is different: its data is stored on a retained local-path PV and had to survive the cluster rebuild.

## Decision

Rebuild the three-node cluster on Kubernetes 1.36.4 instead of performing a long sequence of in-place minor-version upgrades.

Rebuild order:

```text
worker1
→ worker2
→ control plane
→ CNI
→ workers rejoin
→ Registry
→ Storage
→ Argo CD
→ Retail GitOps recovery
```

Runtime baseline:

```text
Kubernetes 1.36.4
containerd 2.3.4
Flannel 0.28.9
local-path-provisioner 0.0.36
Argo CD 3.5.2
```

## Safety Boundary

Before destructive work, the following were preserved:

* etcd snapshot
* `/etc/kubernetes`
* containerd configuration and registry CA configuration
* kubeadm configuration
* Registry Kubernetes manifests and Secrets
* Registry retained hostPath data
* Registry data tar backup

The Registry PV was restored using explicit PV/PVC prebinding so the existing retained hostPath was reused instead of dynamically allocating an empty replacement volume.

## Execution

Both workers were reset and prepared on Kubernetes 1.36.4 before rebuilding the control plane.

The first control-plane `kubeadm init` invocation exited during:

```text
wait-control-plane
```

with an API connection-refused error.

The failure state was preserved instead of immediately resetting again.

Investigation showed that:

* etcd was Running and had elected a leader
* kube-apiserver was Running and listening on 6443
* controller-manager and scheduler were Running
* the API `/readyz` endpoint passed

The remaining kubeadm phases were then completed explicitly.

Flannel was restored and the control-plane node became Ready.

worker1 and worker2 then rejoined the rebuilt cluster.

## Validation

Cluster foundation validation passed:

```text
3/3 Nodes Ready
Flannel 3/3 Ready
kube-proxy 3/3 Ready
CoreDNS 2/2 Ready
cross-node DNS PASS
```

Storage recovery passed:

```text
local-path dynamic provisioning PASS
read/write PASS
Delete reclaim PASS
Registry retained PV Bound
Registry API PASS
```

GitOps recovery passed:

```text
Argo CD platform Ready
Retail Application Synced / Healthy
revision = 3c5e7c088cc93402d4b947443738a342b0fe863d
10 workloads PASS
10 Services with Ready Endpoints
11 Retail Pods Ready
business HTTP 200
verify.sh PASS
```

repo-server was restarted and the Application was hard-refreshed afterward.

The Application remained:

```text
Synced / Healthy
```

at the expected Git revision.

## Consequences

The project now has a new known-good Kubernetes baseline:

```text
Kubernetes 1.36.4
```

The rebuild provides stronger evidence than a documentation-only claim of reproducibility:

```text
cluster destroyed/rebuilt
→ platform restored
→ GitOps restored
→ application automatically reconciled
→ business verification passed
```

## Known Boundaries

This decision does not claim:

* HA control plane
* database persistence
* database backup/restore
* application data disaster recovery
* resolution of the direct GitHub network-path fault

Those remain separate project concerns.

## Evidence

See:

```text
evidence/pre-stage4-20260923/
evidence/verify-20260923-163933.log
docs/incidents/003-argocd-repo-server-github-timeout/
```

