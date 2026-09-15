# Connections

Viewer stability PR #50 is merged. This branch includes master at `4ee856b`,
including PR #52’s evaluation tooling. Bedtime interviews retain their own
validation while ordinary actions preserve the strict evaluation failure policy.
The connections work stays in PR #51.

[Bedtime ranking screenshots](connections/bedtime-review-2026-09-11/README.md) ·
[World and director screenshots](connections/director-repair-2026-09-11/README.md) ·
[Run a real local Claude-subscription playtest](claude-subscription-replays.md).

## Watch the bedtime rankings

At **9pm**, after the day's conversations, the replay holds for a bedtime scene.
Each gnome's portrait opens its ordered ranking of the other gnomes. Select a rank
to read that gnome's recorded reason. Clicking a portrait or rank pauses playback;
Play resumes the sequence. Each gnome gets eight seconds at 1X, followed by the
**Connections updated** screen, with before/after hearts. The left leaderboard
keeps the old hearts through the rankings and switches at the update screen.

The **Night 1** and **Night 2** buttons jump directly to those moments and pause.
The graph stays an optional debug view. Missing or timed-out interviews are
labelled as unavailable, with zero contribution; no ranking is invented.

Both nights, all nine gnome pages and both update screens appear in continuous
playback of the real recording. All 12 conversations and 49 distinct aired lines
remain; the full 1X presentation now takes **12,993 frames (~9 minutes)** including
bedtime reading time. All eight speeds complete with matching simulation hashes.
`tests/bedtime_viewer.nim` also checks page/rank selection, pause, jump, rewind,
next conversation, restart and compact layouts. Reviewed images are actual
protocol renders; browser/GPU interaction is unverified while the Mac is locked.

This uses the existing recorded game. Its sparse decision timing and stationary
gnomes are historical actions, and have not been replaced by a new simulation.

## Director repair — September 11 (before bedtime presentation)

The first public viewer passed simulation hashes but was not watchable at its
normal speed. The real recording spaces many model replies 360 ticks apart;
the director slowed every tick of an open conversation by five, including silence.
The first shot lasted **451.8 seconds**, and a later Yura shot **651.8 seconds**.
The earlier regression fixture had much shorter reply gaps and missed this.

The director now keeps reading time for queued dialogue, advances faster through
empty stretches, and stops on each newly captured line. It drains the last line
before leaving a shot. Playback speed scales the reading clock too; pause still
freezes everything. Old recordings close leftover groups when a new recorded day
starts. The live brains also remove old book membership before the morning reset,
so yesterday's groups cannot keep scheduling the same gnome.

The unchanged real recording now reaches all **12 conversations** in **8,821 frames**
at 1X, with **49 distinct aired lines**; the first shot is **36.7 seconds**.
`tests/real_replay_director.nim` drives the same frame entry point as the static
viewer, checks pause and every conversation, and runs all eight playback speeds.
These are native/protocol checks; browser/GPU click-through remains unavailable
while the Mac is locked. The old game trace is preserved, including its historical
model decisions and interview timeouts.

## What ships

- Each pair of seated gnomes has one shared connection in **[0, 1]**, initially **0.5**.
  Connections persist across days in an episode and reset for a new game.
- At **9pm**, after the day's dinner outcomes have entered each gnome's memory,
  the score screen waits for one bedtime interview per gnome. The model ranks
  every other seated gnome and gives short reasons grounded in that day's events.
- The compact left leaderboard shows **numeric game points** and **ten pixel
  connection hearts**. Heart fill is the average of that gnome's pair strengths
  multiplied by ten: five filled hearts initially, zero through ten overall.
  There are no bars. The existing game reward/winner rules are unchanged.
- Conversation cards keep the original font and 54px portraits. Their identity
  strip says **“Connection with Anton”** (the named listener) above three pixel
  hearts. A 0.5 pair is one full, one half-full and one empty heart.
- `send_emoji` is a deliberate model action targeting a nearby visible gnome:
  `happy`, `very_happy`, `sad`, or `very_sad`. Small pixel faces clear the gnome's
  portrait/body and disappear after their recorded animation. The recipient
  notices the reaction in its memory. Proximity and spoken-turn count no longer
  emit reactions or change the connection score.
- **Debug: connections** opens the full village graph; it is closed by default.
  All nine gnomes and all 36 pairs remain visible. Select a graph portrait to
  highlight its edges, inspect the percentages, last recorded action and bedtime
  ranking/reasons. Long reflections have pages. Close the graph with the same
  debug button. Leaderboard rows have no inspector click action.
- Pair snapshots, interviews, actions and reactions travel inside the replay.
  Both native and static viewers derive them from the playhead, including backward
  seeks and concurrent-conversation rewinds. Old replays remain playable and show
  unavailable relationship data, rather than fabricated interviews.

