# Decision 001: Use a dedicated Argo CD resource tracking label

Status: Accepted

## Context

The upstream Retail manifests already use:

`
app.kubernetes.io/instance
`

as part of the business/application labeling model. Argo CD also uses that label by default for resource ownership tracking.

During Application adoption this created ambiguous ownership semantics and risked modifying labels that belong to the upstream application's identity.

## Decision

Configure Argo CD to use:

`
argocd.argoproj.io/instance
`

for Application resource tracking.

The live configuration used:

`yaml
data:
  application.instanceLabelKey: argocd.argoproj.io/instance
`

## Result

`
argocd.argoproj.io/instance=retail
`

identifies Argo ownership while existing business labels such as:

`
app.kubernetes.io/instance=catalog
`

remain unchanged.

## Consequences

- Argo ownership is separated from application identity.
- Upstream vendor labels remain intact.
- Resource comparison is easier to reason about.
- The setting must ultimately be declared in Git rather than existing only as an imperative live-cluster patch.

## Related Work

- [Stage 3 GitOps](../gitops/stage3-gitops.md)
- [Incident #003](../incidents/003-argocd-repo-server-github-timeout/README.md)
- infra/argocd/retail-application.yaml
