import
  std/[json, os, random, strutils, tables, times],
  flatty, jsony, pixie,
  bitworld/aseprite, bitworld/pixelfonts, bitworld/spriteprotocol,
  bitworld/resources, bitworld/sprites,
  heartleaf/common, heartleaf/protocol, heartleaf/souls,
  heartleaf/observation, heartleaf/navigation,
  replays

when not defined(emscripten):
  import
    std/[locks, monotimes, sysrand],
    curly, mummy,
    bitworld/client as bitworldClient,
    bitworld/runtime,
    heartleaf/brains, heartleaf/bedrock_client

const
  DefaultSeed* = 0x484541
  DefaultMaxTicks = 0
  DefaultMaxGames = 0
  MainMapIndex = 0
  HomeMapIndexBase = 1
  DefaultSoulTimeoutSeconds* = 150
  CogamePlayerFailureUriEnv = "COGAME_PLAYER_FAILURE_URI"
  LogCursorPrefix = "log-cursor "
  FoodGridCols = 8
  FoodGridRows = 8
  DirectionCount = 4
  FoodVeggieCols = 8
  FoodMarkerCellX = 7
  FoodMarkerCellY = 7
  GardenStartFoodCount = 1
  MotionScale = 256
  Accel = 76
  FrictionNum = 144
  FrictionDen = 256
  MaxSpeed = 704
  StopThreshold = 8
  MovementSlideMaxScan = 3
  MinSpawnSpacing = 20
  SpawnScanStep = 4
  HouseSpawnMaxDistance = 96
  DinnerScreenTicks = 10 * TicksPerSecond
  DinnerTallyMinutes = DinnerMinutes
  DinnerEatRounds = 3
  NewFoodEatScore = 3
  LeftoverEatScore = 1
  DayStepMinutes = 5
  DayStepCount = DayTotalMinutes div DayStepMinutes
  DuskStartMinutes = 17 * 60
  DayTintCount = 5
  TargetFps = 24.0
  HealthzPath = "/healthz"
  WebSocketPath = "/player"
  GlobalWebSocketPath = "/global"
  ReplayWebSocketPath = "/replay"
  MaxWebSocketFrameBytes = 900_000
  MapLayerId = 0
  UiLayerId = 1
  ClockLayerId = 2
  GlobalPanelLayerId = 3
  ReplayCenterBottomLayerId = 4
  ReplayMismatchLayerId = 6
  MapLayerKind = 0
  GlobalPanelLayerKind = 1
  UiLayerKind = 3
  ClockLayerKind = 2
  ReplayCenterBottomLayerKind = 8
  ReplayMismatchLayerKind = 5
  MapLayerFlags = 1
  UiLayerFlags = 2
  ReplayPanelHeight = 27
  ReplayScrubberWidth = 300
  ReplayScrubberHeight = 5
  ReplayControlsBgAlpha = 204'u8
  ReplayScrubberTrackY = 2
  ReplayScrubberY = 15
  ReplayTickTextY = 4
  TransportButtonsX = 6
  TransportRowY = 4
  TransportButtonWidth = 12
  TransportButtonStride = 14
  TransportButtonCount = 4
  TransportRowHeight = 7
  TransportSpeedStride = 18
  TransportSpeedWidth = 16
  TransportSpeedLabels = ["1X", "2X", "3X", "4X", "8X", "16X"]
  TransportSpeedValues = [1, 2, 3, 4, 8, 16]
  TransportSpeedCommands = ['1', '2', '3', '4', '8', '6']
  SpeedRowX =
    ViewportWidth - TransportSpeedStride * TransportSpeedLabels.len - 6
  ReplayMismatchPadX = 4
  ReplayMismatchPadY = 3
  InventoryColumns = 8
  InventoryRows = (FoodVeggieSlots + InventoryColumns - 1) div InventoryColumns
  InventoryIconStep = 34
  InventoryUiWidth = InventoryColumns * InventoryIconStep
  InventoryUiHeight = InventoryRows * InventoryIconStep
  ClockUiWidth = 120
  ClockUiHeight = 12
  GlobalPanelWidth = 128
  GlobalPanelHeight = 128
  GlobalPanelPad = 2
  GlobalPanelRowHeight = 9
  GlobalPanelScoreX = 2
  GlobalPanelNameX = 22
  GlobalPanelTextR = 245'u8
  GlobalPanelTextG = 247'u8
  GlobalPanelTextB = 240'u8
  GlobalPanelScoreR = 185'u8
  GlobalPanelScoreG = 195'u8
  GlobalPanelScoreB = 205'u8
  GlobalPanelSelectedR = 255'u8
  GlobalPanelSelectedG = 226'u8
  GlobalPanelSelectedB = 92'u8
  ClockPadX = 2
  ClockPadY = 1
  ClockGlyphGap = 1
  OverlayFoodColumns = 8
  OverlayFoodStep = 34
  OverlayGuestColumns = 4
  OverlayGuestCellWidth = 78
  OverlayGuestCellHeight = 32
  OverlayScoreColumns = 3
  OverlayScoreCellWidth = 104
  OverlayScoreCellHeight = 54
  BottomSpriteId = 1
  OverhangSpriteId = 2
  HomeBottomSpriteId = 4
  HomeOverhangSpriteId = 5
  MainBottomTintSpriteBase = 10
  MainOverhangTintSpriteBase = MainBottomTintSpriteBase + DayTintCount
  HomeBottomTintSpriteBase = MainOverhangTintSpriteBase + DayTintCount
  HomeOverhangTintSpriteBase = HomeBottomTintSpriteBase + DayTintCount
  FoodSpriteBase = 400
  FoodMarkerSpriteId = FoodSpriteBase + FoodVeggieSlots
  PlayerSpriteBase = 100
  NameSpriteBase = 2000
  ChatSpriteBase = 3000
  InventoryCountSpriteBase = 4000
  ClockGlyphSpriteBase = 7000
  ScoreSpriteBase = 7100
  ReplayTickSpriteId = 8400
  ReplayScrubberSpriteId = 8401
  ReplayControlsSpriteId = 8402
  ReplayMismatchSpriteId = 8403
  ReplayPanelBgSpriteId = 8404
  GnomeOutlineSpriteBase = 8500
  TrailDotSpriteBase = 8600
  ReplayTickObjectId = 20_400
  ReplayScrubberObjectId = 20_401
  ReplayControlsObjectId = 20_402
  ReplayMismatchObjectId = 20_403
  ReplayPanelBgObjectId = 20_404
  HouseGnomeObjectBase = 21_000
  HouseGnomeBorderObjectBase = 21_100
  PlayerBorderObjectId = 21_200
  InsetBottomObjectId = 21_300
  InsetOverhangObjectId = 21_301
  InsetPlayerObjectBase = 21_400
  HouseGnomeZ = 20_500
  HouseGnomeLift = 12
  InsetBottomZ = 31_000
  InsetPlayerZBase = 31_100
  InsetOverhangZ = 31_500
  InsetNameZ = 31_600
  InsetChatZ = 31_601
  OutlinePad = 1
  TrailObjectBase = 24_000
  TrailZ = 50
  TrailSampleTicks = 6
  TrailMaxPoints = 5
  ChatBannerSpriteId = 8700
  ChatBannerObjectId = 25_000
  ChatFeedShowFrames = 96
  ChatFeedMaxItems = 400
  ChatBannerMaxHearers = 3
  ChatBannerNameGap = 10
  PortraitGridColumns = 3
  ChatBannerPortraitMargin = 10
  ChatBannerPortraitY = 2
  ChatBannerTextGap = 8
  ChatBannerAreaHeight = 64
  ReplayBarTotalHeight = ChatBannerAreaHeight + ReplayPanelHeight
  GlobalPanelScoreSpriteBase = 8200
  GlobalPanelNameSpriteBase = 8300
  GlobalPanelScoreObjectBase = 20_100
  GlobalPanelNameObjectBase = 20_200
  BottomZ = int(low(int16))
  OverhangZ = 20_000
  GardenMarkerZ = OverhangZ - 1
  NameZ = 30_000
  ChatZ = 30_001
  ScoreZ = 30_002
  NameMaxChars = 14
  ChatLifetimeTicks = 5 * 24
  ChatPad = 3
  ChatWrapChars = 40
  ChatPointerHeight = 3
  ChatGapY = 3
  NamePadX = 2
  NamePadY = 1
  NameGapY = 2
  TextBackR = 0x33'u8
  TextBackG = 0x31'u8
  TextBackB = 0x36'u8
  ClockGlyphs =
    "0123456789: " &
    "abcdefghijklmnopqrstuvwxyz" &
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  TintHueTargets = [0.80, 0.78, 0.75, 0.70, 0.64]
  TintHueMixes = [0.18, 0.30, 0.43, 0.57, 0.72]
  TintSaturationScales = [1.05, 1.12, 1.20, 1.30, 1.38]
  TintValueScales = [0.86, 0.70, 0.54, 0.39, 0.25]

type
  Direction = enum
    DirDown
    DirUp
    DirRight
    DirLeft

  HeartleafError* = object of ValueError

  Rect = common.Rect

  FoodCounts = array[FoodVeggieSlots, int]

  WorldMap = ref object
    width, height: int
    bottomSprite: RgbaSprite
    overhangSprite: RgbaSprite
    bottomTints: array[DayTintCount, RgbaSprite]
    overhangTints: array[DayTintCount, RgbaSprite]
    walkMask: seq[bool]

  GnomeSprites = ref object
    frames: array[Direction, RgbaSprite]

  FoodSprites = ref object
    icons: array[FoodVeggieSlots, RgbaSprite]
    marker: RgbaSprite

  Garden = object
    rect: Rect
    inventory: FoodCounts

  TrailPoint = object
    x, y: int
    mapIndex: int

  ChatFeedPerson = object
    name: string
    gnomeIndex: int

  ChatFeedItem = object
    speaker: ChatFeedPerson
    hearers: seq[ChatFeedPerson]
    message: string

  ChatBannerHearer = object
    portrait: RgbaSprite
    tag: RgbaSprite
    portraitX: int
    tagX: int

  House = object
    rect: Rect
    valid: bool

  HomeResources = ref object
    exit: Rect
    hasExit: bool
    washes: seq[Rect]
    cooks: seq[Rect]
    diners: seq[Rect]

  DinnerRecord = ref object
    hostName: string
    wasHost: bool
    foods: FoodCounts
    guestNames: seq[string]
    guestGnomeIndices: seq[int]
    guestCount: int
    score: int

  Player = ref object
    username: string
    playerName: string
    x, y: int
    velX, velY: int
    carryX, carryY: int
    inputX, inputY: int
    direction: Direction
    gnomeIndex: int
    homeFlag: int
    mapIndex: int
    inventory: FoodCounts
    eaten: array[FoodVeggieSlots, bool]
    dinners: seq[DinnerRecord]
    score: int
    dinnerTicks: int
    dinnerRecord: DinnerRecord
    message: string
    messageTicks: int
    attackDown: bool

  SpriteCacheEntry = ref object
    spriteId: int
    width: int
    height: int
    pixels: seq[uint8]

  SimServer* = ref object
    mainMap: WorldMap
    homeMaps: array[HouseCount, WorldMap]
    resourceRects: seq[ResourceRect]
    homeResourceRects: seq[ResourceRect]
    homeResources: HomeResources
    foods: FoodSprites
    gardens: seq[Garden]
    houses: array[HouseCount, House]
    gnomes: seq[GnomeSprites]
    players: seq[Player]
    seatCount*: int
      ## Player seats this game was configured for (the hosted token
      ## count). Results report exactly this many slots, so a 4-seat
      ## experience request does not get 9 scores.
    textFont: PixelFont
    rng: Rand
    tickCount*: int
    dayTick: int
    dayTicks: int
    dayNumber: int
    scoreTicks: int
    dinnerDone: bool
    playerInitPacket: seq[uint8]
    trails: seq[seq[TrailPoint]]  ## viewer-only history, never hashed
    chatBanner: RgbaSprite
    portraits: seq[RgbaSprite]
    chatFeed: seq[ChatFeedItem]   ## viewer-only delay chat, never hashed
    chatFeedIndex: int
    chatFeedFrames: int

  KeyframeState = object
    ## Dynamic simulation state stored in one replay keyframe. Static
    ## assets (maps, sprites, fonts, init packet) are never serialized.
    players: seq[Player]
    gardens: seq[Garden]
    houses: array[HouseCount, House]
    rng: Rand
    tickCount: int
    dayTick: int
    dayTicks: int
    dayNumber: int
    scoreTicks: int
    dinnerDone: bool

  PlayerViewerState* = ref object
    initialized: bool
    selectedPlayerIndex: int
    selectedHouseNumber: int  ## 0 = none, 1..HouseCount = house interior view
    pendingMapClick: bool
    pendingMapClickX: int
    pendingMapClickY: int
    spriteCache: seq[SpriteCacheEntry]
    mouseX: int
    mouseY: int
    mouseLayer: int
    mouseDown: bool
    clickPending: bool
    mousePressX: int
    mousePressY: int
    mousePressLayer: int
    scrubbingReplay: bool
    replaySeekTick: int
    replayCommands: seq[char]

  RunConfig = ref object
    address: string
    port: int
    seed: int
    maxTicks: int
    maxDays: int
      ## Game length in days, score screens included; overrides maxTicks.
    maxGames: int
    daySeconds: int
    tokens: seq[string]
    playerNames: seq[string]
      ## Per-slot display names from `players[].name`, filled by hosted
      ## dispatch with the policy or player name behind each slot.
    soulTimeoutSeconds: int
      ## How long the village waits for every seat's soul before day 1.
    soulConnectionRequired: bool
      ## Whether a seat whose socket drops after its soul is a player failure.
    mockReply: string
      ## Offline stand-in for the model, for certification and smoke runs
      ## only; empty in every hosted variant.

when not defined(emscripten):
  type
    WebSocketAppState = ref object
      lock: Lock
      playerSlots: Table[WebSocket, int]
        ## Seat requested by each /player socket, -1 for any free seat.
      globalViewers: Table[WebSocket, PlayerViewerState]
      replayViewers: Table[WebSocket, PlayerViewerState]
      playerUsernames: Table[WebSocket, string]
      souls: Table[int, Soul]
        ## Accepted soul per seat; a seat comes alive when its soul arrives.
      soulSockets: Table[WebSocket, int]
        ## Seat whose soul each socket delivered.
      logSent: Table[WebSocket, int]
        ## How many of the seat's log entries each soul socket has received.
      gameNumber: int
        ## One-based game of this process, matching the log records.
      closedSockets: seq[WebSocket]
      tokens: seq[string]
      playerNames: seq[string]
      replayServerMode: bool
      replayLoaded: bool
      pendingReplayUri: string

    ServerThreadArgs = ref object
      server: ptr Server
      address: string
      port: int

  var appState: WebSocketAppState

proc addSpriteProtocolInit(
  packet: var seq[uint8],
  sim: SimServer,
  viewportWidth,
  viewportHeight: int,
  globalPanel = false
)

proc dataDir(): string =
  ## Returns the Heartleaf data directory.
  let cwdData = getCurrentDir() / "data"
  if fileExists(cwdData / "map.aseprite"):
    return cwdData
  let repoData = getCurrentDir() / "heartleaf" / "data"
  if fileExists(repoData / "map.aseprite"):
    return repoData
  let sourceData = currentSourcePath().parentDir().parentDir() / "data"
  if fileExists(sourceData / "map.aseprite"):
    return sourceData
  return currentSourcePath().parentDir() / "data"

proc layerIndexByName(
  aseprite: AsepriteSprite,
  names: openArray[string]
): int =
  ## Returns the first layer index matching one of the given names.
  for i, layer in aseprite.layers:
    for name in names:
      if layer.name.normalize() == name.normalize():
        return i
  return -1

proc requiredLayerIndex(
  aseprite: AsepriteSprite,
  names: openArray[string],
  label: string
): int =
  ## Returns a named layer index or raises a Heartleaf error.
  result = aseprite.layerIndexByName(names)
  if result < 0:
    raise newException(
      HeartleafError,
      "Map aseprite needs a " & label & " layer."
    )

proc houseIndex(rect: ResourceRect): int =
  ## Returns the zero-based house index for one resource rectangle.
  rect.rectName().houseIndexFromName()

proc loadHouses(rects: openArray[ResourceRect]): array[HouseCount, House] =
  ## Loads numbered house rectangles from parsed resource data.
  for rect in rects:
    let index = rect.houseIndex()
    if index >= 0:
      result[index] = House(rect: rect.toRect(), valid: true)

proc loadHomeResources(rects: openArray[ResourceRect]): HomeResources =
  ## Loads named interaction rectangles from home resource data.
  result = HomeResources()
  for rect in rects:
    case rect.rectName()
    of "exit":
      result.exit = rect.toRect()
      result.hasExit = true
    of "wash":
      result.washes.add(rect.toRect())
    of "cook":
      result.cooks.add(rect.toRect())
    of "diner", "diners":
      result.diners.add(rect.toRect())
    else:
      discard

proc loadGardens(
  rects: openArray[ResourceRect],
  rng: var Rand
): seq[Garden] =
  ## Loads garden rectangles and gives each garden one food item.
  for rect in rects:
    if rect.rectName() == "garden":
      var garden = Garden(rect: rect.toRect())
      for i in 0 ..< GardenStartFoodCount:
        inc garden.inventory[rng.rand(FoodVeggieSlots - 1)]
      result.add(garden)

proc loadWalkMask(walkImage: Image): seq[bool] =
  ## Builds a per-pixel walk mask from an alpha layer.
  result = newSeq[bool](walkImage.width * walkImage.height)
  for y in 0 ..< walkImage.height:
    for x in 0 ..< walkImage.width:
      result[y * walkImage.width + x] = walkImage[x, y].a > 0

proc loadWorldMap(path, label: string): WorldMap =
  ## Loads one layered map with bottom, walkable, and overhang data.
  result = WorldMap()
  let aseprite = readAseprite(path)
  if aseprite.layers.len < 2:
    raise newException(
      HeartleafError,
      label & " aseprite needs a bottom and walkable layer."
    )

  let
    bottomLayer = max(0, aseprite.layerIndexByName(["bottom"]))
    walkLayer = aseprite.requiredLayerIndex(
      ["walkable", "walk"],
      "walkable"
    )
    overhangLayer = aseprite.layerIndexByName(["overhang"])
    bottomImage = aseprite.layerImage(bottomLayer)
    walkImage = aseprite.layerImage(walkLayer)
  result.width = aseprite.header.width
  result.height = aseprite.header.height
  result.bottomSprite = bottomImage.imageRgbaSprite()
  result.overhangSprite =
    if overhangLayer >= 0:
      aseprite.layerImage(overhangLayer).imageRgbaSprite()
    else:
      transparentRgbaSprite(result.width, result.height)
  for i in 0 ..< DayTintCount:
    result.bottomTints[i] = result.bottomSprite.hsvTinted(
      TintHueTargets[i],
      TintHueMixes[i],
      TintSaturationScales[i],
      TintValueScales[i]
    )
    result.overhangTints[i] = result.overhangSprite.hsvTinted(
      TintHueTargets[i],
      TintHueMixes[i],
      TintSaturationScales[i],
      TintValueScales[i]
    )
  result.walkMask = walkImage.loadWalkMask()

proc loadGnomeSprites(path: string): seq[GnomeSprites] =
  ## Loads all gnome direction sets from the sheet.
  let image = readAsepriteImage(path)
  if image.width mod GnomeSpriteSize != 0 or
      image.height mod GnomeSpriteSize != 0:
    raise newException(
      HeartleafError,
      "Gnome sheet dimensions must be multiples of " & $GnomeSpriteSize & "."
    )

  let
    cols = image.width div GnomeSpriteSize
    rows = image.height div GnomeSpriteSize
    spriteCount = cols * rows
  if spriteCount < DirectionCount or spriteCount mod DirectionCount != 0:
    raise newException(
      HeartleafError,
      "Gnome sheet must contain groups of four direction sprites."
    )

  result = newSeq[GnomeSprites](spriteCount div DirectionCount)
  for i in 0 ..< result.len:
    result[i] = GnomeSprites()
  for i in 0 ..< spriteCount:
    let
      cellX = i mod cols
      cellY = i div cols
      group = i div DirectionCount
      slot = i mod DirectionCount
      sprite = image.cellRgbaSprite(cellX, cellY, GnomeSpriteSize)
    case slot
    of 0:
      result[group].frames[DirDown] = sprite
    of 1:
      result[group].frames[DirUp] = sprite
    of 2:
      result[group].frames[DirRight] = sprite
    else:
      result[group].frames[DirLeft] = sprite

proc loadFoodSprites(path: string): FoodSprites =
  ## Loads veggie icons and the garden marker from the food sheet.
  result = FoodSprites()
  let image = readAsepriteImage(path)
  if image.width < FoodGridCols * FoodSpriteSize or
      image.height < FoodGridRows * FoodSpriteSize:
    raise newException(
      HeartleafError,
      "Food sheet must contain an 8x8 grid of 32px sprites."
    )

  for i in 0 ..< FoodVeggieSlots:
    let
      cellX = i mod FoodVeggieCols
      cellY = i div FoodVeggieCols
    result.icons[i] = image.cellRgbaSprite(cellX, cellY, FoodSpriteSize)
  result.marker = image.cellRgbaSprite(
    FoodMarkerCellX,
    FoodMarkerCellY,
    FoodSpriteSize
  )

