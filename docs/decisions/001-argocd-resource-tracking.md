# Decision 001: Use Argo CD annotation-based resource tracking

Status: Accepted

## Context

The upstream Retail manifests use:

~~~
app.kubernetes.io/instance
~~~

as part of the business/application labeling model.

An audit of the running Retail Application recorded `argocd.argoproj.io/tracking-id` on 33/33 observed resources and `argocd.argoproj.io/instance` on 0/33. The repository-managed Application also does not set `application.instanceLabelKey`. The previous description of a dedicated tracking label was therefore not supported by the live evidence.

## Decision

Use Argo CD annotation-based resource tracking and declare the tracking mode explicitly in Git.

The Argo CD platform configuration now contains:

~~~
application.resourceTrackingMethod: annotation
~~~

Argo ownership is represented on resources through:

~~~
argocd.argoproj.io/tracking-id
~~~

Keep business identity labels such as `app.kubernetes.io/instance` separate from Argo-owned tracking metadata.

## Live Evidence

- 33/33 observed Retail resources carried an `argocd.argoproj.io/tracking-id` annotation.
- 0/33 observed Retail resources carried an `argocd.argoproj.io/instance` tracking label.
- `infra/argocd/platform` explicitly declares `application.resourceTrackingMethod: annotation`.
- The same platform configuration declares `application.instanceLabelKey: argocd.argoproj.io/instance`.
- With `resourceTrackingMethod: annotation`, resource ownership is tracked through the Argo tracking annotation rather than that label key.

## Result

Argo ownership is represented by the tracking annotation while existing business labels such as:

~~~
app.kubernetes.io/instance=catalog
~~~

remain unchanged.

## Consequences

- Argo ownership is kept separate from application identity.
- The documentation matches the observed live resource metadata.
- Tracking mode remains auditable through the Application resource tree and resource annotations.
- Tracking mode is explicitly versioned in Git.
- Any future tracking-mode change must go through normal review and a fresh resource audit.

## Related Work

- [Stage 3 GitOps](../gitops/stage3-gitops.md)
- [Incident #003](../incidents/003-argocd-repo-server-github-timeout/README.md)
- [Retail Application](../../infra/argocd/retail-application.yaml)
- [Argo CD 2.14 to 3.0 upgrade notes](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.14-3.0/)
