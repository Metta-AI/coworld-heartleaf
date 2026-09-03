import
  std/[json, os, random, sequtils, sets, strutils, tables],
  bitworld/client as bitworldClient,
  bitworld/resources,
  bitworld/spriteprotocol,
  curly,
  heartleaf,
  heartleaf/[common, protocol, decisions, souls, observation, navigation,
    villager, executor, report, prompt, pacing, bedrock_client, brains,
    encounters],
  replays,
  ../tools/llm_chart,
  voiced_replay

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

echo "Testing decisions"
let talkDecision = parseDecision("""
{
  "action": "talk_to",
  "targetName": "Ivan",
  "message": "Got any carrot?",
  "reason": "I still need carrot."
}
""")
doAssert talkDecision.valid, "talk_to should parse"
doAssert talkDecision.action == TalkTo, "action should match"
doAssert talkDecision.targetName == "Ivan", "target should parse"
doAssert talkDecision.houseIndex == 0, "a named gnome fills houseIndex"
doAssert talkDecision.message == "Got any carrot?", "message should parse"

let invalidDecision = parseDecision("""{"action": "dance"}""")
doAssert not invalidDecision.valid, "unknown actions should be invalid"
doAssert not invalidDecision.malformed, "unknown actions are still JSON"

let fencedDecision = parseDecision("""
```json
{"action": "go_to_house", "targetName": "Egor"}
```
""")
doAssert fencedDecision.valid, "fenced JSON should parse defensively"
doAssert fencedDecision.action == GoToHouse, "go_to_house should parse"
doAssert fencedDecision.houseIndex == 8, "Egor is house 9"

let trailing = parseDecision("""
{"action": "say", "message": "Hi {there}"}
user(You now carry: Corn.) Return JSON now.
{"action": "go_home"}
""")
doAssert trailing.valid and trailing.action == Say,
  "only the first complete object counts, braces in strings included"
doAssert trailing.message == "Hi {there}"

for pair in [
  ("gather_plants", GatherPlants),
  ("keep_gathering_plants", GatherPlants),
  ("talk_to", TalkTo),
  ("say", Say),
  ("bye", Bye),
  ("follow", Follow),
  ("go_home", GoHome),
  ("go_to_house", GoToHouse),
  ("go_to_garden", GoToGarden),
  ("wait", Wait),
  ("wander", Wander)
]:
  let parsed = parseDecision("{\"action\": \"" & pair[0] &
    "\", \"targetName\": \"Anton\", \"message\": \"ok\"}")
  doAssert parsed.valid and parsed.action == pair[1], pair[0] & " should parse"

echo "Testing self name prefix stripping"
let vova = ["Vova", "grumpy_villager"]
doAssert "Vova: hello Anton".stripSelfPrefix(vova) == "hello Anton",
  "plain self label should be stripped"
doAssert "vova:hello".stripSelfPrefix(vova) == "hello",
  "self label match should ignore case and missing space"
doAssert "**Vova:** hello".stripSelfPrefix(vova) == "hello",
  "markdown bold self label should be stripped"
doAssert "[Vova]: hello".stripSelfPrefix(vova) == "hello",
  "bracketed self label should be stripped"
doAssert "Vova: Vova: hello".stripSelfPrefix(vova) == "hello",
  "repeated self labels should all be stripped"
doAssert "grumpy_villager: hello".stripSelfPrefix(vova) == "hello",
  "any of the bot's names should be stripped"
doAssert "Anton: come to dinner".stripSelfPrefix(vova) ==
  "Anton: come to dinner", "other names must not be stripped"
doAssert "Vova's house at 6!".stripSelfPrefix(vova) == "Vova's house at 6!",
  "self name without a colon label must stay"
doAssert "Vovan: hi".stripSelfPrefix(vova) == "Vovan: hi",
  "longer names sharing a prefix must stay"
doAssert "Vova:".stripSelfPrefix(vova) == "",
  "a bare label leaves an empty line"
doAssert "Vova: hello".stripSelfPrefix([]) == "Vova: hello",
  "no names means nothing is stripped"
let prefixedDecision = parseDecision("""
{"action": "talk_to", "targetName": "Anton", "message": "Vova: hi Anton"}
""", vova)
doAssert prefixedDecision.message == "hi Anton",
  "decision messages should lose the self label"
doAssert "today\u2014found pear\u2026 \u201cnice\u201d".cleanDecisionText() ==
  "today - found pear... \"nice\"", "model punctuation becomes ASCII"

echo "Testing food name lists"
doAssert "Yellow Squash x2, Beet".foodNamesIn() ==
  @["Yellow Squash", "Beet"], "counts are stripped from food names"
doAssert "none".foodNamesIn().len == 0

echo "Testing the shared request budget"
block:
  var budget = newRequestBudget(42)
  budget.minRequestSeconds = 1.0
  budget.maxInFlight = 3
  var now = 1000.0
  doAssert budget.canRequest(now), "first request should be allowed at once"
  budget.noteRequest(now)
  doAssert not budget.canRequest(now + 0.5), "requests are spaced pod-wide"
  doAssert budget.canRequest(now + 1.0), "spacing reopens after the floor"
  budget.noteRequest(now + 1.0)
  budget.noteRequest(now + 2.0)
  doAssert not budget.canRequest(now + 3.0), "three in flight is the cap"
  budget.noteReply()
  doAssert budget.canRequest(now + 3.0), "a reply frees an in-flight slot"
  budget.noteRequest(now + 3.0)
  budget.noteReply()
  budget.noteReply()
  budget.noteReply()
  let throttle = budget.noteThrottle(now + 60.0, 4.5)
  doAssert throttle == 4.5, "Retry-After wins over the throttle floor"
  doAssert not budget.canRequest(now + 64.0), "everyone waits while throttled"
  doAssert budget.canRequest(now + 64.5)

echo "Testing per-villager retry backoff"
block:
  var budget = newRequestBudget(7)
  let soul = parseSoul("#!test-model\nYour name is {name}. Test soul.\n")
  var villager = newVillager(3, soul, 1)
  var now = 2000.0
  let firstWait = villager.noteTransientFailure(budget, now)
  doAssert firstWait >= 2.0 and firstWait <= 3.0,
    "first backoff is the minimum plus up to 50% jitter"
  doAssert villager.failures == 1
  doAssert villager.retryAt >= now + firstWait
  var last = villager.retryBackoffSeconds
  now += firstWait
  for _ in 0 ..< 8:
    let wait = villager.noteTransientFailure(budget, now)
    doAssert villager.retryBackoffSeconds == min(last * 2.0, 60.0),
      "backoff doubles until the cap"
    doAssert wait >= villager.retryBackoffSeconds and
      wait <= villager.retryBackoffSeconds * 1.5
    last = villager.retryBackoffSeconds
    now += wait
  doAssert villager.retryBackoffSeconds == 60.0, "backoff caps at a minute"
  let honored = villager.noteTransientFailure(budget, now, retryAfter = 120.0)
  doAssert honored == 120.0, "Retry-After extends the wait"
  villager.noteUsableReply()
  doAssert villager.failures == 0 and villager.retryAt == 0.0,
    "a usable reply clears the backoff"
  for _ in 0 ..< 7:
    now += villager.noteTransientFailure(budget, now, dailyQuota = true)
  doAssert villager.retryBackoffSeconds == 100.0,
    "a spent daily quota has its own, longer cap"

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

echo "Testing foods not eaten"
var uneaten: array[FoodVeggieSlots, bool]
doAssert "Carrot" in foodsNotEatenText(uneaten),
  "a new gnome should still want carrot"
uneaten[1] = true
doAssert "Carrot" notin foodsNotEatenText(uneaten),
  "eaten carrot should leave the list"
for i in 0 ..< FoodVeggieSlots:
  uneaten[i] = true
doAssert foodsNotEatenText(uneaten) == "none",
  "a finished gnome wants none"

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

echo "Testing delay chat holds four wall-clock seconds"
block:
  doAssert ChatFeedShowSeconds == 4.0, "delay chat is four real seconds"
  var sim = initSimServer(1)
  sim.queueDelayChat("Ivan", "hello")
  sim.queueDelayChat("Egor", "hi")
  sim.advanceChatFeed(1.0)
  doAssert sim.delayChatMessage() == "hello", "the first line should show"
  sim.advanceChatFeed(4.9)
  doAssert sim.delayChatMessage() == "hello",
    "the first line should hold until four seconds"
  sim.advanceChatFeed(5.0)
  doAssert sim.delayChatMessage() == "hi",
    "the queued line should show after four seconds"
  for i in 0 ..< 200:
    sim.advanceChatFeed(5.0)
  doAssert sim.delayChatMessage() == "hi",
    "zipping sim ticks should not skip the hold"

echo "Testing delay chat banner reuses init sprites"
block:
  var sim = initSimServer(1)
  discard sim.addPlayer("alice", 0)
  sim.queueDelayChat("Ivan", "hello there")
  sim.advanceChatFeed(1.0)
  var next: PlayerViewerState
  let first = sim.buildGlobalPacket(nil, next)
  var
    sawBanner = false
    ringFrames = 0
    glyphSprites = 0
    portraitSprites = 0
  for msg in parseSpritePacket(first):
    if msg.kind != spkSprite:
      continue
    if msg.sprite.label == "chat banner":
      sawBanner = true
    elif msg.sprite.label.startsWith("conversation ring"):
      inc ringFrames
    elif msg.sprite.label.startsWith("banner glyph"):
      inc glyphSprites
    elif msg.sprite.label.startsWith("portrait"):
      inc portraitSprites
  doAssert sawBanner, "the banner background is in the init packet"
  doAssert ringFrames == 16, "sixteen ring frames are in the init packet"
  doAssert glyphSprites > 50, "banner glyphs are in the init packet"
  doAssert portraitSprites >= 18, "portraits and flips are in the init packet"
  var next2: PlayerViewerState
  let second = sim.buildGlobalPacket(next, next2)
  var bannerObjects = 0
  for msg in parseSpritePacket(second):
    if msg.kind == spkSprite:
      doAssert msg.sprite.label != "chat banner",
        "must not resend the banner background"
      doAssert not msg.sprite.label.startsWith("banner glyph"),
        "must not resend banner glyphs"
      doAssert not msg.sprite.label.startsWith("portrait"),
        "must not resend portraits"
      doAssert not msg.sprite.label.startsWith("conversation ring"),
        "must not resend ring frames"
    elif msg.kind == spkObject:
      inc bannerObjects
  doAssert bannerObjects > 0, "later frames still place banner objects"

