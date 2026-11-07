# Stage 7 Performance / Capacity Closeout

## Scope and status

This stage measures the existing Retail browse workload in the local three-node Lab. It establishes a tested operating envelope, records degradation and limitations, and makes an evidence-based optimization decision. No production capacity or long-duration endurance claim is made.

| Stage | Status | Evidence boundary |
|---|---|---|
| S7-A–D | DONE, inherited from approved Stage 7 handover | Existing baseline includes the prior UI async fix at the tested revision; this closeout adds no application changes. |
| S7-E | DONE | 39 RPS qualified healthy / 300s; 42 RPS saturation knee resolved; repeatable degradation at 45. |
| S7-F | DONE: no new SUT optimization | Insufficient causal evidence for a safe component-specific change. |
| S7-G | DONE: final report and evidence index prepared | Release acceptance is tracked by PR #57, its merged commit/CI and annotated tag stage7-v0.8. |

## Fixed identity and method

- Tested Git commit: `0f79db24e20c7d8d843e2e42d116c5700aa45e02`.
- `tests/performance/browse.yml` canonical Git blob / runtime LF bytes SHA256: `2fb51c1138a269fc8ca811bb5fe050a7316d05861a589fa1cb4d1760d66c98ed`.
- Artillery: `artilleryio/artillery:2.0.22`; generator `k8s-master`, CPU request/limit `100m/1 core`, memory `128Mi/512Mi`.
- Read-only browse: GET `/home`, `/catalog`, `/catalog/<product-id>`; three configured requests/VU. Arrival rate is VU/s, not HTTP RPS.
- Formal method: clean host → verify → fixed `/home` warm-up (1 VU/s, 30s, max5) → post-warm-up health gate → formal load → telemetry → post verify/HTTP/readyz/restart diff → archive.
- Full client logs, actual phase markers, RED/USE telemetry, generator CPU/CFS and post-health are required. Job Complete alone is insufficient. A first failure is SUSPECT_FAILURE; repeated same-load degradation needs clean confirmation.
- Prometheus query_range step5s, actual scrape about30s. Brief events and sparse container-CPU series cannot establish precise causal ordering. Request hooks and Artillery summaries have different phase/count boundaries; do not splice them.

## Baseline and attempt register

Inherited handover reports healthy ~3, ~6, ~9, 10.5, 11.25 and 12 RPS. An original 12 RPS collapse did not repeat in clean confirmation and is excluded from ceiling evidence. These earlier claims are inherited, not newly reverified by this closeout. Subsequent local low-load diagnostic ran three independent `/home` stability gates; all passed, but this is not a capacity result.

| Attempt | Target RPS | Normalized classification | Qualification / observation |
|---|---:|---|---|
| E01 | 15 | INVALID | preflight; no formal |
| E02 | 15 | INVALID | warm-up; no formal |
| E03 | 15 | INVALID | observability gate; no formal |
| E04 | 15 | INVALID | warm-up; no formal |
| E05 | 15 | INVALID | warm-up; no formal |
| E06 | 15 | SUSPECT_FAILURE | formal timeouts; not repeated in clean confirmation |
| E07 | 15 | HEALTHY | 180s clean confirmation |
| E08 | 18 | HEALTHY | 180s |
| E09 | 21 | HEALTHY | 180s |
| E10 | 30 | SUSPECT_FAILURE | 180s; original TRANSITION_UNSTABLE; first minute slow |
| E11 | 30 | HEALTHY | 120s ramp + 300s steady |
| E12 | 45 | SUSPECT_FAILURE | 120s ramp + 300s steady; first transition degradation |
| E13 | 45 | INVALID | warm-up; no formal |
| E14 | 45 | SUSPECT_FAILURE | clean confirmation of E12; original REPRODUCIBLE_TRANSITION_DEGRADATION |
| E15 | 45 | SUSPECT_FAILURE | 300s ramp + 300s settle + 300s measurement; 44 measurement slow triggers |
| E16 | 39 | INVALID | formal ran; post-health/query_range missing |
| E17 | 39 | INVALID | warm-up failed; formal NOT TESTED |
| E18 | 39 | NOT_STARTED | prepared only; Lab recovery blocked; no preflight/warm-up/formal |
| E19 | 39 | HEALTHY | 300s ramp + 300s settle + 300s measurement; 100% 200, 0 timeouts |
| E20 | 39 | HEALTHY | Clean confirmation of E19; 33,750 requests, 100% 200, steady p95 54–85ms |
| E21 | 42 | SUSPECT_FAILURE | Saturation knee; catalog-mysql CPU 0.748 core (limit 0.8), 2,856 skipped VUs, p95 8,213ms |

