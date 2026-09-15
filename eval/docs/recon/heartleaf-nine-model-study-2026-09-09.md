# Nine-model, top-nine-soul study — September 9, 2026

## Durable evidence runtime and fifth game

Eval 0.1.9 writes complete lifecycle evidence into the results JSON, independent
of stdout retention. New Coworld: `cow_cad66f79-b6f0-4395-bcb9-554606824df4`;
image `sha256:1d8fdd4a4d0418f19e02aae715d3e0c051ff30078fb4021f4d4495ab36e7d740`.
105 Python tests and the Linux Nim suite pass. Local and hosted smoke
certification pass; the hosted results artifact was downloaded and all 441
events/nine accepted seats were validated. Full hosted certification passed and 0.1.9 is canonical; the readback is retained
in `tmp/heartleaf-eval/20260909-durable-artifact/status.json`.

The first four S1 study games (seeds 91002–91005) were already submitted on 0.1.8
and are preserved. The final seed 91006 is configured under
`tmp/heartleaf-eval/20260909-one-soul-nine-models/experiments/s1-artifact-final/experiment.json`,
with `eval_artifact_required: true`. Its supervisor drains the existing four games,
then runs the fifth seven-day game directly. James explicitly removed the pending
validation canary; its original unsubmitted configuration is archived in
`configuration-revisions/before-canary-removal/`. This is five full study games.
No hosted requests were cancelled. Analyses must identify the instrumentation
version difference; token cap, deadline, models, soul, and gameplay are unchanged.
Original source snapshots, certification artifacts, and verification records are
under `tmp/heartleaf-eval/20260909-durable-artifact/`.


## Current scope: one soul, nine models, five games

James reduced the study to S1 (`nishadiota-heartleaf-tablekeeper:v2`) across all
nine models, playing five seven-day games on seeds 91002–91006. The active
configuration is `tmp/heartleaf-eval/20260909-one-soul-nine-models/experiments/s1-five-games/experiment.json`.
The S1 canary and first full-game request are inherited unchanged. Only four new
full games will be submitted. All three original full games remain running; the
other two will be collected as separate historical data. The 90-game schedule is
now draining with zero new submissions, followed automatically by the smaller
study. Its supervisor and child stage are recorded in `current-launch.json` and
`stage.json` in the new experiment directory. The earlier scope descriptions below
are historical, not active submission plans.


## Pair-once successor

The active experiment is now `frontier-nine-once-v5`, under the same batch's
`experiments/` directory. James requested minimum coverage with each pair meeting
once. The affine-plane schedule has exactly 90 full seven-day games and ten full
games per policy, plus the nine existing canaries. All twelve existing XP request
IDs (nine completed canaries and three running full games) were carried over with
identical rosters, seats, runtime, and settings. No hosted request was cancelled.
The old local runner was stopped; the successor continues collection and will
submit the remaining 87 games with concurrency three. Source and runner hashes
are frozen in the successor. Python validation: 102 tests passed.

The rough canary-based full-game cost estimate is $1,773 for 90 games, plus $25
for the canaries and approximately $177 recorded on older runtime revisions:
about $1,975 total before unrecorded overhead/final billing. This extrapolates
one-day calls linearly and is not a seven-day measured cost forecast. Do not sum
v4 and v5 totals: the carried request IDs refer to the same billable work.

The status sections below describe earlier snapshots.


Status at 2026-09-09 21:56 UTC: the revised runtime 0.1.8 is certified and
`frontier-nine-v4` is running its first three hosted canaries. The full schedule
is nine canaries followed by 230 seven-day games, with three games concurrent.
The prior v3 runner was stopped and its three active full-game requests cancelled
because unusable responses still retried. Those attempts and their evidence remain
intact; their results are not carried into the new runtime's study.

The active frozen experiment is
`tmp/heartleaf-eval/20260909-top9-nine-frontier-models/experiments/frontier-nine-v4/experiment.json`.
Its `current-launch.json` identifies the detached process and file-backed log.

## Strict unusable-response revision

