import
  std/[json, locks, math, monotimes, os, random, strutils,
    tables, times],
  jsony, mummy, pixie,
  bitworld/aseprite, bitworld/client as bitworldClient,
  bitworld/pixelfonts, bitworld/spriteprotocol, bitworld/resources,
  bitworld/runtime, bitworld/sprites

const
  DefaultSeed = 0x484541
  DefaultMaxTicks = 0
  DefaultMaxGames = 0
  DebugOutlines = false
  MainMapIndex = 0
  HomeMapIndexBase = 1
  UnassignedPlayerIndex = 0x7fffffff
  ViewportWidth = 320
  ViewportHeight = 200
  GnomeSpriteSize = 32
  FoodSpriteSize = 32
  FoodGridCols = 8
  FoodGridRows = 8
  DirectionCount = 4
  FoodVeggieSlots = 24
  FoodVeggieCols = 8
  FoodMarkerCellX = 7
  FoodMarkerCellY = 7
  GardenStartFoodCount = 1
  HouseCount = 9
  PlayerBoxWidth = 14
  PlayerBoxHeight = 8
  PlayerBoxOffsetX = 9
  PlayerBoxOffsetY = 22
  FootHalfWidth = PlayerBoxWidth div 2
  FootHalfHeight = PlayerBoxHeight div 2
  InteractionRadius = 40
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
  TicksPerSecond = 24
  DayRealMinutes = 3
  DayTicks = DayRealMinutes * 60 * TicksPerSecond
  ScoreScreenTicks = 10 * TicksPerSecond
  DinnerScreenTicks = 10 * TicksPerSecond
  DayStartMinutes = 8 * 60
  DayEndMinutes = 22 * 60
  DinnerMinutes = 18 * 60
  DayStepMinutes = 5
  DayTotalMinutes = DayEndMinutes - DayStartMinutes
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
  MapLayerKind = 0
  GlobalPanelLayerKind = 1
  UiLayerKind = 3
  ClockLayerKind = 2
  MapLayerFlags = 1
  UiLayerFlags = 2
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
  GlobalPanelIconWidth = 5
  GlobalPanelIconHeight = 7
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
  MainWalkSpriteId = 8000
  HomeWalkSpriteId = 8001
  GlobalPanelBackSpriteId = 8100
  GlobalPanelTitleSpriteId = 8101
  GlobalPanelSelectSpriteId = 8102
  GlobalPanelScoreSpriteBase = 8200
  GlobalPanelNameSpriteBase = 8300
  BottomObjectId = 1
  OverhangObjectId = 2
  PlayerObjectBase = 1000
  NameObjectBase = 2000
  ChatObjectBase = 3000
  GardenObjectBase = 4000
  InventoryObjectBase = 5000
  InventoryCountObjectBase = 6000
  ClockObjectBase = 7000
  ScoreObjectBase = 7100
  GlobalPanelBackObjectId = 20_000
  GlobalPanelTitleObjectId = 20_001
  GlobalPanelSelectObjectId = 20_002
  GlobalPanelScoreObjectBase = 20_100
  GlobalPanelNameObjectBase = 20_200
  BottomZ = int(low(int16))
  OverhangZ = 20_000
  GardenMarkerZ = OverhangZ - 1
  NameZ = 30_000
  ChatZ = 30_001
  ScoreZ = 30_002
  ChatMaxChars = 48
  NameMaxChars = 14
  ChatLifetimeTicks = 5 * 24
  ChatPad = 3
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
  WeekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
  TintHueTargets = [0.80, 0.78, 0.75, 0.70, 0.64]
  TintHueMixes = [0.18, 0.30, 0.43, 0.57, 0.72]
  TintSaturationScales = [1.05, 1.12, 1.20, 1.30, 1.38]
  TintValueScales = [0.86, 0.70, 0.54, 0.39, 0.25]
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
  FoodNames = [
    "Lettuce",
    "Carrot",
    "Apple",
    "Tomato",
    "Cucumber",
    "Zucchini",
    "Beet",
    "Pear",
    "Cabbage",
    "Purple cabbage",
    "Grapes",
    "Raspberries",
    "Yam",
    "Potato",
    "Wheat",
    "Hay Grass",
    "Avocado",
    "Red pepper",
    "Green pepper",
    "Blueberries",
    "Corn",
    "Radish",
    "Garlic",
    "Onion"
  ]

when DebugOutlines:
  const
    DebugSpriteId = 3
    HomeDebugSpriteId = 6
    DebugObjectId = 3
    DebugZ = 25_000

