# Heartleaf evaluation duration

The game advances simulation ticks as fast as it can between model waits. The
180 simulated seconds per day are not an additional 180 wall-clock seconds.

With seven days, nine concurrent requests, a 20-second hard client deadline, and
strict unusable-as-wait behavior:

| Component | Conservative waiting budget |
| --- | ---: |
| Planning: 7 days × 12 hourly rounds × 20 seconds | 1,680 seconds (28 minutes) |
| Conversation: 7 × 180 possible four-minute slots × 3 seconds | 3,780 seconds (63 minutes) |
| Day rollover: up to 20 seconds for old in-flight calls to release capacity at each of 6 boundaries | 120 seconds (2 minutes) |
| Total | 5,580 seconds (93 minutes), plus overhead |

This is a conservative bound on waits, not a prediction. Conversations do not
necessarily exist in every slot, and an occupied participant skips planning
requests. Busy speakers also skip conversation requests. Calls across agents and
separate conversation circles run concurrently; do not multiply the wait budget
by nine. The estimate assumes the default nine-request capacity and no retries.
Startup, the 24 Hz polling loop, CPU time, and artifact upload are additional.

One 20-second planner can hold each planning round for 20 seconds even when its
eight opponents respond quickly. Increasing concurrency between games improves
study throughput, but does not shorten that individual game's dependency chain.

## Executable check

`eval/tools/heartleaf_eval_duration.nim` runs the real brain scheduler and simulation
with a virtual clock and scripted responses. It makes no network calls. From the
project's provisioned Nim environment:

```sh
nim r -d:release --path:src eval/tools/heartleaf_eval_duration.nim 7 20
```

Arguments are days and simulated response latency in seconds. With wait actions
and no conversations, all three cases finish in exactly 1,680 virtual seconds
with 756 calls: one slow agent, nine slow agents, and nine agents producing
unusable text. The last case proves that failed answers do not add retries.
`DURATION_RESULT` lines contain measurements; `DURATION_BOUND` contains the
separate conservative calculation including conversations. Raw September 9
output is under `tmp/heartleaf-eval/20260909-runtime-unusable-wait/`.

## Hosted configuration

The strict eval manifest uses a 100-minute episode limit to cover this waiting
budget with overhead. The per-call deadline stays 20 seconds and the output cap
stays 2,048 tokens. A larger episode envelope does not grant a model more time per
decision. The original 40-minute manifest was not sized from this cohort's full
seven-day waiting budget.