proc loadChatBanner(path: string): RgbaSprite =
  ## Loads and crops the delay-chat banner art to its solid bounds.
  if not fileExists(path):
    return newRgbaSprite(0, 0)
  let
    full = imageRgbaSprite(readAsepriteImage(path))
    bounds = full.solidBounds()
  if not bounds.found:
    return newRgbaSprite(0, 0)
  result = newRgbaSprite(
    bounds.maxX - bounds.minX + 1,
    bounds.maxY - bounds.minY + 1
  )
  for y in 0 ..< result.height:
    for x in 0 ..< result.width:
      result.putPixel(
        x,
        y,
        full.rgbaSpriteAt(bounds.minX + x, bounds.minY + y)
      )

proc loadPortraits(dataRoot: string): seq[RgbaSprite] =
  ## Loads the gnome profile portraits used by the delay chat banner
  ## from a 3x3 grid sheet.
  let path = dataRoot / "gnome_faces.aseprite"
  if not fileExists(path):
    return
  let image = readAsepriteImage(path)
  if image.width mod PortraitGridColumns != 0:
    raise newException(
      HeartleafError,
      "Gnome faces sheet width must be a multiple of " &
        $PortraitGridColumns & "."
    )
  let cellSize = image.width div PortraitGridColumns
  for i in 0 ..< HouseCount:
    result.add(image.cellRgbaSprite(
      i mod PortraitGridColumns,
      i div PortraitGridColumns,
      cellSize
    ))

proc initSimServer*(seed = DefaultSeed, dayTicks = DayTicks): SimServer =
  ## Initializes the Heartleaf simulation.
  result = SimServer()
  result.dayTicks = max(TicksPerSecond, dayTicks)
  result.seatCount = HouseCount
  let dataRoot = dataDir()
  # Keep asset paths explicit here so startup shows what the game needs.
  let
    mapPath = dataRoot / "map.aseprite"
    homeMapPath = dataRoot / "home_map.aseprite"
    gnomesPath = dataRoot / "gnomes.aseprite"
    foodPath = dataRoot / "food.aseprite"
    resourcePath = dataRoot / "map.resource"
    homeResourcePath = dataRoot / "home_map.resource"
    tiny5Path = dataRoot / "tiny5.aseprite"
  result.rng = initRand(seed)
  result.resourceRects = loadResourceRects(resourcePath)
  result.homeResourceRects = loadResourceRects(homeResourcePath)
  result.homeResources = loadHomeResources(result.homeResourceRects)
  result.mainMap = loadWorldMap(mapPath, "Map")
  let homeMap = loadWorldMap(homeMapPath, "Home map")
  for i in 0 ..< HouseCount:
    result.homeMaps[i] = homeMap
  result.houses = loadHouses(result.resourceRects)
  result.gardens = loadGardens(result.resourceRects, result.rng)
  result.foods = loadFoodSprites(foodPath)
  result.gnomes = loadGnomeSprites(gnomesPath)
  if result.gnomes.len == 0:
    raise newException(HeartleafError, "Gnome sheet has no gnomes.")
  result.textFont = readPixelFont(tiny5Path)
  result.chatBanner = loadChatBanner(dataRoot / "chatbanner.aseprite")
  result.portraits = loadPortraits(dataRoot)
  result.chatFeedIndex = -1
  result.players = @[]
  result.dayNumber = 1
  result.playerInitPacket.addSpriteProtocolInit(
    result,
    ViewportWidth,
    ViewportHeight,
    true
  )

proc addRgbaSprite(
  packet: var seq[uint8],
  spriteId: int,
  sprite: RgbaSprite,
  label: string
) =
  ## Appends one RGBA sprite definition.
  packet.addSprite(spriteId, sprite.width, sprite.height, sprite.pixels, label)

proc addRgbaSpriteCached(
  packet: var seq[uint8],
  cache: var seq[SpriteCacheEntry],
  spriteId: int,
  sprite: RgbaSprite,
  label: string
) =
  ## Appends one RGBA sprite only when its pixels changed.
  for item in cache.mitems:
    if item.spriteId != spriteId:
      continue
    if item.width == sprite.width and
        item.height == sprite.height and
        item.pixels.pixelsMatch(sprite.pixels):
      return
    packet.addRgbaSprite(spriteId, sprite, label)
    item.width = sprite.width
    item.height = sprite.height
    item.pixels = sprite.pixels.copyPixels()
    return

  packet.addRgbaSprite(spriteId, sprite, label)
  cache.add(SpriteCacheEntry(
    spriteId: spriteId,
    width: sprite.width,
    height: sprite.height,
    pixels: sprite.pixels.copyPixels()
  ))

when not defined(emscripten):
  proc sendSpritePacket(websocket: WebSocket, packet: seq[uint8]) =
    ## Sends sprite protocol messages in certification-sized frames.
    var start = 0
    while start < packet.len:
      var stop = start
      while stop < packet.len:
        let messageBytes = packet.spriteMessageBytes(stop)
        if messageBytes <= 0:
          stop = packet.len
          break
        if stop > start and
            stop + messageBytes - start > MaxWebSocketFrameBytes:
          break
        stop += messageBytes
        if stop - start >= MaxWebSocketFrameBytes:
          break
      if stop == start:
        let messageBytes = packet.spriteMessageBytes(start)
        stop =
          if messageBytes > 0:
            start + messageBytes
          else:
            packet.len
      websocket.send(blobFromBytes(packet.toOpenArray(start, stop - 1)),
        BinaryMessage)
      start = stop

proc rectVisible(
  x,
  y,
  w,
  h,
  viewportWidth,
  viewportHeight: int
): bool =
  ## Returns true when one rectangle overlaps one viewport size.
  x < viewportWidth and y < viewportHeight and x + w > 0 and y + h > 0

proc chatTextWidth(sim: SimServer, text: string): int =
  ## Returns the rendered width of one chat line.
  sim.textFont.textWidth(text)

proc blitChatGlyph(
  target: var RgbaSprite,
  glyph: PixelGlyph,
  x, y: int,
  color: ColorRGBA
) =
  ## Blits one Tiny5 glyph into a sprite.
  for gy in 0 ..< glyph.height:
    for gx in 0 ..< glyph.width:
      if glyph.glyphPixel(gx, gy):
        target.putPixel(x + gx, y + gy, color)

proc blitTinyText(
  sim: SimServer,
  target: var RgbaSprite,
  text: string,
  x, y: int,
  color: ColorRGBA
) =
  ## Blits one Tiny5 text line into a sprite.
  var dx = x
  for ch in text:
    let glyph = sim.textFont.glyphAt(ch)
    target.blitChatGlyph(glyph, dx, y, color)
    dx += sim.textFont.glyphAdvance(ch)

proc blitChatText(
  sim: SimServer,
  target: var RgbaSprite,
  text: string,
  x, y: int
) =
  ## Blits white Tiny5 text into a sprite.
  sim.blitTinyText(target, text, x, y, rgba(255, 255, 255, 255))

proc chatBubbleLines(text: string): seq[string] =
  ## Wraps one chat message on spaces after the wrap width.
  var remaining = text
  while remaining.len > ChatWrapChars:
    var breakAt = -1
    for i in ChatWrapChars ..< remaining.len:
      if remaining[i] == ' ':
        breakAt = i
        break
    if breakAt <= 0 or breakAt >= remaining.len - 1:
      break
    result.add(remaining[0 ..< breakAt])
    remaining = remaining[breakAt + 1 .. ^1]
  result.add(remaining)

proc speechBubbleSprite(sim: SimServer, text: string): RgbaSprite =
  ## Builds one speech bubble sprite for a player message.
  let
    lines = chatBubbleLines(text)
    lineHeight = sim.textFont.height
  var textWidth = 6
  for line in lines:
    textWidth = max(textWidth, sim.chatTextWidth(line))
  let
    bodyWidth = textWidth + ChatPad * 2
    bodyHeight = lineHeight * lines.len + ChatPad * 2
    fill = rgba(TextBackR, TextBackG, TextBackB, 255)
  result = newRgbaSprite(bodyWidth, bodyHeight + ChatPointerHeight)
  result.fillRect(0, 0, bodyWidth, bodyHeight, fill)
  let pointerX = bodyWidth div 2
  for y in 0 ..< ChatPointerHeight:
    let span = ChatPointerHeight - y - 1
    for x in pointerX - span .. pointerX + span:
      result.putPixel(x, bodyHeight + y, fill)
  for i, line in lines:
    sim.blitChatText(
      result,
      line,
      ChatPad + (textWidth - sim.chatTextWidth(line)) div 2,
      ChatPad + i * lineHeight
    )

proc nameTagSprite(sim: SimServer, text: string): RgbaSprite =
  ## Builds one compact player name tag sprite.
  let
    width = max(1, sim.textFont.textWidth(text) + NamePadX * 2)
    height = sim.textFont.height + NamePadY * 2
    fill = rgba(TextBackR, TextBackG, TextBackB, 255)
  result = newRgbaSprite(width, height)
  result.fillRect(0, 0, width, height, fill)
  sim.blitChatText(result, text, NamePadX, NamePadY)

proc inventoryCountSprite(sim: SimServer, count: int): RgbaSprite =
  ## Builds one compact inventory count sprite.
  let
    text = $count
    width = max(1, sim.textFont.textWidth(text) + NamePadX * 2)
    height = sim.textFont.height + NamePadY * 2
    fill = rgba(TextBackR, TextBackG, TextBackB, 255)
  result = newRgbaSprite(width, height)
  result.fillRect(0, 0, width, height, fill)
  sim.blitChatText(result, text, NamePadX, NamePadY)

proc clockGlyphWidth(sim: SimServer, ch: char): int =
  ## Returns the rendered sprite width for one clock glyph.
  max(1, sim.textFont.textWidth($ch) + ClockPadX * 2)

proc clockGlyphSprite(sim: SimServer, ch: char): RgbaSprite =
  ## Builds one individual clock glyph sprite.
  let
    width = sim.clockGlyphWidth(ch)
    height = sim.textFont.height + ClockPadY * 2
    fill = rgba(TextBackR, TextBackG, TextBackB, 220)
  result = newRgbaSprite(width, height)
  result.fillRect(0, 0, width, height, fill)
  sim.blitChatText(result, $ch, ClockPadX, ClockPadY)

proc overlaySprite(): RgbaSprite =
  ## Builds one fully black viewport-sized overlay sprite.
  result = newRgbaSprite(ViewportWidth, ViewportHeight)
  result.fillRect(
    0,
    0,
    ViewportWidth,
    ViewportHeight,
    rgba(0, 0, 0, 255)
  )

proc drawFoodCounts(
  sim: SimServer,
  target: var RgbaSprite,
  foods: FoodCounts,
  x,
  y: int
) =
  ## Draws food icons with their item counts.
  var slot = 0
  for foodIndex, count in foods:
    if count <= 0:
      continue
    let
      col = slot mod OverlayFoodColumns
      row = slot div OverlayFoodColumns
      iconX = x + col * OverlayFoodStep
      iconY = y + row * OverlayFoodStep
    if iconY + FoodSpriteSize > ViewportHeight:
      return
    target.blitRgbaSprite(sim.foods.icons[foodIndex], iconX, iconY)
    let countSprite = sim.inventoryCountSprite(count)
    target.blitRgbaSprite(
      countSprite,
      iconX + FoodSpriteSize - countSprite.width,
      iconY + FoodSpriteSize - countSprite.height
    )
    inc slot

proc drawDinnerGuests(
  sim: SimServer,
  target: var RgbaSprite,
  record: DinnerRecord,
  x,
  y: int
) =
  ## Draws gnome icons with names for fed dinner guests.
  for i, name in record.guestNames:
    let
      col = i mod OverlayGuestColumns
      row = i div OverlayGuestColumns
      iconX = x + col * OverlayGuestCellWidth
      iconY = y + row * OverlayGuestCellHeight
    if iconY + GnomeSpriteSize > ViewportHeight:
      return
    if i < record.guestGnomeIndices.len:
      let gnomeIndex = record.guestGnomeIndices[i]
      if gnomeIndex >= 0 and gnomeIndex < sim.gnomes.len:
        target.blitRgbaSprite(
          sim.gnomes[gnomeIndex].frames[DirDown],
          iconX,
          iconY
        )
    sim.blitChatText(target, name, iconX + GnomeSpriteSize + 2, iconY + 12)

proc dinnerOverlaySprite(sim: SimServer, record: DinnerRecord): RgbaSprite =
  ## Builds the full-screen dinner result overlay.
  result = overlaySprite()
  if record.wasHost:
    sim.blitChatText(result, "During dinner party you fed:", 8, 4)
    sim.blitChatText(result, "+" & $record.score & " score", 8, 16)
    sim.blitChatText(result, "Guests: " & $record.guestCount, 8, 27)
    sim.drawDinnerGuests(result, record, 8, 36)
    sim.drawFoodCounts(result, record.foods, 8, 100)
  else:
    sim.blitChatText(result, "At dinner party you ate:", 8, 8)
    sim.blitChatText(result, "+" & $record.score & " score", 8, 20)
    sim.blitChatText(result, "Host: " & record.hostName, 8, 32)
    sim.drawFoodCounts(result, record.foods, 8, 44)

proc scoreDisplayName(player: Player): string =
  ## Returns the score-screen name with username and player name.
  if player.username.len == 0:
    return player.playerName
  return player.username & " (" & player.playerName & ")"

proc scoreOverlaySprite(sim: SimServer): RgbaSprite =
  ## Builds the full-screen cumulative score overlay.
  result = overlaySprite()
  sim.blitChatText(result, "End of day scores", 8, 8)
  for i, player in sim.players:
    let
      col = i mod OverlayScoreColumns
      row = i div OverlayScoreColumns
      x = 8 + col * OverlayScoreCellWidth
      y = 28 + row * OverlayScoreCellHeight
    if y + GnomeSpriteSize > ViewportHeight:
      return
    result.blitRgbaSprite(
      sim.gnomes[player.gnomeIndex].frames[DirDown],
      x,
      y
    )
    sim.blitChatText(
      result,
      player.scoreDisplayName(),
      x,
      y + GnomeSpriteSize + 2
    )
    sim.blitChatText(result, "Score: " & $player.score, x + 36, y + 12)

proc globalPanelTextSprite(
  sim: SimServer,
  text: string,
  color: ColorRGBA
): RgbaSprite =
  ## Builds one Tiny5 text sprite for the global score panel.
  result = newRgbaSprite(
    max(1, sim.textFont.textWidth(text)),
    sim.textFont.height
  )
  sim.blitTinyText(result, text, 0, 0, color)

proc globalPanelScoreText(score: int): string =
  ## Returns one global panel score label.
  $max(0, score)

proc selectedGlobalPlayerIndex(state: PlayerViewerState, sim: SimServer): int =
  ## Returns the selected global player index clamped to connected players.
  if sim.players.len == 0:
    return -1
  result = state.selectedPlayerIndex
  if result < 0:
    return -1
  if result >= sim.players.len:
    return -1

proc addGlobalScorePanel(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  selectedIndex: int
) =
  ## Appends the global top-left score and selection panel.
  if sim.players.len == 0:
    return
  for i, player in sim.players:
    let
      rowY = GlobalPanelPad + i * GlobalPanelRowHeight
      scoreText = player.score.globalPanelScoreText()
      scoreSpriteId = GlobalPanelScoreSpriteBase + i
      nameSpriteId = GlobalPanelNameSpriteBase + i
      nameColor =
        if i == selectedIndex:
          rgba(
            GlobalPanelSelectedR,
            GlobalPanelSelectedG,
            GlobalPanelSelectedB,
            255
          )
        else:
          rgba(GlobalPanelTextR, GlobalPanelTextG, GlobalPanelTextB, 255)
    if rowY + GlobalPanelRowHeight > GlobalPanelHeight:
      return
    packet.addRgbaSpriteCached(
      cache,
      scoreSpriteId,
      sim.globalPanelTextSprite(
        scoreText,
        rgba(GlobalPanelScoreR, GlobalPanelScoreG, GlobalPanelScoreB, 255)
      ),
      "global value " & $i & " " & scoreText
    )
    packet.addRgbaSpriteCached(
      cache,
      nameSpriteId,
      sim.globalPanelTextSprite(player.scoreDisplayName(), nameColor),
      "global name " & player.scoreDisplayName()
    )
    packet.addObject(
      GlobalPanelScoreObjectBase + i,
      GlobalPanelScoreX,
      rowY,
      1,
      GlobalPanelLayerId,
      scoreSpriteId
    )
    packet.addObject(
      GlobalPanelNameObjectBase + i,
      GlobalPanelNameX,
      rowY,
      2,
      GlobalPanelLayerId,
      nameSpriteId
    )

proc addNameTag(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  player: Player,
  playerIndex,
  screenX,
  screenY,
  z,
  viewportWidth,
  viewportHeight: int
): int =
  ## Appends a player name tag and returns its top y coordinate.
  let
    tag = sim.nameTagSprite(player.playerName)
    x = screenX + GnomeSpriteSize div 2 - tag.width div 2
    y = screenY - tag.height - NameGapY
    spriteId = NameSpriteBase + playerIndex
  if not rectVisible(
    x,
    y,
    tag.width,
    tag.height,
    viewportWidth,
    viewportHeight
  ):
    return y
  packet.addRgbaSpriteCached(cache, spriteId, tag, NameLabelPrefix & player.playerName)
  packet.addObject(
    NameObjectBase + playerIndex,
    x,
    y,
    z,
    MapLayerId,
    spriteId
  )
  return y

proc addSpeechBubble(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  player: Player,
  playerIndex,
  screenX,
  anchorY,
  z,
  viewportWidth,
  viewportHeight: int
) =
  ## Appends a speech bubble object above one player name.
  if player.message.len == 0 or player.messageTicks <= 0:
    return
  let
    bubble = sim.speechBubbleSprite(player.message)
    x = screenX + GnomeSpriteSize div 2 - bubble.width div 2
    y = anchorY - bubble.height - ChatGapY
    spriteId = ChatSpriteBase + playerIndex
  if not rectVisible(
    x,
    y,
    bubble.width,
    bubble.height,
    viewportWidth,
    viewportHeight
  ):
    return
  packet.addRgbaSpriteCached(cache, spriteId, bubble, ChatLabelPrefix & player.message)
  packet.addObject(
    ChatObjectBase + playerIndex,
    x,
    y,
    z,
    MapLayerId,
    spriteId
  )

proc directionLabel(direction: Direction): string =
  ## Returns the sprite label for one direction.
  case direction
  of DirDown:
    "down"
  of DirUp:
    "up"
  of DirRight:
    "right"
  of DirLeft:
    "left"

proc playerSpriteId(gnomeIndex: int, direction: Direction): int =
  ## Returns the sprite id for one gnome direction.
  PlayerSpriteBase + gnomeIndex * DirectionCount + ord(direction)

proc foodSpriteId(foodIndex: int): int =
  ## Returns the sprite id for one veggie inventory icon.
  FoodSpriteBase + foodIndex

proc mainBottomSpriteId(tintIndex: int): int =
  ## Returns the main map bottom sprite id for one day tint.
  if tintIndex < 0:
    return BottomSpriteId
  return MainBottomTintSpriteBase + tintIndex

proc mainOverhangSpriteId(tintIndex: int): int =
  ## Returns the main map overhang sprite id for one day tint.
  if tintIndex < 0:
    return OverhangSpriteId
  return MainOverhangTintSpriteBase + tintIndex

proc homeBottomSpriteId(tintIndex: int): int =
  ## Returns the home map bottom sprite id for one day tint.
  if tintIndex < 0:
    return HomeBottomSpriteId
  return HomeBottomTintSpriteBase + tintIndex

proc homeOverhangSpriteId(tintIndex: int): int =
  ## Returns the home map overhang sprite id for one day tint.
  if tintIndex < 0:
    return HomeOverhangSpriteId
  return HomeOverhangTintSpriteBase + tintIndex

proc clockGlyphIndex(ch: char): int =
  ## Returns the compact clock sprite slot for one glyph.
  for i, glyph in ClockGlyphs:
    if glyph == ch:
      return i
  for i, glyph in ClockGlyphs:
    if glyph == ' ':
      return i
  return 0

proc clockGlyphSpriteId(ch: char): int =
  ## Returns the sprite id for one clock glyph.
  ClockGlyphSpriteBase + ch.clockGlyphIndex()

proc dailyResultsJson*(sim: SimServer): string =
  ## Returns one daily player score result as JSON.
  var
    names = newJArray()
    usernames = newJArray()
    playerNames = newJArray()
    scores = newJArray()
    results = newJObject()
  for houseIndex in 0 ..< sim.seatCount:
    let fixedPlayerName = houseIndex.playerNameForHouse()
    var player: Player = nil
    for candidate in sim.players:
      if candidate.homeFlag == HomeMapIndexBase + houseIndex:
        player = candidate
        break
    if player != nil:
      names.add(%player.scoreDisplayName())
      usernames.add(%player.username)
      playerNames.add(%player.playerName)
      scores.add(%player.score)
    else:
      names.add(%fixedPlayerName)
      usernames.add(%"")
      playerNames.add(%fixedPlayerName)
      scores.add(%0)
  results["day"] = %sim.dayNumber
  results["names"] = names
  results["usernames"] = usernames
  results["playerNames"] = playerNames
  results["scores"] = scores
  return $results

proc totalItems(foods: FoodCounts): int =
  ## Returns the total number of items in one food count set.
  for count in foods:
    result += count

