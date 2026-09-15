## Replay dialogue at curfew must air once, on the map where it was spoken,
## even when dinner-room cuts compete with a committed outdoor conversation.
import std/[importutils, sets, strutils, tables]
import heartleaf, replays
import heartleaf/encounters
import bitworld/spriteprotocol

privateAccess(SimServer)

let
  path = "docs/connections/claude/two-day.bitreplay"
  data = loadReplay(path)
  cfg = data.replaySimConfig()
  sim = initSimServer(cfg.seed, cfg.dayTicks)

privateAccess(typeof(sim.chatFeed[0]))
privateAccess(typeof(sim.chatFeed[0].speaker))
privateAccess(typeof(sim.players[0]))

sim.attachConversationTimeline(data, path)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed, cfg.dayTicks)
replay.looping = false
sim.buildConversationQueue(replay.replayMaxTick())

proc queueIndex(encounterId: int): int =
  for i, span in sim.convQueue:
    if span.id == encounterId:
      return i
  -1

proc speakerMap(name: string): int =
  for player in sim.players:
    if player.playerName == name:
      return player.mapIndex
  -1

proc targetCount(prefix: string): int =
  for item in sim.chatFeed:
    if item.message.startsWith(prefix):
      inc result

let
  farewellPrefix = "Anton's hosting tomorrow at his house"
  farewellQueue = queueIndex(5)
  farewellDeath = sim.convQueue[farewellQueue].deathTick

doAssert farewellQueue >= 0
var
  farewellAired = false
  maxFarewellCopies = 0
  frames = 0
while replay.playing and frames < 8000:
  sim.advanceReplayPresentation(replay)
  inc frames
  maxFarewellCopies = max(maxFarewellCopies, targetCount(farewellPrefix))
  for item in sim.chatFeed:
    if item.message.startsWith(farewellPrefix) and item.everAired and
        not farewellAired:
      farewellAired = true
      doAssert sim.tickCount < farewellDeath,
        "the death-tick farewell must air before its actors leave"
      doAssert sim.directorSceneMap == item.mapIndex
      doAssert speakerMap(item.speaker.name) == item.mapIndex
  if sim.convQueueIndex > farewellQueue:
    break

doAssert farewellAired
doAssert maxFarewellCopies == 1,
  "preloading the final line must not capture it again on the next step"

# Seeking rebuilds viewer-only feed state, so the line is eligible to air again.
replay.applyReplaySeek(sim, farewellDeath - 2)
replay.applyReplayCommand(sim, 'p')
var
  replayedAfterSeek = false
  maxSeekCopies = 0
  seekFrames = 0
while replay.playing and seekFrames < 1000:
  sim.advanceReplayPresentation(replay)
  inc seekFrames
  maxSeekCopies = max(maxSeekCopies, targetCount(farewellPrefix))
  for item in sim.chatFeed:
    if item.message.startsWith(farewellPrefix) and item.everAired and
        not replayedAfterSeek:
      replayedAfterSeek = true
      doAssert sim.tickCount < farewellDeath
      doAssert sim.directorSceneMap == item.mapIndex
  if sim.convQueueIndex > farewellQueue:
    break
doAssert replayedAfterSeek,
  "seeking before a final line must make it visible again"
doAssert maxSeekCopies == 1

# Encounter 7 remains committed while dinner starts. Its last outdoor and
# indoor lines arrive while the director is touring other maps. Each line must
# temporarily route the camera to its own map, retain its read history across
# later room cuts, and finish before curfew.
let
  dinnerQueue = queueIndex(7)
  dinnerDeath = sim.convQueue[dinnerQueue].deathTick
replay.applyReplayConversation(sim, dinnerQueue)

let targetPrefixes = [
  "Who's hosting tomorrow, and what will you cook?",
  "Yes! Tomorrow at my house at six.",
  "Yes, tomorrow at six! What will you cook, Vova?"
]
var
  targetAired: HashSet[string]
  homeScenes: HashSet[int]
  selectionCounts: CountTable[string]
  lastSelection = ""
  lastShownAt = -1.0
  dinnerFrames = 0
