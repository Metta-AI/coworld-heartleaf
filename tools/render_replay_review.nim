## Play a saved replay through the shared native/static presentation clock,
## and capture actual protocol frames offline. Does not control a browser.
## nim r tools/render_replay_review.nim INPUT.replay OUTPUT_DIR
import std/[importutils, os, strutils], heartleaf, replays
import viewer_review_render
privateAccess(SimServer)
let path = paramStr(1)
let output = paramStr(2)
createDir(output)
createDir(output / "animation")
let data = loadReplay(path)
let cfg = data.replaySimConfig()
let sim = initSimServer(cfg.seed,cfg.dayTicks)
sim.attachConversationTimeline(data,path)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed,cfg.dayTicks)
replay.looping = false
sim.buildConversationQueue(replay.replayMaxTick())
proc capture(name:string,width=1280,height=720) =
  var state = newReplayViewerState()
  state.setViewerSize(width,height)
  var next:PlayerViewerState
  render(sim.buildGlobalPacket(state,next,replayControls=true,
    replayPlaying=replay.playing,replayTick=sim.tickCount,
    replayMaxTick=replay.replayMaxTick(),replaySpeedIndex=replay.speedIndex),
    width,height,output/name)
while sim.tickCount < 800: sim.advanceReplayPresentation(replay)
capture("01-overview.png")
for frame in 1..240:
  sim.advanceReplayPresentation(replay)
  doAssert not replay.hashValidationFailed
  if frame == 16:
    replay.applyReplayCommand(sim,'P')
    capture("02-paused-mid-zoom.png")
    let camera = (sim.directorCamX,sim.directorCamY,sim.directorCamW,sim.directorCamH)
    for _ in 0..<60: sim.advanceReplayPresentation(replay)
    doAssert camera == (sim.directorCamX,sim.directorCamY,sim.directorCamW,sim.directorCamH)
    capture("03-still-paused.png")
    replay.applyReplayCommand(sim,'p')
  if frame mod 3 == 0:
    capture("animation/frame-" & align($frame,3,'0') & ".png",960,540)
  if frame == 48: capture("04-settled-zoom.png")
  if frame == 220:
    capture("05-dialogue-portrait.png")
    capture("06-dialogue-narrow.png",768,1024)
# Seek to the dinner phase, then play normally so post-seek dialogue lands.
replay.applyReplaySeek(sim,2598)
replay.applyReplayCommand(sim,'p')
var frames=0
while sim.tickCount < 2650 and frames < 2000:
  sim.advanceReplayPresentation(replay)
  inc frames
  doAssert not replay.hashValidationFailed
capture("07-dinner-room.png")
replay.applyReplaySeek(sim,4200)
sim.advanceReplayPresentation(replay)
capture("08-night-room.png")
echo "Saved replay-derived protocol frames to ",output

# Additional conversation framing at laptop size.
replay.applyReplayConversation(sim,1)
for _ in 0..<220: sim.advanceReplayPresentation(replay)
capture("09-selected-conversation.png")
capture("10-dialogue-laptop.png",1440,900)
replay.applyReplaySeek(sim,799)
for _ in 0..<60: sim.advanceReplayPresentation(replay)
capture("11-overview.png")
