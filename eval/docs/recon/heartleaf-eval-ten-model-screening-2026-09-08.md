# Heartleaf eval: screening ten distinct models

September 8, 2026 Pacific. Read-only research; no additional XP, policy upload, provider request, or backend change was made for this report.

## Recommendation and current boundary

Keep the three models that passed the transport-fixed canary. Screen seven more, in the order below, with five reserves. The goal is **ten distinct model identities**, not ten combinations of one model and different providers. Nitro and ordinary routing do not count as separate models. A dated alias and the same underlying moving alias do not count twice.

The intended final cohort is nine source souls crossed with ten accepted models: 90 policies. That is an expansion from the existing three-soul canary, not something already uploaded or verified. Existing successful models still need verification across the additional souls and longer gameplay histories.

**No further paid screening is authorized by this research artifact.** The $10 cumulative soft stop and the public replay-access finding remain separate operator gates pending user direction. The successful canary's XP row was private but its replay was downloadable without authentication. See `heartleaf-eval-gemini-canary-2026-09-08.md:13–17` and its Privacy finding section. Do not interpret working inference as satisfied team-only privacy.

## Source map

- `eval/docs/recon/heartleaf-eval-gemini-canary-2026-09-08.md`: latest completed hosted result, durable logs, pricing reconciliation and privacy limitation.
- `eval/docs/recon/heartleaf-eval-reasoning-limit-2026-09-08.md`: accepted Qwen disable setting versus rejected GPT effort treatment.
- `src/heartleaf/bedrock_client.nim`: model header routing and request construction; the transport-fixed runtime retains the existing model tuning.
- OpenRouter's public model catalog: exact IDs and advertised parameter/reasoning metadata.
- Linked OpenRouter model pages: provider-specific rolling P50 latency, throughput and prices. These are selection evidence, not Heartleaf results.

## Three provisionally accepted models

Reuse existing control policy IDs and headers for the original three souls. In particular, Haiku keeps `us.anthropic.claude-haiku-4-5-20251001-v1:0`, not a newly substituted slash-form header that would change the game's protocol path.

| Model identity / actual requested header | Completed-canary actions | Median / maximum proxy attempt |
| --- | ---: | ---: |
| Haiku 4.5 / existing dot-form header | 35 / 35 | 1.501 / 2.563 s |
| `google/gemini-2.5-flash-lite` | 36 / 36 | 0.630 / 1.572 s |
| `openai/gpt-oss-120b:nitro` | 34 / 34 | 0.470 / 3.792 s |

All nine seats produced usable actions, with no timeout, truncation or empty-text failures. Gemini had zero reasoning tokens without a thinking override; GPT used Cerebras with default reasoning. This is one successful short canary, not a future-tail guarantee. Source: `heartleaf-eval-gemini-canary-2026-09-08.md:45–61`.

## Twelve untested candidates: seven first choices, five reserves

Every proposed new header below is exact, including the optional routing suffix we propose testing. The linked base-model pages and public catalog confirm the underlying model exists; they do not confirm the hosted allowlist or exact Messages request succeeds.

Latency and throughput are **the same named provider's public P50 snapshot**. Prices are USD per million uncached input/output tokens for that endpoint. Nitro does not pin that provider. Public P50 is not game enqueue-to-action time and does not reveal a maximum or our nine-request-concurrency behavior.

