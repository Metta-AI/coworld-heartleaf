# Heartleaf eval implementation status — 2026-09-08

## Latest: reasoning limit implemented; latency gate still unmet

Qwen reasoning is now explicitly disabled in the eval game. The controlled
0.1.2 canary recorded 19 Qwen calls with zero reasoning tokens, no truncation,
and a maximum of 13.16 seconds, but four GPT-OSS calls exceeded 20 seconds.
A 0.1.3 experiment adding GPT-OSS low effort failed because the hosted route
excluded every endpoint for that parameter shape. It also recorded one Qwen
call taking 23.53 seconds with zero reasoning and only 60 output tokens.
Reasoning limits alone therefore have not met the requested latency gate.

Both requests are terminal and their pods are gone. The unsupported GPT-OSS
setting was removed; 0.1.4 is certified and canonical, restoring the exact
Qwen-only image. The final metered subtotal across eval versions is $0.50029461,
with incomplete compute pricing and possible ingestion lag still excluded.
No full evaluation games were submitted; pair coverage remains zero.
See [reasoning-limit results](../recon/heartleaf-eval-reasoning-limit-2026-09-08.md)
for build provenance, tests, automatic retries, and the exact upstream evidence.

## Previous status

The league-less driver and hosted setup are implemented. The first real-model canary exposed a backend response-translation failure and was cancelled. A separate backend task deployed the fix. The replacement canary verified successful translation but failed the action-delivery gate and was cancelled. The full milestone is **not complete**. This evaluation work has made no backend changes or league mutations.

## Post-fix retry

James authorized routine milestone run attempts without another approval. On September 8 at 23:20:19 UTC, submitted a distinct private league-less canary `xreq_6ca9f873-c2e9-460f-b350-9bd8e0c489a5`, episode `ereq_389ddf88-e05b-40ce-81fb-3a639ff395a5`, job `fd3557f1-0ec4-4bd2-885e-0c61366f8e2f`. It retains the same world, nine immutable policies, seed, one-day schedule, and 2048 token setting. The original cancelled intent remains intact.

The realized sidecar image is `sha256:0aeba2bd2ad18254d759aa71f85226b37d5413d2e10247fa6cef6ac979c326f1`; its OCI configuration identifies commit `712af9f8713f08e6a083a36a704abad06974cdbd`, which contains fix `c90b9ebbb1c0c617c5fb343c54ae4cf8a0fdefe3` by verified git ancestry. Routing remains OpenRouter 100%. SQL readback confirms the new world's attribution, null league, and private request. All nine image digests and realized seats match the frozen roster.

All nine souls were accepted and all nine seats produced usable actions. The village reached 10am, then remained paused while the S3-Q seat repeatedly timed out or received unusable output. Cancelled at 23:27:18 UTC after persistent failure; all ten pods were subsequently verified absent. The saved game log records at least 21 client timeouts, 17 usable actions, and one HTTP 200 response without text. These are pre-cancellation snapshot counts, not a complete terminal artifact.

All 36 durable attempts returned sidecar success with zero observed translation failures: Haiku 9/9, GPT-OSS 9/9, Qwen 18/18. Seven Qwen provider completions reported `finish_reason=length`; response translation is not proof of usable or timely actions. All 36 provider rows are Broadcast-reconciled, totalling $0.103551335. No final scores or replay were produced. Full games remain unsubmitted and pair coverage remains zero.

The observed cumulative metered subtotal is $0.3061909985 including the first canary and setup-child compute. At final readback the world-usage projection includes $0.098755735 of this retry, leaving $0.0047956 unmatched to the reconciled provider subtotal. Cancelled retry compute is null, not zero. Complete accounting remains unresolved. See [retry outcome](../recon/heartleaf-eval-post-fix-canary-2026-09-08.md).

Private evidence: `tmp/heartleaf-eval/20260908-retry1/`. Fresh prior metered spend is $0.2026396635; the retry carries it forward with a $3 projected increment under the unchanged $10 soft stop. Unmetered certification-parent/cancelled-canary compute and shared overhead remain unresolved. Heartleaf is current with fetched origin/master at `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`. Updated the isolated Coworld CLI to current release 0.1.46; Softmax CLI 0.26.32 remains current. All 41 driver tests pass after the update.

## Original attempt record

## Delivered

- `eval/tools/heartleaf_eval.py`: validates frozen source provenance and soul hashes, preserves body bytes while replacing model headers, prepares nine image contexts, constructs the fixed nine-seat schedule, and reports supplied evidence and pair coverage.
- `eval/tools/heartleaf_eval_api.py`: synchronous existing-API inspection and serial submission; explicit private league-less targets, immutable policy/image checks, fresh seed absence checks, persisted intents, GET-only recovery after ambiguous league-less submissions, and accounting/seat gates before progression.
- `eval/tests/test_heartleaf_eval.py`: offline contract and failure-path tests.
- [Operator runbook](../heartleaf_eval.md): preparation, supported setup requirements, explicit requests, evidence schemas, recovery, and final verification.

