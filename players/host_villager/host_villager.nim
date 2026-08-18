import
  std/[algorithm, json, options, os, parseopt, strutils, times],
  bitworld/[spriteprotocol, resources],
  curly, pathy, supersnappy, whisky,
  players/talking_villager/[bedrock_auth, decisions],
  heartleaf/[common, protocol]

const

  BedrockVersion = "bedrock-2023-05-31"
  DefaultBedrockRegion = "us-east-1"
  DefaultBedrockModel = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  DefaultBedrockTimeoutSeconds = 30
  ReconnectDelayMs = 1000
  ReconnectGiveUpSeconds = 8.0
  DefaultBedrockMaxTokens = 192
  BedrockTemperature = 0.2



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
  DefaultName = "host_villager"
  UnknownHouse = -1
  # Host-always policy schedule (minutes after midnight).
  GatherUntilMinutes = 15 * 60 + 35
  HostEnterMinutes = 17 * 60 + 15
  EveningGatherMinutes = 18 * 60 + 5
  # Chat cadence in frame ticks (24 ticks per real second).
  ChatIntervalTicks = 240
  ChatReplyIntervalTicks = 72
  ChatHistoryLimit = 80
  DoorGatherSlots = 5
  DoorGatherSpacing = 18
  HouseGatherMaxRadius = 96
  MorningIdentityUntilMinutes = 9 * 60
  MorningIdentityRadius = 140


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

  ConversationMessage = object
    role: string
    content: string

  BedrockResult = object
    done: bool
    ok: bool
    statusCode: int
    tag: string
    reply: string
    error: string

  TalkingVillagerError = object of CatchableError

  Bot = ref object
    name: string
    playerName: string
    soulTemplate: string
    soulInstructions: string
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
    chatHistory: seq[ConversationMessage]
    heardChats: seq[string]
    currentGarden: int
    dayIndex: int
    frameTick: int
    desiredMask: uint8
    target: Point
    hasTarget: bool
    llmWaiting: bool
    llmTag: string
    llmSerial: int
    lastLlmError: string
    llmPacer: LlmPacer
    pendingChat: string
    hasPendingChat: bool
    lastChatRequestTick: int
    lastChatSentTick: int
    heardSinceRequest: bool


var bedrockCurl = newCurly(1)

proc bedrockRegion(): string =
  ## Returns the configured AWS Region for Bedrock.
  result = getEnv("AWS_REGION").strip()
  if result.len == 0:
    result = getEnv("AWS_DEFAULT_REGION").strip()
  if result.len == 0:
    result = DefaultBedrockRegion

proc bedrockModel(): string =
  ## Returns the configured Bedrock model id.
  result = getEnv("BEDROCK_MODEL").strip()
  if result.len == 0:
    result = DefaultBedrockModel

proc bedrockToken(): string =
  ## Returns the configured Bedrock bearer token.
  result = getEnv("AWS_BEARER_TOKEN_BEDROCK").strip()
  if result.len == 0:
    result = getEnv("BEDROCK_KEY").strip()

proc mockBedrockReply(): string =
  ## Returns a configured mock LLM reply for smoke tests.
  getEnv("TALKING_VILLAGER_MOCK_REPLY").strip()

proc bedrockTimeoutSeconds(): int =
  ## Returns the configured Bedrock request timeout.
  let value = getEnv("BEDROCK_TIMEOUT_SECONDS").strip()
  if value.len == 0:
    return DefaultBedrockTimeoutSeconds
  try:
    max(1, int(parseFloat(value)))
  except ValueError:
    DefaultBedrockTimeoutSeconds

proc bedrockMaxTokens(): int =
  ## Returns the configured maximum Bedrock response tokens.
  let value = getEnv("BEDROCK_MAX_TOKENS").strip()
  if value.len == 0:
    return DefaultBedrockMaxTokens
  try:
    max(32, parseInt(value))
  except ValueError:
    DefaultBedrockMaxTokens