| Order | Exact proposed header | Reasoning treatment | Example provider P50 latency / throughput | Input / output price | Primary source |
| --- | --- | --- | --- | --- | --- |
| 1 | `meta-llama/llama-3.3-70b-instruct:nitro` | Ordinary instruct; no reasoning control | Groq: 0.23 s / 136 tokens/s | $0.59 / $0.79 | [Llama](https://openrouter.ai/meta-llama/llama-3.3-70b-instruct) |
| 2 | `google/gemma-4-31b-it:nitro` | Optional reasoning; catalog default off | Cerebras: 0.25 s / 320 tokens/s | $0.99 / $1.49 | [Gemma 31B](https://openrouter.ai/google/gemma-4-31b-it) |
| 3 | `openai/gpt-4.1-mini:nitro` | Ordinary non-reasoning model | OpenAI: 1.03 s / 51 tokens/s | $0.40 / $1.60 | [GPT-4.1 Mini](https://openrouter.ai/openai/gpt-4.1-mini) |
| 4 | `qwen/qwen3-next-80b-a3b-instruct:nitro` | Explicit non-thinking instruct | DeepInfra: 0.75 s / 48 tokens/s | $0.09 / $1.10 | [Qwen Next](https://openrouter.ai/qwen/qwen3-next-80b-a3b-instruct) |
| 5 | `mistralai/ministral-14b-2512:nitro` | Ordinary instruct; no reasoning control | Mistral: 0.27 s / 46 tokens/s | $0.20 / $0.20 | [Ministral 14B](https://openrouter.ai/mistralai/ministral-14b-2512) |
| 6 | `qwen/qwen3-30b-a3b-instruct-2507:nitro` | Explicit non-thinking instruct | Alibaba: 0.34 s / 89 tokens/s | $0.13 / $0.52 | [Qwen 30B](https://openrouter.ai/qwen/qwen3-30b-a3b-instruct-2507) |
| 7 | `openai/gpt-4.1-nano:nitro` | Ordinary non-reasoning model | OpenAI: 0.98 s / 70 tokens/s | $0.10 / $0.40 | [GPT-4.1 Nano](https://openrouter.ai/openai/gpt-4.1-nano) |
| Reserve 1 | `openai/gpt-oss-20b:nitro` | Mandatory reasoning; leave accepted-style default | Groq: 0.31 s / 322 tokens/s | $0.075 / $0.30 | [GPT-OSS 20B](https://openrouter.ai/openai/gpt-oss-20b) |
| Reserve 2 | `google/gemma-4-26b-a4b-it:nitro` | Optional reasoning; catalog default off | NextBit: 0.45 s / 55 tokens/s | $0.10 / $0.40 | [Gemma 26B](https://openrouter.ai/google/gemma-4-26b-a4b-it) |
| Reserve 3 | `openai/gpt-4o-mini:nitro` | Ordinary non-reasoning model | OpenAI: 0.53 s / 37 tokens/s | $0.15 / $0.60 | [GPT-4o Mini](https://openrouter.ai/openai/gpt-4o-mini) |
| Reserve 4 | `mistralai/mistral-small-3.2-24b-instruct:nitro` | Ordinary instruct; no reasoning control | DeepInfra: 0.57 s / 30 tokens/s | $0.075 / $0.20 | [Mistral Small](https://openrouter.ai/mistralai/mistral-small-3.2-24b-instruct) |
| Reserve 5 | `google/gemini-3.1-flash-lite:nitro` | Reasoning enabled, default minimal; not disabled | AI Studio: 0.55 s / 141 tokens/s | $0.25 / $1.50 | [Gemini 3.1](https://openrouter.ai/google/gemini-3.1-flash-lite) |

Reasoning-default metadata above was checked in the [live OpenRouter catalog](https://openrouter.ai/api/v1/models). Missing reasoning metadata alone does not prove an endpoint never generates reasoning text; the explicit non-thinking Qwen descriptions provide stronger evidence for those two candidates.

This order balances non-thinking behavior, provider-family variety and plausible action quality rather than sorting only by advertised speed. Gemma 31B's fast endpoint costs more than its cheaper alternatives; Friendli also lists 0.61 s / 76 tokens/s at $0.14/$0.40. Smaller Nano and Ministral models must earn acceptance through valid actions and sensible behavior, not just fast HTTP responses. These are screening judgments, not measured gameplay rankings.

## Exact existing-route compatibility constraints

The game's slash-form IDs go through Bedrock Converse, but the backend translates Converse into **OpenRouter `/api/v1/messages`**, not Chat Completions. A model's Chat Completions capabilities therefore do not prove our current route can carry every advertised parameter. Historical implementation was re-read at `712af9f8713f08e6a083a36a704abad06974cdbd`, using the separate `metta_4` checkout after `metta_5` was no longer present: `app_backend/src/metta/app_backend/job_runner/bedrock_translation.py:306–350` and `:787–799`. This is pinned source evidence; the latest hosted archives are the stronger evidence for what actually ran.

The existing translated request carries model, system/messages, `max_tokens` and `temperature`. The current evaluation uses 2048 maximum output tokens and a 20-second client deadline. Do not raise either to make a candidate pass. `additionalModelRequestFields` cannot override translated or trusted fields; the trusted provider object sets `require_parameters=true`. Source: the same pinned translation file, `:314–328`; `llm_sidecar.py:260–291`; successful archive readback in `heartleaf-eval-gemini-canary-2026-09-08.md:53–55`.

For every proposed candidate, the current model catalog advertises `max_tokens`, `temperature`, `response_format`, and `structured_outputs`. Only the first two are part of this game's normal request. Do not add schema constraints during the model screen: advertised schema support is not measured action reliability. Gemma 4 advertises `reasoning` but not `reasoning_effort`; GPT-OSS 20B and Gemini 3.1 advertise both. GPT-OSS permits high/medium/low, with medium default; Gemini 3.1 permits high/medium/low/minimal, with minimal default. [Current catalog](https://openrouter.ai/api/v1/models).

**Do not copy the failed GPT effort treatment.** The earlier Messages-route `output_config.effort=low` attempt filtered out all GPT endpoints and produced 404s. The successful GPT-OSS 120B Nitro canary used default reasoning instead. Qwen 3.5's accepted `thinking.type=disabled` control is a different setting and still did not eliminate overlong/truncated replies. Neither establishes a universal no-reasoning switch for new models. See `heartleaf-eval-reasoning-limit-2026-09-08.md` and `heartleaf-eval-nitro-xp-2026-09-08.md`.

Use the exact canonical identity plus `:nitro` when proposed, preserving the suffix in evidence. Nitro favors throughput and admits priority endpoints; it is not a provider pin or deadline guarantee. Do not inject `provider.sort`, `provider.only`, headers or presets to bypass the existing trusted route. [OpenRouter Nitro documentation](https://openrouter.ai/docs/guides/routing/model-variants/nitro).

## Screening and expansion plan

1. Resolve privacy and budget scope first. Read back current cumulative accounting and projection before every XP, including failed screening spend. Missing usage is not zero; this report does not estimate a safe total for the expanded workload.
2. Before paid work, validate exact model admission and request construction locally without changing the backend. Preserve the certified transport-fixed game, shared output cap and deadline. Reject unsupported settings explicitly rather than silently switching models.
3. Screen up to three new model identities per nine-seat village using the same three frozen souls crossed with those models. This is an economical initial filter, not validation across all nine final souls. Keep new cohorts and submission intents separate, with no automatic ambiguous-POST retry.
4. Count a candidate provisionally accepted only after its seats produce usable action JSON before the deadline, without timeout, truncation, empty replies, provider errors or silent default actions, and the canary completes. Retain latency p50/p95/max, sample counts, reasoning/output tokens, provider and cost. Preserve failures; do not select only successful calls when calculating pass rates.
5. Continue down the reserve list until ten distinct model identities have passed. Do not count ordinary and Nitro versions of one model twice, and do not replace failed models invisibly inside an accepted cohort.
6. Freeze the final ten-model configuration, then prepare the nine-by-ten product from the nine reviewed source souls. Verify immutable policy IDs and raw soul-body preservation. Exercise every one of the 90 variants before counting the expanded cohort accepted; three-soul screening does not cover the six additional soul prompts.
7. Only then run the explicitly scheduled coverage experiment. Nine-player games cannot hold all 90 policies at once. Scheduling, repeated pair coverage and final results are separate from finding ten models that respond successfully; avoid claiming either from screening alone.

## Unresolved

Twelve candidates remain untested through the hosted Messages route. Their allowlist admission, nine-way concurrency tails, prompt-length sensitivity, action semantics and final nine-soul behavior are unknown. Public provider inventory and rolling P50s cannot settle those questions. Endpoint API speed fields were null in the earlier public API check, so the table uses readable model-page statistics; values already changed materially within this day's investigation.

The confirmed replay-access limitation and the budget scope are the immediate operational gates. No paid work or new exposure was created by this research track.