echo "Testing the game clock fits the hosted deadline"
doAssert DayTotalMinutes == 12 * 60, "a day is twelve hours"
doAssert DayTicks == 180 * TicksPerSecond, "three-minute days"
doAssert MovementTurnTicks == MovementTurnSeconds * TicksPerSecond
doAssert MovementTurnTicks == 360, "one game hour is 15s at 24 ticks"
doAssert MovementTurnsPerDay == 12, "twelve hourly slices fill a day"
doAssert SecondsPerGameHour * 4 == 60, "four game hours per real minute"
doAssert DayTicks mod (DayTotalMinutes div 5) == 0, "one clock step is a whole number of ticks"
let week = gameTicksForDays(DefaultDayCount, DayTicks)
doAssert week == 7 * (4320 + 240), "a week is 31920 ticks"
doAssert hostedDeadlineProblem(week) == "", "the week fits in 30 minutes"
doAssert hostedDeadlineProblem(0) == "", "unlimited games are local only"
doAssert hostedDeadlineProblem(HostedDeadlineSeconds * TicksPerSecond + 24) != "",
  "a game past the deadline is refused"

echo "Testing unpinned seed sentinel"
doAssert not seedPinned(""), "empty config should be unpinned"
doAssert not seedPinned("{}"), "missing seed should be unpinned"
doAssert not seedPinned($(%*{"seed": DefaultSeed})),
  "DefaultSeed should be the unpinned sentinel"
doAssert seedPinned($(%*{"seed": 1})),
  "any other integer should pin the village RNG"
doAssert seedPinned($(%*{"seed": 4242})),
  "fixture seeds should stay pinned"
let stripped = stripUnpinnedSeed(
  $(%*{"seed": DefaultSeed, "maxTicks": 8})
)
let strippedNode = parseJson(stripped)
doAssert not strippedNode.hasKey("seed"),
  "stripUnpinnedSeed should drop the sentinel"
doAssert strippedNode["maxTicks"].getInt == 8,
  "stripUnpinnedSeed should keep the rest of the config"
let drawnSeed = randomSeed()
doAssert drawnSeed >= 0 and drawnSeed <= 0x7FFF_FFFF,
  "randomSeed should be 31-bit"

echo "Testing per-model request shapes"
block:
  let turns = @[
    ConversationMessage(role: "system", content: "soul"),
    ConversationMessage(role: "user", content: "Day 1 8:00am")
  ]
  let haiku = parseJson(bedrockBody(turns, "Ivan", false,
    "us.anthropic.claude-haiku-4-5-20251001-v1:0"))
  doAssert haiku.hasKey("temperature") and not haiku.hasKey("thinking"),
    "older models keep sampling and never think"
  let opus5 = parseJson(bedrockBody(turns, "Ivan", false, "us.anthropic.claude-opus-5"))
  doAssert not opus5.hasKey("temperature"), "the 5 family rejects temperature"
  doAssert opus5["thinking"]["type"].getStr() == "disabled"
  let sonnet5 = parseJson(bedrockBody(turns, "Ivan", false, "us.anthropic.claude-sonnet-5"))
  doAssert sonnet5["thinking"]["type"].getStr() == "disabled"
  let opus48 = parseJson(bedrockBody(turns, "Ivan", false, "us.anthropic.claude-opus-4-8"))
  doAssert not opus48.hasKey("temperature") and not opus48.hasKey("thinking")
  let fable = parseJson(bedrockBody(turns, "Ivan", false, "us.anthropic.claude-fable-5"))
  doAssert not fable.hasKey("thinking"), "Fable cannot switch thinking off"
  doAssert fable["output_config"]["effort"].getStr() == "low"
  doAssert fable["max_tokens"].getInt() >= 1024, "thinking needs output room"
  let sonnet46 = parseJson(bedrockBody(turns, "Ivan", false, "us.anthropic.claude-sonnet-4-6"))
  doAssert sonnet46.hasKey("temperature") and not sonnet46.hasKey("thinking")

echo "Testing Coworld player attribution headers"
block:
  putEnv("AWS_ENDPOINT_URL_BEDROCK_RUNTIME", "http://127.0.0.1:18000")
  let headers = bedrockHeaders("{}", "us.anthropic.claude-sonnet-4-6", 4)
  doAssert headers[CoworldPlayerSlotHeader] == "4",
    "hosted model calls identify the logical player slot"
  delEnv("AWS_ENDPOINT_URL_BEDROCK_RUNTIME")

echo "Testing Converse bodies for other providers"
block:
  doAssert "us.anthropic.claude-opus-5".isAnthropicModel()
  doAssert not "us.xai.grok-4.6".isAnthropicModel()
  let turns = @[
    ConversationMessage(role: "system", content: "soul"),
    ConversationMessage(role: "assistant", content: "(I said hi)"),
    ConversationMessage(role: "user", content: "Clock: 9am"),
    ConversationMessage(role: "user", content: "Day 1 9:00am")
  ]
  let grok = parseJson(converseBody(turns, "us.xai.grok-4.6"))
  doAssert grok["system"][0]["text"].getStr() == "soul"
  doAssert grok["messages"][0]["role"].getStr() == "user", "a leading assistant turn is seeded"
  doAssert grok["messages"].len == 3, "same-role turns are joined"
  doAssert grok["messages"][2]["content"][0]["text"].getStr() == "Clock: 9am\nDay 1 9:00am"
  doAssert not grok["inferenceConfig"].hasKey("temperature"), "reasoning models get no sampling"
  doAssert grok["inferenceConfig"]["maxTokens"].getInt() >= 1024
  let llama = parseJson(converseBody(turns, "us.meta.llama4-maverick-17b-instruct-v1:0"))
  doAssert llama["inferenceConfig"].hasKey("temperature"), "chat models keep the temperature"
  doAssert bedrockUsageText("""{"output":{},"usage":{"inputTokens":12,"outputTokens":3}}""") ==
    "in=12 cacheRead=0 cacheWrite=0 out=3"

echo "Testing soul files"
block:
  let soul = parseSoul("#!us.anthropic.claude-haiku-4-5-20251001-v1:0\r\nYour name is {name}.\r\nBe kind.\n")
  doAssert soul.modelId == "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  doAssert soul.text == "Your name is {name}.\nBe kind.\n", "CRLF is normalised"
  doAssert soul.modelId.knownModelFamily()
  for id in ["us.openai.gpt-5.6-luna", "us.xai.grok-4.6", "qwen.qwen3-32b-v1:0",
      "us.meta.llama4-maverick-17b-instruct-v1:0", "moonshotai.kimi-k2.5",
      "mistral.mistral-large-3-675b-instruct", "global.anthropic.claude-sonnet-5"]:
    doAssert id.knownModelFamily(), id & " is a family the game can call"
  doAssert not "acme.gnome-9000".knownModelFamily()
  doAssert not "claude-opus-5".knownModelFamily(), "a bare id has no provider"
  proc rejects(raw: string): bool =
    try:
      discard parseSoul(raw)
      false
    except SoulError:
      true
  doAssert rejects(""), "empty souls are rejected"
  doAssert rejects("Your name is Vova.\n"), "a missing shebang is rejected"
  doAssert rejects("#!\nbody\n"), "a shebang without a model is rejected"
  doAssert rejects("#!bad model!\nbody\n"), "odd model characters are rejected"
  doAssert rejects("#!model\n\n  \n"), "an empty body is rejected"
  doAssert rejects("#!model\nbody\0\n"), "NUL bytes are rejected"
  doAssert rejects("#!model\n" & "x".repeat(SoulMaxBytes)), "oversize is rejected"
  var souls = initTable[int, Soul]()
  doAssert seatsWaitingForSouls(3, souls) == @[0, 1, 2]
  souls[1] = soul
  doAssert seatsWaitingForSouls(3, souls) == @[0, 2]
  souls[0] = soul
  souls[2] = soul
  doAssert seatsWaitingForSouls(3, souls).len == 0
  var accepted = soul
  accepted.seat = 4
  doAssert accepted.soulReply().isSoulAccepted()
  doAssert soulRejection("nope").isSoulRejected()

echo "Testing the system prompt"
block:
  let soul = parseSoul("#!test-model\nYour name is {name}. You are shy.\n")
  let text = systemPrompt(soul, "Vova")
  doAssert text.startsWith("Your name is Vova. You are shy."), "{name} is filled in"
  doAssert "{name}" notin text
  let sections = ["Response format:", "Conversation memory:", "Talking:",
    "Actions:", "\nDinner:\n", "Repeating yourself:", "Greeting:",
    "Vegetable hunt:"]
  var last = 0
  for section in sections:
    let at = text.find(section)
    doAssert at > last, section & " should follow the previous section"
    last = at
  doAssert MechanicsBlock in text, "the mechanics follow the soul"
  doAssert text.endsWith(housesText()), "the house table comes last"
  doAssert "Ivan," in text and "Egor." in text, "houses are listed by owner"
  doAssert "Earlier state reports" in text, "old reports are not part of memory"
  doAssert "reason field is your notes" in text, "reason stays as self memory"
  doAssert "Talking:" in text, "the mechanics lock talk mode"
  doAssert "Dinner bell" in text, "the dinner bell is in the mechanics"
  doAssert "portal takes you" in text, "night is a portal, not a curfew"
  doAssert "Where line" in text, "location is in the mechanics"
  doAssert "Last JSON was ignored" in text, "ignored actions are told why"
  let bare = systemPrompt(parseSoul("#!m\nJust a soul.\n"), "Ivan")
  doAssert bare.startsWith("Your name is Ivan. You are a Heartleaf gnome player."),
    "a soul without {name} gets a name line"

