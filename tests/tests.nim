import
  std/[json, os, random, strutils],
  bitworld/client as bitworldClient,
  bitworld/resources,
  bitworld/spriteprotocol,
  heartleaf,
  heartleaf/[common, protocol],
  replays,
  ../players/talking_villager/decisions

echo "Testing assets"
doAssert fileExists("data/map.aseprite"), "map asset should exist"
doAssert fileExists("data/gnomes.aseprite"), "gnome asset should exist"
doAssert fileExists("data/food.aseprite"), "food asset should exist"
doAssert fileExists("data/tiny5.aseprite"), "font asset should exist"
doAssert fileExists("data/home_map.resource"), "home resource should exist"
doAssert "function websocketPathForClientPage" in
  bitworldClient.EmbeddedGlobalClientHtml,
  "global sprite client should be embedded"
doAssert bitworldClient.EmbeddedSnappyClientJs.len > 0,
  "snappy client should be embedded"

echo "Testing resources"
let rects = loadResourceRects("data/map.resource")
doAssert rects.len > 0, "resource rectangles should parse"
doAssert rects[0].name.len > 0, "resource rectangle should have a name"
doAssert rects[0].w > 0, "resource rectangle should have a width"
doAssert rects[0].h > 0, "resource rectangle should have a height"
let homeRects = loadResourceRects("data/home_map.resource")
doAssert homeRects.len > 0, "home resource rectangles should parse"
doAssert homeRects[0].name == "exit", "home exit should be first"

echo "Testing talking_villager decisions"
let inviteDecision = parseLlmDecision("""
{
  "action": "say_to_person",
  "targetName": "Ivan",
  "houseIndex": 2,
  "message": "Come to my party?",
  "commitParty": true,
  "reason": "I have lots of food."
}
""")
doAssert inviteDecision.valid, "invite decision should parse"
doAssert inviteDecision.action == LlmSayToPerson, "action should match"
doAssert inviteDecision.targetName == "Ivan", "target should parse"
doAssert inviteDecision.houseIndex == 1, "house index should be zero based"
doAssert inviteDecision.message == "Come to my party?", "message should parse"
doAssert inviteDecision.commitParty, "commitment should parse"

let invalidDecision = parseLlmDecision("""{"action": "dance"}""")
doAssert not invalidDecision.valid, "unknown actions should be invalid"

let fencedDecision = parseLlmDecision("""
```json
{"action": "go_to_party", "houseIndex": 9, "commitParty": true}
```
""")
doAssert fencedDecision.valid, "fenced JSON should parse defensively"
doAssert fencedDecision.action == LlmGoToParty, "party action should parse"
doAssert fencedDecision.houseIndex == 8, "house 9 should become index 8"

let stringHouse = parseLlmDecision("""
{"action": "go_to_party", "houseIndex": "4", "targetName": "Sasha"}
""")
doAssert stringHouse.valid, "string houseIndex should parse"
doAssert stringHouse.houseIndex == 3, "house 4 should become index 3"

echo "Testing food names"
let namedFoods = replayFoodNames()
doAssert namedFoods.len == FoodVeggieSlots, "food names should match veggie slots"
doAssert namedFoods[0] == "Lettuce", "slot 0 should be Lettuce"
doAssert namedFoods[1] == "Carrot", "slot 1 should be Carrot"
doAssert namedFoods[5] == "Yellow Squash", "slot 5 should be Yellow Squash"
doAssert namedFoods[9] == "Purple Cabbage", "slot 9 should be Purple Cabbage"
doAssert namedFoods[11] == "Strawberries", "slot 11 should be Strawberries"
doAssert namedFoods[15] == "Rice", "slot 15 should be Rice"
doAssert namedFoods[17] == "Red Pepper", "slot 17 should be Red Pepper"
doAssert namedFoods[18] == "Green Pepper", "slot 18 should be Green Pepper"
doAssert "Zucchini" notin namedFoods, "old zucchini name should be gone"
doAssert "Raspberries" notin namedFoods, "old raspberry name should be gone"
doAssert "Hay Grass" notin namedFoods, "old hay grass name should be gone"

