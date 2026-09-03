## Gnome voices: one synthesizer per machine, one voice per seat.
##
## Three synthesizers are known. ElevenLabs when a key is present
## (ELEVENLABS_API_KEY or ~/.elevenlabs_key), macOS `say` + `afconvert`
## on Darwin, and `espeak-ng` + `ffmpeg` anywhere else. HEARTLEAF_VOICE_SYNTH
## forces one of `auto`, `none`, `eleven`, `say`, `espeak`.
##
## Voices are made once, at record time, and baked into the replay (see
## VoiceClip in src/replays.nim): hosted replays are static bundles with no
## server and no key, so nothing may be synthesized at serve time. The
## VoiceBaker here runs the synthesizer on its own thread so the live game
## loop never waits on it; the replay server and the wasm viewer only read
## the baked rows back.

import
  std/[hashes, json, os, osproc, sets, strutils, times],
  replays

type
  VoiceSynth* = enum
    vsNone = "none"
    vsEleven = "eleven"
    vsSay = "say"
    vsEspeak = "espeak"

  VoiceClipBytes* = tuple[codec, bytes: string]
    ## One synthesized line: the container ("m4a" or "mp3") and the
    ## bytes. Empty bytes mean the synthesizer failed.

  VoiceBakeRequest = object
    stop: bool
    seat: int
    text: string

  VoiceBakeResult* = object
    seat*: int
    text*: string
    codec*: string
    bytes*: string

  VoiceBaker* = object
    ## Bookkeeping for the one background synthesizer thread: what was
    ## asked for (so a repeated line is made once) and how many
    ## answers are still to come.
    synth*: VoiceSynth
    running*: bool
    pending*: int
    seen: HashSet[string]

const
  ElevenDefaultFormat = "mp3_22050_32"
    ## 32 kbit/s mono at 22 kHz: about 4 KB per second of speech,
    ## plenty for a gnome. HEARTLEAF_ELEVEN_FORMAT overrides.
  ElevenCast = [
    "nzeAacJi50IvxcyDnMXa",  # Ivan (chatty)    - Marshal, exuberant professor
    "ouL9IsyrSnUkCmfnD02u",  # Anton (curious)  - Grimblewood, snarky gnome
    "M4zkunnpRihDKTNF0D7f",  # Yura (fatherly)  - Klaus Santa, warm and jolly
    "ZUz67EWNNT6d1i38Xmcm",  # Sasha (friendly) - Robert, warm baritone
    "LRpNiUBlcqgIsKUzcrlN",  # Maxim (funny)    - Georg, funny and emotional
    "0pkdtmrxitYBWv6q9NJO",  # Nikita (grumpy)  - Potato, deep wooden stoic
    "B52raBK48m23qWYbwchQ",  # Vova (jolly)     - Matthew Schmitz, warm teller
    "gSYqSbtMajxq5LUT0bNl",  # Dima (poet)      - Elder, epic storyteller
    "LxiqOV1uxBCgYTeitAHf"   # Egor (shy)       - Bowo, hoarse and quiet
  ]
    ## The ElevenLabs cast, seat by seat, matched to the persona souls.
    ## Override with HEARTLEAF_ELEVEN_VOICES, a comma list of voice ids.
  SayCast = [
    ("Grandpa (English (US))", 185),
    ("Junior", 200),
    ("Jester", 205),
    ("Eddy (English (US))", 200),
    ("Ralph", 190),
    ("Reed (English (US))", 190),
    ("Daniel", 195),
    ("Fred", 185),
    ("Rishi", 200)
  ]
    ## macOS voices and words per minute, seat by seat.
  EspeakCast = [
    ("en+m1", 55, 175),  # Ivan (chatty)
    ("en+m2", 65, 170),  # Anton (curious)
    ("en+m3", 40, 150),  # Yura (fatherly)
    ("en+m4", 50, 160),  # Sasha (friendly)
    ("en+m5", 70, 180),  # Maxim (funny)
    ("en+m6", 30, 145),  # Nikita (grumpy)
    ("en+m7", 60, 165),  # Vova (jolly)
    ("en+m3", 45, 140),  # Dima (poet)
    ("en+m2", 50, 150)   # Egor (shy)
  ]
    ## espeak-ng voice variant, pitch (0-99) and words per minute.
  VoiceBitrate = "32k"
    ## AAC bitrate for the local synthesizers, mono 22 kHz.