proc bedrockPerformanceLatency(): string =
  ## Returns the optional Bedrock latency performance setting.
  let value = getEnv("BEDROCK_PERFORMANCE_LATENCY").strip().toLowerAscii()
  if value == "standard" or value == "optimized":
    return value

proc requireBedrockConfig() =
  ## Raises when live Bedrock cannot be called.
  if mockBedrockReply().len > 0:
    return
  if bedrockToken().len == 0 and not hasAwsCredentialSignal():
    raise newException(TalkingVillagerError, BedrockNotConfiguredMessage)

proc transientBedrockError(answer: BedrockResult): bool =
  ## Returns true for Bedrock failures worth retrying later.
  let message = answer.error.toLowerAscii()
  if answer.statusCode == 408 or
      answer.statusCode == 429 or
      answer.statusCode == 500 or
      answer.statusCode == 502 or
      answer.statusCode == 503 or
      answer.statusCode == 504:
    return true
  if message.contains("timeout") or
      message.contains("timed out") or
      message.contains("timeout was reached") or
      message.contains("operation timed out") or
      message.contains("temporarily unavailable") or
      message.contains("service unavailable") or
      message.contains("throttl") or
      message.contains("rate exceeded") or
      message.contains("too many requests") or
      message.contains("connection reset") or
      message.contains("couldn't connect") or
      message.contains("could not connect"):
    return true

proc permanentBedrockError(answer: BedrockResult): bool =
  ## Returns true for Bedrock failures that should stop the bot: the
  ## request itself is rejected (bad model id, bad credentials, prompt too
  ## long), so retrying can only fail the same way. Anything else, including
  ## a 200 whose body we could not use, is worth playing through.
  if answer.transientBedrockError():
    return false
  if answer.statusCode == 200:
    return false
  if answer.statusCode == 400 or
      answer.statusCode == 401 or
      answer.statusCode == 403 or
      answer.statusCode == 404:
    return true
  let message = answer.error.toLowerAscii()
  if message.contains("too many tokens") or
      message.contains("input is too long") or
      message.contains("context length") or
      message.contains("maximum context") or
      message.contains("token limit") or
      message.contains("validationexception") or
      message.contains("resourcenotfoundexception") or
      message.contains("accessdenied") or
      message.contains("unauthorized") or
      message.contains("forbidden") or
      message.contains("not authorized"):
    return true

proc bedrockHost(): string =
  ## Returns the Bedrock Runtime host for the selected Region.
  "bedrock-runtime." & bedrockRegion() & ".amazonaws.com"

proc bedrockPath(): string =
  ## Returns the REST path for a Bedrock InvokeModel request.
  "/model/" & bedrockModel().awsUriEncode() & "/invoke"

proc bedrockUrl(): string =
  ## Builds the Bedrock Runtime InvokeModel URL.
  let sidecar = sidecarEndpoint()
  if sidecar.len > 0:
    return sidecar.joinUrl(bedrockPath())
  "https://" & bedrockHost() & bedrockPath()

proc bedrockHeaders(body: string): HttpHeaders =
  ## Builds one Bedrock HTTP header set for the signed request body.
  if hasSidecarEndpoint():
    result["Accept"] = "application/json"
    result["Content-Type"] = "application/json"
  elif bedrockToken().len > 0:
    result["Authorization"] = "Bearer " & bedrockToken()
    result["Accept"] = "application/json"
    result["Content-Type"] = "application/json"
  else:
    for (key, value) in signedBedrockHeaders(
      body, bedrockHost(), bedrockPath(), bedrockRegion()
    ):
      result[key] = value
  let latency = bedrockPerformanceLatency()
  if latency.len > 0:
    result["X-Amzn-Bedrock-PerformanceConfig-Latency"] = latency

