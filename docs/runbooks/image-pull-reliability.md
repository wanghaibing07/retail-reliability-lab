# Retail Reliability Lab 镜像拉取可靠性 Runbook

状态：已在本实验室验证（2026-09-12）
范围：`retail` 命名空间、k8s-worker1/2、containerd 2.3.4、Kubernetes v1.28.2

## 1. 结论先行

本次故障不是 Kubernetes 清单、磁盘或 ECR 鉴权错误，而是虚拟机经 VMware NAT 直连 ECR/CDN 时，大镜像层的长连接传输不稳定；containerd 的并发下载和 5 分钟无进度阈值放大了这个问题。

已验证过的恢复路径，以及本次重启后的最终状态是：

1. 曾用宿主机代理证明“替换出口可以完成大层下载”，但该路径已按要求撤销，不作为最终依赖。
2. 两个 worker 的 containerd 不再注入任何宿主机代理环境变量；宿主机 `17890` VMnet8 portproxy 已不存在。本次实验创建的转发链路已撤销；宿主机上其他应用自有的代理防火墙规则未修改，也不在 Kubernetes containerd 路径中。
3. containerd 2.x 的两个相关并发入口都设为 1，镜像无进度超时设为 10 分钟；不要只修改旧版 CRI 配置项后就假定生效。
4. 项目清单使用 `IfNotPresent`；当前 10 个项目镜像已进入两个 worker 的本地缓存，重启后可直接从缓存启动。

当前“无宿主机依赖”状态已经扩展为集群内 TLS Registry：清空节点缓存后，containerd 仍可按原始镜像引用从内网恢复。新增版本仍需先审核 digest、预置和验收；生产环境应使用高可用私有 Registry、共享/分布式存储和受控供应链。

## 2. 证据与验收结果

### 根因证据

- 直连 ECR 的 Orders 最大层约 `141,699,047` 字节；180 秒只收到 `6,045,714` 字节后超时。
- 经过 VMnet8 代理转发后，同一层完整收到 `141,699,047` 字节，用时约 `20.733` 秒，速度约 `6.8 MB/s`。
- 直连时多个大层并发更容易停滞；因此把“并发提高”当作性能优化是不成立的，当前链路应先限流并保证可完成。

### 当前配置证据

两个 worker 的 active containerd 配置均包含：

```toml
[plugins.'io.containerd.cri.v1.images']
max_concurrent_downloads = 1
image_pull_progress_timeout = '10m0s'
use_local_image_pull = false

[plugins.'io.containerd.transfer.v1.local']
max_concurrent_downloads = 1
max_concurrent_unpacks = 1
```

最终状态：两个 worker 的 `systemctl show containerd -p Environment -p DropInPaths` 均为空；原代理 drop-in 已改名为 `10-k8slab-proxy.conf.disabled-20260912`，可审计、可恢复但不会被 systemd 加载。

### 当前验收结果

- 两个 worker 各自持有项目所需的 10 个镜像，逐项 `crictl inspecti` 检查为 `OK`。
- 重启三台 VM 后，Orders 在两个 worker 上执行 `crictl pull` 均返回 `Image is up to date`，不经过宿主机代理。
- `retail` 命名空间 `10/10` 个 Pod 均为 `1/1 Running`。
- 所有应用清单已经显式设置 `imagePullPolicy: IfNotPresent`。
- 变更前已创建 VMware 快照 `pre-image-pull-20260912`，并保留 `/etc/containerd/config.toml.pre-image-pull-20260912`。
- 本次无宿主机依赖重启前创建快照 `pre-no-host-proxy-reboot-20260912`。

### 集群内离线 registry（本次已部署）

为消除 Windows 宿主机代理、云代理和公共镜像站依赖，已在 `k8s-master` 部署单副本 CNCF Distribution Registry 3.1.1：