type
  Direction = enum
    DirDown
    DirUp
    DirRight
    DirLeft

  HeartleafError* = object of ValueError

  Rect = object
    x, y, w, h: int

  FoodCounts = array[FoodVeggieSlots, int]

  WorldMap = ref object
    width, height: int
    bottomSprite: RgbaSprite
    overhangSprite: RgbaSprite
    bottomTints: array[DayTintCount, RgbaSprite]
    overhangTints: array[DayTintCount, RgbaSprite]
    debugSprite: RgbaSprite
    walkMask: seq[bool]

  GnomeSprites = ref object
    frames: array[Direction, RgbaSprite]

  FoodSprites = ref object
    icons: array[FoodVeggieSlots, RgbaSprite]
    marker: RgbaSprite

  Garden = object
    rect: Rect
    inventory: FoodCounts

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

  SimServer = ref object
    mainMap: WorldMap
    homeMaps: array[HouseCount, WorldMap]
    debugRects: seq[ResourceRect]
    homeDebugRects: seq[ResourceRect]
    homeResources: HomeResources
    foods: FoodSprites
    gardens: seq[Garden]
    houses: array[HouseCount, House]
    gnomes: seq[GnomeSprites]
    players: seq[Player]
    textFont: PixelFont
    rng: Rand
    tickCount: int
    dayTick: int
    dayNumber: int
    scoreTicks: int
    dinnerDone: bool
    playerInitPacket: seq[uint8]

  PlayerViewerState = ref object
    initialized: bool
    selectedPlayerIndex: int
    spriteCache: seq[SpriteCacheEntry]

  WebSocketAppState = ref object
    lock: Lock
    inputMasks: Table[WebSocket, uint8]
    lastAppliedMasks: Table[WebSocket, uint8]
    playerIndices: Table[WebSocket, int]
    playerSlots: Table[WebSocket, int]
    playerViewers: Table[WebSocket, PlayerViewerState]
    globalViewers: Table[WebSocket, PlayerViewerState]
    replayViewers: Table[WebSocket, bool]
    playerUsernames: Table[WebSocket, string]
    chatMessages: Table[WebSocket, string]
    closedSockets: seq[WebSocket]
    tokens: seq[string]

  ServerThreadArgs = ref object
    server: ptr Server
    address: string
    port: int

  RunConfig = ref object
    address: string
    port: int
    seed: int
    maxTicks: int
    maxGames: int
    tokens: seq[string]

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
  currentSourcePath().parentDir() / "data"

proc layerIndexByName(
  aseprite: AsepriteSprite,
  names: openArray[string]
): int =
  ## Returns the first layer index matching one of the given names.
  for i, layer in aseprite.layers:
    for name in names:
      if layer.name.normalize() == name.normalize():
        return i
  -1

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

proc resourceDebugSprite(
  width, height: int,
  rects: openArray[ResourceRect]
): RgbaSprite =
  ## Builds one transparent sprite containing resource debug outlines.
  result = transparentRgbaSprite(width, height)
  for rect in rects:
    result.strokeRect(rect.x, rect.y, rect.w, rect.h, rect.color)

proc toRect(rect: ResourceRect): Rect =
  ## Converts one resource rectangle to a gameplay rectangle.
  Rect(x: rect.x, y: rect.y, w: rect.w, h: rect.h)

proc rectName(rect: ResourceRect): string =
  ## Returns one normalized resource rectangle name.
  rect.name.strip().toLowerAscii()

proc houseIndex(rect: ResourceRect): int =
  ## Returns the zero-based house index for one resource rectangle.
  let name = rect.rectName()
  if not name.startsWith("house"):
    return -1
  if name.len <= "house".len:
    return -1
  let suffix = name["house".len ..< name.len]
  try:
    result = parseInt(suffix) - 1
  except ValueError:
    return -1
  if result < 0 or result >= HouseCount:
    return -1

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

proc loadWorldMap(
  path,
  label: string,
  debugRects: seq[ResourceRect]
): WorldMap =
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
  result.debugSprite = resourceDebugSprite(
    result.width,
    result.height,
    debugRects
  )
  result.walkMask = walkImage.loadWalkMask()

proc walkabilitySprite(world: WorldMap): RgbaSprite =
  ## Builds an invisible helper sprite containing the walkable pixels.
  result = newRgbaSprite(world.width, world.height)
  for y in 0 ..< world.height:
    for x in 0 ..< world.width:
      if world.walkMask[y * world.width + x]:
        result.putPixel(x, y, rgba(255, 255, 255, 255))

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

proc initSimServer(seed = DefaultSeed): SimServer =
  ## Initializes the Heartleaf simulation.
  result = SimServer()
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
  result.debugRects = loadResourceRects(resourcePath)
  result.homeDebugRects = loadResourceRects(homeResourcePath)
  result.homeResources = loadHomeResources(result.homeDebugRects)
  result.mainMap = loadWorldMap(mapPath, "Map", result.debugRects)
  let homeMap = loadWorldMap(homeMapPath, "Home map", result.homeDebugRects)
  for i in 0 ..< HouseCount:
    result.homeMaps[i] = homeMap
  result.houses = loadHouses(result.debugRects)
  result.gardens = loadGardens(result.debugRects, result.rng)
  result.foods = loadFoodSprites(foodPath)
  result.gnomes = loadGnomeSprites(gnomesPath)
  if result.gnomes.len == 0:
    raise newException(HeartleafError, "Gnome sheet has no gnomes.")
  result.textFont = readPixelFont(tiny5Path)
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

