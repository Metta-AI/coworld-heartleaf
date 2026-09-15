# Movement and conversation-release diagnosis

Status: diagnosis and full-day acceptance are complete. The exact PR baseline
failure is covered by a regression, and two complete ordinary non-thinking
episodes reached bedtime with nine schema-valid interviews and one connection
update each. The final reviewed episode made 247 real model calls with no model
failures and produced replay SHA-256
`4c94b0f342fe983fec94f8939a0734df3741b4099cecb435cc5d8097bdf921fb`.

## Confirmed release/replan failure at the PR baseline

The exact PR 51 baseline (`15364fe`) leaves a departing speaker and the dissolved
singleton with their old conversation decisions. `tests/conversation_replanning.nim`
reproduces the failure with a three-gnome fixture: Vova says `bye` during an active
movement turn, both released members should request new plans, the untouched third
gnome should retain its existing plan, and a late reply from the abandoned
conversation request must not overwrite either new plan.

Running that test in a detached worktree at `15364fe` compiled and failed at the
first release assertion:

```text
conversation_replanning.nim(75, 1) `released.paused` 
```

No post-conversation requests were made on the baseline. With the current change,
the same regression passes: both released seats receive new request tags in the
same movement tick, the third seat receives no request and keeps its plan, and the
late abandoned reply is rejected as stale.

The relevant fix points are `releaseConversation` in
`src/heartleaf/brains.nim:381`, explicit/singleton release in `leaveEncounter` at
line 472, silent release in `dissolveSilent` at line 596, request scheduling during
movement at line 858, and the readiness holds in `advance` at lines 1048, 1063,
and 1083. `handleReply` sets `turnReady` before applying `bye` at line 741, so the
release helper's `turnReady = false` survives the accepted farewell. Clearing the
pending talk target/message and abandoning the old request prevents a released
gnome from walking back to the ended chat or accepting a reply composed for it.

## The old bottom-edge pile is not a navigation boundary failure

In the published two-day recording, all garden food was gone at tick 629
(10:40am), but gatherers did not yet consider their action complete. Anton reached
`(499,892)` at tick 830. Yura and Sasha reached `(499-500,892)` by tick 924, and
all three remained there until the noon plan turn at tick 1080. The point is a
valid reachable point near garden 9, whose rectangle is `(588,897,9,9)` and whose
center is `(590,901)`. It is about 91 pixels from the garden center, within the
96-pixel collection radius.

This follows the gather executor exactly. `gardensExhausted` in
`src/heartleaf/executor.nim:185` is per gnome: after visible food disappears, each
gnome still has to mark every garden checked. `gardenGoal` at line 206 visits the
remaining unchecked gardens and calls `pathNear(..., CollectActionRadius)` at
line 252. Once the checklist is complete, `decisionGoal` returns an outdoor idle
goal at line 625. The Actions section of `src/heartleaf/prompt.nim` describes the same behavior:
gatherers check every garden, then stand still.

At noon the old run started a conversation at that already shared position:
Anton chose `talk_to Yura`, Sasha chose `talk_to Anton`, and encounter 1 formed at
tick 1080. The old evidence profile used 180 game-minute plan turns and 60-minute
conversation gaps (`docs/connections/claude/manifest.json:27-29`), so both the
pre-noon idle and the later conversation were visually long. The sparkle-ring
code does not move agents: `outdoorConversationFeet` in `src/heartleaf.nim:1916`
only reads feet, and `placeEncounterCircle`/`encounterCircles` in
`src/heartleaf/encounters.nim:152` only stores and renders an anchor.

The old pile therefore combines deterministic convergence on the last unchecked
garden, expected end-of-action waiting, slow 180-minute replanning, and then a
conversation at the same location. It is separate from the confirmed stale-plan
bug after a conversation ends.

## First normal-timing episode: engine release fixed, behavior still looked stuck

Run: `out/claude-subscription/run-9g-normal-20260914/heartleaf.bitreplay`, nine
unchanged souls, seed 20260914, 60-minute planning, four-minute conversation gap.
The run was stopped and preserved at tick 1895 (2:15pm) rather than presented as
a successful full episode.

All nine agents gathered at 9:00am. At tick 270 (9:45am), they occupied multiple
parts of the map; nobody was at the old `(500,892)` endpoint. At tick 360 (10:00am)
all nine received the scheduled hourly plan request. Eight chose social actions
and Egor chose `wander`, producing three active conversations at distinct map
positions rather than one bottom-edge pile.

The first real release validates the fix. Vova returned `bye` at tick 479, and
both Vova and the singleton Nikita logged `conversation exit` at that same tick.
Their replacement plan requests started immediately at tick 479. Nikita's reply
arrived in 6.5 wall seconds and Vova's in 10.4 seconds; both chose
`gather_plants`. Simulation time remained at 10:15am during the hold. On the next
simulation tick, both began moving away from their conversation positions:
Nikita moved from `(232,460)` at tick 479 to `(255,517)` by tick 504 and Vova from
`(215,424)` to `(235,481)`. At tick 551 they were still moving at approximately
`(257,538)` and `(264,539)`. Their farewell bubbles remained visible while their
new plans executed.