- 地址：`https://192.168.88.3:5000`；仅监听实验网节点地址，使用内部 TLS 证书，containerd 配置了 CA，未使用 `skip_verify`。
- 命名空间：`retail-registry`；registry Pod 使用 `hostNetwork` 固定在 master，避免依赖业务 CNI 才能完成节点级镜像拉取。
- 存储：`local-path-retain`、20Gi PVC，固定在 master；这是学习集群的单副本方案，不宣称高可用。
- 内容：项目 10 个镜像、Kubernetes control-plane/kube-proxy/pause、Flannel、local-path-provisioner、registry 引导镜像均已预置；以 amd64 内容和 digest 验收。
- containerd：三个节点的 `/etc/containerd/certs.d/docker.io/hosts.toml` 与 `_default/hosts.toml` 均指向内部 registry；原先指向 `docker.m.daocloud.io`、`docker.1panel.live` 的配置已移出 active 目录，不能再作为隐式外部依赖。

### 离线冷拉取证据

在 worker2 上删除未被该节点 Pod 使用的 Orders 镜像缓存，再按原始引用 `public.ecr.aws/aws-containers/retail-store-sample-orders:1.6.2` 拉取成功，digest 仍为 `sha256:b1999c1d...`。registry 日志显示请求来自 `192.168.88.5`，访问路径为 `/v2/aws-containers/retail-store-sample-orders/...?...ns=public.ecr.aws`，大层返回 HTTP 200；之后重启 registry Pod，PVC 仍为 `Bound`，Orders 再次拉取和 inspecti 均通过。

这证明现有项目在清空节点缓存后也可以通过集群内部 registry 恢复，不再依赖宿主机或云代理。需要保留的边界是：registry 只有一个实例且数据在 master 的本地盘；master 故障时镜像服务不可用，生产环境应换成多副本 registry + 共享/分布式存储。

### 公共镜像对照测试（无宿主机代理）

在 `2026-09-12 08:37-08:42 +08:00`，两个 worker 使用同一组未指定宿主机代理的 `crictl pull` 顺序测试；两台机器的 `systemctl show containerd -p Environment -p DropInPaths` 均为 `Environment=`、`DropInPaths=` 空值。成功项随后用 `crictl inspecti` 验证，结果如下：

| 镜像 | worker1 | worker2 | 结果 |
|---|---:|---:|---|
| `docker.io/library/alpine:3.20` | 7s | 7s | 成功 |
| `docker.io/library/busybox:1.36` | 2s | 1s | 成功 |
| `docker.io/library/nginx:1.27-alpine` | 13s | 14s | 成功 |
| `docker.io/library/python:3.12-slim` | 10s | 9s | 成功 |
| `docker.io/library/redis:7.2-alpine` | 15s | 13s | 成功 |
| `docker.io/library/postgres:16-alpine` | 28s | 22s | 成功 |
| `public.ecr.aws/docker/library/nginx:1.27-alpine` | 1s | 1s | 成功 |
| `registry.k8s.io/coredns/coredns:v1.11.1` | 31s 超时 | 32s 超时 | 失败 |

Docker Hub 和 ECR Public 的常见镜像在两个 worker 均能完成；`registry.k8s.io` 的失败不是镜像内容或 containerd 配置错误，而是在解析其后端 `us-west2-docker.pkg.dev`/`europe-west2-docker.pkg.dev` 的 HTTPS manifest 请求时 TCP 443 超时。该对照进一步证明：当前问题是按公共仓库/后端出口划分的网络可达性差异，不能用一个 registry 的成功推断所有 registry 都稳定。测试失败不会影响现有业务 Pod；临时测试脚本已从 worker 删除。

### 重启过程中的额外故障

- VMware 启动初次返回取消，日志显示三台 VM 的 `node1-cl3-000004.vmdk` 需要修复；使用 `vmware-vdiskmanager -R` 对明确的三个链节点修复后才成功启动。
- 启动后 Flannel 的旧 DaemonSet Pod 没有及时重新生成 `/run/flannel/subnet.env`，导致 worker2 的业务 Pod 暂时 `Unknown`；重建三枚 Flannel Pod 后 CNI 恢复，业务 Pod 从本地缓存收敛到 Ready。
- 这些是 VM 磁盘链和 CNI 启动顺序问题，与 Orders 镜像内容无关。

