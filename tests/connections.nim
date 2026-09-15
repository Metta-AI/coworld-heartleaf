## Relationship semantics, real brain request lifecycle, and replay folding.
import std/[json, os, sequtils, strutils, tables]
import heartleaf, replays
import heartleaf/[brains, bedrock_client, common, connections, decisions, encounters,
  observation, protocol, souls, villager]

proc interview(seat,day:int, order:seq[int]): Interview =
  result = Interview(seat:seat,day:day,valid:true)
  for other in order:
    result.ranking.add(Ranking(seat:other,reason:"Kept a promise."))
proc reply(order:seq[int]):string =
  var rows = newJArray()
  for seat in order: rows.add(%*{"name":seat.playerNameForHouse(),"reason":"Kept a promise."})
  $(%*{"ranking":rows})

block:
  var ledger = initConnections(@[2,0,1,1])
  doAssert ledger.seats == @[0,1,2] and ledger.bonds.len == 3
  doAssert ledger.bonds.connectionScore(0) == 1.0
  for bond in ledger.bonds: doAssert bond.strength == 0.5
  doAssert rankContribution(1,8) == 0.5 and rankContribution(8,8) == -0.5
  doAssert rankContribution(1,1) == 0 and rankContribution(1,0) == 0
  let rows = {0:interview(0,1,@[1,2]),1:interview(1,1,@[0,2]),
    2:interview(2,1,@[0,1])}.toTable
  let before = ledger.bonds
  doAssert ledger.applyDay(1,rows)
  doAssert before.strength(0,1) == 0.5, "old snapshots must stay immutable"
  doAssert ledger.bonds.strength(0,1) == 1.0
  doAssert ledger.bonds.strength(1,2) == 0.0
  doAssert ledger.bonds.strength(0,2) == 0.5
  doAssert not ledger.applyDay(1,rows), "once per day"
  var next = rows
  for row in next.mvalues: row.day = 2
  doAssert ledger.applyDay(2,next)
  doAssert ledger.bonds.strength(0,1) == 1 and ledger.bonds.strength(1,2) == 0
  next = {0:interview(0,3,@[2,1])}.toTable
  doAssert ledger.applyDay(3,next)
  doAssert ledger.bonds.strength(0,1) == 0.75, "missing partner contributes zero"
  doAssert parseInterview(reply(@[1,2]),0,1,@[0,1,2]).valid
  for text in ["garbage","{}",reply(@[1,1]),reply(@[0,2]),reply(@[1]),reply(@[1,8])]:
    doAssert not parseInterview(text,0,1,@[0,1,2]).valid, text

block:
  let initial = initConnections(@[0,1,2])
  var changed = initial
  discard changed.applyDay(1,{0:interview(0,1,@[1,2]),1:interview(1,1,@[0,2])}.toTable)
  let text = ConnectionEvent(kind:"connection-start",tick:0,seats:initial.seats,bonds:initial.bonds).record & "\n" &
    ConnectionEvent(kind:"connection-update",tick:100,day:1,seats:changed.seats,bonds:changed.bonds).record & "\n" &
    ConnectionEvent(kind:"connection-emoji",tick:20,seat:0,target:1,emotion:VerySad).record
  let timeline = parseConnections(text)
  doAssert timeline.events.len == 3
  doAssert timeline.bondsAt(100).strength(0,1) == 1
  doAssert timeline.bondsAt(99).strength(0,1) == 0.5
  doAssert timeline.bondsAt(0).strength(0,1) == 0.5
  doAssert parseConnections("not JSON\n{\"kind\":\"connection-update\",\"version\":9}").events.len == 0
  doAssert parseConnections("").bondsAt(100).len == 0, "old replay has no invented ranking"