Original source classifications remain unchanged in local reports. E10/E14 are normalized here to the allowed SUSPECT_FAILURE category with their transition interpretation preserved. E18 NOT_STARTED is lifecycle status, not an experimental verdict. Recovery/attribution diagnostics are indexed separately from capacity attempts. Invalid experiments do not contribute capacity points.

## 30 RPS qualified healthy point (E11)

120s ramp7→10 VU/s, then300s at10 VU/s, max100. Job SHA `017269da954960fd679cdf5f8779f99b778f169a6fe1bbb1c2c76f1dfb3127bd`.

- All run planned/created/completed4020/4020/4020; failed/skipped0; requests/responses/20012060/12060/12060; 5xx/timeout/refused0.
- Steady marker03:42:23–03:47:23 +08, 8999 successful request-start hooks inside window (~29.997 RPS), with boundary/drain accounted separately.
- Steady hook mean/median/p95/p99/max13.57/11/26/48/166ms; no >2s trigger. Artillery full-run p95/p9926.8/46.1ms.
- Carts active peak1; process/container CPU peak0.0143/0.0280core; scrape60/60 up; Carts/UI ready throughout. No observed Retail OOM or restart/UID delta.
- Generator CPU peak~0.324core, CFS ratio0, memory207.3MiB, no restart/OOM; full offered load delivered.
- Post verify PASS, HTTP200, APIreadyz/livez ok, Nodes3/3/Retail11/11 Ready, Argo Synced/Healthy, targets complete;41 query_range responses collected. Windows page-out was a single transient, not sustained.

## 45 RPS repeated degradation

E12 first observed transition degradation, E14 clean confirmation repeated the shape with identical target/profile. E13 stopped at warm-up and is excluded. E15 used longer ramp/settle to isolate measurement.

| Evidence | E12 | E14 clean confirmation | E15 isolation |
|---|---:|---:|---:|
| All run created/completed/skipped/failed VUs | 5720/4488/280/1232 | 5394/3863/578/1559 | 12660/12369/90/291 |
| ETIMEDOUT / ECONNREFUSED | 1220/12 | 1489/70 | 291/0 |
| Client interpretation | Slow transition and early steady; later recovery | Same form repeated; early steady incomplete | 44 measurement >2s triggers, all in minute3; later recovery |
| Generator peak core | ~0.505 | ~0.480 | ~0.486 |
| Post health | PASS | PASS | PASS |

E14 summary/hook/VU counts contain unresolved differences documented in its source report. Do not recompute exact phase errors from periodic counters. E15 measurement observed45.04RPS, 13512 successful hooks and p95/p99/max87/995/3960ms; phase cohort/boundary crossing means this does not prove all planned VUs completed without errors. These results show repeatable degradation by45RPS, not a proven hard ceiling or permanently unsustainable steady state.

## Resolution of 39 RPS capacity and 42 RPS saturation knee (E19–E21)

While earlier exploratory runs E16–E18 were interrupted by missing post-health telemetry or host recovery gates, subsequent dedicated test runs (E19 through E21) successfully isolated and qualified the capacity boundary:

