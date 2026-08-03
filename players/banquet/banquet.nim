import
  std/[algorithm, options, os, parseopt, strutils],
  bitworld/[spriteprotocol, resources],
  pathy, supersnappy, whisky,
  heartleaf/[common, protocol]

const

  CollectActionRadius = InteractionRadius - 8
  PersonStandRadius = 30
  GoalArrivePixels = 2
  PathArrivePixels = 3
  PathRejoinPixels = 8

  MoveDeadZonePixels = 1
  PathDensifyPixels = 4
  SteerLookaheadPoints = 12
  UnstuckAfterTicks = 30
  UnstuckDurationTicks = 24
  RepathStuckTicks = 48
  MaxDrainMessages = 256
  DefaultName = "banquet"
  UnknownHouse = -1
  # Banquet policy schedule (minutes after midnight).
  RendezvousEndMinutes = 12 * 60
  GatherUntilMinutes = 16 * 60 + 30
  DinnerEnterMinutes = 18 * 60 + 15
  EveningGatherMinutes = 19 * 60 + 5
  SummonFromMinutes = 15 * 60
  # Measured: 96% of a day's harvest is in hand by 10am, because the
  # whole village strips all 39 gardens in the first two hours. The
  # rest of the day is worth far more spent recruiting than walking to
  # gardens that are already empty.
  TourFromMinutes = 10 * 60
  # Chat cadence in frame ticks (24 ticks per real second).
  HandshakeIntervalTicks = 48
  HandshakeConfirmSends = 6
  InviteCooldownTicks = 300
  DoorGatherSlots = 5
  DoorGatherSpacing = 18
  HouseGatherMaxRadius = 96
  MorningIdentityUntilMinutes = 9 * 60
  MorningIdentityRadius = 140
  # Sibling handshake chat token; must match the speaker's own name to
  # count, so third-party relays of the line cannot spoof a sibling.
  SiblingToken = "hl5 "
  # The village's common invitation dialect, read off public replays.
  # Listeners key on the "Party at <host>'s house" clause and act on it
  # from any speaker; every line we send names our own real house and a
  # party we actually host, so the invitation is true as well as legible.
  InviteToken = "/hl! "
  InviteHouseClause = "Party at "


  UnstuckMasks = [
    ButtonUp,
    ButtonRight,
    ButtonDown,
    ButtonLeft,
    ButtonUp or ButtonRight,
    ButtonDown or ButtonRight,
    ButtonDown or ButtonLeft,
    ButtonUp or ButtonLeft
  ]

type
  ScreenKind = enum
    UnknownScreen
    MainMap
    HomeMap
    OverlayScreen

  SpriteKind = enum
    SpriteUnknown
    SpriteMainBottom
    SpriteHomeBottom
    SpriteMainWalk
    SpriteHomeWalk
    SpriteGarden
    SpriteGnome
    SpriteName
    SpriteChat
    SpriteClock
    SpriteOverlay

  GoalKind = enum
    GoalIdle
    GoalCollect
    GoalGatherHouse
    GoalEnterHouse
    GoalExitHouse
    GoalStandPerson
    GoalMove

  Goal = object
    kind: GoalKind
    screenKind: ScreenKind
    x, y: int
    houseIndex: int
    gardenIndex: int
    targetName: string

  SpriteInfo = ref object
    defined: bool
    width, height: int
    label: string
    kind: SpriteKind
    glyph: char
    pixels: seq[uint8]

  ObjectState = object
    present: bool
    x, y, z: int
    layer: int
    spriteId: int

  Resources = ref object
    gardens: seq[Rect]
    houses: array[9, Rect]
    houseValid: array[9, bool]
    exit: Rect
    hasExit: bool

  BotRole = enum
    RoleSolo
    RoleHost
    RoleGuest

  Bot = ref object
    name: string
    playerName: string
    slot: int
    homeIndex: int
    sprites: seq[SpriteInfo]
    objects: seq[ObjectState]
    resources: Resources
    mainNav: JumpPointSpace
    homeNav: JumpPointSpace
    screenKind: ScreenKind
    previousScreenKind: ScreenKind
    currentHouse: int
    pendingHouse: int
    cameraX, cameraY: int
    localized: bool
    selfIndex: int
    selfX, selfY: int
    previousX, previousY: int
    previous2X, previous2Y: int
    velEstX, velEstY: int
    stuckTicks: int
    unstuckTicks: int
    unstuckMaskIndex: int
    minutes: int
    lastMask: uint8
    attackCooldown: int
    lastCollectTick: int
    goal: Goal
    path: seq[Point]
    gardenChecked: seq[bool]
    lastClockHour: int
    heardChats: seq[string]
    currentGarden: int
    dayIndex: int
    frameTick: int
    desiredMask: uint8
    target: Point
    hasTarget: bool
    pendingChat: string
    hasPendingChat: bool
    lastChatSentTick: int
    # Banquet twin coordination and invitations.
    siblingHouses: array[HouseCount, bool]
    invitesSent: array[HouseCount, int]
    pitchedToday: array[HouseCount, bool]
    lastInviteTick: array[HouseCount, int]
    lastTokenTick: int
    tokenSerial: int
    tokensNearSibling: int
    mainWidth: int
    mainHeight: int

proc repoDir(): string =
  ## Returns the Heartleaf repository directory.
  currentSourcePath().parentDir().parentDir().parentDir()

proc loadBotResources(): Resources =
  ## Loads house, garden, and home-exit resource rectangles.
  result = Resources()
  let root = repoDir()
  for rect in loadResourceRects(root / "data" / "map.resource"):
    let name = rect.rectName()
    if name == "garden":
      result.gardens.add(rect.toRect())
    else:
      let index = name.houseIndexFromName()
      if index >= 0:
        result.houses[index] = rect.toRect()
        result.houseValid[index] = true
  for rect in loadResourceRects(root / "data" / "home_map.resource"):
    if rect.rectName() == "exit":
      result.exit = rect.toRect()
      result.hasExit = true

proc screenRectVisible(x, y, w, h: int): bool =
  ## Returns true when one screen-space rectangle overlaps the viewport.
  x < ViewportWidth and y < ViewportHeight and x + w > 0 and y + h > 0

proc playerDistanceSquared(bot: Bot, rect: Rect): int =
  ## Returns the squared distance from the bot foot pixel to one rectangle.
  pointRectDistanceSquared(
    bot.selfX.footXAt(),
    bot.selfY.footYAt(),
    rect
  )

proc playerFootX(bot: Bot): int =
  ## Returns the bot foot-center X coordinate.
  bot.selfX.footXAt()

proc playerFootY(bot: Bot): int =
  ## Returns the bot foot-center Y coordinate.
  bot.selfY.footYAt()

proc objectWorldX(bot: Bot, objectState: ObjectState): int =
  ## Converts one object X coordinate to current-map coordinates.
  objectState.x + bot.cameraX

proc objectWorldY(bot: Bot, objectState: ObjectState): int =
  ## Converts one object Y coordinate to current-map coordinates.
  objectState.y + bot.cameraY

proc objectFootX(bot: Bot, objectState: ObjectState): int =
  ## Converts one object X coordinate to current-map foot center.
  bot.objectWorldX(objectState).footXAt()

proc objectFootY(bot: Bot, objectState: ObjectState): int =
  ## Converts one object Y coordinate to current-map foot center.
  bot.objectWorldY(objectState).footYAt()

proc spriteInfo(bot: Bot, spriteId: int): SpriteInfo =
  ## Returns sprite metadata for one sprite id.
  if spriteId >= 0 and spriteId < bot.sprites.len:
    return bot.sprites[spriteId]

proc visiblePlayerName(bot: Bot, playerIndex: int): string =
  ## Returns the visible name for one player index.
  let objectId = NameObjectBase + playerIndex
  if objectId < 0 or objectId >= bot.objects.len:
    return
  let objectState = bot.objects[objectId]
  if not objectState.present:
    return
  let sprite = bot.spriteInfo(objectState.spriteId)
  if sprite == nil or not sprite.label.startsWith(NameLabelPrefix):
    return
  sprite.label[NameLabelPrefix.len .. ^1]