Eval 0.1.8 enables `HEARTLEAF_UNUSABLE_AS_WAIT=true`. Timeouts, token-limit
responses (including valid-looking truncated text), empty or malformed responses,
invalid actions, and request errors consume a turn as a wait without retrying.
The hard client deadline is 20 seconds for every model family, with a 2,048-token
output cap. Normal Heartleaf retains its existing behavior when this mode is off.

Each unusable outcome records the raw response body and text when received,
stop reason, usage, error, timing, slot, local request tag, and platform/provider
request IDs when available. Collection adds the full hosted job ID and exports
`failures.json` and `failures.csv`. The platform ID comes from the existing
`X-Softmax-Llm-Call-Id` response header. A timeout before response headers cannot
supply that ID or a response; job, slot, and request-start time remain available
for later correlation. This change does not create a new PostHog/Datadog pipeline.

A live sample across the first three v4 canaries contains 26 failure events:
18 deadlines, six invalid actions, and two token-limit outcomes. All eight
received unusable responses retain both a response body and platform call ID.
All seven sampled IDs checked against collected platform calls matched exactly.
The snapshot is saved in `hosted-failure-verification.json` under the runtime
evidence directory below; this is an early sample, not final study totals.

The real scheduler with a virtual clock measures 28 minutes for seven days of
planning when one or all nine agents take 20 seconds per call. The same test with
unusable answers also finishes in 28 minutes with 756 calls, showing no retry
inflation. A conservative budget including every possible conversation hold and
day-rollover capacity wait is 93 minutes plus overhead. The eval manifest now
allows 100 minutes per episode; the per-call deadline remains 20 seconds.
See [the timing calculation and executable check](../heartleaf_eval_timing.md).

- Coworld: `cow_dde280a0-4a33-45f6-b1ad-2cbaaa82c6fe` (eval 0.1.8).
- Image: `sha256:a80d64b17892d0332f4bb141510a480228028ff4cc7eac551219dddd5c45005f`.
- Local certification: ten steps passed; hosted smoke and full certification passed.
- Validation: 100 Python tests, Linux Nim unit suite, focused lint, and diff checks passed.
- Source base: `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`, matching fetched `origin/master`.
- Project-local CLI releases checked: Coworld 0.1.46 and Softmax CLI 0.26.32.
- Runtime evidence and source hashes: `tmp/heartleaf-eval/20260909-runtime-unusable-wait/`.
- Original Heartleaf 0.2.7 manifest hash was unchanged after publication.

## Previous run and timeout investigation

Status at 2026-09-09 21:16 UTC: all nine canaries completed and pass measurement
validation. The runner is alive and the first three full evaluation games are
running their second hosted attempts; no full game has completed. Each first
attempt failed with `episode_timeout` after approximately 40 minutes, waiting for
results/replay artifacts. The episode wall-clock limit is now the blocker to
full-game results; repeated attempts do not address that limit. Exact hosted error
types and timestamps are saved in `hosted-retry-errors.json` in the experiment.
The current dataset has 5,297 recorded calls and $140.5326475763939 known cost,
including restarted attempts; final billing and running-game artifacts are pending.

The subsequent timeout investigation found that raising the limit alone would
miss a runtime bug. The original Heartleaf 0.2.7 manifest and eval 0.1.7 both set
`episode_timeout_minutes: 40`; it was inherited, not measured for this cohort.
In eval-0003's first attempt, GLM produced 27 length-limited responses at the
2,048-token output cap. Empty visible text was classified as a transient error,
which still retries with backoff despite timeout-as-wait being enabled. At day 2,
11:00am, 24 GLM replies span 1,873.7 seconds without game-clock progress; the
associated retry messages schedule 1,731.8 seconds of backoff. The last scheduled
wait need not have elapsed before termination.

