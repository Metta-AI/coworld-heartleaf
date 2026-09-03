import
  std/[base64, json, strutils, tables],
  bitworld/replays as replayCodec

type
  CirclesTimeline* = seq[
    tuple[tick: int, circles: seq[tuple[x, y, radius: int]]]
  ]
    ## Conversation circles recorded inside the replay itself: the
    ## hosted 0.1.3 builds write {"tick","circles"} JSON rows on the
    ## codec's debug-sprite channel.

  VoiceClip* = object
    ## One spoken chat line, synthesized once at record time and
    ## carried inside the replay so every viewer - the replay server,
    ## the static wasm bundle - plays the same voice with no
    ## synthesizer and no API key at serve time.
    tick*: int
      ## The tick the line was spoken at; informational only, the
      ## lookup key is the seat and the text.
    seat*: int
      ## The speaker's gnome index (house seat), which picks the voice.
    text*: string
      ## The spoken line exactly as the chat feed shows it.
    codec*: string
      ## "m4a" (AAC in an MP4 container, served as audio/mp4) or
      ## "mp3" (served as audio/mpeg).
    base64*: string
      ## The clip bytes, base64 text as stored in the row. Kept
      ## encoded so the wasm viewer can hand it straight to a data:
      ## URL; the server decodes on request.

  VoiceClipTable* = Table[string, VoiceClip]
    ## Baked clips keyed by voiceClipKey(seat, text).

  ReplayKeyframe* = object
    tick*: int
    simBytes*: string
    joinIndex*: int
    leaveIndex*: int
    inputIndex*: int
    chatIndex*: int
    hashIndex*: int
    masks*: seq[uint8]
    hashValidationFailed*: bool
    hashMismatchTick*: int

  ReplayPlayer* = object
    data*: ReplayData
    joinIndex*: int
    leaveIndex*: int
    inputIndex*: int
    chatIndex*: int
    hashIndex*: int
    masks*: seq[uint8]
    playing*: bool
    looping*: bool
    speedIndex*: int
    frameAccum*: int
      ## Frames waited toward the next tick at a slow-motion speed.
    circlesTimeline*: CirclesTimeline
      ## Circle records parsed out of the replay, empty when the
      ## replay carries none.
    hashValidationFailed*: bool
    hashMismatchTick*: int
    keyframes*: seq[ReplayKeyframe]
    seekSerial*: int
      ## Bumped on every keyframed seek. The replay server watches it
      ## to release a viewer's voice hold when the line being spoken
      ## was seeked away - a queue rewind, a next/prev jump, a scrub -
      ## so the show never stalls out the hold timeout on a line that
      ## no longer exists in the feed.
    voiceClips*: VoiceClipTable
      ## The voice clips baked into the replay, empty for a replay
      ## recorded without them.

const
  VoiceRecordPrefix* = "{\"kind\":\"voice\","
    ## Every voice row starts with exactly this text, so the
    ## conversation and circle readers can skip the (large) rows with
    ## a prefix test instead of parsing them.

  ReplayFps* = 24
  PlaybackSpeedTicks* = [1, 1, 1, 2, 3, 4, 8, 16]
    ## Ticks stepped on a stepping frame at each speed.
  PlaybackSpeedFrames* = [4, 2, 1, 1, 1, 1, 1, 1]
    ## Frames per stepping frame: slow-motion speeds step one tick
    ## every few frames instead of several ticks every frame.
  DefaultSpeedIndex* = 2
    ## The 1X entry.
  ReplayKeyframeTicks* = 100
  HeartleafGameName* = "heartleaf"
  HeartleafGameVersion* = "0.1.0"
  HeartleafReplayMagic = "HEARTLEA"
  HeartleafReplayFormatVersion = 1'u16
  HeartleafReplaySpec = ReplaySpec(
    magic: HeartleafReplayMagic,
    formatVersion: HeartleafReplayFormatVersion,
    gameName: HeartleafGameName,
    gameVersion: HeartleafGameVersion,
    joinKind: rjkNameSlotToken,
    allowChat: true,
    allowCompressed: true,
    hashOrder: rhoStop
  )

