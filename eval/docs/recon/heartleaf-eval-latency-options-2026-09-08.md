# Heartleaf eval: three latency experiments

September 8, 2026, America/Los_Angeles. Follow-up to the [latency breakdown](heartleaf-eval-latency-breakdown-2026-09-08.md).

## Outcome

All three requested tracks were completed: a local transport reproduction, one private nine-player Nitro XP canary, and research into faster model candidates. No backend changes were made. The hosted canary failed the all-request 20-second gate and was cancelled; no full evaluation games were started.

The strongest next direction is to fix the independently reproduced client connection-waiting issue, retain GPT-OSS Nitro as a promising model/routing combination, and screen a non-thinking replacement for Qwen. Neither the transport fix nor a new-model cohort has been deployed or submitted.

## A. Startup delay: locally reproduced

Pinned Curly's unconditional `CURLOPT_PIPEWAIT=1` delays other transfers behind the first slow response. In the controlled Linux test, one 18-second response caused eight three-second requests to time out at 20 seconds. Disabling only PIPEWAIT made all nine succeed; the fast calls took approximately three seconds. The server itself did not queue these requests—the delay was before server receipt.

Six cases covered 108 fake requests, cold and repeated waves, and immediate versus delayed headers. Immediate headers did not fix the behavior. After timeouts, the delay could recur on the same client. The libcurl package matched the frozen eval runtime; no inference spend was incurred. This proves the local mechanism, while attribution to every historical hosted delay remains an inference.

[Reproduction, exact measurements, source references, and proposed change](heartleaf-eval-startup-investigation-2026-09-08.md).

## B. Nitro XP: excellent GPT sample, Qwen still fails

One private, league-less request targeted certified `heartleaf-eval:0.1.4`, retaining its game image, nine seats, 20-second deadline, 2,048-token cap, Qwen thinking disabled, and GPT default reasoning. Six private Nitro policies preserved the three source soul bodies; the three existing Haiku policies were reused unchanged.

Request: `xreq_4e24bde1-2bc8-4cc0-bade-e1bd6b3205e4`. Job: `9d1aeb41-3cce-435f-b3c9-cd6da77bc241`.

| Model / actual provider | Calls | Median proxy duration | Maximum | Above 20 seconds |
| --- | ---: | ---: | ---: | ---: |
| Haiku / Amazon Bedrock | 35 | 1.570 s | 2.420 s | 0 |
| GPT-OSS 120B Nitro / Cerebras | 36 | 0.502 s | 1.526 s | 0 |
| Qwen 3.5 Nitro / Alibaba | 23 | 1.116 s | 1.924 s | 0 |
| Qwen 3.5 Nitro / Venice | 14 | 2.385 s | 25.494 s | 2 |

There were 108 provider responses and 106 usable game actions. Both misses were Qwen/Venice calls: each generated 2,048 tokens, reported zero reasoning tokens, and returned invalid JSON. Their timing confirms another upstream completion problem, not a long first-token wait:

| Call | First token | After first token | Approximate non-OpenRouter residual |
| --- | ---: | ---: | ---: |
| `31b0929a-e331-40e0-b9aa-893e464dc7c3` | 1.721 s | 23.715 s | 0.058 s |
| `d2135f97-e093-476e-9e26-2972467c9cb6` | 1.042 s | 20.711 s | 0.062 s |

Neither call used a fallback. Router overhead was 10 ms and 5 ms respectively. “After first token” includes generation and delivery, not a direct GPU-only measurement. Raw Broadcast traces were retrieved for all 108 calls, with none missing. Local evidence: `tmp/heartleaf-eval/20260908-nitro-timing/{calls,traces,breakdown,summary}.json`.

The canary was cancelled and all its pods were removed. Provider-billed LLM subtotal was **$0.20714325**. World-level metering lagged and did not yet include this canary; unknown compute is not represented by that subtotal. [Hosted execution, privacy, archives, accounting, and validation report](heartleaf-eval-nitro-xp-2026-09-08.md).

The earlier GPT default-routing sample had an 8.830-second median versus 0.502 seconds here. This is a promising screening result, not a controlled speedup estimate: prompts, histories, providers, and sample sizes differ. Nitro did not select a single provider for Qwen and cannot be treated as a provider pin or deadline guarantee.

## C. Faster alternatives: researched, not yet run

The leading candidates are `google/gemini-2.5-flash-lite` and `meta-llama/llama-3.3-70b-instruct:nitro`. They offer a non-thinking proprietary comparison and a non-reasoning open-weight comparison. `qwen/qwen3-next-80b-a3b-instruct:nitro` is the next open-weight candidate. GPT-OSS 20B remains exploratory because mandatory reasoning can still consume latency and output budget.

Public provider speed listings are useful for choosing experiments, not proof of compatibility or deadline behavior through our Messages/Converse route. Keep the original Haiku policy UUIDs and dot-form model headers unchanged as controls. [Exact slugs, prices, provider speeds, reasoning behavior, primary sources, and proposed cohort](heartleaf-eval-faster-model-options-2026-09-08.md).

## Recommended sequence

1. Expose a supported Curly setting and disable PIPEWAIT for the local sidecar client, preserving nine handles and the deadline. Keep the local regression test. This is a client/dependency change, not a backend project.
2. Verify the isolated transport change in a labeled eval revision. Do not claim that it repairs upstream 20-plus-second completions.
3. Screen the proposed non-thinking alternatives in a separate nine-seat cohort. Retain GPT-OSS Nitro as a promising tested option for later comparisons.
4. Require a complete canary with valid actions and no deadline misses before resuming full milestone games. Report game enqueue-to-action time, not just provider success.

No runtime source fix, backend mutation, new-model XP, or full evaluation was performed in these three tracks. Existing unrelated changes were preserved.
