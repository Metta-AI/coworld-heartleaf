# Heartleaf evaluation: hosted Nitro canary

Date: September 8, 2026 Pacific; evidence captured September 9 UTC.

## Outcome

Nitro dramatically improved GPT-OSS-120B in this canary: all 36 calls used
Cerebras, with a 0.502-second median and 1.526-second maximum. Qwen's typical
response also became fast, but two Venice calls generated 2048 output tokens,
hit the token limit, and exceeded the game's 20-second deadline. The canary
therefore **failed the all-calls-under-20s gate** and was cancelled. No full
evaluation games or automatic replacements were submitted.

This tests routing under existing backend behavior. No backend, game source,
runtime timeout, token cap, original Heartleaf world, or league was changed.

## Experiment and provenance

The same frozen three ranked soul bodies were crossed with three model choices:
the existing three Haiku policies, plus six newly uploaded policies whose only
soul-file change was appending `:nitro` to the Qwen or GPT model header. Raw body
bytes were checked unchanged. These are nine distinct policy versions, not nine
different souls. All retain the intended James Botts player identity.

- World: `heartleaf-eval:0.1.4`, certified canonical
  `cow_16f8134d-3c67-4b2a-8ede-2795e746c23c`.
- Game image:
  `public.ecr.aws/q5f4m8t9/cogames@sha256:50cfb46390232d83039e6b7f95946e9961bc677a7b3fa8ad684ad1606a48f4be`.
- XP: `xreq_4e24bde1-2bc8-4cc0-bade-e1bd6b3205e4`.
- Episode request: `ereq_6035990d-869d-4372-86c5-24b29acfef99`.
- Only job attempt: `9d1aeb41-3cce-435f-b3c9-cd6da77bc241`.
- Configuration: nine seats, seed 91001, one day, 180 seconds/day, one game,
  real replies, 2048 output-token cap, unchanged 20-second deadline.

The repository was refreshed before execution: Heartleaf HEAD and
`origin/master` both `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`. Existing dirty
changes were preserved. Project-local Coworld 0.1.46 and Softmax CLI 0.26.32
matched the latest releases reported by `uv pip list --outdated`.

## Measured results

These are complete sidecar attempt durations, not TTFT. All 108 provider rows
were reconciled from Broadcast; all returned transport-level success. Transport
success does not mean the game received a timely usable action.

| Model | Calls | Median | Maximum | Over 20s | Length stops | Usable actions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Haiku 4.5 control | 35 | 1.570s | 2.420s | 0 | 0 | 35 |
| GPT-OSS-120B `:nitro` | 36 | 0.502s | 1.526s | 0 | 0 | 36 |
| Qwen3.5-35B-A3B `:nitro` | 37 | 1.390s | 25.494s | 2 | 2 | 35 |

The game logs contain 106 usable actions and exactly two client timeout errors.
Every seat accepted its soul and produced at least 11 usable actions. No empty
text responses were observed. The failed calls were both S1-Q, seat 1; the other
eight seats had no deadline or truncation failures. No startup timeout occurred
in this particular canary; this does not rule out the separately reproduced
cold-connection scheduling problem.

Provider readback:

- GPT: Cerebras, 36 calls, maximum 1.526s.
- Qwen: Alibaba, 23 calls, maximum 1.924s; Venice, 14 calls, maximum 25.494s.
- Haiku: Amazon Bedrock through OpenRouter, 35 calls, maximum 2.420s.

The provider groups are small, unmatched samples of different turns and prompts.
Their differences are diagnostic evidence, not a general provider benchmark.

## What the two Qwen failures contain

Both archived requests explicitly contain model
`qwen/qwen3.5-35b-a3b:nitro`, `thinking: {type: disabled}`, `max_tokens: 2048`, and
`provider: {require_parameters: true}`. Both report zero reasoning tokens. This
is not the previous reasoning-only failure returning under a different name.

| Call | Provider | Attempt | Output tokens | Output shape |
| --- | --- | ---: | ---: | --- |
| `31b0929a-e331-40e0-b9aa-893e464dc7c3` | Venice | 25.494s | 2048 | 7650 characters; JSON parser finds extra data at character 980; starts with an object but does not finish with a closing brace |
| `d2135f97-e093-476e-9e26-2972467c9cb6` | Venice | 21.815s | 2048 | 6662 characters; unterminated string beginning at character 154; no final closing brace |