while replay.playing and dinnerFrames < 12000:
  sim.advanceReplayPresentation(replay)
  inc dinnerFrames
  if sim.directorSceneMap > 0:
    homeScenes.incl(sim.directorSceneMap)
  if sim.chatFeedIndex >= 0 and sim.chatFeedIndex < sim.chatFeed.len:
    let item = sim.chatFeed[sim.chatFeedIndex]
    if item.everAired:
      let key = $item.encounterId & ":" & $item.mapIndex & ":" &
        item.speaker.name & ":" & item.message
      if key != lastSelection or sim.chatFeedShownAt != lastShownAt:
        selectionCounts.inc(key)
        lastSelection = key
        lastShownAt = sim.chatFeedShownAt
      for prefix in targetPrefixes:
        if item.message.startsWith(prefix) and prefix notin targetAired:
          targetAired.incl(prefix)
          doAssert sim.tickCount < dinnerDeath,
            "late dinner dialogue must finish before curfew"
          doAssert sim.directorSceneMap == item.mapIndex,
            "committed speech must own the camera on its actual map"
          doAssert speakerMap(item.speaker.name) == item.mapIndex
  if sim.convQueueIndex > dinnerQueue:
    break

doAssert targetAired.len == targetPrefixes.len,
  "all speech hidden by dinner-room cuts must still air"
doAssert homeScenes.len >= 2,
  "fixture must exercise dinner cuts between multiple rooms"
for key, count in selectionCounts:
  doAssert count == 1,
    "a room cut must not replay an already-read line: " & key
doAssert not replay.hashValidationFailed

echo "Replay boundary dialogue airs once on its speakers' map, survives room cuts, and replays after a seek."

# A real `bye` is stamped on the conversation's exit tick, rather than on
# curfew's preceding tick. Keep the shot until that last line has been read.
block departureTick:
  let
    finalPath = "docs/connections/review-2026-09-14/episode.bitreplay"
    finalData = loadReplay(finalPath)
    finalCfg = finalData.replaySimConfig()
    finalSim = initSimServer(finalCfg.seed, finalCfg.dayTicks)
  finalSim.attachConversationTimeline(finalData, finalPath)
  var finalReplay = initReplayPlayer(finalData)
  finalReplay.buildReplayKeyframes(finalCfg.seed, finalCfg.dayTicks)
  finalReplay.looping = false
  finalSim.buildConversationQueue(finalReplay.replayMaxTick())
  var departureQueue = -1
  for i, span in finalSim.convQueue:
    if span.id == 6: departureQueue = i
  doAssert departureQueue >= 0
  finalReplay.applyReplayConversation(finalSim, departureQueue)
  let farewell = "The portal calls. Tomorrow waits at Yura's door."
  var aired = false
  var count = 0
  for frame in 0 ..< 4000:
    finalSim.advanceReplayPresentation(finalReplay)
    var copies = 0
    for item in finalSim.chatFeed:
      if item.message == farewell:
        inc copies
        if item.everAired:
          aired = true
          doAssert item.encounterId == 6
          doAssert item.connectionPartner == "Anton"
          doAssert finalSim.directorSceneMap == item.mapIndex
    count = max(count, copies)
    if finalSim.convQueueIndex > departureQueue: break
  doAssert aired, "Dima's farewell on the exit tick must air in his conversation"
  doAssert count == 1, "preloaded departure speech must not be queued twice"
  doAssert not finalReplay.hashValidationFailed

echo "Recorded departure-tick farewell stays with its conversation and actual partner."

block departureAttributionExpires:
  let talk = initSimServer(42)
  for seat in [1, 7]:
    let player = talk.addPlayer("departure", seat)
    talk.players[player].mapIndex = 0
    talk.players[player].x = 320 + player * 10
    talk.players[player].y = 300
  talk.conversationTimeline = parseConversationTimeline("""
{"kind":"convo-enter","tick":0,"day":1,"seat":1,"text":"conversation id=1 members=Anton,Dima turn=1"}
{"kind":"convo-exit","tick":1,"day":1,"seat":7,"text":"conversation id=1 turn=2"}
{"kind":"convo-exit","tick":1,"day":1,"seat":1,"text":"conversation id=1 turn=2"}
""")
  talk.step(newSeq[InputState](2))
  talk.applyPlayerChat(1, "Goodbye, Anton!")
  talk.step(newSeq[InputState](2))
  doAssert talk.chatFeed[^1].encounterId == 1
  doAssert talk.chatFeed[^1].connectionPartner == "Anton"
  talk.applyPlayerChat(1, "A new day awaits.")
  talk.step(newSeq[InputState](2))
  doAssert talk.chatFeed[^1].encounterId == 0,
    "later speech must not inherit an already-departed conversation"