proc bedrockBody(messages: openArray[ConversationMessage]): string =
  ## Builds one Anthropic Messages request body for Bedrock.
  ## Consecutive same-role messages are joined because the Anthropic
  ## Messages API requires user and assistant turns to alternate.
  var
    systemPrompt = ""
    chatMessages = newJArray()
  for message in messages:
    if message.role == "system":
      systemPrompt = message.content
      continue
    if chatMessages.elems.len == 0 and message.role == "assistant":
      chatMessages.add(%*{
        "role": "user",
        "content": "(The day begins.)"
      })
    if chatMessages.elems.len > 0 and
        chatMessages.elems[^1]["role"].getStr() == message.role:
      chatMessages.elems[^1]["content"] = %(
        chatMessages.elems[^1]["content"].getStr() & "\n" & message.content
      )
    else:
      chatMessages.add(%*{
        "role": message.role,
        "content": message.content
      })
  let body = %*{
    "anthropic_version": BedrockVersion,
    "max_tokens": bedrockMaxTokens(),
    "temperature": BedrockTemperature,
    "system": systemPrompt,
    "messages": chatMessages
  }
  if not hasSidecarEndpoint():
    body["requestMetadata"] = bedrockRequestMetadata("talking_villager")
  $body

proc parseBedrockReply(body: string): string =
  ## Extracts output text from one Bedrock response body.
  let data = parseJson(body)
  for part in data["content"]:
    if part{"type"}.getStr() == "text":
      result.add(part["text"].getStr())

proc startTalkToBedrock(
  messages: openArray[ConversationMessage],
  tag: string
): bool =
  ## Starts a non-blocking Bedrock request.
  if bedrockToken().len == 0 and not hasAwsCredentialSignal():
    return false
  let body = bedrockBody(messages)
  bedrockCurl.startRequest(
    "POST",
    bedrockUrl(),
    bedrockHeaders(body),
    body,
    bedrockTimeoutSeconds(),
    tag
  )
  return true

proc pollTalkToBedrock(): BedrockResult =
  ## Polls for one completed Bedrock response.
  let answer = bedrockCurl.pollForResponse()
  if answer.isNone:
    return BedrockResult(done: false)
  result.done = true
  result.tag = answer.get.response.request.tag
  if answer.get.error.len > 0:
    result.error = answer.get.error
    return
  let response = answer.get.response
  result.statusCode = response.code
  if response.code != 200:
    result.error = response.body
    return
  try:
    result.reply = response.body.parseBedrockReply()
  except CatchableError as e:
    result.error = e.msg
    return
  if result.reply.len == 0:
    result.error = "Bedrock response did not include text."
    return
  result.ok = true

proc repoDir(): string =
  ## Returns the Heartleaf repository directory.
  currentSourcePath().parentDir().parentDir().parentDir()

proc loadSoulInstructions(bot: Bot, name: string): string =
  ## Builds the full system prompt for one player name.
  let cleanName =
    if name.strip().len > 0:
      name.strip()
    else:
      "a Heartleaf gnome"
  if bot.soulTemplate.contains("{name}"):
    return bot.soulTemplate.replace("{name}", cleanName)
  "Your name is " & cleanName & ".\n\n" & bot.soulTemplate

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

proc recordChatLine(bot: Bot, role, speaker, text: string) =
  ## Appends one heard or spoken chat line to the conversation history.
  bot.chatHistory.add(ConversationMessage(
    role: role,
    content: speaker & ": " & text
  ))

proc selfNames(bot: Bot): seq[string] =
  ## Returns the names this bot goes by, for stripping self labels.
  if bot.playerName.len > 0:
    result.add(bot.playerName)
  if bot.name.len > 0 and bot.name != bot.playerName:
    result.add(bot.name)

proc recordOwnChat(bot: Bot, text: string) =
  ## Records one chat message this bot said out loud. Own turns are
  ## stored as bare text: the soul tells the model that its earlier turns
  ## are what it said out loud, and a "Name:" label here is exactly what
  ## the model would imitate in its next line.
  bot.chatHistory.add(ConversationMessage(role: "assistant", content: text))

