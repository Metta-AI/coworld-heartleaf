# Why Qwen timed out in the hosted canary

Date: 2026-09-08. Read-only investigation; no backend changes or new paid model calls.

Follow-up: [reasoning-limit implementation and hosted tests](heartleaf-eval-reasoning-limit-2026-09-08.md)
verified that disabling Qwen reasoning substantially improves typical latency,
but a later zero-reasoning call still exceeded 20 seconds upstream.

## Conclusion

The main failure is a mismatch between Heartleaf's **20-second total request deadline** and Qwen's reasoning behavior. Qwen spent approximately 97% of its reported output tokens on reasoning. Ten of its 18 recorded calls exceeded 20 seconds. Seven responses contained thinking blocks but no action text, so a longer timeout alone would not make this configuration reliable.

The fixed translation layer accepted and translated all 36 recorded attempts. That is not proof the game received a usable response before its deadline: provider work continued after the game had timed out. Qwen's slow calls are predominantly provider time, not translation overhead.

## Run and evidence

- World: `heartleaf-eval:0.1.0`, private to the Softmax team.
- XP: `xreq_6ca9f873-c2e9-460f-b350-9bd8e0c489a5`.
- Episode: `ereq_389ddf88-e05b-40ce-81fb-3a639ff395a5`.
- Job: `fd3557f1-0ec4-4bd2-885e-0c61366f8e2f`.
- Nine seats: three souls crossed with Haiku 4.5, Qwen3.5-35B-A3B, and GPT-OSS-120B.
- Submitted at 23:20:19 UTC; cancelled at 23:27:18 UTC. No complete game or final scores.

Durable attempt/provider records, plus all 36 retained request/response archives, were inspected. Timings below start inside the proxy; they exclude any earlier client or sidecar queue wait.

| Model | Recorded calls | Median duration | Maximum duration | Over 20 seconds |
| --- | ---: | ---: | ---: | ---: |
| Claude Haiku 4.5 | 9 | 1.47 s | 5.22 s | 0 |
| GPT-OSS-120B | 9 | 6.11 s | 15.92 s | 0 |
| Qwen3.5-35B-A3B | 18 | 22.48 s | 122.13 s | 10 |

Qwen reported 51,715 reasoning tokens out of 53,396 output tokens. Its median difference between proxy duration and reported provider latency was only 53 ms; the maximum difference was 321 ms. Only one Qwen call reported provider fallback. There were no recorded translation errors or upstream 429/503 responses in these 36 attempts.

### One timeout traced end to end

For a Qwen seat at village time 10 am:

1. Inferred proxy start: 23:22:06.338 UTC, calculated from completion timestamp minus measured duration.
2. Game reports timeout: 23:22:26.334 UTC, about 20 seconds later.
3. Provider/proxy completion: 23:22:30.207 UTC, after 23.869 seconds.

This response had action text, but it completed after the game had given up. The game then retried while the village waited.

## Why the current request settings cause trouble

Every archived Qwen request had the following effective settings at OpenRouter's `/api/v1/messages` endpoint:

```json
{
  "model": "qwen/qwen3.5-35b-a3b",
  "max_tokens": 2048,
  "temperature": 0.2,
  "provider": {"require_parameters": true}
}
```

There was no explicit thinking/reasoning control. The original Converse request also had no `additionalModelRequestFields`. The sidecar preserved the requested token setting: this is not evidence that translation dropped `maxTokens`.

All seven Qwen responses with a length finish reason contained only thinking blocks and zero text characters. The translator correctly represents thinking as Converse `reasoningContent`; Heartleaf extracts only text and reports `Bedrock response did not include text.` when none exists. One thinking-only response completed in 9.87 seconds, demonstrating a failure that raising the deadline would not address.

Several provider records nevertheless reported more than 2,048 output tokens. The longest call reported 18,709 output tokens, including 18,662 reasoning tokens. The precise reason for this provider accounting/limit behavior remains unresolved; the archives prove the setting was sent, not that every provider interpreted or enforced it identically.

[OpenRouter documents model-dependent reasoning controls](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens). Its current model metadata advertises optional reasoning for this Qwen model, but that does not establish which disable/budget setting works through the Anthropic-compatible route and each selected provider. Hiding reasoning with `exclude` is not the same as disabling it.

## Game behavior amplifies the delay

