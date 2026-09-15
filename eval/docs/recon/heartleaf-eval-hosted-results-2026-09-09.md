# Heartleaf hosted benchmark results, September 9

## Scope

James accepted publicly downloadable gameplay replays on September 9 and
authorized resumed hosted runs. Extracted souls and submitted policy images
remain private. The $10 soft stop remains in force. No backend changes were made.

Live preflight confirmed certified `heartleaf-eval:0.1.5`, Coworld
`cow_88c0215f-6f90-42ec-826c-c1729312e494`, no league seed, and no active XP.
The game image remains
`sha256:4a186a7cf10ce05fc94fa57b05ff8e8ded6a0d235ef18a530792a63848aface0`.
OpenRouter routing was enabled at 100%. Heartleaf HEAD and `origin/master`
were `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`; project Coworld 0.1.46 and
Softmax CLI 0.26.32 were the latest available releases when checked.

## First full game: completed, acceptance failed

Request: `xreq_9ae948e7-be8c-46ed-b37b-d90e210b0ce2`.
Episode: `330b39b9-2557-4474-9ffa-000f86068a83`.
Job: `69bd00e3-b28d-439d-97b3-9e0b272cb3a0`.
Seed 91002, seven days, nine frozen policies, 2048 output-token cap and
20-second client deadline. Durable results confirm day 7 and all nine scores.

| Ranked source soul | Haiku 4.5 | Gemini 2.5 Flash-Lite | GPT-OSS-120B Nitro |
| --- | ---: | ---: | ---: |
| 1 | 55 | 0 | 6 |
| 2 | 85 | 0 | 29 |
| 3 | 27 | 35 | 9 |

| Model | Calls | Median proxy latency | Maximum | Truncations |
| --- | ---: | ---: | ---: | ---: |
| Haiku 4.5 | 242 | 2.078 s | 5.245 s | 0 |
| Gemini 2.5 Flash-Lite | 247 | 0.758 s | 1.703 s | 0 |
| GPT-OSS-120B Nitro | 251 | 0.622 s | 5.222 s | 1 |

There were 739 parsed replies from 740 calls, but only **633 applied actions**.
The game rejected 106 actions and substituted waiting: 8 Haiku, 90 Gemini, and
8 GPT actions. There were zero client timeouts and one empty-text reply. All provider calls returned successfully at the transport
level; that does not imply usable gameplay output. In particular, the runtime
logs `outcome=usable` even when it subsequently marks `ignored=wait`. Reports
now subtract these ignored replies instead of treating them as applied actions.

The failed GPT reply used 2,045 reasoning tokens out of 2,048 output tokens,
returned no action text, and stopped at the token limit. It was served by
Cerebras and completed in 2.350 seconds. The short canary had not exposed this
failure. GPT has therefore not met the full-game acceptance criterion. The
second scheduled game for this cohort was not submitted.

Measured cost, including compute, is **$1.58431707**. All 740 provider records
reconciled, and the job's compute charge was available. Retained evidence:
`tmp/heartleaf-eval/20260908-gemini/hosted/eval-a/`, including `summary.json`,
`calls.json`, `jobs.json`, `game.log`, `results`, `replay`, and `truncations.json`.

This is one multiplayer outcome with fixed seats, not an estimate of a model's
general strength. The policies interact, and the three souls are not independent
replications of all possible prompts. Do not count this game as accepted pair
coverage: its zero-truncation gate failed.

## Accounting boundary

Pre-resumption metered usage was $0.9345047425, including earlier canaries and
available setup compute. Adding this full game gives $2.5188218125 in known
spend before subsequent screens. Four older cancelled jobs still have no
persisted compute charge. An explicit **$2 budget reservation** is charged
against the unchanged $10 stop for those jobs. That reserve is not measured
cost, and their historical accounting remains unresolved.

