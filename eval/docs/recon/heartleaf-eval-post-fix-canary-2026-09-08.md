# Heartleaf eval post-fix canary — September 8, 2026

## Outcome

The backend null-cache response fix works in the evaluation: 36 recorded calls translated successfully. The canary nevertheless failed its action-delivery acceptance gate. It was cancelled after the village stalled at 10am with repeated Qwen timeouts/truncations. This is not a completed game or evidence of model-quality rankings.

- Private league-less request: `xreq_6ca9f873-c2e9-460f-b350-9bd8e0c489a5`.
- Episode: `ereq_389ddf88-e05b-40ce-81fb-3a639ff395a5`.
- Job: `fd3557f1-0ec4-4bd2-885e-0c61366f8e2f`.
- World: `heartleaf-eval:0.1.0`, `cow_8bbab666-3bcb-4d0d-930b-27c9d6cd2ced`.
- Submitted 23:20:19 UTC; running 23:20:41; cancelled 23:27:18. All ten pods subsequently verified absent.
- Same frozen nine policy versions, nine seats, seed 91001, one day, `daySeconds=180`, `BEDROCK_MAX_TOKENS=2048`. No backend or original-world changes.

The realized sidecar image `sha256:0aeba2bd2ad18254d759aa71f85226b37d5413d2e10247fa6cef6ac979c326f1` identifies source commit `712af9f8713f08e6a083a36a704abad06974cdbd` in its OCI configuration. Git ancestry verifies that it contains fix `c90b9ebbb1c0c617c5fb343c54ae4cf8a0fdefe3`. SQL confirms persisted request privacy, null league, correct world attribution, and the realized nine-slot roster. Image records remain private. Default OpenRouter routing is enabled at 100%; no routing override was sent.

## Observed behavior

| Model | Recorded calls | Sidecar successes | Provider length stops | Provider USD |
| --- | ---: | ---: | ---: | ---: |
| Haiku 4.5 | 9 | 9 | 0 | 0.025642 |
| Qwen3.5-35B-A3B | 18 | 18 | 7 | 0.076167780 |
| GPT-OSS-120B | 9 | 9 | 0 | 0.001741555 |

All nine souls were accepted, and each seat produced at least one usable action. The saved game log contains at least 17 usable actions and 21 client timeouts. The S3-Q seat produced one usable action and then stalled; its saved log records eight client timeouts and one HTTP 200 response without text. Six of that seat's nine recorded provider completions hit the length limit. These counts come from saved pre-cancellation snapshots, not complete terminal logs.

The village resumed after an initial 87.9-second pause, reached 10am, and paused again at 23:22:06. It did not advance further before cancellation. Unlike the first canary, neither saved sidecar logs nor durable attempt outcomes show the null-cache translation failure.

Qwen's length-limited replies consumed most of their 2048 output tokens on reasoning. Some Alibaba-served rows reported more than 2048 output tokens despite the requested setting. Do not treat the configured token setting as a guaranteed provider billing cap, or infer its precise enforcement semantics from the setting alone.

## Accounting and evidence

All 36 provider rows are reconciled from OpenRouter Broadcast; sum $0.103551335. At final readback, world usage includes only $0.098755735 of that increment, leaving a $0.0047956 projection discrepancy. Keep it unresolved until a subsequent read reconciles it. The cancelled job has null compute cost. Certification-parent compute, both cancelled-canary compute totals, and shared overhead are not known to be zero.

Observed metered subtotal across setup and both canaries: $0.3061909985. The $10 soft stop was not increased. No further game was submitted.

Private evidence remains in `tmp/heartleaf-eval/20260908-retry1/`: batch and intent/response, deployment/image provenance, scope and privacy readback, live logs, calls, usage, cancellation and cleanup records, and `retry-results.json`. The original cancelled batch remains intact in `../20260908-pilot/`. No soul bodies, prompts, credentials, or signed URLs belong in tracked documentation.

## Next technical step

The blocker is now the evaluation's runtime settings and Qwen's usable-output behavior, not another null-cache translation fix. Heartleaf exposes `BEDROCK_TIMEOUT_SECONDS` and `BEDROCK_MAX_TOKENS` in its existing game runtime. A follow-up should version an eval-only settings change, validate actual request/response behavior, preserve the same souls/models, and run another bounded canary before full games. Increasing a timeout alone does not cure truncated or empty output; increasing tokens alone can increase latency and spend. Do not silently weaken the acceptance gate or count either cancelled canary toward pair coverage.

James has authorized routine milestone attempts without further run-by-run approval. This does not remove the no-backend-change boundary, the experiment's versioning requirements, or the existing budget stop.
