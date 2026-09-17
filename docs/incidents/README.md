# Incident Reviews

This directory contains evidence-based incident reviews produced during the Retail Reliability Lab.

| Incident | Scope | Status |
| --- | --- | --- |
| [#001](001-image-pull-failure/README.md) | Public registry image-pull instability | Resolved / hardened |
| [#002](002-containerd-metadata-corruption/README.md) | containerd local metadata corruption after unexpected power loss | Recovered |
| [#003](003-argocd-repo-server-github-timeout/README.md) | Argo CD GitHub access timeout through the guest egress path | Partially mitigated; exact component not isolated |

## Documentation Principle

Incident reviews record:

`
what happened
→ impact
→ evidence
→ diagnosis
→ mitigation/recovery
→ validation
→ lessons
→ measurable follow-up
`

Runbooks are maintained separately because they answer a different question:

`
How should the next operator diagnose or recover this class of failure?
`

Design decisions are also kept separately from incidents.