proc visibleChatText(bot: Bot, playerIndex: int): string =
  ## Returns the visible chat bubble text for one player.
  let objectId = ChatObjectBase + playerIndex
  if objectId < 0 or objectId >= bot.objects.len:
    return
  let objectState = bot.objects[objectId]
  if not objectState.present:
    return
  let sprite = bot.spriteInfo(objectState.spriteId)
  if sprite == nil or not sprite.label.startsWith(ChatLabelPrefix):
    return
  sprite.label[ChatLabelPrefix.len .. ^1]

proc scanHeardChats(bot: Bot) =
  ## Watches chat bubbles for sibling handshake tokens and rival hosts.
  ## A sibling token only counts when the embedded name matches the
  ## speaker's own name tag, so relayed copies cannot spoof a sibling.
  for objectId, objectState in bot.objects:
    if objectId < ChatObjectBase or objectId >= GardenObjectBase:
      continue
    let playerIndex = objectId - ChatObjectBase
    while playerIndex >= bot.heardChats.len:
      bot.heardChats.add("")
    if not objectState.present:
      bot.heardChats[playerIndex] = ""
      continue
    let text = bot.visibleChatText(playerIndex)
    if text == bot.heardChats[playerIndex]:
      continue
    if text.len == 0:
      bot.heardChats[playerIndex] = ""
      continue
    let speaker = bot.visiblePlayerName(playerIndex)
    if speaker.len == 0:
      # The name sprite can lag the bubble by a frame; leave the line
      # unconsumed so the next frame can attribute it.
      continue
    bot.heardChats[playerIndex] = text
    if playerIndex == bot.selfIndex or speaker == bot.playerName:
      continue
    if text.startsWith(SiblingToken):
      let parts = text.splitWhitespace()
      if parts.len >= 2 and parts[1] == speaker:
        let house = speaker.houseIndexForPlayerName()
        if house >= 0 and house < HouseCount and
            not bot.siblingHouses[house]:
          bot.siblingHouses[house] = true
          echo bot.name, ": sibling found: ", speaker, " house ", house + 1
      continue

proc logName(bot: Bot): string =
  ## Returns the username and fixed player name for bot logs.
  if bot.playerName.len == 0:
    return bot.name
  bot.name & " (" & bot.playerName & ")"

proc ensureSprite(bot: Bot, spriteId: int) =
  ## Ensures the sprite table can contain one sprite id.
  if spriteId >= bot.sprites.len:
    bot.sprites.setLen(spriteId + 1)

proc ensureObject(bot: Bot, objectId: int) =
  ## Ensures the object table can contain one object id.
  if objectId >= bot.objects.len:
    bot.objects.setLen(objectId + 1)

proc readU16(blob: string, offset: int): int =
  ## Reads one little-endian unsigned 16-bit value.
  int(uint16(blob[offset].uint8) or
    (uint16(blob[offset + 1].uint8) shl 8))

proc readI16(blob: string, offset: int): int =
  ## Reads one little-endian signed 16-bit value.
  let value = uint16(blob[offset].uint8) or
    (uint16(blob[offset + 1].uint8) shl 8)
  return int(cast[int16](value))

proc readU32(blob: string, offset: int): int =
  ## Reads one little-endian unsigned 32-bit value.
  int(uint32(blob[offset].uint8) or
    (uint32(blob[offset + 1].uint8) shl 8) or
    (uint32(blob[offset + 2].uint8) shl 16) or
    (uint32(blob[offset + 3].uint8) shl 24))

proc classifySprite(label: string): tuple[kind: SpriteKind, glyph: char] =
  ## Classifies one Heartleaf sprite protocol label.
  let lower = label.toLowerAscii()
  result = (kind: SpriteUnknown, glyph: '\0')
  if lower == MainWalkabilityLabel:
    result.kind = SpriteMainWalk
  elif lower == HomeWalkabilityLabel:
    result.kind = SpriteHomeWalk
  elif lower.startsWith(HomeBottomLabelPrefix):
    result.kind = SpriteHomeBottom
  elif lower.startsWith(MainBottomLabelPrefix):
    result.kind = SpriteMainBottom
  elif lower == GardenMarkerLabel:
    result.kind = SpriteGarden
  elif lower.startsWith(GnomeLabelPrefix):
    result.kind = SpriteGnome
  elif lower.startsWith(NameLabelPrefix):
    result.kind = SpriteName
  elif lower.startsWith(ChatLabelPrefix):
    result.kind = SpriteChat
  elif lower.startsWith(ClockLabelPrefix):
    result.kind = SpriteClock
    if label.len > ClockLabelPrefix.len:
      result.glyph = label[ClockLabelPrefix.len]
    else:
      result.glyph = ' '
  elif lower.startsWith(ScoreLabelPrefix) or lower.startsWith(DinnerLabelPrefix):
    result.kind = SpriteOverlay

proc needsPixels(kind: SpriteKind): bool =
  ## Returns true when the bot needs sprite pixels for navigation.
  kind in {SpriteMainWalk, SpriteHomeWalk}

proc buildNavSpace(sprite: SpriteInfo): JumpPointSpace =
  ## Builds a pathy JPS+ space from one walkability sprite.
  var walkMask = newSeq[bool](sprite.width * sprite.height)
  for i in 0 ..< walkMask.len:
    walkMask[i] = sprite.pixels[i * 4 + 3] > 0
  newJumpPointSpace(walkMask, sprite.width, sprite.height, DiagonalPath)

proc nearestPassablePoint(nav: JumpPointSpace, x, y: int): Point =
  ## Returns the nearest walkable foot pixel to a position.
  result = Point(
    x: x.clamp(0, nav.path.width - 1),
    y: y.clamp(0, nav.path.height - 1)
  )
  if nav.path.passable(result.x, result.y):
    return
  let step = nav.path.nearestPassable(
    result.x,
    result.y,
    max(nav.path.width, nav.path.height)
  )
  if step.found:
    result = Point(x: step.x, y: step.y)

proc nearestPointInside(nav: JumpPointSpace, rect: Rect, x, y: int): Point =
  ## Returns the nearest walkable foot pixel inside one rectangle.
  result = rect.center()
  if nav == nil:
    return
  var bestDistance = high(int)
  for py in max(0, rect.y) ..< min(nav.path.height, rect.y + rect.h):
    for px in max(0, rect.x) ..< min(nav.path.width, rect.x + rect.w):
      if not nav.path.passable(px, py):
        continue
      let distance = distanceSquared(px, py, x, y)
      if distance < bestDistance:
        bestDistance = distance
        result = Point(x: px, y: py)

proc nearestPointOutside(
  nav: JumpPointSpace,
  rect: Rect,
  desired: Point,
  radius: int
): tuple[found: bool, point: Point] =
  ## Returns the nearest walkable point near but outside one rectangle.
  if nav == nil:
    return
  var
    bestDistance = high(int)
    bestRectDistance = high(int)
  let
    minX = max(0, rect.x - radius)
    maxX = min(nav.path.width - 1, rect.x + rect.w + radius)
    minY = max(0, rect.y - radius)
    maxY = min(nav.path.height - 1, rect.y + rect.h + radius)
  for py in minY .. maxY:
    for px in minX .. maxX:
      if rect.contains(px, py):
        continue
      if not nav.path.passable(px, py):
        continue
      let rectDistance = pointRectDistanceSquared(px, py, rect)
      if rectDistance > radius * radius:
        continue
      let distance = distanceSquared(px, py, desired.x, desired.y)
      if distance < bestDistance or
          (distance == bestDistance and rectDistance < bestRectDistance):
        bestDistance = distance
        bestRectDistance = rectDistance
        result = (found: true, point: Point(x: px, y: py))

proc toDensePath(steps: openArray[PathStep]): seq[Point] =
  ## Converts sparse jump-point steps into a dense followable path.
  for step in steps:
    let point = Point(x: step.x, y: step.y)
    if result.len == 0:
      result.add(point)
      continue
    let
      previous = result[^1]
      dx = point.x - previous.x
      dy = point.y - previous.y
      span = max(abs(dx), abs(dy))
    var walked = PathDensifyPixels
    while walked < span:
      result.add(Point(
        x: previous.x + dx * walked div span,
        y: previous.y + dy * walked div span
      ))
      walked += PathDensifyPixels
    result.add(point)

