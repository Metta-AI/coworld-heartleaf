import
  std/[json, os, random, sequtils, sets, strutils, tables],
  bitworld/client as bitworldClient,
  bitworld/resources,
  bitworld/spriteprotocol,
  heartleaf,
  heartleaf/[common, protocol, decisions, souls, observation, navigation,
    villager, executor, report, prompt, pacing, bedrock_client, brains],
  replays

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
let inviteDecision = parseDecision("""
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
doAssert inviteDecision.action == SayToPerson, "action should match"
doAssert inviteDecision.targetName == "Ivan", "target should parse"
doAssert inviteDecision.houseIndex == 1, "house index should be zero based"
doAssert inviteDecision.message == "Come to my party?", "message should parse"
doAssert inviteDecision.commitParty, "commitment should parse"

let invalidDecision = parseDecision("""{"action": "dance"}""")
doAssert not invalidDecision.valid, "unknown actions should be invalid"

let fencedDecision = parseDecision("""
```json
{"action": "go_to_party", "houseIndex": 9, "commitParty": true}
```
""")
doAssert fencedDecision.valid, "fenced JSON should parse defensively"
doAssert fencedDecision.action == GoToParty, "party action should parse"
doAssert fencedDecision.houseIndex == 8, "house 9 should become index 8"

let trailing = parseDecision("""
{"action": "say_to_person", "targetName": "Kiran", "message": "Hi {there}"}
user(You now carry: Corn.) Return JSON now.
{"action": "go_home"}
""")
doAssert trailing.valid and trailing.action == SayToPerson,
  "only the first complete object counts, braces in strings included"
doAssert trailing.message == "Hi {there}"

let stringHouse = parseDecision("""
{"action": "go_to_party", "houseIndex": "4", "targetName": "Sasha"}
""")
doAssert stringHouse.valid, "string houseIndex should parse"
doAssert stringHouse.houseIndex == 3, "house 4 should become index 3"

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
{"action": "say_to_person", "targetName": "Anton", "message": "Vova: hi Anton"}
""", vova)
doAssert prefixedDecision.message == "hi Anton",
  "decision messages should lose the self label"
doAssert "today\u2014found pear\u2026 \u201cnice\u201d".cleanDecisionText() ==
  "today - found pear... \"nice\"", "model punctuation becomes ASCII"

echo "Testing untilTime parsing"
let untilDecision = parseDecision("""
{"action": "stand_at_house_garden", "houseIndex": 3, "untilTime": "5:15pm"}
""")
doAssert untilDecision.valid and untilDecision.untilMinutes == 17 * 60 + 15,
  "untilTime accepts am/pm clocks"
doAssert parseDecision("""{"action": "go_home", "untilTime": "18:30"}""")
  .untilMinutes == 18 * 60 + 30, "untilTime accepts 24h clocks"
doAssert parseDecision("""{"action": "go_home", "untilTime": 1110}""")
  .untilMinutes == 1110, "untilTime accepts day minutes"
doAssert parseDecision("""{"action": "go_home"}""").untilMinutes == -1,
  "untilTime defaults to none"

echo "Testing food name lists"
doAssert "Yellow Squash x2, Beet".foodNamesIn() ==
  @["Yellow Squash", "Beet"], "counts are stripped from food names"
doAssert "none".foodNamesIn().len == 0

echo "Testing the shared request budget"
block:
  var budget = newRequestBudget(42)
  budget.requestsPerMinute = 5
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
  budget.noteRequest(now + 4.0)
  budget.noteReply()
  budget.noteReply()
  doAssert budget.requestsInLastMinute(now + 5.0) == 5
  doAssert not budget.canRequest(now + 5.0), "the minute budget closes"
  doAssert budget.canRequest(now + 60.0), "the budget reopens after a minute"
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

