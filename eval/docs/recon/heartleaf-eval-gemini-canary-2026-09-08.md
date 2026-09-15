# Heartleaf: transport-fixed Gemini canary

September 8, 2026 Pacific; hosted evidence September 9 UTC.

## Outcome

The one-day hosted canary **completed with 105 usable actions from 105 calls**,
all nine souls accepted, and no timeout, truncation, empty-text, or provider
error. The slowest attempt was 3.792 seconds. This passes this canary's latency
and usable-action checks, not a guarantee for future requests or a completed
seven-day evaluation milestone.

**The strict team-only privacy requirement is not met.** An independent
unauthenticated request by the main investigation retrieved the completed
episode's replay artifact with HTTP 200. The XP row is private, but the replay
link does not enforce that access boundary. Further hosted XP is on hold for
user direction. The public artifact URL is deliberately not reproduced here.

## What ran

The same three frozen soul bodies were used with Haiku 4.5, Gemini 2.5
Flash-Lite, and GPT-OSS-120B Nitro. Three new private Gemini policies replaced
the Qwen policies; the three Haiku and three GPT Nitro policies were reused.
Only the model header changed in the three replacement soul files; raw body
bytes were preserved. Legacy `S*-Q` keys remain schedule identifiers but now
refer to Gemini, not Qwen.

- World: `heartleaf-eval:0.1.5`, certified canonical
  `cow_88c0215f-6f90-42ec-826c-c1729312e494`.
- Game image:
  `public.ecr.aws/q5f4m8t9/cogames@sha256:4a186a7cf10ce05fc94fa57b05ff8e8ded6a0d235ef18a530792a63848aface0`.
- XP: `xreq_deaa18ed-a132-44ad-b195-06468cfa4c49`.
- Episode request: `ereq_75fe3891-cfc9-45ca-964b-7b63ad344282`.
- Completed episode: `3e74fc46-f341-4764-b008-00b11624f389`.
- Only job attempt: `da00a452-89a2-4b91-88be-5b467ab831e4`.

The new world contains the separately verified client transport fix. No backend
change was made for this experiment. The shared output cap remains 2048 tokens
and the client deadline remains 20 seconds. Seed 91001, one day, nine seats,
and real replies were pinned. `daySeconds=180` is the simulation configuration,
not a claim that the hosted process spent three wall-clock minutes in the day.

## Measured latency and action results

| Model | Calls / usable actions | Median attempt | Maximum attempt | Median first token | Median after first token |
| --- | ---: | ---: | ---: | ---: | ---: |
| Haiku 4.5 | 35 / 35 | 1.501s | 2.563s | 0.676s | 0.767s |
| Gemini 2.5 Flash-Lite | 36 / 36 | 0.630s | 1.572s | 0.364s | 0.213s |
| GPT-OSS-120B `:nitro` | 34 / 34 | 0.470s | 3.792s | 0.137s | 0.207s |

Gemini used Google and produced zero reasoning tokens. GPT used Cerebras and
retained default reasoning behavior. Haiku used Amazon Bedrock through
OpenRouter. All 105 provider records reconciled from Broadcast, and all 105
request archives preserve the intended model slug, 2048-token cap, and
`provider.require_parameters=true`. Gemini had no explicit thinking override.

Durable game stdout independently confirms every reply's outcome was `usable`:
105 usable actions, zero client timeout messages, zero empty-text errors.
Each seat produced 11 or 12 actions, with observed game-side maximum reply
times between 0.6 and 3.8 seconds. Transport-level success was not used as a
substitute for usable game actions.

For each seat's first request, the interval between the game's logged request
`now` timestamp and OpenRouter's earliest provider start was approximately
**10–58 milliseconds**. The old multi-second startup delay was not observed.
This is a cross-clock comparison using the game's frame/request timestamp,
not an exact measurement of client socket time.

These results change both transport and one model relative to the preceding
Nitro experiment. They are a successful combined canary, not a controlled
estimate of how much each change contributed. The separate local transport
reproduction isolates that code change.