proc scanHeardChats(bot: Bot) =
  ## Records newly visible chat bubbles from other players.
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
    bot.heardChats[playerIndex] = text
    if text.len == 0 or playerIndex == bot.selfIndex:
      continue
    let speaker = bot.visiblePlayerName(playerIndex)
    if speaker.len == 0 or speaker == bot.playerName:
      continue
    bot.recordChatLine("user", speaker, text)
    bot.heardSinceRequest = true

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

proc dayNumber(bot: Bot): int =
  ## Returns the one-based day of the current game.
  bot.dayIndex + 1


proc clockAnnouncement(minutes: int): string =
  ## Returns one hourly clock line for the conversation history.
  let clock = minutes.clockName()
  if minutes < DinnerMinutes:
    let hours = (DinnerMinutes - minutes) div 60
    if hours <= 0:
      "It is " & clock & ". Dinner starts within the hour! Be INSIDE " &
        "your dinner house before it is served at 6:00pm - if you are " &
        "outside when it is served you miss dinner entirely."
    elif hours == 1:
      "It is " & clock & " (1 hour till dinner). Settle on a dinner " &
        "house now; you must be inside it before 6:00pm."
    else:
      "It is " & clock & " (" & $hours & " hours till dinner)."
  elif minutes < DinnerMinutes + 60:
    "It is " & clock & ". Dinner was served at 6:00pm sharp - anyone " &
      "outside then missed it. The evening is for gathering food " &
      "for tomorrow."
  elif minutes < DayEndMinutes:
    let hours = (DayEndMinutes - minutes) div 60
    if hours <= 1:
      "It is " & clock & " (night falls within the hour)."
    else:
      "It is " & clock & " (" & $hours & " hours till night time)."
  else:
    "It is " & clock & ". It is night time."

proc maybeRecordClock(bot: Bot) =
  ## Records one clock line in the conversation every game hour.
  if bot.minutes < 0:
    return
  let hour = bot.minutes div 60
  if hour == bot.lastClockHour:
    return
  bot.lastClockHour = hour
  bot.chatHistory.add(ConversationMessage(
    role: "user",
    content: "Clock: " & bot.minutes.clockAnnouncement()
  ))

proc resetGardenPlan(bot: Bot) =
  ## Resets the static garden checklist for a new day.
  inc bot.dayIndex
  bot.gardenChecked = newSeq[bool](bot.resources.gardens.len)
  bot.currentGarden = -1
  bot.llmWaiting = false
  bot.lastLlmError = ""
  bot.pendingChat = ""
  bot.hasPendingChat = false
  bot.path.setLen(0)
  bot.goal = Goal(kind: GoalIdle, screenKind: UnknownScreen)

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
  bot.soulInstructions = bot.loadSoulInstructions(name)
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

proc inventoryCountAt(bot: Bot, foodIndex: int): int =
  ## Returns how many of one named food this bot is carrying.
  let countObjectId = InventoryCountObjectBase + foodIndex
  if countObjectId < bot.objects.len and
      bot.objects[countObjectId].present:
    let sprite = bot.spriteInfo(bot.objects[countObjectId].spriteId)
    if sprite != nil:
      return sprite.label.parseInventoryCount()
  let iconObjectId = InventoryObjectBase + foodIndex
  if iconObjectId < bot.objects.len and bot.objects[iconObjectId].present:
    return 1

proc inventoryTotal(bot: Bot): int =
  ## Returns how many food items this bot is carrying.
  for foodIndex in 0 ..< FoodVeggieSlots:
    result += bot.inventoryCountAt(foodIndex)

proc collectedFoodsText(bot: Bot): string =
  ## Returns named foods in this bot's inventory for the LLM prompt.
  for foodIndex in 0 ..< FoodVeggieSlots:
    let count = bot.inventoryCountAt(foodIndex)
    if count <= 0:
      continue
    if result.len > 0:
      result.add(", ")
    result.add(foodIndex.foodName())
    if count > 1:
      result.add(" x" & $count)
  if result.len == 0:
    result = "none"

