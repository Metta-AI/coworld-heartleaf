## A reproducible local viewer exercise, with authored decisions and dialogue.
## Uses the normal movement executor and simulation; no teleports, edited
## hashes, model calls or borrowed recording. This is a scripted test game,
## not a claim about autonomous model behavior.
## nim r tools/record_connection_scenario.nim OUTPUT.replay
import std/[importutils, json, os, tables, strutils], heartleaf, replays
import heartleaf/[common, decisions, executor, protocol, souls, villager, brains, bedrock_client, observation, connections]
import bitworld/spriteprotocol
privateAccess(SimServer)

let output = if paramCount()>0: paramStr(1) else: "out/connections-scenario.replay"
const Seed = 7301
const DayTicks = 4320
let sim = initSimServer(Seed, DayTicks)
let nav = sim.navigationFor()
let layout = sim.worldLayoutFor()
var actors: seq[Villager]
let client = newScriptedBedrockClient()
let minds = newBrains(nav,layout,client,Seed)
var answered = 0
var writer = openReplayWriter(output, $(%*{"seed":Seed,"daySeconds":DayTicks div 24,
  "scenario":"authored two-day connection review; scripted model replies, not autonomous LLM behavior"}))
writer.lastMasks.setLen(9)
for seat in 0..<9:
  let name = seat.playerNameForHouse()
  discard sim.addPlayer(name,seat)
  writer.writeJoin(0,seat,name,seat,"")
  minds.attachSoul(seat,parseSoul("#!test-model\nYou are {name}."))
  actors.add(minds.villagers[seat])

proc decide(seat:int, action:Action, house = -1, target="") =
  actors[seat].applyDecision(sim.observe(seat),layout,
    Decision(valid:true,action:action,houseIndex:house,targetName:target),false)
  writer.writeConversationRecord(tickTime(sim.tickCount),ConnectionEvent(
    kind:"connection-action",tick:sim.tickCount,day:sim.observe(seat).dayNumber,
    seat:seat,action:action.actionName() &
      (if target.len>0: " " & target elif house>=0: " " & house.playerNameForHouse() else: ""),
    reason:"Authored review scenario.").record())
proc recordEvent(seat:int, kind,text:string) =
  let row = $(%*{"tick":sim.tickCount,"seat":seat,"kind":kind,"text":text})
  var bytes: seq[uint8]
  for c in row: bytes.add(uint8(c))
  writer.writeDebugSprite(tickTime(sim.tickCount),seat,bytes)
proc say(seat:int, message:string) =
  sim.applyPlayerChat(seat,message)
  writer.writeChat(tickTime(sim.tickCount),seat,message)

const Lines = [
  "I found carrots by the garden. Shall we bring some to dinner?",
  "Yes! I will bring cabbage. Save me a seat beside you.",
  "The paths are busy today. Let us meet by the old tree first.",
  "I can see the others arriving. There is room for everyone.",
  "We have enough vegetables to share with the whole table.",
  "Thank you. Tomorrow I will gather fruit for our next meal."
]
proc observations():Table[int,Observation] =
  for seat in 0..<9: result[seat]=sim.observe(seat)
proc respond() =
  while answered < client.started.len:
    let request = client.started[answered]
    inc answered
    var answer = "{\"action\":\"wait\"}"
    if "Bedtime interview" in request.messages[^1].content:
      var ranking = newJArray()
      let buddy = if request.playerSlot < 8: request.playerSlot xor 1 else: 0
      ranking.add(%*{"name":buddy.playerNameForHouse(),"reason":"You shared dinner and kept your promise."})
      for other in 0..<9:
        if other notin [request.playerSlot,buddy]:
          ranking.add(%*{"name":other.playerNameForHouse(),"reason":"We had less time together today."})
      answer = $(%*{"ranking":ranking})
    elif sim.tickCount mod 4560 == 844 and request.playerSlot < 6:
      answer = $(%*{"action":"send_emoji","targetName":(request.playerSlot xor 1).playerNameForHouse(),
        "emotion":["very_happy","happy","sad","very_sad"][request.playerSlot mod 4]})
    client.scriptReply(BedrockReply(tag:request.tag,statusCode:200,text:answer))
proc drain() =
  for line in minds.gameLog.conversationLines:
    writer.writeConversationRecord(tickTime(sim.tickCount),line)
  minds.gameLog.conversationLines.setLen(0)
