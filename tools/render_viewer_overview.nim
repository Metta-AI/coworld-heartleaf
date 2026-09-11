## Review the compact leaderboard and supplied texture in the actual replay layout.
## nim r tools/render_viewer_overview.nim OUTPUT_DIR
import std/[importutils, os], heartleaf, replays
import viewer_review_render
privateAccess(SimServer)
privateAccess(PlayerViewerState)
let path = "docs/viewer-stability/local-viewer-scenario.replay"
let output = paramStr(1)
createDir(output)
let data = loadReplay(path)
let cfg = data.replaySimConfig()
let sim = initSimServer(cfg.seed,cfg.dayTicks)
sim.attachConversationTimeline(data,path)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed,cfg.dayTicks)
replay.looping = false
sim.buildConversationQueue(replay.replayMaxTick())
proc capture(name:string,width=1280,height=720,openLeaderboard=false) =
  var state = newReplayViewerState()
  state.setViewerSize(width,height)
  if openLeaderboard: state.openPanel=1
  var next:PlayerViewerState
  render(sim.buildGlobalPacket(state,next,replayControls=true,
    replayPlaying=replay.playing,replayTick=sim.tickCount,
    replayMaxTick=replay.replayMaxTick(),replaySpeedIndex=replay.speedIndex),
    width,height,output/name)
replay.applyReplaySeek(sim,799)
sim.advanceReplayPresentation(replay)
capture("01-overview.png")
capture("02-laptop.png",1440,900)
capture("03-narrow.png",390,844,true)
capture("05-short-window.png",1280,600)
capture("06-reported-window.png",1468,798)
capture("07-cramped-window.png",1366,1024)
replay.applyReplayConversation(sim,1)
for _ in 0..<220: sim.advanceReplayPresentation(replay)
capture("04-conversation.png")
echo "Saved leaderboard and overview review frames to ",output