echo "Testing live state reports stay out of history"
block:
  var sim = initSimServer(7)
  doAssert sim.addPlayer("alice", 0) == 0
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let villager = newVillager(0, soul, sim.worldLayoutFor().gardens.len)
  villager.systemPrompt = systemPrompt(soul, villager.name)
  let
    observation = sim.observe(0)
    navigation = sim.navigationFor()
    layout = sim.worldLayoutFor()
  let first = villager.requestMessages(observation, navigation, layout)
  doAssert first[^1].role == "user"
  doAssert "Where:" in first[^1].content, "the live report is last"
  doAssert villager.history.len == 0, "the live report is not kept"
  villager.appendHistory(
    "assistant",
    """{"action":"keep_gathering_plants","reason":"start"}"""
  )
  let second = villager.requestMessages(observation, navigation, layout)
  doAssert second[^1].content.contains("Where:")
  doAssert villager.history.len == 1
  doAssert villager.history[0].role == "assistant"
  var reportLogs = 0
  for entry in villager.logEntries:
    let node = parseJson(entry)
    if node["index"].getInt() < 0 and "Where:" in node["text"].getStr():
      inc reportLogs
  doAssert reportLogs == 2, "each live report is logged"

echo "Testing live headers omit empty next-to lines"
block:
  var sim = initSimServer(7)
  doAssert sim.addPlayer("alice", 0) == 0
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let villager = newVillager(0, soul, sim.worldLayoutFor().gardens.len)
  var observation = sim.observe(0)
  let layout = sim.worldLayoutFor()
  let navigation = sim.navigationFor()
  let report = villager.stateReport(observation, navigation, layout)
  doAssert "People next to" notin report
  doAssert "Houses next to" notin report
  doAssert "Conversation:" notin report
  doAssert "Talking: no" in report
  doAssert "minutes until dinner" notin report
  doAssert "Food collected:" notin report, "carry nothing, omit the line"
  doAssert "Where: inside Ivan's house" in report
  doAssert "People next to: none" notin report
  doAssert "Houses next to: none" notin report
  doAssert report.endsWith("Return JSON now.")
  villager.lastError = "Talking: yes, so action must be talk_to, say, or bye."
  let talking = villager.stateReport(observation, navigation, layout)
  doAssert "Talking: yes. Only" notin talking
  doAssert "Last JSON was ignored:" in talking
  observation.minutes = DinnerDepartMinutes
  observation.scene = Outdoors
  observation.currentHouse = -1
  let bell = villager.stateReport(observation, navigation, layout)
  doAssert "Dinner bell:" in bell
  doAssert "leave now" in bell
  doAssert "Where: outside, in the village" in bell
  observation.scene = Indoors
  observation.currentHouse = 2
  let inside = villager.stateReport(observation, navigation, layout)
  doAssert "Where: inside Yura's house" in inside
  doAssert "Stay through 6:00pm" in inside

echo "Testing house-circuit wander"
block:
  var sim = initSimServer(1)
  doAssert sim.addPlayer("alice", 0) == 0
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let villager = newVillager(0, soul, sim.worldLayoutFor().gardens.len)
  doAssert villager.nextWanderHouse() == 0, "the circuit starts at house 0"
  villager.wanderedDoors[0] = true
  doAssert villager.nextWanderHouse() == 1
  for i in 0 ..< HouseCount:
    villager.wanderedDoors[i] = i != villager.houseIndex
  doAssert villager.nextWanderHouse() == villager.houseIndex,
    "own house is on the circuit, never skipped"
  for i in 0 ..< HouseCount:
    villager.wanderedDoors[i] = true
  doAssert villager.nextWanderHouse() == 0, "all 9 reset the circuit"
  doAssert not villager.wanderedDoors[0]
  var observation = sim.observe(0)
  observation.scene = Outdoors
  for i in 0 ..< HouseCount:
    observation.houseOnScreen[i] = false
  observation.houseOnScreen[4] = true
  villager.markSeenDoors(observation)
  doAssert villager.wanderedDoors[4], "a door on screen is marked"
  doAssert villager.nextWanderHouse() != 4, "a seen door is not the next target"

echo "Testing n-way encounters"
block:
  var book = initEncounterBook()
  let group = book.startEncounter(0, 1)
  doAssert group.members.len == 2
  group.addMember(2)
  doAssert group.members.len == 3
  group.addLine("Ivan", "hey")
  group.addLine("Anton", "hi")
  let text = group.conversationText("Yura")
  doAssert "Ivan: hey" in text
  doAssert "Anton: hi" in text
  group.removeMember(0)
  doAssert group.members.len == 2
  var sim = initSimServer(1)
  for i in 0 .. 2:
    doAssert sim.addPlayer("p" & $i, i) == i
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let brains = newBrains(
    sim.navigationFor(), sim.worldLayoutFor(), newScriptedBedrockClient(), 1
  )
  for i in 0 .. 2:
    brains.attachSoul(i, soul)
  let
    ivan = brains.villagers[0]
    anton = brains.villagers[1]
    yura = brains.villagers[2]
  let say = parseDecision("""{"action": "say", "message": "hi"}""")
  let bye = parseDecision("""{"action": "bye", "message": "later"}""")
  let wait = parseDecision("""{"action": "wait"}""")
  doAssert not ivan.modeAllows(say), "say outside talk is rejected"
  doAssert not ivan.modeAllows(bye), "bye outside talk is rejected"
  doAssert ivan.modeAllows(wait)
  discard brains.joinOrStartTalk(ivan, "Anton")
  doAssert ivan.talking and anton.talking
  doAssert brains.book.encounter(ivan.encounterId).members.len == 2
  brains.speakInEncounter(ivan, "hey there")
  var ivanYou, antonHeard = 0
  for line in ivan.history:
    if line.content == "You: hey there":
      inc ivanYou
  for line in anton.history:
    if line.content == "Ivan: hey there":
      inc antonHeard
  doAssert ivanYou == 1 and antonHeard == 1, "each spoken line is one history turn"
  discard brains.joinOrStartTalk(ivan, "Yura")
  doAssert yura.talking
  doAssert brains.book.encounter(ivan.encounterId).members.len == 3
  var yuraHeard = 0
  for line in yura.history:
    if line.content == "Ivan: hey there":
      inc yuraHeard
  doAssert yuraHeard == 1, "a joiner gets the lines so far, once"
  doAssert ivan.modeAllows(say)
  doAssert not ivan.modeAllows(wait), "must bye to walk off"
  brains.leaveEncounter(ivan)
  doAssert not ivan.talking
  doAssert anton.talking and yura.talking
  doAssert brains.book.encounter(anton.encounterId).members.len == 2
  brains.leaveEncounter(anton)
  doAssert not anton.talking and not yura.talking,
    "the last two dissolve together"
  ivan.askedWhileTalking = true
  doAssert ivan.modeAllows(say),
    "say still counts if the group dissolved while the ask was in flight"
  ivan.askedWhileTalking = false
  doAssert not ivan.modeAllows(say)

echo "Testing conversation circle geometry"
block:
  doAssert ConversationExitRadius == 72
  doAssert ConversationRingRadius == 36
  doAssert conversationCircle(@[]).radius == 0
  doAssert conversationCircle(@[Point(x: 10, y: 10)]).radius == 0
  let pair = conversationCircle(@[
    Point(x: 100, y: 100),
    Point(x: 132, y: 100)
  ])
  doAssert pair.x == 116 and pair.y == 100
  doAssert pair.radius == ConversationRingRadius
  let spread = conversationCircle(@[
    Point(x: 0, y: 0),
    Point(x: 200, y: 0)
  ])
  doAssert spread.x == 100 and spread.y == 0
  doAssert spread.radius == ConversationRingRadius,
    "the ring stays one size when people stand outside it"
  var book = initEncounterBook()
  var feet = initTable[int, Point]()
  doAssert book.encounterCircles(feet).len == 0
  discard book.startEncounter(0, 1)
  feet[0] = Point(x: 100, y: 100)
  doAssert book.encounterCircles(feet).len == 0, "one outdoor member is not a ring"
  feet[1] = Point(x: 140, y: 100)
  let rings = book.encounterCircles(feet)
  doAssert rings.len == 1, "two outdoor members draw a ring"
  doAssert rings[0].radius == ConversationRingRadius
  let frozenX = rings[0].x
  feet[0] = Point(x: 10, y: 10)
  let dragged = book.encounterCircles(feet)
  doAssert dragged.len == 1
  doAssert dragged[0].x == frozenX,
    "a walker must not drag the ring; they already left it"
  feet.del(0)
  doAssert book.encounterCircles(feet).len == 0,
    "one gnome left dissolves the conversation ring"
  feet[0] = Point(x: 100, y: 100)
  discard book.encounterCircles(feet)
  let encounter = book.encounter(1)
  encounter.addMember(2)
  feet[2] = Point(x: 180, y: 100)
  let joined = book.encounterCircles(feet)
  doAssert joined.len == 1
  doAssert joined[0].x != frozenX,
    "a new joiner recenters the ring once"

