# Local Claude subscription playtests

The optional bridge runs gnomes through the installed Claude Code CLI and its
existing Claude.ai subscription login. It binds to localhost, disables Claude's
tools/customizations, and converts Heartleaf's model requests into print-mode
prompts. No Bedrock credentials are needed for this route.

The game still owns every action, observation, conversation, interview and replay.
This is a local development transport, not the production model backend.

## Start a game

First verify that `claude auth status` reports a Claude.ai subscription login.
Build/install the repository's locked Nim dependencies as usual. From the repository
root, start the bridge in one terminal:

```sh
python3 tools/claude_subscription_bridge.py \
  --model haiku --port 8099 --max-parallel 9 --timeout 300 \
  --trace out/claude-playtest/bridge-trace.jsonl
```

In a second terminal:

```sh
env -u HEARTLEAF_MOCK_REPLY \
  AWS_ENDPOINT_URL_BEDROCK_RUNTIME=http://127.0.0.1:8099 \
  BEDROCK_TIMEOUT_SECONDS=300 \
  HEARTLEAF_INTERVIEW_TIMEOUT_SECONDS=300 \
  HEARTLEAF_CONVERSATION_TICK_SECONDS=300 \
  HEARTLEAF_PLAN_TURN_MINUTES=60 \
  HEARTLEAF_CONVERSATION_GAP_MINUTES=4 \
  HEARTLEAF_UNUSABLE_AS_WAIT=false HEARTLEAF_TIMEOUT_AS_WAIT=false \
  nim r tools/play.nim --days:1 --seed:20260914 --port:8084 \
    --no-browser --log-dir:out/claude-playtest
```

The game seats the nine normal example souls, then writes `game.log`, per-gnome
logs and `heartleaf.bitreplay` under the log directory. The bridge records model
results, provider/model IDs, call durations and failures separately. Stop the bridge
with Ctrl-C after the game finishes. The map seed is repeatable; model replies are
not deterministic.

To watch a completed recording without calling a model:

```sh
out/heartleaf --load-replay:out/claude-playtest/heartleaf.bitreplay --port:8084
```

Open `http://localhost:8084/` on that machine. The same replay can be copied to
another machine running the PR's viewer.

## Timing and interpretation

This profile keeps the normal game cadence: hourly planning and four game minutes
between conversation slots. Only the wall-clock allowances for local model calls
are extended. Do not slow the game cadence merely to reduce CLI calls: the older
two-day recording used three-hour plans and hourly conversation slots, which
amplified visible waiting after completed tasks.
Conversation slots remain enabled: gnomes already talking skip ordinary planning
calls, so disabling conversation slots would prevent normal replies.

Our first attempt used short waits. Every first-night interview missed the 45-second
deadline and the neutral fallback kept every pair at 0.5. CLI request time can be
much longer than model generation time, and old requests can still occupy the
request budget after the game stops waiting for them. The profile above gives local
conversation turns and bedtime interviews up to 300 seconds,
with at most nine CLI calls running concurrently. The ordinary interview default
stays 45 seconds; its override is bounded to 5–300 seconds.

The CLI does not expose an equivalent to the Bedrock output-token cap. The bridge
records the requested cap and `max_tokens_enforced: false`; it does not pretend to
enforce it. It explicitly requests no extended thinking with
`MAX_THINKING_TOKENS=0`, matching Heartleaf's ordinary non-thinking requests, and
records `thinking_requested: disabled`. The coding CLI's default thinking budget
otherwise produced thousands of output tokens for short JSON actions and greatly
lengthened local playtests. See [Claude's documented environment setting](https://code.claude.com/docs/en/env-vars).
Transcripts are passed as labelled messages in a print-mode prompt.
These transport differences and a small sample limit what this playtest
establishes about normal league behavior. A completed replay with valid hashes
does not by itself prove healthy agent behavior: inspect the decisions and watch
the episode, including dinner and every bedtime ranking.

Tests for the bridge use mocked subprocess results and do not spend subscription
usage: `python3 tests/claude_subscription_bridge_test.py`.

The recorded two-day evaluation, its failure cases and behavioral observations are
[available here](connections/claude-observations.md). Reproduce its offline viewer
frames with `nim r tools/render_connection_replay.nim docs/connections/claude/two-day.bitreplay out/claude-review`.

## PR replay evidence

For a Heartleaf PR, include a reviewed replay link and its source/replay hashes
in the PR description. Behavior changes need a fresh real episode; viewer-only
changes may reuse a clearly identified recording rendered with the new viewer.
Watch early, middle, dinner and bedtime stages, inspect movement against the
actual decisions, and exercise mixed playback controls. Do not treat a successful
build or matching simulation hashes as a substitute for watching the replay.

The [September 14 review](connections/review-2026-09-14/README.md) is a complete
example with a public interactive viewer and MP4 video. Publish a new immutable
revision directory on the existing `codex/replay-pages` branch; preserve old links.
Share only the portable recording, viewer/video and curated evidence, not local
provider logs or credentials. Record unsuccessful outcomes and remaining model
limitations alongside the successful checks.