Eval-0002's first attempt progressed to day 5 around 12:55pm after 963 requests.
Its resumed-pause messages sum to 2,393.9 seconds, against a 2,418.7-second span
of request/reply events. Thus the wall time was overwhelmingly spent waiting,
including ordinary planning/conversation holds and failed-response retries.
Heartleaf fast-forwards simulation ticks between holds. Fixing unusable-response
retry behavior and measuring the full game's call cadence are prerequisites to
choosing an appropriate episode limit. Raw logs and parsed counts are under
`timeout-investigation/`; eval-0001's downloaded artifact did not contain a unique
game-log section, so these detailed conclusions rely on attempts 2 and 3.
That superseded experiment is
`tmp/heartleaf-eval/20260909-top9-nine-frontier-models/experiments/frontier-nine-v3/experiment.json`.
Its `current-launch.json` records the current background process and log filename.
Earlier launch records and logs remain intact.
Earlier interrupted trials remain under sibling `frontier-nine-v1` and
`frontier-nine-v2` directories.

## Design

Cross the previously frozen top-nine ranked source souls with nine models:

| Key | Canonical model | Purpose |
| --- | --- | --- |
| M01 | anthropic/claude-haiku-4.5 | Fast established control from the pilot |
| M02 | anthropic/claude-fable-5.1 | Current Anthropic frontier model |
| M03 | openai/gpt-6-astra | Current OpenAI frontier model |
| M04 | openai/gpt-5.6-luna | Smaller OpenAI comparison |
| M05 | google/gemini-3.8-flash | Current Google Flash comparison |
| M06 | deepseek/deepseek-v4-pro-0813 | Dated DeepSeek Pro model |
| M07 | qwen/qwen3.8-max-0902 | Dated Qwen Max model |
| M08 | moonshotai/kimi-k3 | Moonshot general-purpose model |
| M09 | z-ai/glm-5.3 | Z.ai general-purpose model |