echo "Testing conversation rings follow chat-mode objects"
block:
  let timeline = parseConversationTimeline(
    """{"tick":10,"seat":0,"kind":"convo-enter","text":"conversation enter id=1 members=Ivan,Egor turn=0"}
{"tick":15,"seat":4,"kind":"convo-enter","text":"conversation enter id=1 members=Egor,Ivan,Maxim turn=1"}
{"tick":20,"seat":0,"kind":"convo-exit","text":"conversation exit id=1 turn=2"}
{"tick":20,"seat":8,"kind":"convo-exit","text":"conversation exit id=1 turn=2"}
{"tick":20,"seat":4,"kind":"convo-exit","text":"conversation exit id=1 turn=2"}
"""
  )
  doAssert timeline.encounterMembersAt(9).len == 0
  let opened = timeline.encounterMembersAt(10)
  doAssert opened.len == 1
  doAssert 0 in opened[0] and 8 in opened[0]
  doAssert 4 notin opened[0]
  let joined = timeline.encounterMembersAt(15)
  doAssert joined.len == 1
  doAssert 0 in joined[0] and 4 in joined[0] and 8 in joined[0]
  doAssert timeline.encounterMembersAt(20).len == 0
  var sim = initSimServer(1)
  discard sim.addPlayer("alice", 0)
  discard sim.addPlayer("bob", 1)
  sim.applyPlayerChat(0, "hello")
  sim.inferConversationCircles()
  doAssert sim.conversationCircles.len == 0,
    "speech bubbles without a conversation object must not draw a ring"

echo "Testing say and bye flow through the conversation clock"
block:
  var sim = initSimServer(1)
  doAssert sim.addPlayer("alice", 0) == 0
  doAssert sim.addPlayer("bob", 1) == 1
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let client = newScriptedBedrockClient()
  let brains = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, 1)
  brains.attachSoul(0, soul)
  brains.attachSoul(1, soul)
  discard brains.joinOrStartTalk(brains.villagers[0], "Anton")
  proc observations(): Table[int, Observation] =
    {0: sim.observe(0), 1: sim.observe(1)}.toTable
  var now = 2000.0
  var frame = brains.advance(observations(), now)
  doAssert client.started.len == 0,
    "gnomes in a conversation get no plan call"
  doAssert brains.phase == MovePhase,
    "with everyone ready the movement turn begins at once"
  var chats: seq[string]
  proc drainChats() =
    for item in frame.outputs:
      if item.output.chat.len > 0:
        chats.add(item.output.chat)
  proc runToSlot() =
    var guard = 0
    while not frame.paused and guard < 40:
      now += 0.05
      frame = brains.advance(observations(), now)
      drainChats()
      inc guard
    doAssert frame.paused, "a conversation tick holds the world"
  runToSlot()
  doAssert client.started.len == 1, "one member is asked for a line"
  client.scriptReply(BedrockReply(
    tag: client.started[^1].tag, statusCode: 200,
    text: """{"action": "say", "message": "wait I had more"}"""
  ))
  now += 0.1
  frame = brains.advance(observations(), now)
  drainChats()
  runToSlot()
  doAssert client.started.len == 2, "the turn rotates to the other member"
  client.scriptReply(BedrockReply(
    tag: client.started[^1].tag, statusCode: 200,
    text: """{"action": "bye", "message": "later"}"""
  ))
  now += 0.1
  frame = brains.advance(observations(), now)
  drainChats()
  var guard = 0
  while ("later" notin chats or "wait I had more" notin chats) and guard < 60:
    now += 0.05
    frame = brains.advance(observations(), now)
    drainChats()
    inc guard
  doAssert "wait I had more" in chats, "the say line lands"
  doAssert "later" in chats, "the bye line lands"
  doAssert not brains.villagers[1].talking, "bye leaves the conversation"

echo "Testing leapfrog turns"
block:
  var sim = initSimServer(7)
  doAssert sim.addPlayer("alice", 0) == 0
  doAssert sim.addPlayer("bob", 1) == 1
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let client = newScriptedBedrockClient()
  let brains = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, 1)
  brains.attachSoul(0, soul)
  brains.attachSoul(1, soul)
  proc observations(): Table[int, Observation] =
    {0: sim.observe(0), 1: sim.observe(1)}.toTable
  var now = 1000.0
  var answered = 0
  proc answer(text: string) =
    client.scriptReply(BedrockReply(
      tag: client.started[answered].tag, statusCode: 200, text: text
    ))
    inc answered
  var frame = brains.advance(observations(), now)
  doAssert frame.paused, "the village waits until every gnome replies"
  doAssert brains.phase == LlmPhase
  doAssert client.started.len == 2
  answer("""{"action": "wait"}""")
  now += 0.1
  frame = brains.advance(observations(), now)
  doAssert frame.paused, "one reply is not enough to start movement"
  doAssert brains.phase == LlmPhase
  answer("""{"action": "wait"}""")
  now += 0.1
  var moveTicks = 0
  while true:
    frame = brains.advance(observations(), now)
    if frame.paused:
      break
    var inputs = newSeq[InputState](2)
    for item in frame.outputs:
      inputs[item.houseIndex] = decodeInputMask(item.output.mask)
    sim.step(inputs)
    inc moveTicks
    now += 0.05
    doAssert moveTicks <= MovementTurnTicks + 1
  doAssert moveTicks == MovementTurnTicks,
    "a movement slice is one game hour of 24-tick seconds"
  doAssert brains.phase == LlmPhase
  doAssert frame.paused, "the next LLM phase waits again"

echo "Testing parse failures stay in the LLM phase"
block:
  var sim = initSimServer(7)
  doAssert sim.addPlayer("alice", 0) == 0
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let client = newScriptedBedrockClient()
  let brains = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, 1)
  brains.attachSoul(0, soul)
  proc observations(): Table[int, Observation] =
    {0: sim.observe(0)}.toTable
  var now = 4000.0
  discard brains.advance(observations(), now)
  doAssert client.started.len == 1
  client.scriptReply(BedrockReply(
    tag: client.started[0].tag, statusCode: 200, text: "not json"
  ))
  now += 0.1
  var frame = brains.advance(observations(), now)
  let villager = brains.villagers[0]
  doAssert frame.paused, "a parse failure keeps the village paused"
  doAssert brains.phase == LlmPhase
  doAssert not villager.turnReady
  doAssert villager.failures == 1
  doAssert villager.retryPending
  now = villager.retryAt + 0.01
  discard brains.advance(observations(), now)
  doAssert client.started.len == 2, "retries stay in the same LLM phase"
  doAssert brains.phase == LlmPhase
  client.scriptReply(BedrockReply(
    tag: client.started[1].tag, statusCode: 200,
    text: """{"action": "wait"}"""
  ))
  now += 0.1
  frame = brains.advance(observations(), now)
  doAssert not frame.paused
  doAssert brains.phase == MovePhase
  doAssert villager.hasDecision, "a usable reply starts movement"

echo "Testing a bad choice waits instead of retrying"
block:
  var sim = initSimServer(7)
  doAssert sim.addPlayer("alice", 0) == 0
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let client = newScriptedBedrockClient()
  let brains = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, 1)
  brains.attachSoul(0, soul)
  proc observations(): Table[int, Observation] =
    {0: sim.observe(0)}.toTable
  var now = 5000.0
  discard brains.advance(observations(), now)
  client.scriptReply(BedrockReply(
    tag: client.started[0].tag, statusCode: 200,
    text: """{"action": "say", "message": "hi"}"""
  ))
  now += 0.1
  var frame = brains.advance(observations(), now)
  let villager = brains.villagers[0]
  doAssert not frame.paused, "a bad choice does not hold the village"
  doAssert brains.phase == MovePhase
  doAssert villager.turnReady
  doAssert villager.failures == 0
  doAssert not villager.retryPending
  doAssert villager.decision.action == Wait, "say outside talk becomes wait"
  doAssert villager.lastError.len > 0
  var sawIgnore = false
  for line in villager.history:
    if line.content.startsWith("(Your action was ignored:"):
      sawIgnore = true
      doAssert "Talking: no" in line.content
  doAssert sawIgnore, "the gnome is told the action was ignored and why"

echo "Testing wait in conversation is silence, not a retry"
block:
  var sim = initSimServer(1)
  doAssert sim.addPlayer("alice", 0) == 0
  doAssert sim.addPlayer("bob", 1) == 1
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let client = newScriptedBedrockClient()
  let brains = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, 1)
  brains.attachSoul(0, soul)
  brains.attachSoul(1, soul)
  discard brains.joinOrStartTalk(brains.villagers[0], "Anton")
  proc observations(): Table[int, Observation] =
    {0: sim.observe(0), 1: sim.observe(1)}.toTable
  var now = 6000.0
  var frame = brains.advance(observations(), now)
  doAssert brains.phase == MovePhase
  var guard = 0
  while not frame.paused and guard < 40:
    now += 0.05
    frame = brains.advance(observations(), now)
    inc guard
  doAssert frame.paused, "a conversation tick holds the world"
  let asked = client.started[^1]
  client.scriptReply(BedrockReply(
    tag: asked.tag, statusCode: 200, text: """{"action": "wait"}"""
  ))
  now += 0.1
  frame = brains.advance(observations(), now)
  doAssert not frame.paused, "an ignored action releases the world"
  let speaker = brains.villagers[asked.playerSlot]
  doAssert speaker.talking, "wait does not leave the group"
  doAssert speaker.failures == 0, "an ignored action is not a retry"
  var sawIgnore = false
  for line in speaker.history:
    if line.content.startsWith("(Your action was ignored:"):
      sawIgnore = true
  doAssert sawIgnore, "wait in conversation is ignored with a reason"
  var silentRows = 0
  for line in brains.gameLog.entries:
    if "convo-tick" in line and "silent=true" in line:
      inc silentRows
  doAssert silentRows == 1, "the quiet stop counts as one silent tick"

