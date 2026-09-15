# Heartleaf eval: faster model candidates

Research date: September 8, 2026, America/Los_Angeles. Public listings were read live; prices and rolling performance will change.

## Recommendation

Test **Gemini 2.5 Flash-Lite** and **Llama 3.3 70B Instruct with Nitro**, retaining Haiku as the control. Prefer **Qwen3 Next 80B A3B Instruct** as the next open-weight alternative. GPT-OSS 20B is a useful speed experiment, but its mandatory reasoning makes it a less clean remedy for the current reasoning-related delays.

These are candidates, not verified replacements. This track made no inference requests, uploaded no policies, and changed no backend or game code. Existing evidence establishes that Haiku already completes these calls quickly: 27 successful calls, median 1.614 seconds, maximum 2.450 seconds. Those are proxy durations, not full game enqueue-to-action measurements. See `eval/docs/recon/heartleaf-eval-latency-breakdown-2026-09-08.md:42–50`.

## Mission and source map

Identify current OpenRouter models that could return valid Heartleaf actions within the existing deadline, using the existing hosted Converse translation. Answer: which models, which provider speeds and prices, which reasoning settings, which compatibility risks, and what to test next.

- `eval/docs/heartleaf_eval.md`: private league-less hosting, nine-seat schedule, spending and acceptance requirements.
- `eval/docs/recon/heartleaf-eval-latency-breakdown-2026-09-08.md`: measured baseline and known routing constraints.
- Frozen game source at `/Users/jamesboggs/coding/coworlds/heartleaf-eval-reasoning/src/heartleaf/bedrock_client.nim`: request construction and model tuning.
- OpenRouter model pages: current provider P50 performance and prices.
- OpenRouter public model and endpoint APIs: current slugs, advertised parameters, reasoning metadata and provider inventory.

## Shortlist

Prices are USD per million uncached input/output tokens **for the named endpoint**, not the cheapest headline model price. Performance is the model page's provider P50 latency/throughput snapshot, not a Heartleaf benchmark, deadline guarantee, or independently measured GPU speed. Each latency/throughput pair belongs to the same provider; do not combine a model's best latency from one provider with its best throughput from another.

| Exact base model slug | Role / reasoning | Example provider | Listed P50 latency / throughput | Input / output price |
| --- | --- | --- | --- | --- |
| `anthropic/claude-haiku-4.5` | Existing proprietary control; retain accepted settings | Anthropic | 0.72 s / 78 tokens/s | $1.00 / $5.00 |
| `google/gemini-2.5-flash-lite` | Proprietary candidate; thinking disabled by default | Google AI Studio standard | 0.43 s / 118 tokens/s | $0.10 / $0.40 |
| `meta-llama/llama-3.3-70b-instruct` | Open-weight, non-reasoning instruction model | Groq | 0.22 s / 137 tokens/s | $0.59 / $0.79 |
| `qwen/qwen3-next-80b-a3b-instruct` | Open-weight, explicit non-thinking instruction model | Google Vertex | 0.48 s / 90 tokens/s | $0.15 / $1.20 |
| `openai/gpt-oss-20b` | Open-weight; mandatory reasoning, default medium | Groq | 0.31 s / 365 tokens/s | $0.075 / $0.30 |