proc lookingForFoodsText(bot: Bot): string =
  ## Returns named foods this bot has not eaten yet this game.
  if LookingForObjectId < bot.objects.len and
      bot.objects[LookingForObjectId].present:
    let sprite = bot.spriteInfo(bot.objects[LookingForObjectId].spriteId)
    if sprite != nil and sprite.label.startsWith(LookingForLabelPrefix):
      let rest = sprite.label[LookingForLabelPrefix.len .. ^1].strip()
      if rest.len > 0:
        return rest
  FoodNames.join(", ")

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

proc initBot(name: string, slot: int, soul: string): Bot =
  ## Builds a new talking Villager bot state.
  result = Bot()
  result.soulTemplate = soul.strip()
  result.name =
    if name.len > 0:
      name
    else:
      DefaultName
  result.slot = slot
  result.llmPacer = initLlmPacer(
    slot * 7919 + int(epochTime() * 1000) mod 100_000
  )
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
  result.soulInstructions =
    if result.playerName.len > 0:
      result.loadSoulInstructions(result.playerName)
    else:
      result.loadSoulInstructions(DefaultName)
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
  result.llmWaiting = false
  result.dayIndex = 0
  result.gardenChecked = newSeq[bool](result.resources.gardens.len)
  result.lastClockHour = -1

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

proc visiblePlayersText(bot: Bot): string =
  ## Returns visible player facts for the LLM prompt.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let
      playerIndex = objectId - PlayerObjectBase
      name = bot.visiblePlayerName(playerIndex)
    if name.len == 0 or playerIndex == bot.selfIndex or
        name == bot.playerName:
      continue
    if result.len > 0:
      result.add("\n")
    let
      footX = bot.objectFootX(objectState)
      footY = bot.objectFootY(objectState)
      distance = distanceSquared(
        bot.playerFootX(),
        bot.playerFootY(),
        footX,
        footY
      )
      chat = bot.visibleChatText(playerIndex)
    result.add(
      "- " & name &
      " homeOwner=" & name &
      " homeHouseIndex=" & $(name.houseIndexForPlayerName() + 1) &
      " x=" & $footX &
      " y=" & $footY &
      " distanceSquared=" & $distance
    )
    if chat.len > 0:
      result.add(" says=\"" & chat & "\"")
  if result.len == 0:
    result = "- none"

proc hostGoal(bot: Bot): Goal =
  ## Returns the deterministic host-always goal for the current clock.
  ## Gather all morning, anchor visibly at the own door before dinner,
  ## sit inside through the 6:00pm tally, then bank food for tomorrow.
  if not bot.localized or bot.navForCurrentMap() == nil:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  if bot.screenKind == OverlayScreen:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  if bot.minutes >= DayEndMinutes:
    return bot.ownHomeGoal()
  if bot.minutes >= EveningGatherMinutes:
    if bot.screenKind == HomeMap:
      return bot.exitGoal()
    let garden = bot.gardenGoal()
    if garden.kind != GoalIdle:
      return garden
    return bot.gatherOwnHouseGoal()
  if bot.minutes >= HostEnterMinutes:
    return bot.ownHomeGoal()
  if bot.minutes >= GatherUntilMinutes:
    if bot.screenKind == HomeMap:
      return bot.exitGoal()
    return bot.gatherOwnHouseGoal()
  if bot.screenKind == HomeMap:
    return bot.exitGoal()
  if bot.screenKind == MainMap:
    let garden = bot.gardenGoal()
    if garden.kind != GoalIdle:
      return garden
    return bot.gatherOwnHouseGoal()
  Goal(kind: GoalIdle, screenKind: bot.screenKind)

proc trimChatHistory(bot: Bot) =
  ## Keeps the conversation transcript bounded for prompt size.
  if bot.chatHistory.len > ChatHistoryLimit:
    bot.chatHistory = bot.chatHistory[^ChatHistoryLimit .. ^1]

