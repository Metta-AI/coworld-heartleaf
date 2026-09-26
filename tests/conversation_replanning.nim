## A conversation that ends during a movement phase must release both gnomes
## into fresh plans without restarting the unrelated villagers' plans.
import std/[algorithm, os, sequtils, tables]
import heartleaf
import heartleaf/[brains, bedrock_client, decisions, executor, observation, protocol,
  souls, villager]

putEnv("HEARTLEAF_CONVERSATION_GAP_MINUTES", "1")
putEnv("HEARTLEAF_CONVERSATION_TICK_SECONDS", "0.5")

let
  sim = initSimServer(51)
  client = newScriptedBedrockClient()
  minds = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, 51)
  soul = parseSoul("#!test-model\nYou are {name}.")

var observations: Table[int, Observation]
for seat in 0 .. 2:
  discard sim.addPlayer(seat.playerNameForHouse(), seat)
  minds.attachSoul(seat, soul)
  observations[seat] = sim.observe(seat)
  observations[seat].scene = Outdoors

# Make the pair visible to each other and give everyone an existing movement-turn
# action. Seat 2 is the control: ending seats 0/1's chat must not replan it.
observations[0].visiblePlayers = @[
  VisiblePlayer(name: 1.playerNameForHouse(), houseIndex: 1,
    foot: observations[0].foot)
]
observations[1].visiblePlayers = @[
  VisiblePlayer(name: 0.playerNameForHouse(), houseIndex: 0,
    foot: observations[1].foot)
]
for seat in 0 .. 1:
  minds.villagers[seat].applyDecision(
    observations[seat], minds.layout, waitDecision(), fromModel = false)
  minds.villagers[seat].turnReady = true
let controlDecision = parseDecision("{\"action\":\"gather_plants\"}")
minds.villagers[2].applyDecision(
  observations[2], minds.layout, controlDecision, fromModel = false)
minds.villagers[2].turnReady = true

discard minds.joinOrStartTalk(minds.villagers[0], 1.playerNameForHouse())
minds.phase = MovePhase
minds.moveTicksLeft = 100

var now = 0.0
proc advanceUntilStarted(count: int): BrainFrame =
  var tries = 0
  while client.started.len < count and tries < 20:
    now += 0.1
    for observation in observations.mvalues:
      inc observation.tick
    result = minds.advance(observations, now)
    inc tries
  doAssert client.started.len == count

# Let seat 0's first conversation request miss its slot but stay in flight.
# The next slot asks seat 1, whose bye dissolves the pair while seat 0 still has
# a stale conversation reply outstanding.
doAssert advanceUntilStarted(1).paused
doAssert client.started.len == 1 and client.started[0].playerSlot == 0
let staleConversation = client.started[0]
now += 1.0
discard minds.advance(observations, now)
doAssert advanceUntilStarted(2).paused
doAssert client.started.len == 2 and client.started[1].playerSlot == 1
client.scriptReply(BedrockReply(
  tag: client.started[1].tag,
  statusCode: 200,
  text: "{\"action\":\"bye\",\"message\":\"See you later.\"}"))

now += 0.1
let released = minds.advance(observations, now)
doAssert released.paused,
  "the world must hold while both released gnomes choose what to do next"
doAssert not minds.villagers[0].talking and not minds.villagers[1].talking
doAssert client.started.len == 4,
  "bye must immediately request a new plan for the speaker and dissolved singleton"
let replans = client.started[2 .. 3]
doAssert replans.mapIt(it.playerSlot).sorted() == @[0, 1]
doAssert client.started.allIt(it.playerSlot != 2),
  "an unrelated gnome must keep its current movement plan"
doAssert minds.villagers[2].decision.action == GatherPlants

# A reply from seat 0's abandoned conversation request must not become its new
# outdoor plan. The two fresh replies should release the same movement turn.
client.scriptReply(BedrockReply(
  tag: staleConversation.tag,
  statusCode: 200,
  text: "{\"action\":\"say\",\"message\":\"This reply is stale.\"}"))
for request in replans:
  client.scriptReply(BedrockReply(
    tag: request.tag,
    statusCode: 200,
    text: if request.playerSlot == 0:
      "{\"action\":\"gather_plants\"}"
    else:
      "{\"action\":\"wander\"}"))
now += 0.1
let resumed = minds.advance(observations, now)
doAssert not resumed.paused
doAssert minds.phase == MovePhase
doAssert minds.villagers[0].decision.action == GatherPlants
doAssert minds.villagers[1].decision.action == Wander
doAssert minds.villagers[2].decision.action == GatherPlants
doAssert minds.moveTicksLeft < 100,
  "conversation replanning resumes the existing movement turn"

echo "Conversation release replans both participants, drops stale replies, and preserves unrelated plans."