proc pathTo(
  nav: JumpPointSpace,
  startX,
  startY,
  goalX,
  goalY: int
): seq[Point] =
  ## Finds a JPS+ path between two foot pixels.
  if nav == nil:
    return
  let
    start = nav.nearestPassablePoint(startX, startY)
    goal = nav.nearestPassablePoint(goalX, goalY)
  nav.findPath(start.x, start.y, goal.x, goal.y).toDensePath()

proc pathTo(
  nav: JumpPointSpace,
  startX,
  startY: int,
  rect: Rect
): seq[Point] =
  ## Finds a JPS+ path to a walkable pixel inside one rectangle.
  if nav == nil:
    return
  let goal = nav.nearestPointInside(rect, startX, startY)
  nav.pathTo(startX, startY, goal.x, goal.y)

proc pathNear(
  nav: JumpPointSpace,
  startX,
  startY: int,
  rect: Rect,
  radius: int
): seq[Point] =
  ## Finds a JPS+ path to a pixel that can interact with one rectangle.
  if nav == nil:
    return
  if nav.path.passable(startX, startY) and
      pointRectDistanceSquared(startX, startY, rect) <= radius * radius:
    return @[Point(x: startX, y: startY)]
  var candidates: seq[tuple[distance: int, point: Point]]
  let
    minX = max(0, rect.x - radius)
    maxX = min(nav.path.width - 1, rect.x + rect.w + radius)
    minY = max(0, rect.y - radius)
    maxY = min(nav.path.height - 1, rect.y + rect.h + radius)
  for py in countup(minY, maxY, 2):
    for px in countup(minX, maxX, 2):
      if not nav.path.passable(px, py):
        continue
      if pointRectDistanceSquared(px, py, rect) > radius * radius:
        continue
      candidates.add((
        distance: distanceSquared(px, py, startX, startY),
        point: Point(x: px, y: py)
      ))
  candidates.sort(proc(a, b: tuple[distance: int, point: Point]): int =
    cmp(a.distance, b.distance))
  # Nearby candidates are usually reachable; spread later attempts out
  # across the sorted list in case the closest side is walled off.
  var tried = 0
  var index = 0
  while index < candidates.len and tried < 8:
    result = nav.pathTo(
      startX,
      startY,
      candidates[index].point.x,
      candidates[index].point.y
    )
    if result.len > 0:
      return
    inc tried
    index += max(1, candidates.len div 8)

proc sameGoal(a, b: Goal): bool =
  ## Returns true when two goals are the same navigation target.
  a.kind == b.kind and
    a.screenKind == b.screenKind and
    a.x == b.x and
    a.y == b.y and
    a.houseIndex == b.houseIndex and
    a.gardenIndex == b.gardenIndex and
    a.targetName == b.targetName

proc navForCurrentMap(bot: Bot): JumpPointSpace =
  ## Returns the navigation space for the current observed map.
  case bot.screenKind
  of MainMap:
    bot.mainNav
  of HomeMap:
    bot.homeNav
  else:
    nil

proc updateNavSprite(bot: Bot, sprite: SpriteInfo) =
  ## Stores a decoded walkability sprite as a navigation map.
  if not sprite.kind.needsPixels() or
      sprite.pixels.len != sprite.width * sprite.height * 4:
    return
  case sprite.kind
  of SpriteMainWalk:
    bot.mainNav = sprite.buildNavSpace()
    bot.mainWidth = sprite.width
    bot.mainHeight = sprite.height
  of SpriteHomeWalk:
    bot.homeNav = sprite.buildNavSpace()
  else:
    discard

proc applySpritePacket(bot: Bot, packet: string): bool =
  ## Applies one or more Heartleaf sprite protocol messages.
  var offset = 0
  while offset < packet.len:
    let messageType = packet[offset].uint8
    inc offset
    case messageType
    of 0x01:
      if offset + 10 > packet.len:
        return false
      let
        spriteId = packet.readU16(offset)
        width = packet.readU16(offset + 2)
        height = packet.readU16(offset + 4)
        compressedLen = packet.readU32(offset + 6)
      offset += 10
      if offset + compressedLen + 2 > packet.len:
        return false
      let compressedStart = offset
      offset += compressedLen
      let labelLen = packet.readU16(offset)
      offset += 2
      if offset + labelLen > packet.len:
        return false
      let label =
        if labelLen > 0:
          packet.substr(offset, offset + labelLen - 1)
        else:
          ""
      offset += labelLen
      let classified = classifySprite(label)
      var pixels: seq[uint8]
      if classified.kind.needsPixels():
        let compressed =
          if compressedLen > 0:
            packet.substr(compressedStart, compressedStart + compressedLen - 1)
          else:
            ""
        try:
          let rawPixels = supersnappy.uncompress(compressed)
          pixels = newSeq[uint8](rawPixels.len)
          for i, ch in rawPixels:
            pixels[i] = ch.uint8
        except CatchableError:
          if classified.kind.needsPixels():
            return false
          pixels.setLen(0)
        if pixels.len != width * height * 4:
          if classified.kind.needsPixels():
            return false
          pixels.setLen(0)
      bot.ensureSprite(spriteId)
      bot.sprites[spriteId] = SpriteInfo(
        defined: true,
        width: width,
        height: height,
        label: label,
        kind: classified.kind,
        glyph: classified.glyph,
        pixels: pixels
      )
      bot.updateNavSprite(bot.sprites[spriteId])
    of 0x02:
      if offset + 11 > packet.len:
        return false
      let
        objectId = packet.readU16(offset)
        x = packet.readI16(offset + 2)
        y = packet.readI16(offset + 4)
        z = packet.readI16(offset + 6)
        layer = int(packet[offset + 8].uint8)
        spriteId = packet.readU16(offset + 9)
      offset += 11
      bot.ensureObject(objectId)
      bot.objects[objectId] = ObjectState(
        present: true,
        x: x,
        y: y,
        z: z,
        layer: layer,
        spriteId: spriteId
      )
    of 0x03:
      if offset + 2 > packet.len:
        return false
      let objectId = packet.readU16(offset)
      offset += 2
      if objectId >= 0 and objectId < bot.objects.len:
        bot.objects[objectId].present = false
    of 0x04:
      for objectState in bot.objects.mitems:
        objectState.present = false
    of 0x05:
      if offset + 5 > packet.len:
        return false
      offset += 5
    of 0x06:
      if offset + 3 > packet.len:
        return false
      offset += 3
    else:
      return false
  true

proc clockText(bot: Bot): string =
  ## Reads the current clock text from visible glyph objects.
  var glyphs: seq[tuple[x: int, ch: char]]
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < ClockObjectBase or objectId >= ScoreObjectBase:
      continue
    let sprite = bot.spriteInfo(objectState.spriteId)
    if sprite == nil or sprite.kind != SpriteClock:
      continue
    glyphs.add((x: objectState.x, ch: sprite.glyph))
  glyphs.sort(proc(a, b: tuple[x: int, ch: char]): int = cmp(a.x, b.x))
  for glyph in glyphs:
    result.add(glyph.ch)
  result = result.strip()

proc log(bot: Bot, text: string) =
  ## Writes one bot activity log line.
  echo bot.logName(), ": ", text, " (", bot.clockText(), ")"


proc resetGardenPlan(bot: Bot) =
  ## Resets the static garden checklist for a new day.
  inc bot.dayIndex
  bot.gardenChecked = newSeq[bool](bot.resources.gardens.len)
  bot.currentGarden = -1
  bot.pendingChat = ""
  bot.hasPendingChat = false
  bot.path.setLen(0)
  bot.goal = Goal(kind: GoalIdle, screenKind: UnknownScreen)
  for house in 0 ..< HouseCount:
    bot.pitchedToday[house] = false

proc updateClock(bot: Bot) =
  ## Updates the bot's current day clock from the UI glyphs.
  let minutes = bot.clockText().parseClockMinutes()
  if minutes >= 0:
    if bot.minutes > minutes:
      bot.resetGardenPlan()
    bot.minutes = minutes