proc chatUserPrompt(bot: Bot): string =
  ## Builds one current-state prompt asking for a single chat line.
  let phase =
    if bot.minutes >= DinnerMinutes:
      "dinner is being served at your table"
    elif bot.minutes >= HostEnterMinutes:
      "you are heading inside; guests must come in now"
    elif bot.minutes >= GatherUntilMinutes:
      "you are at your door welcoming guests for 6pm"
    else:
      "you are gathering food and drumming up guests"
  result =
    "Current Heartleaf state:\n" &
    "clock=" & bot.minutes.clockName() & "\n" &
    "day=" & $bot.dayNumber & "\n" &
    "yourName=" & bot.playerName & "\n" &
    "yourHouse=" & bot.playerName & "'s house\n" &
    "yourFoodTotal=" & $bot.inventoryTotal() & "\n" &
    "foodCollected=" & bot.collectedFoodsText() & "\n" &
    "foodLookingFor=" & bot.lookingForFoodsText() & "\n" &
    "foodTalk=name foods from foodCollected when pitching dinner; " &
    "if someone asks for a food you hold, say you have it and invite " &
    "them to your party; never say food numbers\n" &
    "phase=" & phase & "\n" &
    "visiblePlayers:\n" & bot.visiblePlayersText() & "\n" &
    "Say one chat line out loud now (max " & $ChatMaxChars &
    " characters). Return only the line, no quotes."

proc applyChatReply(bot: Bot, reply: string) =
  ## Stores one LLM chat line for sending on the next frame.
  var line = reply.strip()
  let newlineAt = line.find('\n')
  if newlineAt >= 0:
    line = line[0 ..< newlineAt]
  line = line.strip(chars = {'"', ' ', '\t'})
    .stripSelfPrefix(bot.selfNames())
    .strip(chars = {'"', ' ', '\t'})
    .cleanDecisionText()
  if line.len == 0:
    return
  bot.pendingChat = line
  bot.hasPendingChat = true

proc mockChatLine(bot: Bot): string =
  ## Returns a deterministic chat line for offline mock testing.
  let mock = mockBedrockReply()
  if mock.len > 0 and mock[0] != '{':
    return mock.cleanDecisionText()
  ("Dinner at my house at 6! I have plenty.").cleanDecisionText()

proc startChatRequest(bot: Bot) =
  ## Starts one non-blocking Bedrock request for a chat line.
  bot.lastChatRequestTick = bot.frameTick
  bot.heardSinceRequest = false
  if mockBedrockReply().len > 0:
    bot.applyChatReply(bot.mockChatLine())
    return
  inc bot.llmSerial
  bot.llmTag = "chat-" & $bot.llmSerial
  bot.trimChatHistory()
  var messages = @[
    ConversationMessage(role: "system", content: bot.soulInstructions)
  ]
  for message in bot.chatHistory:
    messages.add(message)
  messages.add(
    ConversationMessage(role: "user", content: bot.chatUserPrompt())
  )
  var started = false
  try:
    started = startTalkToBedrock(messages, bot.llmTag)
  except CatchableError as e:
    bot.lastLlmError = e.msg
    if BedrockResult(done: true, error: e.msg).transientBedrockError():
      let waitTicks = bot.llmPacer.noteTransientError(bot.frameTick)
      bot.log("llm chat start error " & e.msg & ", backing off " &
        $(waitTicks div 24) & "s")
    else:
      bot.log("llm chat start error " & e.msg)
    return
  if not started:
    raise newException(TalkingVillagerError, BedrockNotConfiguredMessage)
  bot.llmWaiting = true
  bot.llmPacer.noteRequest(bot.frameTick)

proc pollChatReply(bot: Bot) =
  ## Polls and applies one completed chat request.
  if not bot.llmWaiting:
    return
  let answer = pollTalkToBedrock()
  if not answer.done:
    return
  if answer.tag != bot.llmTag:
    return
  bot.llmWaiting = false
  if answer.ok:
    bot.llmPacer.noteSuccess()
    bot.applyChatReply(answer.reply)
    return
  bot.lastLlmError = answer.error
  bot.log("llm chat error " & answer.error)
  if answer.permanentBedrockError():
    raise newException(
      TalkingVillagerError,
      "Bedrock request failed: " & answer.error
    )
  if answer.transientBedrockError():
    let waitTicks = bot.llmPacer.noteTransientError(bot.frameTick)
    bot.log("llm chat transient error, backing off " &
      $(waitTicks div 24) & "s")

