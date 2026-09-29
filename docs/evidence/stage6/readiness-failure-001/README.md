# Stage 6 Evidence — Readiness Failure #001

实验日期：2026-09-29

## 目标

验证一个能够通过静态 CI、但运行时 readiness 失败的 UI 发布，并证明：

- Kubernetes 能阻止坏 Pod 成为 Ready backend
- 旧健康实例能继续提供服务
- rollout failure 能被明确检测
- Prometheus 能针对 Deployment stalled 状态告警
- 恢复通过 Git desired state 完成
- Argo CD 能自动把集群恢复到健康状态

## Git revisions

Stable release-safety baseline:

    bf74d52c15bb5b074407a5b0de999cad38c3f6ec

Intentional bad release:

    PR #50
    ba058deadec602ae0392ab8a42cb2c72fa13061d

Recovery commit:

    2cb8ed53d7e16eee7d5b201790a37c392105e9fc

Recovery merge:

    PR #51
    9cae7211894947f6a780fcac9678121255e675a0

## Failure

Intentional change:

    /actuator/health/readiness
    ->
    /stage6-intentional-readiness-failure

Container image remained unchanged:

    public.ecr.aws/aws-containers/retail-store-sample-ui:1.6.2
    sha256:489421be17ec24f7d89cf603b8519fb78711b323b63c723f8be833a07bdf7206

Observed bad ReplicaSet:

    ui-bf4cfc995
    desired=1
    ready=0

Observed bad Pod:

    ui-bf4cfc995-5mxkw
    Running
    Ready=False
    restarts=0
    node=k8s-worker2
    IP=10.244.2.104

The readiness endpoint returned HTTP 404 after startup.

The Pod remained running, proving the experiment was a readiness regression rather than an image-pull or container-crash failure.

## Blast-radius control

Release-safety configuration:

    replicas=2
    progressDeadlineSeconds=120
    maxUnavailable=0
    maxSurge=1

During the failed rollout:

    healthy old replicas = 2
    bad new replicas     = 1
    healthy replicas     = 2
    NotReady replicas    = 1

EndpointSlice:

    ui-646d576cb4-w5vmr  10.244.1.152  ready=true
    ui-646d576cb4-x6jlw  10.244.1.153  ready=true
    ui-bf4cfc995-5mxkw   10.244.2.104  ready=false

The intentionally broken Pod was therefore not a Ready Service backend.

Captured user-facing HTTP requests remained HTTP 200 throughout the observation sample.

This experiment does not claim that every possible request experienced zero failure; it only records that no outage was observed in the captured HTTP samples.

## Failure detection

Deployment eventually reported:

    Progressing=False
    Reason=ProgressDeadlineExceeded

`kubectl rollout status deployment/ui`:

    rc=1
    deployment "ui" exceeded its progress deadline

Prometheus confirmed:

    kube_deployment_status_condition{
      namespace="retail",
      deployment="ui",
      condition="Progressing",
      status="false",
      reason="ProgressDeadlineExceeded"
    } = 1

Stage 6 alert:

    KubernetesDeploymentRolloutStalled
    state=firing

Retail user-facing availability alert:

    RetailUIProbeFailed
    not active in the captured failure state

This distinguishes a failed release from a user-facing availability outage.

## Timing

Authoritative / observed timestamps:

    bad PR merged                2026-09-29T07:34:37Z
    Argo sync started            2026-09-29T07:39:37Z
    Argo sync finished           2026-09-29T07:39:38Z
    ProgressDeadlineExceeded     2026-09-29T07:41:39Z
    Git recovery started         2026-09-29T07:54:06Z
    recovery PR merged           2026-09-29T08:09:12Z
    Argo Healthy observed        2026-09-29T08:09:53Z
    final validation completed   2026-09-29T08:10:40Z

Measured intervals:

    bad merge -> Argo sync start             5m00s
    Argo sync start -> rollout failure       2m02s
    Argo sync finish -> rollout failure      2m01s
    bad merge -> rollout failure             7m02s
    rollout failure -> recovery start        12m27s
    recovery start -> recovery merge         15m06s
    recovery merge -> Argo Healthy           41s
    recovery merge -> final validation       1m28s
    bad merge -> Argo Healthy                35m16s
    bad merge -> final validation            36m03s

The 7m02s merge-to-detection interval must not be interpreted as the Kubernetes progress deadline.

Five minutes elapsed before Argo CD began reconciling the new Git revision.

Once Argo began the bad rollout, `ProgressDeadlineExceeded` was observed approximately 122 seconds later, consistent with the configured 120-second Deployment progress deadline plus observation/controller timing.

These values are measurements from one local-lab experiment, not production SLO, RTO, or MTTR guarantees.

## Recovery

No authoritative recovery was performed with:

- `kubectl rollout undo`
- `kubectl patch`
- `kubectl set image`
- Argo CD application rollback

Recovery used:

    identify bad Git merge
    ->
    verify merge parent
    ->
    git revert -m 1
    ->
    recovery branch
    ->
    PR #51
    ->
    CI PASS
    ->
    merge
    ->
    Argo CD reconciliation

After recovery:

    readinessPath=/actuator/health/readiness
    progressDeadlineSeconds=120
    maxUnavailable=0
    maxSurge=1

Healthy ReplicaSet:

    ui-646d576cb4
    desired=2
    ready=2

Bad ReplicaSet:

    ui-bf4cfc995
    desired=0
    ready=0

The failed ReplicaSet remains as Deployment revision history; deletion is not required for recovery.

Final state:

    Retail revision=9cae7211894947f6a780fcac9678121255e675a0
    Sync=Synced
    Health=Healthy
    HTTP=200
    verify.sh=PASS
    KubernetesDeploymentRolloutStalled=inactive

## Evidence files

The files in this directory contain the captured Git, Argo CD, Kubernetes, EndpointSlice, HTTP, Prometheus and recovery evidence used for the conclusions above.

They intentionally exclude credentials, kubeconfig files, Secret values and unnecessary full logs.

## Result

Stage 6 Controlled Failure #001 demonstrated:

    static CI PASS
    ->
    runtime readiness regression
    ->
    controlled rollout stall
    ->
    old healthy replicas retained
    ->
    user-facing HTTP remained available in observed samples
    ->
    ProgressDeadlineExceeded
    ->
    rollout-stalled alert firing
    ->
    Git revert recovery
    ->
    Argo CD reconciliation
    ->
    healthy application
    ->
    alert cleared

Result: PASS