## Terminal results and replay

The request reached `completed`. The durable results artifact contains day 1
and nine scores in slot order: `0, 0, 6, 0, 0, 0, 18, 0, 6`. This short canary
does not support a model-quality ranking, and it does not count toward the two
required full seven-day pair meetings.

The durable replay was downloaded through authorized S3 access and parsed with
the project's actual Nim replay codec. It is 75,443 bytes, with nine joins,
47 chat records, 1,689 input records, and 4,560 tick hashes. Parsing succeeded;
there was no hosted visual playback test in this track. Exact-image local mock
replays passed the CLI's replay validation before the paid submission.

The first live snapshot missed the short-lived game pod, so its helper reported
zero usable actions from an absent live log. That was an evidence gap, not a
game failure. The completed job's durable `logs.txt` was subsequently retrieved
and its game stdout decoded, establishing the 105 usable actions above.
`final-evidence.json` supersedes those incomplete live-log counts.

## Privacy finding

Authoritative SQL confirms `private=true`, no league target, and the dedicated
evaluation world. All three newly uploaded Gemini images were read back as
ready, without a public image URI, and not bundled Coworld images; existing
control images passed the same scope checks. No league membership was created.

Nevertheless, the replay artifact was downloadable without authentication.
Inspection of this exact replay found **zero debug/conversation records**, zero
full extracted-soul-body matches, and zero system/assistant-role markers. It
contains gameplay chat, but this inspection did not find full soul prompts.
That limits the observed exposure; it does not make the access-control failure
acceptable or prove other artifacts and future replays are safe. Do not expose
the artifact URL, and do not claim end-to-end team-only privacy from the private
XP flag alone.

## Spend, checks, and cleanup

Pre-submission metered cumulative spend was $0.7490175725. The $3 canary
projection remained below the unchanged $10 cumulative soft stop, personal
allowance was sufficient, and there were no active evaluation XP requests.
Exactly one paid canary was submitted after the main agent released the
certified transport-fixed version.

All 105 provider prices reconciled, totaling **$0.17858017**. The completed job
reports **$0.006907 compute**, for a measured canary total of **$0.18548717**.
The world meter initially lagged the provider subtotal. At 01:11:58 UTC it
caught up to **$0.9345047425 cumulative**, an increase of exactly $0.18548717
from the pre-canary reading, matching provider plus job compute. Do not add
the provider amount again: these are overlapping views of the same spend.
Unknown prior certification/cancelled compute remains unknown.

The completed job had **zero remaining Kubernetes pods**. No replacement or
full evaluation game was submitted.

Before upload and submission, the repository was refreshed at
`ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`, matching `origin/master`, with existing
dirty changes preserved. Project-local Coworld 0.1.46 and Softmax CLI 0.26.32
were current. Two nine-seat local mocked runs passed: first uploader/header
packaging on 0.1.4, then the exact 0.1.5 game and final cohort. Both had nine
accepted souls, terminal scores, and replay validation. The local 0.1.5 manifest
omitted only the asserted default `player_runtime=platform-hosted` field that
the latest released CLI does not yet recognize; the hosted world was unchanged.

## Evidence and next decision

Private ignored artifacts live under `tmp/heartleaf-eval/20260908-gemini/`:
`batch.json`, `uploads/`, `requests/`, `privacy-readback.json`,
`evidence/scope.json`, `routing-archive-shapes.json`, `calls.json`,
`durable-logs.txt`, `durable-results.json`, `durable-replay.replay`,
`job-result.json`, and `final-evidence.json`. The sibling
`20260908-gemini-timing/` holds all 105 raw timing summaries. The preparation and
execution operator is `tmp/heartleaf-eval/gemini_operator.py`.

Keep the successful latency result, but stop further hosted experiments until
the user decides how to handle the replay-access limitation under the existing
no-backend-change constraint. Full-duration coverage, broad latency-tail
confidence, and complete historical accounting remain separate outstanding
milestone work.