export replayCodec

proc tickTime*(tick: int): uint32 =
  ## Converts a simulation tick to replay milliseconds.
  replayCodec.tickTime(tick, ReplayFps)

proc openReplayWriter*(path: string, configJson: string): ReplayWriter =
  ## Opens a replay file and writes the header.
  replayCodec.openReplayWriter(path, configJson, HeartleafReplaySpec)

proc parseReplayBytes*(bytes: string): ReplayData =
  ## Parses one replay file buffer into memory.
  replayCodec.parseReplayBytes(bytes, HeartleafReplaySpec)

proc loadReplay*(path: string): ReplayData =
  ## Loads a replay file into memory.
  replayCodec.loadReplay(path, HeartleafReplaySpec)

proc writeInputMaskChange*(
  writer: var ReplayWriter,
  time: uint32,
  playerIndex: int,
  mask: uint8
) =
  ## Writes one replay input event when a player's held mask changes.
  if playerIndex < 0 or playerIndex >= writer.lastMasks.len:
    return
  if writer.lastMasks[playerIndex] == mask:
    return
  writer.writeInput(ReplayInput(
    time: time,
    player: uint8(playerIndex),
    keys: mask
  ))
  writer.lastMasks[playerIndex] = mask

proc writeConversationRecord*(
  writer: var ReplayWriter,
  time: uint32,
  payload: string
) =
  ## Writes one conversation log line into the replay itself. The
  ## payload is the same stamped JSON row that goes to game.log; it
  ## rides the debug-sprite channel of the codec, so the format and
  ## old replays are untouched, and every viewer - native, wasm,
  ## hosted - can rebuild the conversation timeline from the one
  ## replay file.
  var bytes = newSeq[uint8](payload.len)
  for i, ch in payload:
    bytes[i] = uint8(ch)
  writer.writeDebugSprite(time, 0, bytes)

proc conversationRecordText*(record: ReplayDebugSprite): string =
  ## The JSON payload of one conversation record as text.
  result = newString(record.packet.len)
  for i, b in record.packet:
    result[i] = char(b)

proc isVoiceRecord*(record: ReplayDebugSprite): bool =
  ## Whether one debug-sprite row is a baked voice clip.
  if record.packet.len < VoiceRecordPrefix.len:
    return false
  for i, ch in VoiceRecordPrefix:
    if record.packet[i] != uint8(ch):
      return false
  true

proc voiceClipKey*(seat: int, text: string): string =
  ## The lookup key of one spoken line: the seat picks the voice and
  ## the text is what it says, so the same line by the same gnome is
  ## one clip however often it recurs or wherever it sits in the feed.
  $seat & "\n" & text

proc voiceRecordText*(
  tick, seat: int,
  text, codec, clipBytes: string
): string =
  ## The JSON row of one baked voice clip. The key order is fixed so
  ## the row starts with VoiceRecordPrefix.
  VoiceRecordPrefix &
    "\"tick\":" & $tick &
    ",\"seat\":" & $seat &
    ",\"text\":" & escapeJson(text) &
    ",\"codec\":" & escapeJson(codec) &
    ",\"bytes\":\"" & encode(clipBytes) & "\"}"

proc writeVoiceRecord*(
  writer: var ReplayWriter,
  time: uint32,
  tick, seat: int,
  text, codec, clipBytes: string
) =
  ## Writes one baked voice clip into the replay, on the same
  ## debug-sprite channel as the conversation records. Old replays
  ## without voice rows play as before: viewers that find no clip for
  ## a line fall back to whatever they did without one.
  writer.writeConversationRecord(
    time, voiceRecordText(tick, seat, text, codec, clipBytes)
  )

proc parseVoiceRecord*(text: string): VoiceClip =
  ## One voice row as a clip; raises on a malformed row.
  let node = parseJson(text)
  if node{"kind"}.getStr() != "voice":
    raise newException(ValueError, "not a voice record")
  VoiceClip(
    tick: node{"tick"}.getInt(),
    seat: node{"seat"}.getInt(),
    text: node{"text"}.getStr(),
    codec: node{"codec"}.getStr(),
    base64: node{"bytes"}.getStr()
  )

