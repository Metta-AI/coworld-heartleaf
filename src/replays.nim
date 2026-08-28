import
  std/[json, strutils],
  bitworld/replays as replayCodec

type
  CirclesTimeline* = seq[
    tuple[tick: int, circles: seq[tuple[x, y, radius: int]]]
  ]
    ## Conversation circles recorded inside the replay itself: the
    ## hosted 0.1.3 builds write {"tick","circles"} JSON rows on the
    ## codec's debug-sprite channel.

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

const
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

proc conversationLogText*(data: ReplayData): string =
  ## Every conversation record in this replay as game.log-shaped lines.
  var rows: seq[string]
  for record in data.debugSprites:
    rows.add(record.conversationRecordText())
  rows.join("\n")

proc replayCirclesTimeline*(data: ReplayData): CirclesTimeline =
  ## Reads the conversation circles recorded inside one replay. Rows
  ## that are not circle records (slot rows share the channel) are
  ## skipped.
  for record in data.debugSprites:
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
