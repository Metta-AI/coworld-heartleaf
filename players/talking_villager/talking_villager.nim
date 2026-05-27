import
  std/[algorithm, heapqueue, json, options, os, parseopt, strutils],
  curly, supersnappy, whisky,
  heartleaf/protocol, heartleaf/resources,
  decisions

when defined(gui):
  import
    pixie, silky, vmath, windy

const
  BedrockVersion = "bedrock-2023-05-31"
  DefaultBedrockRegion = "us-east-1"
  DefaultBedrockModel = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  DefaultBedrockTimeoutSeconds = 30
  DefaultBedrockMaxTokens = 192
  BedrockTemperature = 0.2
  ViewportWidth = 320
  ViewportHeight = 200
  GnomeSpriteSize = 32
  FoodSpriteSize = 32
  FoodVeggieSlots = 24
  PlayerBoxWidth = 14
  PlayerBoxHeight = 8
  PlayerBoxOffsetX = 9
  PlayerBoxOffsetY = 22
  NavPointOffsetX = PlayerBoxOffsetX + PlayerBoxWidth div 2
  NavPointOffsetY = PlayerBoxOffsetY + PlayerBoxHeight div 2
  FootHalfWidth = PlayerBoxWidth div 2
  FootHalfHeight = PlayerBoxHeight div 2
  FootMinX = FootHalfWidth
  FootMinY = FootHalfHeight
  CollectActionRadius = 32
  GreetingRadius = 180
  PersonStandRadius = 30
  NavStep = 2
  PathArrivePixels = 3
  PathRejoinPixels = 8
  MoveDeadZonePixels = 1
  PathLookaheadPixels = 4
  StuckLookaheadPixels = 10
  StuckLookaheadTicks = 18
  RepathStuckTicks = 48
  MaxDrainMessages = 256
  DefaultName = "talking_villager"
  UnknownHouse = -1
  HouseCount = 9
  DecisionRetryTicks = 24
  DecisionStuckTicks = RepathStuckTicks * 2
  HighFoodForInvites = 6
  DoorGatherSlots = 5
  DoorGatherSpacing = 18
  DayStartMinutes = 8 * 60
  HostPrepMinutes = 15 * 60
  InviteStartMinutes = 16 * 60
  HouseEnterMinutes = 17 * 60
  DinnerMinutes = 18 * 60
  PartyLeaveMinutes = 20 * 60
  DayEndMinutes = 22 * 60
  LatePartySearchMinutes = 16 * 60
  MaxHostWaitMinutes = 90
  StrongHostFood = 12
  MediumHostFood = 6
  LowHostFood = 2
  HouseGatherMaxRadius = 96
  MorningIdentityUntilMinutes = 9 * 60
  MorningIdentityRadius = 140
  BottomObjectId = 1
  PlayerObjectBase = 1000
  NameObjectBase = 2000
  ChatObjectBase = 3000
  GardenObjectBase = 4000
  InventoryObjectBase = 5000
  InventoryCountObjectBase = 6000
  ClockObjectBase = 7000
  ScoreObjectBase = 7100
  PlayerNames = [
    "Ivan",
    "Anton",
    "Yura",
    "Sasha",
    "Maxim",
    "Nikita",
    "Vova",
    "Dima",
    "Egor"
  ]

when defined(gui):
  const
    ViewerWindowWidth = 1480
    ViewerWindowHeight = 900
    ViewerMargin = 16.0'f
    ViewerFrameScale = 2.0'f
    ViewerMapWidth = 720.0'f
    ViewerMapHeight = 480.0'f
    ViewerBackground = rgbx(17, 20, 24, 255)
    ViewerPanel = rgbx(31, 35, 42, 255)
    ViewerPanelAlt = rgbx(24, 28, 34, 255)
    ViewerText = rgbx(232, 237, 226, 255)
    ViewerMutedText = rgbx(152, 164, 150, 255)
    ViewerWall = rgbx(78, 58, 70, 255)
    ViewerWalk = rgbx(48, 72, 57, 255)
    ViewerViewport = rgbx(143, 197, 255, 190)
    ViewerPath = rgbx(117, 219, 255, 235)
    ViewerGoal = rgbx(255, 121, 104, 255)
    ViewerTarget = rgbx(255, 221, 102, 255)
    ViewerGarden = rgbx(108, 214, 117, 255)
    ViewerHouse = rgbx(214, 173, 93, 255)
    ViewerPlayer = rgbx(120, 255, 176, 255)
    ViewerOther = rgbx(105, 169, 255, 255)
    ViewerExit = rgbx(205, 130, 255, 255)
    ViewerInventoryHeight = 64.0'f
    ViewerInventoryGap = 8.0'f
    ViewerInventoryScale = 1.0'f

type
  MapKind = enum
    MapUnknown
    MapMain
    MapHome
    MapOverlay

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

  Rect = object
    x, y, w, h: int

  Point = object
    x, y: int

  Goal = object
    kind: GoalKind
    mapKind: MapKind
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

  NavMap = ref object
    width, height: int
    cols, rows: int
    walk: seq[bool]
    canStand: seq[bool]

  Resources = ref object
    gardens: seq[Rect]
    houses: array[9, Rect]
    houseValid: array[9, bool]
    exit: Rect
    hasExit: bool

  PathNode = object
    priority: int
    index: int

  DrawItem = object
    layer, z, y, id: int

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
    soulInstructions: string
    slot: int
    homeIndex: int
    sprites: seq[SpriteInfo]
    objects: seq[ObjectState]
    resources: Resources
    mainNav: NavMap
    homeNav: NavMap
    mapKind: MapKind
    previousMapKind: MapKind
    currentHouse: int
    pendingHouse: int
    cameraX, cameraY: int
    localized: bool
    selfIndex: int
    selfX, selfY: int
    previousX, previousY: int
    stuckTicks: int
    minutes: int
    lastMask: uint8
    attackCooldown: int
    lastCollectTick: int
    goal: Goal
    path: seq[Point]
    gardenChecked: seq[bool]
    greetedNames: seq[string]
    lastGreetingTick: int
    currentGarden: int
    partyHouse: int
    searchHouse: int
    hostUntilMinutes: int
    hostCommitted: bool
    dayIndex: int
    frameTick: int
    desiredMask: uint8
    target: Point
    hasTarget: bool
    decodeVisualSprites: bool
    decision: LlmDecision
    hasDecision: bool
    decisionChatSent: bool
    decisionStartedTick: int
    decisionState: string
    decisionFoodBand: int
    decisionTimePhase: int
    decisionChatSignature: string
    decisionCrowdSignature: string
    llmWaiting: bool
    llmTag: string
    llmSerial: int
    lastLlmError: string
    committedPartyHouse: int

when defined(gui):
  type
    ViewerApp = ref object
      window: Window
      silky: Silky
      contentScale: float32
else:
  type
    ViewerApp = ref object

proc `<`(a, b: PathNode): bool =
  ## Orders A-star queue nodes by priority and index.
  if a.priority == b.priority:
    return a.index < b.index
  a.priority < b.priority

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
  if bedrockToken().len == 0:
    raise newException(
      TalkingVillagerError,
      "AWS_BEARER_TOKEN_BEDROCK or BEDROCK_KEY is not set."
    )

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
  ## Returns true for Bedrock failures that should stop the bot.
  if answer.transientBedrockError():
    return false
  let message = answer.error.toLowerAscii()
  if answer.statusCode == 400 or
      answer.statusCode == 401 or
      answer.statusCode == 403 or
      answer.statusCode == 404:
    return true
  if message.contains("too many tokens") or
      message.contains("input is too long") or
      message.contains("context length") or
      message.contains("maximum context") or
      message.contains("token limit") or
      message.contains("validationexception") or
      message.contains("accessdenied") or
      message.contains("unauthorized") or
      message.contains("forbidden") or
      message.contains("not authorized") or
      message.contains("not supported") or
      message.contains("model") or
      message.contains("malformed") or
      message.contains("invalid"):
    return true

proc bedrockUrl(): string =
  ## Builds the Bedrock Runtime InvokeModel URL.
  "https://bedrock-runtime." & bedrockRegion() &
    ".amazonaws.com/model/" & bedrockModel() & "/invoke"

proc bedrockHeaders(): HttpHeaders =
  ## Builds one Bedrock HTTP header set.
  result["Authorization"] = "Bearer " & bedrockToken()
  result["Accept"] = "application/json"
  result["Content-Type"] = "application/json"
  let latency = bedrockPerformanceLatency()
  if latency.len > 0:
    result["X-Amzn-Bedrock-PerformanceConfig-Latency"] = latency

proc bedrockBody(messages: openArray[ConversationMessage]): string =
  ## Builds one Anthropic Messages request body for Bedrock.
  var
    systemPrompt = ""
    chatMessages = newJArray()
  for message in messages:
    if message.role == "system":
      systemPrompt = message.content
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
  if bedrockToken().len == 0:
    return false
  bedrockCurl.startRequest(
    "POST",
    bedrockUrl(),
    bedrockHeaders(),
    bedrockBody(messages),
    bedrockTimeoutSeconds(),
    tag
  )
  true

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

proc soulDir(): string =
  ## Returns the talking Villager soul instruction directory.
  currentSourcePath().parentDir() / "souls"

proc soulFileName(name: string): string =
  ## Returns the markdown soul filename for one player name.
  name.strip().toLowerAscii() & ".md"

proc defaultSoulInstructions(name: string): string =
  ## Returns fallback soul instructions for unknown player names.
  "You are " & name & ". Speak in short friendly phrases. " &
    "Gather food early, invite when you have food, attend parties when low."

proc loadSoulInstructions(name: string): string =
  ## Loads the markdown soul instructions for one player name.
  let cleanName = name.strip()
  if cleanName.len == 0:
    return defaultSoulInstructions("a Heartleaf gnome")
  let path = soulDir() / cleanName.soulFileName()
  if fileExists(path):
    return readFile(path).strip()
  let defaultPath = soulDir() / "default.md"
  if fileExists(defaultPath):
    return readFile(defaultPath).strip()
  defaultSoulInstructions(cleanName)

when defined(gui):
  proc atlasPath(): string =
    ## Returns the Silky atlas path used by the debug viewer.
    let localPath = repoDir() / "dist" / "atlas.png"
    if fileExists(localPath):
      return localPath
    repoDir() / ".." / "bitworld" / "clients" / "dist" / "atlas.png"

  proc displayScale(window: Window): float32 =
    ## Returns a safe content scale for the window's current display.
    result = window.contentScale
    if result <= 0.0'f:
      result = 1.0'f

  proc scaledWindowSize(size: IVec2, scale: float32): IVec2 =
    ## Converts a logical window size to physical pixels.
    (size.vec2 * scale).ivec2
else:
  proc initViewerApp(): ViewerApp =
    ## Returns an empty viewer for headless builds.
    nil

  proc viewerOpen(viewer: ViewerApp): bool =
    ## Returns true for headless builds without a viewer.
    discard viewer
    true

  proc pumpViewer(
    viewer: ViewerApp,
    bot: Bot,
    connected: bool,
    url: string
  ) =
    ## Skips viewer updates in headless builds.
    discard viewer
    discard bot
    discard connected
    discard url

proc toRect(rect: ResourceRect): Rect =
  ## Converts one resource rectangle to the bot rectangle type.
  Rect(x: rect.x, y: rect.y, w: rect.w, h: rect.h)

proc rectName(rect: ResourceRect): string =
  ## Returns the normalized resource rectangle name.
  rect.name.strip().toLowerAscii()

proc houseIndex(name: string): int =
  ## Returns the zero-based house index in one resource name.
  if not name.startsWith("house"):
    return -1
  try:
    result = parseInt(name["house".len .. ^1]) - 1
  except ValueError:
    result = -1
  if result < 0 or result >= 9:
    return -1

proc playerNameForHouse(houseIndex: int): string =
  ## Returns the fixed in-game player name for one house.
  if houseIndex >= 0 and houseIndex < PlayerNames.len:
    return PlayerNames[houseIndex]
  ""

proc houseIndexForPlayerName(name: string): int =
  ## Returns the fixed house index for one in-game player name.
  for i, playerName in PlayerNames:
    if playerName == name:
      return i
  -1

proc loadBotResources(): Resources =
  ## Loads house, garden, and home-exit resource rectangles.
  result = Resources()
  let root = repoDir()
  for rect in loadResourceRects(root / "data" / "map.resource"):
    let name = rect.rectName()
    if name == "garden":
      result.gardens.add(rect.toRect())
    else:
      let index = name.houseIndex()
      if index >= 0:
        result.houses[index] = rect.toRect()
        result.houseValid[index] = true
  for rect in loadResourceRects(root / "data" / "home_map.resource"):
    if rect.rectName() == "exit":
      result.exit = rect.toRect()
      result.hasExit = true

proc contains(rect: Rect, x, y: int): bool =
  ## Returns true when a point is inside one rectangle.
  x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h

proc screenRectVisible(x, y, w, h: int): bool =
  ## Returns true when one screen-space rectangle overlaps the viewport.
  x < ViewportWidth and y < ViewportHeight and x + w > 0 and y + h > 0

proc center(rect: Rect): Point =
  ## Returns the center point for one rectangle.
  Point(x: rect.x + rect.w div 2, y: rect.y + rect.h div 2)

proc collisionRectFromFoot(x, y: int): Rect =
  ## Returns the server collision rectangle at one foot-center position.
  Rect(
    x: x - FootHalfWidth,
    y: y - FootHalfHeight,
    w: PlayerBoxWidth,
    h: PlayerBoxHeight
  )

proc navPointX(x: int): int =
  ## Converts a sprite X coordinate to its foot-center X coordinate.
  x + NavPointOffsetX

proc navPointY(y: int): int =
  ## Converts a sprite Y coordinate to its foot-center Y coordinate.
  y + NavPointOffsetY