for absoluteTick in 0..<9120:
  let tick = absoluteTick mod 4560
  for seat in 0..<9: actors[seat].observeWorld(sim.observe(seat),nav,layout)
  if tick in [0,844] or sim.observe(0).minutes >= DayEndMinutes:
    if tick in [0,844]:
      minds.phase = LlmPhase
      for actor in actors: actor.turnReady = false
    var frame = minds.advance(observations(),absoluteTick.float)
    var attempts = 0
    while frame.paused:
      respond()
      frame = minds.advance(observations(),absoluteTick.float+0.01)
      inc attempts
      doAssert attempts < 5, "scripted interview must settle"
    drain()
  if tick == 0:
    for seat in 0..<9: decide(seat,GoToGarden, (seat div 2)*2)
  if tick == 600:
    for seat in 0..<6:
      if seat mod 2 == 0: decide(seat,Wait)
      else: decide(seat,TalkTo,target=(seat-1).playerNameForHouse())
  if tick == 800:
    for seat in 0..<6: decide(seat,Wait)
    for pair in 0..<3:
      let seat = pair*2
      doAssert sim.playerMapIndex(seat)==0 and sim.playerMapIndex(seat+1)==0
      recordEvent(seat,"convo-enter","enter id=" & $(pair+1+3*(absoluteTick div 4560)) & " members=" &
        seat.playerNameForHouse() & "," & (seat+1).playerNameForHouse() & " turn=0")
  if tick >= 820 and tick < 1108 and (tick-820) mod 48 == 0:
    let turn = (tick-820) div 48
    for pair in 0..<3:
      let seat = pair*2+turn mod 2
      say(seat,Lines[turn])
      doAssert sim.replayChatAudience(seat).len > 0, "conversation must have a real listener"
      recordEvent(seat,"convo-tick","tick id=" & $(pair+1+3*(absoluteTick div 4560)) & " ct=" & $(turn+1) & " silent=false")
  if tick == 1200:
    for pair in 0..<3: recordEvent(pair*2,"convo-exit","exit id=" & $(pair+1+3*(absoluteTick div 4560)))
  if tick == 1600:
    for seat in 0..<9:
      decide(seat,GoToHouse,(if seat < 2:0 elif seat < 4:2 else:seat))
  if tick in [2600,2648,2696,2744]:
    let seat = (tick-2600) div 48
    doAssert sim.playerMapIndex(seat)==(if seat<2:1 else:3), "dinner guests must arrive through the doors"
    say(seat,Lines[seat+1])
  var inputs: seq[InputState]
  for seat in 0..<9:
    let input = actors[seat].villagerTick(sim.observe(seat),nav,layout)
    writer.writeInputMaskChange(tickTime(absoluteTick),seat,input.mask)
    inputs.add(decodeInputMask(input.mask))
  sim.step(inputs)
  writer.writeHash(uint32(sim.tickCount),sim.gameHash())
writer.closeReplayWriter()
let data = loadReplay(output)
let check = initSimServer(Seed,DayTicks)
var playback = initReplayPlayer(data)
playback.looping = false
while playback.playing:
  playback.stepReplay(check)
  doAssert not playback.hashValidationFailed, "new recording must replay exactly"
doAssert check.tickCount == sim.tickCount
echo "Recorded and verified ",sim.tickCount," ticks, 9 gnomes, 6 conversations, 2 bedtime interviews per gnome: ",output


let timeline = parseConnections(data.conversationLogText())
doAssert timeline.bondsAt(0).strength(0,1) == 0.5
doAssert timeline.bondsAt(4320).strength(0,1) == 1.0
doAssert timeline.bondsAt(4560).strength(0,1) == 1.0
doAssert timeline.bondsAt(9120).strength(0,1) == 1.0
var interviews, updates, emojis: int
for event in timeline.events:
  case event.kind
  of "connection-interview":
    doAssert event.interview.valid
    inc interviews
  of "connection-update": inc updates
  of "connection-emoji": inc emojis
  else: discard
doAssert interviews == 18 and updates == 2 and emojis >= 8
echo "Verified 18 bedtime interviews, 2 atomic updates, ",emojis," intentional reactions."

let director = initSimServer(Seed,DayTicks)
director.attachConversationTimeline(data,output)
var show = initReplayPlayer(data)
show.buildReplayKeyframes(Seed,DayTicks)
show.looping = false
director.buildConversationQueue(show.replayMaxTick())
doAssert director.convQueue.len == 6
var frames, held: int
var previous: tuple[tick:int, bedtime:float]
while show.playing and frames < 100000:
  director.advanceReplayPresentation(show)
  # Bedtime intentionally holds the world while its reading clock advances.
  let progress = (director.tickCount,
    if director.replayNightActive: director.replayNightTime else: -1.0)
  if progress == previous: inc held
  else: held = 0
  doAssert held < 300, "director and bedtime presentation must not stall"
  previous = progress
  inc frames
  doAssert not show.hashValidationFailed
doAssert director.tickCount == 9120
echo "Full two-day director playback: ",frames," frames, matching hashes, no stalls."
