# containerd Registry Routing

## Scope

本文件记录本实验室对 containerd Registry 路由和镜像恢复路径的验证结果。
它不是生产级高可用 Registry 设计：当前方案的单副本、节点本地存储和实验网段边界必须在生产环境重新设计。
本次项目收口只补充文档和证据，不在此 PR 中修改 containerd、CNI、Windows NAT 或业务 Deployment 的运行时配置。
## Problem

安装 Argo CD 时出现 ImagePullBackOff。

涉及镜像：

```text
quay.io/argoproj/argocd:v3.5.2
ghcr.io/dexidp/dex:v2.45.1
public.ecr.aws/docker/library/redis:8.2.3-alpine
```

## Root Cause

containerd 使用：

```text
/etc/containerd/certs.d/_default/hosts.toml
```

原配置将实验室 Registry：

```text
192.168.88.3:5000
```

设置为默认 server。

因此没有独立 registry 配置的镜像请求会被强制发送到实验室 Registry，
且不会正常回源官方 Registry。

实验室 Registry 中不存在对应 Argo CD 镜像，因此出现：

```text
404 Not Found
ImagePullBackOff
```

同时曾出现本地 Registry CA 信任问题：

```text
x509: certificate signed by unknown authority
```

## Final Policy

实验环境采用：

- Local registry first
- Official registry fallback

默认 hosts 配置不再将实验室 Registry 设置为唯一 server。

针对需要明确配置的 Registry，可建立独立目录：

```text
/etc/containerd/certs.d/quay.io/
/etc/containerd/certs.d/ghcr.io/
/etc/containerd/certs.d/public.ecr.aws/
/etc/containerd/certs.d/docker.io/
```

## Verification

使用：

```bash
crictl pull <image>
```

分别验证：

- quay.io
- ghcr.io
- public.ecr.aws
- docker.io

并确认：

```bash
systemctl is-active containerd
crictl info
```
