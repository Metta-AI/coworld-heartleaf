## A small recorded village whose spoken lines carry baked voice rows,
## shared by the unit tests and the server integration test. The clips
## are fake bytes derived from the line's key, so a test can tell which
## clip came back without any synthesizer on the machine.

import
  std/[json, os, tables],
  bitworld/spriteprotocol,
  heartleaf,
  heartleaf/[observation, souls, bedrock_client, brains],
  replays

const VoicedSeats = 9

proc fakeVoiceBytes*(seat: int, text: string): string =
  ## The stand-in clip bytes for one line.
  "clip:" & voiceClipKey(seat, text)

proc writeVoicedTestReplay*(
  path: string,
  seed = 909,
  ticks = 480
): seq[SpokenLine] =
  ## Records nine mock-driven gnomes who leave their houses to gather,
  ## with a scripted chat line every second from a rotating seat, then
  ## bakes a fake clip for every line the delay-chat feed keeps (the
  ## heard ones) and writes the replay to `path`. Returns those lines.
  putEnv(MockReplyEnv, """{"action": "keep_gathering_plants"}""")
  defer: delEnv(MockReplyEnv)
  var
    recSim = initSimServer(seed)
    writer = openReplayWriter(path, $(%*{"seed": seed}))
  let soul = parseSoul("#!test-model\nYour name is {name}.\n")
  let brains = newBrains(
    recSim.navigationFor(), recSim.worldLayoutFor(),
    newBedrockClient(VoicedSeats), 3
  )
  for seat in 0 ..< VoicedSeats:
    doAssert recSim.addPlayer("gnome" & $seat, seat) == seat
    writer.writeJoin(tickTime(0), seat, "gnome" & $seat, seat, soul.modelId)
    writer.lastMasks.add(0)
    brains.attachSoul(seat, soul)
  var
    now = 3000.0
    stepped = 0
  while stepped < ticks:
    now += 0.05
    var observations = initTable[int, Observation]()
    for seat in 0 ..< VoicedSeats:
      observations[seat] = recSim.observe(seat)
    let frame = brains.advance(observations, now)
    doAssert not frame.paused, "a mock reply never pauses the village"
    var inputs = newSeq[InputState](VoicedSeats)
    for item in frame.outputs:
      inputs[item.houseIndex] = decodeInputMask(item.output.mask)
      writer.writeInputMaskChange(
        tickTime(recSim.tickCount), item.houseIndex, item.output.mask
      )
    if stepped mod 24 == 12:
      let
        seat = (stepped div 24) mod VoicedSeats
        text = "line " & $stepped & " from seat " & $seat
      recSim.applyPlayerChat(seat, text)
      writer.writeChat(tickTime(recSim.tickCount), seat, text)
    recSim.step(inputs)
    writer.writeHash(uint32(recSim.tickCount), recSim.gameHash())
    inc stepped
  writer.closeReplayWriter()

  var data = loadReplay(path)
  result = data.replaySpokenLines()
  for line in result:
    data.addVoiceRecord(
      line.tick, line.seat, line.text, "m4a",
      fakeVoiceBytes(line.seat, line.text)
    )
  writeReplayData(path, data)
