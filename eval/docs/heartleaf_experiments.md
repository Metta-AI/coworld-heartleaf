# Running configurable Heartleaf experiments

`eval/tools/heartleaf_eval_experiment.py` is the canonical runner for **uploaded,
reviewed soul/model cohorts**. It freezes experimental parameters, submits bounded
private experience requests, resumes existing requests, collects raw evidence,
and exports versioned JSON and CSV. It has no dependency on the dated operator
scripts in `tmp/heartleaf-eval/`.

The existing `eval/tools/heartleaf_eval.py prepare` command creates soul/model variants.
Source extraction and certification of a new game revision remain prerequisites
described in the [evaluation runbook](heartleaf_eval.md). Prepared player variants
can be built and privately uploaded with
`eval/tools/heartleaf_eval_players.py --batch PATH/batch.json`; the uploader retains intents/receipts, verifies private image
readback, and reuses identical previously uploaded soul/model variants.
The experiment runner itself does not publish images or change backend settings.

For deadline-sensitive studies, use a certified eval runtime with
`HEARTLEAF_TIMEOUT_AS_WAIT=true`. A client timeout consumes that decision as a wait
action instead of retrying the same turn while the village pauses. The error stays
in the log and `timeout_wait_actions` counts these missed turns separately from
model-produced actions. The default runtime keeps its existing retry behavior;
other transport errors still retry. The runtime version and manifest freeze this
choice for the entire experiment.

The stricter `HEARTLEAF_UNUSABLE_AS_WAIT=true` policy consumes every unusable
response, including low-token malformed answers, empty answers, token-limited
answers (even partially valid ones), rejected actions, and HTTP failures. It never
retries that decision. The batch pins `unusable_as_wait: true`, and the runtime
enforces the configured client timeout without model-family timeout extensions.
Existing normal-runtime retry behavior remains available when this mode is off.

Failure events retain the exact received response body/text, reason, stop reason,
usage, HTTP status, model, seat/tag, pod, and request/response timestamps.
`platform_call_id` comes from the existing `X-Softmax-Llm-Call-Id` response header;
`provider_request_id` is retained when available. If no response headers arrive,
the call ID remains empty: use the job/slot/start time for later reconciliation.
The exporter writes these records to `failures.json` and `failures.csv`, including
the full hosted job ID, for joining to platform telemetry. This does not install
or configure a new PostHog or Datadog ingestion pipeline.

See [duration bounds](heartleaf_eval_timing.md) before changing episode limits or
conversation cadence.

## Environment

Run from the repository root using the isolated project environment:

```sh
uv venv --python 3.12 tmp/heartleaf-eval-venv
uv pip install --python tmp/heartleaf-eval-venv/bin/python \
  -r eval/requirements.txt
```

For an existing environment, skip `uv venv`. Before hosted work, fetch/prune the
repository and verify the checkout against its intended base without discarding
local changes. Check releases with:

```sh
uv pip list --python tmp/heartleaf-eval-venv/bin/python --outdated
```

Validated September 9, 2026 against repository base
`ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`, Coworld `0.1.46`, and Softmax CLI
`0.26.32`. The frozen experiment also records actual package versions and hashes
of the runner sources, including uncommitted changes.

Live commands use the saved project-local Softmax login. Submissions additionally
read deployed routing settings through the existing `softmax-main` Kubernetes
context, namespace `observatory`, deployment `observatory-backend`. They record
only routing settings and image identities, not the deployment's secret values.
Neither identity is currently supplied by the token broker; acquiring any new
service credential must still use the broker first.

## Prepare a cohort and freeze an experiment

Use `prepare --cohort ... --models ... --base-image ...` as documented in the
runbook to change source souls or model headers. Nine or more distinct uploaded
variants are required; the standard game still has exactly nine seats. Complete
`policy_version_id`, `container_image_id`, and `image_digest` from private upload
readback in `batch.json`, and pin its separate eval Coworld ID/version/image.
The runner verifies those identities against the live API before submitting.

Copy [experiment.json](../tools/examples/experiment.json) into the
ignored batch directory and edit it. Set `public_replays_accepted` to `true` only
when that disclosure is authorized. James authorized public gameplay replays for
this study; this does not make source souls or uploaded policy images public.

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval_experiment.py configure \
  --batch tmp/heartleaf-eval/MY_BATCH/batch.json \
  --config tmp/heartleaf-eval/MY_BATCH/parameters.json \
  --name seeds-91002-v1