Row sources: [Haiku](https://openrouter.ai/anthropic/claude-haiku-4.5), [Gemini](https://openrouter.ai/google/gemini-2.5-flash-lite), [Llama](https://openrouter.ai/meta-llama/llama-3.3-70b-instruct), [Qwen Next](https://openrouter.ai/qwen/qwen3-next-80b-a3b-instruct), [GPT-OSS 20B](https://openrouter.ai/openai/gpt-oss-20b). GPT reasoning defaults come from the [live model catalog](https://openrouter.ai/api/v1/models).

### Why these are better experiments

**Gemini 2.5 Flash-Lite:** provides a separate provider family and avoids adding a reasoning-control parameter. Its priority endpoint lists 0.22-second latency and 238 tokens/s at $0.18/$0.72. Start with the existing default request shape; treat a Nitro variant as a separate routing treatment. Thinking being off by default is specifically documented for this model, not an assumption about all Gemini Flash models. [Gemini listing](https://openrouter.ai/google/gemini-2.5-flash-lite).

**Llama 3.3 70B:** useful non-reasoning open-weight contrast. The speed case depends on routing: its cheapest DeepInfra endpoint lists 17 tokens/s versus Groq's 137. Simply changing the base model name may still select a slower endpoint. Nitro is a throughput preference, not a Groq pin. [Llama provider table](https://openrouter.ai/meta-llama/llama-3.3-70b-instruct).

**Qwen3 Next Instruct:** preserves an open-weight Qwen-family comparison without needing the Qwen 3.5 reasoning-disable override. Alibaba also lists 0.53 seconds / 69 tokens/s at $0.0975/$0.78, while DeepInfra lists 26 tokens/s. The model listing explicitly describes operation without thinking traces. [Qwen Next listing](https://openrouter.ai/qwen/qwen3-next-80b-a3b-instruct).

**GPT-OSS 20B:** potentially very fast on suitable hardware, but do not repeat the rejected GPT low-effort request from the previous canary. Groq advertises 1,000 tokens/s directly, compared with OpenRouter's observed 365-token/s P50 for its Groq endpoint. Different measurement conditions matter; neither predicts the tail for our prompts. [Groq model documentation](https://console.groq.com/docs/models), [OpenRouter GPT-OSS listing](https://openrouter.ai/openai/gpt-oss-20b). Mandatory reasoning and the default medium effort are advertised in the [OpenRouter catalog](https://openrouter.ai/api/v1/models).

## Other options examined

`qwen/qwen3-30b-a3b-instruct-2507` is genuinely non-thinking and open-weight, but smaller does not mean faster service: its listed endpoints range from 12 tokens/s on SiliconFlow to 44 on Alibaba. Alibaba lists 0.33-second latency and $0.13/$0.52 pricing. Keep it as a low-cost reserve, below Qwen Next for this particular speed experiment. [OpenRouter listing](https://openrouter.ai/qwen/qwen3-30b-a3b-instruct-2507), [Qwen's model card](https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507).

The catalog lists `google/gemini-3.5-flash-lite` with mandatory reasoning, and `inception/mercury-2.5` with reasoning enabled by default. [Live catalog](https://openrouter.ai/api/v1/models). I would defer both until after the simpler non-thinking candidates; this is a compatibility judgment, not a claim they are slower.

## Existing-route compatibility and JSON caveats

The table names OpenRouter canonical slugs, not replacement headers for the existing control policies. **Reuse the three existing Haiku policy UUIDs unchanged**, including their `us.anthropic.claude-haiku-4-5-20251001-v1:0` header. Replacing that header with `anthropic/claude-haiku-4.5` would change InvokeModel to Converse and confound the control. The frozen game checks dot-form Anthropic IDs for InvokeModel; the proposed slash-form alternatives use Converse. Source: `/Users/jamesboggs/coding/coworlds/heartleaf-eval-reasoning/src/heartleaf/bedrock_client.nim:117–133`.

The Converse request includes the transcript, system text, maximum tokens and temperature, but **does not request JSON-schema constrained decoding**. Therefore a model advertising structured outputs does not establish valid-action reliability in our current game. Inspect returned action JSON, valid game actions, truncation and default replies in the hosted test. Source: the same frozen file, `:282–314`.

The Qwen disabled-thinking override only matches `qwen/qwen3.5-`; neither proposed Qwen Instruct alternative receives it. That is intentional for models documented as non-thinking. Do not generalize the override to all Qwen models as part of this test. Source: the same frozen file, `:178–198`.

OpenRouter advertises structured-output support for the shortlist, but endpoint eligibility also depends on the exact translated request. Its public catalog is not our hosted model allowlist. Read back admission and actual served model/provider; record a rejection rather than silently changing model or backend policy. The earlier GPT effort failure demonstrates this distinction. Existing route constraints are recorded in `eval/docs/recon/heartleaf-eval-latency-breakdown-2026-09-08.md:64–72`.

The exact advertised parameter names relevant to this experiment are `max_tokens`, `temperature`, `response_format`, and `structured_outputs` for all five base slugs. Haiku and Gemini also advertise `reasoning` and `include_reasoning`; GPT-OSS 20B additionally advertises `reasoning_effort`, with catalog efforts `high`, `medium`, and `low` only. Qwen Next Instruct and Llama Instruct do not advertise reasoning controls. These are model-level catalog capabilities, not proof that every endpoint or our translated Messages route accepts them. The existing game does not send `response_format` or `structured_outputs`, so do not silently add either while comparing model slugs. [Live catalog](https://openrouter.ai/api/v1/models).

Nitro appends `:nitro` to a model slug, prioritizes throughput and admits priority-tier endpoints. It can cost more and does not guarantee a specific provider or maximum response time. Do not add provider overrides to the existing trusted request policy. [Nitro documentation](https://openrouter.ai/docs/guides/routing/model-variants/nitro).

## Proposed follow-up hosted comparison — not submitted this turn

Keep this separate from the already-running default-versus-Nitro experiment, so changing both model and routing is not mistaken for a controlled routing result.

1. Assemble a new explicitly labeled nine-policy cohort: reuse the three existing Haiku policy UUIDs and their dot-form headers unchanged, and create six new policies crossing the same three souls with `google/gemini-2.5-flash-lite` and `meta-llama/llama-3.3-70b-instruct:nitro`. Preserve soul bodies, game image, seed, deadline and output cap. Same-soul variants are intentional.
2. Verify hosted model admission, team-only policy access and private XP targeting before submission. Retain the existing accounting and soft-spend-stop gates in `eval/docs/heartleaf_eval.md`.
3. Check all nine seats for valid actions before the deadline. Compare cold-start and later calls separately; retain game enqueue-to-action, proxy duration, raw first-token/body-end timing, provider, prompt size, caching, output/reasoning tokens and cost.
4. Report every failure alongside p50/p95/max and sample count. Treat this as a screen for an acceptable model/provider combination, not a model-quality ranking. Gameplay histories diverge after differing actions.
5. If the open-weight candidate is inadequate, test `qwen/qwen3-next-80b-a3b-instruct:nitro` next; reserve `openai/gpt-oss-20b:nitro` for a distinct mandatory-reasoning experiment. No new backend features are required for these proposed slug-level treatments, subject to hosted admission.

## Unresolved and evidence limits

- No new candidate has been tested through our hosted Messages/Converse route in this research track. JSON/action reliability, parameter compatibility and deadline tails remain unverified.
- Public endpoint API responses returned null `latency_last_30m` and `throughput_last_30m` for every examined endpoint. Numeric speeds above were read from public model-page P50 tables, not invented from null API data. Example reproducible endpoint: [Llama inventory](https://openrouter.ai/api/v1/models/meta-llama/llama-3.3-70b-instruct/endpoints).
- Model-page rolling statistics do not hold prompt length, cache state, concurrency or output length constant. The page's latency metric is upstream-facing; it cannot account for the game's known pre-upstream startup delay.
- Public provider presence is not proof that the provider will be eligible for our exact request or chosen by Nitro. New models cannot fix a transport startup delay outside their inference path.

Resolved: current candidate slugs, public provider speed/pricing evidence, advertised reasoning behavior, and a bounded test plan. Unresolved: actual hosted acceptance and tail latency; those require the proposed paid canary, not further claims from listings.
