## Offline timing experiment using the real brain scheduler and a virtual clock.
## Run inside the project's Nim environment. No network or model calls.
import std/[json, math, os, sequtils, strutils, tables]
import bitworld/spriteprotocol
import heartleaf
import heartleaf/[brains, bedrock_client, common, protocol, souls, observation]

let days = if paramCount() >= 1: parseInt(paramStr(1)) else: 7
let latency = if paramCount() >= 2: parseFloat(paramStr(2)) else: 20.0
doAssert days > 0 and latency > 0
let planningMinutes = parseInt(getEnv("HEARTLEAF_PLAN_TURN_MINUTES", "60"))
let conversationGap = parseInt(getEnv("HEARTLEAF_CONVERSATION_GAP_MINUTES", "4"))
let conversationHold = parseFloat(getEnv("HEARTLEAF_CONVERSATION_TICK_SECONDS", "3"))
let planningBound = float(days) * ceil(float(DayTotalMinutes) / float(planningMinutes)) * latency
let conversationBound = float(days) * ceil(float(DayTotalMinutes) / float(conversationGap)) * conversationHold
let rolloverBound = float(days - 1) * latency
echo "DURATION_BOUND " & $(%*{
  "days": days, "planning_wait_seconds": planningBound,
  "conversation_wait_seconds": conversationBound,
  "day_rollover_in_flight_seconds": rolloverBound,
  "conservative_wait_bound_seconds": planningBound + conversationBound + rolloverBound,
  "assumptions": "Nine concurrent requests; every request terminates within the supplied latency; no retries; ignores startup, polling and CPU overhead. Conversation bound assumes every possible slot holds for its full duration; it is not a prediction."
})

for scenario in ["one_slow", "all_slow", "all_unusable"]:
  let sim = initSimServer(91002)
  let client = newScriptedBedrockClient()
  let minds = newBrains(sim.navigationFor(), sim.worldLayoutFor(), client, 1)
  minds.unusableAsWait = true
  for seat in 0 ..< HouseCount:
    doAssert sim.addPlayer("seat" & $seat, seat) == seat
    minds.attachSoul(seat, parseSoul("#!test-model\nYour name is {name}.\n"))
  var pending: seq[tuple[tag: string, due: float]]
  var now = 1000.0
  var seen, ticks, waits: int
  let totalTicks = gameTicksForDays(days, DayTicks)
  while ticks < totalTicks:
    for item in pending:
      if item.due <= now:
        client.scriptReply(BedrockReply(
          tag: item.tag, statusCode: 200,
          text: (if scenario == "all_unusable": "hello" else: "{\"action\":\"wait\"}")
        ))
    pending = pending.filterIt(it.due > now)
    var observations: Table[int, Observation]
    for seat in 0 ..< HouseCount:
      observations[seat] = sim.observe(seat)
    let frame = minds.advance(observations, now)
    while seen < client.started.len:
      let request = client.started[seen]
      let delay = if scenario == "one_slow" and request.playerSlot != 0: min(0.01, latency) else: latency
      pending.add((request.tag, now + delay))
      inc seen
    if frame.paused:
      doAssert pending.len > 0, "scheduler stalled without an outstanding call"
      now = pending.mapIt(it.due).min()
      inc waits
    else:
      var inputs = newSeq[InputState](HouseCount)
      for item in frame.outputs:
        inputs[item.houseIndex] = decodeInputMask(item.output.mask)
      sim.step(inputs)
      inc ticks
    doAssert now - 1000.0 <= planningBound + rolloverBound + 1.0, "unbounded wait or retry"
  echo "DURATION_RESULT " & $(%*{
    "scenario": scenario, "days": days, "agents": HouseCount,
    "virtual_wall_seconds": now - 1000.0, "calls": seen,
    "simulation_ticks": ticks, "model_delay_seconds": latency,
    "note": "Wait actions only: planning barriers, no conversations or real CPU/network time."
  })
