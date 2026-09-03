## Bake voice clips into an existing Heartleaf replay.
##
## A game recorded by a server with a synthesizer already carries its
## voices (src/heartleaf/voices.nim bakes them at record time). This tool
## is for every other recording: it plays the replay through the real
## simulation to find the lines the delay-chat feed will show, speaks each
## one with the machine's synthesizer, and writes a new replay with one
## voice row per line (VoiceClip in src/replays.nim). Old rows, hashes and
## inputs are copied unchanged, so the result plays exactly as before with
## voices on top - in the replay server and in the static wasm bundle.
##
## Synthesizers, in order of preference: ElevenLabs (ELEVENLABS_API_KEY or
## ~/.elevenlabs_key), macOS `say`, `espeak-ng` + `ffmpeg`. Force one with
## --synth or HEARTLEAF_VOICE_SYNTH.
##
## Usage:
##   bake_voices [--synth:auto|eleven|say|espeak] [--game-log:<path>]
##               [--out:<path>] [--force] <replay.bitreplay>
##
## The output defaults to <replay>-voiced.bitreplay. Lines that already
## have a clip are kept unless --force re-speaks them.

import
  std/[os, strutils, tables],
  ../src/heartleaf,
  ../src/heartleaf/voices,
  ../src/replays

const UsageText =
  "Usage: bake_voices [--synth:auto|eleven|say|espeak] " &
  "[--game-log:<path>] [--out:<path>] [--force] <replay.bitreplay>"

proc fail(message: string) =
  stderr.writeLine(message)
  quit(1)

proc main() =
  var
    replayPath = ""
    outPath = ""
    gameLogPath = ""
    synthName = ""
    force = false
  for arg in commandLineParams():
    if arg == "--help" or arg == "-h":
      echo UsageText
      quit(0)
    elif arg == "--force":
      force = true
    elif arg.startsWith("--synth:"):
      synthName = arg["--synth:".len .. ^1]
    elif arg.startsWith("--out:"):
      outPath = arg["--out:".len .. ^1]
    elif arg.startsWith("--game-log:"):
      gameLogPath = arg["--game-log:".len .. ^1]
    elif arg.startsWith("--"):
      fail("unknown option: " & arg & "\n" & UsageText)
    else:
      replayPath = arg
  if replayPath.len == 0:
    fail(UsageText)
  if not fileExists(replayPath):
    fail("replay not found: " & replayPath)
  if outPath.len == 0:
    let (dir, name, ext) = splitFile(replayPath)
    outPath = dir / (name & "-voiced" & ext)

  let synth = detectVoiceSynth(synthName)
  if synth == vsNone:
    fail("no voice synthesizer available (" &
      (if synthName.len > 0: synthName else: "auto") &
      "): need an ElevenLabs key, macOS say, or espeak-ng + ffmpeg")
  echo "Synthesizer: ", $synth

  var data = loadReplay(replayPath)
  let inputSize = getFileSize(replayPath)
  var clips = data.replayVoiceClips()
  echo "Replay: ", replayPath, " (", inputSize, " bytes, ",
    data.chats.len, " chat records, ", clips.len, " voice clips already)"

  let lines = data.replaySpokenLines(replayPath, gameLogPath)
  echo "Spoken lines on playback: ", lines.len

  var
    baked = 0
    kept = 0
    failed = 0
    bakedBytes = 0
    rowBytes = 0
    seen = initTable[string, bool]()
  for line in lines:
    let key = voiceClipKey(line.seat, line.text)
    if key in seen:
      continue
    seen[key] = true
    if not force and key in clips:
      inc kept
      continue
    let clip = synthesizeVoice(synth, line.seat, line.text)
    if clip.bytes.len == 0:
      inc failed
      echo "  failed: seat ", line.seat, " tick ", line.tick, ": ", line.text
      continue
    data.addVoiceRecord(line.tick, line.seat, line.text, clip.codec, clip.bytes)
    rowBytes += data.debugSprites[^1].packet.len
    clips[key] = VoiceClip(seat: line.seat, text: line.text, codec: clip.codec)
    inc baked
    bakedBytes += clip.bytes.len
    echo "  ", clip.bytes.len, " bytes  seat ", line.seat, " tick ",
      line.tick, ": ", line.text

  writeReplayData(outPath, data)
  let outputSize = getFileSize(outPath)
  echo "Baked ", baked, " clips (", kept, " kept, ", failed, " failed) into ",
    outPath
  if baked > 0:
    echo "Clip bytes: ", bakedBytes, " total, ", bakedBytes div baked,
      " per line; ", rowBytes, " bytes of rows with base64"
  echo "Replay size: ", inputSize, " -> ", outputSize, " bytes"
  if failed > 0:
    quit(2)

when isMainModule:
  main()
