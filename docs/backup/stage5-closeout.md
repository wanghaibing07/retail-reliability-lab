# Stage 5 Closeout：Orders PostgreSQL Backup / Restore

封板日期：2026-09-28  
实验环境：本地 VMware 三节点 Kubernetes 集群

## 结论

Stage 5 Backup / Restore 完成。

本阶段没有尝试一次性为整个 Retail 构建分布式灾备，而是选择 Orders PostgreSQL 做深度验证，完成：

```text
真实业务数据
→ PostgreSQL 逻辑备份
→ 外部副本与完整性校验
→ 跨 VM 隔离恢复
→ 数据库与应用层读回
→ 生产 emptyDir → PVC 迁移
→ 恢复后新写入
→ PostgreSQL Pod 替换持久性验证
```

允许的最终结论：

> 已验证 Orders PostgreSQL 数据库的备份、持久化和隔离恢复能力。

## 初始风险

Stage 5 开始时：

- StatefulSet：`orders-postgresql`
- PostgreSQL：16.1
- database：`orders`
- PGDATA：`/data/pgdata`
- data volume：`emptyDir`
- source node：`k8s-worker1`
- production PVC：无

因此原始数据库数据与 Pod 生命周期绑定。

业务基线 marker：

```text
f160b51e-6c7d-4479-acc6-96cdcd7f83c0
```

该订单在前端、Orders API 和 PostgreSQL 三层均被确认。

## 1. 可重复备份

新增：

- `scripts/backup-orders.sh`
- `docs/backup/orders-postgresql.md`

备份格式：

```text
pg_dump -Fc
```

fail-closed 检查：

1. 先写 `.partial`
2. archive 非空
3. `pg_restore --list` 可解析
4. 计算 source SHA256
5. 副本写到 source DB VM 之外
6. source / external SHA256 必须一致
7. 写 manifest / validation
8. 全部成功后才发布正式 `.dump`

首个恢复实验 backup：

- backup ID：`20260928T070335Z-9dc19d58`
- source node：`k8s-worker1`
- external backup host：`k8s-master`
- size：6357 bytes
- SHA256：`e5a8f61b74cb300adcb10d34ec4cb458d11a6d4b7329e02d6b566005abd49e3c`
- backup duration：4s
- archive validation：PASS
- external SHA256：PASS

备份文件本体不提交 Git。

## 2. 隔离恢复

隔离恢复目标：

- restore node：`k8s-worker2`
- PostgreSQL：16.1
- 独立 Pod / Service / PVC
- 与生产 PostgreSQL Service selector 分离

实际执行：

```text
k8s-master external backup
→ k8s-worker2 isolated PostgreSQL
→ pg_restore
→ database validation
→ isolated Orders 1.6.2 application validation
```

结果：

- `pg_restore`：PASS
- orders：1
- order_items：1
- shipping_addresses：1
- marker：PASS
- Orders API marker：PASS
- measured restore start → application validation：81.285s

该数值是一次实验观测值，不是生产 RTO 承诺。

## 3. 生产迁移前门禁

先通过 GitOps 进入维护状态：

- Checkout：0
- Orders：0
- PostgreSQL：保持 1
- PostgreSQL 仍使用旧 `emptyDir`

确认：

- Retail：Synced / Healthy
- application write path suspended
- PostgreSQL：Ready
- marker：仍存在

之后生成 final backup：

- backup ID：`20260928T085552Z-9dc19d58`
- source node：`k8s-worker1`
- external host：`k8s-master`
- size：6357 bytes
- SHA256：`ed42fad85324f8cc682cb406d3a03a28943165cfc681726b59f7c7073d15d3dd`
- duration：6s
- archive validation：PASS
- external SHA256：PASS

final backup 完成后源数据库与 marker 仍正常。

## 4. emptyDir → retained PVC

生产目标：

- PVC：`orders-postgresql-data`
- capacity：4Gi
- access mode：RWO
- StorageClass：`local-path-retain`
- reclaimPolicy：Retain
- PV：`pvc-0dd9ab31-7885-495e-9864-2665898491a1`
- node affinity：`k8s-worker2`

切换顺序：

```text
Checkout / Orders = 0
→ final backup PASS
→ PostgreSQL = 0
→ old emptyDir Pod removed
→ production PVC declared
→ temporary restore Pod becomes first consumer
→ PVC Bound on worker2
→ final backup restored
→ marker validation
→ temporary restore Pod removed
→ production StatefulSet resumes
```