# Both normal play and strict evaluation must retain the bedtime lifecycle.
for strictEval in [false, true]:
  let sim = initSimServer(22)
  let client = newScriptedBedrockClient()
  let minds = newBrains(sim.navigationFor(),sim.worldLayoutFor(),client,22)
  minds.unusableAsWait = strictEval
  let soul = parseSoul("#!test-model\nYou are {name}.")
  var obs: Table[int,Observation]
  for seat in 0..2:
    discard sim.addPlayer(seat.playerNameForHouse(),seat)
    minds.attachSoul(seat,soul)
    obs[seat] = sim.observe(seat)
  discard minds.advance(obs,0)
  let stale = client.started[0]
  for request in client.started:
    client.scriptReply(BedrockReply(tag:request.tag,statusCode:200,text:"{\"action\":\"wait\"}"))
  discard minds.advance(obs,1)
  doAssert minds.connections.bonds.connectionScore(0) == 1
  for value in obs.mvalues:
    value.tick = DayTicks
    value.minutes = DayEndMinutes
    value.scene = Overlay
  let first = client.started.len
  doAssert minds.advance(obs,2).paused
  doAssert client.started.len == first+3
  for request in client.started[first..^1]:
    doAssert request.maxTokens >= 1000
    doAssert "Bedtime interview" in request.messages[^1].content
    let order = if request.playerSlot == 0: @[1,2]
      elif request.playerSlot == 1: @[0,2] else: @[0,1]
    client.scriptReply(BedrockReply(tag:request.tag,statusCode:200,text:reply(order)))
  doAssert not minds.advance(obs,3).paused
  doAssert minds.connections.bonds.strength(0,1) == 1
  let count = minds.connectionTimeline.events.len
  discard minds.advance(obs,4)
  doAssert minds.connectionTimeline.events.len == count
  client.scriptReply(BedrockReply(tag:stale.tag,statusCode:200,text:reply(@[2,1])))
  discard minds.advance(obs,5)
  doAssert minds.connectionTimeline.events.len == count, "stale reply ignored"
  for value in obs.mvalues: value.dayNumber=2
  doAssert minds.advance(obs,6).paused
  doAssert not minds.advance(obs,52).paused, "deadline releases the world"
  doAssert minds.connections.appliedDay == 2
  doAssert minds.connections.bonds.strength(0,1) == 1, "unavailable interviews are neutral"
  minds.resetForNewGame()
  doAssert minds.connections.bonds.len == 0 and minds.connectionTimeline.events.len == 0
  for value in obs.mvalues:
    value.dayNumber=1
    value.minutes=DayStartMinutes
    value.scene=Outdoors
  discard minds.advance(obs,53)
  let newTag = client.started[^1].tag
  doAssert newTag != stale.tag
  client.scriptReply(BedrockReply(tag:stale.tag,statusCode:200,text:reply(@[2,1])))
  discard minds.advance(obs,54)
  doAssert minds.villagers[0].requestInFlight, "a prior game's reply cannot settle a new request"

# Failed interviews are recorded as unavailable, not ordinary missed actions.
block:
  let sim = initSimServer(25)
  let client = newScriptedBedrockClient()
  let minds = newBrains(sim.navigationFor(),sim.worldLayoutFor(),client,25)
  minds.unusableAsWait = true
  var obs: Table[int,Observation]
  for seat in 0..1:
    discard sim.addPlayer(seat.playerNameForHouse(),seat)
    minds.attachSoul(seat,parseSoul("#!test-model\nYou are {name}."))
    obs[seat] = sim.observe(seat)
    obs[seat].minutes = DayEndMinutes
    obs[seat].scene = Overlay
  doAssert minds.advance(obs,0).paused
  for request in client.started:
    client.scriptReply(BedrockReply(tag:request.tag,error:"Timeout was reached"))
  doAssert not minds.advance(obs,1).paused
  let reviews = minds.connectionTimeline.events.filterIt(it.kind == "connection-interview")
  doAssert reviews.len == 2 and reviews.allIt(not it.interview.valid)
  doAssert minds.connections.appliedDay == 1
  doAssert minds.connections.bonds.strength(0,1) == 0.5

block:
  let sim = initSimServer(23)
  let client = newScriptedBedrockClient()
  let minds = newBrains(sim.navigationFor(),sim.worldLayoutFor(),client,23)
  for seat in 0..1:
    discard sim.addPlayer(seat.playerNameForHouse(),seat)
    minds.attachSoul(seat,parseSoul("#!test-model\nYou are {name}."))
  var obs = {0:sim.observe(0),1:sim.observe(1)}.toTable
  obs[0].visiblePlayers = @[VisiblePlayer(name:"Anton",houseIndex:1,foot:obs[0].foot)]
  discard minds.advance(obs,0)
  for request in client.started:
    let text = if request.playerSlot == 0:
      "{\"action\":\"send_emoji\",\"targetName\":\"Anton\",\"emotion\":\"very_happy\"}"
      else: "{\"action\":\"wait\"}"
    client.scriptReply(BedrockReply(tag:request.tag,statusCode:200,text:text))
  discard minds.advance(obs,1)
  let reactions = minds.connectionTimeline.events.filterIt(it.kind == "connection-emoji")
  doAssert reactions.len == 1 and reactions[0].emotion == VeryHappy
  doAssert minds.connections.bonds.strength(0,1) == 0.5
  doAssert minds.villagers[1].history.anyIt("sent you very_happy" in it.content)
  let invalid = parseDecision("{\"action\":\"send_emoji\",\"targetName\":\"Ivan\",\"emotion\":\"love\"}")
  doAssert not minds.villagers[0].modeAllows(invalid)