proc elevenKey*(): string =
  ## The ElevenLabs API key: the environment first, then the key
  ## file, so the key never has to travel through a chat or a repo.
  result = getEnv("ELEVENLABS_API_KEY").strip()
  if result.len == 0:
    let keyFile = getHomeDir() / ".elevenlabs_key"
    if fileExists(keyFile):
      result = readFile(keyFile).strip()

proc elevenVoiceFor(seat: int): string =
  ## The ElevenLabs voice id for one seat, or empty for the fallback.
  let listed = getEnv("HEARTLEAF_ELEVEN_VOICES").strip()
  if listed.len > 0:
    let ids = listed.split(',')
    if seat >= 0 and seat < ids.len:
      return ids[seat].strip()
    return ""
  if seat >= 0 and seat < ElevenCast.len:
    return ElevenCast[seat]
  ""

proc elevenClip(seat: int, text: string): string =
  ## One spoken line from ElevenLabs as mp3 bytes, cached on disk by
  ## voice, format and text so a line costs credits once. Empty on any
  ## failure.
  let key = elevenKey()
  if key.len == 0:
    return ""
  let voiceId = elevenVoiceFor(seat)
  if voiceId.len == 0:
    return ""
  let format = getEnv("HEARTLEAF_ELEVEN_FORMAT", ElevenDefaultFormat)
  let cacheDir = getTempDir() / "heartleaf-eleven"
  createDir(cacheDir)
  let clipPath =
    cacheDir / voiceId & "-" & format & "-" & $abs(hash(text)) & ".mp3"
  if fileExists(clipPath):
    return readFile(clipPath)
  let bodyPath = clipPath & ".request.json"
  writeFile(bodyPath, $(%*{
    "text": text,
    "model_id": "eleven_flash_v2_5"
  }))
  discard execProcess("curl", args = [
    "-s", "-f", "--max-time", "20",
    "-X", "POST",
    "https://api.elevenlabs.io/v1/text-to-speech/" & voiceId &
      "?output_format=" & format,
    "-H", "xi-api-key: " & key,
    "-H", "Content-Type: application/json",
    "--data-binary", "@" & bodyPath,
    "-o", clipPath
  ], options = {poUsePath})
  removeFile(bodyPath)
  if fileExists(clipPath) and getFileSize(clipPath) > 500:
    return readFile(clipPath)
  if fileExists(clipPath):
    removeFile(clipPath)
  ""

proc scratchBase(seat: int, text: string): string =
  ## A private scratch path for one synthesis; the HTTP worker threads
  ## and the baker thread may synthesize at the same time.
  getTempDir() / "heartleaf-voice-" & $getCurrentProcessId() & "-" &
    $getThreadId() & "-" & $seat & "-" & $abs(hash(text))

proc sayClip(seat: int, text: string): string =
  ## One spoken line from macOS `say`, as AAC in an m4a container.
  let
    voice = SayCast[seat mod SayCast.len]
    base = scratchBase(seat, text)
  defer:
    removeFile(base & ".aiff")
    removeFile(base & ".m4a")
  discard execProcess("/usr/bin/say", args = [
    "-v", voice[0], "-r", $voice[1], "-o", base & ".aiff", text
  ], options = {poUsePath})
  if not fileExists(base & ".aiff"):
    return ""
  discard execProcess("/usr/bin/afconvert", args = [
    "-f", "m4af", "-d", "aac", "-b", "32000", base & ".aiff", base & ".m4a"
  ], options = {poUsePath})
  if fileExists(base & ".m4a"):
    result = readFile(base & ".m4a")

proc espeakClip(seat: int, text: string): string =
  ## One spoken line from espeak-ng, transcoded by ffmpeg to AAC in
  ## an m4a container (ffmpeg's built-in encoder; no extra codec).
  let
    voice = EspeakCast[seat mod EspeakCast.len]
    base = scratchBase(seat, text)
  defer:
    removeFile(base & ".wav")
    removeFile(base & ".m4a")
  discard execProcess("espeak-ng", args = [
    "-v", voice[0], "-p", $voice[1], "-s", $voice[2],
    "-w", base & ".wav", text
  ], options = {poUsePath})
  if not fileExists(base & ".wav"):
    return ""
  discard execProcess("ffmpeg", args = [
    "-y", "-loglevel", "error", "-i", base & ".wav",
    "-c:a", "aac", "-b:a", VoiceBitrate, "-ar", "22050", "-ac", "1",
    base & ".m4a"
  ], options = {poUsePath})
  if fileExists(base & ".m4a"):
    result = readFile(base & ".m4a")