proc updateScreenKind(bot: Bot) =
  ## Updates the visible screen kind and camera offset.
  bot.previousScreenKind = bot.screenKind
  bot.screenKind = OverlayScreen
  bot.cameraX = 0
  bot.cameraY = 0
  if BottomObjectId >= bot.objects.len:
    return
  let bottom = bot.objects[BottomObjectId]
  if not bottom.present:
    return
  let sprite = bot.spriteInfo(bottom.spriteId)
  if sprite == nil:
    return
  case sprite.kind
  of SpriteMainBottom:
    bot.screenKind = MainMap
  of SpriteHomeBottom:
    bot.screenKind = HomeMap
  else:
    bot.screenKind = UnknownScreen
  bot.cameraX = -bottom.x
  bot.cameraY = -bottom.y
  if bot.screenKind != bot.previousScreenKind:
    bot.path.setLen(0)
    if bot.screenKind == HomeMap and bot.pendingHouse >= 0:
      bot.currentHouse = bot.pendingHouse
      bot.pendingHouse = UnknownHouse
    elif bot.screenKind == MainMap:
      bot.currentHouse = UnknownHouse

proc findSelfIndexByName(bot: Bot): int =
  ## Returns the player index whose name tag matches this bot.
  result = -1
  if bot.playerName.len == 0:
    return
  let expected = NameLabelPrefix & bot.playerName
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < NameObjectBase or objectId >= GardenObjectBase:
      continue
    let sprite = bot.spriteInfo(objectState.spriteId)
    if sprite != nil and sprite.label == expected:
      return objectId - NameObjectBase

proc findSelfIndexByCamera(bot: Bot): int =
  ## Returns the player index closest to the camera center.
  result = -1
  var bestDistance = high(int)
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let distance = distanceSquared(
      objectState.x.footXAt(),
      objectState.y.footYAt(),
      ViewportWidth div 2,
      ViewportHeight div 2
    )
    if distance < bestDistance:
      bestDistance = distance
      result = objectId - PlayerObjectBase

proc adoptHomeIdentity(bot: Bot, homeIndex: int) =
  ## Learns the controlled gnome name from its fixed home number.
  if bot.playerName.len > 0:
    return
  if homeIndex < 0 or homeIndex >= PlayerNames.len:
    return
  let name = homeIndex.playerNameForHouse()
  bot.playerName = name
  bot.homeIndex = homeIndex
  bot.currentHouse =
    if bot.screenKind == HomeMap:
      homeIndex
    else:
      UnknownHouse
  bot.pendingHouse = UnknownHouse
  bot.currentGarden = -1
  bot.path.setLen(0)
  bot.goal = Goal(kind: GoalIdle, screenKind: UnknownScreen)

proc nearestMorningHome(bot: Bot): int =
  ## Returns the nearest home inferred from the morning world spawn.
  result = UnknownHouse
  if bot.screenKind != MainMap or bot.minutes > MorningIdentityUntilMinutes:
    return
  var bestDistance = MorningIdentityRadius * MorningIdentityRadius + 1
  for i, house in bot.resources.houses:
    if not bot.resources.houseValid[i]:
      continue
    let distance = pointRectDistanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      house
    )
    if distance <= MorningIdentityRadius * MorningIdentityRadius and
        distance < bestDistance:
      bestDistance = distance
      result = i

proc adoptVisibleIdentity(bot: Bot, selfIndex: int) =
  ## Learns the controlled gnome name from its visible name tag.
  let name = bot.visiblePlayerName(selfIndex)
  if name.len == 0:
    return
  bot.adoptHomeIdentity(name.houseIndexForPlayerName())

proc updateSelf(bot: Bot) =
  ## Updates the bot's own player position from actor objects.
  bot.localized = false
  let cameraIndex = bot.findSelfIndexByCamera()
  var selfIndex = -1
  if bot.slot >= 0:
    selfIndex = bot.findSelfIndexByName()
    if selfIndex < 0:
      selfIndex = cameraIndex
  elif bot.playerName.len == 0:
    selfIndex = cameraIndex
  elif cameraIndex >= 0 and
      bot.visiblePlayerName(cameraIndex) == bot.playerName:
    selfIndex = cameraIndex
  else:
    selfIndex = bot.findSelfIndexByName()
    if selfIndex < 0:
      selfIndex = cameraIndex
  let objectId = PlayerObjectBase + selfIndex
  if selfIndex < 0 or objectId >= bot.objects.len:
    return
  let objectState = bot.objects[objectId]
  if not objectState.present:
    return
  bot.selfIndex = selfIndex
  bot.selfX = bot.objectWorldX(objectState)
  bot.selfY = bot.objectWorldY(objectState)
  if bot.slot < 0 and bot.playerName.len == 0:
    let homeIndex = bot.nearestMorningHome()
    if homeIndex >= 0:
      bot.adoptHomeIdentity(homeIndex)
    else:
      bot.adoptVisibleIdentity(selfIndex)
  bot.localized = true

proc updateStuck(bot: Bot, mask: uint8) =
  ## Updates stuck detection and jitter recovery state.
  let moving = (mask and (
    ButtonUp or ButtonDown or ButtonLeft or ButtonRight
  )) != 0
  let
    footX = bot.playerFootX()
    footY = bot.playerFootY()
    blocked = footX == bot.previousX and footY == bot.previousY
    wobbling = footX == bot.previous2X and footY == bot.previous2Y and
      not blocked
  if moving and (blocked or wobbling):
    inc bot.stuckTicks
  else:
    bot.stuckTicks = 0
  bot.velEstX = footX - bot.previousX
  bot.velEstY = footY - bot.previousY
  bot.previous2X = bot.previousX
  bot.previous2Y = bot.previousY
  bot.previousX = footX
  bot.previousY = footY
  if bot.unstuckTicks > 0:
    dec bot.unstuckTicks
  elif bot.stuckTicks >= UnstuckAfterTicks and
      bot.stuckTicks mod UnstuckAfterTicks == 0:
    bot.unstuckTicks = UnstuckDurationTicks
    bot.unstuckMaskIndex = (bot.unstuckMaskIndex + 1) mod UnstuckMasks.len
    bot.path.setLen(0)
    bot.log("unstuck jitter " & $bot.unstuckMaskIndex)

proc gardenHasMarker(bot: Bot, gardenIndex: int): bool =
  ## Returns true when the current view has a garden exclamation marker.
  let objectId = GardenObjectBase + gardenIndex
  if objectId < 0 or objectId >= bot.objects.len:
    return false
  bot.objects[objectId].present

proc gardenMarkerVisible(bot: Bot, gardenIndex: int): bool =
  ## Returns true when one garden marker position is inside the viewport.
  if gardenIndex < 0 or gardenIndex >= bot.resources.gardens.len:
    return false
  let
    rect = bot.resources.gardens[gardenIndex]
    x = rect.x + rect.w div 2 - FoodSpriteSize div 2 - bot.cameraX
    y = rect.y + rect.h div 2 - FoodSpriteSize div 2 - bot.cameraY
  screenRectVisible(x, y, FoodSpriteSize, FoodSpriteSize)

proc anyGardenMarkers(bot: Bot): bool =
  ## Returns true when any known garden still has a visible marker.
  for i in 0 ..< bot.resources.gardens.len:
    if bot.gardenHasMarker(i):
      return true

proc nearbyMarkedGarden(bot: Bot): int =
  ## Returns a close marked garden that can be picked up now.
  result = -1
  if bot.screenKind != MainMap:
    return
  var bestDistance = CollectActionRadius * CollectActionRadius + 1
  for i, rect in bot.resources.gardens:
    if not bot.gardenHasMarker(i):
      continue
    let distance = pointRectDistanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      rect
    )
    if distance <= CollectActionRadius * CollectActionRadius and
        distance < bestDistance:
      result = i
      bestDistance = distance

proc parseInventoryCount(label: string): int =
  ## Parses a count from one inventory count sprite label.
  let parts = strutils.splitWhitespace(label)
  if parts.len == 0:
    return 0
  try:
    result = parseInt(parts[^1])
  except ValueError:
    result = 0