The broker catalog was checked first. Hosted API operations used the existing
Softmax login, which the broker does not vend. Kubernetes routing/log reads used
the existing cluster identity; no AWS secrets were fetched or AWS resources
modified. All local evidence remains in the ignored evaluation directory.

## Screening in progress

The first new cohort crosses the same three source souls with Llama 3.3 70B
Instruct Nitro, Gemma 4 31B Nitro, and GPT-4.1 Mini Nitro. Its nine exact Linux
amd64 images passed a mock episode and replay check, were uploaded, and were
read back as private. Request: `xreq_31a4de0e-8964-4351-bf2f-82adda15f713`.

Candidate identities and required request parameters were refreshed against
the [OpenRouter model catalog](https://openrouter.ai/api/v1/models). The
[Llama](https://openrouter.ai/meta-llama/llama-3.3-70b-instruct),
[GPT-4.1 Mini](https://openrouter.ai/openai/gpt-4.1-mini), and
[Ministral](https://openrouter.ai/mistralai/ministral-14b-2512) pages were also
checked. Availability is selection evidence, not a hosted reliability result.
Screen outcomes are retained per seat in each batch's `hosted/canary/summary.json`.

| Candidate | Calls | Applied actions | Ignored actions | Parse / upstream errors | Screening result |
| --- | ---: | ---: | ---: | --- | --- |
| Llama 3.3 70B Nitro | 39 | 33 | 6 | 0 / 0 | Response checks passed |
| Gemma 4 31B Nitro | 39 | 38 | 1 | 0 / 0 | Response checks passed |
| GPT-4.1 Mini Nitro | 38 | 29 | 9 | 0 / 0 | Response checks passed |
| Qwen3 Next 80B Instruct Nitro | 36 | 30 | 6 | 0 / 0 | Response checks passed |
| Ministral 14B Nitro | 41 | 27 | 9 | 5 / 0 | Failed JSON parsing |
| Qwen3 30B Instruct Nitro | 36 | 24 | 12 | 0 / 0 | Response checks passed |

The first two screens cost $0.20541989 and $0.06144420 respectively, including
compute. The second request was `xreq_1e46636e-5bf9-45b5-9723-100ab516592f`.

The third screen, `xreq_33d811d8-33b9-4071-8c82-62e363ece8e1`, completed with
six upstream failures for GPT-4.1 Nano and four for Mistral Small 3.2. GPT-4o
Mini had no upstream failures. Archived error bodies identify provider rate
limits/availability. The ten failed calls have unresolved cost records; the
whole screen's $0.80 projected amount remains reserved against the budget in
addition to known charges, without treating missing cost as zero.

Response checks require positive applied actions for all three seats and no
parse failures, truncations, upstream failures, or deadline failures. They do
not establish the stronger no-persistent-default criterion. Ignored actions
remain explicit quality failures. `acceptance_verified` stays false when ignored
actions occur: no tolerated default rate has been established. Do not silently
interpret these provisional response checks as final cohort acceptance.

The September 8 canary had the same counting problem: 105 parsed replies but
92 applied actions, with 13 ignored actions. Its original acceptance record is
preserved as `acceptance/canary.before-action-metric-correction.json`; the current
record points to `canary-action-metric-correction.json`. The raw historical logs
and cost evidence were retained unchanged.


## Final screening dataset

Five new hosted episodes completed: one seven-day game and four one-day screens.
They produced 1,201 calls, 1,183 parsed replies, 1,002 applied actions, and 181
ignored actions. The remaining 18 calls comprise five parse failures, three
output-cap/empty-text failures, and ten upstream errors. No client timeout was
observed. No automatic retries of an XP request were made.

The ten candidates below passed response checks in their observed runs. This is
not final nine-soul validation. The two seven-day rows had longer histories and
different opponents from the one-day screens; rates are descriptive, not a
controlled model ranking.

| Candidate | Days | Calls | Applied actions | Ignored actions | Median / maximum latency |
| --- | ---: | ---: | ---: | ---: | --- |
| `anthropic/claude-haiku-4.5` | 7 | 242 | 234 | 8 | 2.078 / 5.245 s |
| `google/gemini-2.5-flash-lite` | 7 | 247 | 157 | 90 | 0.758 / 1.703 s |
| `meta-llama/llama-3.3-70b-instruct:nitro` | 1 | 39 | 33 | 6 | 0.602 / 1.458 s |
| `google/gemma-4-31b-it:nitro` | 1 | 39 | 38 | 1 | 0.516 / 0.965 s |
| `openai/gpt-4.1-mini:nitro` | 1 | 38 | 29 | 9 | 1.398 / 3.157 s |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | 1 | 36 | 30 | 6 | 1.067 / 2.057 s |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | 1 | 36 | 24 | 12 | 1.499 / 3.739 s |
| `openai/gpt-4o-mini:nitro` | 1 | 35 | 34 | 1 | 0.921 / 1.800 s |
| `google/gemma-4-26b-a4b-it:nitro` | 1 | 39 | 28 | 11 | 1.478 / 4.472 s |
| `google/gemini-3.1-flash-lite:nitro` | 1 | 38 | 33 | 5 | 0.660 / 1.103 s |

Rejected at this stage: GPT-OSS-120B and GPT-OSS-20B exhausted the output cap;
Ministral produced malformed JSON; Nano and Mistral Small encountered upstream
rate-limit/provider failures. These are results of the tested model/route and
workload, not claims that the models can never work elsewhere.

The reserve request was `xreq_2615db9e-bad2-4c36-aa43-5e629cd2e1ad`; its episode
was `a4a0161e-2b84-429d-b3a5-afe1be8e8042`. Its measured cost was
$0.076526775.

### Downloadable local data

- `tmp/heartleaf-eval/20260909-hosted/model-results.csv`: 15 model-by-game rows,
  including failures, p50/p95/max latency, applied/ignored actions, and cost availability.
- `tmp/heartleaf-eval/20260909-hosted/seat-results.csv`: 45 seat rows with frozen
  policy/source IDs, world version, seed, scores, tokens, and action measurements.
- Matching JSON exports and `episode-results.json` preserve nested measurements.
- Per-batch `hosted/<game>/` retains raw logs, results, replay, call records,
  job attempts, routing, and private-XP readback.

### Frozen expanded candidates and remaining work

`tmp/heartleaf-eval/20260909-top9-ten-models/batch.json` contains the real
90-context Cartesian product from nine ranked sources (eight distinct bodies)
and the ten candidates above. Raw body preservation was rechecked for all 90.
Its 283 planned games cover all 4,005 policy pairs at least twice. No policies
were uploaded from this expanded batch, and its games have not been submitted.

All ten candidates still need verification on the six additional source souls.
The strict no-persistent-default condition is not established; observed ignored
actions must be treated explicitly in the eventual acceptance decision. Expanded
submission/report integration and actual accepted full-game pair coverage remain
unfinished. The prepared Haiku/Gemini/Gemma replacement cohort was not submitted.

The existing $10 cap does not authorize the full expanded schedule. The first
full game cost $1.5843; 283 games at that rate would be about $448, before further
verification. That is a rough scale estimate, not a quote: model mix, prompt
lengths, caching, failures, and provider prices change the cost. A $500 total
limit was proposed to James; no budget increase was assumed.

Known new-run charges total **$1.971310315**, including available compute. Ten
failed-call charges remain unresolved, so this is a known subtotal, not a final
bill. Including the pre-resumption ledger gives **$2.9058150575** in known
charges. The $2 historical-compute and $0.80 failed-screen reservations are
separate budget charges, not reported actual spend.

The local model-validation fix now compares reported models with frozen policy
models, preserving Nitro suffixes rather than interpreting old H/Q/G labels.
All 57 evaluation tests and `git diff --check` pass. No Nim behavior was changed
in this continuation.