proc screenRectVisible(x, y, w, h: int): bool =
  ## Returns true when one screen-space rectangle overlaps the viewport.
  rectVisible(x, y, w, h, ViewportWidth, ViewportHeight)

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

proc speechBubbleSprite(sim: SimServer, text: string): RgbaSprite =
  ## Builds one speech bubble sprite for a player message.
  let
    textWidth = max(6, sim.chatTextWidth(text))
    lineHeight = sim.textFont.height
    bodyWidth = textWidth + ChatPad * 2
    bodyHeight = lineHeight + ChatPad * 2
    fill = rgba(TextBackR, TextBackG, TextBackB, 255)
  result = newRgbaSprite(bodyWidth, bodyHeight + ChatPointerHeight)
  result.fillRect(0, 0, bodyWidth, bodyHeight, fill)
  let pointerX = bodyWidth div 2
  for y in 0 ..< ChatPointerHeight:
    let span = ChatPointerHeight - y - 1
    for x in pointerX - span .. pointerX + span:
      result.putPixel(x, bodyHeight + y, fill)
  sim.blitChatText(result, text, ChatPad, ChatPad)

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
    sim.blitChatText(result, "Host: " & record.hostName, 8, 20)
    sim.drawFoodCounts(result, record.foods, 8, 40)

proc scoreDisplayName(player: Player): string =
  ## Returns the score-screen name with username and player name.
  if player.username.len == 0:
    return player.playerName
  player.username & " (" & player.playerName & ")"

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

proc globalPanelBackSprite(): RgbaSprite =
  ## Builds the global viewer score panel background.
  result = newRgbaSprite(GlobalPanelWidth, GlobalPanelHeight)
  result.fillRect(
    0,
    0,
    GlobalPanelWidth,
    GlobalPanelHeight,
    rgba(0, 0, 0, 210)
  )
  result.strokeRect(
    0,
    0,
    GlobalPanelWidth,
    GlobalPanelHeight,
    rgba(255, 255, 255, 120)
  )

proc globalPanelSelectSprite(): RgbaSprite =
  ## Builds the global viewer selected-player pointer icon.
  result = newRgbaSprite(GlobalPanelIconWidth, GlobalPanelIconHeight)
  let center = GlobalPanelIconHeight div 2
  for y in 0 ..< GlobalPanelIconHeight:
    let span = GlobalPanelIconHeight div 2 - abs(center - y)
    for x in 0 .. span:
      result.putPixel(x, y, rgba(255, 245, 140, 255))

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
  packet.addRgbaSpriteCached(cache, spriteId, tag, "name " & player.playerName)
  packet.addObject(
    NameObjectBase + playerIndex,
    x,
    y,
    z,
    MapLayerId,
    spriteId
  )
  y

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
  packet.addRgbaSpriteCached(cache, spriteId, bubble, "chat " & player.message)
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
  MainBottomTintSpriteBase + tintIndex

proc mainOverhangSpriteId(tintIndex: int): int =
  ## Returns the main map overhang sprite id for one day tint.
  if tintIndex < 0:
    return OverhangSpriteId
  MainOverhangTintSpriteBase + tintIndex

proc homeBottomSpriteId(tintIndex: int): int =
  ## Returns the home map bottom sprite id for one day tint.
  if tintIndex < 0:
    return HomeBottomSpriteId
  HomeBottomTintSpriteBase + tintIndex

proc homeOverhangSpriteId(tintIndex: int): int =
  ## Returns the home map overhang sprite id for one day tint.
  if tintIndex < 0:
    return HomeOverhangSpriteId
  HomeOverhangTintSpriteBase + tintIndex

proc clockGlyphIndex(ch: char): int =
  ## Returns the compact clock sprite slot for one glyph.
  for i, glyph in ClockGlyphs:
    if glyph == ch:
      return i
  for i, glyph in ClockGlyphs:
    if glyph == ' ':
      return i
  0

proc clockGlyphSpriteId(ch: char): int =
  ## Returns the sprite id for one clock glyph.
  ClockGlyphSpriteBase + ch.clockGlyphIndex()

proc foodName(foodIndex: int): string =
  ## Returns the display name for one food slot.
  if foodIndex >= 0 and foodIndex < FoodNames.len:
    return FoodNames[foodIndex]
  "food " & $foodIndex

proc playerNameForHouse(houseIndex: int): string =
  ## Returns the fixed in-game player name for one house.
  if houseIndex >= 0 and houseIndex < PlayerNames.len:
    return PlayerNames[houseIndex]
  "Player"

proc dailyResultsJson*(sim: SimServer): string =
  ## Returns one daily player score result as JSON.
  var
    names = newJArray()
    usernames = newJArray()
    playerNames = newJArray()
    scores = newJArray()
    results = newJObject()
  for houseIndex in 0 ..< HouseCount:
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
  $results

proc totalItems(foods: FoodCounts): int =
  ## Returns the total number of items in one food count set.
  for count in foods:
    result += count

proc clearFoods(foods: var FoodCounts) =
  ## Clears one food count set.
  for i in 0 ..< FoodVeggieSlots:
    foods[i] = 0