proc rectDistanceSquared(a, b: Rect): int =
  ## Returns the squared distance between two rectangles.
  let
    dx =
      if a.x + a.w < b.x:
        b.x - (a.x + a.w)
      elif b.x + b.w < a.x:
        a.x - (b.x + b.w)
      else:
        0
    dy =
      if a.y + a.h < b.y:
        b.y - (a.y + a.h)
      elif b.y + b.h < a.y:
        a.y - (b.y + b.h)
      else:
        0
  dx * dx + dy * dy

proc playerDistanceSquared(bot: Bot, rect: Rect): int =
  ## Returns the squared distance from the bot to one rectangle.
  collisionRectFromFoot(
    bot.selfX.navPointX(),
    bot.selfY.navPointY()
  ).rectDistanceSquared(rect)

proc distanceSquared(ax, ay, bx, by: int): int =
  ## Returns the squared distance between two points.
  let
    dx = ax - bx
    dy = ay - by
  dx * dx + dy * dy

proc playerFootX(bot: Bot): int =
  ## Returns the bot foot-center X coordinate.
  bot.selfX.navPointX()

proc playerFootY(bot: Bot): int =
  ## Returns the bot foot-center Y coordinate.
  bot.selfY.navPointY()

proc objectWorldX(bot: Bot, objectState: ObjectState): int =
  ## Converts one object X coordinate to current-map coordinates.
  objectState.x + bot.cameraX

proc objectWorldY(bot: Bot, objectState: ObjectState): int =
  ## Converts one object Y coordinate to current-map coordinates.
  objectState.y + bot.cameraY

proc objectFootX(bot: Bot, objectState: ObjectState): int =
  ## Converts one object X coordinate to current-map foot center.
  bot.objectWorldX(objectState).navPointX()

proc objectFootY(bot: Bot, objectState: ObjectState): int =
  ## Converts one object Y coordinate to current-map foot center.
  bot.objectWorldY(objectState).navPointY()

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
  if sprite == nil or not sprite.label.startsWith("name "):
    return
  sprite.label["name ".len .. ^1]

proc visiblePlayerIndexByName(bot: Bot, name: string): int =
  ## Returns the visible player index for one fixed player name.
  result = -1
  let target = name.strip()
  if target.len == 0:
    return
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if bot.visiblePlayerName(playerIndex) == target:
      return playerIndex

proc visibleChatText(bot: Bot, playerIndex: int): string =
  ## Returns the visible chat bubble text for one player.
  let objectId = ChatObjectBase + playerIndex
  if objectId < 0 or objectId >= bot.objects.len:
    return
  let objectState = bot.objects[objectId]
  if not objectState.present:
    return
  let sprite = bot.spriteInfo(objectState.spriteId)
  if sprite == nil or not sprite.label.startsWith("chat "):
    return
  sprite.label["chat ".len .. ^1]

proc hasGreeted(bot: Bot, name: string): bool =
  ## Returns true when this bot has greeted a name today.
  for greetedName in bot.greetedNames:
    if greetedName == name:
      return true

proc greetingText(bot: Bot, name: string): string =
  ## Returns one short greeting for a nearby player.
  "Hi " & name

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
  int(cast[int16](value))

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
  if lower == "heartleaf main walkability":
    result.kind = SpriteMainWalk
  elif lower == "heartleaf home walkability":
    result.kind = SpriteHomeWalk
  elif lower.startsWith("heartleaf home bottom"):
    result.kind = SpriteHomeBottom
  elif lower.startsWith("heartleaf bottom"):
    result.kind = SpriteMainBottom
  elif lower == "garden marker":
    result.kind = SpriteGarden
  elif lower.startsWith("gnome "):
    result.kind = SpriteGnome
  elif lower.startsWith("name "):
    result.kind = SpriteName
  elif lower.startsWith("chat "):
    result.kind = SpriteChat
  elif lower.startsWith("clock "):
    result.kind = SpriteClock
    if label.len > "clock ".len:
      result.glyph = label["clock ".len]
    else:
      result.glyph = ' '
  elif lower.startsWith("score ") or lower.startsWith("dinner "):
    result.kind = SpriteOverlay

proc needsPixels(kind: SpriteKind): bool =
  ## Returns true when the bot needs sprite pixels for navigation.
  kind in {SpriteMainWalk, SpriteHomeWalk}

proc shouldDecodePixels(bot: Bot, kind: SpriteKind): bool =
  ## Returns true when a sprite packet should retain decoded RGBA pixels.
  bot.decodeVisualSprites or kind.needsPixels()

proc walkAt(nav: NavMap, x, y: int): bool =
  ## Returns true when one map pixel is walkable.
  if nav == nil or x < 0 or y < 0 or x >= nav.width or y >= nav.height:
    return false
  nav.walk[y * nav.width + x]

proc canOccupy(nav: NavMap, x, y: int): bool =
  ## Returns true when a foot-center position is walkable.
  if nav == nil:
    return false
  let rect = collisionRectFromFoot(x, y)
  if rect.x < 0 or rect.y < 0 or
      rect.x + rect.w > nav.width or
      rect.y + rect.h > nav.height:
    return false
  for py in rect.y ..< rect.y + rect.h:
    for px in rect.x ..< rect.x + rect.w:
      if not nav.walkAt(px, py):
        return false
  true

proc cellIndex(nav: NavMap, col, row: int): int =
  ## Returns one navigation cell index.
  row * nav.cols + col

proc pointForCell(nav: NavMap, index: int): Point =
  ## Returns the foot-center point for one navigation cell.
  let
    col = index mod nav.cols
    row = index div nav.cols
  Point(x: FootMinX + col * NavStep, y: FootMinY + row * NavStep)

proc buildNavMap(sprite: SpriteInfo): NavMap =
  ## Builds a navigation grid from one walkability sprite.
  result = NavMap()
  result.width = sprite.width
  result.height = sprite.height
  result.walk = newSeq[bool](sprite.width * sprite.height)
  for i in 0 ..< result.walk.len:
    result.walk[i] = sprite.pixels[i * 4 + 3] > 0
  let
    maxFootX = max(
      FootMinX,
      sprite.width - (PlayerBoxWidth - FootHalfWidth)
    )
    maxFootY = max(
      FootMinY,
      sprite.height - (PlayerBoxHeight - FootHalfHeight)
    )
  result.cols = max(1, (maxFootX - FootMinX) div NavStep + 1)
  result.rows = max(1, (maxFootY - FootMinY) div NavStep + 1)
  result.canStand = newSeq[bool](result.cols * result.rows)
  for row in 0 ..< result.rows:
    for col in 0 ..< result.cols:
      let point = result.pointForCell(result.cellIndex(col, row))
      result.canStand[result.cellIndex(col, row)] =
        result.canOccupy(point.x, point.y)

proc nearestCell(nav: NavMap, x, y: int): int =
  ## Returns the nearest standable navigation cell to a foot point.
  result = -1
  if nav == nil:
    return
  var bestDistance = high(int)
  for index, canStand in nav.canStand:
    if not canStand:
      continue
    let point = nav.pointForCell(index)
    let distance = distanceSquared(point.x, point.y, x, y)
    if distance < bestDistance:
      bestDistance = distance
      result = index

proc nearestCellInside(nav: NavMap, rect: Rect, x, y: int): int =
  ## Returns the nearest standable cell with foot center in a rectangle.
  result = -1
  if nav == nil:
    return
  var bestDistance = high(int)
  for index, canStand in nav.canStand:
    if not canStand:
      continue
    let point = nav.pointForCell(index)
    if not rect.contains(point.x, point.y):
      continue
    let distance = distanceSquared(point.x, point.y, x, y)
    if distance < bestDistance:
      bestDistance = distance
      result = index

proc nearestCellOutside(
  nav: NavMap,
  rect: Rect,
  desired: Point,
  radius: int
): int =
  ## Returns the nearest standable cell near but outside a rectangle.
  result = -1
  if nav == nil:
    return
  var
    bestDistance = high(int)
    bestHouseDistance = high(int)
  for index, canStand in nav.canStand:
    if not canStand:
      continue
    let point = nav.pointForCell(index)
    if rect.contains(point.x, point.y):
      continue
    let houseDistance =
      collisionRectFromFoot(point.x, point.y).rectDistanceSquared(rect)
    if houseDistance > radius * radius:
      continue
    let distance = distanceSquared(point.x, point.y, desired.x, desired.y)
    if distance < bestDistance or
        (distance == bestDistance and houseDistance < bestHouseDistance):
      bestDistance = distance
      bestHouseDistance = houseDistance
      result = index

proc cellInside(nav: NavMap, index: int, rect: Rect): bool =
  ## Returns true when a cell's foot center is inside one rectangle.
  let point = nav.pointForCell(index)
  rect.contains(point.x, point.y)

proc cellCanReach(nav: NavMap, index: int, rect: Rect, radius: int): bool =
  ## Returns true when a cell's foot box can interact with a rectangle.
  let point = nav.pointForCell(index)
  collisionRectFromFoot(point.x, point.y).rectDistanceSquared(rect) <=
    radius * radius

proc heuristic(nav: NavMap, a, b: int): int =
  ## Returns a Manhattan A-star heuristic between two cells.
  let
    ax = a mod nav.cols
    ay = a div nav.cols
    bx = b mod nav.cols
    by = b div nav.cols
  (abs(ax - bx) + abs(ay - by)) * NavStep

proc heuristic(nav: NavMap, index: int, rect: Rect): int =
  ## Returns a Manhattan A-star heuristic between one cell and rectangle.
  let point = nav.pointForCell(index)
  let
    x = point.x
    y = point.y
  var
    dx = 0
    dy = 0
  if x < rect.x:
    dx = rect.x - x
  elif x >= rect.x + rect.w:
    dx = x - (rect.x + rect.w - 1)
  if y < rect.y:
    dy = rect.y - y
  elif y >= rect.y + rect.h:
    dy = y - (rect.y + rect.h - 1)
  dx + dy

proc diagonalClear(nav: NavMap, current, next: int): bool =
  ## Returns true when one diagonal move does not cut a blocked corner.
  let
    currentCol = current mod nav.cols
    currentRow = current div nav.cols
    nextCol = next mod nav.cols
    nextRow = next div nav.cols
    colOffset = nextCol - currentCol
    rowOffset = nextRow - currentRow
  if abs(colOffset) != 1 or abs(rowOffset) != 1:
    return true
  let
    sideA = current + colOffset
    sideB = current + rowOffset * nav.cols
  sideA >= 0 and sideA < nav.canStand.len and
    sideB >= 0 and sideB < nav.canStand.len and
    nav.canStand[sideA] and nav.canStand[sideB]

proc addNeighbor(
  nav: NavMap,
  queue: var HeapQueue[PathNode],
  cameFrom,
  costs: var seq[int],
  current,
  next,
  goal,
  stepCost: int
) =
  ## Adds one possible path neighbor to the A-star frontier.
  if next < 0 or next >= nav.canStand.len or not nav.canStand[next]:
    return
  if not nav.diagonalClear(current, next):
    return
  let nextCost = costs[current] + stepCost
  if nextCost >= costs[next]:
    return
  costs[next] = nextCost
  cameFrom[next] = current
  queue.push(PathNode(
    priority: nextCost + nav.heuristic(next, goal),
    index: next
  ))

proc addNeighbor(
  nav: NavMap,
  queue: var HeapQueue[PathNode],
  cameFrom,
  costs: var seq[int],
  current,
  next: int,
  rect: Rect,
  stepCost: int
) =
  ## Adds one possible path neighbor toward a target rectangle.
  if next < 0 or next >= nav.canStand.len or not nav.canStand[next]:
    return
  if not nav.diagonalClear(current, next):
    return
  let nextCost = costs[current] + stepCost
  if nextCost >= costs[next]:
    return
  costs[next] = nextCost
  cameFrom[next] = current
  queue.push(PathNode(
    priority: nextCost + nav.heuristic(next, rect),
    index: next
  ))

proc reconstructPath(
  nav: NavMap,
  cameFrom: openArray[int],
  start,
  goal: int
): seq[Point] =
  ## Reconstructs one cell path returned by A-star.
  var
    current = goal
    reversed: seq[Point]
  reversed.add(nav.pointForCell(current))
  while current != start:
    current = cameFrom[current]
    if current < 0:
      return @[]
    reversed.add(nav.pointForCell(current))
  for i in countdown(reversed.high, 0):
    result.add(reversed[i])

proc findPath(nav: NavMap, startX, startY, goalX, goalY: int): seq[Point] =
  ## Finds a grid path between two foot-center positions.
  if nav == nil:
    return
  let
    start = nav.nearestCell(startX, startY)
    goal = nav.nearestCell(goalX, goalY)
  if start < 0 or goal < 0:
    return
  var
    queue: HeapQueue[PathNode]
    cameFrom = newSeq[int](nav.canStand.len)
    costs = newSeq[int](nav.canStand.len)
  for i in 0 ..< cameFrom.len:
    cameFrom[i] = -1
    costs[i] = high(int)
  costs[start] = 0
  queue.push(PathNode(priority: nav.heuristic(start, goal), index: start))
  while queue.len > 0:
    let current = queue.pop().index
    if current == goal:
      break
    let
      col = current mod nav.cols
      row = current div nav.cols
    if col > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - 1,
        goal,
        NavStep
      )
    if col + 1 < nav.cols:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + 1,
        goal,
        NavStep
      )
    if row > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - nav.cols,
        goal,
        NavStep
      )
    if row + 1 < nav.rows:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + nav.cols,
        goal,
        NavStep
      )
    if col > 0 and row > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - nav.cols - 1,
        goal,
        NavStep + 2
      )
    if col + 1 < nav.cols and row > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - nav.cols + 1,
        goal,
        NavStep + 2
      )
    if col > 0 and row + 1 < nav.rows:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + nav.cols - 1,
        goal,
        NavStep + 2
      )
    if col + 1 < nav.cols and row + 1 < nav.rows:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + nav.cols + 1,
        goal,
        NavStep + 2
      )
  if start != goal and cameFrom[goal] < 0:
    return
  nav.reconstructPath(cameFrom, start, goal)