Selection is a deliberately broad initial cohort, not a claim that these are the
nine best models for Heartleaf. All IDs were verified in the live
[OpenRouter catalog](https://openrouter.ai/api/v1/models). The full catalog,
selected metadata, and rationale are saved in
`tmp/heartleaf-eval/20260909-nine-model-study-inputs/`.

The source cohort preserves the original reviewed ranking and provenance; it is
not silently refreshed to a new leaderboard snapshot. Ranks 7 and 9 have identical
soul bodies but remain distinct source-policy identities: nine ranked files,
eight unique bodies. Analyses must not treat those as nine independent prompts.

There are 81 policy variants, 3,240 unordered policy pairs, nine one-day canaries,
and 230 seven-day evaluation games. Every pair meets at least twice at seed 91002.
The deterministic greedy schedule guarantees coverage, not minimal game count or
perfect seat balance. The output cap remains 2,048 tokens and the client deadline
remains 20 seconds. Three hosted games may run concurrently; comparisons with
single-game pilots must account for that load difference.

## Outcomes and authorization

James explicitly requested that excessive response latency be a valid test
outcome and authorized the full study without the old cost limit. The frozen
configuration uses `evaluation_mode: measurement`, `stop_threshold_usd: null`,
and records his instruction in `cost_authorization`. This removes the operator's
cost stop for this study; it does not change platform quotas or access controls.
Public gameplay replays remain authorized. Uploaded player images remain private.

Performance failures remain in the dataset. Measurement validity is separate from
strict performance acceptance. In particular, timeout, upstream-error, truncation,
parse-error, and rejected-action counts remain visible even when the game's score
is zero. Missing billing stays null and is recollected later; it is never replaced
with zero. Wrong models/rosters/runtime or missing gameplay evidence still require
investigation before progression.

## Compatibility revision and validation

The first three canaries on runtime 0.1.5 exposed a request-shaping bug: Fable
5.1, GPT-6 Astra, and GPT-5.6 Luna reject `temperature`, but Heartleaf sent it for
those OpenRouter IDs. The model catalog and captured effective requests confirmed
the mismatch. Repeated 404 parameter-filter responses triggered Heartleaf's
permanent player-failure path, aborting the games. Those attempts remain recorded
under `frontier-nine-v1`; they do not count toward full-study coverage.

The fix recognizes those OpenRouter families and omits sampling without changing
the 2,048-token budget or 20-second deadline. Eval-only runtime 0.1.6 is certified:

- Coworld: `cow_3c7724dd-f4bc-49d6-b246-08c458143589`
- Image digest: `sha256:cc17830cf1858fb8b51c404a689886e6ba33b250bedf9980c72dd146d12ff1f1`
- Local certification: all ten steps passed.
- Hosted smoke and full certification: passed.
- Linux Nim unit suite: passed in the project Docker build environment.
- Python runner contracts: 91 passed.

The local Nim invocation could not find BitWorld in the checkout; the Linux tests
used the real Dockerfile with locked dependencies. The released Coworld 0.1.46
CLI also rejected the backend's explicit `player_runtime: platform-hosted` field.
The generated manifest omits that field, preserving the documented default
platform-hosted semantics. No toolchain guard or certification check was disabled.
Source hashes, both certification records, and manifest-normalization evidence are
in `tmp/heartleaf-eval/20260909-runtime-parameters/`. Original Heartleaf manifest
hash readback was unchanged after publication.

### Timeout behavior revision

The 0.1.6 canaries confirmed all nine model routes worked, but live game logs
exposed an evaluation problem: timeouts retried the same turn with increasing
backoff while the village waited. One GLM turn timed out eight consecutive times.
The three canaries were cancelled with durable intents and readbacks, and their
raw evidence was collected under `frontier-nine-v2`.

Runtime 0.1.7 enables `HEARTLEAF_TIMEOUT_AS_WAIT=true`. A client deadline miss now
consumes that decision as a wait action and allows play to proceed. Its timeout
and `timeout_wait_actions` remain distinct from successful model actions. Normal
Heartleaf defaults to retries, and other transport errors retain retries in both
modes. The runner checks the manifest setting against the frozen batch before
submission, and exports the setting with results.

The 92 Python contracts pass, including timeout attribution and runtime-setting
mismatch rejection. The Linux Nim suite passes, including paired retry/wait
behavior and preservation of retries for non-timeout transport errors. Focused
Python lint and local certification pass. Runtime evidence is under
`tmp/heartleaf-eval/20260909-runtime-timeout-wait/`.

Hosted smoke and full certification also passed. The pinned runtime is
`cow_00a0345f-6d12-457d-8a89-8a2ddc9851cf` with image digest
`sha256:bae95a4a4c922950cffa3d66b2fc425bf23314b938fe8c6a44bfa41cf5a1a6a0`.
Canonical eval resolution and the enabled timeout setting were verified before
restart. Original Heartleaf's manifest hash remains unchanged. The environment
uses Coworld 0.1.46 and softmax-cli 0.26.32; the source baseline is
`ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`, with changed runtime source hashes
recorded beside the manifest.

The restarted first canary has demonstrated the new behavior with real calls:
two client timeouts each produced `llm timeout action=wait`, and subsequent game
progress appeared in the live log. The partial log, hash, and observation are
saved as `hosted-canary1-live.log` and `hosted-timeout-verification.json` beside
the runtime manifest. This confirms live timeout handling; it is not a completed
game or a full-study result.

## Latest progress

The six completed canaries contain 1,250 recorded platform calls, 104 explicit
client timeouts, and 104 matching timeout wait actions. Known cost for this v3 run
is $19.2469727832; canary 6's complete cost remains unresolved. These figures exclude
earlier interrupted compatibility trials and certification costs.

Canary 6 logs 13 Qwen requests but has 12 platform call records. Its final request,
`tag=6:13`, has no reply in the game log. The 12 platform records each match a
unique logged request start within one second; the only unmatched request is that
final unreplied request. It is now recorded as `in_flight_at_episode_end`, with
unknown complete cost, rather than an unexplained telemetry gap. The original
refreshed evidence is under
`games/canary-0006/snapshot-86fd463a98b74539ad6f59f591d7f34c/`. No replacement game
was submitted.

The reviewed runner revision is
`runner-revisions/aee6801d20dc4524bfa052c699237d22/revision.json`. It preserves
the frozen experiment and all attached request identities. Temporary connection,
read-timeout, server, and artifact-download errors retry through the polling loop.
Ambiguous creation POSTs still require reconciliation to avoid duplicate games.
All 98 Python contracts and focused lint pass, including failure/recovery tests
and checks that replied requests with missing telemetry remain invalid.
