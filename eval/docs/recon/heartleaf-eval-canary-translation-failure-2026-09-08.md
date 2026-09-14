# Heartleaf eval canary: response translation failure

Investigated 2026-09-08. This is a diagnosis, not authorization to change the backend.

## Confirmed cause

The hosted sidecar received an OpenRouter response whose `usage.cache_creation_input_tokens` was explicitly `null`. Its Anthropic response validator requires an integer. Validation failed before the response could reach the player, and the sidecar returned HTTP 503.

The saved sidecar traceback at `tmp/heartleaf-eval/20260908-pilot/live-canary/bedrock-sidecar.log:29` identifies:

```text
ValidationError: 1 validation error for _AnthropicResponse
usage.cache_creation_input_tokens
Input should be a valid integer [type=int_type, input_value=None, input_type=NoneType]
```

**This supersedes the earlier hypothesis about missing thinking-block signatures.** The observed failure is a null token-accounting field, not evidence that these models cannot play Heartleaf or that OpenRouter failed to execute their generations.

## Run identity and outcome

- Batch: `20260908-pilot`.
- Coworld: `heartleaf-eval` version `0.1.0`, `cow_8bbab666-3bcb-4d0d-930b-27c9d6cd2ced`.
- Private league-less XP: `xreq_1be75a8e-519f-43d4-9c38-cdb84f2ce928`.
- Episode: `ereq_e5b4e884-fa2b-4856-a4da-86efaa6b0c5b`.
- Job: `0294964b-bde3-4891-84c5-9796f060457e`.
- Runtime: `softmax-tournament`, namespace `jobs`; main pod `job-0294964b-62lvr` and nine player pods.
- Deployed sidecar image observed by the main operator in live pod/event metadata around 18:53 UTC: `ghcr.io/metta-ai/bedrock-sidecar@sha256:8614e92cdd95c5a221542ff76c5fa43dbe4b6cccb2bb57565c7d9f1672b0d5bb`.
- Deployed worker image from the same observation: `ghcr.io/metta-ai/coworld-runner@sha256:b36d36cc63ea493aed2ab05617800f1398d17199e18e0193423fb44ef2f219fb`.
- Main operator cancelled the owned XP after observing repeated 503s and stalled game progress. The saved cancellation response reports `status=cancelled`.

The canary did not pass. It contributes no completed evaluation game or pair coverage. Full evaluation requests must remain unsubmitted. Cancellation stops further work but does not erase charges already incurred; final costs belong in the batch results after reconciliation.

## Why billed generations and HTTP 503 coexist

The provider executed and billed requests. The platform then rejected the response during translation. These are separate outcomes: provider success is not player-call success.

Read-only joins of `llm_attempt_events` and `llm_provider_events` showed Haiku successes, repeated GPT-OSS 503s, and mostly Qwen 503s, including provider-completed generations with billed costs. Some Qwen provider rows also reported `finish_reason=length`; those are an additional acceptance failure, not the cause of every 503.

Source inspection at fetched Metta commit `29a6b65a28677b1f69140d9da8724fce9f0ad536` explains the observed path:

1. `app_backend/src/metta/app_backend/job_runner/bedrock_translation.py:540` declares `cache_creation_input_tokens: int = Field(default=0, ge=0)`. The default handles absence, not an explicit null.
2. `bedrock_translation.py:699` validates `_AnthropicResponse`; the deployed traceback points to this same validator.
3. `llm_sidecar.py:754-759` clears `outcome_error_type` after valid provider accounting, then calls the success-payload validator. A failure here occurs before the later translation-error marker is assigned.
4. `llm_sidecar.py:792-794` records a fallback 503 for a successful upstream response that never produced a caller response. This explains why the attempt table can show `ok=false`, `status_code=503`, and a null `error_type` together.
5. `bedrock_sidecar.py:2140-2155` converts the validation exception into a Bedrock `ServiceUnavailableException`, describing an untranslatable provider response.

The null error field therefore does not exonerate translation, and retrying the same operation can spend more money without producing a usable action.

## Evidence boundaries

Raw logs, per-call billing rows, cancellation intent/response, and source souls remain in the ignored batch directory. This note intentionally contains no prompts, soul bodies, credentials, or signed artifact URLs. The source commit above is the inspected implementation reference; it must not be confused with the deployed container image digest.

No backend edit, deployment, routing override, or additional paid retry is part of this diagnosis. Resuming requires a separately authorized decision that addresses this observed translation failure while preserving the no-backend-change constraint, or an explicit change to that constraint.
