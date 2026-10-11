# 集群内镜像 Registry

这套实验室方案把镜像供应链收敛到 Kubernetes 集群内部，运行时不依赖 Windows 宿主机代理、云代理或公共镜像站。

## 组成

- Registry：`https://192.168.88.3:5000`
- Namespace：`retail-registry`
- 部署：单副本，固定在 `k8s-master`，使用 `hostNetwork`
- 持久化：`local-path-retain`，20Gi，数据落在 master 本地盘
- 加密：自签名 TLS；节点通过 `/etc/containerd/certs.d/.../ca.crt` 信任 CA
- 路由：三个节点的 `_default/hosts.toml` 和 `docker.io/hosts.toml` 指向内部 Registry，未配置外部 fallback

`internal-registry.yaml` 只包含 Kubernetes 对象和 Registry 镜像 digest，不包含私钥或 CA 私密材料。TLS Secret 应在集群外单独生成和管理，证书文件不要提交到 Git。

## 部署与预置

1. 先应用 `internal-registry.yaml`，并创建 `registry-tls`、`registry-http-secret` 两个 Secret。
2. 在每个节点安装相应的 `hosts.toml` 和 CA 到 `/etc/containerd/certs.d`。
3. 使用 `seed-internal-registry.sh` 预置项目、worker 和 CNI 镜像。
4. 使用 `seed-control-images.sh` 预置 control-plane 镜像。
5. 在清空某个节点的镜像缓存后，按原始镜像引用执行 `crictl pull`，再用 `crictl inspecti` 校验 digest。

两个 seed 脚本使用单架构 `linux/amd64` 内容和单并发上传，适配当前实验室节点。首次建立空 Registry 时，需要从一个临时可用的外部或离线 OCI 来源引导 `registry:3`、`busybox` 等基础镜像；完成预置后，节点运行时只访问集群内 Registry。若要求从第一步就完全断网，应提前准备 OCI tar 包并用 `ctr images import` 导入。

## Stage 7 Performance 镜像

Stage 7 负载生成器固定使用：

- Kubernetes 镜像引用：`docker.io/artilleryio/artillery:2.0.22`
- 外部 bootstrap 来源：`ghcr.io/wanghaibing07/retail-reliability-lab-artillery@sha256:302fb531cb18e3685eaa81858cee54750c268df111465386fdbe938918797756`
- 平台：`linux/amd64`
- 内部 Registry：`192.168.88.3:5000/artilleryio/artillery:2.0.22`

集群运行时继续保持 air-gapped 策略；`docker.io` 不配置公共 upstream fallback。`seed-performance.sh` 只在 bootstrap 阶段通过临时 GHCR `hosts.toml` 拉取 digest-pinned 镜像，不修改 `/etc/containerd/certs.d` 的长期配置。

执行：

`./infra/registry/seed-performance.sh`

脚本会依次完成 GHCR digest 拉取、amd64 转换、内部 Registry 上传、manifest digest 校验，以及使用原始 docker.io 镜像引用执行 CRI mirror 验证。

## 关键验收

```bash
kubectl get pods,pvc -n retail-registry -o wide
sudo crictl pull public.ecr.aws/aws-containers/retail-store-sample-orders:1.6.2
sudo crictl inspecti public.ecr.aws/aws-containers/retail-store-sample-orders:1.6.2
sudo grep -R -nE 'daocloud|1panel|proxy' /etc/containerd/certs.d || true
```

本次已在 worker2 删除 Orders 缓存后按原始 `public.ecr.aws/...` 引用冷拉取成功；Registry 日志显示请求来自 `192.168.88.5`，由 `192.168.88.3:5000` 返回内部对象。

## 设计边界

该 Registry 采用内网访问、单副本与节点本地存储。master 停机时 Registry 不可用；生产环境应改为多副本、共享或分布式存储、证书生命周期管理、镜像扫描和审计。`local-path-retain` 的数据也不会自动跨节点复制。

## 回滚

旧的公共镜像站配置保存在各节点的：

```text
/var/backups/k8s-lab/containerd-certs.d-20260912/docker.io-hosts.toml
```

回滚前应先确认没有其他实验依赖当前内部路由，并保留 Registry PVC；不要直接删除 PVC 或 Registry 数据目录。
