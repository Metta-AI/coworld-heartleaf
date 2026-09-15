## Replay dialogue at curfew must air once, on the map where it was spoken,
## even when dinner-room cuts compete with a committed outdoor conversation.
import std/[importutils, sets, strutils, tables]
import heartleaf, replays

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