proc voiceClipBytes*(clip: VoiceClip): string =
  ## The decoded audio bytes of one clip.
  decode(clip.base64)

proc voiceContentType*(codec: string): string =
  ## The HTTP content type for one clip codec.
  if codec == "mp3": "audio/mpeg" else: "audio/mp4"

proc replayVoiceClips*(data: ReplayData): VoiceClipTable =
  ## Every baked voice clip in one replay, keyed for lookup. A later
  ## row for the same line replaces an earlier one, so re-baking a
  ## replay with a better voice needs no surgery on the old rows.
  result = initTable[string, VoiceClip]()
  for record in data.debugSprites:
    if not record.isVoiceRecord():
      continue
    try:
      let clip = parseVoiceRecord(record.conversationRecordText())
      result[voiceClipKey(clip.seat, clip.text)] = clip
    except CatchableError:
      discard

proc findVoiceClip*(
  clips: VoiceClipTable,
  seat: int,
  text: string,
  clip: var VoiceClip
): bool =
  ## Looks one spoken line up in the baked clips.
  let key = voiceClipKey(seat, text)
  if key notin clips:
    return false
  clip = clips[key]
  true

proc conversationLogText*(data: ReplayData): string =
  ## Every conversation record in this replay as game.log-shaped lines.
  ## Voice rows share the channel but are not conversation events, so
  ## they are left out (they are also large).
  var rows: seq[string]
  for record in data.debugSprites:
    if record.isVoiceRecord():
      continue
    rows.add(record.conversationRecordText())
  rows.join("\n")

proc writeReplayData*(path: string, data: ReplayData, configJson = "") =
  ## Writes one parsed replay back out as a replay file: every record
  ## of every kind, in its recorded order. Used by the tools that
  ## enrich a recording after the fact (tools/bake_voices.nim). The
  ## codec keeps each record kind on its own timeline, so the kinds
  ## are written one after another; the tick hashes go last.
  var writer = openReplayWriter(
    path, if configJson.len > 0: configJson else: data.configJson
  )
  for join in data.joins:
    writer.writeJoin(join.time, int(join.player), join.name, join.slot, join.token)
  for leave in data.leaves:
    writer.writeLeave(leave.time, int(leave.player))
  for input in data.inputs:
    writer.writeInput(input)
  for chat in data.chats:
    writer.writeChat(chat.time, int(chat.player), chat.message)
  for record in data.debugSprites:
    writer.writeDebugSprite(record.time, int(record.player), record.packet)
  for input in data.clientInputs:
    writer.writeClientInput(input.time, int(input.player), input.packet)
  for hash in data.hashes:
    writer.writeHash(hash.tick, hash.hash)
  writer.closeReplayWriter()

proc addVoiceRecord*(
  data: var ReplayData,
  tick, seat: int,
  text, codec, clipBytes: string
) =
  ## Appends one baked voice clip to parsed replay data, for
  ## writeReplayData. The row's time never runs before the channel's
  ## last row, which the codec requires.
  var time = tickTime(tick)
  if data.debugSprites.len > 0:
    time = max(time, data.debugSprites[^1].time)
  let payload = voiceRecordText(tick, seat, text, codec, clipBytes)
  var bytes = newSeq[uint8](payload.len)
  for i, ch in payload:
    bytes[i] = uint8(ch)
  data.debugSprites.add(ReplayDebugSprite(time: time, player: 0, packet: bytes))

proc replayCirclesTimeline*(data: ReplayData): CirclesTimeline =
  ## Reads the conversation circles recorded inside one replay. Rows
  ## that are not circle records (slot rows share the channel) are
  ## skipped.
  for record in data.debugSprites:
    if record.isVoiceRecord():
      continue
    var text = newString(record.packet.len)
    for i, b in record.packet:
      text[i] = char(b)
    try:
      let node = parseJson(text)
      if not node.hasKey("circles"):
        continue
      var circles: seq[tuple[x, y, radius: int]]
      for circle in node["circles"]:
        circles.add((
          circle[0].getInt(), circle[1].getInt(), circle[2].getInt()
        ))
      result.add((node{"tick"}.getInt(), circles))
    except CatchableError:
      discard