```

This creates `MY_BATCH/experiments/seeds-91002-v1/experiment.json`, its fingerprint,
copies of the source souls and variant build inputs, and copies of runner code.
Existing experiment directories are never overwritten. A new parameter setting
requires a new experiment name. Prepared soul bytes must still match reviewed
hashes. Uploaded policy versions are immutable UUIDs, not mutable names.

| Parameter | Meaning |
| --- | --- |
| `seeds` | Distinct simulation seeds; each receives its own full pair-covering schedule. |
| `meetings` | Minimum meetings for every unordered policy pair **per seed**. |
| `max_days`, `day_seconds` | Evaluation game duration, sent as actual game configuration overrides. |
| `canary_days`, `canary_seed` | Short screening games before evaluations. Every variant is screened unless `canary_days: 0` explicitly skips canaries. |
| `evaluation_mode` | `measurement` (default) retains model failures as experimental outcomes; `strict` additionally requires performance acceptance. |
| `max_ignored_fraction` | Rejected-action threshold for strict performance acceptance, aggregated across the game. Default zero; does not discard valid measurements. |
| `max_parallel_games` | Simultaneous hosted games (default one). Parallel execution currently requires explicit unlimited cost authorization. All canaries finish before evaluations begin. Record this when comparing latency across experiments. |
| `stop_threshold_usd` | Cumulative study spending stop, or `null` when the user explicitly removes the cost limit. |
| `cost_authorization` | The explicit authorization text required for a null spending limit. Costs are still measured and missing charges remain unknown. |
| `projected_canary_usd`, `projected_game_usd` | Conservative next-game estimates used before submission. |
| `public_replays_accepted` | Explicit record that publicly downloadable gameplay replays are acceptable. |

Unknown keys, invalid types, and nonfinite numbers are rejected. Pair scheduling
is deterministic and guarantees coverage, but does not minimize game count or
promise perfect seat balance. Coverage reports separate planned games from
completed, accepted games, and retain zero counts for unplayed pairs.

The **2,048-token cap and 20-second request deadline are runtime properties**,
not experiment-request knobs. A different cap, deadline, or model-specific
reasoning behavior requires an appropriately built and certified game revision
and corresponding verifier changes. This runner supports the current 2,048/20
contract. Do not add a JSON key and assume it changes hosted runtime behavior.

## Budget and execution

For experiments with a numeric spending limit, copy
[budget.json](../tools/examples/budget.json) into the experiment
directory. Replace every placeholder and null using reviewed accounting. Put the
supporting evidence at the relative `evidence_file` path inside that directory.
`experiment_sha256` is the value in `fingerprint.json`.

- `known_prior_usd` covers the entire Heartleaf eval study **before this
  experiment**, including setup, certification, and earlier experiments. Do not
  include this experiment's costs again.
- `unresolved_prior_items` identifies historical missing charges.
  `unresolved_reserve_usd` and `reserve_basis` record an explicit budget reserve
  for them. A reserve is never reported as measured spend.
- `authorized_limit_usd` records the actual approved limit. Editing this number
  is not permission to increase spending. The study's existing authorization
  was **$10** for the earlier pilots. On September 9 James explicitly removed
  that limit for the full nine-model/top-nine-soul study. That study records
  `stop_threshold_usd: null` and the new instruction in `cost_authorization`.
- The ledger's `observed_at` must be within 30 minutes at each new submission.
  Refresh it only after reviewing the underlying accounting evidence. Long
  experiments stop when that review becomes stale.

Before each submission, the runner takes the larger of live study-wide metered
usage and prior known costs plus this experiment's recorded costs, adds the
historical reserve and next-game projection, and stops at the lower authorized
limit. Missing costs within the current experiment stop progression until
reconciled when a numeric cap is in force. With explicitly authorized unlimited
spending, neither unresolved billing nor ledger age stops progression; both remain
visible in results. Numeric limits are soft estimate-based stops, not provider caps.

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval_experiment.py run \
  --experiment tmp/heartleaf-eval/MY_BATCH/experiments/seeds-91002-v1/experiment.json \
  --max-new-games 1
```

The default allows one new game per invocation. Increase `--max-new-games` to
execute more of the frozen schedule within the approved budget. The runner
checks canonical runtime/certification, paused or absent league seed, private
image identities, routing, active requests, acceptance, and spending before each
POST. A process lock serializes these runners across local batches. Other tools
or machines can still race with it; the hosted API does not provide a global
experiment lock.