echo "Testing the conversation clock inside a movement turn"
block:
  var sim = initSimServer(1)
  doAssert sim.addPlayer("alice", 0) == 0
  doAssert sim.addPlayer("bob", 1) == 1
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let client = newScriptedBedrockClient()
  let brains = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, 1)
  brains.attachSoul(0, soul)
  brains.attachSoul(1, soul)
  discard brains.joinOrStartTalk(brains.villagers[0], "Anton")
  proc observations(): Table[int, Observation] =
    {0: sim.observe(0), 1: sim.observe(1)}.toTable
  var now = 6000.0
  discard brains.advance(observations(), now)
  var answered = 0
  proc answerAll(text: string) =
    while answered < client.started.len:
      client.scriptReply(BedrockReply(
        tag: client.started[answered].tag, statusCode: 200, text: text
      ))
      inc answered
  answerAll("""{"action": "say", "message": "opening line"}""")
  now += 0.1
  var frame = brains.advance(observations(), now)
  doAssert brains.phase == MovePhase, "both replied, movement begins"
  # Walk the movement turn until the conversation clock opens a slot.
  var guard = 0
  while not frame.paused and guard < 40:
    now += 0.05
    frame = brains.advance(observations(), now)
    inc guard
  doAssert frame.paused, "a conversation tick holds the world"
  doAssert brains.conversationTick == 1, "the first conversation tick"
  doAssert client.started.len == 1,
    "one line call, and no plan calls for gnomes in a conversation"
  let slotRequest = client.started[^1]
  doAssert frame.blockedNames == @[slotRequest.playerName],
    "the world waits for the speaker alone"
  let linesBefore = brains.book.encounter(
    brains.villagers[0].encounterId
  ).lines.len
  client.scriptReply(BedrockReply(
    tag: slotRequest.tag, statusCode: 200,
    text: """{"action": "say", "message": "a line in the slot"}"""
  ))
  inc answered
  now += 0.1
  frame = brains.advance(observations(), now)
  doAssert not frame.paused, "the line landed and the world runs again"
  doAssert brains.book.encounter(
    brains.villagers[0].encounterId
  ).lines.len == linesBefore + 1, "the slot line is in the shared log"
  var tickRows = 0
  for line in brains.gameLog.entries:
    if "convo-tick" in line:
      inc tickRows
  doAssert tickRows == 1, "the closed conversation tick is stamped"
  # The next slot passes to the other member: round-robin.
  guard = 0
  while not frame.paused and guard < 40:
    now += 0.05
    frame = brains.advance(observations(), now)
    inc guard
  doAssert frame.paused and brains.conversationTick == 2
  doAssert client.started[^1].playerSlot != slotRequest.playerSlot,
    "speaking turns rotate"
  # Silence: five quiet conversation ticks dissolve the circle.
  var dissolvedAt = -1
  for round in 1 .. 6:
    now += 4.0
    frame = brains.advance(observations(), now)
    doAssert not frame.paused, "an expired slot releases the world"
    if not brains.villagers[0].talking:
      dissolvedAt = round
      break
    guard = 0
    while not frame.paused and guard < 40:
      now += 0.05
      frame = brains.advance(observations(), now)
      inc guard
  # A speaker whose slot expired still has that request in flight, so
  # their next slot passes silent too - silence can accrue faster than
  # one tick per round.
  doAssert dissolvedAt in 3 .. 5,
    "consecutive silent ticks end the conversation, got " & $dissolvedAt
  doAssert not brains.villagers[1].talking, "everyone left the circle"

echo "Testing a brain-driven village"
block:
  var sim = initSimServer(4242)
  doAssert sim.addPlayer("alice", 0) == 0
  doAssert sim.addPlayer("bob", 1) == 1
  let soul = parseSoul("#!test-model\nYour name is {name}. Test soul.\n")
  let client = newScriptedBedrockClient()
  let brains = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, 1)
  brains.attachSoul(0, soul)
  brains.attachSoul(1, soul)
  proc observations(): Table[int, Observation] =
    {0: sim.observe(0), 1: sim.observe(1)}.toTable
  var now = 1000.0
  var frame = brains.advance(observations(), now)
  doAssert frame.paused, "nobody has a decision yet, so the village waits"
  doAssert frame.blockedNames.len == 2
  doAssert client.started.len == 2, "both villagers asked the model"
  doAssert client.started.mapIt(it.playerSlot) == @[0, 1],
    "each model request carries its Coworld player slot"
  for request in client.started:
    doAssert request.messages[^1].role == "user"
    doAssert "Where:" in request.messages[^1].content,
      "each ask ends with a live state report"
  for villager in brains.villagers.values:
    for line in villager.history:
      doAssert "Where:" notin line.content,
        "state reports are not kept in history"
  var answered = 0
  proc answer(text: string) =
    client.scriptReply(BedrockReply(
      tag: client.started[answered].tag, statusCode: 200, text: text
    ))
    inc answered
  proc answerPending() =
    while answered < client.started.len:
      let house = client.started[answered].tag.split(':')[0]
      if house == "0" and sim.playerMapIndex(0) == 2:
        answer("""{"action": "talk_to", "targetName": "Anton", "message": "hello there"}""")
      elif house == "0":
        answer("""{"action": "go_to_house", "targetName": "Anton"}""")
      elif sim.playerMapIndex(0) == 2:
        answer("""{"action": "say", "message": "ok"}""")
      else:
        answer("""{"action": "wait"}""")
  var ticks = 0
  var chatsSeen: seq[string]
  proc runTicks(untilDone: proc(): bool, limit: int) =
    var steps = 0
    while steps < limit and not untilDone():
      now += 0.05
      frame = brains.advance(observations(), now)
      answerPending()
      if frame.paused:
        inc steps
        continue
      var inputs = newSeq[InputState](2)
      for item in frame.outputs:
        inputs[item.houseIndex] = decodeInputMask(item.output.mask)
        if item.output.chat.len > 0:
          chatsSeen.add(item.output.chat)
          sim.applyPlayerChat(item.houseIndex, item.output.chat)
      sim.step(inputs)
      inc ticks
      inc steps
  runTicks(proc(): bool = sim.playerMapIndex(0) == 2, 8000)
  doAssert sim.playerMapIndex(0) == 2,
    "alice should walk out of her house and into Anton's"
  doAssert sim.playerMapIndex(1) == 2, "bob stays home"
  runTicks(proc(): bool = "hello there" in chatsSeen, 4000)
  doAssert "hello there" in chatsSeen, "alice greets Anton once next to him"
  doAssert "hello there" in brains.villagers[0].saidToday
  doAssert "Anton" in brains.villagers[0].greetedToday
  let beforeHello = chatsSeen.count("hello there")
  runTicks(proc(): bool = false, 120)
  doAssert chatsSeen.count("hello there") == beforeHello,
    "the same line is never said twice a day"
  var history: seq[string]
  for line in brains.villagers[0].history:
    history.add(line.content)
  doAssert "(Day 1 begins.)" in history
  doAssert "(You see Anton for the first time today.)" in history
  doAssert history.anyIt("hello there" in it and it.startsWith("{")),
    "own chat lives in the JSON message field"
  doAssert not history.anyIt("Where:" in it),
    "state reports are live-only, not kept in history"
  doAssert not history.anyIt(it == "hello there"),
    "spoken lines are not a second assistant turn"
  doAssert not history.anyIt("walkMinutesToHouse" in it),
    "the state report is only the changing facts"
  doAssert history.anyIt(it.startsWith("{\"action\"")),
    "the raw model reply is an assistant turn"
  let logged = brains.villagers[0].logEntries
  doAssert logged.len >= history.len + 1, "every turn is logged, plus the prompt"
  doAssert parseJson(logged[0])["role"].getStr() == "system"
  doAssert parseJson(logged[0])["gnome"].getStr() == "Ivan"
  for i, entry in logged:
    let node = parseJson(entry)
    doAssert node["game"].getInt() == 1 and node["sequence"].getInt() == i,
      "log records carry the game and a dense sequence"
    let role = node["role"].getStr()
    doAssert role == "system" or role == "user" or role == "assistant",
      "the player log is only the conversation"
  var turns = 0
  for entry in logged:
    let node = parseJson(entry)
    if node["index"].getInt() >= 0:
      doAssert node["text"].getStr() == history[node["index"].getInt()],
        "log entries mirror the history exactly"
      inc turns
  doAssert turns == history.len, "the log holds the whole history"
  let prefix = history
  runTicks(proc(): bool = false, 60)
  doAssert brains.villagers[0].history.len >= prefix.len
  for i, content in prefix:
    doAssert brains.villagers[0].history[i].content == content,
      "the history is never rewritten"
  block:
    var ended = 0
    while not sim.scoreScreenActive() and ended < 5000:
      sim.step(newSeq[InputState](2))
      inc ended
    doAssert sim.scoreScreenActive(), "the day should end"
    doAssert sim.playerScore(0) == 0, "away from home at 9pm has no penalty"
    doAssert sim.playerScore(1) == 0, "bob was home"
    now += 0.05
    frame = brains.advance(observations(), now)
    doAssert frame.paused == false, "the score screen keeps stepping"
    for line in brains.villagers[0].history:
      doAssert not line.content.startsWith("(Curfew:"),
        "nobody hears a curfew penalty"
    for line in brains.villagers[1].history:
      doAssert not line.content.startsWith("(Curfew:"), "bob hears nothing"