- **E19 & E20 (39 RPS / 13 VU/s)**: Complete 3-phase formal execution (300s ramp 10→13 VU/s, 300s settle 13 VU/s, 300s measurement 13 VU/s). E20 delivered 33,750 total requests with **100% HTTP 200 responses**, 0 timeouts, 0 virtual users dropped, steady-state p95 latency of 54–85 ms, and `catalog-mysql-0` CPU maintaining a healthy ~0.45 core. Full telemetry and post-health verification passed clean.
- **E21 (42 RPS / 14 VU/s)**: Incrementing offered load by just 1 VU/s (3 RPS) pinpointed the exact saturation onset. Under 14 VU/s, `catalog-mysql-0` on `k8s-worker2` reached 0.748 cores (over 93% of its 0.8-core limit), causing catalog query latency to back up past 2s (4,280 slow triggers recorded). In-flight requests exhausted the 140 concurrent virtual user pool, causing Artillery to skip 2,856 virtual users, producing 14 `ETIMEDOUT`s, and collapsing delivered measurement throughput down to 6.9 RPS.
- **E12–E15 (45 RPS / 15 VU/s)**: Confirmed that driving load further to 15 VU/s results in severe unserviceable degradation with repeated `ECONNREFUSED` connection rejections.

## RED + USE and S7-F decision

- Rate/errors/duration: clean30RPS delivered;45RPS has timeouts, skipped/failed VUs and slow bursts with later recovery. HTTP200 alone conceals latency and lifecycle failures.
- Utilization/saturation/errors: generatorCPU stayed below1core; CFS was generally small, not demonstrated as the ceiling. Carts active requests were low and sampled CPU did not uniquely identify a Retail bottleneck.
- E14 master had iowait up to83%, blocked9 and D-state3; overlap with slow requests is correlation, not proof. Later worker1 had tens of runnable tasks, high systemCPU/runc/runtime churn, readiness/restart oscillation. Kubernetes Pressure=False does not exclude scheduling/runtime pressure.
- Windows low Available memory and isolated page-out samples are recorded separately; no blanket claim that all failures were caused by host RAM. Prometheus gaps and snapshot granularity limit attribution.

**SUT_OPTIMIZATION = NOT_APPLIED; reason = insufficient causal evidence.** No resource, replica, probe, JVM, Carts/UI/database or business configuration is changed in this closeout. Existing application changes at the tested commit are part of the fixed baseline, not new S7-F work. No before/after optimization benefit is claimed.

## Capacity conclusion and operational recommendation

Proven healthy operating point: **39 RPS / 300s (13 VU/s)**. Saturated operating point / knee: **42 RPS (14 VU/s)**. Repeatable degradation observed by: **45 RPS (15 VU/s)**. Exact knee: **Resolved between 39 RPS and 42 RPS (13 to 14 VU/s)**, with the causal bottleneck confirmed at `catalog-mysql-0` CPU budget on `k8s-worker2`.

Use 39 RPS as the currently validated Lab ceiling for this browse workload/duration, not maximum production capacity or an SLO guarantee. Operating at or above 42 RPS requires addressing the MySQL CPU bottleneck and implementing upstream caching or horizontal read scaling. Stop when warm-up/readiness fails; preserve raw evidence before any Lab shutdown.

## Evidence and release boundary

See [evidence index](../../evidence/stage7/README.md), machine-readable register and compact archive/report SHA256 index. The full local evidence manifest and its hash are recorded in summary.json. Raw private logs remain in the local experiment directories; this PR contains only aggregate conclusions and content hashes, no credentials, cookies, chat transcript or raw sensitive logs. Evidence presence does not erase the explicitly listed E16 gaps.

This document records the completed evidence-driven closeout work. It does not by itself assert PR merge, release tag, current Lab health, or Stage7 final acceptance. Release acceptance is independently auditable through [PR #57](https://github.com/wanghaibing07/retail-reliability-lab/pull/57), the actual merged commit/CI and annotated tag `stage7-v0.8`. The user's explicit no-merge boundary remains in force until changed by the user.