Temporary network failures and HTTP 408/429/500/502/503/504 responses during
collection or read-only submission checks retry on the polling loop, with at least
30 seconds between passes. Artifact-download failures follow the same rule. This
applies to both single-game and concurrent execution. Authentication errors and
measurement-integrity failures still stop. A lost response after a creation POST
remains ambiguous and requires GET-only reconciliation before another submission.
The retry stays at the orchestration boundary: [HTTPX's transport retries](https://www.python-httpx.org/advanced/transports/)
cover connection establishment only, and the existing poll loop provides the
required cadence without adding a general retry dependency.

To deploy a reviewed runner fix while preserving a study's parameters and request
identities, stop its local runner and archive the new implementation:

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval_experiment.py revise-runner \
  --experiment tmp/heartleaf-eval/MY_BATCH/experiments/seeds-91002-v1/experiment.json \
  --reason 'Describe the reviewed fix and its validation'
```

This preserves the original experiment and submission notes, copies the revised
code into `runner-revisions/`, records the old/new hashes and reason, and pins new
submissions to that revision. Collection records its actual code hashes. Resume
with `run` afterward; already attached requests are collected, never reposted.

Canaries precede evaluations. In the default `measurement` mode, timeouts,
upstream failures, truncations, parse failures, and rejected actions are valid
performance outcomes. They do not discard an otherwise correctly measured game
or stop the remaining schedule. Runtime/roster/model mismatches, missing gameplay
artifacts, and other measurement-integrity failures still stop progression.

A completed game can end with a model request still in flight. The collector
records `unreported_in_flight_tags` and `unreported_in_flight_calls` only when every
platform record matches a unique logged request start within one second, and the
unreplied missing record is that seat's final request. Such a
game can pass measurement validation while carrying `in_flight_at_episode_end`;
its complete cost stays null. A client timeout can also lack platform telemetry
after the game has consumed the turn. `unreported_timeout_tags` and
`unreported_timeout_calls` identify these requests only when a unique structured
deadline-failure event matches the seat, tag, request start time, HTTP status zero,
and client timeout error. The failure remains in the turn counts; no platform
call, provider latency, or billing is invented. These games carry
`timeout_call_telemetry_missing` and unknown complete cost. Other replied requests
with missing telemetry, earlier unreplied requests, and ambiguous timestamp
matches still fail the evidence check.
`measurement_verified` and `acceptance_verified` are separate fields: slow models
can produce valid measurements while failing strict performance acceptance.
Older frozen experiments without `evaluation_mode` retain strict behavior.

Strict mode continues to require every preceding game to pass the performance
criteria, including the rejected-action threshold. Changing a mode or threshold
requires a new frozen configuration; historical performance failures stay recorded.

`Ctrl-C` stops the local runner and leaves the hosted request recorded. Run the
same command again to collect/resume it. Use `--max-new-games 0` to resume without
creating another request. To collect all attached requests once without waiting
or submitting:

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval_experiment.py collect \
  --experiment tmp/heartleaf-eval/MY_BATCH/experiments/seeds-91002-v1/experiment.json
```

A request intent is durably written **before** POST. If the connection fails or
the process stops before receiving its ID, the runner refuses to POST again.
Locate the matching request in the hosted request list and attach its known ID:

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval_experiment.py reconcile \
  --experiment tmp/heartleaf-eval/MY_BATCH/experiments/seeds-91002-v1/experiment.json \
  --game canary-0001 --request-id xreq_KNOWN_ID
```

Reconciliation uses GET only and verifies the exact notes, runtime, configuration,
and slot-to-policy mapping against the persisted intent. A rejected, failed, or
cancelled request is retained; retries require a deliberate new experiment.

## Evidence and result contract

Each collection creates a new immutable snapshot under `games/GAME/snapshot-ID/`:

- Realized request/episode details, every job attempt, routing metadata, and
  per-call IDs, requested canonical model, upstream provider, outcomes, latency,
  finish reason, token counts, and billing reconciliation.
- Downloaded logs, results, and replay bytes, or explicit artifact fetch errors.
- A versioned normalized summary with observed scores, source and transformed
  soul hashes, policy identities, runtime/configuration, and acceptance failures.

`games/GAME/latest.json` points to the last fully written snapshot. Interrupted
collections can leave an unreferenced partial directory; previous complete
snapshots remain usable. Subsequent reads verify the summary and raw evidence
hashes. Recollection handles late accounting and artifact availability without
rewriting previous observations. Raw full provider request/response bodies are
not fetched automatically; call IDs allow separate investigation when needed.

Exports live under `results/export-ID/`. `results/latest.json` selects one
consistent generation containing:

| File | Contents |
| --- | --- |
| `episodes.json`, `episodes.csv` | One record per realized episode; JSON includes detailed seat/model records. |
| `seats.json`, `seats.csv` | One row per seat with soul/model identity, score, action, latency, token, and cost measurements. |
| `models.json`, `models.csv` | One row per requested model per episode; latency percentiles calculated from calls, not averaged seat percentiles. |
| `manifest.json` | SHA-256 hashes of each exported file and generation time. |

JSON is authoritative: nested measurements contain `value`, `known`, and `missing`.
If any observation is missing, `value` is null; `known` is only the sum of available
values. CSV uses empty cells for null scalar values and JSON for nested values.
Do not coerce either into zero. `known_cost_usd` is not a complete cost claim.
Unreconciled billing keeps `cost_usd` null even if a provisional amount exists.

The SQL API silently caps responses at 1,000 rows. Call collection uses ordered
pagination; unexpected caps in other queries stop collection. Duplicate call IDs
are rejected instead of multiplying costs. Final-attempt call counts must match
logged requests for every seat before accounting can be considered complete.
Each snapshot is a timed observation, not a transaction across the telemetry and
artifact systems; recollect after late ingestion.

Each seat has an `outcome` summary: `request_rejected`, `deadline_exceeded`, `upstream_error`,
`truncated_response`, `invalid_response`, `invalid_action`, `responded`, or
`no_response_observed`. This is a priority summary; the independent counters retain
all overlapping failures. `deadline_exceeded_calls` counts measured call latencies
at or above the 20-second deadline. Explicit client timeout messages are retained
separately as `client_timeout_replies`, since provider completion latency and
client observation are different. Either signal can produce the summary outcome
`deadline_exceeded`. Request rejection counts cover observed upstream HTTP
400/401/403/404 responses; diagnosing their cause requires the archived error.
A permanent rejection can abort the runtime, in which case missing full-game
results still invalidate the measurement.

`parsed_replies` counts parseable replies. `ignored_actions` counts those marked
`ignored=wait`; `applied_actions` excludes them. `at_or_over_deadline` is a latency
measurement, while `client_timeouts` counts explicit timeout messages. They are
separate signals. Requested model strings preserve `:nitro` exactly.

The results artifact supplies the terminal day and scores; both are checked
against requested duration and API scores. Replay presence, byte count, and hash
are recorded; this collector does not render or semantically validate every
replay frame. All known attempts' calls and costs are retained. The collector also
tries the job-level artifact endpoint for earlier attempts and records unavailable
files explicitly. Seat action totals refer to the final attempt. Multiple-attempt
episodes carry `retried_episode_requires_review` and cannot automatically pass
full acceptance; missing earlier logs additionally produce
`prior_attempt_actions_unavailable`.

Outputs and source evidence remain in the ignored `tmp/heartleaf-eval` tree with
private files. These are durable local records, **not an off-machine backup**.
Keep the whole experiment directory when archiving it; do not copy just the CSVs
and expect the underlying evidence to accompany them.

## Import or refresh the September 9 measurements

The old raw files can be normalized without running any games:

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval_experiment.py archive \
  --source tmp/heartleaf-eval/20260908-gemini/batch.json:eval-a \
  --source tmp/heartleaf-eval/20260909-screen1/batch.json:canary \
  --source tmp/heartleaf-eval/20260909-screen2/batch.json:canary \
  --source tmp/heartleaf-eval/20260909-screen3/batch.json:canary \
  --source tmp/heartleaf-eval/20260909-screen4/batch.json:canary \
  --output tmp/heartleaf-eval/20260909-canonical-results
```

Add `--refresh` to fetch those same requests' current metadata and artifacts into
new `archive-collections/` directories. This performs read-only API queries and
artifact downloads; it cannot submit an episode. Imported exports reference the
original batch or fresh collection paths, so retain those directories too.

The canonical collector was validated against all five actual hosted episodes:
1,201 calls, 1,002 applied actions, 181 rejected actions, $1.971310315 in known costs,
and ten calls with unresolved billing. These checks validate the collection and
export path. New configurable paid submission is covered by offline contract
checks; no new paid episode was launched to test this tooling.

```sh
tmp/heartleaf-eval-venv/bin/python -m unittest discover \
  -s eval/tests -p 'test_heartleaf_eval*.py'
```

## Minimum pair-once schedule for 81 policies

Setting `meetings: 1` with exactly 81 policies uses the standard affine plane
AG(2,9), rather than greedy packing: 90 nine-player games, every unordered pair
exactly once, and exactly ten games per policy per seed. The counting lower bound
is 3,240 pairs / 36 pairs per game = 90, so this schedule is minimal. Other cohort
sizes and meeting counts retain the existing greedy algorithm. Seat rotation is
retained but does not guarantee balanced seats. Canaries are additional.

Construction reference: [Affine planes, Discrete Mathematics lecture notes](https://www.isibang.ac.in/~d.yogesh/Course_Notes/DM1/Ch9.S6.html).
The small finite-field construction uses GF(3)[t]/(t²+1); integer arithmetic
modulo 9 would be incorrect. Tests verify all 3,240 pairs and policy participation.

To replace an unsent schedule, stop the local runner (hosted games continue),
copy its parameters with only `meetings` changed, then run:

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval_experiment.py reschedule \
  --experiment tmp/heartleaf-eval/MY_BATCH/experiments/OLD/experiment.json \
  --config once-parameters.json --name NEW
```

This creates a frozen successor, retaining original request IDs, notes, intents,
and exact seats/configuration. It refuses to drop or change any submitted game
or proceed past an ambiguous submission. Existing evidence remains in the old
experiment; the successor recollects the same request IDs. An incomplete handoff
blocks loading, preventing duplicate submissions. Resume `run` on the successor;
never run both predecessors and successors. Reports across revisions must deduplicate
by request/job ID because carried requests appear in both revisions.

## Full-game stdout capture

The hosted artifact collector requests only the last 10,000 lines per container
(`app_backend/.../job_runner/shared.py`, `capture_pod_logs`). Long Heartleaf games
can lose startup and early call evidence even when gameplay completes normally.
Missing evidence must not be interpreted as missing model responses or a valid
measurement. A completed S2 game on September 9 hit this limit and remains marked
unverified; its scores/costs are retained separately.

For the current runtime, `eval/tools/heartleaf_live_logs.py` follows game-container
stdout using the existing tournament Kubernetes identity, before pods disappear:

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_live_logs.py \
  --experiment tmp/heartleaf-eval/MY_BATCH/experiments/NAME/experiment.json \
  --output tmp/heartleaf-eval/hosted-logs
```

Repeat `--experiment` for predecessor requests. The observer never submits or
cancels games. Capture receipts identify job, pod, container, command, and process;
logs are stored by full job ID. It runs for 24 hours by default. The collector
uses matching captures, retains the original artifact as `platform-logs`, and
hashes both plus the capture receipt in the snapshot. Existing completeness and
call-count checks still apply; a disconnected or late-starting observer cannot
silently certify incomplete data. Inspect capture stderr if those checks fail.

`run --max-new-games 0` now continues collecting other existing requests after a
terminal measurement failure, retaining that failure in results. Runs authorized
to submit new games still stop on invalid measurements. The five-game S1 study
uses a drain-only predecessor followed by its own submissions.

Runtime 0.1.9 removes the stdout dependency for new eval games. With
`HEARTLEAF_EVAL_ARTIFACT=true`, the `results` artifact carries an `evaluation`
object using schema `heartleaf-eval-evidence/1`. It contains `accepted_seats`
(slot/model), `event_count`, and ordered `events` with sequence, seat, gnome,
game/wall-clock stamps, kind, and original LLM lifecycle text. Structured failure
events retain response text/body and platform/provider correlation IDs. System
prompts and ordinary conversation history are excluded. Scores and evidence are
written together at each daily score checkpoint and once more at final shutdown.

The checked-in Coworld manifest template defines the optional `evaluation`
property. A strict eval manifest enables the env flag and includes `evaluation`
in `game.results_schema.required`. Its batch sets `eval_artifact_required: true`;
scope validation checks the runtime flag. The collector verifies schema, event
count, contiguous sequence numbers, seat identities, call-count reconciliation,
and existing scores/runtime/roster checks. It reads the artifact even if stdout
is missing or truncated. A malformed present payload never falls back to stdout;
a required missing payload is a measurement failure. Original artifacts remain
hashed in immutable snapshots, and the usual failures JSON/CSV exports are unchanged.

Older runtime experiments remain on the live-capture compatibility path. Do not
silently replace their pinned runtime; record newer-runtime games separately and
retain runtime identity when comparing them. Hosted games already underway are
not cancelled by this collector change.

### Results artifact size audit (September 9)

Runtime 0.1.9's final write occurs after the score screen advances the day counter.
The collector retains that raw value as `reported_day`. For completed artifact-mode
0.1.9 games only, an expected-day-plus-one counter is interpreted as the requested
duration when the structured events' maximum played day matches that duration.
Missing, malformed, short, or overlong event evidence does not qualify for this
rollover correction. Other runtime versions retain the exact day check.

Code inspection found no results-specific byte/line truncation: BitWorld
`writeResults` writes the whole string; the hosted runner calls
`_read_game_authored_file(results_path, None)` and validates complete JSON;
`upload_data` sends the full buffer; backend completion reads the whole response;
and the eval SDK returns `response.content`. The eval schema has no maximum
length on `events` or event text. The egress relay streams tunnel chunks rather
than limiting total body size. This is not an unlimited-capacity claim: full
buffers and parsed JSON require memory, uploads/downloads have 60-second timeouts,
and backend artifact reads have a 300-second timeout. The first finished game's
full stdout was 2,026,650 bytes, of which 1,499,405 bytes were LLM lifecycle lines;
that is a useful scale reference, not a maximum-size benchmark. No large-artifact
load test was run; James requested code inspection and skipping the pending canary.

## Successive candidate cohorts

For the single start/status command, automation boundaries, and dashboard, see
[Campaign operations](heartleaf_campaign_operations.md).

`eval/tools/heartleaf_eval_campaign.py --campaign PATH` resumes a campaign directory
containing `campaign.json`. The September 9 campaign is
`tmp/heartleaf-eval/20260909-candidate-campaign`. Its baseline consists of the
existing five full games, including the recovered game-2 log and corrected
game-5 terminal day. Baseline records and source hashes are frozen alongside it.

After each five-game round, the controller removes the union of the two highest
pooled known inference-cost/score models and the two highest failure-count models.
Failure count is exactly the sum of deadline_exceeded, token_limit, empty_response,
invalid_action, and upstream_error events. It records other evidence without
silently adding categories to this selection rule. Zero-score ratios rank worst;
ties use model ID. Missing billing remains visible, and selection uses known costs
provisionally. A measurement-integrity failure stops progression.

Unseen candidates enter in frozen ascending catalog input-plus-output price order,
then model ID. Exact variants are retained, including free routes. If fewer unseen
candidates remain than vacancies, prior tested models outside the removed/current
cohort fill the last round, ordered by their most recent cost/score. Every selected
new candidate receives five full games before it counts toward coverage.

Each round uses S1, seeds 91002–91006, nine fixed seats, three concurrent games,
the existing 0.1.9 runtime, and explicitly zero canaries. Survivors keep their seats.
The controller reuses the canonical private uploader, frozen experiment config,
submission intents, readback validation, retry loop, and structured-artifact
collector. Each decision and round's request IDs/metrics are persisted. Resume the
same directory after interruption; never delete submission intents to force a retry.

The campaign now has a $1,500 **new-spend** ceiling. `spend-policy.json` excludes
round 0 and earlier experiments. `heartleaf_eval_campaign_budget.py --campaign PATH`
independently polls all new rounds' episode attempts, provider bills, and compute
charges every 30 seconds. `spend-latest.json` retains measured totals and missing
accounting counts. Each experiment's `campaign-budget.json` activates a fresh
pre-submission check that overrides its older unlimited-spend authorization.
The launch projection reserves $150 for each active and proposed game; this is
headroom, not an invoice or a guarantee against delayed billing.

Recorded new spend above $1,500 latches the policy pause. No new games launch until
James approves resumption. Already submitted games are never cancelled for budget:
the runner drains and collects them, and the monitor keeps measuring their spend.
Their final charges can therefore take the total over $1,500. A failed cost query
blocks new submissions through the ordinary runner checks; the monitor retries
HTTP failures. A paused partial round remains unfinished and cannot drive selection.

Local sidecar rate-limit rejections are recorded as `local_rate_limit_tags` and
`local_rate_limit_rejections`. They require a unique matching request and reply,
a structured HTTP 429 `ThrottlingException` identifying the sidecar limit, and
no platform call ID. These requests never reached inference and are excluded
from the expected platform-call count; they still count as `upstream_error`
failed turns. Provider throttles and other missing call records are not covered
by this exception. The raw response remains in `unusable_responses`.