proc clearFoods(foods: var FoodCounts) =
  ## Clears one food count set.
  for i in 0 ..< FoodVeggieSlots:
    foods[i] = 0

proc isHomeMap(mapIndex: int): bool =
  ## Returns true when a map id points at one of the nine home maps.
  mapIndex >= HomeMapIndexBase and mapIndex < HomeMapIndexBase + HouseCount

proc homeMapIndex(houseIndex: int): int =
  ## Converts a zero-based house index to its one-based home map id.
  HomeMapIndexBase + houseIndex

proc mapFor(sim: SimServer, mapIndex: int): WorldMap =
  ## Returns the live world map data for one map id.
  if mapIndex.isHomeMap():
    return sim.homeMaps[mapIndex - HomeMapIndexBase]
  return sim.mainMap

proc currentDayMinutes(sim: SimServer): int =
  ## Returns the current in-game minute of the day.
  let step = min(DayStepCount, sim.dayTick * DayStepCount div sim.dayTicks)
  return DayStartMinutes + step * DayStepMinutes

proc clockText(sim: SimServer): string =
  ## Returns the current weekday and game clock as 12-hour text.
  sim.dayNumber.weekdayName() & " " & sim.currentDayMinutes().clockName()

proc dayTintIndex(sim: SimServer): int =
  ## Returns the active dusk tint index, or -1 during full daylight.
  let minutes = sim.currentDayMinutes()
  if minutes < DuskStartMinutes:
    return -1
  return min(
    DayTintCount - 1,
    (minutes - DuskStartMinutes) * DayTintCount div
      (DayEndMinutes - DuskStartMinutes)
  )

proc addSpriteProtocolInit(
  packet: var seq[uint8],
  sim: SimServer,
  viewportWidth,
  viewportHeight: int,
  globalPanel = false
) =
  ## Appends static sprite protocol setup for one viewer.
  packet.addViewport(MapLayerId, viewportWidth, viewportHeight)
  packet.addViewport(UiLayerId, InventoryUiWidth, InventoryUiHeight)
  packet.addViewport(ClockLayerId, ClockUiWidth, ClockUiHeight)
  if globalPanel:
    packet.addViewport(
      GlobalPanelLayerId,
      GlobalPanelWidth,
      GlobalPanelHeight
    )
  packet.addLayer(MapLayerId, MapLayerKind, MapLayerFlags)
  packet.addLayer(UiLayerId, UiLayerKind, UiLayerFlags)
  packet.addLayer(ClockLayerId, ClockLayerKind, UiLayerFlags)
  if globalPanel:
    packet.addLayer(
      GlobalPanelLayerId,
      GlobalPanelLayerKind,
      UiLayerFlags
    )
  packet.addRgbaSprite(
    BottomSpriteId,
    sim.mainMap.bottomSprite,
    MainBottomLabelPrefix
  )
  packet.addRgbaSprite(
    OverhangSpriteId,
    sim.mainMap.overhangSprite,
    MainOverhangLabelPrefix
  )
  for i in 0 ..< DayTintCount:
    packet.addRgbaSprite(
      mainBottomSpriteId(i),
      sim.mainMap.bottomTints[i],
      MainBottomLabelPrefix & " tint " & $i
    )
    packet.addRgbaSprite(
      mainOverhangSpriteId(i),
      sim.mainMap.overhangTints[i],
      MainOverhangLabelPrefix & " tint " & $i
    )
  packet.addRgbaSprite(
    HomeBottomSpriteId,
    sim.homeMaps[0].bottomSprite,
    HomeBottomLabelPrefix
  )
  packet.addRgbaSprite(
    HomeOverhangSpriteId,
    sim.homeMaps[0].overhangSprite,
    HomeOverhangLabelPrefix
  )
  for i in 0 ..< DayTintCount:
    packet.addRgbaSprite(
      homeBottomSpriteId(i),
      sim.homeMaps[0].bottomTints[i],
      HomeBottomLabelPrefix & " tint " & $i
    )
    packet.addRgbaSprite(
      homeOverhangSpriteId(i),
      sim.homeMaps[0].overhangTints[i],
      HomeOverhangLabelPrefix & " tint " & $i
    )
  for ch in ClockGlyphs:
    packet.addRgbaSprite(
      ch.clockGlyphSpriteId(),
      sim.clockGlyphSprite(ch),
      ClockLabelPrefix & $ch
    )
  for foodIndex, icon in sim.foods.icons:
    packet.addRgbaSprite(foodSpriteId(foodIndex), icon, foodIndex.foodName())
  packet.addRgbaSprite(
    FoodMarkerSpriteId,
    sim.foods.marker,
    GardenMarkerLabel
  )
  for gnomeIndex, gnome in sim.gnomes:
    for direction in Direction:
      packet.addRgbaSprite(
        playerSpriteId(gnomeIndex, direction),
        gnome.frames[direction],
        GnomeLabelPrefix & $gnomeIndex & " " & direction.directionLabel()
      )

proc worldClampPixel(value, maxValue: int): int =
  ## Clamps one pixel coordinate into a non-negative world range.
  value.clamp(0, max(0, maxValue))

proc playerFootX(player: Player): int =
  ## Returns the foot-center x coordinate for one player.
  player.x.footXAt()

proc playerFootY(player: Player): int =
  ## Returns the foot-center y coordinate for one player.
  player.y.footYAt()

proc isWalkable(world: WorldMap, x, y: int): bool =
  ## Returns true when one world pixel is walkable.
  if x < 0 or y < 0 or x >= world.width or y >= world.height:
    return false
  return world.walkMask[y * world.width + x]

proc canOccupy(world: WorldMap, x, y: int): bool =
  ## Returns true when a gnome can stand at one sprite position.
  ## Gnomes occupy a single foot-center pixel, like crewrift crew.
  world.isWalkable(x.footXAt(), y.footYAt())

proc hasFood(garden: Garden): bool =
  ## Returns true when a garden still has food to collect.
  for count in garden.inventory:
    if count > 0:
      return true

proc spawnClear(sim: SimServer, mapIndex, x, y: int): bool =
  ## Returns true when a spawn is walkable and away from other players.
  let world = sim.mapFor(mapIndex)
  if not world.canOccupy(x, y):
    return false
  let
    cx = x.footXAt()
    cy = y.footYAt()
  for player in sim.players:
    if player.mapIndex != mapIndex:
      continue
    if distanceSquared(
      cx,
      cy,
      player.playerFootX(),
      player.playerFootY()
    ) < MinSpawnSpacing * MinSpawnSpacing:
      return false
  return true

proc findHouseSpawn(
  sim: SimServer,
  houseIndex: int,
  spawnX,
  spawnY: var int
): bool =
  ## Finds a walkable spawn near one numbered house.
  if houseIndex < 0 or houseIndex >= HouseCount:
    return false
  if not sim.houses[houseIndex].valid:
    return false

  let
    house = sim.houses[houseIndex].rect
    maxX = max(0, sim.mainMap.width - GnomeSpriteSize)
    maxY = max(0, sim.mainMap.height - GnomeSpriteSize)
  var radius = 0
  while radius <= HouseSpawnMaxDistance:
    let
      minX = max(0, house.x - radius - GnomeSpriteSize)
      minY = max(0, house.y - radius - GnomeSpriteSize)
      maxScanX = min(maxX, house.x + house.w + radius)
      maxScanY = min(maxY, house.y + house.h + radius)
    var y = minY
    while y <= maxScanY:
      var x = minX
      while x <= maxScanX:
        let feet = Rect(x: x.footXAt(), y: y.footYAt(), w: 1, h: 1)
        if feet.rectDistanceSquared(house) <= radius * radius and
            sim.spawnClear(MainMapIndex, x, y):
          spawnX = x
          spawnY = y
          return true
        x += SpawnScanStep
      y += SpawnScanStep
    radius += SpawnScanStep

proc findMainSpawn(sim: SimServer, houseIndex = -1): tuple[x, y: int] =
  ## Returns a walkable main map spawn position.
  var
    spawnX = 0
    spawnY = 0
  if sim.findHouseSpawn(houseIndex, spawnX, spawnY):
    return (spawnX, spawnY)

  let
    maxX = max(0, sim.mainMap.width - GnomeSpriteSize)
    maxY = max(0, sim.mainMap.height - GnomeSpriteSize)
  for _ in 0 ..< 5000:
    let
      x = sim.rng.rand(maxX)
      y = sim.rng.rand(maxY)
    if sim.spawnClear(MainMapIndex, x, y):
      return (x, y)

  var y = 0
  while y <= maxY:
    var x = 0
    while x <= maxX:
      if sim.spawnClear(MainMapIndex, x, y):
        return (x, y)
      x += SpawnScanStep
    y += SpawnScanStep

  raise newException(HeartleafError, "Map has no walkable spawn.")

proc findHomeSpawn(sim: SimServer, mapIndex: int): tuple[x, y: int] =
  ## Returns a walkable spawn near the top center door of a home map.
  let
    world = sim.mapFor(mapIndex)
    doorX = max(0, (world.width - GnomeSpriteSize) div 2)
    doorY = 0
    doorFootX = doorX.footXAt()
    doorFootY = doorY.footYAt()
    maxX = max(0, world.width - GnomeSpriteSize)
    maxY = max(0, world.height - GnomeSpriteSize)
    maxRadius = max(world.width, world.height)
  var radius = 0
  while radius <= maxRadius:
    let
      minX = max(0, doorX - radius)
      minY = max(0, doorY - radius)
      maxScanX = min(maxX, doorX + radius)
      maxScanY = min(maxY, doorY + radius)
    var y = minY
    while y <= maxScanY:
      var x = minX
      while x <= maxScanX:
        if distanceSquared(
          x.footXAt(),
          y.footYAt(),
          doorFootX,
          doorFootY
        ) <= radius * radius and
            sim.spawnClear(mapIndex, x, y):
          return (x, y)
        x += SpawnScanStep
      y += SpawnScanStep
    radius += SpawnScanStep

  raise newException(HeartleafError, "Home map has no walkable spawn.")

proc chatCharSupported(ch: char): bool =
  ## Returns true when Heartleaf can draw one chat character.
  ch >= ' ' and ch <= '~'

proc cleanDisplayText(text: string, maxChars: int): string =
  ## Normalizes one printable Tiny5 text field.
  for ch in text.strip():
    if result.len >= maxChars:
      return
    if ch.chatCharSupported():
      result.add(ch)

proc cleanChatMessage(message: string): string =
  ## Normalizes one submitted player chat message.
  message.cleanDisplayText(ChatMaxChars)

proc cleanUsername(username: string): string =
  ## Normalizes one connection username for score display.
  result = username.cleanDisplayText(NameMaxChars)
  for ch in result.mitems:
    if ch.isSpaceAscii:
      ch = '_'

proc addPlayer*(sim: SimServer, username: string, requestedSlot = -1): int =
  ## Adds one player at a walkable spawn.
  var usedHomes: array[HouseCount, bool]
  for player in sim.players:
    if player.homeFlag.isHomeMap():
      usedHomes[player.homeFlag - HomeMapIndexBase] = true

  var houseIndex = -1
  if requestedSlot >= 0 and
      requestedSlot < HouseCount and
      not usedHomes[requestedSlot]:
    houseIndex = requestedSlot
  else:
    for i in 0 ..< HouseCount:
      if not usedHomes[i]:
        houseIndex = i
        break
  if houseIndex < 0:
    return -1

  let
    mapIndex = houseIndex.homeMapIndex()
    spawn = sim.findHomeSpawn(mapIndex)
    requestedUsername = username.cleanUsername()
    safeUsername =
      if requestedUsername.len > 0:
        requestedUsername
      else:
        "player_" & $(houseIndex + 1)
    playerName = houseIndex.playerNameForHouse()
    gnomeIndex = houseIndex mod sim.gnomes.len
  sim.players.add Player(
    username: safeUsername,
    playerName: playerName,
    x: spawn.x,
    y: spawn.y,
    direction: DirDown,
    gnomeIndex: gnomeIndex,
    homeFlag: mapIndex,
    mapIndex: mapIndex
  )
  return sim.players.high

proc gardenInReach(sim: SimServer, player: Player): int =
  ## Returns the closest harvestable garden in reach.
  result = -1
  if player.mapIndex != MainMapIndex:
    return
  let
    feet = Rect(
      x: player.playerFootX(),
      y: player.playerFootY(),
      w: 1,
      h: 1
    )
    maxDistance = InteractionRadius * InteractionRadius
  var bestDistance = maxDistance + 1
  for i, garden in sim.gardens:
    if not garden.hasFood():
      continue
    let distance = feet.rectDistanceSquared(garden.rect)
    if distance <= maxDistance and distance < bestDistance:
      result = i
      bestDistance = distance

proc collectGarden(sim: SimServer, playerIndex, gardenIndex: int) =
  ## Moves all food at one garden into a player's inventory.
  for foodIndex in 0 ..< FoodVeggieSlots:
    let count = sim.gardens[gardenIndex].inventory[foodIndex]
    if count <= 0:
      continue
    sim.players[playerIndex].inventory[foodIndex] += count
    sim.gardens[gardenIndex].inventory[foodIndex] = 0

proc houseContaining(sim: SimServer, player: Player): int =
  ## Returns the house containing a player's foot-center point.
  result = -1
  if player.mapIndex != MainMapIndex:
    return
  let
    footX = player.playerFootX()
    footY = player.playerFootY()
  for i, house in sim.houses:
    if house.valid and house.rect.contains(footX, footY):
      return i

proc playerAtHomeExit(sim: SimServer, player: Player): bool =
  ## Returns true when a home player is standing in the exit area.
  if not player.mapIndex.isHomeMap():
    return false
  if not sim.homeResources.hasExit:
    return false
  return sim.homeResources.exit.contains(
    player.playerFootX(),
    player.playerFootY()
  )

proc teleportPlayer(
  sim: SimServer,
  playerIndex,
  mapIndex,
  x,
  y: int,
  direction: Direction
) =
  ## Moves one player to a map and clears movement state.
  sim.players[playerIndex].mapIndex = mapIndex
  sim.players[playerIndex].x = x
  sim.players[playerIndex].y = y
  sim.players[playerIndex].direction = direction
  sim.players[playerIndex].velX = 0
  sim.players[playerIndex].velY = 0
  sim.players[playerIndex].carryX = 0
  sim.players[playerIndex].carryY = 0

proc interact(sim: SimServer, playerIndex: int) =
  ## Applies one A-button interaction for a player.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  if sim.players[playerIndex].mapIndex.isHomeMap():
    if not sim.playerAtHomeExit(sim.players[playerIndex]):
      return
    let
      houseIndex = sim.players[playerIndex].mapIndex - HomeMapIndexBase
      spawn = sim.findMainSpawn(houseIndex)
    sim.teleportPlayer(
      playerIndex,
      MainMapIndex,
      spawn.x,
      spawn.y,
      DirDown
    )
    return

  let gardenIndex = sim.gardenInReach(sim.players[playerIndex])
  if gardenIndex >= 0:
    sim.collectGarden(playerIndex, gardenIndex)
    return

  let houseIndex = sim.houseContaining(sim.players[playerIndex])
  if houseIndex >= 0:
    let
      mapIndex = houseIndex.homeMapIndex()
      spawn = sim.findHomeSpawn(mapIndex)
    sim.teleportPlayer(
      playerIndex,
      mapIndex,
      spawn.x,
      spawn.y,
      DirDown
    )

proc cameraXFor(sim: SimServer, player: Player): int =
  ## Returns the player camera x coordinate.
  let world = sim.mapFor(player.mapIndex)
  return worldClampPixel(
    player.playerFootX() - ViewportWidth div 2,
    world.width - ViewportWidth
  )

proc cameraYFor(sim: SimServer, player: Player): int =
  ## Returns the player camera y coordinate.
  let world = sim.mapFor(player.mapIndex)
  return worldClampPixel(
    player.playerFootY() - ViewportHeight div 2,
    world.height - ViewportHeight
  )

proc foodListText(foods: FoodCounts): string =
  ## Returns "Carrot x2, Beet" style text for one food count set.
  for foodIndex, count in foods:
    if count <= 0:
      continue
    if result.len > 0:
      result.add(", ")
    result.add(foodIndex.foodName())
    if count > 1:
      result.add(" x" & $count)
  if result.len == 0:
    result = "none"

proc addScreenOverlay(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  player: Player,
  playerIndex: int
) =
  ## Appends one full-screen dinner or score overlay.
  var
    overlay: RgbaSprite
    label = ""
  if player.dinnerTicks > 0 and player.dinnerRecord != nil:
    overlay = sim.dinnerOverlaySprite(player.dinnerRecord)
    label = DinnerLabelPrefix & $playerIndex
  elif sim.scoreTicks > 0:
    overlay = sim.scoreOverlaySprite()
    label = ScoreLabelPrefix & $playerIndex
  else:
    return

  let spriteId = ScoreSpriteBase + playerIndex
  packet.addRgbaSpriteCached(cache, spriteId, overlay, label)
  packet.addObject(
    ScoreObjectBase + playerIndex,
    0,
    0,
    ScoreZ,
    MapLayerId,
    spriteId
  )

const
  OutlineWhite = ColorRGBA(r: 255, g: 255, b: 255, a: 255)
  OutlineYellow = ColorRGBA(
    r: GlobalPanelSelectedR,
    g: GlobalPanelSelectedG,
    b: GlobalPanelSelectedB,
    a: 255
  )
  TrailColors = [
    ColorRGBA(r: 235, g: 90, b: 80, a: 220),
    ColorRGBA(r: 245, g: 150, b: 60, a: 220),
    ColorRGBA(r: 250, g: 220, b: 80, a: 220),
    ColorRGBA(r: 120, g: 210, b: 90, a: 220),
    ColorRGBA(r: 90, g: 220, b: 210, a: 220),
    ColorRGBA(r: 100, g: 150, b: 250, a: 220),
    ColorRGBA(r: 175, g: 110, b: 250, a: 220),
    ColorRGBA(r: 245, g: 120, b: 200, a: 220),
    ColorRGBA(r: 245, g: 245, b: 245, a: 220)
  ]

proc gnomeOutlineSprite(
  sim: SimServer,
  gnomeIndex: int,
  direction: Direction,
  color: ColorRGBA
): RgbaSprite =
  ## Builds a 1px pixel outline hugging one gnome frame's silhouette.
  let frame = sim.gnomes[gnomeIndex].frames[direction]
  result = newRgbaSprite(
    frame.width + OutlinePad * 2,
    frame.height + OutlinePad * 2
  )
  for y in 0 ..< result.height:
    for x in 0 ..< result.width:
      if frame.rgbaSpriteAt(x - OutlinePad, y - OutlinePad).a > 0:
        continue
      block neighbors:
        for dy in -1 .. 1:
          for dx in -1 .. 1:
            if frame.rgbaSpriteAt(
              x - OutlinePad + dx,
              y - OutlinePad + dy
            ).a > 0:
              result.putPixel(x, y, color)
              break neighbors

proc gnomeOutlineSpriteId(
  gnomeIndex: int,
  direction: Direction,
  yellow: bool
): int =
  ## Returns the sprite id for one cached gnome outline variant.
  GnomeOutlineSpriteBase +
    (gnomeIndex * DirectionCount + ord(direction)) * 2 +
    ord(yellow)

proc addGnomeOutline(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  gnomeIndex: int,
  direction: Direction,
  yellow: bool,
  objectId,
  screenX,
  screenY,
  z: int
) =
  ## Appends one silhouette outline object behind a gnome sprite.
  let
    spriteId = gnomeOutlineSpriteId(gnomeIndex, direction, yellow)
    color =
      if yellow:
        OutlineYellow
      else:
        OutlineWhite
  packet.addRgbaSpriteCached(
    cache,
    spriteId,
    sim.gnomeOutlineSprite(gnomeIndex, direction, color),
    "gnome outline " & $gnomeIndex & " " & directionLabel(direction) &
      (if yellow: " yellow" else: " white")
  )
  packet.addObject(
    objectId,
    screenX - OutlinePad,
    screenY - OutlinePad,
    z,
    MapLayerId,
    spriteId
  )

proc trailDotSprite(color: ColorRGBA): RgbaSprite =
  ## Builds one 5x5 round trail dot with a dark rim.
  let
    fill = ColorRGBA(r: color.r, g: color.g, b: color.b, a: 255)
    rim = ColorRGBA(
      r: fill.r div 3,
      g: fill.g div 3,
      b: fill.b div 3,
      a: 255
    )
  result = newRgbaSprite(5, 5)
  for y in 0 ..< 5:
    for x in 0 ..< 5:
      if (x == 0 or x == 4) and (y == 0 or y == 4):
        continue
      result.putPixel(x, y, rim)
  for y in 1 .. 3:
    for x in 1 .. 3:
      result.putPixel(x, y, fill)

proc addTrailObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry]
) =
  ## Appends per-player movement trail dots on the main map.
  for i, trail in sim.trails:
    if trail.len == 0:
      continue
    let
      colorIndex = i mod TrailColors.len
      spriteId = TrailDotSpriteBase + colorIndex
    packet.addRgbaSpriteCached(
      cache,
      spriteId,
      trailDotSprite(TrailColors[colorIndex]),
      "trail dot " & $colorIndex
    )
    for j, point in trail:
      if point.mapIndex != MainMapIndex:
        continue
      packet.addObject(
        TrailObjectBase + i * TrailMaxPoints + j,
        point.x - 2,
        point.y - 2,
        TrailZ,
        MapLayerId,
        spriteId
      )

