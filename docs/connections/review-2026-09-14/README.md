# Connections: fresh episode and movement review — September 14, 2026

[Play the public replay](https://solbiatialessandro.github.io/coworld-heartleaf/pr-51/a5b6e6c/) ·
[Watch the video](https://solbiatialessandro.github.io/coworld-heartleaf/pr-51/a5b6e6c/watch.html) ·
[PR #51](https://github.com/Metta-AI/coworld-heartleaf/pull/51)

A complete, fresh **nine-gnome, one-day episode**, using real Claude Haiku 4.5
subscription calls and the unchanged example personalities. No mock replies,
scripted decisions, or edited game outcomes. Game source: `1141ef2`; viewer:
`a5b6e6c`. The viewer repair does not change the recorded decisions.

## What was fixed

- **Stale plans after leaving a conversation:** departing gnomes and dissolved
  singletons get a fresh decision immediately. Old in-flight replies cannot
  overwrite it; unrelated gnomes keep their plans.
- **Missing action feedback:** the prompt distinguishes speaking from movement;
  garden observations say when gathering is complete or no food remains.
- **Bystanders mistaken for conversation members:** reports name the actual
  speaking group separately and explain how `talk_to` invites someone nearby.
- **Dialogue lost or repeated across scenes:** the director reads final lines
  on their actual map before curfew, preserves read history through dinner cuts,
  and includes a farewell recorded on the conversation's exit tick.
- **Wrong relationship on a card:** the named connection is with a recorded
  conversation peer, rather than the first nearby bystander.

The final Dima farewell regression fails before the viewer fix and passes after
it. Simulation hashes remain unchanged. The local Claude bridge also disables
unrequested extended thinking for ordinary actions; this changes inference
configuration, not game mechanics.

## What happened in the final episode

**247 successful model calls, zero transport/model-call failures, nine
schema-valid bedtime interviews, one atomic connection update.** Normal cadence:
60 game minutes between planning turns and four between conversation turns.
Seed `20260914`. Generous 300-second wall deadlines accommodate the local bridge.

No unexplained navigation or action-engine lock was observed. All 14 `bye`
actions triggered fresh decisions at the departure tick. Long stationary scenes
were active conversations, completed gathering, early arrivals or chosen waits.
The largest conversation grew to eight members; its continuing dialogue is
visible in the replay. Eight redundant or no-longer-applicable `wait` replies
were ignored by the runtime; that is distinct from model transport failure.

**Six gnomes ate; three missed dinner.** Vova hosted Ivan, Nikita and Egor; Anton
hosted Dima. Yura and Maxim waited inside Egor's house while Egor dined at Vova's.
Sasha chose to wait outside Egor's garden instead of entering. These are model
planning mistakes, preserved in the recording rather than hidden or forced away.

Some rankings reflect those outcomes: Yura and Maxim put Egor last, Dima rewards
Anton, and Vova's guests reward Vova. Other reasons contain mistaken memories
about attendance or invented food trades. Schema validation does not establish
factual truth. This episode did not select `send_emoji`; reaction handling and
rendering remain covered by the separate authored fixture. This single uncontrolled episode does not show that connections
cause cooperation or prevent game exploitation.

## Replay evidence

Use **Night 1** to jump to the end-of-day ranking scene. Each gnome has its own
ranking and reasons, followed by the visible **Connections updated** summary.
The graph remains closed unless **Debug: connections** is explicitly opened.

An independent subagent drives the real replay entry point continuously, samples
the rendered output every ten presentation seconds, and separately captures all
nine ranking pages and the update. Native captures compose the actual persistent
sprite packets; Chrome controls and public video playback are checked separately.
The completed native sweep has **74 checkpoints over 727.6 seconds at 1X**
(17,463 viewer frames), all seven conversations and matching simulation hashes.
All 14 goodbye lines now receive reading time; the remaining reconstructed feed
entries were already shown in their own shots, with no globally missing line.
The director plays overlapping conversations in sequence, so the game clock can
rewind when it moves to another conversation. That is expected replay behavior.

- [Final visual review and screenshots](visual-qa.md)
- [Movement and trace diagnosis, including earlier iterations](movement-diagnosis.md)
- [Dinner/curfew regression evidence](viewer-boundary-fix.md)
- [Run manifest and hashes](run-manifest.json)
- [Portable recording](episode.bitreplay)
- [Reproduce a local Claude-subscription run](../../claude-subscription-replays.md)

## Validation and scope

Regression coverage includes departure/stale replies, action observations,
recorded peer labels, departure-tick farewells, dinner/curfew cuts, backward seeks,
all eight speeds, ordered transport combinations, bedtime interviews and updates.
CI also runs the full core, integration, evaluation-tool, native-build and static
WASM checks. The PR reports the status of its current head.

The old bottom-edge pile was a valid garden endpoint plus completed work and
conversation holds, not an impassable map corner. Earlier diagnostic episodes
are retained locally and clearly distinguished in the trace report. The final
recording includes every accepted decision; raw provider logs and authentication
material are not published.

No new map, font, card design, conversation list, forced wandering, conversation
cap, promise bonus or reward shaping. PR51 keeps persistent pair connections,
nightly rankings, visible updates, deliberate pixel reactions, numeric game
points, connection hearts and an optional graph. Further behavior tuning and
multi-seed evaluation are deferred.
