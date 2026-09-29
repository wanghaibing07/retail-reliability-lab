# Stage 6 Closeout：Release Failure & Recovery

封板日期：2026-09-29
实验环境：本地 VMware 三节点 Kubernetes 集群

## 结论

Stage 6 Release Failure & Recovery 完成。

本阶段没有引入 Argo Rollouts、Service Mesh 或额外 progressive-delivery controller，而是基于现有 Kubernetes Deployment、readiness、Argo CD、Prometheus 和 Git 工作流完成一次真实发布失败与恢复实验。

最终闭环：

    stable release
    ->
    release safety guardrails
    ->
    intentional readiness regression
    ->
    CI PASS
    ->
    Git merge
    ->
    Argo CD auto reconciliation
    ->
    new Pod Running / NotReady
    ->
    bad Pod excluded from Ready traffic
    ->
    rollout stalled
    ->
    ProgressDeadlineExceeded
    ->
    Prometheus alert firing
    ->
    Git revert PR
    ->
    CI PASS
    ->
    recovery merge
    ->
    Argo CD reconciliation
    ->
    application healthy
    ->
    alert cleared

允许的最终结论：

> 已在当前 Kubernetes + Argo CD GitOps 环境中验证一次受控 UI 发布失败的检测、故障范围控制和 Git 驱动恢复流程。

## 1. Release safety baseline

Stage 6 开始前：

    UI replicas=2
    maxUnavailable=1
    maxSurge=25%
    progressDeadlineSeconds=600

新增长期保留的发布护栏：

    progressDeadlineSeconds=120
    maxUnavailable=0
    maxSurge=1

合并：

    PR #49
    bf74d52c15bb5b074407a5b0de999cad38c3f6ec

上线后：

- Retail：Synced / Healthy
- Observability：Synced / Healthy
- UI：2/2 Ready
- HTTP：200
- verify.sh：PASS

修改 Deployment strategy / deadline 没有改变 Pod template，因此没有为了安装护栏而创建新的 UI ReplicaSet。

## 2. Rollout-stalled monitoring

新增：

    KubernetesDeploymentRolloutStalled

判据：

    kube_deployment_status_condition{
      namespace="retail",
      condition="Progressing",
      status="false",
      reason="ProgressDeadlineExceeded"
    } == 1

该规则：

- 通过 Prometheus 3.13.3 `promtool check rules`
- 具备 healthy / firing / clear 单元测试
- 与已有 Stage 4 Prometheus tests 一起执行并全部 PASS
- 已纳入 GitHub Actions CI
- 已在真实 Stage 6 bad release 中观察到 firing
- recovery 后观察到 cleared / inactive

## 3. Controlled Failure #001

实验对象：

    Deployment/ui

Intentional change：

    readiness:
      /actuator/health/readiness
      ->
      /stage6-intentional-readiness-failure

镜像保持：

    public.ecr.aws/aws-containers/retail-store-sample-ui:1.6.2

因此实验变量只涉及 readiness 配置。

Bad release：

    PR #50
    merge=ba058deadec602ae0392ab8a42cb2c72fa13061d

PR #50 的 push / pull-request CI 均 PASS。

这真实证明：

> 静态 CI 验证通过不等价于运行时发布健康。

它不表示静态 CI 无价值，而是说明 schema、render、policy validation 与 runtime readiness validation 解决的是不同问题。

## 4. Runtime failure

Argo CD 确认同步 bad revision：

    revision=ba058deadec602ae0392ab8a42cb2c72fa13061d
    Sync=Synced
    Health=Degraded

Bad ReplicaSet：

    ui-bf4cfc995
    desired=1
    ready=0

Bad Pod：

    ui-bf4cfc995-5mxkw
    phase=Running
    Ready=False
    restarts=0
    node=k8s-worker2
    IP=10.244.2.104

Bad readiness path：

    /stage6-intentional-readiness-failure

steady failure：

    HTTP 404

Container image digest 与稳定版本一致。

因此根因被明确限定为 intentional readiness regression，而不是：

- image pull
- image version change
- container crash
- scheduling failure
- registry failure

## 5. Blast-radius control

失败期间：

    old healthy ReplicaSet:
      ui-646d576cb4
      desired=2
      ready=2

    bad ReplicaSet:
      ui-bf4cfc995
      desired=1
      ready=0

EndpointSlice：

    10.244.1.152 ready=true
    10.244.1.153 ready=true
    10.244.2.104 ready=false

因此坏 Pod 没有成为 Ready Service backend。

观测期间采集的 UI HTTP 请求均返回：

    HTTP 200

本阶段只陈述：

> 在受控实验的 HTTP 观测样本中未观察到用户入口 outage。

不扩大声称：

- 生产零停机已证明
- 所有请求均绝对成功
- 所有类型 release regression 都能被该策略隔离

## 6. Rollout failure detection

Deployment 最终：

    Available=True
    Progressing=False
    Reason=ProgressDeadlineExceeded

`kubectl rollout status deployment/ui`：

    rc=1
    deployment "ui" exceeded its progress deadline

Prometheus：

    kube_deployment_status_condition{
      namespace="retail",
      deployment="ui",
      condition="Progressing",
      status="false",
      reason="ProgressDeadlineExceeded"
    } = 1

Stage 6 alert：

    KubernetesDeploymentRolloutStalled
    state=firing

同期：

    RetailUIProbeFailed
    inactive in captured state

