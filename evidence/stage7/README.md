# Stage 7 evidence index

- `summary.json`: fixed identity, capacity envelope, no-change decision and lifecycle statuses.
- `experiment-register.csv`: all18 attempts, normalized results, source-report and Job hashes.
- `SHA256SUMS-local-evidence.txt`: compact archive/report hashes relative to the execution workspace `outputs/`. The full57,318-file local manifest is retained in `stage7-closeout-delivery/` outside Git; its SHA256 is pinned in summary.json. Source-snapshot copies are excluded.

Raw archive location: the current task workspace `outputs/S7-.../` directories. All Artillery logs, telemetry JSON, host snapshots, pre/post-health and original reports stay local, outside versioned source. Request the matching local directory or archive when auditing a hash; this index is not a claim that raw data is hosted by GitHub. No raw private log or chat transcript is included in this directory.

Primary qualified point: E11 (`S7-30RPS-RAMP-20261006-s7e7-attempt11`), including `remote-artifacts-complete/s7e7-attempt11-raw-evidence.tar.gz`.
Repeated degradation: E12/E14; longer isolation E15.
Excluded from capacity qualification: E16 missing post/query_range; E17 warm-up failure; E18 never started. Historical lower-load3–12RPS is inherited from the approved handover, with no new local qualification asserted.

The manifest preserves files as captured, including diagnostic and partial evidence. A listed file does not imply a successful or valid experiment. S7-E is closed with an environment limitation; final release status remains pending PR/CI/authorized merge/tag.
