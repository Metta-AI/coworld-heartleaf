## Exercise ordered sprite-client packets through the shared native/WASM viewer.
import std/[importutils, os]
import heartleaf, replays
import ../tools/viewer_review_render
privateAccess(SimServer)
privateAccess(PlayerViewerState)
let path = "docs/viewer-stability/local-viewer-scenario.replay"
let data = loadReplay(path)
let cfg = data.replaySimConfig()
let sim = initSimServer(cfg.seed,cfg.dayTicks)
sim.attachConversationTimeline(data,path)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed,cfg.dayTicks)
replay.looping = false
sim.buildConversationQueue(replay.replayMaxTick())
var state = newReplayViewerState()
state.setViewerSize(1440,900)
proc frame() =
  discard sim.replayViewerFrame(replay,state,true)
  doAssert not replay.hashValidationFailed
proc click(x,y:int) =
  state.handleReplayViewerPacket(char(0x82)&char(x and 255)&char(x shr 8)&
    char(y and 255)&char(y shr 8)&char(4)&
    char(0x83)&char(1)&char(1)&char(0x83)&char(1)&char(0))
proc button(index:int) = click(10+14*index+5,75)
proc speed(index:int) = click(174+17*index+5,75)
proc snapshot(name:string) =
  if paramCount() == 0: return
  createDir(paramStr(1))
  var fresh = newReplayViewerState()
  fresh.setViewerSize(1440,900)
  var next: PlayerViewerState
  render(sim.buildGlobalPacket(fresh,next,replayControls=true,
    replayPlaying=replay.playing,replayTick=sim.tickCount,
    replayMaxTick=replay.replayMaxTick(),replaySpeedIndex=replay.speedIndex),
    1440,900,paramStr(1)/name)
# Two next clicks before one frame must both arrive, even at concurrent births.
replay.applyReplaySeek(sim,0)
button(3);button(3);frame()
doAssert sim.convQueueIndex == 1 and not replay.playing
snapshot("01-double-next-paused.png")
# Previous really goes to the previous conversation, retaining paused state.
button(1);frame()
doAssert sim.convQueueIndex == 0 and not replay.playing
# Fast mixed clicks preserve next, next, speed, play, in that order.
button(3);button(3);speed(0);button(2);frame()
doAssert sim.convQueueIndex == 2 and replay.speedIndex == 0 and replay.playing
for _ in 0..<180:frame()
snapshot("02-quarter-speed.png")
button(2);frame()
let frozen = (sim.tickCount,sim.directorCamX,sim.directorCamY,sim.directorCamW,
  sim.directorCamH,sim.directorFrameBlend,sim.directorTweenLeft,sim.gameHash())
for _ in 0..<30:frame()
doAssert frozen == (sim.tickCount,sim.directorCamX,sim.directorCamY,sim.directorCamW,
  sim.directorCamH,sim.directorFrameBlend,sim.directorTweenLeft,sim.gameHash())
snapshot("03-paused.png")
# Both toggle clicks must be processed. Then a third must resume.
button(2);button(2);frame()
doAssert not replay.playing
button(2);speed(1);frame()
doAssert replay.playing and replay.speedIndex == 1
for _ in 0..<180:frame()
snapshot("04-half-speed.png")
# A play click followed by a seek finishes paused. Reverse order finishes playing.
replay.applyReplaySeek(sim,0)
button(2);click(75,92);frame()
doAssert not replay.playing
let seekTick = sim.tickCount
click(75,92);button(2);frame()
doAssert replay.playing and sim.tickCount >= seekTick
snapshot("05-seek-then-play.png")
# Rate labels are true multipliers, independent of the director's base pace.
for setting, expected in [5,10,20,40]:
  replay.applyReplaySeek(sim,850)
  sim.advanceReplayPresentation(replay)
  speed(setting);button(2);frame()
  let start = sim.tickCount
  for _ in 0..<100:sim.advanceReplayPresentation(replay)
  doAssert sim.tickCount-start == expected, $setting & ": " & $(sim.tickCount-start)
  doAssert not replay.hashValidationFailed
  echo "speed index ",setting,": ",expected," ticks / 100 settled frames"
# Selected speed changes immediately while paused and never unpauses by itself.
for setting in 0..7:
  replay.applyReplayCommand(sim,'P')
  let tick = sim.tickCount
  speed(setting);frame()
  doAssert replay.speedIndex == setting and not replay.playing and sim.tickCount == tick
# End -> play starts again rather than appearing to ignore Play.
button(4);frame()
doAssert sim.tickCount == replay.replayMaxTick() and not replay.playing
snapshot("06-end.png")
button(2);frame()
doAssert replay.playing and sim.tickCount < replay.replayMaxTick()
# The first camera cut must hold the exact birth tick even at 16X.
replay.applyReplaySeek(sim,799)
speed(7);button(2);frame()
doAssert sim.tickCount == 800
frame()
doAssert sim.tickCount == 800, "the first camera frame cannot swallow recorded lines"
# Repeated next at the queue end is bounded, and never jumps back unexpectedly.
replay.applyReplaySeek(sim,0)
for _ in 0..<5:button(3)
frame()
doAssert sim.convQueueIndex == 2 and not replay.playing
# All pause/speed/resume combinations retain speed and hash integrity.
for a in 0..7:
  for b in 0..7:
    replay.applyReplaySeek(sim,850)
    speed(a);button(2);speed(b);button(2);frame()
    doAssert replay.speedIndex == b and not replay.playing
    doAssert sim.tickCount == 850
# Playback through every conversation and both dinner rooms at 16X reaches the end.
replay.applyReplaySeek(sim,0)
speed(7);button(2);frame()
var frames = 0
while replay.playing and frames < 20000:
  sim.advanceReplayPresentation(replay)
  inc frames
  doAssert not replay.hashValidationFailed
  if sim.tickCount >= 2620 and sim.tickCount < 2660:snapshot("07-dinner.png")
doAssert sim.tickCount == replay.replayMaxTick() and not replay.playing
snapshot("08-finished.png")
echo "Ordered clicks, pause, seek/play order, eight speeds, 64 combinations and full replay passed (",frames," frames)"
