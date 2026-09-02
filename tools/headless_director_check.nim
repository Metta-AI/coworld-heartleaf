## Headless director-cut soak test for the wasm32 build: loads one
## replay, switches a director-mode viewer to the requested speed, and
## pumps the full viewer frame loop (queue stepping, camera, packet
## build) to the end of the recording with no window and no GL.
## Compiled to wasm32 and run under node, it catches 32-bit arithmetic
## defects that the 64-bit native build can never hit.
##
##   nim c -d:emscripten ... tools/headless_director_check.nim
##   node out/headless_director_check.js <replay> [speedCommand]

import
  std/os,
  heartleaf, replays

proc main() =
  let path =
    if paramCount() >= 1:
      paramStr(1)
    else:
      "out/test.bitreplay"
  let speedCommand =
    if paramCount() >= 2 and paramStr(2).len == 1:
      paramStr(2)[0]
    else:
      '6'
  let bytes = readFile(path)
  let
    data = parseReplayBytes(bytes)
    config = data.replaySimConfig()
  var sim = initSimServer(config.seed, config.dayTicks)
  sim.attachConversationTimeline(data, path)
  var replay = initReplayPlayer(data)
  replay.buildReplayKeyframes(config.seed, config.dayTicks)
  sim.buildConversationQueue(replay.replayMaxTick())
  var state = newReplayViewerState()
  state.directorMode = true
  replay.applyReplayCommand(sim, speedCommand)
  replay.looping = false
  replay.playing = true
  let maxTick = replay.replayMaxTick()
  echo "Headless director run: ", maxTick, " ticks at command '",
    speedCommand, "'"
  var
    frames = 0
    lastReport = 0
  while frames < 500_000:
    inc frames
    let packet = replayViewerFrame(sim, replay, state, true)
    doAssert packet.len > 0
    if sim.tickCount >= lastReport + 250:
      lastReport = sim.tickCount
      echo "frame ", frames, " tick ", sim.tickCount
    if not replay.playing and sim.tickCount >= maxTick:
      break
  echo "Completed: tick ", sim.tickCount, "/", maxTick,
    " in ", frames, " frames"

main()
