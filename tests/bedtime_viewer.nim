## Real recorded bedtime rankings, atomic before/after display, and transport.
import std/[importutils, math, os]
import heartleaf, replays, heartleaf/connections
import ../tools/viewer_review_render
privateAccess(SimServer)
privateAccess(PlayerViewerState)
let path="docs/connections/claude/two-day.bitreplay"
let data=loadReplay(path)
let cfg=data.replaySimConfig()
let sim=initSimServer(cfg.seed,cfg.dayTicks)
sim.attachConversationTimeline(data,path)
var replay=initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed,cfg.dayTicks)
replay.looping=false
sim.buildConversationQueue(replay.replayMaxTick())
var state=newReplayViewerState()
state.setViewerSize(1440,900)
proc frame() = discard sim.replayViewerFrame(replay,state,true)
proc click(x,y:int) =
  state.handleReplayViewerPacket(char(0x82)&char(x and 255)&char(x shr 8)&
    char(y and 255)&char(y shr 8)&char(7)&char(0x83)&char(1)&char(1)&char(0x83)&char(1)&char(0))
  frame()
proc stage(index:int) =
  let button=state.nightStageButtons[index].rect
  click(button.x+2,button.y+2)
proc capture(name:string,w=1440,h=900) =
  state.setViewerSize(w,h)
  if paramCount()==0:
    frame()
    return
  createDir(paramStr(1))
  state.initialized=false
  state.spriteCache.setLen(0)
  var next:PlayerViewerState
  render(sim.buildGlobalPacket(state,next,replayControls=true,replayPlaying=replay.playing,
    replayTick=sim.tickCount,replayMaxTick=replay.replayMaxTick()),w,h,paramStr(1)/name)
  state=next

doAssert sim.replayNights.len==2
let first=sim.replayNights[0]
doAssert first.tick==4320 and first.day==1 and first.interviews.len==9
for interview in first.interviews: doAssert interview.valid and interview.ranking.len==8
doAssert first.before.strength(2,3)==0.5 and first.after.strength(2,3)==1
let second=sim.replayNights[1]
for i in [2,5,6]: doAssert not second.interviews[i].valid
replay.applyReplaySeek(sim,4319)
frame()
doAssert not sim.replayNightActive
let jump=state.nightJumpButtons[0].rect
click(jump.x+2,jump.y+2)
doAssert sim.tickCount==4320 and sim.replayNightActive and not replay.playing
capture("01-night-one-ranking.png")

let rank=state.nightRankButtons[3].rect
click(rank.x+2,rank.y+2)
doAssert state.nightRankSelection==3
stage(7)
doAssert int(sim.replayNightTime/8)==7 and not replay.playing
capture("02-dima-ranking.png")
stage(9)
doAssert sim.replayNightTime==72
capture("03-connection-update.png")
let frozen=(sim.tickCount,sim.replayNightTime,sim.directorCamX,sim.directorCamY)
for _ in 0..<30:frame()
doAssert frozen==(sim.tickCount,sim.replayNightTime,sim.directorCamX,sim.directorCamY)
replay.applyReplayCommand(sim,'p')
for _ in 0..<300:frame()
doAssert not sim.replayNightActive and sim.tickCount>4320
replay.applyReplaySeek(sim,8880)
frame()
stage(2)
capture("04-missing-interview.png")
doAssert sim.replayNightActive and not replay.playing
capture("05-bedtime-laptop.png",1280,720)
capture("06-bedtime-short.png",1280,480)
stage(0)
capture("07-ranking-short.png",1280,480)
doAssert state.nightRankButtons.len==8
for button in state.nightRankButtons:doAssert button.rect.y+button.rect.height<190
stage(9)
capture("08-update-short.png",1280,480)
state.setViewerSize(1440,900)
replay.applyReplaySeek(sim,4320)
frame()
doAssert sim.replayNightIndex==0 and sim.replayNightTime==0
replay.applyReplayCommand(sim,'n')
frame()
doAssert not sim.replayNightActive
replay.applyReplayCommand(sim,'e')
frame()
doAssert not sim.replayNightActive
replay.applyReplayCommand(sim,'p')
frame()
doAssert sim.tickCount<100 and sim.replayNightIndex==0
replay.applyReplaySeek(sim,100)
frame()
doAssert not sim.replayNightActive and sim.connectionTimeline.bondsAt(sim.tickCount).strength(2,3)==0.5
for setting in 0..7:
  replay.applyReplaySeek(sim,4320)
  replay.speedIndex=setting
  replay.playing=true
  var count=0
  while sim.replayNightActive and count<10000:
    frame();inc count
  let expected=int(ceil(80.0*24*PlaybackSpeedFrames[setting].float/PlaybackSpeedTicks[setting].float))
  doAssert abs(count-expected)<=1
  doAssert not replay.hashValidationFailed
echo "Bedtime: both recorded nights, rankings, reasons, before/after, timeouts, pause, seek, navigation and eight speeds passed"