Through tick 719, every stationary group corresponds to an active recorded
encounter: Anton/Dima/Ivan near `(329-354,235-266)` and Yura/Sasha/Maxim near
`(469-497,483-491)` until Sasha left. Sasha's 10:50am `bye` produced a replacement
request at the same tick; her `gather_plants` reply arrived 8.7 wall seconds later,
and she moved from `(497,483)` to `(496,371)` by tick 719. Egor's `wander` and
released Nikita/Vova also continue to change position. No unexplained action or
navigation stall has appeared in the observed portion of the fresh episode.

Later releases behave the same way. Sasha's `bye` from Egor at tick 839 released
and replanned both members at that tick; both selected `gather_plants` and moved.
Maxim's `bye` at tick 959 released both Maxim and Yura, their replacement requests
started at tick 959, and they traveled about 336 and 345 pixels respectively by
tick 1079. Anton's `bye` at tick 983 immediately requested a replacement plan; he
selected `follow Ivan` 9.3 wall seconds later.

A per-tick position audit through tick 1103 found movement for every agent outside
an active conversation. Between ticks 480 and 719, released Nikita and Vova
traveled about 709 and 706 pixels, while Egor traveled 765 pixels. During ticks
840-959, Sasha, Nikita, Vova, and Egor traveled about 393, 375, 392, and 335
pixels. The fixed positions in those intervals belong to the two active groups:
Ivan/Anton/Dima at `(329-354,235-266)` and, until the tick-959 farewell,
Yura/Maxim at `(469-496,485-491)`. Replay expansion reports no hash mismatch, and
the live log contains no model or simulation error through tick 1103.

The later trace showed a different problem that still made healthy engine state
look broken. Encounter 3 kept Dima and Vova, and later Sasha, stationary for more
than 15 conversation turns. The dialogue repeatedly promised movement without
ending the modal conversation: examples included “Off to creek,” “Let's find,”
“Four of us dig … Come!,” and “let's go” from ticks 1127 through 1223, followed
by further “ready,” “dig,” and “lead” variants through tick 1559. A `say` action
cannot move a speaker, so those statements produced no departure even though
requests, replies, and conversation turns remained live.

The same run also showed a completed gather action being selected again. All
garden food was gone by 9:45am. Nikita had exhausted the per-gnome garden
checklist and reached `goal idle` at 11:50am, then chose `gather_plants` again at
noon. The pre-change report listed foods still wanted but did not state whether
food remained or whether that gnome's daily search was complete. This was a
feedback gap, rather than a pathfinding failure.

The contained follow-up makes the existing mechanics explicit: speech never
moves anyone, and a gnome should say `bye` after agreeing to carry out a movement
plan so it immediately receives a fresh movement choice. The action report now
distinguishes food remaining, globally empty gardens with unchecked stops, and a
completed daily checklist. It uses only the existing village food observation
and that gnome's own checklist. It does not add forced wandering, a conversation
cap, new simulation state, changed rewards, or changed action behavior.

## Second same-seed episode: incomplete diagnostic under default CLI thinking

Run: `out/claude-subscription/run-9g-feedback-20260914/heartleaf.bitreplay`, with
the same nine soul files, seed, and 60/4-minute timing as the first run.

By 10:00am all garden food was gone and planning reports explicitly said so.
Maxim and Yura chose `wander` while citing empty gardens; Anton also chose
`wander` to meet and trade. Two early conversations ended normally after plans
were settled. Ivan said `bye` at tick 527 (10:25am); Ivan and Dima both exited,
received replacement choices at the same tick, chose `wander` while citing the
exhausted gardens, and moved. Egor said `bye` at tick 551 (10:30am); Egor and
Sasha likewise exited, replanned immediately, chose `wander`, and moved.

A larger food-and-dinner conversation formed near Yura's garden. Through tick
1055 (11:55am), its speech remained responsive to newly arriving gnomes,
specific food offers, competing dinner invitations, and a personal cooking
question rather than repeating a movement promise. It nevertheless reached 29
turns and seven members. Those members were stationary because the encounter was
active, but a long novel group conversation still looks like a clustered stall
in the replay. This remains a visible behavior limitation even when the engine
is operating correctly.

Egor then said `bye` at tick 1055, exited, received a replacement request at the
same tick, returned `go_home` 4.8 wall seconds later, and started toward house 9.
That is direct evidence of an agreed plan becoming an actual departure. His
reason incorrectly called 11:55am “nearly dinner time at six”; the noon clock
message corrected the interval to six hours, although he still chose to prepare
at home early. Time judgment and long intentional home waiting are model behavior,
not movement-engine stalls.

This run is not full-day acceptance evidence. Its Claude CLI child inherited an
extended-thinking default and emitted thousands of hidden reasoning tokens per
turn despite the game requesting a short decision, making each five-minute turn
take tens of wall seconds. It was stopped at tick1223 (12:20pm) and preserved. The completed episodes below
use the same game inputs with the bridge child explicitly configured for ordinary
non-thinking calls; they provide full-day dinner, interview and movement evidence.

