# Heartleaf evaluation operator runbook

For new configurable runs, start with the
[canonical experiment runner](heartleaf_experiments.md). It supports arbitrary
uploaded soul/model cohorts, seed schedules, resumable serial execution, and
versioned evidence/JSON/CSV exports. This document retains the original milestone
procedure and the source extraction, build, upload, and runtime prerequisites.

This local driver prepares three ranked souls crossed with Haiku 4.5,
Qwen3.5-35B-A3B, and GPT-OSS-120B. The nine resulting policies fill every
seat of a separate `heartleaf-eval` Coworld. It does not modify the backend,
create a scheduler, or make the Coworld itself private.

See the [approved milestone design](designs/heartleaf-eval-milestone-1.md)
for the experiment and its acceptance gates. Preparation is not evidence
that a hosted evaluation has succeeded.

The [September 8 execution status](designs/heartleaf-eval-implementation-status-2026-09-08.md)
records the certified world and uploaded policies. Its first private league-less
canary was cancelled after an existing response-translation failure. The backend
owner subsequently deployed the fix in PR 21950. James authorized routine paid
run attempts within this milestone without another approval; the existing
scope, acceptance gates, and $10 soft stop still apply. A distinct replacement
canary is recorded in `tmp/heartleaf-eval/20260908-retry1/`; never overwrite or
replay the cancelled batch's submission intent.

## Hosting choice: private league, or explicitly approved league-less XP

The standard seeded Coworld league is reconciled back to public. Setting
its visibility to private once, pausing rounds, or disabling its seed does
not establish the required private, enabled XP target. To use private-league
mode, identify a supported existing-platform setup with the platform owner
and read its state back after reconciliation before any extracted-policy
upload or paid evaluation.

The league must resolve to the new Coworld, remain private and enabled, and
have automatic rounds paused. Do not change backend code, database rows,
permissions, infrastructure, or reconciliation. Do not reuse an unrelated
league. This is a limitation of this seeded setup, not proof that private or
unlisted leagues no longer exist. Browse visibility, access restrictions,
and supported creation are separate questions.

James approved league-less private XP requests on September 8, 2026 if no
supported private-league setup can be established. In that fallback, set
`submission_mode: "leagueless"`, leave `league_id` null, and record the new
world's public seeded league as `seed_league_id`, if one exists. Keep that seed
league's automatic rounds paused, but never target it or attach the cohort to
it. If there is no seed, leave `seed_league_id` null; fresh authorized seed
catalog readback must establish its absence. Do not create a seed solely for
the evaluation.
Requests select the new Coworld directly and remain private. Do not change
the original Heartleaf world or league. The fallback does not claim league
privacy or hide the new Coworld's metadata.

World metadata and shared game/viewer assets are intentionally visible.
Extracted souls must not appear in public manifest player entries or public
submitted-image URIs. Use legitimate credentials to check team access and
ordinary non-team denial. If role testing is unavailable, record that gap
instead of claiming privacy verification.

## Local environment and checks

Run from this repository, never James's primary Metta checkout. Refresh the
repository and check current CLI releases before relying on local behavior;
preserve unrelated changes. The requirements file pins the versions checked
for this implementation. Update pins deliberately if release checks require
it, and record the versions actually used.

```sh
uv venv tmp/heartleaf-eval-venv
uv pip install --python tmp/heartleaf-eval-venv/bin/python -r eval/requirements.txt
tmp/heartleaf-eval-venv/bin/python -m unittest discover -s eval/tests -p test_heartleaf_eval.py
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval.py --help
```