## Daily arithmetic and edge cases

For a gnome ranking `m` other gnomes, rank 1 is most connected:

```text
contribution(rank, m) = 0.5 - (rank - 1) / (m - 1)
delta(A,B) = (A's contribution to B + B's contribution to A) / 2
new_connection(A,B) = clamp(old_connection(A,B) + delta(A,B), 0, 1)
```

Both first: +0.5. Both last: -0.5. First versus last: zero. Intermediate ranks
are evenly spaced. This is a relative ranking system: a low rank can decrease a
connection even without a deliberately harmful action. Clamping can change the village's
total connection score. There is no separate bonus for promises, dinners, or emoji;
models use those experiences as evidence in their rankings.

Rankings must contain every other seated gnome exactly once, with a nonempty reason
of at most 240 characters each. Ties are not part of this version. Unknown partners
must be ranked honestly as little/no interaction. With zero or one possible partner,
ordinal position provides no contrast, so the contribution is zero.

All changes commit together once per day. Missing, invalid, failed or timed-out
interviews contribute zero, without inventing a ranking. The other gnome's valid
contribution still supplies its half of the update. There is a **45-second overall
deadline** by default. Slow local transports can set
`HEARTLEAF_INTERVIEW_TIMEOUT_SECONDS=300` (bounded to 5–300 seconds); this does not
change the neutral fallback or nightly arithmetic. Requests receive a 1,200-token
output budget through the Bedrock API. Stale responses, including
responses from a prior game, cannot be applied to a new request. Gnomes receive their
old/new pair strengths and the partner's recorded reason for discussion tomorrow.

## Review and validation

The original fixture, `connections/two-day.replay`, is an **authored two-day
scenario with scripted model replies**. It uses normal movement and the actual brain
interview/action handlers. It has nine gnomes, six conversations, eighteen valid
bedtime interviews, two daily commits and twelve deliberate reactions. All 9,120
simulation ticks replay with matching hashes; the full director playback is checked
for stalls. These hashes cover the simulation; recorded connection metadata is
validated and separately tested for correct playhead folding.

```sh
nim r tests/connections.nim
nim r tools/record_connection_scenario.nim out/connections-scenario.replay
nim r tests/connections_viewer.nim out/connections-scenario.replay out/connections-review
nim c -d:release src/heartleaf.nim
out/heartleaf --load-replay:docs/connections/two-day.replay --port:8084
# Open http://localhost:8084/
```

Also checked: core tests, native integration, viewer stability, navigation, ordered
control clicks, eight playback speeds and 64 pause/speed combinations, routes, and
the static WASM build. New viewer checks exercise selection, reflection pages,
pause, next/previous, speeds, end/restart, and forward/backward seeks across days.

The authored fixture does not validate model ranking quality or request latency.
The [current screenshot gallery](connections/director-repair-2026-09-11/README.md) uses the
separate **real Claude replay**, rendered with the latest viewer code. It shows
numeric points, ten Connections hearts, the “Connection with Anton” card label,
and the full debug graph both closed and explicitly opened. These are offline
renders of actual drawing packets; OS/browser click-through remains unverified.

## Real Claude-subscription playtest

A separate nine-gnome, two-day run uses the normal example souls and actual Haiku
4.5 replies through the local Claude.ai subscription. It produced 15 valid bedtime
interviews out of 18: all nine on day one and six on day two. Three second-night
calls exceeded the local deadline and contributed zero. Both daily updates were
recorded. The longer local timing profile differs from ordinary league play.

[Observations and evidence](connections/claude-observations.md) ·
[Run manifest](connections/claude/manifest.json) ·
[Portable recording](connections/claude/two-day.bitreplay)

The run includes an accepted decision explicitly citing a connection value,
a delivered happy reaction, and Dima hosting Vova on day two: Dima earned 15 total (9 from eating plus
6 from hosting), while Vova earned 9 from eating. It also exposes important limits: day-one party warmth was
rewarded despite missed dinners, and mandatory rankings lowered connections
between gnomes who had not interacted. This is descriptive evidence from one
small run, without a no-connections control.

```sh
out/heartleaf --load-replay:docs/connections/claude/two-day.bitreplay --port:8084
```

## Out of scope

Production deployment or merge; tournament reward changes; automatic promise
tracking or event-based point bonuses; ties/absolute ratings; relationship decay;
persistence across separate episodes; the removed right-side conversation list;
and automatic live-model quality evaluation. PR #50's replay control layout, camera
transitions, map geometry, font sizes, muted ground texture and original portrait
pixels are preserved; the director repair above changes pacing through silence.
Its removed logo and bricks are not restored.

The September 14 shipping scope is frozen to the implemented connections and
replay features. Movement replanning, fresh model campaigns, reward/winner
changes and additional UI design are deferred.