The outputs contain 1466/1618 words but only 207/92 unique words respectively,
consistent with repetitive or overlong generation. These counts alone do not
identify the exact semantic cause. Raw private prompt/output text was not copied
into this report. The game timed out while these responses were still running;
even if their full output had arrived, the archived bodies were not single valid
complete JSON values.

For the first outlier, the independently collected raw Broadcast timeline shows
first token at 1.721s, body end at 25.436s, and 23.715s after the first token.
Routing took 10ms and the approximate attempt-minus-provider residual was 58ms.
The second outlier reached its first token at 1.042s, then spent another 20.711s
finishing the body; routing was 5ms and the local residual was 61.6ms. Neither
used provider fallback. Both long tails are upstream generation/delivery, not
startup scheduling. All 108 raw traces were found in the complete
[timing collection](../../../tmp/heartleaf-eval/20260908-nitro-timing/breakdown.json).

All 108 request archives preserve the intended model slugs and 2048-token cap.
Qwen has thinking disabled throughout; GPT has no low-effort override. The
existing backend passes `:nitro` through without a backend change. Haiku remains
an unchanged control.

## Privacy, budget, and cleanup

Before the paid submission, authorized readback found no active evaluation XP
and zero running personal XP requests. Existing metered Heartleaf-eval spend was
$0.5284003225; the canary projection was $3, below the unchanged $10 cumulative
soft stop. Personal credit allowance was sufficient. This was the only paid
submission in the Nitro track.

All six uploaded images were read back as ready, without a public image URI,
and not bundled Coworld images. The existing three control images passed the
same scope checks. Authoritative XP SQL verified `private=true`,
`league_id=null`, and the dedicated evaluation world. No league membership was
created. These checks verify stored privacy configuration and team-authorized
access; this run did not add a fresh independent ordinary-non-team denial test.

Provider billed cost is **$0.20714325**, across all 108 reconciled calls with
no missing provider prices. At 00:47:06 UTC, the separate world usage meter still
showed the unchanged prior $0.5284003225: this canary's world-meter ingestion had
not caught up. A conservative known subtotal, pending that reconciliation, is
$0.7355435725. Do not add the provider subtotal a second time after it appears in
the world meter. Unmetered or lagging compute remains unknown, not zero.

Cancellation was confirmed as terminal `cancelled`; a subsequent Kubernetes
read found **zero remaining pods** for the only job attempt. There is no accepted
terminal game result, hosted final-score claim, or coverage credit. No replacement
was submitted.

## Verification and artifacts

Before the paid canary, an exact-image local nine-seat mock completed with nine
accepted souls, nine terminal scores, and successful replay validation. The
42 offline driver contract tests passed. The first local mock invocation failed
because the existing evidence sanitizer removed the public JSON-schema key
`tokens`; retrieving the unsanitized public manifest for local execution fixed
that diagnostic artifact. Both logs were retained. This did not change the
hosted manifest or bypass a runtime check.

All private evidence is ignored under `tmp/heartleaf-eval/20260908-nitro/`:

- `batch.json`: source hashes, nine exact policy IDs, six new image digests.
- `requests/`: exact request, durable submission intent and response.
- `privacy-readback.json`, `evidence/scope.json`, `routing-readback.json`.
- `local-mock/`, `local-mock.log`, `local-mock-retry.log`, `upload.log`.
- `calls.json`, `routing-archive-shapes.json`, `outlier-output-shapes.json`.
- `live/`: preserved game and all nine player logs.
- `latency-summary.json`, `final-evidence.json`, cancellation records.

The ignored operator `tmp/heartleaf-eval/nitro_operator.py` reuses the existing
upload CLI, scope checks, request constructor, and read-only telemetry helpers.
It does not create a new backend path. Do not rerun submission under this batch
identity; preserve its cancelled intent and use a separately reviewed experiment.

## Recommendation

Keep GPT `:nitro` as a strong candidate: this sample removes the previously
observed long generation tail without changing its reasoning settings. Do not
claim Qwen `:nitro` solves the deadline problem. Its remaining failure is overlong,
invalid output on one routed provider, not simply slow first-token latency.
Compare a faster non-thinking replacement or a supported constrained-output/
provider option in a new bounded experiment. A smaller output cap alone could
trade timeouts for invalid truncated actions; it is not proof of success.