echo "Testing llm lifecycle logs"
block:
  var sim = initSimServer(7)
  doAssert sim.addPlayer("alice", 0) == 0
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let client = newScriptedBedrockClient()
  let brains = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, 1)
  brains.attachSoul(0, soul)
  let now = 1000.0
  discard brains.advance({0: sim.observe(0)}.toTable, now)
  let villager = brains.villagers[0]
  doAssert villager.gameLog == brains.gameLog, "seats share one game log"
  var kinds: seq[string]
  for entry in villager.gameLog.entries:
    let node = parseJson(entry)
    doAssert node.hasKey("day") and node.hasKey("minutes")
    doAssert node.hasKey("now")
    if node["role"].getStr() == "llm":
      kinds.add(node["kind"].getStr())
      doAssert node["day"].getInt() >= 1
      doAssert node["minutes"].getInt() >= DayStartMinutes
      if node["kind"].getStr() == "request":
        doAssert "llm request" in node["text"].getStr()
        doAssert node["now"].getFloat() == now
  doAssert "request" in kinds, "starting a call is logged"
  doAssert "turn" in kinds, "the first LLM turn is stamped"
  var sawClock = false
  for entry in villager.gameLog.entries:
    let node = parseJson(entry)
    if node["role"].getStr() == "clock":
      sawClock = true
      doAssert node["now"].getFloat() == now
      doAssert node["minutes"].getInt() == DayStartMinutes
  doAssert sawClock, "the first game hour is stamped with wall time"
  var observation = sim.observe(0)
  observation.visiblePlayers = @[VisiblePlayer(
    name: "Anton", houseIndex: 1, foot: Point(x: 10, y: 10),
    distanceSquared: 100, says: ""
  )]
  villager.scanSeenGnomes(observation)
  var sawSighting = false
  for line in villager.history:
    if "You see Anton" in line.content:
      sawSighting = true
  doAssert sawSighting, "a first sighting is recorded"
  client.scriptReply(BedrockReply(
    tag: client.started[0].tag,
    statusCode: 200,
    text: """{"action": "wait"}"""
  ))
  discard brains.advance({0: sim.observe(0)}.toTable, now + 1.0)
  var sawReply = false
  for entry in villager.gameLog.entries:
    let node = parseJson(entry)
    if node["role"].getStr() == "llm" and node["kind"].getStr() == "reply":
      sawReply = true
      doAssert "outcome=usable" in node["text"].getStr()
  doAssert sawReply, "the reply is logged"
  doAssert villager.turnReady

echo "Testing veggies picked log"
block:
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  var villager = newVillager(0, soul, 1)
  villager.now = 1000.0
  villager.minutes = 630
  var observation = Observation(gardensWithFood: 4, minutes: 630)
  villager.maybeRecordVeggies(observation)
  doAssert not villager.veggiesLogged
  observation.gardensWithFood = 0
  villager.maybeRecordVeggies(observation)
  doAssert villager.veggiesLogged
  var found = false
  for entry in villager.gameLog.entries:
    let node = parseJson(entry)
    if node["role"].getStr() == "veggies":
      found = true
      doAssert "veggies" in node["text"].getStr()
  doAssert found, "empty gardens are logged once"
  let before = villager.gameLog.entries.len
  villager.maybeRecordVeggies(observation)
  doAssert villager.gameLog.entries.len == before, "the empty log is once a day"

echo "Testing house enter and exit logs"
block:
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  var villager = newVillager(0, soul, 1)
  villager.now = 1000.0
  villager.minutes = 540
  var observation = Observation(
    scene: Indoors, currentHouse: 0, minutes: 540
  )
  villager.maybeRecordHouse(observation)
  doAssert villager.insideHouse == 0
  observation.scene = Outdoors
  observation.currentHouse = -1
  villager.minutes = 555
  villager.maybeRecordHouse(observation)
  doAssert villager.insideHouse < 0
  observation.scene = Indoors
  observation.currentHouse = 1
  villager.minutes = 600
  villager.maybeRecordHouse(observation)
  var enters, exits: int
  var sawOther = false
  for entry in villager.gameLog.entries:
    let node = parseJson(entry)
    if node["role"].getStr() != "house":
      continue
    if node["kind"].getStr() == "enter":
      inc enters
      if "own=no" in node["text"].getStr():
        sawOther = true
    elif node["kind"].getStr() == "exit":
      inc exits
  doAssert enters == 2 and exits == 1
  doAssert sawOther, "a visit to another house is logged"

echo "Testing the llm call chart"
block:
  doAssert 45.0.formatWallSpan() == "45s"
  doAssert 180.0.formatWallSpan() == "3 min"
  doAssert 610.0.formatWallSpan() == "10 min 10s"
  let text = """
{"game":1,"sequence":0,"seat":0,"gnome":"Ivan","index":-1,"role":"clock","kind":"clock","day":1,"minutes":540,"tick":0,"now":1000.0,"text":"clock day=1 minutes=540 now=1000.000 clock=9:00am"}
{"game":1,"sequence":1,"seat":0,"gnome":"Ivan","index":-1,"role":"clock","kind":"clock","day":1,"minutes":600,"tick":60,"now":1015.0,"text":"clock day=1 minutes=600 now=1015.000 clock=10:00am"}
{"game":1,"sequence":2,"seat":0,"gnome":"Ivan","index":-1,"role":"clock","kind":"clock","day":1,"minutes":660,"tick":120,"now":1045.0,"text":"clock day=1 minutes=660 now=1045.000 clock=11:00am"}
{"game":1,"sequence":3,"seat":0,"gnome":"Ivan","index":-1,"role":"clock","kind":"clock","day":1,"minutes":720,"tick":180,"now":1060.0,"text":"clock day=1 minutes=720 now=1060.000 clock=12:00pm"}
{"game":1,"sequence":7,"seat":0,"gnome":"Ivan","index":-1,"role":"clock","kind":"clock","day":1,"minutes":1080,"tick":360,"now":1075.0,"text":"clock day=1 minutes=1080 now=1075.000 clock=6:00pm"}
{"game":1,"sequence":8,"seat":0,"gnome":"Ivan","index":-1,"role":"clock","kind":"clock","day":1,"minutes":1260,"tick":540,"now":1090.0,"text":"clock day=1 minutes=1260 now=1090.000 clock=9:00pm"}
{"game":1,"sequence":9,"seat":0,"gnome":"Ivan","index":-1,"role":"veggies","kind":"veggies","day":1,"minutes":630,"tick":80,"now":1030.0,"text":"veggies day=1 minutes=630 now=1030.000 clock=10:30am"}
{"game":1,"sequence":4,"seat":0,"gnome":"Ivan","index":-1,"role":"llm","kind":"request","day":1,"minutes":540,"tick":12,"now":1002.0,"text":"llm request day=1 minutes=540 tick=12 now=1002.000 clock=9:00am tag=0:1"}
{"game":1,"sequence":5,"seat":0,"gnome":"Ivan","index":-1,"role":"llm","kind":"interrupt","day":1,"minutes":630,"tick":80,"now":1025.0,"text":"llm interrupt day=1 minutes=630 tick=80 now=1025.000 clock=10:30am reason=chat"}
{"game":1,"sequence":6,"seat":0,"gnome":"Ivan","index":-1,"role":"llm","kind":"reply","day":1,"minutes":660,"tick":120,"now":1040.0,"text":"llm reply day=1 minutes=660 tick=120 now=1040.000 clock=11:00am tag=0:1 outcome=usable took=2.1s in=80000 cacheRead=15000 cacheWrite=4000 out=1000"}
Yura: llm request day=1 minutes=555 tick=20 now=1004.000 clock=9:15am tag=2:1 (9:15am)
Yura: llm interrupt day=1 minutes=600 tick=50 now=1016.000 clock=10:00am reason=sighting who=Ivan (10:00am)
Yura: llm interrupt day=1 minutes=645 tick=90 now=1030.000 clock=10:45am reason=leave (10:45am)
Yura: llm reply day=1 minutes=690 tick=140 now=1050.000 clock=11:30am tag=2:1 outcome=usable took=4.0s ignored=wait (11:30am)
Dima: llm request day=1 minutes=570 tick=30 now=1008.000 clock=9:30am tag=7:1 (9:30am)
Dima: llm reply day=1 minutes=750 tick=200 now=1065.000 clock=12:30pm tag=7:1 outcome=parse took=8.0s (12:30pm)
Egor: llm interrupt day=1 minutes=720 tick=180 now=1060.000 clock=12:00pm reason=hour (12:00pm)
{"game":1,"sequence":10,"seat":0,"gnome":"Ivan","index":-1,"role":"house","kind":"enter","day":1,"minutes":540,"tick":0,"now":1000.0,"text":"house enter day=1 minutes=540 now=1000.000 clock=9:00am house=1 own=yes"}
{"game":1,"sequence":11,"seat":0,"gnome":"Ivan","index":-1,"role":"house","kind":"exit","day":1,"minutes":555,"tick":20,"now":1006.0,"text":"house exit day=1 minutes=555 now=1006.000 clock=9:15am house=1 own=yes"}
{"game":1,"sequence":12,"seat":0,"gnome":"Ivan","index":-1,"role":"house","kind":"enter","day":1,"minutes":600,"tick":60,"now":1015.0,"text":"house enter day=1 minutes=600 now=1015.000 clock=10:00am house=2 own=no"}
{"game":1,"sequence":13,"seat":0,"gnome":"Ivan","index":-1,"role":"house","kind":"exit","day":1,"minutes":660,"tick":120,"now":1040.0,"text":"house exit day=1 minutes=660 now=1040.000 clock=11:00am house=2 own=no"}
{"game":1,"sequence":14,"seat":7,"gnome":"Dima","index":-1,"role":"house","kind":"enter","day":1,"minutes":630,"tick":80,"now":1025.0,"text":"house enter day=1 minutes=630 now=1025.000 clock=10:30am house=8 own=yes"}
{"game":1,"sequence":15,"seat":7,"gnome":"Dima","index":-1,"role":"house","kind":"exit","day":1,"minutes":690,"tick":140,"now":1050.0,"text":"house exit day=1 minutes=690 now=1050.000 clock=11:30am house=8 own=yes"}
"""
  var events = text.parseLlmText("")
  events.fillMissingNow()
  doAssert events.len == 23,
    "json, stdout, clock, veggies, house, and interrupt lines all parse"
  doAssert events.selectedGame(0) == 1
  let calls = events.pairLlmCalls(1)
  let clocks = events.collectClockMarks(1)
  let veggies = events.collectVeggieMarks(1)
  let houses = events.pairHouseStays(1)
  let ticks = events.collectInterruptMarks(1)
  doAssert calls.len == 3
  doAssert calls.chartDays() == 1
  doAssert clocks.len >= 6
  doAssert veggies.len == 1
  doAssert veggies[0].minutes == 630
  doAssert houses.len == 3
  var ownStays, otherStays: int
  for stay in houses:
    if stay.own:
      inc ownStays
    else:
      inc otherStays
  doAssert ownStays == 2 and otherStays == 1
  var nine, ten, eleven: ClockMark
  for mark in clocks:
    case mark.minutes
    of 9 * 60: nine = mark
    of 10 * 60: ten = mark
    of 11 * 60: eleven = mark
    else: discard
  doAssert ten.now - nine.now == 15.0, "a full-speed hour is 15s"
  doAssert eleven.now - ten.now == 30.0, "a paused hour stretches in wall time"
  var ivan, yura, dima: LlmCall
  for call in calls:
    case call.gnome
    of "Ivan": ivan = call
    of "Yura": yura = call
    of "Dima": dima = call
    else: discard
  doAssert ivan.interrupts.len == 1 and ivan.interrupts[0].reason == "chat"
  doAssert yura.interrupts.len == 2
  doAssert not ivan.pending and ivan.outcome == "usable"
  doAssert yura.outcome == "ignored"
  doAssert ivan.tokens == 100000, "reply in/cache/out tokens are summed"
  doAssert ivan.promptTokens == 99000, "prompt is in plus cache"
  doAssert ivan.cacheTokens == 19000, "cache is read plus write"
  doAssert dima.outcome == "parse"
  doAssert dima.tokens == 0, "a reply without usage has no tokens"
  doAssert ivan.endNow - ivan.startNow == 38.0
  var sawEgorHour = false
  for mark in ticks:
    if mark.gnome == "Egor" and mark.reason == "hour":
      sawEgorHour = true
  doAssert sawEgorHour, "an idle hour interrupt is kept"
  let svg = calls.renderLlmChart(clocks, veggies, houses, ticks)
  doAssert "Day 1" in svg
  doAssert "Ivan" in svg and "Yura" in svg and "Dima" in svg
  doAssert "9am" in svg
  doAssert "noon" in svg
  doAssert "10am" in svg
  doAssert "wakeup" in svg
  doAssert "dinner" in svg
  doAssert "sleep" in svg
  doAssert "veggies picked" in svg
  doAssert "stroke-dasharray=\"4 3\"" in svg
  doAssert "fill=\"none\"" in svg
  doAssert "own house" in svg
  doAssert "Anton's house" in svg
  doAssert "stroke-dasharray=\"3 2\"" in svg
  doAssert "Egor interrupt hour" in svg
  doAssert "#f03b20" in svg, "held interrupts use tufte red"
  doAssert "#c8c8c0" in svg, "failed calls fill gray"
  doAssert "stroke-dasharray=\"1 2\"" in svg,
    "invalid replies use a dotted border"
  doAssert "<rect" in svg
  doAssert "y1=\"343" in svg, "10am sits 15s below 9am"
  doAssert "y1=\"793" in svg, "11am sits 30s below 10am"
  doAssert "#b0b0a8" in svg, "hourly lines are faint gray"
  doAssert "#e9ecef" notin svg, "the old paper-on-paper hour color is gone"
  let page = calls.renderLlmPage(clocks, veggies, houses, ticks)
  doAssert "<h1>Heartleaf LLM Calls</h1>" in page
  doAssert "Interrupts held" notin page
  doAssert "Cache %" in page
  doAssert "19.2%" in page, "Ivan's cacheable prefix is 19.2%"
  doAssert "LLM seconds" in page
  doAssert "Avg LLM Seconds" in page
  doAssert "Non-LLM seconds" in page
  doAssert "Tokens" in page
  doAssert "Cost" in page
  doAssert "Total" in page
  doAssert "100000" in page
  doAssert "$0.10" in page
  doAssert "38.0" in page, "Ivan's one call lasted 38s"
  doAssert "52.0" in page, "Ivan was idle for the rest of the span"
  doAssert "real time" in page
  doAssert "1 min 30s" in page, "the first chart fixture spans 90s"
  doAssert "dotted" in page


