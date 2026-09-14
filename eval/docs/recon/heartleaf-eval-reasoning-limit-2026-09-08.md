# Heartleaf eval: reasoning-limit verification

## Change

Qwen3.5-35B-A3B now receives `thinking: {"type": "disabled"}` through the
existing Converse `additionalModelRequestFields` path. This sets optional
reasoning to zero rather than increasing Heartleaf's deadline. A second revision
tested GPT-OSS low effort through `additionalModelRequestFields.output_config`,
but the hosted route rejected that setting; it was removed. The 20-second
default deadline, 2048 output cap, three souls, nine policies, Haiku settings,
viewer, and canary schedule are unchanged. No backend changes were made.

OpenRouter exposes reasoning controls through its existing API; this change
reuses the game's `ModelTuning.disableThinking` field and the deployed
translator instead of adding another proxy or dependency. See [OpenRouter's
reasoning documentation](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens).
Actual provider compliance and latency must be verified from hosted calls;
disabling reasoning cannot guarantee a network response within 20 seconds.

## Build provenance

The original uploaded manifest identifies source revision
`fa7b3f654174c9c7ddbde412ef610f63484eb487`. The controlled image was built from
a detached worktree at that revision with only the Qwen request change and
its tests. The current checkout at `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`
also contains the patch for review, but its unrelated newer gameplay changes
are not in the controlled build. The original Dockerfile and dependency lock
were used with Linux amd64 and Nim 2.2.4.

An initial current-master image upload had already registered version 0.1.1
when the source mismatch was discovered and the command was interrupted.
Its automatic certification completed and made it canonical temporarily.
No eval XP was submitted to it. The controlled replacement is 0.1.2,
`cow_c334a1c1-e4d8-4cbc-aa02-39526cc32ccf`; automatic certification costs for
both uploads belong in the cumulative spend record. The original Heartleaf
world was not updated.

The driver now permits an explicitly pinned `eval_game_image` while retaining
the original `game_provenance`. A regression test rejects both unrecorded image
changes and a return to the old image under a revised batch.

## Local checks

- 42 eval-driver tests passed; Ruff lint and format checks passed.
- Current-source and controlled frozen-source Linux game builds passed.
- Game unit tests, including reasoning request-shape assertions, passed on
  both source versions in their Docker build environments.
- Current-source socket integration tests passed. The frozen source's socket
  integration test failed at its initial handshake against both the unchanged
  original hosted binary and the patched binary. This is a reproduced baseline
  failure, not a clean integration result.
- The controlled image completed a nine-seat mocked episode with nine scores
  and a successful replay-load check. All nine soul-player logs confirm soul
  acceptance. This proves packaging, not real-model latency.

The host Nim command initially failed because the local workspace lacked the
pinned dependency setup. Tests were run using the repository's real Docker
build stage and its pinned dependencies; no toolchain checks were bypassed.

## Hosted verification

Version 0.1.2 passed all five upload-smoke episodes and all ten certification
steps. Its private canary was `xreq_b2d6ca69-fafb-4757-aec0-5c010cef8505`,
episode `ereq_b080ba78-974b-4da9-add2-cd843fd020c2`, job
`c4bd32a0-ab8d-43e0-90eb-094771ab47e0`.

| Model | Calls | Median | Maximum | Calls over 20 s | Reasoning tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| Haiku | 18 | 1.69 s | 1.96 s | 0 | 0 |
| Qwen, reasoning disabled | 19 | 1.97 s | 13.16 s | 0 | 0 |
| GPT-OSS, default effort | 21 | 8.83 s | 25.10 s | 4 | 6,461 |

All 19 Qwen archives confirm `thinking.type=disabled`, with action text and no
thinking blocks. None of the 58 provider completions was length-limited. The
game log records four deadline failures, all GPT-OSS; the request was cancelled
rather than continuing a failed latency test. All ten pods were subsequently
verified removed. Provider charges were $0.0775436115, excluding unresolved
cancelled-job compute. This is a Qwen improvement, not an all-model pass or
a completed milestone episode.