## Complete non-thinking episode before membership labels

Run: `out/claude-subscription/run-9g-final-20260914/heartleaf.bitreplay`, source
`38f8919`, with the same seed, nine soul files, 60/4-minute timing, and ordinary
non-thinking Claude Haiku calls. It completed one full day with 239 calls, no
model failures, nine schema-valid bedtime interviews, and one connection update.

All nine gnomes ate in three mechanically successful dinners. Yura hosted Ivan,
Sasha, Maxim, and Egor; Anton hosted Dima; and Nikita hosted Vova. The engine
successfully carried the guests into the correct houses and reported each meal.
This episode also exposed a report defect: a talking gnome saw nearby agents but
could not distinguish the actual conversation members from bystanders. The model
spent five turns asking Nikita questions even though Nikita was outside that
speaking rotation.

The contained report change lists `Conversation members` separately from
`Nearby bystanders (not in this conversation)` and explains that `talk_to` brings
a nearby outsider into the group. It preserves the old `People next to` report
when no conversation is active. The regression constructs a real encounter with
one member, a nearby nonmember, and a distant nonmember, so it verifies group
membership rather than only matching prompt wording.

## Final reviewed episode

Run: `out/claude-subscription/run-9g-reviewed-20260914/heartleaf.bitreplay`, source
`1141ef2`, with the same seed, souls, timing, and non-thinking inference profile.
It completed at tick 4320 with 247 calls, no model failures, nine schema-valid
interviews, and one connection update.

The new membership report changed real choices in the intended way. At 10:10am,
Nikita's report identified Ivan as a nearby bystander and Nikita used `talk_to
Ivan`, bringing him into the group. At 10:45am Nikita similarly used `talk_to
Anton`; later Nikita used `talk_to Yura` when Yura was identified as a bystander.
The reviewed trace did not repeat the earlier pattern of directing questions at
an outsider without first adding that gnome to the conversation.

Conversation release produced immediate, executable movement plans throughout
the day. Sasha said `bye` at tick 527 and immediately chose `wander`. Anton's
tick-575 farewell released both Anton and Dima, and both chose `wander` in the
same simulation tick. Yura's tick-599 farewell likewise produced new `wander`
plans for Yura and Maxim. Later, Egor left at tick 1343 and chose
`go_to_house Vova`; Ivan left at tick 1751 and chose the same destination;
Nikita left at tick 1775 and followed them; Vova left at tick 1799 and chose
`go_home`; Anton left at tick 1919 and chose `go_home`. These are recorded
actions and arrivals, rather than inferred intent from dialogue.

The largest midday encounter still lasted many turns and grew to eight members.
It remained live and responsive, with new food offers and conflicting dinner
plans, but it looked like a stationary cluster in the replay. This is an honest
visible behavior limitation: the model may sustain a long social exchange even
when navigation and request handling are healthy. The trace also includes an
incorrect time estimate from Ivan at 12:55pm and several inconsistent hosting
commitments. These are model coordination errors, not failed movement actions.

At 4:00pm every outdoor agent received the dinner warning. By 5:00pm Vova, Ivan,
Nikita, and Egor were inside Vova's house, while Anton and Dima were inside
Anton's. Yura and Maxim went inside Egor's house based on Egor's earlier hosting
offer, but Egor had instead accepted Vova's invitation. No dinner was served at
Egor's. Sasha chose `wait` outside Egor's garden, incorrectly expecting that to
enter the house, and missed dinner outdoors. The resulting mechanical outcomes
were six gnomes fed and three missed: Vova hosted Ivan, Nikita, and Egor for +18;
Anton hosted Dima for +4; Yura and Maxim received explicit no-host reports at
Egor's; and Sasha received an outside-at-6pm report. The failed table therefore
came from contradictory choices that executed as requested, not from an agent
being unable to reach a destination.

The bedtime interviews were all structurally valid, but structural validity does
not guarantee factual grounding. Several rankings accurately used the recorded
outcome: Maxim and Yura placed Egor last for missing his hosting promise, Dima
ranked Anton first for hosting, and the Vova-table guests ranked Vova highly.
Other reasons misremembered events. Ivan and Nikita both claimed Sasha attended
Vova's dinner even though her dinner report says she was outside, Anton described
Egor as switching to host with Yura even though Egor ate at Vova's, and some
reasons described food trades even though the game has no transfer action. Those
are model-memory limitations; the connection update faithfully applied the
submitted rankings.

No automatic wander fallback, forced conversation cap, or strategy rule is
justified by these traces. The normal hourly plan boundary already gives a fresh
choice after a completed action, and the release fix gives an immediate choice
after conversation departure. Across the final reviewed episode, stationary
periods correspond to an active encounter, a selected `wait` or house action, or
a completed movement endpoint. No unexplained navigation or action-engine stall
was found.