proc addPlayerObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  mapIndex,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int,
  highlightIndex = -1
) =
  ## Appends all player sprite objects for one map.
  for i, player in sim.players:
    if player.mapIndex != mapIndex:
      continue
    let
      screenX = player.x - cameraX
      screenY = player.y - cameraY
    if not rectVisible(
      screenX,
      screenY,
      GnomeSpriteSize,
      GnomeSpriteSize,
      viewportWidth,
      viewportHeight
    ):
      continue
    packet.addObject(
      PlayerObjectBase + i,
      screenX,
      screenY,
      player.y + 100,
      MapLayerId,
      playerSpriteId(player.gnomeIndex, player.direction)
    )
    if i == highlightIndex:
      packet.addGnomeOutline(
        sim,
        cache,
        player.gnomeIndex,
        player.direction,
        yellow = true,
        PlayerBorderObjectId,
        screenX,
        screenY,
        player.y + 99
      )
    let nameY = packet.addNameTag(
      sim,
      cache,
      player,
      i,
      screenX,
      screenY,
      NameZ,
      viewportWidth,
      viewportHeight
    )
    packet.addSpeechBubble(
      sim,
      cache,
      player,
      i,
      screenX,
      nameY,
      ChatZ,
      viewportWidth,
      viewportHeight
    )

proc addHouseGnomeObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry]
) =
  ## Draws gnomes who are inside a house on the outside map in one
  ## horizontal row centered above the house door, outlined white for
  ## guests and yellow for the house owner.
  var occupants: array[HouseCount, seq[int]]
  for i, player in sim.players:
    let houseIndex = player.mapIndex - HomeMapIndexBase
    if houseIndex < 0 or houseIndex >= HouseCount:
      continue
    if not sim.houses[houseIndex].valid:
      continue
    occupants[houseIndex].add(i)
  for houseIndex in 0 ..< HouseCount:
    if occupants[houseIndex].len == 0:
      continue
    let
      rect = sim.houses[houseIndex].rect
      stride = GnomeSpriteSize + OutlinePad * 2 + 2
      rowWidth = stride * occupants[houseIndex].len - 2
      startX = rect.x + rect.w div 2 - rowWidth div 2
      y = rect.y - GnomeSpriteSize - HouseGnomeLift
    for slot, i in occupants[houseIndex]:
      let
        player = sim.players[i]
        x = startX + slot * stride
        isOwner = player.homeFlag == HomeMapIndexBase + houseIndex
      packet.addObject(
        HouseGnomeObjectBase + i,
        x,
        y,
        HouseGnomeZ + slot * 2 + 1,
        MapLayerId,
        playerSpriteId(player.gnomeIndex, DirDown)
      )
      packet.addGnomeOutline(
        sim,
        cache,
        player.gnomeIndex,
        DirDown,
        yellow = isOwner,
        HouseGnomeBorderObjectBase + i,
        x,
        y,
        HouseGnomeZ + slot * 2
      )

proc addHouseInsetView(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  houseIndex: int
) =
  ## Draws one house interior centered over the global map view.
  let
    homeMap = sim.homeMaps[houseIndex]
    tintIndex = sim.dayTintIndex()
    insetX = max(0, (sim.mainMap.width - homeMap.width) div 2)
    insetY = max(0, (sim.mainMap.height - homeMap.height) div 2)
    mapIndex = houseIndex.homeMapIndex()
  packet.addObject(
    InsetBottomObjectId,
    insetX,
    insetY,
    InsetBottomZ,
    MapLayerId,
    homeBottomSpriteId(tintIndex)
  )
  for i, player in sim.players:
    if player.mapIndex != mapIndex:
      continue
    let
      screenX = insetX + player.x
      screenY = insetY + player.y
    packet.addObject(
      InsetPlayerObjectBase + i,
      screenX,
      screenY,
      clamp(
        InsetPlayerZBase + player.y,
        InsetPlayerZBase,
        InsetOverhangZ - 1
      ),
      MapLayerId,
      playerSpriteId(player.gnomeIndex, player.direction)
    )
    let nameY = packet.addNameTag(
      sim,
      cache,
      player,
      i,
      screenX,
      screenY,
      InsetNameZ,
      sim.mainMap.width,
      sim.mainMap.height
    )
    packet.addSpeechBubble(
      sim,
      cache,
      player,
      i,
      screenX,
      nameY,
      InsetChatZ,
      sim.mainMap.width,
      sim.mainMap.height
    )
  packet.addObject(
    InsetOverhangObjectId,
    insetX,
    insetY,
    InsetOverhangZ,
    MapLayerId,
    homeOverhangSpriteId(tintIndex)
  )

proc addGardenObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
) =
  ## Appends garden item markers for gardens that still hold food.
  for i, garden in sim.gardens:
    if not garden.hasFood():
      continue
    let
      x = garden.rect.x + garden.rect.w div 2 - FoodSpriteSize div 2
      y = garden.rect.y + garden.rect.h div 2 - FoodSpriteSize div 2
      screenX = x - cameraX
      screenY = y - cameraY
    if not rectVisible(
      screenX,
      screenY,
      FoodSpriteSize,
      FoodSpriteSize,
      viewportWidth,
      viewportHeight
    ):
      continue
    packet.addObject(
      GardenObjectBase + i,
      screenX,
      screenY,
      GardenMarkerZ,
      MapLayerId,
      FoodMarkerSpriteId
    )

proc addInventoryObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  player: Player
) =
  ## Appends a compact bottom-right inventory UI for one player.
  var slot = 0
  for foodIndex, count in player.inventory:
    if count <= 0:
      continue
    let
      col = slot mod InventoryColumns
      row = slot div InventoryColumns
      x = InventoryUiWidth - FoodSpriteSize - col * InventoryIconStep
      y = InventoryUiHeight - FoodSpriteSize - row * InventoryIconStep
    packet.addObject(
      InventoryObjectBase + foodIndex,
      x,
      y,
      0,
      UiLayerId,
      foodSpriteId(foodIndex)
    )
    let
      countSprite = sim.inventoryCountSprite(count)
      countX = x + FoodSpriteSize - countSprite.width
      countY = y + FoodSpriteSize - countSprite.height
      spriteId = InventoryCountSpriteBase + foodIndex
    packet.addRgbaSpriteCached(
      cache,
      spriteId,
      countSprite,
      "inventory " & foodIndex.foodName() & " " & $count
    )
    packet.addObject(
      InventoryCountObjectBase + foodIndex,
      countX,
      countY,
      1,
      UiLayerId,
      spriteId
    )
    inc slot

proc addClockObjects(packet: var seq[uint8], sim: SimServer) =
  ## Appends the upper-right clock using individual glyph objects.
  let text = sim.clockText()
  var totalWidth = 0
  for ch in text:
    totalWidth += sim.clockGlyphWidth(ch)
  totalWidth += max(0, text.len - 1) * ClockGlyphGap

  var x = max(0, ClockUiWidth - totalWidth)
  for i, ch in text:
    packet.addObject(
      ClockObjectBase + i,
      x,
      0,
      0,
      ClockLayerId,
      ch.clockGlyphSpriteId()
    )
    x += sim.clockGlyphWidth(ch) + ClockGlyphGap

proc addPlayerView(
  packet: var seq[uint8],
  sim: SimServer,
  playerIndex: int,
  cache: var seq[SpriteCacheEntry],
  highlight = false
): bool =
  ## Appends one selected player's map and UI view.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  let
    player = sim.players[playerIndex]
    onMainMap = player.mapIndex == MainMapIndex
    tintIndex = sim.dayTintIndex()
    cameraX = sim.cameraXFor(player)
    cameraY = sim.cameraYFor(player)
    bottomSpriteId =
      if onMainMap:
        mainBottomSpriteId(tintIndex)
      else:
        homeBottomSpriteId(tintIndex)
    overhangSpriteId =
      if onMainMap:
        mainOverhangSpriteId(tintIndex)
      else:
        homeOverhangSpriteId(tintIndex)
  if player.dinnerTicks > 0 or sim.scoreTicks > 0:
    packet.addScreenOverlay(
      sim,
      cache,
      player,
      playerIndex
    )
    return true
  packet.addObject(
    BottomObjectId,
    -cameraX,
    -cameraY,
    BottomZ,
    MapLayerId,
    bottomSpriteId
  )
  if onMainMap:
    packet.addGardenObjects(
      sim,
      cameraX,
      cameraY,
      ViewportWidth,
      ViewportHeight
    )
  packet.addPlayerObjects(
    sim,
    cache,
    player.mapIndex,
    cameraX,
    cameraY,
    ViewportWidth,
    ViewportHeight,
    highlightIndex =
      if highlight:
        playerIndex
      else:
        -1
  )
  packet.addObject(
    OverhangObjectId,
    -cameraX,
    -cameraY,
    OverhangZ,
    MapLayerId,
    overhangSpriteId
  )
  packet.addInventoryObjects(
    sim,
    cache,
    player
  )
  packet.addClockObjects(sim)
  return true

proc addGlobalWorldView(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry]
) =
  ## Appends the full main map view for an unselected global viewer.
  let tintIndex = sim.dayTintIndex()
  packet.addViewport(MapLayerId, sim.mainMap.width, sim.mainMap.height)
  packet.addObject(
    BottomObjectId,
    0,
    0,
    BottomZ,
    MapLayerId,
    mainBottomSpriteId(tintIndex)
  )
  packet.addGardenObjects(
    sim,
    0,
    0,
    sim.mainMap.width,
    sim.mainMap.height
  )
  packet.addTrailObjects(sim, cache)
  packet.addPlayerObjects(
    sim,
    cache,
    MainMapIndex,
    0,
    0,
    sim.mainMap.width,
    sim.mainMap.height
  )
  packet.addHouseGnomeObjects(sim, cache)
  packet.addObject(
    OverhangObjectId,
    0,
    0,
    OverhangZ,
    MapLayerId,
    mainOverhangSpriteId(tintIndex)
  )
  packet.addClockObjects(sim)

proc replayCommandAt(layer, x, y: int): char =
  ## Returns the replay transport command under a UI coordinate. The
  ## transport buttons and speed labels share one row on the center bar.
  if layer != ReplayCenterBottomLayerId:
    return '\0'
  let localY = y - ChatBannerAreaHeight - TransportRowY
  if localY < 0 or localY >= TransportRowHeight:
    return '\0'
  let buttonX = x - TransportButtonsX
  if buttonX >= 0 and
      buttonX < TransportButtonCount * TransportButtonStride:
    let index = buttonX div TransportButtonStride
    if buttonX - index * TransportButtonStride >= TransportButtonWidth:
      return '\0'
    case index
    of 0: return '<'
    of 1: return ' '
    of 2: return 'e'
    else: return 'r'
  let speedX = x - SpeedRowX
  if speedX >= 0 and
      speedX < TransportSpeedCommands.len * TransportSpeedStride:
    let index = speedX div TransportSpeedStride
    if speedX - index * TransportSpeedStride >= TransportSpeedWidth:
      return '\0'
    return TransportSpeedCommands[index]
  '\0'

const ReplayControlsBg = ColorRGBA(r: 0, g: 0, b: 0, a: ReplayControlsBgAlpha)

proc replayScrubTickAt(
  layer, x, y, maxTick: int,
  requireInside = true
): int =
  ## Returns the replay tick under the scrubber pointer.
  if layer != ReplayCenterBottomLayerId or maxTick < 0:
    return -1
  let
    scrubberX = max(0, (ViewportWidth - ReplayScrubberWidth) div 2)
    localX = x - scrubberX
    localY = y - ChatBannerAreaHeight - ReplayScrubberY
  if requireInside and (
      localX < 0 or localX >= ReplayScrubberWidth or
      localY < 0 or localY >= ReplayScrubberHeight
    ):
    return -1
  if ReplayScrubberWidth <= 1:
    return 0
  let clampedX = clamp(localX, 0, ReplayScrubberWidth - 1)
  clamp((clampedX * maxTick) div (ReplayScrubberWidth - 1), 0, maxTick)

proc buildReplayScrubberSprite(tick, maxTick, dayTicks: int): RgbaSprite =
  ## Builds the compact replay scrubber sprite with dinner-time pips.
  result = newRgbaSprite(ReplayScrubberWidth, ReplayScrubberHeight)
  let
    track = rgba(90, 90, 90, 255)
    knob = rgba(255, 255, 255, 255)
    knobEdge = rgba(180, 180, 180, 255)
    pip = rgba(255, 196, 64, 255)
    knobX =
      if maxTick > 0:
        clamp(
          (tick * (ReplayScrubberWidth - 1)) div maxTick,
          0,
          ReplayScrubberWidth - 1
        )
      else:
        0
  for x in 0 ..< ReplayScrubberWidth:
    result.putPixel(x, ReplayScrubberTrackY, track)
  if maxTick > 0 and dayTicks > 0:
    let dinnerOffset =
      dayTicks * (DinnerMinutes - DayStartMinutes) div DayTotalMinutes
    var dinnerTick = dinnerOffset
    while dinnerTick <= maxTick:
      let x = clamp(
        (dinnerTick * (ReplayScrubberWidth - 1)) div maxTick,
        0,
        ReplayScrubberWidth - 1
      )
      for y in 0 ..< ReplayScrubberHeight:
        result.putPixel(x, y, pip)
      dinnerTick += dayTicks
  for x in 0 .. knobX:
    result.putPixel(x, ReplayScrubberTrackY, knob)
  for y in 0 ..< ReplayScrubberHeight:
    result.putPixel(knobX, y, knob)
  if knobX > 0:
    result.putPixel(knobX - 1, ReplayScrubberTrackY, knobEdge)
  if knobX < ReplayScrubberWidth - 1:
    result.putPixel(knobX + 1, ReplayScrubberTrackY, knobEdge)

proc buildReplayControlsSprite(
  sim: SimServer,
  playing: bool,
  looping: bool,
  speed: int
): RgbaSprite =
  ## Builds the one-row transport buttons and speed labels sprite.
  result = newRgbaSprite(ViewportWidth, TransportRowHeight)
  let
    bright = rgba(255, 255, 255, 255)
    dim = rgba(128, 128, 128, 255)
    buttons = [
      "<<",
      if playing: "||" else: "|>",
      ">|",
      "R"
    ]
  for i, label in buttons:
    let color =
      if i == 3:
        if looping: bright else: dim
      else:
        bright
    sim.blitTinyText(
      result,
      label,
      TransportButtonsX + i * TransportButtonStride,
      0,
      color
    )
  for i, label in TransportSpeedLabels:
    let color =
      if TransportSpeedValues[i] == speed:
        bright
      else:
        dim
    sim.blitTinyText(
      result,
      label,
      SpeedRowX + i * TransportSpeedStride,
      0,
      color
    )

proc addReplayControlLayers(packet: var seq[uint8]) =
  ## Adds the fixed UI layer shared by the delay chat banner and the
  ## replay timing controls.
  packet.addLayer(
    ReplayCenterBottomLayerId,
    ReplayCenterBottomLayerKind,
    UiLayerFlags
  )
  packet.addViewport(
    ReplayCenterBottomLayerId,
    ViewportWidth,
    ReplayBarTotalHeight
  )

proc addReplayMismatchWarning(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  tick: int
) =
  ## Adds a fixed top-center replay hash mismatch warning.
  if tick < 0:
    return
  let
    label = "HASH MISMATCH AT TICK " & $tick
    textWidth = sim.textFont.textWidth(label)
  var warning = newRgbaSprite(
    textWidth + ReplayMismatchPadX * 2,
    sim.textFont.height + ReplayMismatchPadY * 2
  )
  warning.fillRect(
    0,
    0,
    warning.width,
    warning.height,
    rgba(220, 20, 20, 255)
  )
  sim.blitTinyText(
    warning,
    label,
    ReplayMismatchPadX,
    ReplayMismatchPadY,
    rgba(255, 255, 255, 255)
  )
  packet.addLayer(
    ReplayMismatchLayerId,
    ReplayMismatchLayerKind,
    UiLayerFlags
  )
  packet.addViewport(ReplayMismatchLayerId, warning.width, warning.height)
  packet.addRgbaSpriteCached(
    cache,
    ReplayMismatchSpriteId,
    warning,
    "replay mismatch " & $tick
  )
  packet.addObject(
    ReplayMismatchObjectId,
    0,
    0,
    0,
    ReplayMismatchLayerId,
    ReplayMismatchSpriteId
  )

proc addReplayControls(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  replayTick,
  replaySpeed,
  replayMaxTick: int,
  playing,
  looping: bool,
  mismatchTick = -1
) =
  ## Adds the replay timing controls for one replay viewer frame.
  packet.addReplayControlLayers()
  var panelBg = newRgbaSprite(ViewportWidth, ReplayPanelHeight)
  panelBg.fillRect(0, 0, panelBg.width, panelBg.height, ReplayControlsBg)
  packet.addRgbaSpriteCached(
    cache,
    ReplayPanelBgSpriteId,
    panelBg,
    "replay panel bg"
  )
  packet.addObject(
    ReplayPanelBgObjectId,
    0,
    ChatBannerAreaHeight,
    -1,
    ReplayCenterBottomLayerId,
    ReplayPanelBgSpriteId
  )
  let
    controlTick = max(0, replayTick)
    controlMaxTick = max(controlTick, replayMaxTick)
    tickText = sim.globalPanelTextSprite(
      "TICK " & $controlTick,
      rgba(GlobalPanelTextR, GlobalPanelTextG, GlobalPanelTextB, 255)
    )
    scrubber = buildReplayScrubberSprite(
      controlTick,
      controlMaxTick,
      sim.dayTicks
    )
    controls = sim.buildReplayControlsSprite(playing, looping, replaySpeed)
  packet.addRgbaSpriteCached(
    cache,
    ReplayTickSpriteId,
    tickText,
    "replay tick " & $controlTick
  )
  packet.addObject(
    ReplayTickObjectId,
    max(0, (ViewportWidth - tickText.width) div 2),
    ChatBannerAreaHeight + ReplayTickTextY,
    0,
    ReplayCenterBottomLayerId,
    ReplayTickSpriteId
  )
  packet.addRgbaSpriteCached(
    cache,
    ReplayScrubberSpriteId,
    scrubber,
    "replay scrubber"
  )
  packet.addObject(
    ReplayScrubberObjectId,
    max(0, (ViewportWidth - ReplayScrubberWidth) div 2),
    ChatBannerAreaHeight + ReplayScrubberY,
    0,
    ReplayCenterBottomLayerId,
    ReplayScrubberSpriteId
  )
  packet.addRgbaSpriteCached(
    cache,
    ReplayControlsSpriteId,
    controls,
    "replay controls"
  )
  packet.addObject(
    ReplayControlsObjectId,
    0,
    ChatBannerAreaHeight + TransportRowY,
    0,
    ReplayCenterBottomLayerId,
    ReplayControlsSpriteId
  )
  packet.addReplayMismatchWarning(sim, cache, mismatchTick)

proc flippedHorizontal(sprite: RgbaSprite): RgbaSprite =
  ## Returns one horizontally mirrored sprite.
  result = newRgbaSprite(sprite.width, sprite.height)
  for y in 0 ..< sprite.height:
    for x in 0 ..< sprite.width:
      result.putPixel(sprite.width - 1 - x, y, sprite.rgbaSpriteAt(x, y))

proc blitSprite(target: var RgbaSprite, source: RgbaSprite, ox, oy: int) =
  ## Blits non-transparent source pixels into a target sprite.
  for y in 0 ..< source.height:
    for x in 0 ..< source.width:
      let color = source.rgbaSpriteAt(x, y)
      if color.a > 0:
        target.putPixel(ox + x, oy + y, color)

proc bannerPortrait(sim: SimServer, gnomeIndex: int): RgbaSprite =
  ## Returns the profile portrait for one gnome index.
  if sim.portraits.len == 0:
    return newRgbaSprite(0, 0)
  sim.portraits[gnomeIndex mod sim.portraits.len]

proc bannerMessageLines(
  sim: SimServer,
  text: string,
  maxWidth: int
): seq[string] =
  ## Greedily wraps banner text into pixel-width limited lines.
  var line = ""
  for word in text.splitWhitespace():
    let candidate =
      if line.len == 0:
        word
      else:
        line & " " & word
    if line.len > 0 and sim.chatTextWidth(candidate) > maxWidth:
      result.add(line)
      line = word
    else:
      line = candidate
  if line.len > 0:
    result.add(line)

proc layoutBannerHearers(
  sim: SimServer,
  item: ChatFeedItem,
  bannerWidth: int
): seq[ChatBannerHearer] =
  ## Packs up to three hearers from the right, spaced by name tags.
  var tagRight = bannerWidth - ChatBannerPortraitMargin
  for h in 0 ..< min(item.hearers.len, ChatBannerMaxHearers):
    let
      portrait = sim.bannerPortrait(item.hearers[h].gnomeIndex)
      tag = sim.nameTagSprite(item.hearers[h].name)
    if portrait.width == 0 or tag.width == 0:
      continue
    let
      tagX = tagRight - tag.width
      portraitX = tagX + tag.width div 2 - portrait.width div 2
    result.add(ChatBannerHearer(
      portrait: portrait,
      tag: tag,
      portraitX: portraitX,
      tagX: tagX
    ))
    tagRight = tagX - ChatBannerNameGap