- [The client defaults to 20 seconds](../../../src/heartleaf/bedrock_client.nim#L15), with an environment override at lines 86–94. The frozen uploaded manifest does not set that override.
- [Model tuning](../../../src/heartleaf/bedrock_client.nim#L178) gives recognized reasoning models a 60-second minimum. Qwen is not recognized. The dotted `openai.` check also misses the actual slash-form `openai/gpt-oss-120b` slug.
- [Request submission](../../../src/heartleaf/bedrock_client.nim#L430) passes the resulting deadline to Curly/libcurl. This is a total transfer timeout, not an inactivity timeout; see [libcurl's timeout contract](https://curl.se/libcurl/c/CURLOPT_TIMEOUT.html).
- [Response parsing](../../../src/heartleaf/bedrock_client.nim#L306) extracts text only; [empty text becomes an error](../../../src/heartleaf/bedrock_client.nim#L468).
- [Failed calls retry](../../../src/heartleaf/brains.nim#L555), using [exponential backoff](../../../src/heartleaf/pacing.nim#L98). [The LLM phase waits for every seat](../../../src/heartleaf/brains.nim#L810), so one repeatedly failing seat stalls all nine.

The village advanced from 9 am after an 87.9-second pause, then remained paused at 10 am until cancellation.

The sidecar's configured 60-second HTTPX timeout does not contradict the 122-second call: [HTTPX timeouts govern individual connection/read/write/pool waits](https://www.python-httpx.org/advanced/timeouts/), not a single total wall-clock deadline. We did not capture the transport chunks needed to explain that particular call's read timing.

## Secondary uncertainty: initial requests waited before the proxy

Some first-round Haiku calls timed out despite short provider execution. Their inferred proxy starts were approximately 20 seconds after the game queued them. Provider latency therefore does not explain every timeout in the run.

One plausible contributor is the pinned Curly client's unconditional `CURLOPT_PIPEWAIT=1`. [libcurl documents that this can wait for an existing connection's multiplexing capability to become known](https://curl.se/libcurl/c/CURLOPT_PIPEWAIT.html). A slow first response could delay other transfers. This is a hypothesis, not a confirmed root cause: the hosted curl version, negotiated protocol, connection timings, and transport trace were not captured. The client uses a nonblocking multi-transfer loop; a single I/O thread alone does not establish serial execution.

## Recommended next step — not implemented

For the eval configuration, explicitly control Qwen reasoning and give requests an appropriate total deadline. Do not merely raise the output-token limit: that can increase thinking time and spend. Do not merely raise the deadline: seven existing responses still contain no usable action.

The existing Converse `additionalModelRequestFields` path can carry model-specific request fields through the translator, so a backend change is not the first requirement. First verify a supported reasoning setting through the exact hosted route, then run a bounded nine-seat test. Acceptance should require usable action text for every seat, no client deadline failures, and village progress through the full episode—not just successful sidecar attempt records. Separately instrument pre-proxy/connection timing if initial fast-model timeouts recur.

This would change the eval client's request configuration; it has not been applied in this diagnostic turn. The original frozen game remains unchanged.

## Source and artifact map

```text
src/heartleaf/bedrock_client.nim       Deadline, model tuning, request/response shape
src/heartleaf/brains.nim              Retry handling and all-seat barrier
src/heartleaf/pacing.nim              Backoff
tmp/heartleaf-eval/20260908-retry1/    Private run evidence and sanitized analysis
```

Local evidence, intentionally not committed:

- `tmp/heartleaf-eval/20260908-retry1/timeout-timings.json`: 36 joined attempt/provider records.
- `tmp/heartleaf-eval/20260908-retry1/timeout-shapes.json`: sanitized request controls and response block shapes; no prompt or answer text.
- `tmp/heartleaf-eval/20260908-retry1/timeout-summary.json`: aggregate timing/token statistics.
- `tmp/heartleaf-eval/20260908-pilot/coworld_manifest.json`: frozen game image and environment.
- [Prior canary report](heartleaf-eval-post-fix-canary-2026-09-08.md): run lifecycle and broader milestone status.

Deployed backend source was inspected at immutable commit `712af9f8713f08e6a083a36a704abad06974cdbd`:

- [Converse translation](https://github.com/Metta-AI/metta/blob/712af9f8713f08e6a083a36a704abad06974cdbd/app_backend/src/metta/app_backend/job_runner/bedrock_translation.py#L308): request fields and thinking/text response mapping at lines 621–651.
- [Sidecar forwarding](https://github.com/Metta-AI/metta/blob/712af9f8713f08e6a083a36a704abad06974cdbd/app_backend/src/metta/app_backend/job_runner/bedrock_sidecar.py#L1294): synchronous proxy work dispatched into a worker thread.
- [Provider transport and recording](https://github.com/Metta-AI/metta/blob/712af9f8713f08e6a083a36a704abad06974cdbd/app_backend/src/metta/app_backend/job_runner/llm_sidecar.py#L318): HTTPX transport, completion/accounting paths, and attempt timing.

Freshness: Heartleaf HEAD and fetched `origin/master` were both `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`. Project-local Coworld was `0.1.46`, Softmax CLI `0.26.32`; the package-tool freshness check found no newer release of either. Curly revision `a0f42baacbc48f4e5924b18854c0df9dcc251466` matches `nimby.lock`.

Provenance caveat: the frozen game image is `sha256:4bccff4f2fad9d55a0a60ab84ef19b2f50aaf12b71f04ae791852eddc39081db` (Heartleaf 0.2.7), but its labels do not identify a source commit. Current source matches observed payloads and timeout behavior; exact source-to-binary equivalence was not independently established.