echo "Testing the leapfrog chart"
block:
  let text = """
{"game":1,"sequence":0,"seat":0,"gnome":"Ivan","index":-1,"role":"clock","kind":"clock","day":1,"minutes":540,"tick":0,"now":1000.0,"text":"clock day=1 minutes=540 now=1000.000 clock=9:00am"}
{"game":1,"sequence":1,"seat":0,"gnome":"Ivan","index":-1,"role":"veggies","kind":"veggies","day":1,"minutes":630,"tick":80,"now":1030.0,"text":"veggies day=1 minutes=630 now=1030.000 clock=10:30am"}
Ivan: llm turn kind=llm index=0 now=1000.000 clock=9:00am
Ivan: llm request day=1 minutes=540 tick=0 now=1001.000 clock=9:00am tag=0:1
Ivan: llm reply day=1 minutes=540 tick=0 now=1002.000 clock=9:00am tag=0:1 outcome=usable
Anton: llm turn kind=llm index=0 now=1000.000 clock=9:00am
Ivan: llm turn kind=move index=1 now=1003.000 clock=9:00am
Anton: llm turn kind=move index=1 now=1003.000 clock=9:00am
Ivan: conversation enter id=1 members=Anton,Ivan turn=1 now=1003.000
Anton: conversation enter id=1 members=Anton,Ivan turn=1 now=1003.000
Ivan: llm turn kind=llm index=2 now=1009.000 clock=9:00am
Anton: llm turn kind=llm index=2 now=1009.000 clock=9:00am
Ivan: conversation exit id=1 turn=2 now=1009.000
Anton: conversation exit id=1 turn=2 now=1009.000
Ivan: llm request day=1 minutes=540 tick=0 now=1010.000 clock=9:00am tag=0:2
Ivan: llm reply day=1 minutes=540 tick=0 now=1012.000 clock=9:00am tag=0:2 outcome=parse
Ivan: llm request day=1 minutes=540 tick=0 now=1013.000 clock=9:00am tag=0:3
Ivan: llm reply day=1 minutes=540 tick=0 now=1016.000 clock=9:00am tag=0:3 outcome=usable
Ivan: llm turn kind=move index=3 now=1017.000 clock=9:00am
Anton: llm turn kind=move index=3 now=1017.000 clock=9:00am
"""
  var events = text.parseLlmText("")
  let turns = events.collectTurns(0)
  let talks = events.collectTalks(0)
  let calls = events.pairLlmCalls(0)
  let clocks = events.collectClockMarks(0)
  let veggies = events.collectVeggieMarks(0)
  doAssert turns.len == 4, "llm and move rows both parse"
  doAssert turns[0].kind == "llm" and turns[0].index == 0
  doAssert turns[1].kind == "move" and turns[1].index == 1
  doAssert talks.len == 2
  doAssert calls.len == 3, "a retry is a second call, not a stacked cell"
  var parseCalls, usableCalls: int
  var parseEnd, retryStart: float
  for call in calls:
    if call.gnome != "Ivan":
      continue
    if call.outcome == "parse":
      inc parseCalls
      parseEnd = call.endNow
    elif call.outcome == "usable":
      inc usableCalls
      if call.startNow > 1010:
        retryStart = call.startNow
  doAssert parseCalls == 1 and usableCalls == 2
  doAssert retryStart >= parseEnd, "the retry starts after the failed call"
  let svg = calls.renderLlmChart(
    clocks, veggies, turns = turns, talks = talks
  )
  doAssert "#e8e8e4" in svg, "movement slices fill gray"
  doAssert "#ffe8e6" in svg, "conversation fills light red"
  doAssert "conversation" in svg
  doAssert "0 llm" notin svg
  doAssert "Day 1" in svg
  doAssert "9am" in svg
  doAssert "wakeup" in svg
  doAssert "veggies picked" in svg
  doAssert "parse" in svg
  doAssert "#c8c8c0" in svg, "the failed retry fills gray"
  doAssert "stroke-dasharray=\"1 2\"" in svg,
    "a parse failure uses a dotted border"
  let page = calls.renderLlmPage(
    clocks, veggies, turns = turns, talks = talks
  )
  doAssert "leapfrog" in page
  doAssert "light red" in page
  doAssert "real time" in page
  doAssert "retry" in page

echo "Testing the chart prefers game.log"
block:
  let dir = getTempDir() / "heartleaf-chart-game-log"
  createDir(dir)
  writeFile(
    dir / "game.log",
    """{"game":1,"gnome":"Ivan","role":"llm","kind":"request","day":1,"minutes":540,"now":1.0,"text":"llm request"}""" &
      "\n"
  )
  writeFile(
    dir / "chatty_villager-Ivan.log",
    """{"game":1,"gnome":"Ivan","role":"llm","kind":"reply","day":1,"minutes":540,"now":2.0,"text":"llm reply"}""" &
      "\n"
  )
  let events = loadLlmEvents(@[dir])
  doAssert events.len == 1, "player logs are skipped when game.log exists"
  doAssert events[0].kind == LlmRequest
  removeDir(dir)