proc chatBannerSprite(sim: SimServer, item: ChatFeedItem): RgbaSprite =
  ## Builds the delay-chat banner: the flipped speaker on the left, the
  ## message in the middle, up to three hearers on the right, and name
  ## tags along the bottom. Hearer portraits overlap above the names.
  result = sim.chatBanner
  if result.width == 0:
    return
  let
    ink = ColorRGBA(r: 0x94, g: 0x5C, b: 0x29, a: 255)
    speakerPortrait =
      sim.bannerPortrait(item.speaker.gnomeIndex).flippedHorizontal()
    speakerTag = sim.nameTagSprite(item.speaker.name)
    hearers = sim.layoutBannerHearers(item, result.width)
    tagY = result.height - speakerTag.height - 2
  result.blitSprite(
    speakerPortrait,
    ChatBannerPortraitMargin,
    ChatBannerPortraitY
  )
  for hearer in hearers:
    result.blitSprite(
      hearer.portrait,
      hearer.portraitX,
      ChatBannerPortraitY
    )
  result.blitSprite(
    speakerTag,
    ChatBannerPortraitMargin + speakerPortrait.width div 2 -
      speakerTag.width div 2,
    tagY
  )
  for hearer in hearers:
    result.blitSprite(hearer.tag, hearer.tagX, tagY)
  var huddleLeft = result.width - ChatBannerPortraitMargin
  for hearer in hearers:
    huddleLeft = min(huddleLeft, hearer.portraitX)
    huddleLeft = min(huddleLeft, hearer.tagX)
  let
    textLeft =
      ChatBannerPortraitMargin + speakerPortrait.width + ChatBannerTextGap
    maxWidth = max(20, huddleLeft - ChatBannerTextGap - textLeft)
    lines = sim.bannerMessageLines(item.message, maxWidth)
    lineHeight = sim.textFont.height + 1
    blockTop = max(
      ChatBannerPortraitY,
      (result.height - 8 - lines.len * lineHeight) div 2
    )
  for i, line in lines:
    sim.blitTinyText(
      result,
      line,
      textLeft + (maxWidth - sim.chatTextWidth(line)) div 2,
      blockTop + i * lineHeight,
      ink
    )

proc addChatBanner(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  declareLayer: bool
) =
  ## Appends the paced delay-chat banner at the top of the center bar.
  ## The replay controls declare the shared layer; standalone (live
  ## global view) callers declare it here instead.
  if sim.chatFeedIndex < 0 or sim.chatFeedIndex >= sim.chatFeed.len:
    return
  let banner = sim.chatBannerSprite(sim.chatFeed[sim.chatFeedIndex])
  if banner.width == 0:
    return
  if declareLayer:
    packet.addLayer(
      ReplayCenterBottomLayerId,
      ReplayCenterBottomLayerKind,
      UiLayerFlags
    )
    packet.addViewport(
      ReplayCenterBottomLayerId,
      ViewportWidth,
      ChatBannerAreaHeight
    )
  packet.addRgbaSpriteCached(cache, ChatBannerSpriteId, banner, "chat banner")
  packet.addObject(
    ChatBannerObjectId,
    max(0, (ViewportWidth - banner.width) div 2),
    0,
    0,
    ReplayCenterBottomLayerId,
    ChatBannerSpriteId
  )

proc buildGlobalPacket(
  sim: SimServer,
  state: PlayerViewerState,
  nextState: var PlayerViewerState,
  replayControls = false,
  replayTick = -1,
  replaySpeed = 1,
  replayMaxTick = -1,
  replayPlaying = false,
  replayLooping = false,
  replayMismatchTick = -1
): seq[uint8] =
  ## Builds one sprite protocol packet for a global viewer.
  nextState =
    if state == nil:
      PlayerViewerState(selectedPlayerIndex: -1)
    else:
      state
  if not nextState.initialized:
    result.add(sim.playerInitPacket)
    nextState.initialized = true

  result.addClearObjects()
  if nextState.pendingMapClick:
    nextState.pendingMapClick = false
    let
      clickX = nextState.pendingMapClickX
      clickY = nextState.pendingMapClickY
    if nextState.selectedPlayerIndex >= 0:
      nextState.selectedPlayerIndex = -1
    elif nextState.selectedHouseNumber > 0 and
        nextState.selectedHouseNumber <= HouseCount:
      let
        homeMap = sim.homeMaps[nextState.selectedHouseNumber - 1]
        inset = Rect(
          x: max(0, (sim.mainMap.width - homeMap.width) div 2),
          y: max(0, (sim.mainMap.height - homeMap.height) div 2),
          w: homeMap.width,
          h: homeMap.height
        )
      if not inset.contains(clickX, clickY):
        nextState.selectedHouseNumber = 0
    else:
      for i, house in sim.houses:
        if house.valid and house.rect.contains(clickX, clickY):
          nextState.selectedHouseNumber = i + 1
          break
  let selectedIndex = nextState.selectedGlobalPlayerIndex(sim)
  nextState.selectedPlayerIndex = selectedIndex
  if selectedIndex >= 0:
    result.addViewport(MapLayerId, ViewportWidth, ViewportHeight)
    discard result.addPlayerView(
      sim,
      selectedIndex,
      nextState.spriteCache,
      highlight = true
    )
  else:
    result.addGlobalWorldView(sim, nextState.spriteCache)
    if nextState.selectedHouseNumber > 0 and
        nextState.selectedHouseNumber <= HouseCount:
      result.addHouseInsetView(
        sim,
        nextState.spriteCache,
        nextState.selectedHouseNumber - 1
      )
  result.addGlobalScorePanel(sim, nextState.spriteCache, selectedIndex)
  if replayControls:
    result.addReplayControls(
      sim,
      nextState.spriteCache,
      replayTick,
      replaySpeed,
      replayMaxTick,
      replayPlaying,
      replayLooping,
      replayMismatchTick
    )
  result.addChatBanner(sim, nextState.spriteCache, declareLayer = not replayControls)

proc updateDirection(player: var Player, input: InputState) =
  ## Updates the player's facing direction from held input.
  let
    x =
      if input.left:
        -1
      elif input.right:
        1
      else:
        0
    y =
      if input.up:
        -1
      elif input.down:
        1
      else:
        0
  if abs(x) > abs(y):
    player.direction =
      if x < 0:
        DirLeft
      else:
        DirRight
  elif y != 0:
    player.direction =
      if y < 0:
        DirUp
      else:
        DirDown

proc applyInput(sim: SimServer, playerIndex: int, input: InputState) =
  ## Applies one player's held movement input.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  var
    inputX = 0
    inputY = 0
  if input.left:
    dec inputX
  if input.right:
    inc inputX
  if input.up:
    dec inputY
  if input.down:
    inc inputY

  sim.players[playerIndex].updateDirection(input)
  let player = sim.players[playerIndex]
  player.inputX = inputX
  player.inputY = inputY
  if inputX != 0:
    player.velX = clamp(
      player.velX + inputX * Accel,
      -MaxSpeed,
      MaxSpeed
    )
  else:
    player.velX = (player.velX * FrictionNum) div FrictionDen
    if abs(player.velX) < StopThreshold:
      player.velX = 0
  if inputY != 0:
    player.velY = clamp(
      player.velY + inputY * Accel,
      -MaxSpeed,
      MaxSpeed
    )
  else:
    player.velY = (player.velY * FrictionNum) div FrictionDen
    if abs(player.velY) < StopThreshold:
      player.velY = 0

proc signum(value: int): int =
  ## Returns the sign of one integer as -1, 0, or 1.
  if value < 0:
    return -1
  if value > 0:
    return 1
  return 0

proc slideScanRadius(carry, velocity: int): int =
  ## Returns the perpendicular scan radius for blocked movement.
  let
    pending = abs(carry) div MotionScale
    speed = (abs(velocity) + MotionScale - 1) div MotionScale
  return clamp(max(1, max(pending, speed)), 1, MovementSlideMaxScan)

proc canSlideHorizontal(world: WorldMap, x, y, step, offset: int): bool =
  ## Returns true when a horizontal step can slide by one offset.
  if offset == 0:
    return false
  let slideStep = offset.signum()
  for i in 1 .. abs(offset):
    if not world.canOccupy(x, y + slideStep * i):
      return false
  return world.canOccupy(x + step, y + offset)

proc canSlideVertical(world: WorldMap, x, y, step, offset: int): bool =
  ## Returns true when a vertical step can slide by one offset.
  if offset == 0:
    return false
  let slideStep = offset.signum()
  for i in 1 .. abs(offset):
    if not world.canOccupy(x + slideStep * i, y):
      return false
  return world.canOccupy(x + offset, y + step)

proc trySlideOffset(
  world: WorldMap,
  player: Player,
  step,
  offset: int,
  horizontal: bool
): bool =
  ## Tries one candidate slide offset for a blocked movement step.
  if horizontal:
    if not world.canSlideHorizontal(player.x, player.y, step, offset):
      return false
    player.x += step
    player.y += offset
  else:
    if not world.canSlideVertical(player.x, player.y, step, offset):
      return false
    player.x += offset
    player.y += step
  return true

proc trySlideMove(
  world: WorldMap,
  player: Player,
  step,
  radius,
  preferredSlide: int,
  horizontal: bool
): bool =
  ## Tries nearby slide offsets for one blocked movement step.
  if radius <= 0:
    return false
  let preferred = preferredSlide.signum()
  for distance in 1 .. radius:
    if preferred != 0:
      if world.trySlideOffset(player, step, preferred * distance, horizontal):
        return true
      if world.trySlideOffset(player, step, -preferred * distance, horizontal):
        return true
    else:
      if world.trySlideOffset(player, step, -distance, horizontal):
        return true
      if world.trySlideOffset(player, step, distance, horizontal):
        return true

proc applyMomentumAxis(
  world: WorldMap,
  player: Player,
  carry: var int,
  velocity,
  preferredSlide: int,
  horizontal: bool
) =
  ## Applies one fixed-point movement axis with collision sliding.
  carry += velocity
  while abs(carry) >= MotionScale:
    let step =
      if carry < 0:
        -1
      else:
        1
    let
      nx =
        if horizontal:
          player.x + step
        else:
          player.x
      ny =
        if horizontal:
          player.y
        else:
          player.y + step
    if world.canOccupy(nx, ny):
      if horizontal:
        player.x = nx
      else:
        player.y = ny
      carry -= step * MotionScale
    else:
      let radius = slideScanRadius(carry, velocity)
      if world.trySlideMove(player, step, radius, preferredSlide, horizontal):
        carry -= step * MotionScale
      else:
        carry = 0
        break

proc moveAxis(sim: SimServer, player: Player, horizontal: bool) =
  ## Moves one player along one axis with crewrift-style sliding.
  let world = sim.mapFor(player.mapIndex)
  if horizontal:
    let preferredSlide =
      if player.inputY != 0:
        player.inputY
      else:
        player.velY.signum()
    world.applyMomentumAxis(
      player,
      player.carryX,
      player.velX,
      preferredSlide,
      true
    )
  else:
    let preferredSlide =
      if player.inputX != 0:
        player.inputX
      else:
        player.velX.signum()
    world.applyMomentumAxis(
      player,
      player.carryY,
      player.velY,
      preferredSlide,
      false
    )

proc updateMessages(sim: SimServer) =
  ## Clears transient player panels when their lifetime expires.
  for player in sim.players.mitems:
    if player.dinnerTicks > 0:
      dec player.dinnerTicks
      if player.dinnerTicks <= 0:
        player.dinnerRecord = nil
    if player.messageTicks <= 0:
      if player.message.len > 0:
        player.message = ""
      continue
    dec player.messageTicks
    if player.messageTicks <= 0:
      player.message = ""

proc teleportPlayerToOwnHome(sim: SimServer, playerIndex: int) =
  ## Teleports one player to their assigned home map.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  let
    mapIndex = sim.players[playerIndex].homeFlag
    spawn = sim.findHomeSpawn(mapIndex)
  sim.teleportPlayer(
    playerIndex,
    mapIndex,
    spawn.x,
    spawn.y,
    DirDown
  )

proc clearInventory(player: Player) =
  ## Clears one player inventory.
  player.inventory.clearFoods()

proc homeHostIndex(sim: SimServer, mapIndex: int): int =
  ## Returns the player index for the host assigned to one home map.
  result = -1
  for i, player in sim.players:
    if player.homeFlag == mapIndex:
      return i

proc homeVisitors(sim: SimServer, mapIndex, hostIndex: int): seq[int] =
  ## Returns player indices visiting one occupied home map.
  for i, player in sim.players:
    if i == hostIndex:
      continue
    if player.mapIndex == mapIndex:
      result.add(i)

proc recordDinner(
  player: Player,
  record: DinnerRecord
) =
  ## Stores and shows one dinner result for a player.
  player.dinners.add(record)
  player.dinnerRecord = record
  player.dinnerTicks = DinnerScreenTicks

proc chooseDinnerBite*(
  eaten: array[FoodVeggieSlots, bool],
  pantry: array[FoodVeggieSlots, int],
  rng: var Rand
): int =
  ## Returns one host-pantry food index to eat, or -1 when empty.
  var wanted: seq[int]
  for i in 0 ..< FoodVeggieSlots:
    if pantry[i] > 0 and not eaten[i]:
      wanted.add(i)
  if wanted.len > 0:
    return wanted[rng.rand(wanted.len - 1)]
  let total = pantry.totalItems()
  if total <= 0:
    return -1
  var pick = rng.rand(total - 1)
  for i in 0 ..< FoodVeggieSlots:
    if pick < pantry[i]:
      return i
    pick -= pantry[i]
  -1

proc applyDinnerBite(
  eaten: var array[FoodVeggieSlots, bool],
  pantry: var FoodCounts,
  ate: var FoodCounts,
  foodIndex: int
): int =
  ## Takes one pantry item and returns the bite score.
  if foodIndex < 0 or foodIndex >= FoodVeggieSlots:
    return 0
  if pantry[foodIndex] <= 0:
    return 0
  let isNew = not eaten[foodIndex]
  eaten[foodIndex] = true
  dec pantry[foodIndex]
  inc ate[foodIndex]
  if isNew:
    NewFoodEatScore
  else:
    LeftoverEatScore

proc eatDinnerRounds*(
  eaten: var seq[array[FoodVeggieSlots, bool]],
  pantry: var array[FoodVeggieSlots, int],
  rng: var Rand
): tuple[
  scores: seq[int],
  foods: seq[array[FoodVeggieSlots, int]]
] =
  ## Runs three shared rounds of one bite each from a host pantry.
  result.scores = newSeq[int](eaten.len)
  result.foods = newSeq[array[FoodVeggieSlots, int]](eaten.len)
  for r in 0 ..< DinnerEatRounds:
    for i in 0 ..< eaten.len:
      let foodIndex = chooseDinnerBite(eaten[i], pantry, rng)
      result.scores[i] += applyDinnerBite(
        eaten[i],
        pantry,
        result.foods[i],
        foodIndex
      )

proc startDinnerParties(sim: SimServer) =
  ## Resolves all valid 6pm dinner parties in occupied homes.
  sim.dinnerDone = true
  for homeIndex in 0 ..< HouseCount:
    let
      mapIndex = homeIndex.homeMapIndex()
      hostIndex = sim.homeHostIndex(mapIndex)
    if hostIndex < 0:
      continue
    let host = sim.players[hostIndex]
    if host.mapIndex != mapIndex:
      continue
    let visitors = sim.homeVisitors(mapIndex, hostIndex)
    if visitors.len == 0:
      continue

    var
      guestNames: seq[string]
      guestGnomeIndices: seq[int]
      diners = @[hostIndex]
    for visitorIndex in visitors:
      guestNames.add(sim.players[visitorIndex].playerName)
      guestGnomeIndices.add(sim.players[visitorIndex].gnomeIndex)
      diners.add(visitorIndex)
    sim.rng.shuffle(diners)

    var
      dinerEaten = newSeq[array[FoodVeggieSlots, bool]](diners.len)
      pantry = host.inventory
    for i, dinerIndex in diners:
      dinerEaten[i] = sim.players[dinerIndex].eaten
    let
      served = host.inventory
      hostScore = served.totalItems() * visitors.len
      eatenMeals = eatDinnerRounds(dinerEaten, pantry, sim.rng)
    for i, dinerIndex in diners:
      sim.players[dinerIndex].eaten = dinerEaten[i]
      sim.players[dinerIndex].score += eatenMeals.scores[i]

    let hostRecord = DinnerRecord(
      hostName: host.playerName,
      wasHost: true,
      foods: served,
      guestNames: guestNames,
      guestGnomeIndices: guestGnomeIndices,
      guestCount: visitors.len,
      score: hostScore
    )
    host.score += hostScore
    host.recordDinner(hostRecord)
    host.clearInventory()

    for visitorIndex in visitors:
      let visitor = sim.players[visitorIndex]
      var
        ate: FoodCounts
        eatScore = 0
      for i, dinerIndex in diners:
        if dinerIndex == visitorIndex:
          ate = eatenMeals.foods[i]
          eatScore = eatenMeals.scores[i]
          break
      visitor.recordDinner(
        DinnerRecord(
          hostName: host.playerName,
          wasHost: false,
          foods: ate,
          guestNames: guestNames,
          guestGnomeIndices: guestGnomeIndices,
          guestCount: visitors.len,
          score: eatScore
        )
      )

proc startDay(sim: SimServer) =
  ## Starts a new morning while keeping long-game player progress.
  inc sim.dayNumber
  sim.dayTick = 0
  sim.scoreTicks = 0
  sim.dinnerDone = false
  sim.gardens = loadGardens(sim.resourceRects, sim.rng)
  for player in sim.players.mitems:
    player.dinnerTicks = 0
    player.dinnerRecord = nil
  for i in 0 ..< sim.players.len:
    sim.teleportPlayerToOwnHome(i)

proc startScoreScreen(sim: SimServer) =
  ## Starts the end-of-day scoring screen.
  sim.dayTick = sim.dayTicks
  sim.scoreTicks = ScoreScreenTicks
  for player in sim.players.mitems:
    player.dinnerTicks = 0
    player.dinnerRecord = nil
  for i in 0 ..< sim.players.len:
    sim.teleportPlayerToOwnHome(i)

proc replayChatVisibleTo(sim: SimServer, speaker, viewer: Player): bool =
  ## Whether `viewer` would see `speaker`'s current speech bubble — the
  ## in-game "hearing range". Chat has no explicit radius: a bubble is only
  ## delivered to a viewer when it lands inside that viewer's viewport (the
  ## camera follows the viewer, clamped at map edges). This mirrors the exact
  ## geometry of `addNameTag` + `addSpeechBubble` on the render path.
  if speaker.message.len == 0 or speaker.messageTicks <= 0:
    return false
  if speaker.mapIndex != viewer.mapIndex:  # a house wall blocks the bubble
    return false
  let
    cameraX = sim.cameraXFor(viewer)
    cameraY = sim.cameraYFor(viewer)
    screenX = speaker.x - cameraX
    screenY = speaker.y - cameraY
    tag = sim.nameTagSprite(speaker.playerName)
    nameY = screenY - tag.height - NameGapY
    bubble = sim.speechBubbleSprite(speaker.message)
    bubbleX = screenX + GnomeSpriteSize div 2 - bubble.width div 2
    bubbleY = nameY - bubble.height - ChatGapY
  rectVisible(bubbleX, bubbleY, bubble.width, bubble.height,
    ViewportWidth, ViewportHeight)

proc replayChatAudience*(sim: SimServer, speakerSlot: int): seq[int] =
  ## Slots of the OTHER players who would currently see `speakerSlot`'s chat
  ## bubble — everyone in hearing range at this tick. Empty when the speaker
  ## has no active message. Evaluate it on the tick the message is set; the
  ## bubble then lingers (`ChatLifetimeTicks`), so someone who walks up later
  ## can also see it — this captures the audience at the moment of speaking.
  if speakerSlot < 0 or speakerSlot >= sim.players.len:
    return @[]
  let speaker = sim.players[speakerSlot]
  for slot, viewer in sim.players:
    if slot != speakerSlot and sim.replayChatVisibleTo(speaker, viewer):
      result.add(slot)

proc playerMapIndex*(sim: SimServer, playerIndex: int): int =
  ## The map one player is on: 0 outdoors, 1..9 inside that house.
  sim.players[playerIndex].mapIndex

proc playerMessage*(sim: SimServer, playerIndex: int): string =
  ## One player's current chat bubble text.
  sim.players[playerIndex].message

proc worldLayoutFor*(sim: SimServer): WorldLayout =
  ## The static village layout the villager brains navigate.
  for garden in sim.gardens:
    result.gardens.add(garden.rect)
  for i in 0 ..< HouseCount:
    result.houses[i] = sim.houses[i].rect
    result.houseValid[i] = sim.houses[i].valid
  result.exit = sim.homeResources.exit
  result.hasExit = sim.homeResources.hasExit

proc navigationFor*(sim: SimServer): Navigation =
  ## Navigation spaces over the same walk masks the simulation uses.
  let home = sim.homeMaps[0]
  newNavigation(
    sim.mainMap.walkMask, sim.mainMap.width, sim.mainMap.height,
    home.walkMask, home.width, home.height
  )

proc nameTagVisible(sim: SimServer, player: Player, screenX, screenY: int): bool =
  ## Whether a gnome's name tag would be drawn, using the same geometry as
  ## addNameTag without rendering the sprite.
  let
    width = max(1, sim.textFont.textWidth(player.playerName) + NamePadX * 2)
    height = sim.textFont.height + NamePadY * 2
    x = screenX + GnomeSpriteSize div 2 - width div 2
    y = screenY - height - NameGapY
  rectVisible(x, y, width, height, ViewportWidth, ViewportHeight)

