import
  bitworld/replays as replayCodec

type
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
    hashValidationFailed*: bool
    hashMismatchTick*: int
    keyframes*: seq[ReplayKeyframe]

const
  ReplayFps* = 24
  PlaybackSpeeds* = [1, 2, 3, 4, 8, 16]
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

proc initReplayPlayer*(data: ReplayData): ReplayPlayer =
  ## Builds replay playback state.
  result.data = data
  result.masks = @[]
  result.playing = true
  result.looping = true
  result.hashMismatchTick = -1

proc replaySpeed*(replay: ReplayPlayer): int =
  ## Returns the current integer replay speed.
  PlaybackSpeeds[clamp(replay.speedIndex, 0, PlaybackSpeeds.high)]

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