proc scaledFoods(foods: FoodCounts, multiplier: int): FoodCounts =
  ## Returns food counts multiplied by one guest count.
  for i in 0 ..< FoodVeggieSlots:
    result[i] = foods[i] * multiplier

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
  sim.mainMap

proc currentDayMinutes(sim: SimServer): int =
  ## Returns the current in-game minute of the day.
  let step = min(DayStepCount, sim.dayTick * DayStepCount div DayTicks)
  DayStartMinutes + step * DayStepMinutes

proc twoDigits(value: int): string =
  ## Formats one integer as two decimal digits.
  if value < 10:
    return "0" & $value
  $value

proc clockText(sim: SimServer): string =
  ## Returns the current weekday and game clock as 12-hour text.
  let
    minutes = sim.currentDayMinutes()
    weekday = WeekdayNames[(sim.dayNumber - 1) mod WeekdayNames.len]
    hour24 = minutes div 60
    minute = minutes mod 60
    suffix =
      if hour24 < 12:
        "am"
      else:
        "pm"
    hour12 =
      if hour24 mod 12 == 0:
        12
      else:
        hour24 mod 12
  weekday & " " & $hour12 & ":" & minute.twoDigits() & suffix

proc dayTintIndex(sim: SimServer): int =
  ## Returns the active dusk tint index, or -1 during full daylight.
  let minutes = sim.currentDayMinutes()
  if minutes < DuskStartMinutes:
    return -1
  min(
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
    "heartleaf bottom"
  )
  packet.addRgbaSprite(
    OverhangSpriteId,
    sim.mainMap.overhangSprite,
    "heartleaf overhang"
  )
  when DebugOutlines:
    packet.addRgbaSprite(
      DebugSpriteId,
      sim.mainMap.debugSprite,
      "heartleaf debug"
    )
  for i in 0 ..< DayTintCount:
    packet.addRgbaSprite(
      mainBottomSpriteId(i),
      sim.mainMap.bottomTints[i],
      "heartleaf bottom tint " & $i
    )
    packet.addRgbaSprite(
      mainOverhangSpriteId(i),
      sim.mainMap.overhangTints[i],
      "heartleaf overhang tint " & $i
    )
  packet.addRgbaSprite(
    HomeBottomSpriteId,
    sim.homeMaps[0].bottomSprite,
    "heartleaf home bottom"
  )
  packet.addRgbaSprite(
    HomeOverhangSpriteId,
    sim.homeMaps[0].overhangSprite,
    "heartleaf home overhang"
  )
  when DebugOutlines:
    packet.addRgbaSprite(
      HomeDebugSpriteId,
      sim.homeMaps[0].debugSprite,
      "heartleaf home debug"
    )
  for i in 0 ..< DayTintCount:
    packet.addRgbaSprite(
      homeBottomSpriteId(i),
      sim.homeMaps[0].bottomTints[i],
      "heartleaf home bottom tint " & $i
    )
    packet.addRgbaSprite(
      homeOverhangSpriteId(i),
      sim.homeMaps[0].overhangTints[i],
      "heartleaf home overhang tint " & $i
    )
  for ch in ClockGlyphs:
    packet.addRgbaSprite(
      ch.clockGlyphSpriteId(),
      sim.clockGlyphSprite(ch),
      "clock " & $ch
    )
  for foodIndex, icon in sim.foods.icons:
    packet.addRgbaSprite(foodSpriteId(foodIndex), icon, foodIndex.foodName())
  packet.addRgbaSprite(
    FoodMarkerSpriteId,
    sim.foods.marker,
    "garden marker"
  )
  packet.addRgbaSprite(
    MainWalkSpriteId,
    sim.mainMap.walkabilitySprite(),
    "heartleaf main walkability"
  )
  packet.addRgbaSprite(
    HomeWalkSpriteId,
    sim.homeMaps[0].walkabilitySprite(),
    "heartleaf home walkability"
  )
  for gnomeIndex, gnome in sim.gnomes:
    for direction in Direction:
      packet.addRgbaSprite(
        playerSpriteId(gnomeIndex, direction),
        gnome.frames[direction],
        "gnome " & $gnomeIndex & " " & direction.directionLabel()
      )

proc worldClampPixel(value, maxValue: int): int =
  ## Clamps one pixel coordinate into a non-negative world range.
  value.clamp(0, max(0, maxValue))

proc footXAt(spriteX: int): int =
  ## Returns the foot-center x coordinate for one sprite x coordinate.
  spriteX + PlayerBoxOffsetX + PlayerBoxWidth div 2

proc footYAt(spriteY: int): int =
  ## Returns the foot-center y coordinate for one sprite y coordinate.
  spriteY + PlayerBoxOffsetY + PlayerBoxHeight div 2

proc playerFootX(player: Player): int =
  ## Returns the foot-center x coordinate for one player.
  player.x.footXAt()

proc playerFootY(player: Player): int =
  ## Returns the foot-center y coordinate for one player.
  player.y.footYAt()