echo "Testing looking-for labels"
var uneaten: array[FoodVeggieSlots, bool]
doAssert lookingForLabel(uneaten).startsWith(LookingForLabelPrefix),
  "looking-for label should use the protocol prefix"
doAssert "Carrot" in lookingForLabel(uneaten),
  "a new gnome should still want carrot"
uneaten[1] = true
doAssert "Carrot" notin lookingForLabel(uneaten),
  "eaten carrot should leave the looking-for list"
for i in 0 ..< FoodVeggieSlots:
  uneaten[i] = true
doAssert lookingForLabel(uneaten) == LookingForLabelPrefix & "none",
  "a finished gnome should look for none"

echo "Testing dinner bites"
block:
  var
    rng = initRand(1)
    eaten: array[FoodVeggieSlots, bool]
    pantry: array[FoodVeggieSlots, int]
  pantry[1] = 2
  doAssert chooseDinnerBite(eaten, pantry, rng) == 1,
    "an uneaten carrot in the pantry should be taken"
  pantry[1] = 0
  doAssert chooseDinnerBite(eaten, pantry, rng) == -1,
    "an empty pantry should skip the bite"
  eaten[1] = true
  pantry[3] = 4
  doAssert chooseDinnerBite(eaten, pantry, rng) == 3,
    "a leftover tomato should be taken after new types are gone"

echo "Testing dinner rounds"
block:
  var
    rng = initRand(2)
    eaten = newSeq[array[FoodVeggieSlots, bool]](2)
    pantry: array[FoodVeggieSlots, int]
  pantry[1] = 1
  pantry[3] = 5
  let meals = eatDinnerRounds(eaten, pantry, rng)
  doAssert meals.scores.len == 2, "both diners should get a score"
  doAssert meals.scores[0] >= 3, "the first diner should eat a new type"
  doAssert meals.scores[1] >= 3, "the second diner should eat a new type"
  doAssert pantry[1] + pantry[3] == 0,
    "six bites should empty six host items"
  doAssert eaten[0][1] or eaten[1][1],
    "someone should have eaten the carrot"