生产 PVC restore：

- SHA256：匹配 final backup
- database restore：PASS
- `pg_restore` time：0.365s
- orders：1
- order_items：1
- shipping_addresses：1
- pre-migration marker：PASS

## 5. 生产服务恢复

生产 PostgreSQL 接管：

- Pod：`orders-postgresql-0`
- node：`k8s-worker2`
- PVC：`orders-postgresql-data`
- endpoint：Ready
- restored marker：PASS

随后分阶段恢复：

1. Orders：0 → 1
2. Orders API 读取 pre-migration marker：PASS
3. Checkout：0 → 1
4. 前端正常完成新订单

post-migration order：

```text
9614fdec-30f6-4b27-8fa4-239105720f62
```

验证：

- PostgreSQL：pre / post migration 两个订单均存在
- Orders API：old marker PASS
- Orders API：new marker PASS
- application write validation：PASS

## 6. Pod replacement persistence drill

主动删除生产：

```text
orders-postgresql-0
```

替换前 UID：

```text
4bf2b73d-2494-480f-af9b-e8dddd64fc3d
```

替换后 UID：

```text
7b12b5bd-7d7e-401f-a118-2f675a2cbb25
```

替换后：

- Pod：Ready
- node：`k8s-worker2`
- PVC：仍为 `orders-postgresql-data`
- pre-migration order：存在
- post-migration order：存在
- Orders API old marker：PASS
- Orders API new marker：PASS
- persistence validation：PASS

这证明了 Pod 级删除 / 重建不会再导致 Orders PostgreSQL 数据丢失。

## 7. 数据损失与恢复时间表述

本次受控实验：

- application writes 在 final backup 前已冻结
- final backup 中已确认的 pre-migration marker 恢复成功
- 恢复后新创建订单成功写入 PVC-backed PostgreSQL
- persistence drill 后新旧两个 marker 均存在

因此可陈述：

> 本次受控恢复实验中未观察到已确认 Orders 记录丢失。

不应陈述：

- 保证 RPO=0
- 保证固定 RTO
- 整个 Retail 具备一致性灾备

已测时间：

- first backup：4s
- final backup：6s
- isolated restore → application validation：81.285s
- production PVC `pg_restore`：0.365s

生产维护窗口没有使用统一自动计时器采集精确 end-to-end RTO，因此不补造一个 RTO 数字。

## 8. 已知边界

1. Stage 5 只完整覆盖 Orders PostgreSQL。
2. catalog-mysql 未执行正式 restore drill。
3. orders-rabbitmq 未纳入数据库一致性快照。
4. checkout-redis / carts-dynamodb 未纳入正式恢复链路。
5. PostgreSQL 逻辑备份不是整个 Retail 的分布式一致性快照。
6. `k8s-master` 副本虽然离开源数据库 VM，但仍与其他 VMware guest 共用同一物理宿主，不是异地备份。
7. `local-path-retain` 是节点本地存储，不是跨节点复制存储。
8. persistence drill 证明 Pod replacement，不证明 `k8s-worker2` 整节点丢失后的自动恢复。
9. 没有实现持续周期备份、PITR 或 WAL archive，因此不宣称持续 RPO 保障。
10. 本阶段没有引入 Operator、Velero、Ceph 等额外系统。

这些边界不阻塞 Stage 5 封板，因为本阶段目标是建立最小、真实、可复现、可验证的 Orders PostgreSQL 恢复能力。

## 主要证据

- [首个隔离恢复证据](../evidence/stage5/20260928T070335Z-9dc19d58/README.md)
- [生产 PVC cutover evidence](../evidence/stage5/production-pvc-cutover/README.md)
- [Backup 设计](orders-postgresql.md)
- [Restore Runbook](../runbooks/orders-postgresql-restore.md)
- [PVC Migration Runbook](../runbooks/orders-postgresql-pvc-migration.md)
- `scripts/backup-orders.sh`
- `scripts/restore-orders.sh`

## 下一阶段

Stage 6：Release Failure & Recovery。

重点转向：

- 发布失败
- 错误版本 / 不健康版本
- rollout 失败判定
- 回滚路径
- GitOps 下的安全恢复
- 发布恢复证据