proc circlesAtTick*(
  timeline: CirclesTimeline,
  tick: int
): seq[tuple[x, y, radius: int]] =
  ## The circles in effect at one replay tick: the last change at or
  ## before it. Works under scrubbing in both directions.
  for entry in timeline:
    if entry.tick > tick:
      break
    result = entry.circles

proc initReplayPlayer*(data: ReplayData): ReplayPlayer =
  ## Builds replay playback state.
  result.data = data
  result.masks = @[]
  result.playing = true
  result.looping = true
  result.speedIndex = DefaultSpeedIndex
  result.hashMismatchTick = -1
  result.circlesTimeline = data.replayCirclesTimeline()
  result.voiceClips = data.replayVoiceClips()

proc replaySpeedIndex*(replay: ReplayPlayer): int =
  ## Returns the current index into the playback speed tables.
  clamp(replay.speedIndex, 0, PlaybackSpeedTicks.high)

proc replayTicksThisFrame*(replay: var ReplayPlayer): int =
  ## Returns how many ticks to step this frame at the current speed.
  ## Slow-motion speeds step one tick every few frames, so this is 0 on
  ## the frames in between.
  let index = replay.replaySpeedIndex()
  if PlaybackSpeedFrames[index] <= 1:
    replay.frameAccum = 0
    return PlaybackSpeedTicks[index]
  inc replay.frameAccum
  if replay.frameAccum >= PlaybackSpeedFrames[index]:
    replay.frameAccum = 0
    return 1
  0

proc replayMaxTick*(replay: ReplayPlayer): int =
  ## Returns the final tick available in the replay.
  if replay.data.hashes.len == 0:
    return 0
  int(replay.data.hashes[^1].tick)

proc resetReplay*(replay: var ReplayPlayer) =
  ## Resets replay playback cursors.
  replay.joinIndex = 0
  replay.leaveIndex = 0
  replay.inputIndex = 0
  replay.chatIndex = 0
  replay.hashIndex = 0
  replay.hashValidationFailed = false
  replay.hashMismatchTick = -1
  replay.masks = @[]

proc ensureReplayPlayer*(replay: var ReplayPlayer, player: int) =
  ## Expands replay input tables for one player.
  while replay.masks.len <= player:
    replay.masks.add(0)

proc saveReplayKeyframe*(
  replay: ReplayPlayer,
  tick: int,
  simBytes: string
): ReplayKeyframe =
  ## Builds one replay keyframe from the current playback cursors.
  ReplayKeyframe(
    tick: tick,
    simBytes: simBytes,
    joinIndex: replay.joinIndex,
    leaveIndex: replay.leaveIndex,
    inputIndex: replay.inputIndex,
    chatIndex: replay.chatIndex,
    hashIndex: replay.hashIndex,
    masks: replay.masks,
    hashValidationFailed: replay.hashValidationFailed,
    hashMismatchTick: replay.hashMismatchTick
  )

proc restoreReplayKeyframeCursors*(
  replay: var ReplayPlayer,
  keyframe: ReplayKeyframe
) =
  ## Restores playback cursors and masks from one replay keyframe.
  replay.joinIndex = keyframe.joinIndex
  replay.leaveIndex = keyframe.leaveIndex
  replay.inputIndex = keyframe.inputIndex
  replay.chatIndex = keyframe.chatIndex
  replay.hashIndex = keyframe.hashIndex
  replay.masks = keyframe.masks
  replay.hashValidationFailed = keyframe.hashValidationFailed
  replay.hashMismatchTick = keyframe.hashMismatchTick

proc replayKeyframeIndex*(replay: ReplayPlayer, tick: int): int =
  ## Returns the newest keyframe at or before one tick.
  for i, keyframe in replay.keyframes:
    if keyframe.tick > tick:
      break
    result = i