echo "Testing replay round trip"
block:
  const
    TestSeed = 4242
    TestTicks = 200
  let replayPath = getTempDir() / "heartleaf-test-replay.bitreplay"

  # Record: drive a live-style sim with scripted inputs and a chat.
  var
    recSim = initSimServer(TestSeed)
    writer = openReplayWriter(replayPath, $(%*{"seed": TestSeed}))
  doAssert recSim.addPlayer("alice", -1) == 0, "alice should join first"
  writer.writeJoin(tickTime(0), 0, "alice", -1, "")
  writer.lastMasks.add(0)
  doAssert recSim.addPlayer("bob", 3) == 1, "bob should join second"
  writer.writeJoin(tickTime(0), 1, "bob", 3, "")
  writer.lastMasks.add(0)

  var masks = [0'u8, 0'u8]
  for tick in 0 ..< TestTicks:
    masks[0] =
      if tick < 40:
        ButtonRight
      elif tick < 90:
        ButtonRight or ButtonDown
      elif tick < 120:
        ButtonA
      else:
        ButtonUp or ButtonLeft
    masks[1] =
      if tick mod 30 < 15:
        ButtonLeft
      else:
        ButtonDown or ButtonA
    for playerIndex in 0 ..< 2:
      writer.writeInputMaskChange(
        tickTime(recSim.tickCount),
        playerIndex,
        masks[playerIndex]
      )
    if tick == 100:
      recSim.applyPlayerChat(0, "hello bob")
      writer.writeChat(tickTime(recSim.tickCount), 0, "hello bob")
    let inputs = @[decodeInputMask(masks[0]), decodeInputMask(masks[1])]
    recSim.step(inputs)
    writer.writeHash(uint32(recSim.tickCount), recSim.gameHash())
  let recordedHash = recSim.gameHash()
  writer.closeReplayWriter()

  # Play back against a fresh sim and validate every recorded hash.
  let data = loadReplay(replayPath)
  doAssert data.configJson == $(%*{"seed": TestSeed}),
    "replay config should round trip"
  doAssert data.joins.len == 2, "replay should keep both joins"
  doAssert data.chats.len == 1, "replay should keep the chat"
  doAssert data.hashes.len == TestTicks, "replay should hash every tick"
  var
    playSim = initSimServer(TestSeed)
    replay = initReplayPlayer(data)
  doAssert replay.replayMaxTick() == TestTicks, "max tick should match"
  while replay.playing and replay.hashIndex < data.hashes.len:
    replay.stepReplay(playSim)
  doAssert playSim.tickCount == TestTicks, "playback should reach the end"
  doAssert not replay.hashValidationFailed, "replay hashes should validate"
  doAssert playSim.gameHash() == recordedHash,
    "playback should reproduce the final game hash"
  doAssert playSim.gameHash() == data.hashes[^1].hash,
    "final hash should match the recorded stream"

  echo "Testing replay snapshot inspection"
  doAssert replaySimConfig(data).seed == TestSeed,
    "replaySimConfig should recover the recorded seed"
  let foodNames = replayFoodNames()
  doAssert foodNames.len > 0, "food names should be listed"
  doAssert "Apple" in foodNames, "food names should include Apple"

  let snapshots = snapshotReplayPlayers(playSim)
  doAssert snapshots.len == 2, "both players should be snapshotted"
  for snapshot in snapshots:
    doAssert snapshot.inventory.len == foodNames.len,
      "inventory should have one slot per food"
    doAssert snapshot.inventoryTotal >= 0, "inventory total should be sane"
    doAssert snapshot.x > 0 and snapshot.y > 0,
      "a played-back player should have a real foot position"
    doAssert snapshot.direction in ["north", "south", "east", "west"],
      "direction should be a named facing"

  let gardens = snapshotReplayGardens(playSim)
  doAssert gardens.len > 0, "the main map should have gardens"
  for garden in gardens:
    doAssert garden.foodTotal >= 0, "garden food should be non-negative"
    doAssert garden.centerX > 0 and garden.centerY > 0,
      "garden centre should be a real map point"

  # Chat hearing range: only a speaker with an active bubble has an audience,
  # and it never includes the speaker or an invalid slot.
  doAssert replayChatAudience(playSim, 99).len == 0,
    "an out-of-range slot should have no audience"
  doAssert replayChatAudience(playSim, 1).len == 0,
    "bob never chatted, so nobody hears bob"
  for heardSlot in replayChatAudience(playSim, 0):
    doAssert heardSlot != 0, "a speaker never hears themselves"
    doAssert heardSlot >= 0 and heardSlot < snapshots.len,
      "audience slots should be valid players"

  echo "Testing replay keyframes and seeking"
  # Reference hashes come from a second, straight linear playback.
  var
    refSim = initSimServer(TestSeed)
    refPlayer = initReplayPlayer(data)
    refHashes = newSeq[uint64](TestTicks + 1)
  refHashes[0] = refSim.gameHash()
  for tick in 1 .. TestTicks:
    refPlayer.stepReplay(refSim)
    doAssert refSim.tickCount == tick, "reference playback should be linear"
    refHashes[tick] = refSim.gameHash()

  var seekPlayer = initReplayPlayer(data)
  seekPlayer.buildReplayKeyframes(TestSeed)
  doAssert seekPlayer.keyframes.len == 3,
    "a 200 tick replay should keyframe ticks 0, 100, and 200"
  doAssert seekPlayer.keyframes[0].tick == 0, "first keyframe should be 0"
  doAssert seekPlayer.keyframes[1].tick == 100,
    "second keyframe should be 100"
  doAssert seekPlayer.keyframes[2].tick == 200, "last keyframe should be 200"
  echo "Keyframe simBytes sizes: ",
    seekPlayer.keyframes[0].simBytes.len, " ",
    seekPlayer.keyframes[1].simBytes.len, " ",
    seekPlayer.keyframes[2].simBytes.len, " bytes"

  let seekSim = initSimServer(TestSeed)
  for target in [0, 37, 100, 150, 199]:
    seekPlayer.seekReplay(seekSim, target)
    doAssert seekSim.tickCount == target,
      "seek should land on tick " & $target
    doAssert seekSim.gameHash() == refHashes[target],
      "seek to tick " & $target & " should match the linear hash"
  removeFile(replayPath)