这证明本阶段能够区分：

    release health failure
    !=
    user-facing availability failure

## 7. GitOps recovery

没有将以下操作作为正式 recovery：

    kubectl rollout undo
    kubectl patch
    kubectl set image
    argocd app rollback

Bad merge：

    ba058deadec602ae0392ab8a42cb2c72fa13061d

Merge parents：

    parent 1:
    bf74d52c15bb5b074407a5b0de999cad38c3f6ec

    parent 2:
    6aa02a450cb28e93cdc3b577542d6c9190e11eb8

在明确 parent 关系后执行：

    git revert -m 1 --no-commit

先检查 recovery diff，再形成正式 recovery commit：

    2cb8ed53d7e16eee7d5b201790a37c392105e9fc

Recovery：

    PR #51
    push CI=PASS
    pull-request CI=PASS
    merge=9cae7211894947f6a780fcac9678121255e675a0

Git 恢复后由 Argo CD 自动 reconciliation，没有通过 imperative live rollback 绕开 Git source of truth。

## 8. Recovery validation

最终：

    Retail revision:
    9cae7211894947f6a780fcac9678121255e675a0

    Sync:
    Synced

    Health:
    Healthy

UI：

    desired=2
    ready=2
    available=2

Healthy ReplicaSet：

    ui-646d576cb4
    desired=2
    ready=2

Bad ReplicaSet：

    ui-bf4cfc995
    desired=0
    ready=0

恢复后的配置：

    readinessPath=/actuator/health/readiness
    progressDeadlineSeconds=120
    maxUnavailable=0
    maxSurge=1

最终：

- EndpointSlice：2 个 healthy ready endpoints
- HTTP：200
- `ProgressDeadlineExceeded` metric：不存在
- `KubernetesDeploymentRolloutStalled`：inactive
- `verify.sh`：PASS
- 10 workloads：PASS
- 10 services：PASS
- active Pods：全部 Ready

## 9. Timing

事件：

    bad PR merged                2026-09-29T07:34:37Z
    Argo bad sync started        2026-09-29T07:39:37Z
    Argo bad sync finished       2026-09-29T07:39:38Z
    rollout failure detected     2026-09-29T07:41:39Z
    recovery started             2026-09-29T07:54:06Z
    recovery PR merged           2026-09-29T08:09:12Z
    Argo Healthy observed        2026-09-29T08:09:53Z
    final validation completed   2026-09-29T08:10:40Z

Measured:

    bad merge -> Argo sync start           5m00s
    Argo sync start -> rollout failure     2m02s
    Argo sync finish -> rollout failure    2m01s
    bad merge -> failure detection         7m02s
    failure detection -> recovery start    12m27s
    recovery start -> recovery merge       15m06s
    recovery merge -> Argo Healthy         41s
    recovery merge -> final validation     1m28s
    bad merge -> Argo Healthy              35m16s
    bad merge -> final validation          36m03s

Important interpretation:

The 7m02s bad-merge-to-failure interval is not the Kubernetes progress deadline.

Five minutes elapsed before Argo CD began synchronizing the Git change.

After Argo began applying the bad revision, the Deployment reached `ProgressDeadlineExceeded` approximately 122 seconds later, closely matching the configured `progressDeadlineSeconds=120`.

These are observed experiment durations, not production SLO, RTO or MTTR guarantees.

## 10. What Stage 6 proved

Stage 6 demonstrated:

    protected Git change
    ->
    CI PASS
    ->
    runtime release failure
    ->
    Kubernetes readiness isolation
    ->
    limited rollout blast radius
    ->
    Deployment failure condition
    ->
    Prometheus alert
    ->
    Git revert
    ->
    CI PASS
    ->
    Argo CD recovery
    ->
    business healthy

The key engineering result is:

> 发布失败是可发现的、影响范围是可控的、恢复过程是可审计的，而且 Git 始终保持唯一 desired-state 来源。

## 11. Known boundaries

Stage 6 does not prove:

1. Every release regression can be detected automatically.
2. Every business-semantic regression will fail readiness.
3. Automatic rollback has been implemented.
4. Canary deployment has been implemented.
5. Blue/Green deployment has been implemented.
6. Production zero-downtime has been proven.
7. Every Retail service has equivalent release guardrails.
8. A Pod that remains Ready but returns incorrect business results would be detected by this experiment.
9. The measured local-lab timings represent production SLO / RTO / MTTR.
10. Argo CD Git polling delay is bounded to the timings observed in this single experiment.

No Argo Rollouts, Istio, Service Mesh or additional deployment controller was required to meet the Stage 6 objective.

## 12. Evidence

Primary evidence:

- `docs/evidence/stage6/readiness-failure-001/`
- `docs/runbooks/release-failure-recovery.md`

Important Git history:

    PR #49 - release safety guardrails
    PR #50 - intentional bad release
    PR #51 - Git-driven recovery

## Final state

    main=9cae7211894947f6a780fcac9678121255e675a0
    Retail=Synced / Healthy
    UI=2/2 Ready
    HTTP=200
    verify.sh=PASS
    KubernetesDeploymentRolloutStalled=inactive

Stage 6 technical experiment: PASS.

Stage 6 release is ready for documentation closeout and `stage6-v0.7` after final documentation CI is merged.

## Next stage

Stage 7：Performance / Capacity。

Do not begin Stage 7 until the Stage 6 documentation closeout is merged, final main validation passes and the `stage6-v0.7` annotated release tag is created.