Version 0.1.3 passed its frozen-source unit suite, all five hosted smoke episodes,
and all ten certification steps. Its real-model canary
`xreq_4a960347-c1fc-45cc-acc0-58220b0200fa` nevertheless failed. The episode
`ereq_9ca0c3c4-9f9b-469d-9a04-26f91fec66f5` had three automatic job attempts:

- `b9e51fdb-8557-4924-83b5-2c345eeb22b9`
- `fc5978ea-08a3-4abd-99d8-f678f08a2e61`
- `8a128813-20fe-4b34-8f3b-3ea568151c96`

Across those attempts, 15 GPT-OSS calls returned HTTP 404. The retained upstream
error identifies `Filter by Parameters` as the failed routing step: all
endpoints were excluded with `output_config.effort=low` and the platform's
existing `provider.require_parameters=true`. This is not evidence GPT-OSS
was removed from OpenRouter; it is failure of this requested parameter shape
on the actual route. No backend or routing-policy setting was changed to bypass
that filter. The cancellation request raced with terminal failure and returned
409, despite the detail projection still exposing `can_cancel=true`; subsequent
readback confirmed `failed` and no remaining pods for any of the three jobs.

Crucially, **Qwen also exceeded 20 seconds with reasoning disabled**:

- Call `cbca51c3-bc41-4768-9585-2cb0ca96aee9`, slot 1, provider Darkbloom.
- Proxy duration 23.528 seconds; reconciled provider duration 23.482 seconds.
- Zero reasoning tokens, only 60 output tokens, normal stop, valid text.

The extra duration was upstream, not translation overhead. There is no lower
reasoning setting than zero to fix this counterexample. Across the second
canary's nine Qwen calls the median was 2.02 seconds, with one over 20 seconds;
all nine Haiku calls stayed below 2.46 seconds. The 15 fast GPT-OSS errors are
not successful low-latency actions. Complete-game latency acceptance remains
unmet. These failed/cancelled episodes contribute no pair coverage or scores.

The unsupported GPT-OSS code was removed from both source worktrees. Version
0.1.4 restores the exact Qwen-only image from 0.1.2 as the eval's current version.
It is canonical and passed all five upload smoke episodes and all ten
certification steps. Its ID is `cow_16f8134d-3c67-4b2a-8ede-2795e746c23c` and
game digest is `sha256:50cfb46390232d83039e6b7f95946e9961bc677a7b3fa8ad684ad1606a48f4be`.
Final readback verified the original Heartleaf manifest hash unchanged and the
restored runnable/viewer identical to 0.1.2. No further paid model canary will
be launched merely to try to obtain a sample without provider tail latency.

## Remaining work

The Qwen reasoning change is implemented and verified, but reasoning limits
alone did not meet the all-request 20-second target. The next investigation
should address provider latency and a supported way to express GPT-OSS low
reasoning through this route. Do not increase the deadline or relax parameter
enforcement without a separate decision. Do not label this milestone complete.

Persisted request records confirm both canaries were private, league-less, and
attributed to their new eval versions. The original Heartleaf manifest hash
was checked unchanged before each canary. No policy/soul uploads were repeated.

Private evidence: `tmp/heartleaf-eval/20260908-reasoning0/`. The prior metered
subtotal was $0.3061909985 before these uploads. The unchanged soft stop is $10;
unmetered certification-parent/cancelled-job compute remains unknown, not zero.
The second revision's evidence is `tmp/heartleaf-eval/20260908-reasoning-low/`.
Final metered world-usage subtotal across all eval versions was $0.50029461.
This remains a partial accounting total: provider ingestion can lag and
certification-parent/cancelled-job compute is not fully priced. It is not a
claim that all work cost exactly fifty cents.

Codebase friction: 3/5. Existing model tuning kept the source patch small, but
mock certification did not exercise actual provider parameter compatibility;
the GPT-OSS routing failure appeared only in the paid canary. Distinguishing
canonical versions, frozen game source, and automatic episode retries also
required separate readbacks.

Project-local tools were checked against available releases: Coworld 0.1.46,
Softmax CLI 0.26.32. No newer release of either was found.
