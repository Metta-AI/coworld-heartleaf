## A reproducible local viewer exercise, with authored decisions and dialogue.
## Uses the normal movement executor and simulation; no teleports, edited
## hashes, model calls or borrowed recording. This is a scripted test game,
## not a claim about autonomous model behavior.
## nim r tools/record_viewer_scenario.nim OUTPUT.replay
import std/[json, os], heartleaf, replays
import heartleaf/[common, decisions, executor, protocol, souls, villager]
import bitworld/spriteprotocol

let output = if paramCount()>0: paramStr(1) else: "out/viewer-scenario.replay"
const Seed = 7301
const DayTicks = 4320
let sim = initSimServer(Seed, DayTicks)
let nav = sim.navigationFor()
let layout = sim.worldLayoutFor()
var brains: seq[Villager]
var writer = openReplayWriter(output, $(%*{"seed":Seed,"daySeconds":DayTicks div 24,
  "scenario":"scripted viewer review: three conversations and two dinner rooms"}))
writer.lastMasks.setLen(9)
for seat in 0..<9:
  let name = seat.playerNameForHouse()
  discard sim.addPlayer(name,seat)
  writer.writeJoin(0,seat,name,seat,"")
  brains.add(newVillager(seat,Soul(),layout.gardens.len))

proc decide(seat:int, action:Action, house = -1, target="") =
  brains[seat].applyDecision(sim.observe(seat),layout,
    Decision(valid:true,action:action,houseIndex:house,targetName:target),false)
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
for tick in 0..<4500:
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
      recordEvent(seat,"convo-enter","enter id=" & $(pair+1) & " members=" &
        seat.playerNameForHouse() & "," & (seat+1).playerNameForHouse() & " turn=0")
  if tick >= 820 and tick < 1108 and (tick-820) mod 48 == 0:
    let turn = (tick-820) div 48
    for pair in 0..<3:
      let seat = pair*2+turn mod 2
      say(seat,Lines[turn])
      doAssert sim.replayChatAudience(seat).len > 0, "conversation must have a real listener"
      recordEvent(seat,"convo-tick","tick id=" & $(pair+1) & " ct=" & $(turn+1) & " silent=false")
  if tick == 1200:
    for pair in 0..<3: recordEvent(pair*2,"convo-exit","exit id=" & $(pair+1))
  if tick == 1600:
    for seat in 0..<9:
      decide(seat,GoToHouse,(if seat < 2:0 elif seat < 4:2 else:seat))
  if tick in [2600,2648,2696,2744]:
    let seat = (tick-2600) div 48
    doAssert sim.playerMapIndex(seat)==(if seat<2:1 else:3), "dinner guests must arrive through the doors"
    say(seat,Lines[seat+1])
  var inputs: seq[InputState]
  for seat in 0..<9:
    let input = brains[seat].villagerTick(sim.observe(seat),nav,layout)
    writer.writeInputMaskChange(tickTime(tick),seat,input.mask)
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
echo "Recorded and verified ",sim.tickCount," ticks, 9 gnomes, 3 conversations, 2 dinner rooms: ",output

# Run the same director clock as both viewers, including concurrent rewinds.
let director = initSimServer(Seed,DayTicks)
director.attachConversationTimeline(data,output)
var show = initReplayPlayer(data)
show.buildReplayKeyframes(Seed,DayTicks)
show.looping = false
director.buildConversationQueue(show.replayMaxTick())
doAssert director.convQueue.len == 3
var frames, sameTick, lastTick:int
while show.playing and frames < 50000:
  director.advanceReplayPresentation(show)
  if director.tickCount == lastTick: inc sameTick
  else: sameTick = 0
  doAssert sameTick < 300, "director playback stalled"
  lastTick = director.tickCount
  inc frames
  doAssert not show.hashValidationFailed
doAssert director.tickCount == 4500
echo "Director playback verified: ",frames," frames, all 3 conversations, matching hashes."