proc observe*(sim: SimServer, playerIndex: int): Observation =
  ## What one gnome can see this tick: exactly what its own player view
  ## would draw, read from ground truth instead of sprites.
  let player = sim.players[playerIndex]
  result.tick = sim.tickCount
  result.dayNumber = sim.dayNumber
  result.minutes = sim.currentDayMinutes()
  result.ticksPerMinute = float(sim.dayTicks) / float(DayTotalMinutes)
  result.scene =
    if player.dinnerTicks > 0 or sim.scoreTicks > 0:
      Overlay
    elif player.mapIndex.isHomeMap():
      Indoors
    else:
      Outdoors
  result.currentHouse =
    if player.mapIndex.isHomeMap():
      player.mapIndex - HomeMapIndexBase
    else:
      -1
  result.foot = Point(x: player.playerFootX(), y: player.playerFootY())
  result.inventoryTotal = player.inventory.totalItems()
  result.foodCollectedText = player.inventory.foodListText()
  result.foodLookingForText = player.eaten.foodsNotEatenText()
  result.dinnerDone = sim.dinnerDone
  if player.dinnerTicks > 0 and player.dinnerRecord != nil:
    let record = player.dinnerRecord
    result.dinner = DinnerOutcome(
      present: true,
      hostName: record.hostName,
      wasHost: record.wasHost,
      score: record.score,
      guests: record.guestNames,
      foodsText: record.foods.foodListText()
    )
  if result.scene == Overlay:
    return
  let
    cameraX = sim.cameraXFor(player)
    cameraY = sim.cameraYFor(player)
  for i, other in sim.players:
    if i == playerIndex or other.mapIndex != player.mapIndex:
      continue
    let
      screenX = other.x - cameraX
      screenY = other.y - cameraY
    if not rectVisible(screenX, screenY, GnomeSpriteSize, GnomeSpriteSize,
        ViewportWidth, ViewportHeight):
      continue
    if not sim.nameTagVisible(other, screenX, screenY):
      continue
    var visible = VisiblePlayer(
      name: other.playerName,
      houseIndex: other.homeFlag - HomeMapIndexBase,
      foot: Point(x: other.playerFootX(), y: other.playerFootY())
    )
    visible.distanceSquared = distanceSquared(
      result.foot.x, result.foot.y, visible.foot.x, visible.foot.y
    )
    if other.message.len > 0 and other.messageTicks > 0 and
        sim.replayChatVisibleTo(other, player):
      visible.says = other.message
    result.visiblePlayers.add(visible)
  result.gardenMarkerOnScreen = newSeq[bool](sim.gardens.len)
  result.gardenMarkerVisible = newSeq[bool](sim.gardens.len)
  if result.scene == Outdoors:
    for i, garden in sim.gardens:
      let
        center = garden.rect.center()
        x = center.x - FoodSpriteSize div 2 - cameraX
        y = center.y - FoodSpriteSize div 2 - cameraY
      result.gardenMarkerOnScreen[i] = rectVisible(
        x, y, FoodSpriteSize, FoodSpriteSize, ViewportWidth, ViewportHeight
      )
      result.gardenMarkerVisible[i] =
        result.gardenMarkerOnScreen[i] and garden.hasFood()

proc captureChatFeed(sim: SimServer) =
  ## Queues freshly spoken chats with their audience for the delay chat.
  ## Messages nobody heard are skipped.
  for i, player in sim.players:
    if player.message.len == 0 or player.messageTicks != ChatLifetimeTicks:
      continue
    let audience = sim.replayChatAudience(i)
    if audience.len == 0:
      continue
    var item = ChatFeedItem(
      speaker: ChatFeedPerson(
        name: player.playerName,
        gnomeIndex: player.gnomeIndex
      ),
      message: player.message
    )
    for slot in audience:
      item.hearers.add(ChatFeedPerson(
        name: sim.players[slot].playerName,
        gnomeIndex: sim.players[slot].gnomeIndex
      ))
    sim.chatFeed.add(item)
  while sim.chatFeed.len > ChatFeedMaxItems and sim.chatFeedIndex > 0:
    sim.chatFeed.delete(0)
    dec sim.chatFeedIndex

proc advanceChatFeed*(sim: SimServer) =
  ## Advances the paced delay-chat cursor by one render frame. Queued
  ## messages each stay up long enough to be read, however fast the
  ## simulation is running.
  if sim.chatFeedIndex < 0:
    if sim.chatFeed.len > 0:
      sim.chatFeedIndex = 0
      sim.chatFeedFrames = 0
    return
  inc sim.chatFeedFrames
  if sim.chatFeedFrames >= ChatFeedShowFrames and
      sim.chatFeedIndex + 1 < sim.chatFeed.len:
    inc sim.chatFeedIndex
    sim.chatFeedFrames = 0

proc step*(sim: SimServer, inputs: openArray[InputState]) =
  ## Advances the Heartleaf simulation by one tick.
  inc sim.tickCount
  if sim.scoreTicks > 0:
    dec sim.scoreTicks
    sim.updateMessages()
    if sim.scoreTicks <= 0:
      sim.startDay()
    return

  sim.captureChatFeed()
  for i in 0 ..< sim.players.len:
    let input =
      if i < inputs.len:
        inputs[i]
      else:
        InputState()
    let attackPressed = input.attack and not sim.players[i].attackDown
    if attackPressed:
      sim.interact(i)
    sim.players[i].attackDown = input.attack
    sim.applyInput(i, input)
  for i in 0 ..< sim.players.len:
    sim.moveAxis(sim.players[i], true)
    sim.moveAxis(sim.players[i], false)
  if sim.tickCount mod TrailSampleTicks == 0:
    while sim.trails.len < sim.players.len:
      sim.trails.add(@[])
    for i, player in sim.players:
      sim.trails[i].add(TrailPoint(
        x: player.playerFootX(),
        y: player.playerFootY(),
        mapIndex: player.mapIndex
      ))
      if sim.trails[i].len > TrailMaxPoints:
        sim.trails[i].delete(0)
  sim.updateMessages()
  inc sim.dayTick
  if not sim.dinnerDone and sim.currentDayMinutes() >= DinnerTallyMinutes:
    sim.startDinnerParties()
  if sim.dayTick >= sim.dayTicks:
    sim.startScoreScreen()

proc mixHash(hash: var uint64, value: uint64) =
  ## Mixes one value into a running FNV-1a style hash.
  hash = (hash xor value) * 1099511628211'u64

proc mixHashInt(hash: var uint64, value: int) =
  ## Mixes one integer into a running hash.
  hash.mixHash(cast[uint64](int64(value)))

proc gameHash*(sim: SimServer): uint64 =
  ## Returns a deterministic hash of gameplay state.
  result = 14695981039346656037'u64
  result.mixHashInt(sim.tickCount)
  result.mixHashInt(sim.dayTick)
  result.mixHashInt(sim.dayNumber)
  result.mixHashInt(sim.scoreTicks)
  result.mixHashInt(ord(sim.dinnerDone))
  result.mixHashInt(sim.players.len)
  for player in sim.players:
    result.mixHashInt(player.x)
    result.mixHashInt(player.y)
    result.mixHashInt(player.velX)
    result.mixHashInt(player.velY)
    result.mixHashInt(player.carryX)
    result.mixHashInt(player.carryY)
    result.mixHashInt(ord(player.direction))
    result.mixHashInt(player.gnomeIndex)
    result.mixHashInt(player.homeFlag)
    result.mixHashInt(player.mapIndex)
    result.mixHashInt(player.score)
    result.mixHashInt(player.dinnerTicks)
    result.mixHashInt(player.messageTicks)
    result.mixHashInt(player.message.len)
    result.mixHashInt(ord(player.attackDown))
    for count in player.inventory:
      result.mixHashInt(count)
    for eatenFlag in player.eaten:
      result.mixHashInt(ord(eatenFlag))
  result.mixHashInt(sim.gardens.len)
  for garden in sim.gardens:
    for count in garden.inventory:
      result.mixHashInt(count)

proc applyPlayerChat*(sim: SimServer, playerIndex: int, message: string) =
  ## Shows one chat message above a player's head.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  sim.players[playerIndex].message = message
  sim.players[playerIndex].messageTicks = ChatLifetimeTicks

proc removePlayerAt*(sim: SimServer, playerIndex: int) =
  ## Removes one player from the simulation, compacting indices.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  sim.players.delete(playerIndex)

proc applyReplayEvents(replay: var ReplayPlayer, sim: SimServer) =
  ## Applies replay leaves, joins, inputs, and chats for the current tick.
  let time = tickTime(sim.tickCount)
  while replay.leaveIndex < replay.data.leaves.len and
      replay.data.leaves[replay.leaveIndex].time <= time:
    let leave = replay.data.leaves[replay.leaveIndex]
    if int(leave.player) < 0 or int(leave.player) >= sim.players.len:
      raise newException(ReplayError, "Replay player leave is invalid")
    sim.removePlayerAt(int(leave.player))
    if int(leave.player) < replay.masks.len:
      replay.masks.delete(int(leave.player))
    inc replay.leaveIndex

  while replay.joinIndex < replay.data.joins.len and
      replay.data.joins[replay.joinIndex].time <= time:
    let join = replay.data.joins[replay.joinIndex]
    if int(join.player) != sim.players.len:
      raise newException(ReplayError, "Replay player join order is invalid")
    if sim.addPlayer(join.name, join.slot) != int(join.player):
      raise newException(ReplayError, "Replay player join was rejected")
    replay.ensureReplayPlayer(int(join.player))
    inc replay.joinIndex

  while replay.inputIndex < replay.data.inputs.len and
      replay.data.inputs[replay.inputIndex].time <= time:
    let input = replay.data.inputs[replay.inputIndex]
    replay.ensureReplayPlayer(int(input.player))
    replay.masks[int(input.player)] = input.keys
    inc replay.inputIndex

  while replay.chatIndex < replay.data.chats.len and
      replay.data.chats[replay.chatIndex].time <= time:
    let chat = replay.data.chats[replay.chatIndex]
    sim.applyPlayerChat(int(chat.player), chat.message)
    inc replay.chatIndex

proc checkReplayHash(replay: var ReplayPlayer, sim: SimServer) =
  ## Checks the recorded hash for the current tick, leniently.
  if replay.hashValidationFailed:
    if sim.tickCount >= replay.replayMaxTick():
      replay.playing = false
    return
  if replay.hashIndex >= replay.data.hashes.len:
    replay.playing = false
    return
  let expected = replay.data.hashes[replay.hashIndex]
  if int(expected.tick) < sim.tickCount:
    stderr.writeLine "Replay hash tick is missing at tick " & $sim.tickCount & "."
    replay.hashValidationFailed = true
    replay.hashMismatchTick = sim.tickCount
    return
  if int(expected.tick) > sim.tickCount:
    return
  let hash = sim.gameHash()
  if hash != expected.hash:
    stderr.writeLine "Replay hash mismatch at tick " & $sim.tickCount &
      "; expected " & $expected.hash & ", got " & $hash & "."
    replay.hashValidationFailed = true
    replay.hashMismatchTick = sim.tickCount
    return
  inc replay.hashIndex

proc stepReplay*(replay: var ReplayPlayer, sim: SimServer) =
  ## Advances replay playback by one simulation tick.
  replay.applyReplayEvents(sim)
  var inputs = newSeq[InputState](sim.players.len)
  for playerIndex in 0 ..< sim.players.len:
    replay.ensureReplayPlayer(playerIndex)
    inputs[playerIndex] = decodeInputMask(replay.masks[playerIndex])
  sim.step(inputs)
  replay.checkReplayHash(sim)

proc saveKeyframe(sim: SimServer): string =
  ## Serializes dynamic simulation state for one replay keyframe.
  KeyframeState(
    players: sim.players,
    gardens: sim.gardens,
    houses: sim.houses,
    rng: sim.rng,
    tickCount: sim.tickCount,
    dayTick: sim.dayTick,
    dayTicks: sim.dayTicks,
    dayNumber: sim.dayNumber,
    scoreTicks: sim.scoreTicks,
    dinnerDone: sim.dinnerDone
  ).toFlatty()

proc restoreKeyframe(sim: SimServer, bytes: string) =
  ## Restores dynamic simulation state from one replay keyframe,
  ## keeping loaded asset references untouched.
  let state = bytes.fromFlatty(KeyframeState)
  sim.players = state.players
  sim.gardens = state.gardens
  sim.houses = state.houses
  sim.rng = state.rng
  sim.tickCount = state.tickCount
  sim.dayTick = state.dayTick
  sim.dayTicks = state.dayTicks
  sim.dayNumber = state.dayNumber
  sim.scoreTicks = state.scoreTicks
  sim.dinnerDone = state.dinnerDone

proc buildReplayKeyframes*(
  replay: var ReplayPlayer,
  seed = DefaultSeed,
  dayTicks = DayTicks,
  interval = ReplayKeyframeTicks
) =
  ## Builds serialized seek keyframes across the whole replay.
  replay.keyframes = @[]
  let sim = initSimServer(seed, dayTicks)
  var builder = initReplayPlayer(replay.data)
  builder.looping = false
  replay.keyframes.add(
    builder.saveReplayKeyframe(sim.tickCount, sim.saveKeyframe())
  )
  let maxTick = builder.replayMaxTick()
  while builder.playing and sim.tickCount < maxTick:
    builder.stepReplay(sim)
    if sim.tickCount mod max(interval, 1) == 0 or sim.tickCount == maxTick:
      replay.keyframes.add(
        builder.saveReplayKeyframe(sim.tickCount, sim.saveKeyframe())
      )

proc seekReplay*(replay: var ReplayPlayer, sim: SimServer, tick: int) =
  ## Seeks replay playback to a target tick using seek keyframes.
  if replay.keyframes.len == 0:
    return
  let keyframe = replay.keyframes[replay.replayKeyframeIndex(tick)]
  sim.restoreKeyframe(keyframe.simBytes)
  replay.restoreReplayKeyframeCursors(keyframe)
  sim.trails.setLen(0)
  sim.chatFeed.setLen(0)
  sim.chatFeedIndex = -1
  sim.chatFeedFrames = 0
  while sim.tickCount < tick and replay.hashIndex < replay.data.hashes.len:
    replay.stepReplay(sim)

proc applyReplaySeek*(replay: var ReplayPlayer, sim: SimServer, tick: int) =
  ## Seeks replay playback and pauses on the target tick.
  replay.playing = false
  replay.seekReplay(sim, clamp(tick, 0, replay.replayMaxTick()))

proc applyReplayCommand*(
  replay: var ReplayPlayer,
  sim: SimServer,
  command: char
) =
  ## Applies one replay viewer transport command.
  case command
  of ' ':
    replay.playing = not replay.playing
  of 'p':
    replay.playing = true
  of 'P':
    replay.playing = false
  of '+', '=':
    replay.speedIndex = min(replay.speedIndex + 1, PlaybackSpeeds.high)
  of '-', '_':
    replay.speedIndex = max(replay.speedIndex - 1, 0)
  of '1':
    replay.speedIndex = 0
  of '2':
    replay.speedIndex = 1
  of '3':
    replay.speedIndex = 2
  of '4':
    replay.speedIndex = 3
  of '8':
    replay.speedIndex = 4
  of '6':
    replay.speedIndex = 5
  of ',', '<':
    replay.playing = false
    replay.seekReplay(sim, 0)
  of 'b':
    replay.playing = false
    replay.seekReplay(sim, max(0, sim.tickCount - 1))
  of 'e':
    replay.playing = false
    replay.seekReplay(sim, replay.replayMaxTick())
  of 'r':
    replay.looping = not replay.looping
  of '.', '>':
    replay.playing = false
    replay.seekReplay(sim, sim.tickCount + ReplayFps * 5)
  else:
    discard

when not defined(emscripten):
  proc initAppState() =
    ## Initializes shared websocket state.
    appState = WebSocketAppState()
    initLock(appState.lock)
    appState.playerSlots = initTable[WebSocket, int]()
    appState.globalViewers = initTable[WebSocket, PlayerViewerState]()
    appState.replayViewers = initTable[WebSocket, PlayerViewerState]()
    appState.playerUsernames = initTable[WebSocket, string]()
    appState.souls = initTable[int, Soul]()
    appState.soulSockets = initTable[WebSocket, int]()
    appState.logSent = initTable[WebSocket, int]()
    appState.gameNumber = 1
    appState.closedSockets = @[]
    appState.tokens = @[]
    appState.replayServerMode = false
    appState.replayLoaded = false
    appState.pendingReplayUri = ""

proc globalPanelClickedPlayer(data: string): int =
  ## Returns the clicked global score-panel player index or -1.
  result = -1
  var
    x = 0
    y = 0
    layer = -1
  for item in data.parseSpriteClientMessages():
    case item.kind
    of SpriteClientMouseMoveMessage:
      x = item.x
      y = item.y
      layer =
        if item.hasLayer:
          item.layer
        else:
          -1
    of SpriteClientMouseButtonMessage:
      if layer != GlobalPanelLayerId or item.button != 1'u8 or
          not item.down:
        continue
      if x < GlobalPanelNameX or x >= GlobalPanelWidth:
        continue
      if y < GlobalPanelPad:
        continue
      let row = (y - GlobalPanelPad) div GlobalPanelRowHeight
      if row >= 0 and row < HouseCount:
        return row
    of SpriteClientChatMessage, SpriteClientInputMessage,
        SpriteClientReadyMessage, SpriteClientDebugSpriteMessage,
        SpriteClientSpritesOffMessage:
      discard

proc globalMapClickAt(data: string): tuple[hit: bool, x, y: int] =
  ## Returns the map-layer click position in one viewer packet.
  result = (false, 0, 0)
  var
    x = 0
    y = 0
    layer = -1
  for item in data.parseSpriteClientMessages():
    case item.kind
    of SpriteClientMouseMoveMessage:
      x = item.x
      y = item.y
      layer =
        if item.hasLayer:
          item.layer
        else:
          -1
    of SpriteClientMouseButtonMessage:
      if layer == MapLayerId and item.button == 1'u8 and item.down:
        return (true, x, y)
    of SpriteClientChatMessage, SpriteClientInputMessage,
        SpriteClientReadyMessage, SpriteClientDebugSpriteMessage,
        SpriteClientSpritesOffMessage:
      discard

proc applyReplayViewerMessage(state: PlayerViewerState, data: string) =
  ## Applies mouse and replay command input from one viewer message.
  for item in data.parseSpriteClientMessages():
    case item.kind
    of SpriteClientMouseMoveMessage:
      state.mouseX = item.x
      state.mouseY = item.y
      state.mouseLayer =
        if item.hasLayer:
          item.layer
        else:
          MapLayerId
    of SpriteClientMouseButtonMessage:
      if item.button == 0x01'u8:
        state.mouseDown = item.down
        if item.down:
          state.clickPending = true
          state.mousePressX = state.mouseX
          state.mousePressY = state.mouseY
          state.mousePressLayer = state.mouseLayer
        else:
          state.scrubbingReplay = false
    of SpriteClientChatMessage:
      for ch in item.text:
        state.replayCommands.add(ch)
    of SpriteClientInputMessage, SpriteClientReadyMessage,
        SpriteClientDebugSpriteMessage, SpriteClientSpritesOffMessage:
      discard

proc drainReplayViewerInput(
  state: PlayerViewerState,
  maxTick: int,
  seekTicks: var seq[int],
  commands: var seq[char]
) =
  ## Collects pending replay seeks and commands from one viewer.
  ## Score-panel clicks are handled first in the websocket handler;
  ## the panel, scrubber, and transport live on distinct layers, so
  ## a panel click never reaches the scrubber or transport checks.
  state.replaySeekTick = -1
  if state.clickPending:
    state.clickPending = false
    let seekTick = replayScrubTickAt(
      state.mousePressLayer,
      state.mousePressX,
      state.mousePressY,
      maxTick
    )
    if seekTick >= 0:
      state.scrubbingReplay = true
      state.replaySeekTick = seekTick
    else:
      let command = replayCommandAt(
        state.mousePressLayer,
        state.mousePressX,
        state.mousePressY
      )
      if command != '\0':
        state.replayCommands.add(command)
  if state.mouseDown and state.scrubbingReplay:
    let seekTick = replayScrubTickAt(
      state.mouseLayer,
      state.mouseX,
      state.mouseY,
      maxTick
    )
    if seekTick >= 0:
      state.replaySeekTick = seekTick
  if state.replaySeekTick >= 0:
    seekTicks.add(state.replaySeekTick)
  state.replaySeekTick = -1
  for command in state.replayCommands:
    commands.add(command)
  state.replayCommands.setLen(0)

proc newReplayViewerState*(): PlayerViewerState =
  ## Creates one replay viewer state with nothing selected.
  PlayerViewerState(selectedPlayerIndex: -1)

proc handleReplayViewerPacket*(state: PlayerViewerState, data: string) =
  ## Applies one raw sprite-client packet from a local viewer: the
  ## score-panel selection toggle, house-inset map clicks, and mouse,
  ## scrubber, and transport state. Mirrors websocketHandler.
  when defined(replayViewerDebug):
    for item in data.parseSpriteClientMessages():
      case item.kind
      of SpriteClientMouseMoveMessage:
        echo "debug mouse move x=", item.x, " y=", item.y,
          " layer=", (if item.hasLayer: item.layer else: -1)
      of SpriteClientMouseButtonMessage:
        echo "debug mouse button=", item.button, " down=", item.down
      else:
        discard
  let clickedPlayer = data.globalPanelClickedPlayer()
  if clickedPlayer >= 0:
    state.selectedPlayerIndex =
      if state.selectedPlayerIndex == clickedPlayer:
        -1
      else:
        clickedPlayer
    when defined(replayViewerDebug):
      echo "debug clickedPlayer=", clickedPlayer,
        " selected=", state.selectedPlayerIndex
  let mapClick = data.globalMapClickAt()
  if mapClick.hit:
    state.pendingMapClick = true
    state.pendingMapClickX = mapClick.x
    state.pendingMapClickY = mapClick.y
  state.applyReplayViewerMessage(data)