proc inventoryTotal(bot: Bot): int =
  ## Returns how many food items this bot is carrying.
  for foodIndex in 0 ..< FoodVeggieSlots:
    let countObjectId = InventoryCountObjectBase + foodIndex
    if countObjectId < bot.objects.len and
        bot.objects[countObjectId].present:
      let sprite = bot.spriteInfo(bot.objects[countObjectId].spriteId)
      if sprite != nil:
        result += sprite.label.parseInventoryCount()
        continue
    let iconObjectId = InventoryObjectBase + foodIndex
    if iconObjectId < bot.objects.len and bot.objects[iconObjectId].present:
      inc result

proc gardensExhausted(bot: Bot): bool =
  ## Returns true when the bot has checked every known garden.
  if bot.gardenChecked.len != bot.resources.gardens.len:
    return false
  if bot.anyGardenMarkers():
    return false
  for checked in bot.gardenChecked:
    if not checked:
      return false
  true

proc analyze(bot: Bot) =
  ## Rebuilds high-level bot state from decoded objects.
  bot.updateClock()
  bot.updateScreenKind()
  bot.updateSelf()
  if bot.screenKind == HomeMap and bot.currentHouse == UnknownHouse and
      bot.playerName.len > 0:
    bot.currentHouse = bot.homeIndex

proc homeIndexFromName(name: string): int =
  ## Guesses a zero-based home index from trailing name digits.
  var start = name.len
  while start > 0 and name[start - 1].isDigit():
    dec start
  if start >= name.len:
    return 0
  try:
    result = (parseInt(name[start .. ^1]) - 1).clamp(0, 8)
  except ValueError:
    result = 0

proc initBot(name: string, slot: int): Bot =
  ## Builds a new banquet bot state.
  result = Bot()
  result.name =
    if name.len > 0:
      name
    else:
      DefaultName
  result.slot = slot
  result.homeIndex =
    if slot >= 0 and slot < 9:
      slot
    else:
      result.name.homeIndexFromName()
  result.playerName =
    if slot >= 0 and slot < 9:
      result.homeIndex.playerNameForHouse()
    else:
      ""
  result.resources = loadBotResources()
  result.currentHouse =
    if result.playerName.len > 0:
      result.homeIndex
    else:
      UnknownHouse
  result.pendingHouse = UnknownHouse
  result.minutes = DayStartMinutes
  result.selfIndex = -1
  result.goal = Goal(kind: GoalIdle, screenKind: UnknownScreen)
  result.currentGarden = -1
  result.dayIndex = 0
  result.gardenChecked = newSeq[bool](result.resources.gardens.len)
  result.lastClockHour = -1
  for i in 0 ..< HouseCount:
    result.lastInviteTick[i] = -InviteCooldownTicks

proc gardenGoal(bot: Bot): Goal =
  ## Returns a goal for the nearest garden that may still have food.
  result = Goal(kind: GoalIdle, screenKind: MainMap)
  if bot.screenKind != MainMap or bot.mainNav == nil:
    return
  if bot.gardenChecked.len != bot.resources.gardens.len:
    bot.resetGardenPlan()

  let nearbyGarden = bot.nearbyMarkedGarden()
  if nearbyGarden >= 0:
    let target = bot.resources.gardens[nearbyGarden].center()
    bot.currentGarden = nearbyGarden
    return Goal(
      kind: GoalCollect,
      screenKind: MainMap,
      x: target.x,
      y: target.y,
      gardenIndex: nearbyGarden,
      houseIndex: UnknownHouse
    )

  if bot.currentGarden >= 0 and
      bot.currentGarden < bot.gardenChecked.len and
      not bot.gardenChecked[bot.currentGarden]:
    if bot.gardenMarkerVisible(bot.currentGarden) and
        not bot.gardenHasMarker(bot.currentGarden):
      bot.gardenChecked[bot.currentGarden] = true
      bot.currentGarden = -1
    else:
      let rect = bot.resources.gardens[bot.currentGarden]
      let target = rect.center()
      return Goal(
        kind: GoalCollect,
        screenKind: MainMap,
        x: target.x,
        y: target.y,
        gardenIndex: bot.currentGarden,
        houseIndex: UnknownHouse
      )

  let preferMarkers = bot.anyGardenMarkers()
  for i in 0 ..< bot.resources.gardens.len:
    if i < bot.gardenChecked.len and
        bot.gardenMarkerVisible(i) and
        not bot.gardenHasMarker(i):
      bot.gardenChecked[i] = true
  if bot.currentGarden >= 0 and
      bot.currentGarden < bot.gardenChecked.len and
      not bot.gardenChecked[bot.currentGarden]:
    let rect = bot.resources.gardens[bot.currentGarden]
    let target = rect.center()
    return Goal(
        kind: GoalCollect,
        screenKind: MainMap,
        x: target.x,
        y: target.y,
        gardenIndex: bot.currentGarden,
        houseIndex: UnknownHouse
    )

  var
    bestIndex = -1
    bestPathLen = high(int)
    bestDistance = high(int)
  for i, rect in bot.resources.gardens:
    if i < bot.gardenChecked.len and bot.gardenChecked[i]:
      continue
    if preferMarkers and bot.gardenMarkerVisible(i) and
        not bot.gardenHasMarker(i):
      continue
    let path = bot.mainNav.pathNear(
      bot.playerFootX(),
      bot.playerFootY(),
      rect,
      CollectActionRadius
    )
    if path.len == 0:
      if i < bot.gardenChecked.len:
        bot.gardenChecked[i] =
          bot.gardenMarkerVisible(i) and not bot.gardenHasMarker(i)
      continue
    let
      target = rect.center()
      distance = distanceSquared(
        bot.playerFootX(),
        bot.playerFootY(),
        target.x,
        target.y
      )
    if path.len < bestPathLen or
        (path.len == bestPathLen and distance < bestDistance):
      bestIndex = i
      bestPathLen = path.len
      bestDistance = distance
  if bestIndex < 0:
    return

  bot.currentGarden = bestIndex
  let target = bot.resources.gardens[bestIndex].center()
  result = Goal(
    kind: GoalCollect,
    screenKind: MainMap,
    x: target.x,
    y: target.y,
    gardenIndex: bestIndex,
    houseIndex: UnknownHouse
  )

proc goalForRect(
  bot: Bot,
  kind: GoalKind,
  rect: Rect,
  houseIndex: int
): Goal =
  ## Returns a navigation goal for standing inside one rectangle.
  let nav = bot.navForCurrentMap()
  var target = rect.center()
  if nav != nil:
    target = nav.nearestPointInside(rect, target.x, target.y)
  Goal(
    kind: kind,
    screenKind: bot.screenKind,
    x: target.x,
    y: target.y,
    houseIndex: houseIndex,
    gardenIndex: -1
  )

proc exitGoal(bot: Bot): Goal =
  ## Returns a goal for leaving the current home map.
  if not bot.resources.hasExit:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  bot.goalForRect(GoalExitHouse, bot.resources.exit, UnknownHouse)

proc enterHouseGoal(bot: Bot, houseIndex: int): Goal =
  ## Returns a goal for entering one main-map house.
  if houseIndex < 0 or houseIndex >= bot.resources.houseValid.len or
      not bot.resources.houseValid[houseIndex]:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  bot.goalForRect(GoalEnterHouse, bot.resources.houses[houseIndex], houseIndex)

proc playerNearHouse(
  bot: Bot,
  objectState: ObjectState,
  houseIndex: int
): bool =
  ## Returns true when a player object is waiting near one house.
  if houseIndex < 0 or
      houseIndex >= bot.resources.houseValid.len or
      not bot.resources.houseValid[houseIndex]:
    return false
  pointRectDistanceSquared(
    bot.objectFootX(objectState),
    bot.objectFootY(objectState),
    bot.resources.houses[houseIndex]
  ) <= HouseGatherMaxRadius * HouseGatherMaxRadius

proc visiblePlayerHome(bot: Bot, playerIndex: int): int =
  ## Returns the fixed home index for one visible player.
  bot.visiblePlayerName(playerIndex).houseIndexForPlayerName()

proc houseCrowdOthers(bot: Bot, houseIndex: int): int =
  ## Returns how many other visible gnomes are gathered near one house.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if playerIndex == bot.selfIndex:
      continue
    if bot.visiblePlayerName(playerIndex) == bot.playerName:
      continue
    if bot.playerNearHouse(objectState, houseIndex):
      inc result

