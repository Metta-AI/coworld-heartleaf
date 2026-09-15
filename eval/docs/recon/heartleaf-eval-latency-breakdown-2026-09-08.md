# Heartleaf eval: where the latency goes

Investigation date: 2026-09-08 America/Los_Angeles (some evidence timestamps are September 9 UTC).

## Answer

The remaining slow completions are predominantly upstream response generation/delivery, not translation-layer work, and usually not time to first token. Disabling Qwen reasoning helped substantially: its subsequent 28 successful calls had a 1.997-second median, but one still took 23.528 seconds. A separate startup delay before the proxy timer remains unresolved.

Under 20 seconds is demonstrably achievable for these models. Keeping every request under 20 seconds has not been demonstrated. The next useful experiment is throughput-oriented routing, alongside a local investigation of startup connection scheduling—not increasing the timeout.

This investigation made read-only SQL/S3 queries and inspected existing code and logs. No new inference calls, backend changes, deployments, or runtime configuration changes were made.

## Evidence and measurement boundaries

Joined 127 attempt records from five jobs across three existing canaries. There were 112 successful responses and 15 GPT parameter-routing failures. Retrieved all 112 corresponding raw OpenRouter Broadcast traces; none were missing. Failure responses are excluded from the timing distribution below.

Raw traces contain `timeline.providerRequestMs`, `providerHeadersMs`, `firstTokenMs`, and `providerBodyEndMs`. Our SQL projection does not retain this timeline; the attempt first-byte field was null in all 112 successful records. Reading the existing raw traces recovered the missing distinction without changing the backend.

- **Attempt:** the proxy's measured forward-call duration, not game enqueue-to-action time.
- **First token:** OpenRouter's first-token offset. This can be a reasoning token, not usable action JSON.
- **After first token:** body-end offset minus first-token offset. Includes generation, buffering, delivery, and possible stalls; not a direct GPU inference measurement.
- **Residual:** attempt duration minus independently reconciled OpenRouter duration. Approximately the non-OpenRouter portion inside the proxy timer; excludes earlier game/transport/admission delays.

Across the 112 successes, residual median was **58.8 ms**, empirical p95 **266.2 ms**, and maximum **580.9 ms**. Router latency median was **10 ms**. Routing can occasionally be expensive: the older 122-second Qwen fallback had an 11.691-second router offset, but still spent 109.902 seconds after its first token.

## Slow calls after Qwen reasoning was disabled

All five remaining successful attempts above 20 seconds:

| Model / provider | Attempt | First token | After first token | Residual | Reasoning tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| GPT-OSS / SiliconFlow | 21.780 s | 2.030 s | 19.691 s | 0.059 s | 196 |
| GPT-OSS / DigitalOcean | 23.631 s | 0.660 s | 22.912 s | 0.059 s | 627 |
| GPT-OSS / DeepInfra | 25.033 s | 0.577 s | 24.411 s | 0.045 s | 712 |
| GPT-OSS / DigitalOcean | 25.096 s | 0.508 s | 24.432 s | 0.156 s | 599 |
| Qwen / Darkbloom | 23.528 s | 7.434 s | 16.048 s | 0.046 s | 0 |

The Qwen outlier returned only 60 output tokens, with zero reported reasoning tokens. Its routing step took 13 ms, with one successful provider attempt and no fallback. Both its initial wait and subsequent delivery were slow. Reasoning therefore cannot explain this call.

GPT's four outliers are much more clearly post-first-token delays, with substantial reasoning output. Three had no fallback. The 23.631-second DigitalOcean call used a fallback, but its first token still arrived within 0.660 seconds; fallback does not explain its long completion phase.

For comparison, successful calls in the two Qwen-disabled batches were:

| Model | Calls | Median attempt | Maximum | Above 20 s |
| --- | ---: | ---: | ---: | ---: |
| Claude Haiku 4.5 | 27 | 1.614 s | 2.450 s | 0 |
| Qwen 3.5 35B A3B | 28 | 1.997 s | 23.528 s | 1 |
| GPT-OSS 120B, default reasoning | 21 | 8.830 s | 25.096 s | 4 |

These are small, unmatched samples with different prompts and cache conditions—not a provider ranking or an unbiased end-to-end timeout rate. A proxy success can arrive after the game has already timed out. GPT's 15 rejected low-reasoning requests are not successful low-reasoning measurements.

## Latency we may introduce

The small residual rules out tens of seconds of work *inside the measured proxy forward path* for these outliers. It does not clear the entire local stack.

In the original canary, seat 0 queued its first Haiku request at 23:20:43.514 UTC; the matched OpenRouter generation started at 23:21:02.316, approximately 18.8 seconds later. Haiku then completed upstream in 1.366 seconds. This is a distinct pre-upstream delay, sufficient to threaten the game deadline even with fast inference.