proc replayViewerFrame*(
  sim: SimServer,
  replay: var ReplayPlayer,
  state: var PlayerViewerState,
  replayLoaded: bool
): seq[uint8] =
  ## Advances one replay viewer frame for a single local viewer and
  ## returns the sprite packet to render: pending seeks and transport
  ## commands, playback stepping with loop restart, the delay chat
  ## pacing, and the global packet build.
  var
    seekTicks: seq[int]
    commands: seq[char]
  state.drainReplayViewerInput(replay.replayMaxTick(), seekTicks, commands)
  if replayLoaded:
    for seekTick in seekTicks:
      replay.applyReplaySeek(sim, seekTick)
    for command in commands:
      replay.applyReplayCommand(sim, command)
    if replay.playing:
      for _ in 0 ..< replay.replaySpeed():
        if replay.playing:
          replay.stepReplay(sim)
      if replay.looping and not replay.playing and
          replay.replayMaxTick() > 0:
        replay.seekReplay(sim, 0)
        replay.playing = true
  sim.advanceChatFeed()
  var nextState: PlayerViewerState
  result = sim.buildGlobalPacket(
    state,
    nextState,
    replayControls = replayLoaded,
    replayTick = sim.tickCount,
    replaySpeed = replay.replaySpeed(),
    replayMaxTick = replay.replayMaxTick(),
    replayPlaying = replay.playing,
    replayLooping = replay.looping,
    replayMismatchTick = replay.hashMismatchTick
  )
  state = nextState

when not defined(emscripten):
  proc removePlayer(sim: SimServer, websocket: WebSocket) =
    ## Forgets one websocket. Gnomes are owned by their souls, not their
    ## sockets, so a dropped player connection leaves the village as it is.
    if websocket in appState.replayViewers:
      appState.replayViewers.del(websocket)
    if websocket in appState.globalViewers:
      appState.globalViewers.del(websocket)
    if websocket in appState.playerSlots:
      appState.playerSlots.del(websocket)
    if websocket in appState.playerUsernames:
      appState.playerUsernames.del(websocket)
    if websocket in appState.soulSockets:
      appState.soulSockets.del(websocket)
    if websocket in appState.logSent:
      appState.logSent.del(websocket)

  proc resetConnectedPlayers() =
    ## Resets log cursors for a fresh simulation: the next game's log
    ## starts again at sequence 0.
    for websocket in appState.logSent.keys:
      appState.logSent[websocket] = 0

  proc freeSeatForSoul(): int =
    ## The lowest seat without a soul, or -1 when the village is full.
    let seatLimit =
      if appState.tokens.len > 0:
        appState.tokens.len
      else:
        HouseCount
    for seat in 0 ..< seatLimit:
      if seat notin appState.souls:
        return seat
    -1

  proc acceptSoul(websocket: WebSocket, raw: string): string =
    ## Stores the soul a player socket sent and returns the reply text.
    ## Souls are immutable for the episode; an identical resend is fine.
    if websocket in appState.soulSockets:
      let seat = appState.soulSockets[websocket]
      if appState.souls[seat].raw == raw:
        return appState.souls[seat].soulReply()
      return soulRejection("seat " & $seat & " already has a soul")
    var soul: Soul
    try:
      soul = parseSoul(raw)
    except SoulError as e:
      echo "soul rejected from ", appState.playerUsernames.getOrDefault(
        websocket, ""), ": ", e.msg
      return soulRejection(e.msg)
    var seat = appState.playerSlots.getOrDefault(websocket, -1)
    if seat < 0:
      seat = freeSeatForSoul()
      if seat < 0:
        return soulRejection("no free seat")
    if seat >= HouseCount:
      return soulRejection("seat " & $seat & " does not exist")
    if seat in appState.souls:
      if appState.souls[seat].raw == raw:
        appState.soulSockets[websocket] = seat
        return appState.souls[seat].soulReply()
      return soulRejection("seat " & $seat & " already has a soul")
    soul.seat = seat
    soul.username = appState.playerUsernames.getOrDefault(websocket, "")
    appState.souls[seat] = soul
    appState.soulSockets[websocket] = seat
    appState.playerSlots[websocket] = seat
    echo "soul accepted seat=", seat, " model=", soul.modelId,
      " bytes=", raw.len, " username=", soul.username
    if not soul.modelId.knownModelFamily():
      echo "soul seat=", seat, " names an unfamiliar model: ", soul.modelId
    soul.soulReply()

  proc parseLogCursor(text: string): tuple[game, sequence: int] =
    ## Reads "log-cursor game=N sequence=M"; missing parts read as 0 / -1.
    result = (game: 0, sequence: -1)
    for part in text[LogCursorPrefix.len .. ^1].splitWhitespace():
      let pair = part.split('=')
      if pair.len != 2:
        continue
      try:
        if pair[0] == "game":
          result.game = parseInt(pair[1])
        elif pair[0] == "sequence":
          result.sequence = parseInt(pair[1])
      except ValueError:
        discard

  proc declarePlayerFailure(seat: int, message: string) =
    ## Reports one seat as the reason the episode cannot go on. Hosted runs
    ## write the Coworld player failure artifact and exit without results;
    ## local runs only log it.
    echo "player failure seat=", seat, ": ", message
    if getEnv(CogamePlayerFailureUriEnv).len == 0:
      return
    writeCogameEnv(
      CogamePlayerFailureUriEnv,
      $(%*{"message": message, "failed_policy_index": seat}),
      "application/json"
    )
    quit(1)

  proc isWebSocketUpgrade(request: Request): bool =
    ## Returns true when the request is a websocket upgrade.
    request.headers["Sec-WebSocket-Key"].len > 0

  proc respondPlain(request: Request, status: int, body: string) =
    ## Sends a no-cache plain text response.
    var headers: HttpHeaders
    headers["Content-Type"] = "text/plain; charset=utf-8"
    headers["Cache-Control"] = "no-cache"
    request.respond(status, headers, body)

  proc serveHealthz(request: Request): bool =
    ## Serves the container health check endpoint.
    if request.path != HealthzPath or request.httpMethod notin ["GET", "HEAD"]:
      return false
    request.respondPlain(200, "healthy")
    return true

  proc playerSlot(request: Request): int =
    ## Returns the requested zero-based slot or -1 for automatic assignment.
    let text = request.queryParams.getOrDefault("slot", "").strip()
    if text.len == 0:
      return -1
    try:
      result = parseInt(text)
    except ValueError:
      return int.high
    if result < 0:
      return int.high

  proc playerToken(request: Request): string =
    ## Returns the requested player token.
    request.queryParams.getOrDefault("token", "").strip()

  proc playerUsername(request: Request, slot: int): string =
    ## Returns the display username for one joining player. The hosted
    ## `players[].name` config entry for the slot is authoritative; the
    ## `username` or `name` query parameter is the local-play fallback.
    if slot >= 0 and slot < appState.playerNames.len and
        appState.playerNames[slot].len > 0:
      return appState.playerNames[slot].cleanUsername()
    let username = request.queryParams.getOrDefault("username", "")
    if username.len > 0:
      return username.cleanUsername()
    return request.queryParams.getOrDefault("name", "").cleanUsername()

  proc playerJoinAllowed(slot: int, token: string): bool =
    ## Returns true when the configured token list accepts a join.
    if appState.tokens.len == 0:
      return true
    if slot >= 0 and slot < appState.tokens.len:
      return token == appState.tokens[slot]
    if slot == -1:
      return token in appState.tokens
    return false

  proc replayFilePath(uri: string): string =
    ## Resolves one local replay URI to a host path.
    const FilePrefix = "file://"
    if uri.startsWith(FilePrefix):
      return uri[FilePrefix.len .. ^1]
    if "://" in uri:
      return ""
    uri

  let replayDownloadPool = newCurlPool(1)

  proc loadReplayUri(uri: string): ReplayData =
    ## Loads a replay from a local file URI or HTTP(S) URL.
    parseReplayBytes(readCogameUri(uri, CogameLoadReplayUriEnv))

  proc readableReplayUri(uri: string): bool =
    ## Returns true when a replay URI can be opened by this server.
    if uri.len == 0:
      return false
    if uri.startsWith("http://") or uri.startsWith("https://"):
      return replayDownloadPool.head(uri).code == 200
    let path = replayFilePath(uri)
    path.len > 0 and fileExists(path)

  proc replayRequestUri(request: Request): string =
    ## Returns the replay artifact URI requested by a Coworld replay client.
    request.queryParams.getOrDefault("uri", "").strip()

  proc checkReplayRequest(request: Request): bool =
    ## Validates one replay page or websocket request, capturing the
    ## requested replay URI for the playback loop. Returns false after
    ## responding with an error.
    result = true
    var
      replayServerMode = false
      replayLoaded = false
    {.gcsafe.}:
      withLock appState.lock:
        replayServerMode = appState.replayServerMode
        replayLoaded = appState.replayLoaded
    if not replayServerMode:
      return true
    let uri = request.replayRequestUri()
    if uri.len == 0:
      if replayLoaded:
        return true
      request.respondPlain(400, "missing replay uri\n")
      return false
    var readable = false
    {.gcsafe.}:
      readable = uri.readableReplayUri()
    if not readable:
      request.respondPlain(404, "replay uri is not readable\n")
      return false
    {.gcsafe.}:
      withLock appState.lock:
        appState.pendingReplayUri = uri
    return true

  proc httpHandler(request: Request) =
    ## Handles Heartleaf HTTP and websocket routes.
    if request.serveHealthz():
      discard
    elif request.path == WebSocketPath and request.httpMethod == "GET" and
        not request.isWebSocketUpgrade():
      request.respondPlain(426, "websocket required\n")
    elif request.path == GlobalWebSocketPath and request.httpMethod == "GET" and
        not request.isWebSocketUpgrade():
      discard bitworldClient.serveClientFile(
        request,
        bitworldClient.GlobalClientRoute,
        bitworldClient.GlobalClientRoute
      )
    elif request.path == ReplayWebSocketPath and request.httpMethod == "GET" and
        not request.isWebSocketUpgrade():
      if not request.checkReplayRequest():
        return
      discard bitworldClient.serveClientFile(
        request,
        bitworldClient.ReplayClientRoute,
        bitworldClient.GlobalClientRoute
      )
    elif request.path == WebSocketPath and request.httpMethod == "GET" and
        request.isWebSocketUpgrade():
      let
        slot = request.playerSlot()
        token = request.playerToken()
      var
        allowed = false
        username = ""
      {.gcsafe.}:
        withLock appState.lock:
          allowed = playerJoinAllowed(slot, token)
          username = request.playerUsername(slot)
      if not allowed:
        request.respondPlain(403, "player token rejected\n")
        return
      let websocket = request.upgradeToWebSocket()
      {.gcsafe.}:
        withLock appState.lock:
          appState.playerSlots[websocket] = slot
          appState.playerUsernames[websocket] = username
    elif request.path == GlobalWebSocketPath and request.httpMethod == "GET" and
        request.isWebSocketUpgrade():
      let websocket = request.upgradeToWebSocket()
      {.gcsafe.}:
        withLock appState.lock:
          appState.globalViewers[websocket] = PlayerViewerState(
            selectedPlayerIndex: -1
          )
    elif request.path == ReplayWebSocketPath and request.httpMethod == "GET" and
        request.isWebSocketUpgrade():
      if not request.checkReplayRequest():
        return
      let websocket = request.upgradeToWebSocket()
      {.gcsafe.}:
        withLock appState.lock:
          appState.replayViewers[websocket] = PlayerViewerState(
            selectedPlayerIndex: -1
          )
    elif request.path in [
        bitworldClient.ReplayClientRoute,
        bitworldClient.CoworldReplayClientRoute
      ] and request.httpMethod == "GET":
      if not request.checkReplayRequest():
        return
      discard bitworldClient.serveClientFile(
        request,
        request.path,
        bitworldClient.GlobalClientRoute
      )
    elif bitworldClient.serveClientRoute(
      request,
      bitworldClient.GlobalClientRoute
    ):
      discard
    else:
      request.respondPlain(200, "Heartleaf sprite protocol server")

  proc websocketHandler(
    websocket: WebSocket,
    event: WebSocketEvent,
    message: Message
  ) =
    ## Handles websocket ping, soul uploads, viewer clicks, and close events.
    case event
    of OpenEvent:
      discard
    of MessageEvent:
      if message.kind == Ping:
        websocket.send(message.data, Pong)
        return
      if message.kind == Pong:
        return
      if message.kind == TextMessage:
        {.gcsafe.}:
          withLock appState.lock:
            if websocket in appState.soulSockets and
                message.data.startsWith(LogCursorPrefix):
              # A reconnecting collector tells us what it already has, so
              # the backlog resumes instead of replaying from the start.
              let cursor = parseLogCursor(message.data)
              if cursor.game == appState.gameNumber:
                appState.logSent[websocket] = max(0, cursor.sequence + 1)
              else:
                appState.logSent[websocket] = 0
            elif websocket in appState.playerSlots:
              # Reply while still holding the lock: the loop streams log
              # records under the same lock, so nothing can overtake the
              # acceptance on this socket.
              let reply = acceptSoul(websocket, message.data)
              if reply.len > 0:
                websocket.send(reply, TextMessage)
        return
      let clickedPlayer =
        if message.kind == BinaryMessage:
          message.data.globalPanelClickedPlayer()
        else:
          -1
      if clickedPlayer >= 0:
        {.gcsafe.}:
          withLock appState.lock:
            if websocket in appState.globalViewers:
              let state = appState.globalViewers[websocket]
              state.selectedPlayerIndex =
                if state.selectedPlayerIndex == clickedPlayer:
                  -1
                else:
                  clickedPlayer
            elif websocket in appState.replayViewers:
              let state = appState.replayViewers[websocket]
              state.selectedPlayerIndex =
                if state.selectedPlayerIndex == clickedPlayer:
                  -1
                else:
                  clickedPlayer
      let mapClick =
        if message.kind == BinaryMessage:
          message.data.globalMapClickAt()
        else:
          (hit: false, x: 0, y: 0)
      if mapClick.hit:
        {.gcsafe.}:
          withLock appState.lock:
            var state: PlayerViewerState
            if websocket in appState.globalViewers:
              state = appState.globalViewers[websocket]
            elif websocket in appState.replayViewers:
              state = appState.replayViewers[websocket]
            if state != nil:
              state.pendingMapClick = true
              state.pendingMapClickX = mapClick.x
              state.pendingMapClickY = mapClick.y
      if message.kind == BinaryMessage:
        {.gcsafe.}:
          withLock appState.lock:
            if appState.replayServerMode:
              if websocket in appState.replayViewers:
                appState.replayViewers[websocket].applyReplayViewerMessage(
                  message.data
                )
              elif websocket in appState.globalViewers:
                appState.globalViewers[websocket].applyReplayViewerMessage(
                  message.data
                )
      # Button masks and chat from /player sockets are ignored: souls play.
    of ErrorEvent:
      discard
    of CloseEvent:
      {.gcsafe.}:
        withLock appState.lock:
          appState.closedSockets.add(websocket)

  proc serverThreadProc(args: ServerThreadArgs) {.thread.} =
    ## Runs the mummy server on a background thread.
    args.server[].serve(Port(args.port), args.address)

  proc runFrameLimiter(previousTick: var MonoTime) =
    ## Sleeps until the next simulation frame should run.
    let frameDuration = initDuration(milliseconds = int(1000.0 / TargetFps))
    let elapsed = getMonoTime() - previousTick
    if elapsed < frameDuration:
      sleep(int((frameDuration - elapsed).inMilliseconds))
    previousTick = getMonoTime()

  proc writeArtifacts(
    sim: SimServer,
    runtimeConfig: RuntimeConfig
  ) =
    ## Writes the results artifact for the current day.
    runtimeConfig.writeResults(sim.dailyResultsJson() & "\n")

  proc runServerLoop*(
    host = DefaultHost,
    port = DefaultPort,
    seed = DefaultSeed,
    maxTicks = DefaultMaxTicks,
    maxDays = 0,
    maxGames = DefaultMaxGames,
    daySeconds = DefaultDaySeconds,
    tokens: seq[string] = @[],
    playerNames: seq[string] = @[],
    soulTimeoutSeconds = DefaultSoulTimeoutSeconds,
    soulConnectionRequired = false,
    mockReply = "",
    saveReplayPath = "",
    runtimeConfig = RuntimeConfig()
  ) =
    ## Runs the Heartleaf websocket game server. A seat comes alive when its
    ## soul arrives; with tokens configured the village waits for every seat
    ## (or the soul timeout) before day 1 starts, so nobody misses a morning.
    initAppState()
    appState.tokens = tokens
    appState.playerNames = playerNames
    let dayTicks = max(1, daySeconds) * TicksPerSecond
    let totalTicks =
      if maxDays > 0:
        gameTicksForDays(maxDays, dayTicks)
      else:
        maxTicks
    let deadlineProblem = hostedDeadlineProblem(totalTicks)
    if deadlineProblem.len > 0:
      echo "fatal: ", deadlineProblem
      quit(1)
    var replayWriter = openReplayWriter(
      saveReplayPath,
      $(%*{
        "seed": seed,
        "maxTicks": totalTicks,
        "maxGames": maxGames,
        "daySeconds": daySeconds,
        "tokenCount": tokens.len
      })
    )
    var
      sim = initSimServer(seed, dayTicks)
      lastTick: MonoTime
      runTicks = 0
      gamesFinished = 0
      lastWrittenDay = 0
      seatPlayers: array[HouseCount, int]
      simStarted = tokens.len == 0
      pausedSince = 0.0
    for seat in 0 ..< HouseCount:
      seatPlayers[seat] = -1
    if tokens.len > 0:
      sim.seatCount = tokens.len
    if tokens.len > 0 and not bedrockConfigured(mockReply):
      echo "fatal: ", BedrockNotConfiguredMessage
      quit(1)
    if mockReply.len > 0:
      echo "model mocked by config: every decision is ", mockReply
    let brains = newBrains(
      sim.navigationFor(),
      sim.worldLayoutFor(),
      newBedrockClient(HouseCount, mockReply),
      seed
    )
    brains.onSeatFailure = proc(seat: int, message: string) =
      declarePlayerFailure(seat, message)
    # Load assets before healthz so /global can send on the first tick.
    let httpServer = newServer(
      httpHandler,
      websocketHandler,
      workerThreads = 4,
      tcpNoDelay = true
    )
    var serverThread: Thread[ServerThreadArgs]
    var serverPtr = cast[ptr Server](unsafeAddr httpServer)
    createThread(
      serverThread,
      serverThreadProc,
      ServerThreadArgs(server: serverPtr, address: host, port: port)
    )
    httpServer.waitUntilReady()
    lastTick = getMonoTime()
    let soulDeadline = epochTime() + soulTimeoutSeconds.float
    if not simStarted:
      echo "waiting for ", tokens.len, " souls (", soulTimeoutSeconds, "s)"

    while true:
      var
        globalSockets: seq[WebSocket] = @[]
        globalStates: seq[PlayerViewerState] = @[]
        inputs: seq[InputState]
        waitingSeats: seq[int] = @[]

      {.gcsafe.}:
        withLock appState.lock:
          for websocket in appState.closedSockets:
            if soulConnectionRequired and websocket in appState.soulSockets:
              let seat = appState.soulSockets[websocket]
              declarePlayerFailure(
                seat,
                "Seat " & $seat & " disconnected after sending its soul"
              )
            sim.removePlayer(websocket)
          appState.closedSockets.setLen(0)

          for seat, soul in appState.souls.pairs:
            if seatPlayers[seat] >= 0:
              continue
            let playerIndex = sim.addPlayer(soul.username, seat)
            if playerIndex < 0:
              continue
            seatPlayers[seat] = playerIndex
            echo "seat ", seat, " joined as ",
              sim.players[playerIndex].playerName, " (", soul.username, ")"
            brains.attachSoul(seat, soul)
            if replayWriter.enabled:
              replayWriter.writeJoin(
                tickTime(sim.tickCount),
                playerIndex,
                soul.username,
                seat,
                soul.modelId
              )
              while replayWriter.lastMasks.len < sim.players.len:
                replayWriter.lastMasks.add(0)

          if not simStarted:
            waitingSeats = seatsWaitingForSouls(tokens.len, appState.souls)

          for websocket, state in appState.globalViewers.pairs:
            globalSockets.add(websocket)
            globalStates.add(state)

      if not simStarted:
        if waitingSeats.len == 0:
          simStarted = true
          echo "all souls received, starting day 1"
        elif epochTime() >= soulDeadline:
          declarePlayerFailure(
            waitingSeats[0],
            "Seat " & $waitingSeats[0] & " sent no soul file within " &
              $soulTimeoutSeconds & "s"
          )
          echo "starting without seats ", waitingSeats.join(", ")
          simStarted = true

      var observations = initTable[int, Observation]()
      for seat in 0 ..< HouseCount:
        if seatPlayers[seat] >= 0:
          observations[seat] = sim.observe(seatPlayers[seat])
      let frame = brains.advance(observations, epochTime())
      let paused = not simStarted or frame.paused
      if paused:
        if pausedSince == 0.0:
          pausedSince = epochTime()
          if simStarted:
            echo "sim paused: waiting on ", frame.blockedNames.join(", ")
        sim.advanceChatFeed()
      else:
        if pausedSince > 0.0:
          echo "sim resumed after ",
            formatFloat(epochTime() - pausedSince, ffDecimal, 1), "s"
          pausedSince = 0.0
        inputs = newSeq[InputState](sim.players.len)
        for item in frame.outputs:
          let playerIndex = seatPlayers[item.houseIndex]
          if playerIndex < 0 or playerIndex >= inputs.len:
            continue
          inputs[playerIndex] = decodeInputMask(item.output.mask)
          replayWriter.writeInputMaskChange(
            tickTime(sim.tickCount),
            playerIndex,
            item.output.mask
          )
          let chatText = item.output.chat.cleanChatMessage()
          if chatText.len > 0:
            sim.applyPlayerChat(playerIndex, chatText)
            replayWriter.writeChat(
              tickTime(sim.tickCount),
              playerIndex,
              chatText
            )
        let wasScoring = sim.scoreTicks > 0
        sim.step(inputs)
        sim.advanceChatFeed()
        replayWriter.writeHash(uint32(sim.tickCount), sim.gameHash())
        if not wasScoring and sim.scoreTicks > 0:
          sim.writeArtifacts(runtimeConfig)
          lastWrittenDay = sim.dayNumber
        inc runTicks

      # Stream each seat's model log to the player that sent its soul:
      # every turn appended to the history, plus notes, exactly once.
      var logDrops: seq[WebSocket]
      {.gcsafe.}:
        withLock appState.lock:
          for websocket, seat in appState.soulSockets.pairs:
            if seat notin brains.villagers:
              continue
            let entries = brains.villagers[seat].logEntries
            var sent = appState.logSent.getOrDefault(websocket, 0)
            try:
              while sent < entries.len:
                websocket.send(entries[sent], TextMessage)
                inc sent
            except CatchableError:
              logDrops.add(websocket)
            appState.logSent[websocket] = sent
          for websocket in logDrops:
            sim.removePlayer(websocket)

      for i in 0 ..< globalSockets.len:
        var nextState: PlayerViewerState
        let packet = sim.buildGlobalPacket(globalStates[i], nextState)
        try:
          globalSockets[i].sendSpritePacket(packet)
          {.gcsafe.}:
            withLock appState.lock:
              if globalSockets[i] in appState.globalViewers:
                appState.globalViewers[globalSockets[i]] = nextState
        except CatchableError:
          {.gcsafe.}:
            withLock appState.lock:
              sim.removePlayer(globalSockets[i])

      if totalTicks > 0 and runTicks >= totalTicks:
        if lastWrittenDay == 0:
          sim.writeArtifacts(runtimeConfig)
        if replayWriter.enabled:
          # Only the first game of a run is recorded and uploaded.
          replayWriter.closeReplayWriter()
          if fileExists(saveReplayPath):
            echo "Replay written: ", saveReplayPath,
              " (", getFileSize(saveReplayPath), " bytes)"
            runtimeConfig.writeReplay(readFile(saveReplayPath))
        inc gamesFinished
        if maxGames > 0 and gamesFinished >= maxGames:
          quit(0)
        sim = initSimServer(seed + gamesFinished, dayTicks)
        if tokens.len > 0:
          sim.seatCount = tokens.len
        runTicks = 0
        lastWrittenDay = 0
        for seat in 0 ..< HouseCount:
          seatPlayers[seat] = -1
        brains.resetForNewGame()
        {.gcsafe.}:
          withLock appState.lock:
            appState.gameNumber = brains.gameNumber
            resetConnectedPlayers()

      runFrameLimiter(lastTick)