proc desiredHouseGatherPoint(bot: Bot, house: Rect): Point =
  ## Returns this bot's preferred outside door spot around one house.
  let
    slot = bot.homeIndex mod DoorGatherSlots
    offset = (slot - DoorGatherSlots div 2) * DoorGatherSpacing
  return Point(
    x: house.x + house.w div 2 + offset,
    y: house.y + house.h + 4
  )

proc houseGatherPoint(bot: Bot, houseIndex: int): Point =
  ## Returns a walkable outside gathering point near one house.
  result = Point(x: bot.playerFootX(), y: bot.playerFootY())
  if bot.mainNav == nil or
      houseIndex < 0 or
      houseIndex >= bot.resources.houseValid.len or
      not bot.resources.houseValid[houseIndex]:
    return
  let
    house = bot.resources.houses[houseIndex]
    desired = bot.desiredHouseGatherPoint(house)
    outside = bot.mainNav.nearestPointOutside(
      house,
      desired,
      HouseGatherMaxRadius
    )
  if outside.found:
    result = outside.point

proc gatherAtHouseGoal(bot: Bot, houseIndex: int): Goal =
  ## Returns a goal that keeps the bot visible outside one house.
  if bot.screenKind == HomeMap:
    return bot.exitGoal()
  if bot.screenKind != MainMap:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  let point = bot.houseGatherPoint(houseIndex)
  Goal(
    kind: GoalGatherHouse,
    screenKind: MainMap,
    x: point.x,
    y: point.y,
    houseIndex: houseIndex,
    gardenIndex: -1
  )

proc gatherOwnHouseGoal(bot: Bot): Goal =
  ## Returns the goal that keeps the bot outside its own house.
  bot.gatherAtHouseGoal(bot.homeIndex)

proc firstDinerGoal(bot: Bot): Goal =
  ## Returns a small idle movement goal away from the home exit.
  Goal(
    kind: GoalMove,
    screenKind: bot.screenKind,
    x: bot.playerFootX(),
    y: bot.playerFootY(),
    houseIndex: bot.currentHouse,
    gardenIndex: -1
  )

proc ownHomeGoal(bot: Bot): Goal =
  ## Returns the goal that gets the bot into its own house.
  if bot.screenKind == HomeMap:
    if bot.currentHouse == bot.homeIndex:
      return bot.firstDinerGoal()
    return bot.exitGoal()
  if bot.screenKind == MainMap:
    return bot.enterHouseGoal(bot.homeIndex)
  Goal(kind: GoalIdle, screenKind: bot.screenKind)

proc visibleOtherPlayerCount(bot: Bot): int =
  ## Returns how many other player sprites are visible now.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    if objectId - PlayerObjectBase != bot.selfIndex:
      inc result

proc hostHouse(bot: Bot): int =
  ## Returns the elected dinner-host house: the lowest house index
  ## among this bot and every known sibling.
  result = bot.homeIndex
  for house in 0 ..< HouseCount:
    if bot.siblingHouses[house] and house < result:
      result = house

proc knownSiblingCount(bot: Bot): int =
  ## Returns how many sibling seats have been discovered so far.
  for house in 0 ..< HouseCount:
    if bot.siblingHouses[house]:
      inc result

proc role(bot: Bot): BotRole =
  ## Returns the current coordination role from the sibling election.
  if bot.knownSiblingCount() == 0:
    return RoleSolo
  if bot.hostHouse() == bot.homeIndex:
    return RoleHost
  RoleGuest

proc inRendezvous(bot: Bot): bool =
  ## Returns true while the sibling handshake is still worth sending.
  ## The handshake rides along with gathering rather than taking a trip
  ## of its own: every garden is stripped within the first few hours,
  ## so a morning spent meeting is a whole day of food conceded, and
  ## the gardens are where the other gnomes are anyway.
  if bot.knownSiblingCount() > 0:
    return bot.tokensNearSibling < HandshakeConfirmSends
  bot.minutes < RendezvousEndMinutes

proc tourTarget(bot: Bot): int =
  ## Returns the nearest house whose owner has not been pitched today.
  ## Rival hosts and siblings are skipped; they are not recruitable.
  result = UnknownHouse
  if bot.screenKind != MainMap or bot.mainNav == nil:
    return
  var bestDistance = high(int)
  for house in 0 ..< HouseCount:
    if house == bot.homeIndex or bot.siblingHouses[house] or
        bot.pitchedToday[house]:
      continue
    if house >= bot.resources.houseValid.len or
        not bot.resources.houseValid[house]:
      continue
    let distance = pointRectDistanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      bot.resources.houses[house]
    )
    if distance < bestDistance:
      bestDistance = distance
      result = house

proc gatherGoal(bot: Bot): Goal =
  ## Returns the default harvest-race goal.
  if bot.screenKind == HomeMap:
    return bot.exitGoal()
  if bot.screenKind == MainMap:
    let garden = bot.gardenGoal()
    if garden.kind != GoalIdle:
      return garden
    return bot.gatherOwnHouseGoal()
  Goal(kind: GoalIdle, screenKind: bot.screenKind)

proc guestDinnerGoal(bot: Bot): Goal =
  ## Returns the guest-side dinner goal: wait at the host's door from
  ## late afternoon, then sit inside through the 6:55pm tally.
  let host = bot.hostHouse()
  if bot.minutes >= DinnerEnterMinutes:
    if bot.screenKind == HomeMap:
      if bot.currentHouse == host:
        return bot.firstDinerGoal()
      return bot.exitGoal()
    if bot.screenKind == MainMap:
      return bot.enterHouseGoal(host)
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  if bot.screenKind == HomeMap:
    return bot.exitGoal()
  bot.gatherAtHouseGoal(host)

proc banquetGoal(bot: Bot): Goal =
  ## Returns the banquet goal for the current clock and role. Race the
  ## gardens at dawn while they still hold food, spend the long empty
  ## middle of the day recruiting door to door, then host or attend the
  ## 6:55pm tally.
  if not bot.localized or bot.navForCurrentMap() == nil:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  if bot.screenKind == OverlayScreen:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  if bot.minutes >= DayEndMinutes:
    return bot.ownHomeGoal()
  if bot.minutes >= EveningGatherMinutes:
    return bot.gatherGoal()
  if bot.minutes >= GatherUntilMinutes:
    if bot.role() == RoleGuest:
      return bot.guestDinnerGoal()
    if bot.minutes >= DinnerEnterMinutes:
      return bot.ownHomeGoal()
    if bot.screenKind == HomeMap:
      return bot.exitGoal()
    return bot.gatherOwnHouseGoal()
  # Only the host's food is ever spent, so the host farms and the guest
  # twin buys guests instead: chat reaches only gnomes whose screen we
  # are on, so someone has to walk to the doors, and the guest's own
  # harvest would never be served to anyone.
  let touring =
    case bot.role()
    of RoleGuest: true
    of RoleHost, RoleSolo: bot.minutes >= TourFromMinutes
  if touring:
    var house = bot.tourTarget()
    if house == UnknownHouse:
      # A lap is done; start another so gnomes who were out gathering
      # the first time round still get asked.
      for i in 0 ..< HouseCount:
        bot.pitchedToday[i] = false
      house = bot.tourTarget()
    if house != UnknownHouse:
      # Count the door as worked once we arrive, so an owner who is out
      # gathering costs one visit rather than looping the rest of the day.
      if bot.screenKind == MainMap and
          pointRectDistanceSquared(
            bot.playerFootX(),
            bot.playerFootY(),
            bot.resources.houses[house]
          ) <= HouseGatherMaxRadius * HouseGatherMaxRadius:
        bot.pitchedToday[house] = true
      return bot.gatherAtHouseGoal(house)
  bot.gatherGoal()

proc queueChat(bot: Bot, line: string) =
  ## Queues one chat line for sending on the next possible frame.
  if bot.hasPendingChat or line.len == 0:
    return
  bot.pendingChat =
    if line.len > ChatMaxChars:
      line[0 ..< ChatMaxChars]
    else:
      line
  bot.hasPendingChat = true

