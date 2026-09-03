## Headless director-cut soak check: loads one replay, switches a
## director-mode viewer to the requested speed, and pumps the full
## viewer frame loop (queue stepping, show pacing, camera, packet
## build) to the end of the recording with no window and no GL. It
## reports the largest camera move between two consecutive frames,
## as a fraction of the crop, so a cut that snaps instead of gliding
## shows up as a number instead of a feeling; --trace prints every
## frame where the crop moved by more than a tenth of itself.
##
##   nim r tools/headless_director_check.nim <replay> [speedCommand] [--trace]
##
## Compiled to wasm32 and run under node it also catches 32-bit
## arithmetic defects that the 64-bit native build can never hit.

import
  std/[os, strformat, strutils],
  heartleaf, replays

proc main() =
  var
    path = "out/test.bitreplay"
    speedCommand = '6'
    trace = false
    positional = 0
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg == "--trace":
      trace = true
    elif positional == 0:
      path = arg
      inc positional
    elif positional == 1 and arg.len == 1:
      speedCommand = arg[0]
      inc positional
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
    worstJump = 0.0
    worstFrame = 0
    worstTick = 0
    haveLast = false
    lastCrop: tuple[x, y, w, h: float]
  while frames < 500_000:
    inc frames
    let packet = replayViewerFrame(sim, replay, state, true)
    doAssert packet.len > 0
    let crop = sim.directorCrop()
    if haveLast:
      let jump = directorCropJump(lastCrop, crop)
      if jump > worstJump:
        worstJump = jump
        worstFrame = frames
        worstTick = sim.tickCount
      if trace and jump > 0.1:
        echo &"frame {frames} tick {sim.tickCount} jump {jump:.3f} " &
          &"crop {crop.x:.0f},{crop.y:.0f} {crop.w:.0f}x{crop.h:.0f}"
    lastCrop = crop
    haveLast = true
    if sim.tickCount >= lastReport + 250:
      lastReport = sim.tickCount
      echo "frame ", frames, " tick ", sim.tickCount
    if not replay.playing and sim.tickCount >= maxTick:
      break
  echo "Completed: tick ", sim.tickCount, "/", maxTick,
    " in ", frames, " frames"
  echo &"Largest camera move between frames: {worstJump:.3f} of the crop" &
    &" at frame {worstFrame} (tick {worstTick})"

main()