Code inspection found nine Curly handles, a nonblocking multi-transfer loop, nine allowed in-flight game requests, no global pacing gap, and a two-second per-villager spacing rule. A single I/O thread does not imply serialized requests. However, Curly unconditionally enables `CURLOPT_PIPEWAIT`, which can wait to establish connection multiplexing capability. This is a candidate explanation, not a confirmed cause. [Official curl documentation](https://curl.se/libcurl/c/CURLOPT_PIPEWAIT.html).

The proxy timer also starts after request-body reading, Converse translation, and thread-worker admission. Existing traces cannot separate these from client connection/queue delay. A local fake-upstream reproduction with nine simultaneous requests should record enqueue, connection assignment, sidecar receipt, forward start, and completion; compare cold and warm connections before changing transport behavior.

The current proxy buffers the full upstream response. Streaming could improve observability, but receiving a first token does not provide the complete action JSON the game needs and would not by itself remove a long generation phase.

## Best next experiment without backend changes

Current requests supply `provider: {require_parameters: true}`, without a speed preference. OpenRouter documents default price-weighted routing; throughput and latency routing are separate choices. This explains why the current configuration need not choose the fastest eligible provider, but does not prove that routing alone caused every slow response. [Provider selection](https://openrouter.ai/docs/guides/routing/provider-selection).

The existing model-slug path appears capable of carrying `qwen/qwen3.5-35b-a3b:nitro` and `openai/gpt-oss-120b:nitro`. Colon is accepted and preserved, and Qwen's disabled-reasoning prefix check still matches. Exact hosted model allowlist admission and endpoint compatibility remain to be verified.

Nitro prioritizes throughput and also admits priority-tier endpoints, which may cost more. It is a plausible treatment for the measured long completion phase, not a deadline guarantee. [Nitro documentation](https://openrouter.ai/docs/guides/routing/model-variants/nitro).

Direct `provider.sort`, provider pinning, and latency preferences collide with trusted fields in the existing Converse route. Routing headers are filtered. A preset is not a reliable workaround because the request's explicit provider object replaces that preset field. No backend workaround should be added for this milestone.

Proposed verification sequence:

1. Reproduce and measure cold-start transport scheduling locally, with no inference spend.
2. Verify suffixed-slug allowlist compatibility; retain the 20-second game deadline, Qwen reasoning disabled, and GPT's currently accepted default settings.
3. Compare default versus Nitro as explicitly labeled routing variants under the same nine-player load, holding souls constant and recording prompt sizes, reasoning/output tokens, provider, cache hits, and cost. Do not change reasoning and routing simultaneously.
4. Audit game enqueue-to-action time as well as proxy and raw Broadcast timing. A request passes only if the game receives valid action JSON before its deadline—not merely if the provider reports success.
5. Report every timeout/error, p50/p95/max, cold-start behavior, and per-provider samples. Run a complete hosted episode before claiming the milestone verified. Zero misses in a finite test is evidence, not a guarantee about future requests.

## Source map and reproducibility

Heartleaf checkout was fetched and verified at `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`, equal to `origin/master`; existing user changes were preserved. Project environment: Coworld 0.1.46, Softmax CLI 0.26.32; neither appeared outdated in the package check.

Game source references below use the frozen worktree `/Users/jamesboggs/coding/coworlds/heartleaf-eval-reasoning` at `fa7b3f654174c9c7ddbde412ef610f63484eb487`, plus its existing reasoning-disable patch, rather than assuming the moving development checkout equals the uploaded image:

- `src/heartleaf/bedrock_client.nim:183`: Qwen reasoning override; `:403`: handle count; `:440`: request timeout forwarding.
- `src/heartleaf/pacing.nim:9`: concurrency and spacing; `:64`: admission checks.
- `src/heartleaf/souls.nim:13`: accepted model characters; `:61`: slug parsing.

Metta source inspected read-only in the separate `metta_5` checkout:

- At `712af9f8713f08e6a083a36a704abad06974cdbd`, `app_backend/src/metta/app_backend/job_runner/llm_sidecar.py:614`: timer boundary; `:345`: buffered HTTP; `:804`: accounting; `:944`: latency and absent first-byte measurement; `:260`: model validation; `:281`: provider policy.
- Same revision, `bedrock_sidecar.py:1627`: body read; `:1706`: translation; `:1338`: worker admission. Both sidecar files were verified unchanged through the later recorded backend commit `b5292f46fb07b45002d914fff6797590222cf841`. The newer sidecar image's embedded commit could not independently be recovered; this limits exact deployed-source attribution.
- At refreshed `origin/main` `0ee36144a4c8343989bab361a6824e3a0498eda9`, `app_backend/src/metta/app_backend/usage_ingest/openrouter_broadcast.py:260`: parsed trace schema omits timeline; `:309`: routing projection; `:350`: generation timestamp-derived latency.
- Pinned Curly `a0f42baacbc48f4e5924b18854c0df9dcc251466`, `src/curly.nim:261`: handle assignment/timeouts; `:292`: PIPEWAIT; `:342`: nonblocking transfer loop; `:835`: enqueue.

Local sanitized evidence, outside version control:

- `tmp/heartleaf-eval/latency_audit.py`: read-only collection and summary script.
- `tmp/heartleaf-eval/20260908-latency-audit/calls.json`: 127 joined attempt/provider records.
- `tmp/heartleaf-eval/20260908-latency-audit/traces.json`: 112 sanitized raw trace timing records, without prompts or generated text.
- `tmp/heartleaf-eval/20260908-latency-audit/breakdown.json`: joined per-call timing breakdown.
- `tmp/heartleaf-eval/20260908-latency-audit/summary.json`: provider/model/batch aggregates.
- `tmp/heartleaf-eval/20260908-retry1/live/job-fd3557f1-gdqwz.game.log:57`: original seat-0 enqueue evidence.

Unresolved: provider-internal queue versus prefill versus network time; decoding versus buffering/stalls after first token; the startup pre-proxy delay mechanism; and whether Nitro materially improves the tail under matched nine-player load.
