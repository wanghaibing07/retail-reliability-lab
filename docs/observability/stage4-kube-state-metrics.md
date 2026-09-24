# Stage 4：kube-state-metrics 验收（2026-09-24）

时区：北京时间 UTC+08:00。以下运行态来自用户在实验集群提供的终端结果。

## 变更

PR #38 增加 kube-state-metrics v2.20.0，并将对象状态采集范围限制为：

- Node
- Pod
- Deployment
- StatefulSet

Prometheus 增加 `kube-state-metrics` scrape job。RBAC 仅允许对上述资源执行 `list/watch`。

## 镜像准备

- source：`registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.20.0`
- master 通过 `ctr images pull --local` 成功取得 linux/amd64 镜像
- source digest：`sha256:42cfe3723a5f058171c627537fb57a3ea0f26e4380fa18555a95cb1a1b4cfc5b`
- 已 seed 到内部 Registry：`192.168.88.3:5000/kube-state-metrics/kube-state-metrics:v2.20.0`
- worker1 使用原始镜像引用成功取得同版本镜像
- 当前证据证明镜像可用，但不单独声称该次 worker1 pull 一定由内部 Registry 提供

## 运行态验收

2026-09-24 19:38 CST：

- observability Application revision：`1c693beb54c115d776cc97e43f897ca70f0100ce`
- Argo CD：Synced / Healthy
- kube-state-metrics Deployment：successfully rolled out
- Pod：`kube-state-metrics-6dfcc55485-8cvv5`
- Ready：1/1
- Status：Running
- Restarts：0
- Node：`k8s-worker1`

Prometheus 共 8 个配置 target，全部 `up=1`：

- alertmanager
- argocd-application-controller
- argocd-repo-server
- argocd-server
- blackbox-exporter
- kube-state-metrics
- prometheus
- retail-ui-nodeport

Node Ready：

- k8s-master = 1
- k8s-worker1 = 1
- k8s-worker2 = 1

Retail Deployment 可用副本指标已返回：catalog=1、carts-dynamodb=1、carts=1、orders=1、checkout-redis=1、ui=2、checkout=1。

Retail StatefulSet Ready 指标已返回：orders-rabbitmq=1、orders-postgresql=1、catalog-mysql=1。

终端捕获中 Deployment/StatefulSet 行出现重复，Pod 状态查询返回数值但未保留足够标签；这些格式问题不影响 S4-C3 的核心验收结论，因此不重复采样。

## 结论

S4-C3 完成。S4-C 整包完成：

- C1：Prometheus TSDB PVC 持久化已跨 Pod 替换验证
- C2：Blackbox Exporter / Alertmanager 自身指标已采集
- C3：Kubernetes Node/Pod/Deployment/StatefulSet 对象状态已进入 Prometheus

下一步进入 S4-D：少量可行动告警和四组诊断查询。