proc synthAvailable*(synth: VoiceSynth): bool =
  ## Whether one synthesizer can run on this machine.
  case synth
  of vsNone:
    true
  of vsEleven:
    elevenKey().len > 0 and findExe("curl").len > 0
  of vsSay:
    defined(macosx) and fileExists("/usr/bin/say") and
      fileExists("/usr/bin/afconvert")
  of vsEspeak:
    findExe("espeak-ng").len > 0 and findExe("ffmpeg").len > 0

proc detectVoiceSynth*(requested = ""): VoiceSynth =
  ## Picks the synthesizer: `requested`, else HEARTLEAF_VOICE_SYNTH,
  ## else the first available of ElevenLabs, say, espeak-ng. An
  ## unknown name or an unavailable named synthesizer means none.
  var name = requested.strip().toLowerAscii()
  if name.len == 0:
    name = getEnv("HEARTLEAF_VOICE_SYNTH", "auto").strip().toLowerAscii()
  if name.len == 0 or name == "auto":
    for synth in [vsEleven, vsSay, vsEspeak]:
      if synth.synthAvailable():
        return synth
    return vsNone
  for synth in VoiceSynth:
    if $synth == name:
      return if synth.synthAvailable(): synth else: vsNone
  vsNone

proc synthesizeVoice*(
  synth: VoiceSynth,
  seat: int,
  text: string
): VoiceClipBytes =
  ## One spoken line from the given synthesizer; empty bytes on
  ## failure or with no synthesizer.
  if text.len == 0:
    return ("", "")
  case synth
  of vsNone:
    ("", "")
  of vsEleven:
    ("mp3", elevenClip(seat, text))
  of vsSay:
    ("m4a", sayClip(seat, text))
  of vsEspeak:
    ("m4a", espeakClip(seat, text))

# --- The record-time baker --------------------------------------------

var
  voiceRequests: Channel[VoiceBakeRequest]
  voiceResults: Channel[VoiceBakeResult]
  voiceThread: Thread[VoiceSynth]

proc voiceBakerThread(synth: VoiceSynth) {.thread.} =
  ## Synthesizes requests one at a time until told to stop.
  while true:
    let request = voiceRequests.recv()
    if request.stop:
      break
    let clip = synthesizeVoice(synth, request.seat, request.text)
    voiceResults.send(VoiceBakeResult(
      seat: request.seat,
      text: request.text,
      codec: clip.codec,
      bytes: clip.bytes
    ))

proc startVoiceBaker*(synth: VoiceSynth): VoiceBaker =
  ## Starts the background synthesizer. With no synthesizer the baker
  ## is inert: requests are dropped and nothing ever comes back.
  result.synth = synth
  result.seen = initHashSet[string]()
  if synth == vsNone:
    return
  voiceRequests.open()
  voiceResults.open()
  createThread(voiceThread, voiceBakerThread, synth)
  result.running = true

proc request*(baker: var VoiceBaker, seat: int, text: string) =
  ## Asks for one line's clip, once per distinct (seat, text).
  if not baker.running or text.len == 0:
    return
  let key = voiceClipKey(seat, text)
  if key in baker.seen:
    return
  baker.seen.incl(key)
  inc baker.pending
  voiceRequests.send(VoiceBakeRequest(seat: seat, text: text))

proc drain*(baker: var VoiceBaker): seq[VoiceBakeResult] =
  ## The clips finished since the last drain; failed lines are
  ## dropped silently (the viewer falls back for those).
  if not baker.running:
    return
  while true:
    let (ready, item) = voiceResults.tryRecv()
    if not ready:
      break
    dec baker.pending
    if item.bytes.len > 0:
      result.add(item)

proc finish*(baker: var VoiceBaker, timeoutSeconds: float): seq[VoiceBakeResult] =
  ## Waits for the outstanding clips, up to the timeout, and returns
  ## everything that finished. The thread stays up for the next game.
  if not baker.running:
    return
  let deadline = epochTime() + timeoutSeconds
  while baker.pending > 0 and epochTime() < deadline:
    result.add(baker.drain())
    if baker.pending > 0:
      sleep(25)
  result.add(baker.drain())

proc stop*(baker: var VoiceBaker) =
  ## Stops the background thread; outstanding requests are abandoned.
  if not baker.running:
    return
  voiceRequests.send(VoiceBakeRequest(stop: true))
  joinThread(voiceThread)
  voiceRequests.close()
  voiceResults.close()
  baker.running = false