proc readConfigString(node: JsonNode, name: string, value: var string) =
  ## Reads one optional string config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JString:
    raise newException(
      HeartleafError,
      "Config field " & name & " must be a string."
    )
  value = item.getStr()

proc readConfigInt(node: JsonNode, name: string, value: var int) =
  ## Reads one optional integer config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JInt:
    raise newException(
      HeartleafError,
      "Config field " & name & " must be an integer."
    )
  value = item.getInt()

proc readConfigBool(node: JsonNode, name: string, value: var bool) =
  ## Reads one optional boolean config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JBool:
    raise newException(
      HeartleafError,
      "Config field " & name & " must be a boolean."
    )
  value = item.getBool()

proc readConfigStrings(node: JsonNode, name: string, value: var seq[string]) =
  ## Reads one optional string array config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JArray:
    raise newException(
      HeartleafError,
      "Config field " & name & " must be an array."
    )
  value.setLen(0)
  for child in item.items:
    if child.kind != JString:
      raise newException(
        HeartleafError,
        "Config field " & name & " items must be strings."
      )
    value.add(child.getStr())

proc readConfigPlayerNames(node: JsonNode, value: var seq[string]) =
  ## Reads the optional Coworld `players[].name` display names by slot.
  if not node.hasKey("players"):
    return
  let item = node["players"]
  if item.kind != JArray:
    raise newException(HeartleafError, "Config field players must be an array.")
  value.setLen(0)
  for child in item.items:
    if child.kind != JObject or not child.hasKey("name") or
        child["name"].kind != JString:
      raise newException(
        HeartleafError,
        "Config field players items must be objects with a string name."
      )
    value.add(child["name"].getStr())

proc seedPinned*(configJson: string): bool =
  ## True when the runtime config pins a seed other than DefaultSeed.
  if configJson.len == 0:
    return false
  try:
    let node = parseJson(configJson)
    node.kind == JObject and node.hasKey("seed") and
      node["seed"].getInt != DefaultSeed
  except CatchableError:
    false

proc randomSeed*(): int =
  ## A crypto-random 31-bit seed from the OS.
  when defined(emscripten):
    raise newException(HeartleafError, "OS entropy source unavailable.")
  else:
    var buf: array[4, byte]
    if not urandom(buf):
      raise newException(HeartleafError, "OS entropy source unavailable.")
    (int(buf[0]) shl 24 or int(buf[1]) shl 16 or
      int(buf[2]) shl 8 or int(buf[3])) and 0x7FFF_FFFF

proc stripUnpinnedSeed*(configJson: string): string =
  ## Drops the DefaultSeed sentinel so it cannot clobber a randomized seed.
  if configJson.len == 0:
    return configJson
  try:
    let node = parseJson(configJson)
    if node.kind == JObject and node.hasKey("seed"):
      node.delete("seed")
    $node
  except CatchableError:
    configJson

proc update(config: var RunConfig, jsonText: string) =
  ## Updates the run config from a JSON object.
  if jsonText.len == 0:
    return
  var node: JsonNode
  try:
    node = fromJson(jsonText)
  except jsony.JsonError as e:
    raise newException(
      HeartleafError,
      "Could not parse config JSON: " & e.msg
    )
  if node.kind != JObject:
    raise newException(HeartleafError, "Config must be a JSON object.")
  node.readConfigString("address", config.address)
  node.readConfigInt("port", config.port)
  node.readConfigInt("seed", config.seed)
  node.readConfigInt("maxTicks", config.maxTicks)
  node.readConfigInt("max-ticks", config.maxTicks)
  node.readConfigInt("maxDays", config.maxDays)
  node.readConfigInt("maxGames", config.maxGames)
  node.readConfigInt("max-games", config.maxGames)
  node.readConfigInt("daySeconds", config.daySeconds)
  node.readConfigInt("day-seconds", config.daySeconds)
  node.readConfigInt("soulTimeoutSeconds", config.soulTimeoutSeconds)
  node.readConfigBool("soulConnectionRequired", config.soulConnectionRequired)
  node.readConfigString("mockReply", config.mockReply)
  node.readConfigStrings("tokens", config.tokens)
  # Seat i spawns in house i, so more tokens than houses can never all
  # join. Fewer tokens is fine: the remaining houses simply stay empty.
  if config.tokens.len > HouseCount:
    raise newException(
      HeartleafError,
      "Config field tokens lists " & $config.tokens.len &
        " seats but Heartleaf has only " & $HouseCount &
        " houses; use at most " & $HouseCount & " tokens."
    )
  node.readConfigPlayerNames(config.playerNames)

proc limitText(value: int): string =
  ## Returns a readable text value for a numeric limit.
  if value > 0:
    $value
  else:
    "infinite"

proc echoStartupConfig(config: RunConfig) =
  ## Prints the effective startup config without token secrets.
  echo "Heartleaf config: host=", config.address,
    " port=", config.port,
    " seed=", config.seed,
    " tokens=", config.tokens.len,
    " playerNames=", config.playerNames.len,
    " maxTicks=", config.maxTicks.limitText(),
    " maxDays=", config.maxDays.limitText(),
    " maxGames=", config.maxGames.limitText(),
    " daySeconds=", config.daySeconds,
    " soulTimeoutSeconds=", config.soulTimeoutSeconds,
    " soulConnectionRequired=", config.soulConnectionRequired,
    " mockReply=", (if config.mockReply.len > 0: "yes" else: "no")

proc replayRunConfigFor(data: ReplayData): RunConfig =
  ## Reads the recorded simulation config from a replay header.
  result = RunConfig(
    address: DefaultHost,
    port: DefaultPort,
    seed: DefaultSeed,
    maxTicks: DefaultMaxTicks,
    maxGames: DefaultMaxGames,
    daySeconds: DefaultDaySeconds,
    tokens: @[],
    soulTimeoutSeconds: DefaultSoulTimeoutSeconds
  )
  result.update(data.configJson)

# ---------------------------------------------------------------------------
# Replay inspection (tooling)
#
# A small, read-only snapshot API for off-line replay analysis (see
# tools/expand_replay.nim). The core `Player`/`SimServer`/`Garden` fields are
# module-private, so this exposes exactly the per-tick state an analysis tool
# needs to re-simulate a replay and read out positions and events — no more.
# ---------------------------------------------------------------------------

type
  ReplayPlayerSnapshot* = object
    slot*: int                ## player index (join order == gnome slot)
    username*: string         ## connection username (varies game to game)
    playerName*: string       ## chosen display name (stable identity)
    x*, y*: int               ## foot-centre position in the CURRENT map's pixels
    direction*: string        ## "north" | "south" | "east" | "west"
    mapIndex*: int            ## 0 = main map, 1..HouseCount = a home map
    houseIndex*: int          ## -1 on the main map, else the house they are inside
    homeIndex*: int           ## the player's OWN house (0-based), -1 if unassigned
    inventory*: seq[int]      ## per-veggie carried counts (len == FoodVeggieSlots)
    inventoryTotal*: int      ## sum of `inventory`
    score*: int               ## cumulative hosting score
    message*: string          ## current chat-bubble text ("" when none)
    messageTicks*: int        ## ticks the current message has left
    dinnerCount*: int         ## number of completed dinners recorded so far
    dinnerTicks*: int         ## ticks into the current dinner (0 when not dining)
    lastDinnerHost*: string   ## host name of the most recent completed dinner
    lastDinnerWasHost*: bool  ## whether THIS player hosted that dinner
    lastDinnerGuests*: int    ## guest count of that dinner
    lastDinnerFood*: int      ## total food served at it
    lastDinnerScore*: int     ## score it awarded

  ReplayGardenSnapshot* = object
    index*: int               ## garden index (matches sim garden order)
    centerX*, centerY*: int   ## garden-rect centre in main-map pixels
    foodTotal*: int           ## total food currently available in the garden

proc replayFoodNames*(): seq[string] =
  ## Veggie names indexed by inventory slot (for naming harvest events).
  @FoodNames

proc replaySimConfig*(data: ReplayData): tuple[seed: int, dayTicks: int] =
  ## Seed + day length recorded in a replay header, ready for `initSimServer`.
  let config = data.replayRunConfigFor()
  (seed: config.seed, dayTicks: max(1, config.daySeconds) * TicksPerSecond)

proc replaySimDay*(sim: SimServer): tuple[dayNumber, dayTick, dayTicks: int] =
  ## The simulation's day-cycle position (event context).
  (dayNumber: sim.dayNumber, dayTick: sim.dayTick, dayTicks: sim.dayTicks)

proc replayDirectionName(direction: Direction): string =
  ## Human-readable facing, matching the sprite gnome labels.
  case direction
  of DirDown: "south"
  of DirUp: "north"
  of DirRight: "east"
  of DirLeft: "west"

proc snapshotReplayPlayers*(sim: SimServer): seq[ReplayPlayerSnapshot] =
  ## One snapshot per connected player at the simulation's current tick.
  result = newSeqOfCap[ReplayPlayerSnapshot](sim.players.len)
  for slot, player in sim.players:
    var inventoryTotal = 0
    for count in player.inventory:
      inventoryTotal += count
    var snapshot = ReplayPlayerSnapshot(
      slot: slot,
      username: player.username,
      playerName: player.playerName,
      x: player.x.footXAt(),
      y: player.y.footYAt(),
      direction: replayDirectionName(player.direction),
      mapIndex: player.mapIndex,
      houseIndex:
        if player.mapIndex.isHomeMap(): player.mapIndex - HomeMapIndexBase
        else: -1,
      homeIndex:
        if player.homeFlag.isHomeMap(): player.homeFlag - HomeMapIndexBase
        else: -1,
      inventory: @(player.inventory),
      inventoryTotal: inventoryTotal,
      score: player.score,
      message: player.message,
      messageTicks: player.messageTicks,
      dinnerCount: player.dinners.len,
      dinnerTicks: player.dinnerTicks
    )
    if player.dinners.len > 0:
      let dinner = player.dinners[^1]
      var foodTotal = 0
      for count in dinner.foods:
        foodTotal += count
      snapshot.lastDinnerHost = dinner.hostName
      snapshot.lastDinnerWasHost = dinner.wasHost
      snapshot.lastDinnerGuests = dinner.guestCount
      snapshot.lastDinnerFood = foodTotal
      snapshot.lastDinnerScore = dinner.score
    result.add(snapshot)

proc snapshotReplayGardens*(sim: SimServer): seq[ReplayGardenSnapshot] =
  ## One snapshot per garden at the simulation's current tick.
  result = newSeqOfCap[ReplayGardenSnapshot](sim.gardens.len)
  for index, garden in sim.gardens:
    var foodTotal = 0
    for count in garden.inventory:
      foodTotal += count
    result.add(ReplayGardenSnapshot(
      index: index,
      centerX: garden.rect.x + garden.rect.w div 2,
      centerY: garden.rect.y + garden.rect.h div 2,
      foodTotal: foodTotal
    ))

when not defined(emscripten):
  proc runReplayServerLoop*(
    host = DefaultHost,
    port = DefaultPort,
    runtimeConfig = RuntimeConfig()
  ) =
    ## Serves recorded Heartleaf replays to replay and global viewers.
    initAppState()
    appState.replayServerMode = true

    var
      replayData = ReplayData()
      replaySeed = DefaultSeed
      replayDayTicks = DefaultDaySeconds * TicksPerSecond
      replayLoaded = false
    if runtimeConfig.replay.len > 0:
      replayData = parseReplayBytes(runtimeConfig.replay)
      let replayConfig = replayData.replayRunConfigFor()
      replaySeed = replayConfig.seed
      replayDayTicks = max(1, replayConfig.daySeconds) * TicksPerSecond
      replayLoaded = true
    appState.replayLoaded = replayLoaded

    var
      sim = initSimServer(replaySeed, replayDayTicks)
      replay =
        if replayLoaded:
          initReplayPlayer(replayData)
        else:
          ReplayPlayer()
      lastTick: MonoTime
    if replayLoaded:
      replay.buildReplayKeyframes(replaySeed, replayDayTicks)
    # Load assets before healthz so replay viewers get frames immediately.
    let httpServer = newServer(
      httpHandler,
      websocketHandler,
      workerThreads = 4,
      tcpNoDelay = true
    )
    var serverThread: Thread[ServerThreadArgs]
    var serverPtr = cast[ptr Server](unsafeAddr httpServer)
    createThread(
      serverThread,
      serverThreadProc,
      ServerThreadArgs(server: serverPtr, address: host, port: port)
    )
    httpServer.waitUntilReady()
    lastTick = getMonoTime()

    while true:
      var
        pendingReplayUri = ""
        viewerSockets: seq[WebSocket] = @[]
        viewerStates: seq[PlayerViewerState] = @[]
        viewerIsReplay: seq[bool] = @[]
        seekTicks: seq[int] = @[]
        commands: seq[char] = @[]

      {.gcsafe.}:
        withLock appState.lock:
          pendingReplayUri = appState.pendingReplayUri
          appState.pendingReplayUri = ""
          for websocket in appState.closedSockets:
            sim.removePlayer(websocket)
          appState.closedSockets.setLen(0)

      if pendingReplayUri.len > 0:
        try:
          replayData = loadReplayUri(pendingReplayUri)
          let replayConfig = replayData.replayRunConfigFor()
          replaySeed = replayConfig.seed
          replayDayTicks = max(1, replayConfig.daySeconds) * TicksPerSecond
          sim = initSimServer(replaySeed, replayDayTicks)
          replay = initReplayPlayer(replayData)
          replay.buildReplayKeyframes(replaySeed, replayDayTicks)
          replayLoaded = true
          {.gcsafe.}:
            withLock appState.lock:
              appState.replayLoaded = true
        except CatchableError as e:
          echo "Could not load replay uri: ", e.msg

      {.gcsafe.}:
        withLock appState.lock:
          for websocket, state in appState.replayViewers.pairs:
            viewerSockets.add(websocket)
            viewerStates.add(state)
            viewerIsReplay.add(true)
            state.drainReplayViewerInput(
              replay.replayMaxTick(),
              seekTicks,
              commands
            )
          for websocket, state in appState.globalViewers.pairs:
            viewerSockets.add(websocket)
            viewerStates.add(state)
            viewerIsReplay.add(false)
            state.drainReplayViewerInput(
              replay.replayMaxTick(),
              seekTicks,
              commands
            )

      if replayLoaded:
        for seekTick in seekTicks:
          replay.applyReplaySeek(sim, seekTick)
        for command in commands:
          replay.applyReplayCommand(sim, command)
        if replay.playing:
          for _ in 0 ..< replay.replaySpeed():
            if replay.playing:
              replay.stepReplay(sim)
          if replay.looping and not replay.playing and
              replay.replayMaxTick() > 0:
            replay.seekReplay(sim, 0)
            replay.playing = true
      sim.advanceChatFeed()

      for i in 0 ..< viewerSockets.len:
        var nextState: PlayerViewerState
        let packet = sim.buildGlobalPacket(
          viewerStates[i],
          nextState,
          replayControls = replayLoaded,
          replayTick = sim.tickCount,
          replaySpeed = replay.replaySpeed(),
          replayMaxTick = replay.replayMaxTick(),
          replayPlaying = replay.playing,
          replayLooping = replay.looping,
          replayMismatchTick = replay.hashMismatchTick
        )
        try:
          viewerSockets[i].sendSpritePacket(packet)
          {.gcsafe.}:
            withLock appState.lock:
              if viewerIsReplay[i]:
                if viewerSockets[i] in appState.replayViewers:
                  appState.replayViewers[viewerSockets[i]] = nextState
              elif viewerSockets[i] in appState.globalViewers:
                appState.globalViewers[viewerSockets[i]] = nextState
        except CatchableError:
          {.gcsafe.}:
            withLock appState.lock:
              sim.removePlayer(viewerSockets[i])

      runFrameLimiter(lastTick)

when isMainModule and not defined(emscripten):
  let runtimeConfig = readRuntimeConfig()
  var
    config = RunConfig(
      address: runtimeConfig.host,
      port: runtimeConfig.port,
      seed: DefaultSeed,
      maxTicks: DefaultMaxTicks,
      maxGames: DefaultMaxGames,
      daySeconds: DefaultDaySeconds,
      tokens: @[],
      soulTimeoutSeconds: DefaultSoulTimeoutSeconds
    )
  if seedPinned(runtimeConfig.config):
    config.update(runtimeConfig.config)
  else:
    config.seed = randomSeed()
    config.update(stripUnpinnedSeed(runtimeConfig.config))
    echo "seed not pinned; randomized"
  config.echoStartupConfig()
  if runtimeConfig.resultsUri.len > 0:
    echo "Using results target: " & runtimeConfig.resultsUri
  if runtimeConfig.replayUri.len > 0:
    echo "Using replay target: " & runtimeConfig.replayUri
  if runtimeConfig.replayMode:
    runReplayServerLoop(config.address, config.port, runtimeConfig)
    quit(0)
  let localReplayPath =
    if runtimeConfig.replayUri.len > 0:
      getTempDir() / ("heartleaf-replay-" & $getCurrentProcessId() &
        ".bitreplay")
    else:
      ""
  runServerLoop(
    config.address,
    config.port,
    seed = config.seed,
    maxTicks = config.maxTicks,
    maxDays = config.maxDays,
    maxGames = config.maxGames,
    daySeconds = config.daySeconds,
    tokens = config.tokens,
    playerNames = config.playerNames,
    soulTimeoutSeconds = config.soulTimeoutSeconds,
    soulConnectionRequired = config.soulConnectionRequired,
    mockReply = config.mockReply,
    saveReplayPath = localReplayPath,
    runtimeConfig = runtimeConfig
  )