proc findPath(nav: NavMap, startX, startY: int, rect: Rect): seq[Point] =
  ## Finds a grid path to any reachable cell inside one rectangle.
  if nav == nil:
    return
  let start = nav.nearestCell(startX, startY)
  if start < 0:
    return
  if nav.cellInside(start, rect):
    return @[nav.pointForCell(start)]
  var
    queue: HeapQueue[PathNode]
    cameFrom = newSeq[int](nav.canStand.len)
    costs = newSeq[int](nav.canStand.len)
    found = -1
  for i in 0 ..< cameFrom.len:
    cameFrom[i] = -1
    costs[i] = high(int)
  costs[start] = 0
  queue.push(PathNode(priority: nav.heuristic(start, rect), index: start))
  while queue.len > 0:
    let current = queue.pop().index
    if nav.cellInside(current, rect):
      found = current
      break
    let
      col = current mod nav.cols
      row = current div nav.cols
    if col > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - 1,
        rect,
        NavStep
      )
    if col + 1 < nav.cols:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + 1,
        rect,
        NavStep
      )
    if row > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - nav.cols,
        rect,
        NavStep
      )
    if row + 1 < nav.rows:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + nav.cols,
        rect,
        NavStep
      )
    if col > 0 and row > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - nav.cols - 1,
        rect,
        NavStep + 2
      )
    if col + 1 < nav.cols and row > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - nav.cols + 1,
        rect,
        NavStep + 2
      )
    if col > 0 and row + 1 < nav.rows:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + nav.cols - 1,
        rect,
        NavStep + 2
      )
    if col + 1 < nav.cols and row + 1 < nav.rows:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + nav.cols + 1,
        rect,
        NavStep + 2
      )
  if found < 0:
    return
  nav.reconstructPath(cameFrom, start, found)

proc findPathNear(
  nav: NavMap,
  startX,
  startY: int,
  rect: Rect,
  radius: int
): seq[Point] =
  ## Finds a grid path to a cell that can interact with one rectangle.
  if nav == nil:
    return
  let start = nav.nearestCell(startX, startY)
  if start < 0:
    return
  if nav.cellCanReach(start, rect, radius):
    return @[nav.pointForCell(start)]
  var
    queue: HeapQueue[PathNode]
    cameFrom = newSeq[int](nav.canStand.len)
    costs = newSeq[int](nav.canStand.len)
    found = -1
  for i in 0 ..< cameFrom.len:
    cameFrom[i] = -1
    costs[i] = high(int)
  costs[start] = 0
  queue.push(PathNode(priority: nav.heuristic(start, rect), index: start))
  while queue.len > 0:
    let current = queue.pop().index
    if nav.cellCanReach(current, rect, radius):
      found = current
      break
    let
      col = current mod nav.cols
      row = current div nav.cols
    if col > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - 1,
        rect,
        NavStep
      )
    if col + 1 < nav.cols:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + 1,
        rect,
        NavStep
      )
    if row > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - nav.cols,
        rect,
        NavStep
      )
    if row + 1 < nav.rows:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + nav.cols,
        rect,
        NavStep
      )
    if col > 0 and row > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - nav.cols - 1,
        rect,
        NavStep + 2
      )
    if col + 1 < nav.cols and row > 0:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current - nav.cols + 1,
        rect,
        NavStep + 2
      )
    if col > 0 and row + 1 < nav.rows:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + nav.cols - 1,
        rect,
        NavStep + 2
      )
    if col + 1 < nav.cols and row + 1 < nav.rows:
      nav.addNeighbor(
        queue,
        cameFrom,
        costs,
        current,
        current + nav.cols + 1,
        rect,
        NavStep + 2
      )
  if found < 0:
    return
  nav.reconstructPath(cameFrom, start, found)

proc sameGoal(a, b: Goal): bool =
  ## Returns true when two goals are the same navigation target.
  a.kind == b.kind and
    a.mapKind == b.mapKind and
    a.x == b.x and
    a.y == b.y and
    a.houseIndex == b.houseIndex and
    a.gardenIndex == b.gardenIndex and
    a.targetName == b.targetName

proc navForCurrentMap(bot: Bot): NavMap =
  ## Returns the navigation map for the current observed map.
  case bot.mapKind
  of MapMain:
    bot.mainNav
  of MapHome:
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
    bot.mainNav = sprite.buildNavMap()
  of SpriteHomeWalk:
    bot.homeNav = sprite.buildNavMap()
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
      if bot.shouldDecodePixels(classified.kind):
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

proc parseClockMinutes(text: string): int =
  ## Parses one Heartleaf AM/PM clock string into day minutes.
  result = -1
  let parts = strutils.splitWhitespace(text)
  if parts.len == 0:
    return
  let token = parts[^1]
  if token.len < 4:
    return
  let suffix = token[^2 .. ^1].toLowerAscii()
  if suffix != "am" and suffix != "pm":
    return
  let timeParts = token[0 .. ^3].split(':')
  if timeParts.len != 2:
    return
  try:
    var hour = parseInt(timeParts[0])
    let minute = parseInt(timeParts[1])
    if suffix == "pm" and hour < 12:
      hour += 12
    elif suffix == "am" and hour == 12:
      hour = 0
    result = hour * 60 + minute
  except ValueError:
    result = -1

proc clockName(minutes: int): string =
  ## Formats day minutes as one AM/PM clock string.
  let wrapped = ((minutes mod (24 * 60)) + (24 * 60)) mod (24 * 60)
  var hour = wrapped div 60
  let minute = wrapped mod 60
  let suffix =
    if hour >= 12:
      "pm"
    else:
      "am"
  hour = hour mod 12
  if hour == 0:
    hour = 12
  let minuteText =
    if minute < 10:
      "0" & $minute
    else:
      $minute
  $hour & ":" & minuteText & suffix

proc resetGardenPlan(bot: Bot) =
  ## Resets the static garden checklist and greetings for a new day.
  inc bot.dayIndex
  bot.gardenChecked = newSeq[bool](bot.resources.gardens.len)
  bot.greetedNames.setLen(0)
  bot.lastGreetingTick = -1
  bot.currentGarden = -1
  bot.partyHouse = UnknownHouse
  bot.searchHouse = UnknownHouse
  bot.hostUntilMinutes = -1
  bot.hostCommitted = false
  bot.hasDecision = false
  bot.decisionChatSent = false
  bot.llmWaiting = false
  bot.lastLlmError = ""
  bot.committedPartyHouse = UnknownHouse
  bot.path.setLen(0)
  bot.goal = Goal(kind: GoalIdle, mapKind: MapUnknown)

proc updateClock(bot: Bot) =
  ## Updates the bot's current day clock from the UI glyphs.
  let minutes = bot.clockText().parseClockMinutes()
  if minutes >= 0:
    if bot.minutes > minutes:
      bot.resetGardenPlan()
    bot.minutes = minutes

proc updateMapKind(bot: Bot) =
  ## Updates the visible map kind and camera offset.
  bot.previousMapKind = bot.mapKind
  bot.mapKind = MapOverlay
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
    bot.mapKind = MapMain
  of SpriteHomeBottom:
    bot.mapKind = MapHome
  else:
    bot.mapKind = MapUnknown
  bot.cameraX = -bottom.x
  bot.cameraY = -bottom.y
  if bot.mapKind != bot.previousMapKind:
    bot.path.setLen(0)
    if bot.mapKind == MapHome and bot.pendingHouse >= 0:
      bot.currentHouse = bot.pendingHouse
      bot.pendingHouse = UnknownHouse
    elif bot.mapKind == MapMain:
      bot.currentHouse = UnknownHouse

proc findSelfIndexByName(bot: Bot): int =
  ## Returns the player index whose name tag matches this bot.
  result = -1
  if bot.playerName.len == 0:
    return
  let expected = "name " & bot.playerName
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
      objectState.x + NavPointOffsetX,
      objectState.y + NavPointOffsetY,
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
  bot.soulInstructions = name.loadSoulInstructions()
  bot.homeIndex = homeIndex
  bot.currentHouse =
    if bot.mapKind == MapHome:
      homeIndex
    else:
      UnknownHouse
  bot.pendingHouse = UnknownHouse
  bot.partyHouse = UnknownHouse
  bot.searchHouse = UnknownHouse
  bot.committedPartyHouse = UnknownHouse
  bot.hasDecision = false
  bot.currentGarden = -1
  bot.path.setLen(0)
  bot.goal = Goal(kind: GoalIdle, mapKind: MapUnknown)

proc nearestMorningHome(bot: Bot): int =
  ## Returns the nearest home inferred from the morning world spawn.
  result = UnknownHouse
  if bot.mapKind != MapMain or bot.minutes > MorningIdentityUntilMinutes:
    return
  let feet = collisionRectFromFoot(bot.playerFootX(), bot.playerFootY())
  var bestDistance = MorningIdentityRadius * MorningIdentityRadius + 1
  for i, house in bot.resources.houses:
    if not bot.resources.houseValid[i]:
      continue
    let distance = feet.rectDistanceSquared(house)
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
  ## Updates simple stuck detection from movement and position deltas.
  let moving = (mask and (
    ButtonUp or ButtonDown or ButtonLeft or ButtonRight
  )) != 0
  let
    footX = bot.playerFootX()
    footY = bot.playerFootY()
  if moving and footX == bot.previousX and footY == bot.previousY:
    inc bot.stuckTicks
  else:
    bot.stuckTicks = 0
  bot.previousX = footX
  bot.previousY = footY

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
  if bot.mapKind != MapMain:
    return
  let feet = collisionRectFromFoot(bot.playerFootX(), bot.playerFootY())
  var bestDistance = CollectActionRadius * CollectActionRadius + 1
  for i, rect in bot.resources.gardens:
    if not bot.gardenHasMarker(i):
      continue
    let distance = feet.rectDistanceSquared(rect)
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

proc shouldGather(bot: Bot): bool =
  ## Returns true when the bot should keep gathering food.
  bot.minutes < HouseEnterMinutes and not bot.gardensExhausted()

proc analyze(bot: Bot) =
  ## Rebuilds high-level bot state from decoded objects.
  bot.updateClock()
  bot.updateMapKind()
  bot.updateSelf()
  if bot.mapKind == MapHome and bot.currentHouse == UnknownHouse and
      bot.playerName.len > 0:
    bot.currentHouse = bot.homeIndex

proc maybeGreetNearby(bot: Bot, ws: WebSocket): bool =
  ## Greets newly seen nearby players once per day.
  if not bot.localized or bot.mapKind == MapOverlay:
    return false
  let
    selfX = bot.playerFootX()
    selfY = bot.playerFootY()
    radiusSquared = GreetingRadius * GreetingRadius
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if playerIndex == bot.selfIndex:
      continue
    let name = bot.visiblePlayerName(playerIndex)
    if name.len == 0 or name == bot.playerName or bot.hasGreeted(name):
      continue
    let distance = distanceSquared(
      selfX,
      selfY,
      bot.objectFootX(objectState),
      bot.objectFootY(objectState)
    )
    if distance > radiusSquared:
      continue
    let message = bot.greetingText(name)
    bot.greetedNames.add(name)
    bot.lastGreetingTick = bot.frameTick
    ws.send(blobFromChat(message), BinaryMessage)
    bot.log("chat " & message)
    return true
  false

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

proc initBot(name: string, slot: int, decodeVisualSprites = false): Bot =
  ## Builds a new talking Villager bot state.
  result = Bot()
  result.decodeVisualSprites = decodeVisualSprites
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
  result.soulInstructions =
    if result.playerName.len > 0:
      result.playerName.loadSoulInstructions()
    else:
      DefaultName.loadSoulInstructions()
  result.resources = loadBotResources()
  result.currentHouse =
    if result.playerName.len > 0:
      result.homeIndex
    else:
      UnknownHouse
  result.pendingHouse = UnknownHouse
  result.minutes = DayStartMinutes
  result.selfIndex = -1
  result.goal = Goal(kind: GoalIdle, mapKind: MapUnknown)
  result.currentGarden = -1
  result.partyHouse = UnknownHouse
  result.searchHouse = UnknownHouse
  result.hostUntilMinutes = -1
  result.hostCommitted = false
  result.hasDecision = false
  result.decisionChatSent = false
  result.llmWaiting = false
  result.committedPartyHouse = UnknownHouse
  result.dayIndex = 0
  result.gardenChecked = newSeq[bool](result.resources.gardens.len)
  result.greetedNames = @[]
  result.lastGreetingTick = -1

