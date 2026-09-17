# Stage 3: Argo CD / GitOps

## Goal

Make Git the source of desired Kubernetes application state while keeping delivery observable and reversible.

## Desired-State Path

The Retail desired state used by CI and Argo CD is:

`
infra/apps/retail
`

Kustomize composes the fixed upstream manifest in infra/vendor/ with project patches.

## CI Flow

Pull requests and pushes validate:

`
Bash syntax
→ ShellCheck
→ kubectl kustomize
→ kubeconform on rendered output
→ reject :latest
`

CI validates rendered desired state rather than only the raw vendor manifest.

## Argo CD Application

The Application tracks:

| Field | Value |
| --- | --- |
| Repository | wanghaibing07/retail-reliability-lab |
| Revision | main |
| Path | infra/apps/retail |
| Namespace | retail |

The Application was initially operated with Manual Sync so that Git observation and deployment could be demonstrated separately.

## Resource Adoption

The initial adoption preserved the upstream business labels. Argo ownership uses argocd.argoproj.io/instance; the decision is recorded in [ADR 001](../decisions/001-argocd-resource-tracking.md).

## First GitOps Change

PR #6 changed the UI replica count from 1 to 2 through a Kustomize patch. The PR passed CI and was merged to main at revision 23f582e.

The resulting release sequence was:

`
Git change
→ Pull request
→ CI pass
→ merge
→ Argo detects OutOfSync
→ Manual Sync
→ UI 2/2
`

The before/after snapshots are kept in [the Manual Sync evidence](../../evidence/gitops-first-manual-sync/after.txt).

The live Application is now Synced; its health field remains Progressing in the current cluster snapshot even though all Retail workloads, endpoints and the business HTTP check passed. This is recorded as a known Argo health-status follow-up rather than being silently reported as Healthy.

## Verification

The current verification run reported:

- 10 Deployment/StatefulSet rollouts passed
- all 11 current Retail Pods were Ready
- all 10 selected Services had Ready endpoints
- business HTTP returned 200

## Repository Access Incident

During this experiment Argo CD repo-server intermittently failed Git requests to GitHub. See [Incident #003](../incidents/003-argocd-repo-server-github-timeout/README.md). The incident is kept separate from the normal GitOps release workflow.

## Remaining Stage 3 Work

`
1. Explain and close the remaining Argo Application health state
2. Remove multiple desired-state entry points
3. Declaratively manage Argo platform configuration
4. Enable and test Auto Sync with prune disabled
5. Enable and test Self Heal
6. Test prune separately with an explicit safety policy
`

Auto Sync, self-heal and prune remain separate capabilities. They are not claimed as completed by the Manual Sync evidence.