echo "Testing the game clock fits the hosted deadline"
doAssert DayTotalMinutes == 12 * 60, "a day is twelve hours"
doAssert DayTicks == 180 * TicksPerSecond, "three-minute days"
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
  let sections = ["Response format:", "Conversation memory:", "Host or guest:",
    "Repeating yourself:", "Actions:", "Greeting:", "Vegetable hunt:"]
  var last = 0
  for section in sections:
    let at = text.find(section)
    doAssert at > last, section & " should follow the previous section"
    last = at
  doAssert text.endsWith(MechanicsBlock), "the mechanics come last"
  let bare = systemPrompt(parseSoul("#!m\nJust a soul.\n"), "Ivan")
  doAssert bare.startsWith("Your name is Ivan. You are a Heartleaf gnome player."),
    "a soul without {name} gets a name line"

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
  var answered = 0
  proc answer(text: string) =
    client.scriptReply(BedrockReply(
      tag: client.started[answered].tag, statusCode: 200, text: text
    ))
    inc answered
  answer("""{"action": "go_to_party", "houseIndex": 2, "commitParty": true}""")
  now += 0.1
  frame = brains.advance(observations(), now)
  doAssert not frame.paused, "one decided villager keeps the clock running"
  doAssert frame.blockedNames == @["Anton"], "the other one still waits"
  doAssert brains.villagers[0].committedPartyHouse == 1
  var ticks = 0
  var chatsSeen: seq[string]
  proc runTicks(untilDone: proc(): bool, limit: int) =
    var steps = 0
    while steps < limit and not untilDone():
      now += 0.05
      frame = brains.advance(observations(), now)
      while answered < client.started.len:
        let house = client.started[answered].tag.split(':')[0]
        if house == "0" and sim.playerMapIndex(0) == 2:
          answer("""{"action": "say_to_person", "targetName": "Anton", "message": "hello there"}""")
        elif house == "0":
          answer("""{"action": "go_to_party", "houseIndex": 2, "commitParty": true}""")
        else:
          answer("""{"action": "stay_inside"}""")
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
  runTicks(proc(): bool = sim.playerMapIndex(0) == 2, 2400)
  doAssert sim.playerMapIndex(0) == 2,
    "alice should walk out of her house and into Anton's"
  doAssert sim.playerMapIndex(1) == 2, "bob stays home"
  block:
    # Curfew: run the clock to 9pm with alice still at Anton's. She loses
    # 3 points, bob at home loses nothing, and alice's transcript says so.
    var ended = 0
    while not sim.scoreScreenActive() and ended < 5000:
      sim.step(newSeq[InputState](2))
      inc ended
    doAssert sim.scoreScreenActive(), "the day should end"
    doAssert sim.playerScore(0) == -CurfewPenalty, "away from home at 9pm costs 3"
    doAssert sim.playerScore(1) == 0, "bob was home"
    now += 0.05
    frame = brains.advance(observations(), now)
    doAssert frame.paused == false, "the score screen keeps stepping"
    var curfewLines = 0
    for line in brains.villagers[0].history:
      if line.content.startsWith("(Curfew:"):
        inc curfewLines
    doAssert curfewLines == 1, "alice hears about the penalty once"
    for line in brains.villagers[1].history:
      doAssert not line.content.startsWith("(Curfew:"), "bob hears nothing"
  runTicks(proc(): bool = chatsSeen.len > 0, 600)
  doAssert chatsSeen == @["hello there"], "alice greets Anton once next to him"
  doAssert "hello there" in brains.villagers[0].saidToday
  doAssert "Anton" in brains.villagers[0].greetedToday
  let before = chatsSeen.len
  runTicks(proc(): bool = false, 120)
  doAssert chatsSeen.len == before, "the same line is never said twice a day"
  var history: seq[string]
  for line in brains.villagers[0].history:
    history.add(line.content)
  doAssert "(Day 1 begins.)" in history
  doAssert "(You see Anton for the first time today.)" in history
  doAssert "hello there" in history, "own chat lands in the history"
  doAssert history.anyIt(it.startsWith("Day 1 ") and "until dinner" in it),
    "every state report stays in the history"
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
  var turns = 0
  for entry in logged:
    let node = parseJson(entry)
    if node["index"].getInt() >= 0:
      doAssert node["text"].getStr() == history[node["index"].getInt()],
        "log entries mirror the history exactly"
      inc turns
  doAssert turns == history.len, "the log holds the whole history"
  # Append-only: what was sent stays sent.
  let prefix = history
  runTicks(proc(): bool = false, 60)
  doAssert brains.villagers[0].history.len >= prefix.len
  for i, content in prefix:
    doAssert brains.villagers[0].history[i].content == content,
      "the history is never rewritten"

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

echo "All tests passed"