proc gardenGoal(bot: Bot): Goal =
  ## Returns a goal for the nearest garden that may still have food.
  result = Goal(kind: GoalIdle, mapKind: MapMain)
  if bot.mapKind != MapMain or bot.mainNav == nil:
    return
  if bot.gardenChecked.len != bot.resources.gardens.len:
    bot.resetGardenPlan()

  let nearbyGarden = bot.nearbyMarkedGarden()
  if nearbyGarden >= 0:
    let target = bot.resources.gardens[nearbyGarden].center()
    bot.currentGarden = nearbyGarden
    return Goal(
      kind: GoalCollect,
      mapKind: MapMain,
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
        mapKind: MapMain,
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
        mapKind: MapMain,
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
    let path = bot.mainNav.findPathNear(
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
    mapKind: MapMain,
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
  let cell = nav.nearestCellInside(rect, target.x, target.y)
  if cell >= 0:
    target = nav.pointForCell(cell)
  Goal(
    kind: kind,
    mapKind: bot.mapKind,
    x: target.x,
    y: target.y,
    houseIndex: houseIndex,
    gardenIndex: -1
  )

proc exitGoal(bot: Bot): Goal =
  ## Returns a goal for leaving the current home map.
  if not bot.resources.hasExit:
    return Goal(kind: GoalIdle, mapKind: bot.mapKind)
  bot.goalForRect(GoalExitHouse, bot.resources.exit, UnknownHouse)

proc enterHouseGoal(bot: Bot, houseIndex: int): Goal =
  ## Returns a goal for entering one main-map house.
  if houseIndex < 0 or houseIndex >= bot.resources.houseValid.len or
      not bot.resources.houseValid[houseIndex]:
    return Goal(kind: GoalIdle, mapKind: bot.mapKind)
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
  collisionRectFromFoot(
    bot.objectFootX(objectState),
    bot.objectFootY(objectState)
  ).rectDistanceSquared(bot.resources.houses[houseIndex]) <=
    HouseGatherMaxRadius * HouseGatherMaxRadius

proc visiblePlayerHome(bot: Bot, playerIndex: int): int =
  ## Returns the fixed home index for one visible player.
  bot.visiblePlayerName(playerIndex).houseIndexForPlayerName()

proc houseOwnerPresent(bot: Bot, houseIndex: int): bool =
  ## Returns true when a home owner is visible near their house.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if bot.visiblePlayerHome(playerIndex) != houseIndex:
      continue
    if bot.playerNearHouse(objectState, houseIndex):
      return true

proc houseHasGuest(bot: Bot, houseIndex: int): bool =
  ## Returns true when another visible player waits near one house.
  if houseIndex < 0 or
      houseIndex >= bot.resources.houseValid.len or
      not bot.resources.houseValid[houseIndex]:
    return false
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    if objectId - PlayerObjectBase == bot.selfIndex:
      continue
    if bot.playerNearHouse(objectState, houseIndex):
      return true

proc houseCrowd(bot: Bot, houseIndex: int): int =
  ## Returns how many visible gnomes are gathered near one house.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    if bot.playerNearHouse(objectState, houseIndex):
      inc result

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

proc socialRandom(bot: Bot, salt, limit: int): int =
  ## Returns one deterministic daily pseudo-random value.
  if limit <= 0:
    return 0
  var value = uint32(bot.homeIndex + 1)
  value = value * 1103515245'u32 + uint32(bot.dayIndex + 1)
  value = value xor (uint32(max(0, salt)) * 2654435761'u32)
  value = value xor (value shr 16)
  int(value mod uint32(limit))

proc hostWaitDuration(bot: Bot): int =
  ## Returns how long this bot should try hosting today.
  let food = bot.inventoryTotal()
  if food >= StrongHostFood:
    return MaxHostWaitMinutes
  var
    base = 0
    jitter = 15
  if food <= 0:
    base = 0
    jitter = 10
  elif food <= LowHostFood:
    base = 5
    jitter = 15
  elif food < MediumHostFood:
    base = 15
    jitter = 25
  else:
    base = 40
    jitter = 45
  min(MaxHostWaitMinutes, base + bot.socialRandom(31 + food, jitter + 1))

proc ensureHostWait(bot: Bot) =
  ## Initializes this day's host patience window.
  if bot.hostUntilMinutes >= 0:
    return
  bot.hostUntilMinutes = min(
    HouseEnterMinutes,
    bot.minutes + bot.hostWaitDuration()
  )

proc shouldHostOwnHouse(bot: Bot): bool =
  ## Returns true when the bot should keep trying to host at home.
  if bot.homeIndex < 0 or bot.homeIndex >= HouseCount:
    return false
  if bot.houseHasGuest(bot.homeIndex):
    bot.hostCommitted = true
    bot.partyHouse = bot.homeIndex
    return true
  if bot.hostCommitted:
    bot.partyHouse = bot.homeIndex
    return true
  if bot.minutes >= LatePartySearchMinutes:
    return false
  let food = bot.inventoryTotal()
  if food >= StrongHostFood:
    bot.partyHouse = bot.homeIndex
    return true
  bot.ensureHostWait()
  if bot.minutes < bot.hostUntilMinutes:
    bot.partyHouse = bot.homeIndex
    return true
  false

proc requiredPartyCrowd(bot: Bot): int =
  ## Returns the crowd size this bot prefers before joining a party.
  if bot.minutes >= LatePartySearchMinutes:
    return 1
  let minutesLeft = max(0, HouseEnterMinutes - bot.minutes)
  result =
    if minutesLeft > 180:
      4
    elif minutesLeft > 90:
      3
    elif minutesLeft > 30:
      2
    else:
      1
  let food = bot.inventoryTotal()
  if food <= LowHostFood:
    result = max(1, result - 1)
  elif food >= MediumHostFood:
    result = min(4, result + 1)

proc acceptsPartyCrowd(bot: Bot, houseIndex, crowd: int): bool =
  ## Returns true when this bot accepts a visible house crowd.
  if crowd <= 0:
    return false
  if bot.minutes >= LatePartySearchMinutes:
    return true
  let required = bot.requiredPartyCrowd()
  if crowd >= required:
    return true
  let
    minutesLeft = max(0, HouseEnterMinutes - bot.minutes)
    deficit = required - crowd
  var chance =
    if minutesLeft > 180:
      case deficit
      of 1: 20
      of 2: 5
      else: 0
    elif minutesLeft > 90:
      case deficit
      of 1: 45
      of 2: 15
      else: 3
    elif minutesLeft > 30:
      case deficit
      of 1: 70
      of 2: 35
      else: 10
    else:
      100
  let food = bot.inventoryTotal()
  if food <= LowHostFood:
    chance += 15
  elif food >= MediumHostFood:
    chance -= 10
  chance = chance.clamp(0, 100)
  let salt = 1000 + houseIndex * 17 + bot.minutes div 15
  bot.socialRandom(salt, 100) < chance

proc visiblePartyScore(bot: Bot, houseIndex, crowd: int): int =
  ## Returns a score for a visible candidate dinner house.
  let distance = bot.playerDistanceSquared(bot.resources.houses[houseIndex])
  result = crowd * 10_000 - distance div 16
  if houseIndex == bot.partyHouse:
    result += 2_000

proc bestVisiblePartyHouse(bot: Bot, relaxed = false): int =
  ## Returns the best visible house party this bot is willing to join.
  result = UnknownHouse
  var bestScore = low(int)
  for houseIndex in 0 ..< HouseCount:
    if not bot.resources.houseValid[houseIndex]:
      continue
    if houseIndex == bot.homeIndex:
      continue
    if not bot.houseOwnerPresent(houseIndex):
      continue
    let count = bot.houseCrowd(houseIndex)
    if not relaxed and not bot.acceptsPartyCrowd(houseIndex, count):
      continue
    let score = bot.visiblePartyScore(houseIndex, count)
    if score > bestScore:
      bestScore = score
      result = houseIndex

proc scoutingHouseIndex(bot: Bot): int =
  ## Returns the next house this bot should inspect while seeking.
  result = bot.homeIndex
  let step = max(0, bot.minutes - DayStartMinutes) div 20
  for offset in 0 ..< HouseCount:
    let houseIndex = (bot.homeIndex + step + offset + 1) mod HouseCount
    if houseIndex == bot.homeIndex:
      continue
    if bot.resources.houseValid[houseIndex]:
      result = houseIndex
      break
  bot.searchHouse = result

proc partyHouseIndex(bot: Bot): int =
  ## Returns the house this bot currently wants for dinner.
  if bot.partyHouse >= 0:
    return bot.partyHouse
  result = bot.bestVisiblePartyHouse(true)
  if result < 0 and bot.searchHouse >= 0:
    result = bot.searchHouse
  if result < 0:
    result = bot.homeIndex
  bot.partyHouse = result

proc desiredHouseGatherPoint(bot: Bot, house: Rect): Point =
  ## Returns this bot's preferred outside door spot around one house.
  let
    slot = bot.homeIndex mod DoorGatherSlots
    offset = (slot - DoorGatherSlots div 2) * DoorGatherSpacing
  Point(
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
    cell = bot.mainNav.nearestCellOutside(
      house,
      desired,
      HouseGatherMaxRadius
    )
  if cell >= 0:
    result = bot.mainNav.pointForCell(cell)

proc gatherAtHouseGoal(bot: Bot, houseIndex: int): Goal =
  ## Returns a goal that keeps the bot visible outside one house.
  if bot.mapKind == MapHome:
    return bot.exitGoal()
  if bot.mapKind != MapMain:
    return Goal(kind: GoalIdle, mapKind: bot.mapKind)
  let point = bot.houseGatherPoint(houseIndex)
  Goal(
    kind: GoalGatherHouse,
    mapKind: MapMain,
    x: point.x,
    y: point.y,
    houseIndex: houseIndex,
    gardenIndex: -1
  )

proc gatherOwnHouseGoal(bot: Bot): Goal =
  ## Returns the goal that keeps the bot outside its own house.
  bot.gatherAtHouseGoal(bot.homeIndex)

proc dinnerGatherGoal(bot: Bot): Goal =
  ## Returns the outside-house goal for pre-dinner social planning.
  if bot.mapKind == MapHome:
    return bot.exitGoal()
  if bot.mapKind != MapMain:
    return Goal(kind: GoalIdle, mapKind: bot.mapKind)
  if bot.shouldHostOwnHouse():
    return bot.gatherOwnHouseGoal()
  let partyHouse = bot.bestVisiblePartyHouse()
  if partyHouse >= 0:
    bot.partyHouse = partyHouse
    return bot.gatherAtHouseGoal(partyHouse)
  let scoutHouse = bot.scoutingHouseIndex()
  bot.partyHouse = UnknownHouse
  bot.searchHouse = scoutHouse
  bot.gatherAtHouseGoal(scoutHouse)

proc firstDinerGoal(bot: Bot): Goal =
  ## Returns a small idle movement goal away from the home exit.
  Goal(
    kind: GoalMove,
    mapKind: bot.mapKind,
    x: bot.playerFootX(),
    y: bot.playerFootY(),
    houseIndex: bot.currentHouse,
    gardenIndex: -1
  )

proc partyGoal(bot: Bot): Goal =
  ## Returns the goal that gets the bot to the shared dinner house.
  let houseIndex = bot.partyHouseIndex()
  if bot.mapKind == MapHome:
    if bot.currentHouse == houseIndex:
      return bot.firstDinerGoal()
    return bot.exitGoal()
  if bot.mapKind == MapMain:
    return bot.enterHouseGoal(houseIndex)
  Goal(kind: GoalIdle, mapKind: bot.mapKind)

proc ownHomeGoal(bot: Bot): Goal =
  ## Returns the goal that gets the bot into its own house.
  if bot.mapKind == MapHome:
    if bot.currentHouse == bot.homeIndex:
      return bot.firstDinerGoal()
    return bot.exitGoal()
  if bot.mapKind == MapMain:
    return bot.enterHouseGoal(bot.homeIndex)
  Goal(kind: GoalIdle, mapKind: bot.mapKind)

proc visibleOtherPlayerCount(bot: Bot): int =
  ## Returns how many other player sprites are visible now.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    if objectId - PlayerObjectBase != bot.selfIndex:
      inc result

proc visiblePlayerNear(bot: Bot, name: string): bool =
  ## Returns true when one named visible player is close enough to talk.
  let playerIndex = bot.visiblePlayerIndexByName(name)
  if playerIndex < 0:
    return false
  let objectId = PlayerObjectBase + playerIndex
  if objectId < 0 or objectId >= bot.objects.len:
    return false
  let objectState = bot.objects[objectId]
  if not objectState.present:
    return false
  distanceSquared(
    bot.playerFootX(),
    bot.playerFootY(),
    bot.objectFootX(objectState),
    bot.objectFootY(objectState)
  ) <= PersonStandRadius * PersonStandRadius

proc standNextToPersonGoal(bot: Bot, name: string): Goal =
  ## Returns a goal for walking near one visible or likely player.
  let playerIndex = bot.visiblePlayerIndexByName(name)
  if playerIndex >= 0:
    let objectState = bot.objects[PlayerObjectBase + playerIndex]
    return Goal(
      kind: GoalStandPerson,
      mapKind: bot.mapKind,
      x: bot.objectFootX(objectState),
      y: bot.objectFootY(objectState),
      houseIndex: bot.visiblePlayerHome(playerIndex),
      gardenIndex: -1,
      targetName: name
    )
  if bot.mapKind == MapHome:
    return bot.exitGoal()
  if bot.mapKind == MapMain:
    let houseIndex = name.houseIndexForPlayerName()
    if houseIndex >= 0:
      return bot.gatherAtHouseGoal(houseIndex)
  Goal(kind: GoalIdle, mapKind: bot.mapKind)

proc decisionHouse(bot: Bot, decision: LlmDecision): int =
  ## Returns the best house target for one LLM decision.
  result = decision.houseIndex
  if result < 0 and decision.targetName.len > 0:
    result = decision.targetName.houseIndexForPlayerName()
  if result < 0 and bot.committedPartyHouse >= 0:
    result = bot.committedPartyHouse

proc mentionedHouseIndex(message: string): int =
  ## Returns a house index mentioned by owner name in chat text.
  result = UnknownHouse
  let lower = message.toLowerAscii()
  for i, playerName in PlayerNames:
    let owner = playerName.toLowerAscii()
    if lower.contains(owner & "'s house") or
        lower.contains(owner & "s house") or
        lower.contains(owner & " house"):
      return i

proc isHostInviteMessage(message: string): bool =
  ## Returns true when chat text invites people to this bot's house.
  let lower = message.toLowerAscii()
  lower.contains("my house") or
    lower.contains("my place") or
    lower.contains("come to my") or
    lower.contains("party at my") or
    lower.contains("meet at my")

proc isAttendanceMessage(message: string): bool =
  ## Returns true when chat text confirms attendance at a party.
  let lower = message.toLowerAscii()
  lower.contains("i will come") or
    lower.contains("i'll come") or
    lower.contains("i will be there") or
    lower.contains("i'll be there") or
    lower.contains("i am coming") or
    lower.contains("i'm coming") or
    lower.contains("see you") or
    lower.contains("sounds great") or
    lower.contains("count me in") or
    lower.contains("coming to")

proc inferSocialCommitment(bot: Bot, decision: LlmDecision): LlmDecision =
  ## Infers party commitments from social chat decisions.
  result = decision
  let mentionedHouse = decision.message.mentionedHouseIndex()
  if result.houseIndex < 0 and mentionedHouse >= 0:
    result.houseIndex = mentionedHouse
  if result.action == LlmGoToParty and result.houseIndex < 0:
    let targetHouse = result.targetName.houseIndexForPlayerName()
    if targetHouse >= 0:
      result.houseIndex = targetHouse
  if result.action != LlmSayToPerson:
    return
  if result.message.isHostInviteMessage():
    result.commitParty = true
    result.houseIndex = bot.homeIndex
    return
  if result.commitParty or result.message.isAttendanceMessage():
    if result.houseIndex < 0:
      let targetHouse = result.targetName.houseIndexForPlayerName()
      if targetHouse >= 0:
        result.houseIndex = targetHouse
    if result.houseIndex >= 0:
      result.commitParty = true

proc timePhase(bot: Bot): int =
  ## Returns a coarse strategic time phase.
  if bot.minutes < HostPrepMinutes:
    return 0
  if bot.minutes < InviteStartMinutes:
    return 1
  if bot.minutes < HouseEnterMinutes:
    return 2
  if bot.minutes < DinnerMinutes:
    return 3
  if bot.minutes < PartyLeaveMinutes:
    return 4
  if bot.minutes < DayEndMinutes:
    return 5
  6

proc foodBand(bot: Bot): int =
  ## Returns a coarse inventory band for interrupt detection.
  let food = bot.inventoryTotal()
  if food <= LowHostFood:
    return 0
  if food >= HighFoodForInvites:
    return 2
  1

proc commitmentHasCompany(bot: Bot): bool =
  ## Returns true while a party commitment should still be honored.
  let houseIndex = bot.committedPartyHouse
  if houseIndex < 0:
    return false
  if bot.hostCommitted and houseIndex == bot.homeIndex:
    return true
  if bot.mapKind == MapHome and bot.currentHouse == houseIndex:
    return bot.visibleOtherPlayerCount() > 0
  true

proc mapNameForPrompt(kind: MapKind): string =
  ## Returns a readable map name for the LLM prompt.
  case kind
  of MapUnknown:
    "unknown"
  of MapMain:
    "world"
  of MapHome:
    "home"
  of MapOverlay:
    "overlay"

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

proc visibleChatsSignature(bot: Bot): string =
  ## Returns a compact signature of visible chat bubbles.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < ChatObjectBase or objectId >= GardenObjectBase:
      continue
    let playerIndex = objectId - ChatObjectBase
    let chat = bot.visibleChatText(playerIndex)
    if chat.len == 0:
      continue
    result.add(bot.visiblePlayerName(playerIndex) & ":" & chat & "|")

proc houseCrowdsText(bot: Bot): string =
  ## Returns visible house crowd facts for the LLM prompt.
  for houseIndex in 0 ..< HouseCount:
    if not bot.resources.houseValid[houseIndex]:
      continue
    if result.len > 0:
      result.add("\n")
    result.add(
      "- houseOwner=" & houseIndex.playerNameForHouse() &
      " houseIndex=" & $(houseIndex + 1) &
      " otherCrowd=" & $bot.houseCrowdOthers(houseIndex) &
      " ownerPresent=" & $bot.houseOwnerPresent(houseIndex) &
      " hasGuest=" & $bot.houseHasGuest(houseIndex)
    )

proc houseCrowdsSignature(bot: Bot): string =
  ## Returns a compact signature of visible house crowds.
  for houseIndex in 0 ..< HouseCount:
    let crowd = bot.houseCrowdOthers(houseIndex)
    if crowd > 0:
      result.add($(houseIndex + 1) & ":" & $crowd & ",")
  if result.len == 0:
    result = "none"

proc gardenMarkersText(bot: Bot): string =
  ## Returns visible garden marker facts for the LLM prompt.
  var count = 0
  for i in 0 ..< bot.resources.gardens.len:
    if bot.gardenHasMarker(i):
      inc count
      if result.len > 0:
        result.add(", ")
      result.add($i)
  if result.len == 0:
    result = "none"
  result = "visible=" & $count & " indices=" & result

proc decisionStateSignature(bot: Bot): string =
  ## Returns the interrupt signature for the current strategic state.
  "phase=" & $bot.timePhase() &
    "|food=" & $bot.foodBand() &
    "|chats=" & bot.visibleChatsSignature() &
    "|crowds=" & bot.houseCrowdsSignature() &
    "|commit=" & $bot.committedPartyHouse &
    "|commitCompany=" & $bot.commitmentHasCompany()

proc llmSystemPrompt(): string =
  ## Returns the stable system prompt for the social player.
  "You are talking_villager, a Heartleaf gnome player. " &
    "Return only one JSON object and no prose. " &
    "Allowed actions are keep_gathering_plants, find_person, find_house, " &
    "go_home, stand_at_house_garden, stand_next_to_person, say_to_person, " &
    "and go_to_party. Fields are action, targetName, houseIndex, message, " &
    "commitParty, and reason. houseIndex is 1 to 9. " &
    "Gather as much food as possible early. If food is high by 3pm, " &
    "stand at your house to greet people. At 4pm, invite people to " &
    "your house if you have food. After 5pm, stop gathering and switch " &
    "to social party planning. After 6pm, go to a party or your own " &
    "house even if food is low. If food is low, seek a party. If food " &
    "is high, invite people to your party using say_to_person. Say " &
    "short friendly phrases to nearby players so " &
    "they are more likely to cooperate. Prefer messages under 12 words. " &
    "In chat messages, never call houses by number. Use my house, your " &
    "house, or the owner's name, like Anton's house. Only use numeric " &
    "houseIndex values in JSON fields. If you agree to attend a party, " &
    "set commitParty true, set houseIndex to that owner's house, and say " &
    "a short confirmation. Do not confirm attendance if you are already " &
    "committed somewhere else or hosting your own party. " &
    "Choose who to visit, who to invite, and exactly what to say. " &
    "Honor party agreements unless nobody else is there."

proc llmUserPrompt(bot: Bot): string =
  ## Builds one current-state prompt for the LLM.
  let commitment =
    if bot.committedPartyHouse >= 0:
      bot.committedPartyHouse.playerNameForHouse() & "'s house"
    else:
      "none"
  let commitmentIndex =
    if bot.committedPartyHouse >= 0:
      $(bot.committedPartyHouse + 1)
    else:
      "none"
  let currentHouse =
    if bot.currentHouse >= 0:
      $(bot.currentHouse + 1)
    else:
      "none"
  let currentHouseOwner =
    if bot.currentHouse >= 0:
      bot.currentHouse.playerNameForHouse()
    else:
      "none"
  result =
    "Current Heartleaf state:\n" &
    "timeMinutes=" & $bot.minutes & "\n" &
    "map=" & bot.mapKind.mapNameForPrompt() & "\n" &
    "homeOwner=" & bot.homeIndex.playerNameForHouse() & "\n" &
    "homeHouseIndex=" & $(bot.homeIndex + 1) & "\n" &
    "currentHouseOwner=" & currentHouseOwner & "\n" &
    "currentHouseIndex=" & currentHouse & "\n" &
    "foodTotal=" & $bot.inventoryTotal() & "\n" &
    "partyCommitment=" & commitment & "\n" &
    "partyCommitmentHouseIndex=" & commitmentIndex & "\n" &
    "agentSoul:\n" & bot.soulInstructions & "\n" &
    "strategyFoodLowAt=" & $LowHostFood & "\n" &
    "strategyFoodHighAt=" & $HighFoodForInvites & "\n" &
    "clock=" & bot.minutes.clockName() & "\n" &
    "timeMeaning=timeMinutes is minutes after midnight; " &
    $HostPrepMinutes & " is 3:00pm, " &
    $InviteStartMinutes & " is 4:00pm, " &
    $DinnerMinutes & " is 6:00pm\n" &
    "hostPrepStartsAt=" & $HostPrepMinutes & "\n" &
    "inviteStartsAt=" & $InviteStartMinutes & "\n" &
    "partyPrepStartsAt=" & $HouseEnterMinutes & "\n" &
    "dinnerStartsAt=" & $DinnerMinutes & "\n" &
    "partyLeaveStartsAt=" & $PartyLeaveMinutes & "\n" &
    "rules=before partyPrepStartsAt gather food; after partyPrepStartsAt " &
    "do not keep gathering; after dinnerStartsAt choose go_to_party " &
    "unless already safely home or honoring another commitment\n" &
    "visiblePlayers:\n" & bot.visiblePlayersText() & "\n" &
    "visibleHouseCrowds:\n" & bot.houseCrowdsText() & "\n" &
    "gardenMarkers=" & bot.gardenMarkersText() & "\n" &
    "availableActions=keep_gathering_plants, find_person, find_house, " &
    "go_home, stand_at_house_garden, stand_next_to_person, say_to_person, " &
    "go_to_party\n" &
    "Return JSON now."

proc partyFallbackHouse(bot: Bot): int =
  ## Returns a deterministic party target for deadline guardrails.
  result = bot.bestVisiblePartyHouse(true)
  if result >= 0:
    return
  if bot.searchHouse >= 0:
    return bot.searchHouse
  result = bot.scoutingHouseIndex()
  if result < 0:
    result = bot.homeIndex

proc partyTimeDecision(bot: Bot, reason: string): LlmDecision =
  ## Returns a go-to-party decision for social deadline guardrails.
  LlmDecision(
    valid: true,
    action: LlmGoToParty,
    houseIndex: bot.partyFallbackHouse(),
    commitParty: true,
    reason: reason
  )

proc prepTimeDecision(bot: Bot, reason: string): LlmDecision =
  ## Returns a pre-dinner social decision when gathering must stop.
  let partyHouse = bot.bestVisiblePartyHouse(true)
  if partyHouse >= 0 or bot.inventoryTotal() <= LowHostFood:
    return bot.partyTimeDecision(reason)
  LlmDecision(
    valid: true,
    action: LlmStandAtHouseGarden,
    houseIndex: bot.homeIndex,
    reason: reason
  )

proc enforceTimePolicy(bot: Bot, decision: LlmDecision): LlmDecision =
  ## Prevents late gathering from overriding dinner and party time.
  result = decision
  if bot.minutes < InviteStartMinutes and
      decision.action == LlmSayToPerson and
      decision.message.isHostInviteMessage():
    if bot.minutes >= HostPrepMinutes:
      result = LlmDecision(
        valid: true,
        action: LlmStandAtHouseGarden,
        houseIndex: bot.homeIndex,
        reason: "wait until 4pm to invite people"
      )
    else:
      result = LlmDecision(
        valid: true,
        action: LlmKeepGatheringPlants,
        reason: "too early to invite people"
      )
    return
  if bot.minutes >= DayEndMinutes:
    if decision.action != LlmGoToParty:
      result = LlmDecision(
        valid: true,
        action: LlmGoHome,
        reason: "day is ending"
      )
    return
  if bot.minutes >= DinnerMinutes:
    case decision.action
    of LlmGoToParty, LlmGoHome:
      return
    else:
      result = bot.partyTimeDecision(
        "dinner time has started; stop gathering and attend a party"
      )
      return
  if bot.minutes >= HouseEnterMinutes and
      decision.action == LlmKeepGatheringPlants:
    result = bot.prepTimeDecision(
      "party planning time has started; stop gathering"
    )
    return
  if bot.minutes >= HostPrepMinutes and
      bot.inventoryTotal() >= HighFoodForInvites and
      decision.action == LlmKeepGatheringPlants and
      bot.committedPartyHouse < 0:
    result = LlmDecision(
      valid: true,
      action: LlmStandAtHouseGarden,
      houseIndex: bot.homeIndex,
      reason: "food reserve is ready; prepare at own house"
    )

proc fallbackDecision(bot: Bot): LlmDecision =
  ## Returns the safest deterministic decision when the LLM is unavailable.
  result = LlmDecision(
    valid: true,
    action: LlmKeepGatheringPlants,
    houseIndex: UnknownHouse,
    reason: "fallback"
  )
  if bot.committedPartyHouse >= 0 and bot.commitmentHasCompany():
    result.action = LlmGoToParty
    result.houseIndex = bot.committedPartyHouse
    result.commitParty = true
  elif bot.minutes >= DayEndMinutes:
    result.action = LlmGoHome
  elif bot.minutes >= DinnerMinutes:
    result = bot.partyTimeDecision("fallback dinner party")
  elif bot.minutes >= HouseEnterMinutes:
    result = bot.prepTimeDecision("fallback party planning")
  elif bot.minutes >= HostPrepMinutes and
      bot.inventoryTotal() >= HighFoodForInvites:
    result.action = LlmStandAtHouseGarden
    result.houseIndex = bot.homeIndex
    result.reason = "fallback host preparation"
  elif bot.shouldGather():
    result.action = LlmKeepGatheringPlants
  elif bot.inventoryTotal() >= HighFoodForInvites:
    result.action = LlmStandAtHouseGarden
    result.houseIndex = bot.homeIndex
  else:
    let houseIndex = bot.bestVisiblePartyHouse(true)
    result.action = LlmGoToParty
    result.houseIndex =
      if houseIndex >= 0:
        houseIndex
      else:
        bot.homeIndex
    result.commitParty = true

proc enforceCommitment(bot: Bot, decision: LlmDecision): LlmDecision =
  ## Forces party commitments unless the bot is alone at that party.
  result = decision
  if bot.committedPartyHouse < 0:
    return
  if bot.hostCommitted and bot.committedPartyHouse == bot.homeIndex:
    if decision.action == LlmSayToPerson:
      if not decision.commitParty or
          decision.houseIndex < 0 or
          decision.houseIndex == bot.homeIndex:
        return
    let decisionHouse = bot.decisionHouse(decision)
    if decision.action == LlmStandAtHouseGarden and
        (decisionHouse < 0 or decisionHouse == bot.homeIndex):
      return
    if decision.action == LlmGoHome:
      return
  if not bot.commitmentHasCompany():
    bot.log("party commitment cleared because no one else is there")
    if bot.searchHouse == bot.committedPartyHouse:
      bot.searchHouse = UnknownHouse
    if bot.partyHouse == bot.committedPartyHouse:
      bot.partyHouse = UnknownHouse
    bot.committedPartyHouse = UnknownHouse
    return
  if decision.action == LlmGoToParty and
      decision.houseIndex == bot.committedPartyHouse:
    return
  result = LlmDecision(
    valid: true,
    action: LlmGoToParty,
    houseIndex: bot.committedPartyHouse,
    commitParty: true,
    reason: "honoring party commitment"
  )

proc applyDecision(bot: Bot, decision: LlmDecision) =
  ## Stores one parsed LLM decision and updates social commitments.
  var nextDecision =
    if decision.valid:
      decision
    else:
      bot.fallbackDecision()
  nextDecision = bot.inferSocialCommitment(nextDecision)
  nextDecision = bot.enforceTimePolicy(nextDecision)
  nextDecision = bot.enforceCommitment(nextDecision)
  let commitHouse =
    if nextDecision.houseIndex >= 0:
      nextDecision.houseIndex
    elif nextDecision.commitParty:
      bot.homeIndex
    else:
      UnknownHouse
  if nextDecision.action == LlmGoToParty and commitHouse >= 0:
    bot.committedPartyHouse = commitHouse
    nextDecision.houseIndex = commitHouse
    nextDecision.commitParty = true
  elif nextDecision.commitParty and commitHouse >= 0:
    bot.committedPartyHouse = commitHouse
    nextDecision.houseIndex = commitHouse
    if commitHouse == bot.homeIndex and
        nextDecision.message.isHostInviteMessage():
      bot.hostCommitted = true
      bot.partyHouse = bot.homeIndex
  bot.decision = nextDecision
  bot.hasDecision = true
  bot.decisionChatSent = false
  bot.decisionStartedTick = bot.frameTick
  bot.decisionState = bot.decisionStateSignature()
  bot.decisionFoodBand = bot.foodBand()
  bot.decisionTimePhase = bot.timePhase()
  bot.decisionChatSignature = bot.visibleChatsSignature()
  bot.decisionCrowdSignature = bot.houseCrowdsSignature()
  bot.path.setLen(0)
  bot.goal = Goal(kind: GoalIdle, mapKind: MapUnknown)
  bot.log(
    "llm action " & nextDecision.action.actionName() &
    " house=" & $(nextDecision.houseIndex + 1) &
    " target=" & nextDecision.targetName &
    " message=" & nextDecision.message &
    " reason=" & nextDecision.reason
  )

proc applyLlmReply(bot: Bot, reply: string) =
  ## Parses and applies one LLM reply.
  let decision = reply.parseLlmDecision()
  if not decision.valid:
    bot.lastLlmError = decision.error
    bot.log("llm parse error " & decision.error)
  bot.applyDecision(decision)

proc startLlmDecision(bot: Bot): bool =
  ## Starts a Bedrock decision request or applies an immediate fallback.
  let mockReply = mockBedrockReply()
  if mockReply.len > 0:
    bot.applyLlmReply(mockReply)
    return false
  inc bot.llmSerial
  bot.llmTag = "decision-" & $bot.llmSerial
  let messages = @[
    ConversationMessage(role: "system", content: llmSystemPrompt()),
    ConversationMessage(role: "user", content: bot.llmUserPrompt())
  ]
  var started = false
  try:
    started = startTalkToBedrock(messages, bot.llmTag)
  except CatchableError as e:
    let answer = BedrockResult(done: true, error: e.msg)
    if answer.transientBedrockError():
      bot.lastLlmError = e.msg
      bot.log("llm transient start error " & e.msg & ", using fallback")
      bot.applyDecision(bot.fallbackDecision())
      return false
    raise newException(
      TalkingVillagerError,
      "Could not start Bedrock request: " & e.msg
    )
  if not started:
    raise newException(
      TalkingVillagerError,
      "AWS_BEARER_TOKEN_BEDROCK or BEDROCK_KEY is not set."
    )
  bot.llmWaiting = true
  bot.decisionStartedTick = bot.frameTick
  let latency = bedrockPerformanceLatency()
  let latencyName =
    if latency.len > 0:
      latency
    else:
      "default"
  bot.log(
    "llm request " & bot.llmTag &
    " model=" & bedrockModel() &
    " region=" & bedrockRegion() &
    " latency=" & latencyName
  )
  true

proc pollLlmDecision(bot: Bot): bool =
  ## Polls and applies a completed LLM request.
  if not bot.llmWaiting:
    return false
  let answer = pollTalkToBedrock()
  if not answer.done:
    return false
  if answer.tag != bot.llmTag:
    return false
  bot.llmWaiting = false
  if answer.ok:
    bot.applyLlmReply(answer.reply)
  else:
    bot.lastLlmError = answer.error
    bot.log("llm error " & answer.error)
    if answer.transientBedrockError():
      bot.log("llm transient error, using fallback")
      bot.applyDecision(bot.fallbackDecision())
    elif answer.permanentBedrockError():
      raise newException(
        TalkingVillagerError,
        "Bedrock request failed: " & answer.error
      )
    else:
      raise newException(
        TalkingVillagerError,
        "Unknown Bedrock request failed: " & answer.error
      )
  true

proc decisionGoal(bot: Bot, decision: LlmDecision): Goal =
  ## Converts one LLM decision into a deterministic navigation goal.
  case decision.action
  of LlmKeepGatheringPlants:
    if bot.minutes >= DinnerMinutes:
      return bot.partyGoal()
    if bot.minutes >= HouseEnterMinutes:
      return bot.dinnerGatherGoal()
    if bot.mapKind == MapHome:
      return bot.exitGoal()
    if bot.mapKind == MapMain:
      let garden = bot.gardenGoal()
      if garden.kind != GoalIdle:
        return garden
    Goal(kind: GoalIdle, mapKind: bot.mapKind)
  of LlmFindPerson, LlmStandNextToPerson, LlmSayToPerson:
    bot.standNextToPersonGoal(decision.targetName)
  of LlmFindHouse, LlmStandAtHouseGarden:
    let houseIndex = bot.decisionHouse(decision)
    if houseIndex < 0:
      return Goal(kind: GoalIdle, mapKind: bot.mapKind)
    bot.gatherAtHouseGoal(houseIndex)
  of LlmGoHome:
    bot.ownHomeGoal()
  of LlmGoToParty:
    let houseIndex = bot.decisionHouse(decision)
    if houseIndex < 0:
      return bot.ownHomeGoal()
    if bot.mapKind == MapHome:
      if bot.currentHouse == houseIndex:
        return bot.firstDinerGoal()
      return bot.exitGoal()
    if bot.mapKind == MapMain:
      return bot.enterHouseGoal(houseIndex)
    Goal(kind: GoalIdle, mapKind: bot.mapKind)
  of LlmInvalid:
    Goal(kind: GoalIdle, mapKind: bot.mapKind)

proc chooseGoal(bot: Bot): Goal =
  ## Chooses the current LLM-backed Heartleaf goal.
  if not bot.localized or bot.navForCurrentMap() == nil:
    return Goal(kind: GoalIdle, mapKind: bot.mapKind)
  if bot.mapKind == MapOverlay:
    return Goal(kind: GoalIdle, mapKind: bot.mapKind)
  if not bot.hasDecision:
    return Goal(kind: GoalIdle, mapKind: bot.mapKind)
  bot.decisionGoal(bot.decision)

proc goalReached(bot: Bot, goal: Goal): bool =
  ## Returns true when the bot is close enough to a goal to act.
  case goal.kind
  of GoalCollect:
    if goal.gardenIndex >= 0 and
        goal.gardenIndex < bot.resources.gardens.len:
      return collisionRectFromFoot(
        bot.playerFootX(),
        bot.playerFootY()
      ).rectDistanceSquared(
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
    ) <= NavStep * NavStep
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
  case goal.kind
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

proc decisionComplete(bot: Bot): bool =
  ## Returns true when the current LLM action has completed.
  if not bot.hasDecision:
    return true
  case bot.decision.action
  of LlmKeepGatheringPlants:
    if not bot.shouldGather():
      return true
    bot.inventoryTotal() >= HighFoodForInvites
  of LlmFindPerson, LlmStandNextToPerson:
    bot.visiblePlayerNear(bot.decision.targetName)
  of LlmSayToPerson:
    bot.decisionChatSent
  of LlmFindHouse, LlmStandAtHouseGarden:
    bot.goal.kind == GoalGatherHouse and bot.goalReached(bot.goal)
  of LlmGoHome:
    bot.mapKind == MapHome and bot.currentHouse == bot.homeIndex
  of LlmGoToParty:
    let houseIndex = bot.decisionHouse(bot.decision)
    bot.mapKind == MapHome and bot.currentHouse == houseIndex
  of LlmInvalid:
    true

proc decisionInterrupted(bot: Bot): bool =
  ## Returns true when major state changes should interrupt an action.
  if not bot.hasDecision:
    return true
  if bot.frameTick - bot.decisionStartedTick < DecisionRetryTicks:
    return false
  if bot.stuckTicks >= DecisionStuckTicks:
    return true
  let chatSignature = bot.visibleChatsSignature()
  if chatSignature.len > 0 and chatSignature != bot.decisionChatSignature:
    return true
  if bot.timePhase() != bot.decisionTimePhase:
    return true
  let foodBand = bot.foodBand()
  if foodBand != bot.decisionFoodBand:
    if bot.decision.action == LlmKeepGatheringPlants:
      return foodBand == 2
    return true
  let crowdSignature = bot.houseCrowdsSignature()
  if crowdSignature == bot.decisionCrowdSignature:
    return false
  if bot.decision.action == LlmKeepGatheringPlants:
    return bot.minutes >= LatePartySearchMinutes and crowdSignature != "none"
  true

proc needsFreshDecision(bot: Bot): bool =
  ## Returns true when the bot should ask the LLM again.
  if bot.llmWaiting:
    return false
  if not bot.hasDecision:
    return true
  bot.decisionComplete() or bot.decisionInterrupted()

proc maybeSendDecisionChat(bot: Bot, ws: WebSocket) =
  ## Sends the chat text chosen by the current LLM decision.
  if not bot.hasDecision or bot.decisionChatSent:
    return
  if bot.decision.action != LlmSayToPerson:
    return
  if bot.decision.message.len == 0:
    bot.decisionChatSent = true
    return
  if bot.decision.targetName.len > 0 and
      not bot.visiblePlayerNear(bot.decision.targetName):
    return
  ws.send(blobFromChat(bot.decision.message), BinaryMessage)
  bot.decisionChatSent = true
  bot.log("chat " & bot.decision.message)

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
      bot.path = nav.findPathNear(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.gardens[goal.gardenIndex],
        CollectActionRadius
      )
  of GoalEnterHouse:
    if goal.houseIndex >= 0 and
        goal.houseIndex < bot.resources.houseValid.len and
        bot.resources.houseValid[goal.houseIndex]:
      bot.path = nav.findPath(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.houses[goal.houseIndex]
      )
  of GoalExitHouse:
    if bot.resources.hasExit:
      bot.path = nav.findPath(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.exit
      )
  else:
    bot.path = nav.findPath(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    )
  if bot.path.len == 0:
    bot.path = nav.findPath(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    )

proc pathTarget(bot: Bot, goal: Goal): Point =
  ## Returns the current lookahead point along the path.
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
    let lookahead =
      if bot.stuckTicks >= StuckLookaheadTicks:
        StuckLookaheadPixels
      else:
        PathLookaheadPixels
    var
      walked = 0
      previous = Point(x: bot.playerFootX(), y: bot.playerFootY())
    result = bot.path[^1]
    for point in bot.path:
      walked += max(abs(point.x - previous.x), abs(point.y - previous.y))
      result = point
      if walked >= lookahead:
        break
      previous = point

proc needsMovement(bot: Bot, target: Point): bool =
  ## Returns true when a target is far enough to require button input.
  abs(target.x - bot.playerFootX()) > MoveDeadZonePixels or
    abs(target.y - bot.playerFootY()) > MoveDeadZonePixels

proc movementMask(bot: Bot, target: Point): uint8 =
  ## Builds a directional input mask toward one path target.
  let
    dx = target.x - bot.playerFootX()
    dy = target.y - bot.playerFootY()
  if abs(dx) > MoveDeadZonePixels:
    if dx > 0:
      result = result or ButtonRight
    else:
      result = result or ButtonLeft
  if abs(dy) > MoveDeadZonePixels:
    if dy > 0:
      result = result or ButtonDown
    else:
      result = result or ButtonUp

proc firstMovingPathTarget(bot: Bot, goal: Goal): Point =
  ## Returns the first path point that can actually produce movement.
  for point in bot.path:
    if bot.needsMovement(point):
      return point
  result = Point(x: goal.x, y: goal.y)

proc decideNextMask(bot: Bot, ws: WebSocket): uint8 =
  ## Chooses the next input mask for one game frame.
  bot.analyze()
  if not bot.localized:
    bot.desiredMask = 0
    bot.hasTarget = false
    return 0
  if bot.maybeGreetNearby(ws):
    bot.desiredMask = 0
    bot.hasTarget = false
    bot.updateStuck(0)
    return 0
  discard bot.pollLlmDecision()
  if bot.llmWaiting:
    bot.desiredMask = 0
    bot.hasTarget = false
    bot.updateStuck(0)
    return 0
  if bot.needsFreshDecision() and bot.startLlmDecision():
    bot.desiredMask = 0
    bot.hasTarget = false
    bot.updateStuck(0)
    return 0
  let goal = bot.chooseGoal()
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
  bot.desiredMask = result
  bot.updateStuck(result)

proc inputMaskSummary(mask: uint8): string =
  ## Returns a compact name for one input mask.
  var parts: seq[string]
  if (mask and ButtonUp) != 0:
    parts.add("up")
  if (mask and ButtonDown) != 0:
    parts.add("down")
  if (mask and ButtonLeft) != 0:
    parts.add("left")
  if (mask and ButtonRight) != 0:
    parts.add("right")
  if (mask and ButtonSelect) != 0:
    parts.add("select")
  if (mask and ButtonA) != 0:
    parts.add("a")
  if (mask and ButtonB) != 0:
    parts.add("b")
  if parts.len == 0:
    return "none"
  parts.join("+")

proc mapKindName(kind: MapKind): string =
  ## Returns a readable map-kind label.
  case kind
  of MapUnknown:
    "unknown"
  of MapMain:
    "world"
  of MapHome:
    "home"
  of MapOverlay:
    "overlay"

proc socialPlanName(bot: Bot): string =
  ## Returns the bot's current social dinner plan.
  if bot.shouldGather():
    return "gather"
  if bot.minutes >= HouseEnterMinutes and bot.minutes < PartyLeaveMinutes:
    return "enter"
  if bot.hostCommitted:
    return "committed host"
  if bot.partyHouse == bot.homeIndex:
    return "host"
  if bot.partyHouse >= 0:
    return "guest"
  if bot.searchHouse >= 0:
    return "seek"
  "plan"

proc checkedGardenCount(bot: Bot): int =
  ## Returns how many static gardens have been ruled out today.
  for checked in bot.gardenChecked:
    if checked:
      inc result

proc markedGardenCount(bot: Bot): int =
  ## Returns how many visible gardens still show a pickup marker.
  for i in 0 ..< bot.resources.gardens.len:
    if bot.gardenHasMarker(i):
      inc result

when defined(gui):
  proc drawOutline(
    sk: Silky,
    pos,
    size: Vec2,
    color: ColorRGBX,
    thickness = 1.0'f
  ) =
    ## Draws an unfilled rectangle.
    sk.drawRect(pos, vec2(size.x, thickness), color)
    sk.drawRect(
      vec2(pos.x, pos.y + size.y - thickness),
      vec2(size.x, thickness),
      color
    )
    sk.drawRect(pos, vec2(thickness, size.y), color)
    sk.drawRect(
      vec2(pos.x + size.x - thickness, pos.y),
      vec2(thickness, size.y),
      color
    )

  proc drawLine(sk: Silky, a, b: Vec2, color: ColorRGBX) =
    ## Draws a simple pixel-like debug line.
    let
      dx = b.x - a.x
      dy = b.y - a.y
      steps = max(1, int(max(abs(dx), abs(dy)) / 4.0'f))
    for i in 0 .. steps:
      let t = i.float32 / steps.float32
      sk.drawRect(
        vec2(a.x + dx * t - 1.0'f, a.y + dy * t - 1.0'f),
        vec2(3, 3),
        color
      )

  proc colorFromSpritePixel(sprite: SpriteInfo, offset: int): ColorRGBX =
    ## Converts one decoded RGBA sprite pixel to a viewer color.
    rgbx(
      sprite.pixels[offset],
      sprite.pixels[offset + 1],
      sprite.pixels[offset + 2],
      sprite.pixels[offset + 3]
    )

  proc compareDrawItems(a, b: DrawItem): int =
    ## Orders sprite protocol objects by render layer and stable id.
    result = cmp(a.layer, b.layer)
    if result != 0:
      return
    result = cmp(a.z, b.z)
    if result != 0:
      return
    result = cmp(a.y, b.y)
    if result != 0:
      return
    result = cmp(a.id, b.id)

  proc drawSpriteAt(
    sk: Silky,
    sprite: SpriteInfo,
    pos: Vec2,
    scale: float32
  ) =
    ## Draws one decoded sprite at an explicit viewer position.
    if sprite == nil or sprite.pixels.len != sprite.width * sprite.height * 4:
      return
    for py in 0 ..< sprite.height:
      for px in 0 ..< sprite.width:
        let offset = (py * sprite.width + px) * 4
        if sprite.pixels[offset + 3] == 0:
          continue
        sk.drawRect(
          vec2(
            pos.x + px.float32 * scale,
            pos.y + py.float32 * scale
          ),
          vec2(scale, scale),
          sprite.colorFromSpritePixel(offset)
        )

  proc drawSpriteObject(
    sk: Silky,
    sprite: SpriteInfo,
    objectState: ObjectState,
    origin: Vec2,
    scale: float32
  ) =
    ## Draws one decoded sprite protocol object into the frame panel.
    if sprite == nil or sprite.pixels.len != sprite.width * sprite.height * 4:
      return
    let
      startX = max(0, -objectState.x)
      startY = max(0, -objectState.y)
      stopX = min(sprite.width, ViewportWidth - objectState.x)
      stopY = min(sprite.height, ViewportHeight - objectState.y)
    if startX >= stopX or startY >= stopY:
      return
    for py in startY ..< stopY:
      for px in startX ..< stopX:
        let offset = (py * sprite.width + px) * 4
        if sprite.pixels[offset + 3] == 0:
          continue
        sk.drawRect(
          vec2(
            origin.x + (objectState.x + px).float32 * scale,
            origin.y + (objectState.y + py).float32 * scale
          ),
          vec2(scale, scale),
          sprite.colorFromSpritePixel(offset)
        )

  proc drawInventoryPanel(
    sk: Silky,
    bot: Bot,
    pos,
    size: Vec2
  ) =
    ## Draws the visible bot inventory along the viewer bottom edge.
    sk.drawRect(pos, size, ViewerPanel)
    var
      x = pos.x + ViewerInventoryGap
      drewAny = false
    let y = pos.y + (size.y - FoodSpriteSize.float32) / 2.0'f
    for foodIndex in 0 ..< FoodVeggieSlots:
      let objectId = InventoryObjectBase + foodIndex
      if objectId >= bot.objects.len:
        continue
      let objectState = bot.objects[objectId]
      if not objectState.present:
        continue
      let icon = bot.spriteInfo(objectState.spriteId)
      if icon == nil or icon.pixels.len == 0:
        continue
      if x + FoodSpriteSize.float32 > pos.x + size.x - ViewerInventoryGap:
        break
      let iconPos = vec2(x, y)
      sk.drawSpriteAt(icon, iconPos, ViewerInventoryScale)
      let countObjectId = InventoryCountObjectBase + foodIndex
      if countObjectId < bot.objects.len:
        let countObject = bot.objects[countObjectId]
        if countObject.present:
          let countSprite = bot.spriteInfo(countObject.spriteId)
          if countSprite != nil and countSprite.pixels.len > 0:
            sk.drawSpriteAt(
              countSprite,
              vec2(
                iconPos.x + FoodSpriteSize.float32 - countSprite.width.float32,
                iconPos.y + FoodSpriteSize.float32 - countSprite.height.float32
              ),
              ViewerInventoryScale
            )
      drewAny = true
      x += FoodSpriteSize.float32 + ViewerInventoryGap
    if not drewAny:
      discard sk.drawText(
        "Default",
        "inventory empty",
        pos + vec2(ViewerInventoryGap, ViewerInventoryGap),
        ViewerMutedText
      )

  proc drawSpriteObjects(
    sk: Silky,
    bot: Bot,
    origin: Vec2,
    scale: float32
  ) =
    ## Draws decoded non-inventory sprite protocol objects in visible order.
    var drawItems: seq[DrawItem]
    for objectId, objectState in bot.objects:
      if not objectState.present:
        continue
      if objectId >= InventoryObjectBase and objectId < ClockObjectBase:
        continue
      let sprite = bot.spriteInfo(objectState.spriteId)
      if sprite == nil or sprite.pixels.len == 0:
        continue
      drawItems.add(DrawItem(
        layer: objectState.layer,
        z: objectState.z,
        y: objectState.y,
        id: objectId
      ))
    drawItems.sort(compareDrawItems)
    for item in drawItems:
      let objectState = bot.objects[item.id]
      sk.drawSpriteObject(
        bot.spriteInfo(objectState.spriteId),
        objectState,
        origin,
        scale
      )

  proc rectVisible(rect: Rect): bool =
    ## Returns true when a world rectangle overlaps the current viewport.
    rect.x + rect.w >= 0 and rect.y + rect.h >= 0 and
      rect.x < ViewportWidth and rect.y < ViewportHeight

  proc screenRect(bot: Bot, rect: Rect): Rect =
    ## Converts a world rectangle to current screen coordinates.
    Rect(
      x: rect.x - bot.cameraX,
      y: rect.y - bot.cameraY,
      w: rect.w,
      h: rect.h
    )

  proc drawScreenRect(
    sk: Silky,
    rect: Rect,
    origin: Vec2,
    scale: float32,
    color: ColorRGBX,
    thickness = 1.0'f
  ) =
    ## Draws one screen-space rectangle if it overlaps the viewport.
    if not rect.rectVisible():
      return
    sk.drawOutline(
      vec2(
        origin.x + rect.x.float32 * scale,
        origin.y + rect.y.float32 * scale
      ),
      vec2(rect.w.float32 * scale, rect.h.float32 * scale),
      color,
      thickness
    )

  proc drawFramePath(sk: Silky, bot: Bot, origin: Vec2, scale: float32) =
    ## Draws the current path over the semantic screen view.
    if not bot.localized or bot.path.len == 0:
      return
    var previous = vec2(
      origin.x + (bot.playerFootX() - bot.cameraX).float32 * scale,
      origin.y + (bot.playerFootY() - bot.cameraY).float32 * scale
    )
    for i in countup(0, bot.path.high, 4):
      let current = vec2(
        origin.x + (bot.path[i].x - bot.cameraX).float32 * scale,
        origin.y + (bot.path[i].y - bot.cameraY).float32 * scale
      )
      sk.drawLine(previous, current, ViewerPath)
      previous = current

  proc drawFrameView(sk: Silky, bot: Bot, x, y: float32) =
    ## Draws a semantic 320x200 view from the latest sprite state.
    let
      scale = ViewerFrameScale
      origin = vec2(x, y)
    sk.drawRect(
      origin,
      vec2(ViewportWidth.float32 * scale, ViewportHeight.float32 * scale),
      ViewerPanelAlt
    )
    sk.drawSpriteObjects(bot, origin, scale)
    if bot.mapKind == MapMain:
      for rect in bot.resources.gardens:
        sk.drawScreenRect(
          bot.screenRect(rect),
          origin,
          scale,
          ViewerGarden
        )
      for i, rect in bot.resources.houses:
        if bot.resources.houseValid[i]:
          sk.drawScreenRect(
            bot.screenRect(rect),
            origin,
            scale,
            ViewerHouse
          )
    elif bot.mapKind == MapHome and bot.resources.hasExit:
      sk.drawScreenRect(
        bot.screenRect(bot.resources.exit),
        origin,
        scale,
        ViewerExit
      )

    sk.drawFramePath(bot, origin, scale)
    if bot.goal.kind != GoalIdle:
      sk.drawScreenRect(
        bot.screenRect(Rect(x: bot.goal.x - 3, y: bot.goal.y - 3, w: 6, h: 6)),
        origin,
        scale,
        ViewerGoal,
        2
      )
    if bot.hasTarget:
      sk.drawScreenRect(
        bot.screenRect(
          Rect(x: bot.target.x - 2, y: bot.target.y - 2, w: 5, h: 5)
        ),
        origin,
        scale,
        ViewerTarget,
        2
      )

    for objectId, objectState in bot.objects:
      if not objectState.present:
        continue
      if objectId >= PlayerObjectBase and objectId < NameObjectBase:
        let
          playerIndex = objectId - PlayerObjectBase
          color =
            if playerIndex == bot.selfIndex:
              ViewerPlayer
            else:
              ViewerOther
        sk.drawOutline(
          vec2(
            origin.x + objectState.x.float32 * scale,
            origin.y + objectState.y.float32 * scale
          ),
          vec2(GnomeSpriteSize.float32 * scale, GnomeSpriteSize.float32 * scale),
          color,
          2
        )
        sk.drawRect(
          vec2(
            origin.x + (objectState.x + NavPointOffsetX).float32 * scale - 2,
            origin.y + (objectState.y + NavPointOffsetY).float32 * scale - 2
          ),
          vec2(5, 5),
          color
        )
      elif objectId >= GardenObjectBase and objectId < InventoryObjectBase:
        sk.drawRect(
          vec2(
            origin.x + objectState.x.float32 * scale - 3,
            origin.y + objectState.y.float32 * scale - 3
          ),
          vec2(7, 7),
          ViewerTarget
        )

  proc activeNav(bot: Bot): NavMap =
    ## Returns the navigation map currently being debugged.
    case bot.mapKind
    of MapMain:
      bot.mainNav
    of MapHome:
      bot.homeNav
    else:
      if bot.mainNav != nil:
        bot.mainNav
      else:
        bot.homeNav

  proc navScale(nav: NavMap): float32 =
    ## Returns a map scale that fits the viewer map panel.
    if nav == nil or nav.width <= 0 or nav.height <= 0:
      return 1.0'f
    min(
      ViewerMapWidth / nav.width.float32,
      ViewerMapHeight / nav.height.float32
    )

  proc navSampleStep(scale: float32): int =
    ## Returns a walkability sampling step for the map panel.
    if scale < 0.25'f:
      8
    elif scale < 0.5'f:
      4
    elif scale < 1.0'f:
      2
    else:
      1

  proc drawMapRect(
    sk: Silky,
    rect: Rect,
    origin: Vec2,
    scale: float32,
    color: ColorRGBX,
    thickness = 1.0'f
  ) =
    ## Draws one map-space rectangle.
    sk.drawOutline(
      vec2(origin.x + rect.x.float32 * scale, origin.y + rect.y.float32 * scale),
      vec2(rect.w.float32 * scale, rect.h.float32 * scale),
      color,
      thickness
    )

  proc drawMapSquare(
    sk: Silky,
    rect: Rect,
    origin: Vec2,
    scale: float32,
    color: ColorRGBX,
    filled: bool
  ) =
    ## Draws one square marker centered on a map-space rectangle.
    let
      size = max(6.0'f, 8.0'f * scale)
      cx = origin.x + (rect.x + rect.w div 2).float32 * scale
      cy = origin.y + (rect.y + rect.h div 2).float32 * scale
      pos = vec2(cx - size / 2.0'f, cy - size / 2.0'f)
      square = vec2(size, size)
    if filled:
      sk.drawRect(pos, square, color)
    else:
      sk.drawOutline(pos, square, color)

  proc drawMapPath(sk: Silky, bot: Bot, origin: Vec2, scale: float32) =
    ## Draws the current A-star path over the map panel.
    if not bot.localized or bot.path.len == 0:
      return
    var previous = vec2(
      origin.x + bot.playerFootX().float32 * scale,
      origin.y + bot.playerFootY().float32 * scale
    )
    for i in countup(0, bot.path.high, 4):
      let current = vec2(
        origin.x + bot.path[i].x.float32 * scale,
        origin.y + bot.path[i].y.float32 * scale
      )
      sk.drawLine(previous, current, ViewerPath)
      previous = current
    if bot.goal.kind != GoalIdle:
      sk.drawLine(
        previous,
        vec2(
          origin.x + bot.goal.x.float32 * scale,
          origin.y + bot.goal.y.float32 * scale
        ),
        ViewerPath
      )

  proc drawMapView(sk: Silky, bot: Bot, x, y: float32) =
    ## Draws walkability, resources, actors, viewport, and path state.
    let
      nav = bot.activeNav()
      scale = nav.navScale()
      origin = vec2(x, y)
    sk.drawRect(origin, vec2(ViewerMapWidth, ViewerMapHeight), ViewerPanelAlt)
    if nav == nil:
      discard sk.drawText("Default", "waiting for walkability", origin,
        ViewerMutedText)
      return

    let step = navSampleStep(scale)
    for my in countup(0, nav.height - 1, step):
      for mx in countup(0, nav.width - 1, step):
        let color =
          if nav.walkAt(mx, my):
            ViewerWalk
          else:
            ViewerWall
        sk.drawRect(
          vec2(origin.x + mx.float32 * scale, origin.y + my.float32 * scale),
          vec2(
            max(1.0'f, step.float32 * scale),
            max(1.0'f, step.float32 * scale)
          ),
          color
        )

    if bot.mapKind == MapMain:
      for i, rect in bot.resources.gardens:
        let checked =
          i < bot.gardenChecked.len and bot.gardenChecked[i]
        sk.drawMapSquare(
          rect,
          origin,
          scale,
          ViewerGarden,
          not checked
        )
      for i, rect in bot.resources.houses:
        if bot.resources.houseValid[i]:
          sk.drawMapRect(rect, origin, scale, ViewerHouse)
    elif bot.mapKind == MapHome and bot.resources.hasExit:
      sk.drawMapRect(bot.resources.exit, origin, scale, ViewerExit, 2)

    if bot.localized:
      sk.drawMapRect(
        Rect(x: bot.cameraX, y: bot.cameraY, w: ViewportWidth, h: ViewportHeight),
        origin,
        scale,
        ViewerViewport
      )
    sk.drawMapPath(bot, origin, scale)
    if bot.goal.kind != GoalIdle:
      sk.drawRect(
        vec2(
          origin.x + bot.goal.x.float32 * scale - 4,
          origin.y + bot.goal.y.float32 * scale - 4
        ),
        vec2(9, 9),
        ViewerGoal
      )
    if bot.hasTarget:
      sk.drawRect(
        vec2(
          origin.x + bot.target.x.float32 * scale - 3,
          origin.y + bot.target.y.float32 * scale - 3
        ),
        vec2(7, 7),
        ViewerTarget
      )

    for objectId, objectState in bot.objects:
      if not objectState.present:
        continue
      if objectId < PlayerObjectBase or objectId >= NameObjectBase:
        continue
      let
        playerIndex = objectId - PlayerObjectBase
        color =
          if playerIndex == bot.selfIndex:
            ViewerPlayer
          else:
            ViewerOther
        worldX = bot.objectFootX(objectState)
        worldY = bot.objectFootY(objectState)
      sk.drawRect(
        vec2(
          origin.x + worldX.float32 * scale - 3,
          origin.y + worldY.float32 * scale - 3
        ),
        vec2(7, 7),
        color
      )
      let playerName = bot.visiblePlayerName(playerIndex)
      if playerName.len > 0:
        discard sk.drawText(
          "Default",
          playerName,
          vec2(
            origin.x + worldX.float32 * scale + 5,
            origin.y + worldY.float32 * scale - 8
          ),
          ViewerText
        )

  proc refreshDisplayScale(viewer: ViewerApp) =
    ## Updates UI scaling after the viewer moves between displays.
    if viewer.isNil:
      return
    let scale = viewer.window.displayScale()
    if abs(scale - viewer.contentScale) <= 0.001'f:
      return
    viewer.contentScale = scale
    viewer.silky.uiScale = scale
    let logicalSize = (viewer.window.size.vec2 / scale).ivec2
    viewer.window.size = logicalSize.scaledWindowSize(scale)

  proc initViewerApp(): ViewerApp =
    ## Opens the diagnostic viewer window.
    result = ViewerApp()
    result.window = newWindow(
      title = "Heartleaf Talking Villager Viewer",
      size = ivec2(ViewerWindowWidth, ViewerWindowHeight),
      style = DecoratedResizable,
      visible = true
    )
    makeContextCurrent(result.window)
    when not defined(useDirectX):
      loadExtensions()
    result.silky = newSilky(result.window, atlasPath())
    result.contentScale = result.window.displayScale()
    result.silky.uiScale = result.contentScale
    result.window.size =
      ivec2(ViewerWindowWidth, ViewerWindowHeight).scaledWindowSize(
        result.contentScale
      )
    result.window.style = Decorated
    let viewer = result
    result.window.onResize = proc() =
      viewer.refreshDisplayScale()

  proc viewerOpen(viewer: ViewerApp): bool =
    ## Returns true while the optional viewer should keep running.
    viewer.isNil or not viewer.window.closeRequested

  proc pumpViewer(
    viewer: ViewerApp,
    bot: Bot,
    connected: bool,
    url: string
  ) =
    ## Pumps window events and draws one bot debugger frame.
    if viewer.isNil:
      return
    pollEvents()
    viewer.refreshDisplayScale()
    if viewer.window.buttonPressed[KeyEscape]:
      viewer.window.closeRequested = true
    if viewer.window.closeRequested:
      return

    let
      frameSize = viewer.window.size
      logicalSize = frameSize.vec2 / viewer.silky.uiScale
      framePos = vec2(ViewerMargin, ViewerMargin)
      mapPos = vec2(
        framePos.x + ViewportWidth.float32 * ViewerFrameScale + 24,
        ViewerMargin
      )
      infoPos = vec2(
        ViewerMargin,
        framePos.y + ViewportHeight.float32 * ViewerFrameScale + 28
      )
      inventoryPos = vec2(
        ViewerMargin,
        max(
          infoPos.y + 220.0'f,
          logicalSize.y - ViewerMargin - ViewerInventoryHeight
        )
      )
      inventorySize = vec2(
        logicalSize.x - ViewerMargin * 2,
        ViewerInventoryHeight
      )
      infoSize = vec2(
        logicalSize.x - ViewerMargin * 2,
        max(120.0'f, inventoryPos.y - infoPos.y - 16.0'f)
      )
      sk = viewer.silky

    sk.beginUI(viewer.window, frameSize)
    sk.clearScreen(ViewerBackground)
    sk.drawRect(
      framePos - vec2(8, 8),
      vec2(
        ViewportWidth.float32 * ViewerFrameScale + 16,
        ViewportHeight.float32 * ViewerFrameScale + 16
      ),
      ViewerPanel
    )
    sk.drawRect(
      mapPos - vec2(8, 8),
      vec2(ViewerMapWidth + 16, ViewerMapHeight + 16),
      ViewerPanel
    )
    sk.drawRect(infoPos - vec2(8, 8), infoSize + vec2(16, 16), ViewerPanel)
    sk.drawFrameView(bot, framePos.x, framePos.y)
    sk.drawMapView(bot, mapPos.x, mapPos.y)
    sk.drawInventoryPanel(bot, inventoryPos, inventorySize)

    let
      target =
        if bot.hasTarget:
          "(" & $bot.target.x & ", " & $bot.target.y & ")"
        else:
          "none"
      infoText =
        "intent: " & bot.goal.goalLabel() & "\n" &
        "status: " & (if connected: "connected" else: "reconnecting") & "\n" &
        "clock: " & bot.clockText() & " minutes=" & $bot.minutes & "\n" &
        "map: " & bot.mapKind.mapKindName() &
          " current house=" & $(bot.currentHouse + 1) &
          " home=" & $(bot.homeIndex + 1) & "\n" &
        "bot: " & bot.logName() &
          " slot=" & $bot.slot &
          " plan=" & bot.socialPlanName() &
          " food=" & $bot.inventoryTotal() &
          " host until=" & $bot.hostUntilMinutes & "\n" &
        "party house=" & $(bot.partyHouse + 1) &
          " search house=" & $(bot.searchHouse + 1) &
          " committed=" & $bot.hostCommitted & "\n" &
        "camera: (" & $bot.cameraX & ", " & $bot.cameraY & ")\n" &
        "player: (" & $bot.selfX & ", " & $bot.selfY & ")" &
          " foot=(" & $bot.playerFootX() & ", " &
          $bot.playerFootY() & ")" &
          " localized=" & $bot.localized & "\n" &
        "goal: " & bot.goal.goalLabel() &
          " pos=(" & $bot.goal.x & ", " & $bot.goal.y & ")" &
          " reached=" & $bot.goalReached(bot.goal) & "\n" &
        "path nodes: " & $bot.path.len & " target=" & target & "\n" &
        "input desired: " & inputMaskSummary(bot.desiredMask) &
          " last sent: " & inputMaskSummary(bot.lastMask) & "\n" &
        "stuck ticks: " & $bot.stuckTicks &
          " attack cooldown=" & $bot.attackCooldown & "\n" &
        "gardens marked=" & $bot.markedGardenCount() &
          " checked=" & $bot.checkedGardenCount() &
          "/" & $bot.gardenChecked.len &
          " current=" & $bot.currentGarden & "\n" &
        "sprites: " & $bot.sprites.len &
          " objects: " & $bot.objects.len &
          " frame tick: " & $bot.frameTick & "\n" &
        "url: " & url
    discard sk.drawText("Default", infoText, infoPos, ViewerText,
      infoSize.x, infoSize.y)
    sk.endUi()
    viewer.window.swapBuffers()

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

proc receiveUpdates(ws: WebSocket, bot: Bot, gui: bool): bool =
  ## Receives and applies all currently queued sprite updates.
  let firstMessage = ws.receiveMessage(if gui: 10 else: -1)
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
  gui: bool
) =
  ## Connects the talking Villager bot to a Heartleaf sprite player endpoint.
  let connectUrl =
    if url.len > 0:
      url
    else:
      playerUrl(host, port, name, token, slot)
  let useGui =
    when defined(gui):
      gui
    else:
      false
  var bot = initBot(name, slot, useGui)
  try:
    requireBedrockConfig()
  except TalkingVillagerError as e:
    echo "talking_villager fatal: ", e.msg
    quit(1)
  let viewer =
    if useGui:
      initViewerApp()
    else:
      nil
  var connected = false
  while viewer.viewerOpen():
    try:
      let ws = newWebSocket(connectUrl)
      echo "talking_villager connected to ", connectUrl
      connected = true
      bot.lastMask = 0xff'u8
      while viewer.viewerOpen():
        if not ws.receiveUpdates(bot, useGui):
          if useGui:
            viewer.pumpViewer(bot, connected, connectUrl)
            if not viewer.viewerOpen():
              ws.close()
              break
          continue
        let nextMask = bot.decideNextMask(ws)
        if bot.lastGreetingTick != bot.frameTick:
          bot.maybeSendDecisionChat(ws)
        if nextMask != bot.lastMask:
          ws.send(blobFromMask(nextMask), BinaryMessage)
          bot.lastMask = nextMask
        if useGui:
          viewer.pumpViewer(bot, connected, connectUrl)
          if not viewer.viewerOpen():
            ws.close()
            break
    except TalkingVillagerError as e:
      echo "talking_villager fatal: ", e.msg
      quit(1)
    except CatchableError as e:
      connected = false
      echo "talking_villager reconnecting: ", e.msg
      if useGui:
        for i in 0 ..< 25:
          if not viewer.viewerOpen():
            break
          viewer.pumpViewer(bot, connected, connectUrl)
          sleep(10)
      else:
        sleep(250)

when isMainModule:
  var
    address = DefaultHost
    port = DefaultPort
    name = DefaultName
    token = ""
    slot = -1
    url = getEnv("COGAMES_ENGINE_WS_URL")
    gui = false
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
      of "gui":
        gui = true
      else:
        discard
    else:
      discard
  if slot < 0 and url.len > 0:
    slot = url.slotFromUrl()
  runBot(address, port, name, token, slot, url, gui)