proc contains(rect: Rect, x, y: int): bool =
  ## Returns true when a point is inside one rectangle.
  x >= rect.x and
    y >= rect.y and
    x < rect.x + rect.w and
    y < rect.y + rect.h

proc isWalkable(world: WorldMap, x, y: int): bool =
  ## Returns true when one world pixel is walkable.
  if x < 0 or y < 0 or x >= world.width or y >= world.height:
    return false
  world.walkMask[y * world.width + x]

proc canOccupy(world: WorldMap, x, y: int): bool =
  ## Returns true when a gnome can stand at one sprite position.
  ## Gnomes occupy a single foot-center pixel, like crewrift crew.
  world.isWalkable(x.footXAt(), y.footYAt())

proc distanceSquared(ax, ay, bx, by: int): int =
  ## Returns the squared distance between two points.
  let
    dx = ax - bx
    dy = ay - by
  dx * dx + dy * dy

proc hasFood(garden: Garden): bool =
  ## Returns true when a garden still has food to collect.
  for count in garden.inventory:
    if count > 0:
      return true

proc rectDistanceSquared(a, b: Rect): int =
  ## Returns the squared distance between two axis-aligned rectangles.
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
  true

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

proc addPlayer(sim: SimServer, username: string, requestedSlot = -1): int =
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
  sim.players.high

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
  sim.homeResources.exit.contains(
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
  worldClampPixel(
    player.playerFootX() - ViewportWidth div 2,
    world.width - ViewportWidth
  )

proc cameraYFor(sim: SimServer, player: Player): int =
  ## Returns the player camera y coordinate.
  let world = sim.mapFor(player.mapIndex)
  worldClampPixel(
    player.playerFootY() - ViewportHeight div 2,
    world.height - ViewportHeight
  )

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
    label = "dinner " & $playerIndex
  elif sim.scoreTicks > 0:
    overlay = sim.scoreOverlaySprite()
    label = "score " & $playerIndex
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

proc addPlayerObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  mapIndex,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
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
  cache: var seq[SpriteCacheEntry]
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
    ViewportHeight
  )
  packet.addObject(
    OverhangObjectId,
    -cameraX,
    -cameraY,
    OverhangZ,
    MapLayerId,
    overhangSpriteId
  )
  when DebugOutlines:
    let debugSpriteId =
      if onMainMap:
        DebugSpriteId
      else:
        HomeDebugSpriteId
    packet.addObject(
      DebugObjectId,
      -cameraX,
      -cameraY,
      DebugZ,
      MapLayerId,
      debugSpriteId
    )
  packet.addInventoryObjects(
    sim,
    cache,
    player
  )
  packet.addClockObjects(sim)
  true

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
  packet.addPlayerObjects(
    sim,
    cache,
    MainMapIndex,
    0,
    0,
    sim.mainMap.width,
    sim.mainMap.height
  )
  packet.addObject(
    OverhangObjectId,
    0,
    0,
    OverhangZ,
    MapLayerId,
    mainOverhangSpriteId(tintIndex)
  )
  when DebugOutlines:
    packet.addObject(
      DebugObjectId,
      0,
      0,
      DebugZ,
      MapLayerId,
      DebugSpriteId
    )
  packet.addClockObjects(sim)

proc buildPlayerPacket(
  sim: SimServer,
  playerIndex: int,
  state: PlayerViewerState,
  nextState: var PlayerViewerState
): seq[uint8] =
  ## Builds one sprite protocol packet for a player viewer.
  nextState =
    if state == nil:
      PlayerViewerState()
    else:
      state
  if not nextState.initialized:
    result.add(sim.playerInitPacket)
    nextState.initialized = true

  result.addClearObjects()
  discard result.addPlayerView(sim, playerIndex, nextState.spriteCache)

