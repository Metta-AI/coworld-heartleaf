## Offline player-visible JSONL bridge through Heartleaf's real scheduler.
import std/[json, os, posix, strutils, tables]
import heartleaf
import bitworld/spriteprotocol
import heartleaf/[common, protocol, decisions, observation, brains, bedrock_client,
    souls, villager]

const DinnerObjective = """Training objective (heartleaf-dinner-training-v1):
The terminal score is the game's dinner score, not connection points.
Hosting earns the number of food items served times the number of guests.
Eating earns the game's food-variety points. Connection points are diagnostic
and do not determine the winner in this evaluation. Stay at dinner until 9pm."""

var
  protocolOutput: File
  sim: SimServer
  brain: Brains
  client: BedrockClient
  players: int
  cursor = 0
  serial = 0
  clock = 0.0
  initialized = false
  finished = false

# Existing engine diagnostics use echo. Keep them off the JSONL transport.
doAssert open(protocolOutput, FileHandle(dup(STDOUT_FILENO)), fmWrite)
doAssert dup2(STDERR_FILENO, STDOUT_FILENO) >= 0

let days = if paramCount() == 0: DefaultDayCount else: parseInt(paramStr(1))
doAssert paramCount() <= 1 and days in 1 .. DefaultDayCount

proc advance() =
  var observations = initTable[int, Observation]()
  for seat in 0 ..< players:
    observations[seat] = sim.observe(seat)
  let frame = brain.advance(observations, clock)
  clock += 0.001
  if not frame.paused:
    var inputs = newSeq[InputState](players)
    for item in frame.outputs:
      inputs[item.houseIndex] = decodeInputMask(item.output.mask)
      if item.output.chat.len > 0:
        sim.applyPlayerChat(item.houseIndex, item.output.chat)
    sim.step(inputs)

proc nextObservation(): JsonNode =
  var advances = 0
  while cursor >= client.started.len:
    inc advances
    doAssert advances <= gameTicksForDays(days, DayTicks) * 100, "Scheduler made no bounded progress"
    if sim.tickCount >= gameTicksForDays(days, DayTicks):
      finished = true
      var scores = newJObject()
      let actual = parseJson(sim.dailyResultsJson())["scores"]
      for seat in 0 ..< players:
        scores[$seat] = actual[seat]
      return %*{"kind": "terminal", "scores": scores}
    advance()
  let request = client.started[cursor]
  var messages = newJArray()
  for message in request.messages:
    messages.add(%*{"role": message.role, "content": message.content})
  %*{
    "kind": "decision", "decision_id": serial,
    "seat": request.playerSlot, "turn": brain.turnIndex,
    "messages": messages,
    "action_schema": {
      "type": "object", "required": ["action"],
      "properties": {
        "action": {"type": "string", "enum": ["gather_plants", "talk_to", "say", "bye",
            "follow", "go_home", "go_to_house", "go_to_garden", "wait", "wander"]},
        "targetName": {"type": "string"}, "message": {"type": "string"}, "reason": {
            "type": "string"}
    }
  }
  }

proc execute(command: JsonNode): JsonNode =
  case command["kind"].getStr()
  of "reset":
    players = command["players"].getInt()
    doAssert players in 1 .. HouseCount
    let seed = parseInt(command["seed"].getStr())
    sim = initSimServer(seed)
    sim.seatCount = players
    client = newScriptedBedrockClient()
    brain = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, seed)
    brain.unusableAsWait = true
    brain.timeoutAsWait = true
    for seat in 0 ..< players:
      doAssert sim.addPlayer(PlayerNames[seat], seat) == seat
      brain.attachSoul(seat, Soul(modelId: "offline/training",
          text: "Play to maximize your terminal dinner score.", seat: seat))
      # Version only this offline condition; historical and hosted prompts stay intact.
      let original = brain.villagers[seat].systemPrompt
      let start = original.find("Connections and winning:")
      let stop = original.find("\n\nHouses:", start)
      doAssert start >= 0 and stop > start
      brain.villagers[seat].systemPrompt = original[0 ..< start] & DinnerObjective &
          original[stop .. ^1]
    cursor = 0
    serial = 0
    clock = 0
    initialized = true
    finished = false
    return nextObservation()
  of "step":
    if not initialized or finished:
      return %*{"kind": "rejected", "reason": "No active decision; reset the game."}
    if command["decision_id"].getInt() != serial:
      return %*{"kind": "rejected", "reason": "Stale decision_id."}
    let request = client.started[cursor]
    let response = command["response"].getStr()
    let villager = brain.villagers[request.playerSlot]
    let decision = parseDecision(response, villager.selfNames())
    let rejection = villager.modeError(decision)
    client.scriptReply(BedrockReply(tag: request.tag, statusCode: 200, text: response))
    inc cursor
    inc serial
    # Apply this reply before exposing another decision, even when requests were batched.
    advance()
    let observation = nextObservation()
    if rejection.len > 0:
      return %*{"kind": "consumed_rejection", "reason": rejection,
        "action": {"action": "wait"}, "observation": observation}
    return %*{"kind": "accepted", "action": {
      "action": decision.action.actionName(), "targetName": decision.targetName,
      "message": decision.message, "reason": decision.reason
    }, "observation": observation}
  else:
    raise newException(ValueError, "Unknown bridge command")

for line in stdin.lines:
  let result = execute(parseJson(line))
  protocolOutput.writeLine($result)
  protocolOutput.flushFile()