proc shouldRequestChat(bot: Bot): bool =
  ## Returns true when the bot should ask the LLM for a fresh line.
  if bot.llmWaiting or bot.hasPendingChat:
    return false
  if not bot.llmPacer.canRequest(bot.frameTick):
    return false
  if bot.minutes >= DayEndMinutes:
    return false
  if bot.visibleOtherPlayerCount() == 0:
    return false
  let sinceRequest = bot.frameTick - bot.lastChatRequestTick
  if bot.heardSinceRequest and sinceRequest >= ChatReplyIntervalTicks:
    return true
  sinceRequest >= ChatIntervalTicks

proc maybeSendPendingChat(bot: Bot, ws: WebSocket) =
  ## Sends one queued chat line when someone can hear it.
  if not bot.hasPendingChat:
    return
  if bot.screenKind == OverlayScreen:
    return
  if bot.visibleOtherPlayerCount() == 0:
    return
  ws.send(blobFromChat(bot.pendingChat), BinaryMessage)
  bot.recordOwnChat(bot.pendingChat)
  bot.trimChatHistory()
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
  bot.maybeRecordClock()
  if not bot.localized:
    bot.desiredMask = 0
    bot.hasTarget = false
    return 0
  # Chat runs in the background; movement never waits on the LLM.
  bot.pollChatReply()
  if bot.shouldRequestChat():
    bot.startChatRequest()
  let goal = bot.hostGoal()
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
  soul: string,
  exitOnDisconnect: bool
) =
  ## Connects the talking Villager bot to a Heartleaf sprite player endpoint.
  let connectUrl =
    if url.len > 0:
      url
    else:
      playerUrl(host, port, name, token, slot)
  var bot = initBot(name, slot, soul)
  try:
    requireBedrockConfig()
  except TalkingVillagerError as e:
    echo bot.name, " fatal: ", e.msg
    quit(1)
  ## Hosted runs (exitOnDisconnect) keep reconnecting through mid-game
  ## drops and only exit once the server has been unreachable for
  ## ReconnectGiveUpSeconds, which is what the end of the game looks like.
  var hadConnection = false
  var disconnectedAt = 0.0
  while true:
    try:
      let ws = newWebSocket(connectUrl)
      echo bot.name, " connected to ", connectUrl
      hadConnection = true
      disconnectedAt = 0.0
      bot.lastMask = 0xff'u8
      while true:
        if not ws.receiveUpdates(bot):
          continue
        let nextMask = bot.decideNextMask(ws)
        bot.maybeSendPendingChat(ws)
        if nextMask != bot.lastMask:
          ws.send(blobFromMask(nextMask), BinaryMessage)
          bot.lastMask = nextMask
    except TalkingVillagerError as e:
      echo bot.name, " fatal: ", e.msg
      quit(1)
    except CatchableError as e:
      echo bot.name, " reconnecting: ", e.msg
      if exitOnDisconnect and hadConnection:
        if disconnectedAt == 0.0:
          disconnectedAt = epochTime()
        elif epochTime() - disconnectedAt > ReconnectGiveUpSeconds:
          echo bot.name, " server gone for ", ReconnectGiveUpSeconds,
            "s, exiting"
          break
      sleep(ReconnectDelayMs)

proc hostVillagerMain*(defaultName = DefaultName, soul: string) =
  ## Parses bot CLI options and runs one talking Villager bot.
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
  runBot(address, port, name, token, slot, url, soul, url.len > 0)

const SoulMarkdown = staticRead("soul.md")

when isMainModule:
  hostVillagerMain(DefaultName, SoulMarkdown)