proc siblingVisible(bot: Bot): bool =
  ## Returns true when any known sibling gnome is on screen now.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if playerIndex == bot.selfIndex:
      continue
    let house = bot.visiblePlayerName(playerIndex).houseIndexForPlayerName()
    if house >= 0 and house < HouseCount and bot.siblingHouses[house]:
      return true

proc maybeHandshake(bot: Bot) =
  ## Broadcasts the sibling token during the morning meetup window.
  ## Sends with a sibling in view count toward the confirm quota that
  ## lets both twins leave the meetup around the same time.
  if not bot.inRendezvous() or bot.playerName.len == 0:
    return
  if bot.frameTick - bot.lastTokenTick < HandshakeIntervalTicks:
    return
  bot.lastTokenTick = bot.frameTick
  inc bot.tokenSerial
  if bot.siblingVisible():
    inc bot.tokensNearSibling
  bot.queueChat(SiblingToken & bot.playerName & " " & $bot.tokenSerial)

proc inviteLine(bot: Bot, targetName, hostName: string): string =
  ## Builds one invitation to our real party at our real house.
  ## One wording serves both audiences: the token and house clause that
  ## scripted listeners parse, with full names so listeners that read
  ## chat as language can resolve the house too. Never abbreviate the
  ## host — a listener that cannot resolve the name still treats the
  ## line as its one accepted invitation and then declines every later
  ## one, so a short name costs the guest outright.
  if bot.minutes >= SummonFromMinutes:
    return InviteToken & targetName & " come now! " & InviteHouseClause &
      hostName & "'s house!"
  InviteToken & targetName & "! " & InviteHouseClause & hostName &
    "'s house tonight!"

proc maybeInvite(bot: Bot) =
  ## Invites one visible gnome to the host twin's dinner. Targets are
  ## ranked by how promising they are — a gnome that advertises its own
  ## house is recruiting, not available — then by distance. Invitations
  ## run from early morning, hours before rival hosts start recruiting,
  ## because a listener's first accepted invitation is the binding one.
  if bot.hasPendingChat or bot.playerName.len == 0:
    return
  if bot.inRendezvous():
    return
  if bot.minutes < DayStartMinutes + 30 or
      bot.minutes >= DinnerEnterMinutes:
    return
  let hostName = bot.hostHouse().playerNameForHouse()
  var
    bestIndex = -1
    bestDistance = high(int)
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if playerIndex == bot.selfIndex:
      continue
    let name = bot.visiblePlayerName(playerIndex)
    if name.len == 0 or name == bot.playerName:
      continue
    let house = name.houseIndexForPlayerName()
    if house < 0 or house >= HouseCount:
      continue
    if bot.siblingHouses[house] or house == bot.homeIndex:
      continue
    if bot.frameTick - bot.lastInviteTick[house] < InviteCooldownTicks:
      continue
    let distance = distanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      bot.objectFootX(objectState),
      bot.objectFootY(objectState)
    )
    if distance >= bestDistance:
      continue
    bestDistance = distance
    bestIndex = playerIndex
  if bestIndex < 0:
    return
  let
    name = bot.visiblePlayerName(bestIndex)
    house = name.houseIndexForPlayerName()
    line = bot.inviteLine(name, hostName)
  bot.lastInviteTick[house] = bot.frameTick
  bot.pitchedToday[house] = true
  inc bot.invitesSent[house]
  bot.queueChat(line)

proc maybeSendPendingChat(bot: Bot, ws: WebSocket) =
  ## Sends one queued chat line when someone can hear it.
  if not bot.hasPendingChat:
    return
  if bot.screenKind == OverlayScreen:
    return
  if bot.visibleOtherPlayerCount() == 0:
    return
  ws.send(blobFromChat(bot.pendingChat), BinaryMessage)
  bot.log("chat " & bot.pendingChat)
  bot.pendingChat = ""
  bot.hasPendingChat = false
  bot.lastChatSentTick = bot.frameTick

proc goalReached(bot: Bot, goal: Goal): bool =
  ## Returns true when the bot is close enough to a goal to act.
  case goal.kind
  of GoalCollect:
    if goal.gardenIndex >= 0 and
        goal.gardenIndex < bot.resources.gardens.len:
      return pointRectDistanceSquared(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.gardens[goal.gardenIndex]
      ) <= CollectActionRadius * CollectActionRadius
    distanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    ) <= CollectActionRadius * CollectActionRadius
  of GoalEnterHouse:
    let house = bot.resources.houses[goal.houseIndex]
    house.contains(bot.playerFootX(), bot.playerFootY())
  of GoalExitHouse:
    bot.resources.exit.contains(bot.playerFootX(), bot.playerFootY())
  of GoalStandPerson:
    distanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    ) <= PersonStandRadius * PersonStandRadius
  of GoalGatherHouse, GoalMove:
    distanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    ) <= GoalArrivePixels * GoalArrivePixels
  of GoalIdle:
    true

proc goalLabel(goal: Goal): string =
  ## Returns a short debug label for one goal.
  case goal.kind
  of GoalIdle:
    "idle"
  of GoalCollect:
    "collect garden " & $goal.gardenIndex
  of GoalGatherHouse:
    "gather outside house " & $(goal.houseIndex + 1)
  of GoalEnterHouse:
    "enter house " & $(goal.houseIndex + 1)
  of GoalExitHouse:
    "exit house"
  of GoalStandPerson:
    "stand next to " & goal.targetName
  of GoalMove:
    "wait"

proc interactionMask(bot: Bot, goal: Goal): uint8 =
  ## Returns an A-button pulse when an interaction goal is ready.
  if bot.attackCooldown > 0:
    dec bot.attackCooldown
    return 0
  if not bot.goalReached(goal):
    return 0
  return case goal.kind
  of GoalCollect:
    bot.attackCooldown = 8
    bot.lastCollectTick = bot.frameTick
    if bot.currentGarden == goal.gardenIndex:
      bot.currentGarden = -1
    bot.path.setLen(0)
    bot.log(goal.goalLabel())
    ButtonA
  of GoalExitHouse:
    bot.attackCooldown = 8
    bot.log(goal.goalLabel())
    ButtonA
  of GoalEnterHouse:
    bot.attackCooldown = 8
    bot.pendingHouse = goal.houseIndex
    bot.log(goal.goalLabel())
    ButtonA
  else:
    0

proc ensurePath(bot: Bot, goal: Goal) =
  ## Recomputes the path when the navigation goal changes.
  let changed = not bot.goal.sameGoal(goal)
  if not changed and bot.path.len > 0 and bot.stuckTicks < RepathStuckTicks:
    return
  if changed:
    bot.log("goal " & goal.goalLabel())
  bot.goal = goal
  bot.path.setLen(0)
  let nav = bot.navForCurrentMap()
  if nav == nil or goal.kind == GoalIdle:
    return
  case goal.kind
  of GoalCollect:
    if goal.gardenIndex >= 0 and
        goal.gardenIndex < bot.resources.gardens.len:
      bot.path = nav.pathNear(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.gardens[goal.gardenIndex],
        CollectActionRadius
      )
  of GoalEnterHouse:
    if goal.houseIndex >= 0 and
        goal.houseIndex < bot.resources.houseValid.len and
        bot.resources.houseValid[goal.houseIndex]:
      bot.path = nav.pathTo(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.houses[goal.houseIndex]
      )
  of GoalExitHouse:
    if bot.resources.hasExit:
      bot.path = nav.pathTo(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.exit
      )
  else:
    bot.path = nav.pathTo(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    )
  if bot.path.len == 0:
    bot.path = nav.pathTo(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    )

