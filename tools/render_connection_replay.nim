## Render portable review frames from a real connection replay.
## Usage: nim r tools/render_connection_replay.nim INPUT.replay OUTPUT_DIR
import std/[importutils, os], heartleaf, replays
import viewer_review_render

privateAccess(SimServer)
privateAccess(PlayerViewerState)

let
  path = paramStr(1)
  output = paramStr(2)
  data = loadReplay(path)
  cfg = data.replaySimConfig()
  sim = initSimServer(cfg.seed, cfg.dayTicks)
createDir(output)
sim.attachConversationTimeline(data, path)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed, cfg.dayTicks)
replay.looping = false
sim.buildConversationQueue(replay.replayMaxTick())
var state = newReplayViewerState()
state.setViewerSize(1440, 900)

proc seek(tick: int) =
  replay.applyReplaySeek(sim, tick)
  discard sim.replayViewerFrame(replay, state, true)
  doAssert not replay.hashValidationFailed

proc capture(name: string, debug = false, selected = 0) =
  state.setViewerSize(1440, 900)
  state.connectionDebugOpen = debug
  state.connectionSelection = selected
  # The offline compositor needs a complete packet while the persistent
  # viewer state retains the camera and inspector state derived after seek.
  state.initialized = false
  state.spriteCache.setLen(0)
  var next: PlayerViewerState
  render(sim.buildGlobalPacket(
    state, next, replayControls = true, replayPlaying = replay.playing,
    replayTick = sim.tickCount, replayMaxTick = replay.replayMaxTick()
  ), 1440, 900, output / name)
  state = next

if sim.convQueue.len > 0:
  replay.applyReplayConversation(sim, 0)
  replay.applyReplayCommand(sim, 'p')
  for _ in 0 ..< 220:
    discard sim.replayViewerFrame(replay, state, true)
  doAssert not replay.hashValidationFailed
  capture("02-conversation.png")

seek(min(8880, replay.replayMaxTick()))
capture("05-final-world.png")
capture("03-debug-graph.png", debug = true, selected = 1)

seek(10)
capture("01-overview.png")

echo "Saved real replay review frames to ", output