Python tests are offline contract checks, not hosted acceptance. Rebuilding
the uploader uses the repository's pinned Nim dependencies and CI setup;
see [Developing](../README.md#developing). Run `nim r tests/tests.nim`; if
building the game, also run
`HEARTLEAF_SERVER=out/heartleaf nim r tests/integration.nim`.

## Freeze the inputs

Snapshot the top three eligible policy versions from the selected Heartleaf
leaderboard. Record the league/division, ranking metric, time, ranks 1–3,
policy UUIDs, and immutable image digests. A historical extraction example
is not a substitute for the current top three. If extraction fails for a
selected policy, report it without replacing the policy with a lower rank.

Use AWS CLI and Docker with the existing authorized identity. Authenticate
with short-lived credentials and a temporary Docker config, pull the
digest-pinned Linux amd64 image, create a stopped container, inspect its
configured soul path, and copy the file without starting the container.
Remove only that temporary stopped container and credential directory. Do
not execute submitted code, print signed download URLs, or expose tokens.

Keep source souls, evidence, batch JSON, builds, logs, and results in the
ignored `tmp/heartleaf-eval/<batch>/` directory. Never commit these files.
Preserve provenance and body hashes, including a note if two ranked policies
have identical bodies. The generated triplets must preserve raw body bytes;
only the model header changes.

Pin the source Coworld manifest, game image digest, and static viewer bundle
digest. The deployed viewer is a bundle, not a container image. Prepare
a renamed `heartleaf-eval` manifest with independent version/ownership, the
standard nine-seat `league` variant, and `BEDROCK_MAX_TOKENS=2048` for all
models. This token cap is the declared exception to unchanged game settings.
Keep eval souls out of bundled player entries. Do not send an unsupported
Coworld `public` field.

The September 8 reasoning-limited revision is a second declared exception:
the eval game sends `additionalModelRequestFields.thinking.type=disabled`
for OpenRouter `qwen/qwen3.5-*` models. The shared 2048 output cap and
20-second default deadline remain unchanged. A tested GPT-OSS low-effort
revision was withdrawn: `output_config.effort=low` excluded every endpoint
on the hosted Messages route. GPT-OSS settings remain unchanged.
This is a client request change,
not a backend change or a change to the original hosted Heartleaf world.
The subsequent transport revision also disables `CURLOPT_PIPEWAIT` for the
game's LLM client using the project-owned pinned Curly module. Preserve the
nine in-flight requests and 20-second deadline. The local causal regression
must pass before publishing this eval-only revision; provider-side response
delays remain a separate acceptance gate. The Gemini follow-up keeps existing
Haiku controls and GPT-OSS `:nitro` policies, replacing Qwen with
`google/gemini-2.5-flash-lite` across the same three source souls. Record this
as a new cohort and game revision, not a retry of a cancelled submission.
Record the revised digest as `eval_game_image` in a new batch, retaining
`game_provenance` as the original source. The driver verifies the explicit eval
digest when present; old unchanged-game batches still verify the source digest.
Do not claim the latency gate passed until hosted archives show the setting
and logs show usable actions without deadline failures for all nine seats.

### Prepare the frozen batch

Create a reviewed cohort JSON in the ignored working directory. The required
shape below uses placeholders, not a real extracted cohort. Repeat the source
record for ranks 2 and 3 with their own immutable policy UUIDs and provenance.
Relative `soul_path` values resolve beside the cohort JSON.

```json
{
  "reviewed": true,
  "batch_id": "heartleaf-eval-20260908",
  "captured_at": "<UTC timestamp>",
  "league_id": "<source Heartleaf league>",
  "division_id": "<source division>",
  "ranking_metric": "<metric used by the frozen leaderboard>",
  "game_provenance": {
    "coworld_id": "<original Heartleaf Coworld ID>",
    "version": "<pinned source version>",
    "game_image": "<registry/repository>@sha256:<64 lowercase hex characters>",
    "viewer_bundle": "sha256:<64 lowercase hex characters>"
  },
  "sources": [{
    "rank": 1,
    "policy_version_id": "<source policy UUID>",
    "image_id": "<submitted image ID>",
    "image_digest": "sha256:<64 lowercase hex characters>",
    "image_ref": "<registry/repository>@sha256:<same image digest>",
    "soul_path": "extracted/S1/soul.md",
    "soul_sha256": "<64 lowercase hex characters from reviewed extraction>",
    "container_soul_path": "/soul.md"
  }]
}
```

The preparation command verifies the reviewed soul hashes and validates all three sources before creating a new
batch directory. It refuses to overwrite an existing batch.

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval.py prepare \
  --cohort tmp/heartleaf-eval/input/cohort.json \
  --base-image '<uploader-registry/repository>@sha256:<64 lowercase hex characters>'
```

It writes `batch.json`, copied source souls, nine image contexts under
`variants/S1-H` through `variants/S3-G`, and `friction.md`. The target
`coworld_id`, `league_id`, variant `policy_version_id`, and `image_digest`
start unset. Fill them only from verified hosted readbacks. Preserve the
source Coworld provenance; it is not the target for requests.

For each generated context, build a distinct tag with the existing Docker
toolchain, then use the normal policy upload workflow after the privacy gate:

```sh
docker build --platform linux/amd64 \
  --tag heartleaf-eval-20260908-s1-h \
  tmp/heartleaf-eval/heartleaf-eval-20260908/variants/S1-H
```

Repeat for all nine contexts; this command is an example for one variant,
not a nine-image build command. Keep registry credentials outside the context.

## Packaging and hosted prerequisites

Build one reusable soul-player base and nine thin Linux amd64 images.
Locally certify the package with mock replies, then use `coworld run-episode`
to run all nine generated images together. Verify soul acceptance, terminal
results, and replay. A mocked run proves packaging/protocol only.

Upload the renamed world through the normal Coworld workflow. Wait for
certification graduation, successful upload smoke episodes, and version
readiness. Verify the original world is unchanged and the new variant has
nine seats. Establish either the private-league gate or the explicitly
approved fallback above before uploading the cohort. Record image digests
and immutable policy-version UUIDs; never use
moving aliases or a dynamic top-N selector in evaluation requests.

In private-league mode, verify automatic rounds are paused before attaching
policies. League-less mode does not attach policies to any league. Do not start
qualification games unless the documented API requires membership and the
additional games have been reviewed. Read submitted-image visibility again
after the publisher cycle.

## Serial execution and recovery

### Import the setup evidence and inspect

After supported setup is verified, each variant in `batch.json` also needs
`container_image_id` matching its policy readback. Set `setup_evidence` to a
relative JSON path within the batch, and `coworld_version` to the verified
new-world version. The driver compares that version, the source game image
and viewer bundle digests, and the shared token cap against the live manifest.
For private-league mode, the setup evidence's required fields are `mechanism`
(the supported operational setup), `league_id`, `reconciled_at`,
`reconciliation_evidence` (relative nonempty evidence file),
`routing_observed_at`, `routing_evidence` (relative nonempty deployment-read
file), and `routing_settings` containing
`COWORLD_OPENROUTER_ROUTING_ENABLED=true` and
`COWORLD_OPENROUTER_EPISODE_PERCENT=100`. Timestamps must be timezone-aware
and within 30 minutes when submitting; refresh the observations as needed.
The driver cannot establish those deployment facts itself: these are reviewed
evidence imports, never permission to change settings.

For `submission_mode: "leagueless"`, setup evidence instead identifies the
matching `coworld_id` and retains the same recent routing evidence and
settings. Do not invent private-league reconciliation evidence. The driver
reads the current seed catalog and checks that no seed exists, or validates
the separate `seed_league_id` and its paused state before submission. That
public seeded league, if present, is a background-scheduling safety check,
not the XP target. Retain authorized evidence that submitted images and realized XP
requests are private, and distinguish that from the visible world metadata.

**September 8 privacy finding:** the completed transport-fixed Gemini canary
had `private=true`, but its gameplay replay was downloadable without
authentication. Inspection found gameplay/chat, no embedded conversation
records, and no full source soul bodies in that particular replay. Private XP
metadata does not establish team-only replay access. On September 9, James explicitly accepted publicly downloadable gameplay
replays and authorized resumed hosted runs. Source souls and submitted policy
images must still remain private. Public replay access is now an accepted
property of this experiment, not a claim of team-only artifact access. Do not change backend/storage permissions or
delete artifacts as an implicit part of the latency work. See the
[Gemini canary report](recon/heartleaf-eval-gemini-canary-2026-09-08.md).

Use the saved Softmax login for the intended API server. The driver uses the
existing elevation header and never asks for tokens on the command line.
If login is absent, use the installed `softmax login` workflow.

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval.py inspect \
  --batch tmp/heartleaf-eval/heartleaf-eval-20260908/batch.json
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval.py submit-one \
  --batch tmp/heartleaf-eval/heartleaf-eval-20260908/batch.json --game canary
```

`inspect` reads scope and any persisted requests without submitting games.
Both commands accept `--api-url` for an explicitly selected server. Inspection
uses the API-server root (for example `https://softmax.com/api`), appending
`/observatory/` as the released Coworld client does; do not include that suffix
in `--api-url`. Inspection
writes local evidence but does not configure the world or league. Submission
persists an intent before POST and a response afterward; keep both files.

The schedule is fixed:

| Game | Seed | Days | Seat order | Counts toward coverage |
| --- | --- | --- | --- | --- |
| canary | 91001 | 1 | S1-H, S1-Q, S1-G, S2-H, S2-Q, S2-G, S3-H, S3-Q, S3-G | No |
| eval-a | 91002 | 7 | Same as canary | Yes |
| eval-b | 91002 | 7 | Move each policy from slot i to (i+4) modulo 9 | Yes |

Every game uses 180 seconds/day, `maxGames=1`, `maxTicks=0`, and real model
replies. Submit one game at a time. Requests are private, target only the
new private league in private-league mode. In league-less mode they instead
include top-level `coworld_id`, omit `target` and `idempotency_key`, and still
set `private: true`. Both modes omit routing overrides and pin the exact nine
policy UUIDs. Immediately before POST, verify the appropriate league/seed
checks, immutable target world and game assets, and all nine images.

Read current budgets, model availability, episode limits, and deployed
OpenRouter routing before the canary. The proposed $10 threshold stops
further submissions; it is not a provider cap or guaranteed maximum.
Explicit XP draws from the requester's personal allowance, not the Coworld's
tournament budget envelope. Its usage is still attributed to the selected
Coworld. Check personal allowance and reconcile usage by Coworld and episode;
do not expect the world tournament-budget meter to increase by XP spend or
require those totals to match. The driver's world-budget read is context,
not proof that the requester can afford an XP request.
Ingestion lag and a running game can exceed it. Wait for actual canary spend,
project remaining cost, and ask for a revised budget if needed. Never treat
missing usage as zero or silently raise the threshold.

Before any submission, set `batch.json`'s `budget_evidence` to a relative
JSON file inside the batch. It must contain the matching `batch_id`,
`accounting_status: "reconciled"`, finite nonnegative `setup_cost_usd` and
`projected_canary_usd`, plus `evidence_file` pointing to a nonempty reviewed
cost record within the batch. The driver includes setup cost before the
canary, then setup plus accepted prior-game costs and the next-game projection
before subsequent games. A sum at or above $10 stops submission. Missing
setup accounting is not free setup.

Keep every exact request body and persisted submission intent. League-scoped
requests use stable, distinct per-game idempotency keys.
On an ambiguous league-scoped response, reconcile the existing request or
repeat the identical body with the same key, then check the returned roster
and configuration. Do not alter a body under a reused key.

**League-less requests have no server deduplication guarantee.** After any
ambiguous POST, including a timeout, rerunning `submit-one` must stop without
another POST, even for an identical body. Keep the intent and look up the
existing request using authorized read-only evidence. Once its request ID is
known, `reconcile-one --batch <batch.json> --game canary --request-id <id>`
fetches and validates its realized world, roster, notes, and configuration
before recording the local response. It does not submit a game. Do not delete
an intent or invent an idempotency key to force a retry. If the request cannot
be found conclusively, stop for operator resolution; uncertainty is not proof
that no game was created. Request detail is a projection, so retained intent
and roster/config readback alone do not independently prove the persisted
private flag; retain authoritative authorized privacy evidence separately.

A failed completed
game is retained with its cost; a replacement requires an explicitly reviewed
schedule and budget, not an invisible retry.

The canary must show accepted souls and real successful calls in all nine
seats, the three frozen batch models on OpenRouter (including any `:nitro` suffix), usable action JSON,
no persistent truncation/default replies, terminal success, results, and
replay. Request fields alone do not prove the realized provider/model. Inspect
durable attempts, provider records, and player logs. If token settings need
changing, stop and version the experiment before full games.

**Action-counting correction, September 9:** `brains.handleReply` logs
`outcome=usable` for a parsed reply even when the action is invalid in the
current state. Those lines also contain `ignored=wait`; the game substitutes
waiting. Count `usable_actions` only from usable reply lines without that marker.
Report parsed replies, ignored actions, parse errors, truncations, and provider
failures separately. Do not claim the no-persistent-default criterion from
positive parsed-reply counts. The [hosted results report](recon/heartleaf-eval-hosted-results-2026-09-09.md)
records this finding and the corrected earlier canary evidence.

Before progressing, write `acceptance/canary.json` (then
`acceptance/eval-a.json`) inside the batch. Record `request_id`, a relative
nonempty `evidence_file` holding reviewed log/usage findings,
`accounting_status: "reconciled"`, measured `cost_usd` across all attempts,
and `projected_next_game_usd`. Its nine `seats` each record `slot`,
`policy_version_id`, `served_model`, `provider: "openrouter"`,
`successful_calls`, `usable_actions`, and `truncations`. The current gate
requires positive integer call/action counts and integer zero truncations;
booleans and NaN are invalid. Slots must be integers 0–8 and map each policy
UUID to its actual slot in the hosted episode participant readback. Do not manufacture
these values from the desired configuration.

After acceptance and budget review, run the same `submit-one` command with
`--game eval-a`, and later `--game eval-b`. The driver checks terminal
request status and the imported acceptance records before progressing.

## Final evidence and results

Record request, episode, and all job-attempt IDs; the realized Coworld/version
and config; nine policy UUIDs; source/rank/model and seat; final scores;
requested/served models and routing; accepted calls, failures, truncations,
timeouts, tokens, cost, and authorized replay/log links. Confirm both full
games reached the final day with all nine scores.

Attribute every attempt, including retries, to `heartleaf-eval`, not the
original world. Separately record canary, full-game, and setup/certification
costs. Reconcile provider usage and episode/world accounting without counting
multiple representations of the same call twice. State rounding/caching
tolerance. After up to 30 minutes for usage ingestion, unresolved accounting
remains unresolved, never zero.

Count distinct successful full episodes only. Each of the 36 unordered
policy pairs must have two meetings; the canary and failed episodes do not
count. Same-soul and same-owner variants remain distinct policies. A pair
matrix is coverage evidence, not 36 independent trials or proof of a winning
model. Report descriptive within-soul differences and leave any relevant
private or public seeded league's automatic rounds paused. If the evaluation
world has no league seed, preserve that state.

Write a friction record alongside the results with: stage, observed evidence,
operator effort, workaround, residual risk, and suggested future improvement.
Include failed API reads and private-league setup limitations. Proposed API
improvements are findings, not authorization to modify the backend. Do not
label this milestone complete without hosted behavior, routing, privacy,
accounting, and coverage evidence.

Generate the report from reconciled evidence, not from scheduled requests:

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval.py report \
  --batch tmp/heartleaf-eval/heartleaf-eval-20260908/batch.json \
  --evidence tmp/heartleaf-eval/heartleaf-eval-20260908/evidence.json
```

Evidence must carry the matching `batch_id` and `episodes`. Each normalized
episode has `episode_id`, `game_id` (`canary`, `eval-a`, or `eval-b`),
`status` (`completed` only after terminal verification), and the nine
`policy_keys` in actual seat order. Include all per-seat and attempt evidence
in those records; arbitrary additional episode fields are preserved in the
JSON report. Duplicate episode IDs are counted once; contradictory records
are rejected.

The top-level `costs` object uses `canary_usd`, `evaluation_usd`,
`setup_compute_usd`, and `total_usd`. Omitted costs remain unresolved. The
total must equal canary plus evaluation plus setup within an absolute
0.000001 USD tolerance; all four values must be finite and nonnegative.

Each completed episode's `seats` must have nine distinct `policy_key` values
and integer `slot` values 0–8 matching `policy_keys` in actual seat order.
`policy_version_id` must match that variant's uploaded UUID. Include the exact
`served_model`, `provider: "openrouter"`, finite numeric `score`, finite
nonnegative `llm_cost_usd`, positive integer `successful_calls` and
`usable_actions`, and nonnegative integer `failed_calls`, `truncations`,
`timeouts`, `input_tokens`, and `output_tokens`. Boolean values do not count
as measurements. The acceptance gate requires zero truncations. Missing or
invalid measurements leave the report unresolved even if a verification flag
was set true.

The `verification` object records `provenance`, `nine_variants`, `canary`,
`full_games`, `routing`, `accounting`, `replays`, and `image_visibility`.
Private-league mode additionally requires `private_league` and `paused_rounds`;
league-less mode instead requires `private_requests` and `seed_rounds_paused`.
The latter means the catalog proves no seed exists, or the matching seeded
league exists and its automatic rounds are paused; record which was observed.
Set a check to true only with retained evidence; a league-less success must
never claim that its public seeded league was private.
Record remaining caveats in `limitations`. The generated `results.md` and
`results.json` summarize this supplied evidence; they do not independently
verify it and cannot replace the hosted checks above.

## Expanded-cohort local groundwork

`eval/tools/heartleaf_eval_schedule.py` provides a standalone, deterministic
nine-seat pair-covering scheduler. Policy identities are opaque, so variants
of the same soul may meet. It guarantees the requested minimum pair coverage,
not the fewest games or perfect seat balance. For 90 identities and two
meetings per pair, the current algorithm produces 283 planned games covering
all 4,005 pairs at least twice. These are not submitted or completed episodes.

The scheduler is integrated with local expanded preparation through `--models`.
Without that option, preparation retains the original three-soul, three-model
milestone. With it, preparation accepts one to nine consecutive ranked sources
and an explicit JSON model catalog, requiring at least nine resulting policies:

```json
[
  {"key": "H", "model": "anthropic/claude-haiku-4.5", "model_header": "#!us.anthropic.claude-haiku-4-5-20251001-v1:0"},
  {"key": "F", "model": "google/gemini-2.5-flash-lite", "model_header": "#!google/gemini-2.5-flash-lite"},
  {"key": "G", "model": "openai/gpt-oss-120b:nitro", "model_header": "#!openai/gpt-oss-120b:nitro"}
]
```

```sh
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_eval.py prepare \
  --cohort tmp/heartleaf-eval/20260908-top9/cohort.json \
  --models tmp/heartleaf-eval/models.json \
  --base-image '<uploader-registry/repository>@sha256:<64 lowercase hex characters>'
```

Use a new batch ID in a copy of the cohort, preserving its source-path resolution;
preparation refuses to overwrite existing batch directories. Model keys are unique
uppercase alphanumeric identifiers, beginning with a letter, at most 16 characters.
Headers must match model slugs, except Haiku retains its existing Bedrock header.
Ordinary and Nitro routes for the same slug cannot count as two model identities.
Operators must also exclude other aliases for the same underlying model; the local
validator does not resolve provider catalogs or prove model availability.

Expanded output uses `heartleaf-eval/2`, preserves source body bytes and duplicate
ranked identities, and creates seven-day nine-seat plans with two meetings per pair.
Every planned game uses seed 91002. This is pair coverage, not a controlled claim
about model effects or optimized seat balance. Catalog entries are not marked as
accepted models, and generated variants have no uploaded policy IDs.
The legacy submission and report commands explicitly reject this schema. Once
the variants are uploaded and their immutable identities recorded, use the
[configurable runner](heartleaf_experiments.md) for expanded hosted execution
and result verification. The 90-policy study itself has not been executed.

The scheduler's separate coverage counter accepts
only completed seven-day episodes explicitly marked `acceptance_verified`,
deduplicates episode IDs, and rejects conflicting evidence. That marker must
come from actual hosted verification; the counter does not authenticate it.

Run the existing driver and new scheduler tests together:

```sh
tmp/heartleaf-eval-venv/bin/python -m unittest discover -s eval/tests -p 'test_heartleaf_eval*.py'
```

The reviewed nine-source snapshot is retained privately under
`tmp/heartleaf-eval/20260908-top9/`. Ranks 7 and 9 have identical soul bodies;
both source identities are retained. Ten working models and the 90-policy
cohort have not been established. Public gameplay replay access was accepted on September 9; further hosted
work remains subject to the existing spending limit and acceptance gates; see
[the privacy investigation](recon/heartleaf-eval-existing-replay-privacy-controls-2026-09-08.md)
and [the candidate screening plan](recon/heartleaf-eval-ten-model-screening-2026-09-08.md).