echo "Connections: math, interviews, deadlines, stale replies, reset, emoji and replay checks passed."

# A slow opt-in transport must be allowed to finish a real interview after 45s,
# while remaining bounded and still discarding late replies after its deadline.
block:
  let previous = getEnv("HEARTLEAF_INTERVIEW_TIMEOUT_SECONDS")
  try:
    putEnv("HEARTLEAF_INTERVIEW_TIMEOUT_SECONDS","300")
    let sim = initSimServer(24)
    let client = newScriptedBedrockClient()
    let minds = newBrains(sim.navigationFor(),sim.worldLayoutFor(),client,24)
    var obs:Table[int,Observation]
    for seat in 0..2:
      discard sim.addPlayer(seat.playerNameForHouse(),seat)
      minds.attachSoul(seat,parseSoul("#!test-model\nYou are {name}."))
      obs[seat] = sim.observe(seat)
      obs[seat].minutes = DayEndMinutes
      obs[seat].scene = Overlay
    doAssert minds.advance(obs,0).paused
    doAssert minds.advance(obs,46).paused, "local override waits beyond the default"
    for request in client.started:
      let order = if request.playerSlot == 0: @[1,2]
        elif request.playerSlot == 1: @[0,2] else: @[0,1]
      client.scriptReply(BedrockReply(tag:request.tag,statusCode:200,text:reply(order)))
    doAssert not minds.advance(obs,70).paused
    doAssert minds.connections.bonds.strength(0,1) == 1
    for value in obs.mvalues: value.dayNumber=2
    doAssert minds.advance(obs,71).paused
    doAssert not minds.advance(obs,372).paused, "the opt-in hold still expires"
    doAssert minds.connections.bonds.strength(0,1) == 1
  finally:
    if previous.len > 0: putEnv("HEARTLEAF_INTERVIEW_TIMEOUT_SECONDS",previous)
    else: delEnv("HEARTLEAF_INTERVIEW_TIMEOUT_SECONDS")
echo "Slow local interview window: delayed valid replies and bounded failure passed."

# Morning must remove yesterday's book membership before startNewDay
# resets local ids. Old groups must not claim a new conversation's speaker.
block:
  let sim = initSimServer(42)
  let minds = newBrains(sim.navigationFor(),sim.worldLayoutFor(),newScriptedBedrockClient(),42)
  let soul = parseSoul("#!test-model\nYou are {name}.")
  var obs:Table[int,Observation]
  for seat in 0..2:
    discard sim.addPlayer(seat.playerNameForHouse(),seat)
    minds.attachSoul(seat,soul)
    obs[seat] = sim.observe(seat)
    obs[seat].dayNumber = 2
  discard minds.joinOrStartTalk(minds.villagers[0],"Anton")
  discard minds.joinOrStartTalk(minds.villagers[0],"Yura")
  doAssert minds.book.encounters.len==1
  discard minds.advance(obs,1)
  doAssert minds.book.encounters.len==0
  for v in minds.villagers.values: doAssert v.encounterId==0
  let newGroup = minds.joinOrStartTalk(minds.villagers[1],"Yura")
  doAssert newGroup.id==2 and newGroup.members.len==2
  doAssert minds.villagers[1].encounterId==minds.villagers[2].encounterId

block:
  let timeline = parseConversationTimeline("""
{"kind":"convo-enter","tick":10,"day":1,"seat":0,"text":"conversation id=1 members=Ivan,Anton turn=1"}
{"kind":"connection-action","tick":100,"day":2}
{"kind":"convo-tick","tick":110,"day":2,"seat":0,"text":"conversation id=1 silent=false"}
{"kind":"convo-enter","tick":120,"day":2,"seat":1,"text":"conversation id=2 members=Anton,Yura turn=2"}
""")
  doAssert timeline.encounterGroupsAt(99).len==1
  doAssert timeline.encounterGroupsAt(110).len==0
  doAssert timeline.encounterGroupsAt(120)[0].id==2
  let spans = timeline.conversationSpans(200)
  doAssert spans.len==2 and spans[0].deathTick==100 and spans[1].birthTick==120
  echo "Overnight encounter cleanup and old-replay boundaries passed"