proc buildGlobalPacket(
  sim: SimServer,
  state: PlayerViewerState,
  nextState: var PlayerViewerState
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
  let selectedIndex = nextState.selectedGlobalPlayerIndex(sim)
  nextState.selectedPlayerIndex = selectedIndex
  if selectedIndex >= 0:
    result.addViewport(MapLayerId, ViewportWidth, ViewportHeight)
    discard result.addPlayerView(
      sim,
      selectedIndex,
      nextState.spriteCache
    )
  else:
    result.addGlobalWorldView(sim, nextState.spriteCache)
  result.addGlobalScorePanel(sim, nextState.spriteCache, selectedIndex)

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
  0

proc slideScanRadius(carry, velocity: int): int =
  ## Returns the perpendicular scan radius for blocked movement.
  let
    pending = abs(carry) div MotionScale
    speed = (abs(velocity) + MotionScale - 1) div MotionScale
  clamp(max(1, max(pending, speed)), 1, MovementSlideMaxScan)

proc canSlideHorizontal(world: WorldMap, x, y, step, offset: int): bool =
  ## Returns true when a horizontal step can slide by one offset.
  if offset == 0:
    return false
  let slideStep = offset.signum()
  for i in 1 .. abs(offset):
    if not world.canOccupy(x, y + slideStep * i):
      return false
  world.canOccupy(x + step, y + offset)

proc canSlideVertical(world: WorldMap, x, y, step, offset: int): bool =
  ## Returns true when a vertical step can slide by one offset.
  if offset == 0:
    return false
  let slideStep = offset.signum()
  for i in 1 .. abs(offset):
    if not world.canOccupy(x + slideStep * i, y):
      return false
  world.canOccupy(x + offset, y + step)

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
  true

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
    for visitorIndex in visitors:
      guestNames.add(sim.players[visitorIndex].playerName)
      guestGnomeIndices.add(sim.players[visitorIndex].gnomeIndex)

    let
      hostFoods = host.inventory
      fedFoods = hostFoods.scaledFoods(visitors.len)
      score = hostFoods.totalItems() * visitors.len
      hostRecord = DinnerRecord(
        hostName: host.playerName,
        wasHost: true,
        foods: fedFoods,
        guestNames: guestNames,
        guestGnomeIndices: guestGnomeIndices,
        guestCount: visitors.len,
        score: score
      )
    host.score += score
    host.recordDinner(hostRecord)
    host.clearInventory()

    for visitorIndex in visitors:
      let visitorRecord = DinnerRecord(
        hostName: host.playerName,
        wasHost: false,
        foods: hostFoods,
        guestNames: guestNames,
        guestGnomeIndices: guestGnomeIndices,
        guestCount: visitors.len,
        score: 0
      )
      sim.players[visitorIndex].recordDinner(visitorRecord)

proc startDay(sim: SimServer) =
  ## Starts a new morning while keeping long-game player progress.
  inc sim.dayNumber
  sim.dayTick = 0
  sim.scoreTicks = 0
  sim.dinnerDone = false
  sim.gardens = loadGardens(sim.debugRects, sim.rng)
  for player in sim.players.mitems:
    player.dinnerTicks = 0
    player.dinnerRecord = nil
  for i in 0 ..< sim.players.len:
    sim.teleportPlayerToOwnHome(i)

proc startScoreScreen(sim: SimServer) =
  ## Starts the end-of-day scoring screen.
  sim.dayTick = DayTicks
  sim.scoreTicks = ScoreScreenTicks
  for player in sim.players.mitems:
    player.dinnerTicks = 0
    player.dinnerRecord = nil
  for i in 0 ..< sim.players.len:
    sim.teleportPlayerToOwnHome(i)

proc step(sim: SimServer, inputs: openArray[InputState]) =
  ## Advances the Heartleaf simulation by one tick.
  inc sim.tickCount
  if sim.scoreTicks > 0:
    dec sim.scoreTicks
    sim.updateMessages()
    if sim.scoreTicks <= 0:
      sim.startDay()
    return

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
  sim.updateMessages()
  inc sim.dayTick
  if not sim.dinnerDone and sim.currentDayMinutes() >= DinnerMinutes:
    sim.startDinnerParties()
  if sim.dayTick >= DayTicks:
    sim.startScoreScreen()

proc initAppState() =
  ## Initializes shared websocket state.
  appState = WebSocketAppState()
  initLock(appState.lock)
  appState.inputMasks = initTable[WebSocket, uint8]()
  appState.lastAppliedMasks = initTable[WebSocket, uint8]()
  appState.playerIndices = initTable[WebSocket, int]()
  appState.playerSlots = initTable[WebSocket, int]()
  appState.playerViewers = initTable[WebSocket, PlayerViewerState]()
  appState.globalViewers = initTable[WebSocket, PlayerViewerState]()
  appState.replayViewers = initTable[WebSocket, bool]()
  appState.playerUsernames = initTable[WebSocket, string]()
  appState.chatMessages = initTable[WebSocket, string]()
  appState.closedSockets = @[]
  appState.tokens = @[]

proc globalPanelClickedPlayer(message: Message): int =
  ## Returns the clicked global score-panel player index or -1.
  result = -1
  if message.kind != BinaryMessage:
    return
  var
    x = 0
    y = 0
    layer = -1
  for item in message.data.parseSpriteClientMessages():
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
        SpriteClientReadyMessage, SpriteClientDebugSpriteMessage:
      discard

proc playerChatFromMessage(message: Message): string =
  ## Reads player chat from text or binary websocket messages.
  case message.kind
  of TextMessage:
    message.data
  of BinaryMessage:
    if message.data.isChatPacket():
      return message.data.blobToChat()
    message.data.readSpriteInputText()
  of Ping, Pong:
    ""

proc removePlayer(sim: SimServer, websocket: WebSocket) =
  ## Removes one websocket and keeps player indices compact.
  if websocket in appState.replayViewers:
    appState.replayViewers.del(websocket)
  if websocket in appState.globalViewers:
    appState.globalViewers.del(websocket)
  if websocket in appState.playerViewers:
    appState.playerViewers.del(websocket)
  if websocket in appState.playerSlots:
    appState.playerSlots.del(websocket)
  if websocket in appState.playerUsernames:
    appState.playerUsernames.del(websocket)
  if websocket in appState.chatMessages:
    appState.chatMessages.del(websocket)
  if websocket notin appState.playerIndices:
    appState.inputMasks.del(websocket)
    appState.lastAppliedMasks.del(websocket)
    return

  let removedIndex = appState.playerIndices[websocket]
  appState.playerIndices.del(websocket)
  appState.inputMasks.del(websocket)
  appState.lastAppliedMasks.del(websocket)
  if removedIndex >= 0 and removedIndex < sim.players.len:
    sim.players.delete(removedIndex)
    for ws, value in appState.playerIndices.mpairs:
      if value > removedIndex:
        dec value

proc resetConnectedPlayers() =
  ## Marks connected player sockets for a fresh simulation join.
  var sockets: seq[WebSocket] = @[]
  for websocket in appState.playerIndices.keys:
    sockets.add(websocket)
  for websocket in sockets:
    appState.playerIndices[websocket] = UnassignedPlayerIndex
    appState.playerViewers[websocket] = PlayerViewerState()
    appState.inputMasks[websocket] = 0
    appState.lastAppliedMasks[websocket] = 0
  appState.chatMessages.clear()

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
  true

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

proc playerUsername(request: Request): string =
  ## Returns the requested connection username.
  let username = request.queryParams.getOrDefault("username", "")
  if username.len > 0:
    return username.cleanUsername()
  request.queryParams.getOrDefault("name", "").cleanUsername()

proc playerJoinAllowed(slot: int, token: string): bool =
  ## Returns true when the configured token list accepts a join.
  if appState.tokens.len == 0:
    return true
  if slot >= 0 and slot < appState.tokens.len:
    return token == appState.tokens[slot]
  if slot == -1:
    return token in appState.tokens
  false

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
      username = request.playerUsername()
    var allowed = false
    {.gcsafe.}:
      withLock appState.lock:
        allowed = playerJoinAllowed(slot, token)
    if not allowed:
      request.respondPlain(403, "player token rejected\n")
      return
    let websocket = request.upgradeToWebSocket()
    {.gcsafe.}:
      withLock appState.lock:
        appState.playerViewers[websocket] = PlayerViewerState()
        appState.playerIndices[websocket] = UnassignedPlayerIndex
        appState.playerSlots[websocket] = slot
        appState.playerUsernames[websocket] = username
        appState.inputMasks[websocket] = 0
        appState.lastAppliedMasks[websocket] = 0
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
    let websocket = request.upgradeToWebSocket()
    {.gcsafe.}:
      withLock appState.lock:
        appState.replayViewers[websocket] = true
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
  ## Handles player websocket input and close events.
  case event
  of OpenEvent:
    discard
  of MessageEvent:
    let clickedPlayer = message.globalPanelClickedPlayer()
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
    if message.kind == BinaryMessage and message.data.len == 2 and
        (
          message.data[0].uint8 == PacketInput or
          message.data[0].uint8 == 0x84'u8
        ):
      {.gcsafe.}:
        withLock appState.lock:
          if websocket in appState.playerViewers:
            appState.inputMasks[websocket] = message.data[1].uint8 and 0x7f'u8
    let chatText = message.playerChatFromMessage().cleanChatMessage()
    if chatText.len > 0:
      {.gcsafe.}:
        withLock appState.lock:
          if websocket in appState.playerViewers:
            appState.chatMessages[websocket] = chatText
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

proc replayJson(sim: SimServer): string =
  ## Builds a tiny replay artifact for Coworld certification.
  let replay = %*{
    "format": "heartleaf-replay-v1",
    "latestResults": parseJson(sim.dailyResultsJson())
  }
  $replay & "\n"

proc writeArtifacts(
  sim: SimServer,
  runtimeConfig: RuntimeConfig
) =
  ## Writes result and replay artifacts for the current day.
  runtimeConfig.writeResults(sim.dailyResultsJson() & "\n")
  runtimeConfig.writeReplay(sim.replayJson())

proc buildReplayPacket(): seq[uint8] =
  ## Builds a minimal sprite-protocol replay frame.
  result.addViewport(MapLayerId, ViewportWidth, ViewportHeight)
  result.addLayer(MapLayerId, MapLayerKind, MapLayerFlags)

proc runReplayServerLoop*(
  host = DefaultHost,
  port = DefaultPort
) =
  ## Runs a minimal Coworld replay websocket server.
  initAppState()
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
  let packet = blobFromBytes(buildReplayPacket())
  var lastTick = getMonoTime()
  while true:
    var sockets: seq[WebSocket] = @[]
    {.gcsafe.}:
      withLock appState.lock:
        for websocket in appState.closedSockets:
          if websocket in appState.replayViewers:
            appState.replayViewers.del(websocket)
        appState.closedSockets.setLen(0)
        for websocket in appState.replayViewers.keys:
          sockets.add(websocket)
    for websocket in sockets:
      try:
        websocket.send(packet, BinaryMessage)
      except CatchableError:
        {.gcsafe.}:
          withLock appState.lock:
            if websocket in appState.replayViewers:
              appState.replayViewers.del(websocket)
    runFrameLimiter(lastTick)

proc runServerLoop*(
  host = DefaultHost,
  port = DefaultPort,
  seed = DefaultSeed,
  maxTicks = DefaultMaxTicks,
  maxGames = DefaultMaxGames,
  tokens: seq[string] = @[],
  runtimeConfig = RuntimeConfig()
) =
  ## Runs the Heartleaf websocket game server.
  initAppState()
  appState.tokens = tokens
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

  var
    sim = initSimServer(seed)
    lastTick = getMonoTime()
    runTicks = 0
    gamesFinished = 0
    lastWrittenDay = 0

  while true:
    var
      sockets: seq[WebSocket] = @[]
      playerIndices: seq[int] = @[]
      playerStates: seq[PlayerViewerState] = @[]
      globalSockets: seq[WebSocket] = @[]
      globalStates: seq[PlayerViewerState] = @[]
      inputs: seq[InputState]

    {.gcsafe.}:
      withLock appState.lock:
        for websocket in appState.closedSockets:
          sim.removePlayer(websocket)
        appState.closedSockets.setLen(0)

        for websocket in appState.playerIndices.keys:
          if appState.playerIndices[websocket] == UnassignedPlayerIndex:
            let playerIndex = sim.addPlayer(
              appState.playerUsernames.getOrDefault(websocket, ""),
              appState.playerSlots.getOrDefault(websocket, -1)
            )
            if playerIndex >= 0:
              appState.playerIndices[websocket] = playerIndex

        inputs = newSeq[InputState](sim.players.len)
        for websocket, playerIndex in appState.playerIndices.pairs:
          sockets.add(websocket)
          playerIndices.add(playerIndex)
          playerStates.add(
            appState.playerViewers.getOrDefault(
              websocket,
              PlayerViewerState()
            )
          )
          if playerIndex < 0 or playerIndex >= inputs.len:
            continue
          let currentMask = appState.inputMasks.getOrDefault(websocket, 0)
          inputs[playerIndex] = decodeInputMask(currentMask)
          appState.lastAppliedMasks[websocket] = currentMask
          let chatText = appState.chatMessages.getOrDefault(websocket, "")
          if chatText.len > 0:
            sim.players[playerIndex].message = chatText
            sim.players[playerIndex].messageTicks = ChatLifetimeTicks
            appState.chatMessages.del(websocket)

        for websocket, state in appState.globalViewers.pairs:
          globalSockets.add(websocket)
          globalStates.add(state)

    let wasScoring = sim.scoreTicks > 0
    sim.step(inputs)
    if not wasScoring and sim.scoreTicks > 0:
      sim.writeArtifacts(runtimeConfig)
      lastWrittenDay = sim.dayNumber
    inc runTicks

    for i in 0 ..< sockets.len:
      var nextState: PlayerViewerState
      let packet = sim.buildPlayerPacket(
        playerIndices[i],
        playerStates[i],
        nextState
      )
      try:
        sockets[i].sendSpritePacket(packet)
        {.gcsafe.}:
          withLock appState.lock:
            if sockets[i] in appState.playerViewers:
              appState.playerViewers[sockets[i]] = nextState
      except CatchableError:
        {.gcsafe.}:
          withLock appState.lock:
            sim.removePlayer(sockets[i])

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

    if maxTicks > 0 and runTicks >= maxTicks:
      if lastWrittenDay == 0:
        sim.writeArtifacts(runtimeConfig)
      inc gamesFinished
      if maxGames > 0 and gamesFinished >= maxGames:
        quit(0)
      sim = initSimServer(seed + gamesFinished)
      runTicks = 0
      lastWrittenDay = 0
      {.gcsafe.}:
        withLock appState.lock:
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
  node.readConfigInt("maxGames", config.maxGames)
  node.readConfigInt("max-games", config.maxGames)
  node.readConfigStrings("tokens", config.tokens)

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
    " maxTicks=", config.maxTicks.limitText(),
    " maxGames=", config.maxGames.limitText()

when isMainModule:
  let runtimeConfig = readRuntimeConfig()
  var
    config = RunConfig(
      address: runtimeConfig.host,
      port: runtimeConfig.port,
      seed: DefaultSeed,
      maxTicks: DefaultMaxTicks,
      maxGames: DefaultMaxGames,
      tokens: @[]
    )
  config.update(runtimeConfig.config)
  config.echoStartupConfig()
  if runtimeConfig.resultsUri.len > 0:
    echo "Using results target: " & runtimeConfig.resultsUri
  if runtimeConfig.replayUri.len > 0:
    echo "Using replay target: " & runtimeConfig.replayUri
  if runtimeConfig.replayMode:
    runReplayServerLoop(config.address, config.port)
    quit(0)
  runServerLoop(
    config.address,
    config.port,
    seed = config.seed,
    maxTicks = config.maxTicks,
    maxGames = config.maxGames,
    tokens = config.tokens,
    runtimeConfig = runtimeConfig
  )