The source images were resolved through authorized existing AWS/ECR access. Three currently ranked souls were copied from stopped containers without executing submitted code. All nine Linux amd64 images were built with the canonical compiled soul-player base. Source souls, hashes, manifests, images, logs and results remain under ignored `tmp/heartleaf-eval/`; none belongs in a commit.

## Actual validation

All 41 offline tests pass. Ruff lint and formatting checks pass for both driver modules and the test file. CLI help also loads successfully against the pinned released authentication package.

Two local nine-player mocked episodes completed. The first used an incorrect mock action and is packaging evidence only. The second used `gather_plants`; all nine player logs confirm accepted souls, terminal results contain nine scores at day 1, and the Coworld replay-load check passed. This is not a hosted canary or proof of real model calls. Neither run counts toward pair coverage.

Evidence: `tmp/heartleaf-eval/20260908-pilot/local-mock-valid-action/`, its adjacent command log, `batch.json`, `results.md`, and `friction.md`. The generated result remains unresolved, with zero completed hosted pair meetings. No model-comparison scores are reported.

Commands for repeatable code validation:

```sh
tmp/heartleaf-eval-venv/bin/python -B -m unittest discover -s eval/tests -p test_heartleaf_eval.py -v
tmp/heartleaf-eval-venv/bin/ruff check eval/tools/heartleaf_eval.py eval/tools/heartleaf_eval_api.py eval/tests/test_heartleaf_eval.py
tmp/heartleaf-eval-venv/bin/ruff format --check eval/tools/heartleaf_eval.py eval/tools/heartleaf_eval_api.py eval/tests/test_heartleaf_eval.py
```

Freshness: Heartleaf HEAD and fetched origin/master remain `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`; the separate Metta checkout's fetched origin/main is `29a6b65a28677b1f69140d9da8724fce9f0ad536`. Isolated tools: coworld 0.1.45, softmax-cli 0.26.32, Python 3.13.5; release checks found no newer Coworld or Softmax CLI. The source world remains Heartleaf 0.2.7 with unchanged manifest hash. The new world's exact game/viewer digests match it; its shared token cap is the declared 2048 exception. Hosted certification used deployed contract `main-b4e3589c1e50`, not the newer inspected source head.

## Hosted result

- New world: `cow_8bbab666-3bcb-4d0d-930b-27c9d6cd2ced`, `heartleaf-eval:0.1.0`, canonical and certified. All five upload smoke episodes and all ten hosted certification steps passed.
- Nine immutable policy versions uploaded, one per frozen soul/model combination. All nine image records are ready, have no public URI, and are not bundled Coworld images. UUIDs/digests are in the private batch record.
- No league seeds or memberships created. James explicitly approved the league-less fallback after the [history investigation](../recon/private-league-history-2026-09-08.md) established the narrower supported-creation limitation.
- Canary: `xreq_1be75a8e-519f-43d4-9c38-cdb84f2ce928`; episode `ereq_e5b4e884-fa2b-4856-a4da-86efaa6b0c5b`; job `0294964b-bde3-4891-84c5-9796f060457e`.
- Persisted private flag, null league, new-world attribution and exact nine-slot roster were verified. Anonymous request read returned 401; requester and elevated-team requester reads returned 200. An unrelated authenticated user was not impersonated; its denial follows the inspected authorization implementation.

The village remained at 9am while the sidecar rejected upstream responses with `usage.cache_creation_input_tokens=null` as invalid integer fields. It returned HTTP 503 even though those provider generations completed and were billed. The canary was cancelled at 18:55:14 UTC; removal of its game and nine player pods was verified. No full games or replacements were submitted. See the [confirmed diagnosis](../recon/heartleaf-eval-canary-translation-failure-2026-09-08.md).

Across 51 recorded calls, Haiku had 3/3 sidecar successes, Qwen 3/22, and GPT-OSS 0/26. These are delivery outcomes, not model-performance rankings. No terminal scores or replay were produced. Partial live logs were preserved privately before cancellation. M=2 coverage remains zero.

Reconciled provider billing is $0.0821156635 and matches new-world XP usage facts within $0.000001. Six setup child jobs add $0.120524 metered compute, giving an observed subtotal of $0.2026396635. The certification parent pod, cancelled-canary compute and shared overhead are unpriced in these records; complete actual spend remains unresolved, not zero. XP charges are attributed to `heartleaf-eval` but draw from the user's allowance, not the tournament budget envelope.

The [operator runbook](../heartleaf_eval.md) and ignored `tmp/heartleaf-eval/20260908-pilot/results.md` record the current state. The certified world and policy versions are retained. Resume requires the response compatibility issue to be resolved or an explicitly approved experiment change; no backend fix, model substitution, replacement canary, or budget increase is implied by this handoff.