echo "Testing a mock-driven replay round trip"
block:
  const
    TestSeed = 777
    TestTicks = 300
  putEnv(MockReplyEnv, """{"action": "keep_gathering_plants"}""")
  let replayPath = getTempDir() / "heartleaf-brain-replay.bitreplay"
  var
    recSim = initSimServer(TestSeed)
    writer = openReplayWriter(replayPath, $(%*{"seed": TestSeed}))
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let brains = newBrains(
    recSim.navigationFor(), recSim.worldLayoutFor(), newBedrockClient(2), 3
  )
  for seat in 0 ..< 2:
    doAssert recSim.addPlayer("gnome" & $seat, seat) == seat
    writer.writeJoin(tickTime(0), seat, "gnome" & $seat, seat, soul.modelId)
    writer.lastMasks.add(0)
    brains.attachSoul(seat, soul)
  var now = 3000.0
  var stepped = 0
  while stepped < TestTicks:
    now += 0.05
    let frame = brains.advance(
      {0: recSim.observe(0), 1: recSim.observe(1)}.toTable, now
    )
    doAssert not frame.paused, "a mock reply never pauses the village"
    var inputs = newSeq[InputState](2)
    for item in frame.outputs:
      inputs[item.houseIndex] = decodeInputMask(item.output.mask)
      writer.writeInputMaskChange(
        tickTime(recSim.tickCount), item.houseIndex, item.output.mask
      )
      if item.output.chat.len > 0:
        recSim.applyPlayerChat(item.houseIndex, item.output.chat)
        writer.writeChat(tickTime(recSim.tickCount), item.houseIndex, item.output.chat)
    recSim.step(inputs)
    writer.writeHash(uint32(recSim.tickCount), recSim.gameHash())
    inc stepped
  let recordedHash = recSim.gameHash()
  writer.closeReplayWriter()
  delEnv(MockReplyEnv)
  doAssert recSim.playerMapIndex(0) == 0 or recSim.playerMapIndex(1) == 0,
    "gathering gnomes leave their houses"
  let data = loadReplay(replayPath)
  var
    playSim = initSimServer(TestSeed)
    replay = initReplayPlayer(data)
  while replay.playing and replay.hashIndex < data.hashes.len:
    replay.stepReplay(playSim)
  doAssert not replay.hashValidationFailed, "brain-driven replays validate"
  doAssert playSim.gameHash() == recordedHash,
    "playback without brains reproduces the game"
  removeFile(replayPath)

echo "Testing heart connections"
block:
  # The one rule: a spoken turn connects the speaker with every member
  # who spoke within the last round of that conversation.
  var ledger: HeartLedger
  let members = @[0, 1]
  ledger.creditTurn(1, 0, members)
  doAssert ledger.heartPairs().len == 0, "an opener alone earns nothing"
  ledger.creditTurn(1, 1, members)
  doAssert ledger.heartPairs() == @[(a: 0, b: 1, links: 1)],
    "the first reply starts the connection"
  ledger.creditTurn(1, 0, members)
  ledger.creditTurn(1, 1, members)
  doAssert ledger.heartPairs() == @[(a: 0, b: 1, links: 3)],
    "each answered turn adds one"
  # A lurker who never speaks earns nothing, even inside the circle.
  var trio: HeartLedger
  let three = @[0, 1, 2]
  trio.creditTurn(2, 0, three)
  trio.creditTurn(2, 1, three)
  trio.creditTurn(2, 0, three)
  var lurker = 0
  for pair in trio.heartPairs():
    if pair.a == 2 or pair.b == 2:
      lurker += pair.links
  doAssert lurker == 0, "a silent member earns nothing"
  trio.creditTurn(2, 2, three)
  var joined = 0
  for pair in trio.heartPairs():
    if pair.a == 2 or pair.b == 2:
      joined += pair.links
  doAssert joined == 2, "a spoken turn connects with the recent speakers"
  # After a full quiet round the conversation starts fresh for you.
  var stale: HeartLedger
  stale.creditTurn(3, 0, members)
  for _ in 0 ..< 5:
    stale.creditTurn(3, 1, members)
  doAssert stale.heartPairs() == @[(a: 0, b: 1, links: 1)],
    "a monologue runs out of recent partners"
  # sqrt scoring: breadth beats farming one partner.
  var farm: HeartLedger
  for i in 0 ..< 16:
    farm.creditTurn(4, i mod 2, members)
  doAssert farm.connectionScore(0) * farm.connectionScore(0) <= 16.0,
    "farming one partner is priced by the square root"

echo "Testing heart links from conversation records"
block:
  # The replay-side fold: links rebuilt purely from convo rows.
  proc row(tick: int, kind, text: string, seat: int): string =
    $(%*{"kind": kind, "tick": tick, "seat": seat, "text": text})
  let log = @[
    row(100, "convo-enter", "enter id=1 members=Ivan, Anton", 0),
    row(110, "convo-tick", "tick id=1 ct=1 speaker=Ivan silent=false", 0),
    row(140, "convo-tick", "tick id=1 ct=2 speaker=Anton silent=false", 1),
    row(170, "convo-tick", "tick id=1 ct=3 speaker= silent=true", 0),
    row(200, "convo-tick", "tick id=1 ct=4 speaker=Ivan silent=false", 0),
    row(230, "convo-exit", "exit id=1", 1)
  ].join("\n")
  let timeline = parseConversationTimeline(log)
  doAssert timeline.heartLinksAt(90).len == 0, "nothing before the talk"
  doAssert timeline.heartLinksAt(120).len == 0,
    "the opener alone mints nothing"
  doAssert timeline.heartLinksAt(150) == @[(a: 0, b: 1, links: 1)],
    "the reply mints one"
  doAssert timeline.heartLinksAt(180) == @[(a: 0, b: 1, links: 1)],
    "a silent slot mints nothing"
  doAssert timeline.heartLinksAt(300) == @[(a: 0, b: 1, links: 2)],
    "the answered turn mints again; scrubbing anywhere reproduces it"

echo "Testing voice rows ride inside the replay"
block:
  # The record format: one debug-sprite row per baked clip, on the
  # channel the conversation rows use, keyed by seat and text.
  const TestSeed = 11
  let replayPath = getTempDir() / "heartleaf-voice-rows.bitreplay"
  var
    recSim = initSimServer(TestSeed)
    writer = openReplayWriter(replayPath, $(%*{"seed": TestSeed}))
  doAssert recSim.addPlayer("alice", 0) == 0
  writer.writeJoin(tickTime(0), 0, "alice", 0, "")
  writer.lastMasks.add(0)
  for tick in 0 ..< 10:
    if tick == 3:
      recSim.applyPlayerChat(0, "the well is dry")
      writer.writeChat(tickTime(recSim.tickCount), 0, "the well is dry")
    recSim.step(@[decodeInputMask(0)])
    writer.writeHash(uint32(recSim.tickCount), recSim.gameHash())
  writer.writeConversationRecord(tickTime(5), $(%*{
    "kind": "convo-enter", "tick": 5, "seat": 0,
    "text": "enter id=1 members=Ivan, Anton"
  }))
  let fakeClip = "not aac \x00\x01\x02\xff but bytes"
  writer.writeVoiceRecord(
    tickTime(9), 9, 0, "the well is dry", "m4a", fakeClip
  )
  writer.closeReplayWriter()

  let data = loadReplay(replayPath)
  let clips = data.replayVoiceClips()
  doAssert clips.len == 1, "one baked clip"
  var clip: VoiceClip
  doAssert clips.findVoiceClip(0, "the well is dry", clip),
    "the clip is found by seat and text"
  doAssert clip.codec == "m4a" and clip.tick == 9
  doAssert clip.voiceClipBytes() == fakeClip, "the bytes round trip"
  doAssert voiceContentType(clip.codec) == "audio/mp4"
  doAssert not clips.findVoiceClip(1, "the well is dry", clip),
    "another seat is another voice"
  doAssert not clips.findVoiceClip(0, "the well is wet", clip),
    "another text is another line"
  doAssert initReplayPlayer(data).voiceClips.len == 1,
    "the player loads the clips"
  doAssert "\"kind\":\"voice\"" notin data.conversationLogText(),
    "voice rows stay out of the conversation log"
  doAssert parseConversationTimeline(data.conversationLogText()).events.len == 1,
    "the conversation row beside the clip still reads"
  doAssert data.replayCirclesTimeline().len == 0,
    "voice rows are not circle rows"

  # Enriching a recording after the fact: copy every record, add a
  # clip, and the copy still validates tick for tick.
  var copy = data
  copy.addVoiceRecord(9, 0, "a second line", "mp3", "mp3 bytes")
  let copyPath = getTempDir() / "heartleaf-voice-rows-copy.bitreplay"
  writeReplayData(copyPath, copy)
  let reread = loadReplay(copyPath)
  doAssert reread.joins.len == 1 and reread.chats.len == 1 and
    reread.hashes.len == 10, "every record kind is copied"
  doAssert reread.replayVoiceClips().len == 2, "the added clip is there"
  doAssert reread.replayVoiceClips().findVoiceClip(0, "a second line", clip)
  doAssert voiceContentType(clip.codec) == "audio/mpeg"
  var
    playSim = initSimServer(TestSeed)
    replay = initReplayPlayer(reread)
  while replay.playing and replay.hashIndex < reread.hashes.len:
    replay.stepReplay(playSim)
  doAssert not replay.hashValidationFailed, "the copy validates"
  doAssert playSim.gameHash() == data.hashes[^1].hash

  removeFile(replayPath)
  removeFile(copyPath)

echo "Testing every heard line of a recording gets a clip"
block:
  # replaySpokenLines finds the lines the delay-chat feed will show by
  # playing the recording; the baker voices exactly those.
  let replayPath = getTempDir() / "heartleaf-voiced-village.bitreplay"
  let lines = writeVoicedTestReplay(replayPath)
  doAssert lines.len > 0, "some scripted line is heard by a neighbour"
  let data = loadReplay(replayPath)
  doAssert data.replayVoiceClips().len > 0
  var clip: VoiceClip
  for line in lines:
    doAssert data.replayVoiceClips().findVoiceClip(line.seat, line.text, clip),
      "a clip for " & line.text
    doAssert clip.voiceClipBytes() == fakeVoiceBytes(line.seat, line.text)
  doAssert data.replaySpokenLines() == lines,
    "the baked recording plays the same lines"
  var unheard = 0
  for chat in data.chats:
    var heard = false
    for line in lines:
      if line.text == chat.message:
        heard = true
    if not heard:
      inc unheard
  echo "Voiced village: ", lines.len, " heard lines, ", unheard,
    " unheard chats without clips"
  removeFile(replayPath)

echo "All tests passed"