## 3. 高标准方案分层

### L0：诊断必须分层

遇到 `ErrImagePull`/`ImagePullBackOff`，依次区分：DNS、TCP 443、TLS/HTTP、registry 401 challenge、manifest、单层下载、并发下载、containerd 解包和磁盘空间。不能只用 `curl -I https://public.ecr.aws` 成功就判定大层传输正常。

### L1：实验室恢复

代理转发只适合作为一次性诊断/恢复手段：它帮助证明是出口链路问题，但不应成为节点的永久依赖。当前实验采用单并发 + 较长无进度阈值 + 逐节点预拉取，并依靠已验证的本地缓存运行。

### L2：稳定的 registry cache

长期应在实验网段部署 Harbor、Distribution registry proxy cache 或其他受控镜像缓存，让 worker 只访问内网 registry；缓存回源由一个受控出口承担。containerd 应使用 `/etc/containerd/certs.d/<registry>/hosts.toml` 配置镜像主机，并只授予 mirror `pull` 能力；TLS CA 应显式配置，禁止用 `skip_verify` 作为长期方案。

### L3：生产级供应链

生产环境优先使用私有 registry 的 pull-through cache、镜像扫描、访问审计和高可用出口；镜像发布使用不可变 digest，部署清单避免 `latest` 和可变 tag。预拉取属于发布流程的一部分，而不是故障发生后的人工补救。

## 4. 发布与回归流程

1. 在 CI 中解析每个 tag 到 digest，记录来源、架构和发布时间。
2. 将测试环境/缓存 registry 中的 digest 逐节点预拉取。
3. 运行节点缓存验收；任何节点失败都不进入滚动更新。
4. 使用 `IfNotPresent` 启动业务，观察 Pod、事件和 containerd 日志。
5. 发布后保留拉取耗时、失败率、缓存命中率和最后一次成功 digest。

建议验收命令：

```bash
kubectl get nodes -o wide
kubectl get pods -n retail -o wide
kubectl get events -n retail --sort-by=.lastTimestamp

# 在每个 worker 上执行
sudo crictl inspecti <image-reference>
sudo crictl images
sudo systemctl show containerd -p Environment -p DropInPaths
sudo containerd config dump | grep -E 'max_concurrent_downloads|image_pull_progress_timeout|use_local_image_pull'
```

## 5. 回滚边界

如果宿主机代理不可用：先恢复原出口或停止依赖外网的发布，不要删除正在运行的业务容器。

若要撤销本次 containerd 代理配置：删除两个 worker 的 `10-k8slab-proxy.conf`，执行 `systemctl daemon-reload && systemctl restart containerd`，再按快照/备份恢复配置。当前已验证宿主机 `17890` VMnet8 portproxy 不存在；不要为清理本实验而删除其他应用自有的防火墙规则。

## 6. 后续待办

- 把 10 个项目镜像从 tag 迁移为经过审核的 digest 引用。
- 当前已完成 VMnet8 内的单副本 Registry 和断缓存冷拉取验证；下一步评估多副本 Registry、共享/分布式存储与 master 故障切换。
- 将逐节点预拉取和验收命令做成脚本或 CI job，记录失败节点和耗时。
- 为 containerd、registry cache、代理出口和镜像拉取增加可查询日志/指标。

## 7. 资料基线

- [Kubernetes Images：imagePullPolicy、预拉取、串行/并行拉取](https://kubernetes.io/docs/concepts/containers/images/)
- [containerd Registry Configuration：hosts.toml、mirror capabilities、CRI config_path](https://github.com/containerd/containerd/blob/main/docs/hosts.md)
- [containerd CRI Configuration：2.x Transfer Service 与 image pull 配置](https://github.com/containerd/containerd/blob/main/docs/cri/config.md)
- [CNCF Distribution：Registry TLS、存储与 air-gapped 预置](https://distribution.github.io/distribution/about/deploying/)
- [Kubernetes Local Volume：节点本地存储、node affinity 与故障边界](https://kubernetes.io/docs/concepts/storage/volumes/#local)
- [Amazon ECR pull-through cache](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html)