proc pathTarget(bot: Bot, goal: Goal): Point =
  ## Returns the current lookahead point along the path.
  if goal.kind == GoalIdle:
    # An idle goal has no coordinates; stand still instead of
    # marching toward the map origin.
    return Point(x: bot.playerFootX(), y: bot.playerFootY())
  result = Point(x: goal.x, y: goal.y)
  if bot.path.len > 1:
    var
      bestIndex = 0
      bestDistance = high(int)
    for i, point in bot.path:
      let distance = distanceSquared(
        bot.playerFootX(),
        bot.playerFootY(),
        point.x,
        point.y
      )
      if distance < bestDistance:
        bestIndex = i
        bestDistance = distance
    if bestIndex > 0 and
        bestDistance <= PathRejoinPixels * PathRejoinPixels:
      for _ in 0 ..< bestIndex:
        bot.path.delete(0)
  while bot.path.len > 0 and
      distanceSquared(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.path[0].x,
        bot.path[0].y
      ) <= PathArrivePixels * PathArrivePixels:
    bot.path.delete(0)
  if bot.path.len > 0:
    result = bot.path[0]
    let nav = bot.navForCurrentMap()
    if nav != nil and nav.path != nil:
      # Steer toward the farthest waypoint with a clear line of sight,
      # like notsus, so paths cut corners instead of hugging waypoints.
      for i in 0 ..< min(bot.path.len, SteerLookaheadPoints):
        if nav.path.linePassable(
          bot.playerFootX(),
          bot.playerFootY(),
          bot.path[i].x,
          bot.path[i].y
        ):
          result = bot.path[i]
        else:
          break

proc needsMovement(bot: Bot, target: Point): bool =
  ## Returns true when a target is far enough to require button input.
  abs(target.x - bot.playerFootX()) > MoveDeadZonePixels or
    abs(target.y - bot.playerFootY()) > MoveDeadZonePixels

proc coastPixels(speed: int): int =
  ## Approximates how far crewrift friction coasts one speed estimate.
  ## Friction 144/256 leaves a geometric tail of about 9/7 of one tick.
  (abs(speed) * 9) div 7

proc axisMask(delta, speed: int, negativeMask, positiveMask: uint8): uint8 =
  ## Returns one axis input, coasting when momentum already arrives.
  if abs(delta) <= MoveDeadZonePixels:
    return 0
  let towardSpeed =
    if delta > 0:
      speed
    else:
      -speed
  if towardSpeed > 0 and coastPixels(towardSpeed) >= abs(delta):
    return 0
  if delta > 0:
    positiveMask
  else:
    negativeMask

proc movementMask(bot: Bot, target: Point): uint8 =
  ## Builds a directional input mask with arrival coasting so momentum
  ## does not overshoot the target and wobble back and forth.
  axisMask(
    target.x - bot.playerFootX(),
    bot.velEstX,
    ButtonLeft,
    ButtonRight
  ) or axisMask(
    target.y - bot.playerFootY(),
    bot.velEstY,
    ButtonUp,
    ButtonDown
  )

proc firstMovingPathTarget(bot: Bot, goal: Goal): Point =
  ## Returns the first path point that can actually produce movement.
  if goal.kind == GoalIdle:
    return Point(x: bot.playerFootX(), y: bot.playerFootY())
  for point in bot.path:
    if bot.needsMovement(point):
      return point
  result = Point(x: goal.x, y: goal.y)

proc decideNextMask(bot: Bot, ws: WebSocket): uint8 =
  ## Chooses the next input mask for one game frame.
  bot.analyze()
  bot.scanHeardChats()
  if not bot.localized:
    bot.desiredMask = 0
    bot.hasTarget = false
    return 0
  bot.maybeHandshake()
  bot.maybeInvite()
  let goal = bot.banquetGoal()
  let action = bot.interactionMask(goal)
  if action != 0:
    bot.desiredMask = action
    bot.hasTarget = false
    bot.updateStuck(action)
    return action
  bot.ensurePath(goal)
  var target = bot.pathTarget(goal)
  bot.target = target
  bot.hasTarget = goal.kind != GoalIdle
  result = bot.movementMask(target)
  if result == 0 and not bot.goalReached(goal):
    target = bot.firstMovingPathTarget(goal)
    bot.target = target
    result = bot.movementMask(target)
  if bot.unstuckTicks > 0 and result != 0:
    result = UnstuckMasks[bot.unstuckMaskIndex]
  bot.desiredMask = result
  bot.updateStuck(result)

proc queryEscape(value: string): string =
  ## Escapes a query string component.
  const Hex = "0123456789ABCDEF"
  for ch in value:
    if ch.isAlphaNumeric() or ch in {'-', '_', '.', '~'}:
      result.add(ch)
    else:
      let byte = ord(ch)
      result.add('%')
      result.add(Hex[(byte shr 4) and 0x0f])
      result.add(Hex[byte and 0x0f])

proc queryParam(url, name: string): string =
  ## Returns one raw query parameter value from a URL.
  let queryAt = url.find('?')
  if queryAt < 0:
    return
  var stop = url.find('#')
  if stop < 0:
    stop = url.len
  if queryAt + 1 >= stop:
    return
  for part in url[queryAt + 1 ..< stop].split('&'):
    let equalsAt = part.find('=')
    if equalsAt < 0:
      if part == name:
        return ""
      continue
    if part[0 ..< equalsAt] == name:
      return part[equalsAt + 1 .. ^1]

proc slotFromUrl(url: string): int =
  ## Returns the slot query value from a Coworld websocket URL.
  result = -1
  let text = url.queryParam("slot")
  if text.len == 0:
    return
  try:
    result = parseInt(text)
  except ValueError:
    result = -1

proc playerUrl(
  host: string,
  port: int,
  name,
  token: string,
  slot: int
): string =
  ## Builds the Heartleaf player websocket URL.
  result = "ws://" & host & ":" & $port & "/player"
  var sep = '?'
  if name.len > 0:
    result.add(sep)
    result.add("username=" & name.queryEscape())
    sep = '&'
  if slot >= 0:
    result.add(sep)
    result.add("slot=" & $slot)
    sep = '&'
  if token.len > 0:
    result.add(sep)
    result.add("token=" & token.queryEscape())

proc acceptServerMessage(ws: WebSocket, message: Message, bot: Bot): bool =
  ## Handles one websocket message and updates sprite state.
  case message.kind
  of BinaryMessage:
    result = bot.applySpritePacket(message.data)
    inc bot.frameTick
  of Ping:
    ws.send(message.data, Pong)
  of TextMessage, Pong:
    discard

proc receiveUpdates(ws: WebSocket, bot: Bot): bool =
  ## Receives and applies all currently queued sprite updates.
  let firstMessage = ws.receiveMessage(-1)
  if firstMessage.isNone:
    return false
  if ws.acceptServerMessage(firstMessage.get(), bot):
    result = true
  var drained = 0
  while drained < MaxDrainMessages:
    let message = ws.receiveMessage(0)
    if message.isNone:
      break
    if ws.acceptServerMessage(message.get(), bot):
      result = true
    inc drained

proc runBot(
  host: string,
  port: int,
  name,
  token: string,
  slot: int,
  url: string,
  exitOnDisconnect: bool
) =
  ## Connects one banquet bot to a Heartleaf sprite player endpoint.
  let connectUrl =
    if url.len > 0:
      url
    else:
      playerUrl(host, port, name, token, slot)
  var bot = initBot(name, slot)
  var hadConnection = false
  while true:
    try:
      let ws = newWebSocket(connectUrl)
      echo bot.name, " connected to ", connectUrl
      hadConnection = true
      bot.lastMask = 0xff'u8
      while true:
        if not ws.receiveUpdates(bot):
          continue
        let nextMask = bot.decideNextMask(ws)
        bot.maybeSendPendingChat(ws)
        if nextMask != bot.lastMask:
          ws.send(blobFromMask(nextMask), BinaryMessage)
          bot.lastMask = nextMask
    except CatchableError as e:
      echo bot.name, " reconnecting: ", e.msg
      if exitOnDisconnect and hadConnection:
        break
      sleep(250)

proc banquetMain*(defaultName = DefaultName) =
  ## Parses bot CLI options and runs one banquet bot.
  var
    address = DefaultHost
    port = DefaultPort
    name = defaultName
    token = ""
    slot = -1
    url = getEnv("COGAMES_ENGINE_WS_URL")
  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "address":
        address = val
      of "port":
        port = parseInt(val)
      of "name":
        name = val
      of "token":
        token = val
      of "slot":
        slot = parseInt(val)
      of "url":
        url = val
      else:
        discard
    else:
      discard
  if slot < 0 and url.len > 0:
    slot = url.slotFromUrl()
  runBot(address, port, name, token, slot, url, url.len > 0)
