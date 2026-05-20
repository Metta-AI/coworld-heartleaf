import
  std/[json, locks, math, monotimes, os, parseopt, random, strutils,
    tables, times],
  mummy, pixie, supersnappy,
  heartleaf/aseprite, heartleaf/pixelfonts, heartleaf/protocol,
  heartleaf/resources

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
  InteractionRadius = 22
  MotionScale = 256
  Accel = 84
  FrictionNum = 184
  FrictionDen = 256
  MaxSpeed = 672
  StopThreshold = 12
  CollisionNudgePixels = 4
  MinSpawnSpacing = 20
  SpawnScanStep = 4
  HouseSpawnMaxDistance = 96
  TicksPerSecond = 24
  DayRealMinutes = 2
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
  PlayerClientRoute = "/client/player"
  GlobalClientRoute = "/client/global"
  PlayerClientHtmlRoute = "/client/player.html"
  GlobalClientHtmlRoute = "/client/global.html"
  PlayerClientLegacyHtmlRoute = "/client/player_client.html"
  GlobalClientLegacyHtmlRoute = "/client/global_client.html"
  CoworldPlayerClientRoute = "/clients/player"
  CoworldGlobalClientRoute = "/clients/global"
  SnappyClientRoute = "/snappyjs.min.js"
  SnappyClientPath = "/client/snappyjs.min.js"
  CoworldSnappyClientRoute = "/clients/snappyjs.min.js"
  ClientHtml = "client.html"
  SnappyClientJs = "snappyjs.min.js"
  MapLayerId = 0
  UiLayerId = 1
  ClockLayerId = 2
  MapLayerKind = 0
  UiLayerKind = 3
  ClockLayerKind = 2
  MapLayerFlags = 1
  UiLayerFlags = 2
  InventoryColumns = 8
  InventoryRows = (FoodVeggieSlots + InventoryColumns - 1) div InventoryColumns
  InventoryIconStep = 34
  InventoryUiWidth = InventoryColumns * InventoryIconStep
  InventoryUiHeight = InventoryRows * InventoryIconStep
  ClockUiWidth = 72
  ClockUiHeight = 12
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
  ClockGlyphs = "0123456789: AMP"
  TintHueTargets = [0.80, 0.78, 0.75, 0.70, 0.64]
  TintHueMixes = [0.18, 0.30, 0.43, 0.57, 0.72]
  TintSaturationScales = [1.05, 1.12, 1.20, 1.30, 1.38]
  TintValueScales = [0.86, 0.70, 0.54, 0.39, 0.25]
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
    name: string
    x, y: int
    velX, velY: int
    carryX, carryY: int
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
    globalInitPacket: seq[uint8]

  PlayerViewerState = ref object
    initialized: bool
    spriteCache: seq[SpriteCacheEntry]

  WebSocketAppState = ref object
    lock: Lock
    inputMasks: Table[WebSocket, uint8]
    lastAppliedMasks: Table[WebSocket, uint8]
    playerIndices: Table[WebSocket, int]
    playerViewers: Table[WebSocket, PlayerViewerState]
    globalViewers: Table[WebSocket, PlayerViewerState]
    playerNames: Table[WebSocket, string]
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
    saveScoresPath: string
    tokens: seq[string]

var appState: WebSocketAppState

proc addSpriteProtocolInit(
  packet: var seq[uint8],
  sim: SimServer,
  viewportWidth,
  viewportHeight: int
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

proc clientsDir(): string =
  ## Returns the Heartleaf clients directory.
  let cwdClients = getCurrentDir() / "clients"
  if fileExists(cwdClients / ClientHtml):
    return cwdClients
  let repoClients = getCurrentDir() / "heartleaf" / "clients"
  if fileExists(repoClients / ClientHtml):
    return repoClients
  let sourceClients = currentSourcePath().parentDir().parentDir() / "clients"
  if fileExists(sourceClients / ClientHtml):
    return sourceClients
  currentSourcePath().parentDir() / "clients"

proc cogamePath(value, source: string): string =
  ## Converts one COGAME file URI or path into a local path.
  if value.len == 0:
    return ""
  const FilePrefix = "file://"
  if value.startsWith(FilePrefix):
    result = value[FilePrefix.len .. ^1]
    if result.len == 0:
      raise newException(HeartleafError, "Empty file URI from " & source & ".")
    return
  if value.contains("://"):
    raise newException(
      HeartleafError,
      "Unsupported URI from " & source & ": " & value
    )
  value

proc resultsPathFromEnv(): string =
  ## Reads one scores path from the current and legacy env vars.
  result = getEnv("COGAME_SAVE_RESULTS_PATH")
  if result.len == 0:
    result = getEnv("COGAME_RESULTS_PATH")
  if result.len == 0:
    result = cogamePath(getEnv("COGAME_RESULTS_URI"), "COGAME_RESULTS_URI")

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
    ViewportHeight
  )
  result.globalInitPacket.addSpriteProtocolInit(
    result,
    result.mainMap.width,
    result.mainMap.height
  )

proc addU8(packet: var seq[uint8], value: uint8) =
  ## Appends one unsigned byte.
  packet.add(value)

proc addU16(packet: var seq[uint8], value: int) =
  ## Appends one little endian unsigned 16 bit value.
  let v = uint16(value)
  packet.add(uint8(v and 0xff'u16))
  packet.add(uint8(v shr 8))

proc addU32(packet: var seq[uint8], value: int) =
  ## Appends one little endian unsigned 32 bit value.
  let v = uint32(value)
  for shift in countup(0, 24, 8):
    packet.add(uint8((v shr shift) and 0xff'u32))

proc addI16(packet: var seq[uint8], value: int) =
  ## Appends one little endian signed 16 bit value.
  let v = cast[uint16](int16(value))
  packet.add(uint8(v and 0xff'u16))
  packet.add(uint8(v shr 8))

proc addViewport(packet: var seq[uint8], layer, width, height: int) =
  ## Appends one sprite protocol viewport message.
  packet.addU8(0x05'u8)
  packet.addU8(uint8(layer))
  packet.addU16(width)
  packet.addU16(height)

proc addLayer(packet: var seq[uint8], layer, layerKind, flags: int) =
  ## Appends one sprite protocol layer definition message.
  packet.addU8(0x06'u8)
  packet.addU8(uint8(layer))
  packet.addU8(uint8(layerKind))
  packet.addU8(uint8(flags))

proc addSprite(
  packet: var seq[uint8],
  spriteId, width, height: int,
  pixels: openArray[uint8],
  label: string
) =
  ## Appends one compressed RGBA sprite definition message.
  packet.addU8(0x01'u8)
  packet.addU16(spriteId)
  packet.addU16(width)
  packet.addU16(height)

  var raw = newSeq[uint8](pixels.len)
  for i in 0 ..< pixels.len:
    raw[i] = pixels[i]
  let compressed = supersnappy.compress(raw)
  packet.addU32(compressed.len)
  for byte in compressed:
    packet.addU8(byte)

  packet.addU16(label.len)
  for ch in label:
    packet.addU8(uint8(ord(ch)))

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

proc addObject(
  packet: var seq[uint8],
  objectId, x, y, z, layer, spriteId: int
) =
  ## Appends one sprite protocol object definition message.
  packet.addU8(0x02'u8)
  packet.addU16(objectId)
  packet.addI16(x)
  packet.addI16(y)
  packet.addI16(z)
  packet.addU8(uint8(layer))
  packet.addU16(spriteId)

proc addClearObjects(packet: var seq[uint8]) =
  ## Appends one sprite protocol clear objects message.
  packet.addU8(0x04'u8)

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
    sim.blitChatText(result, player.name, x, y + GnomeSpriteSize + 2)
    sim.blitChatText(result, "Score: " & $player.score, x + 36, y + 12)

proc addNameTag(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  player: Player,
  playerIndex,
  screenX,
  screenY,
  z: int
): int =
  ## Appends a player name tag and returns its top y coordinate.
  let
    tag = sim.nameTagSprite(player.name)
    x = screenX + GnomeSpriteSize div 2 - tag.width div 2
    y = screenY - tag.height - NameGapY
    spriteId = NameSpriteBase + playerIndex
  packet.addRgbaSpriteCached(cache, spriteId, tag, "name " & player.name)
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
  z: int
) =
  ## Appends a speech bubble object above one player name.
  if player.message.len == 0 or player.messageTicks <= 0:
    return
  let
    bubble = sim.speechBubbleSprite(player.message)
    x = screenX + GnomeSpriteSize div 2 - bubble.width div 2
    y = anchorY - bubble.height - ChatGapY
    spriteId = ChatSpriteBase + playerIndex
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
  if ch >= '0' and ch <= '9':
    return ord(ch) - ord('0')
  case ch
  of ':':
    10
  of 'A':
    11
  of 'M':
    12
  of 'P':
    13
  else:
    14

proc clockGlyphSpriteId(ch: char): int =
  ## Returns the sprite id for one clock glyph.
  ClockGlyphSpriteBase + ch.clockGlyphIndex()

proc foodName(foodIndex: int): string =
  ## Returns the display name for one food slot.
  if foodIndex >= 0 and foodIndex < FoodNames.len:
    return FoodNames[foodIndex]
  "food " & $foodIndex

proc dailyResultsJson*(sim: SimServer): string =
  ## Returns one daily player score result as JSON.
  var
    names = newJArray()
    scores = newJArray()
    results = newJObject()
  for player in sim.players:
    names.add(%player.name)
    scores.add(%player.score)
  results["day"] = %sim.dayNumber
  results["names"] = names
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
  ## Returns the current game clock as 12-hour AM/PM text.
  let
    minutes = sim.currentDayMinutes()
    hour24 = minutes div 60
    minute = minutes mod 60
    suffix =
      if hour24 < 12:
        "AM"
      else:
        "PM"
    hour12 =
      if hour24 mod 12 == 0:
        12
      else:
        hour24 mod 12
  $hour12 & ":" & minute.twoDigits() & " " & suffix

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
  viewportHeight: int
) =
  ## Appends static sprite protocol setup for one viewer.
  packet.addViewport(MapLayerId, viewportWidth, viewportHeight)
  packet.addViewport(UiLayerId, InventoryUiWidth, InventoryUiHeight)
  packet.addViewport(ClockLayerId, ClockUiWidth, ClockUiHeight)
  packet.addLayer(MapLayerId, MapLayerKind, MapLayerFlags)
  packet.addLayer(UiLayerId, UiLayerKind, UiLayerFlags)
  packet.addLayer(ClockLayerId, ClockLayerKind, UiLayerFlags)
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

proc collisionRectAt(x, y: int): Rect =
  ## Returns the player foot collision rectangle at a sprite position.
  Rect(
    x: x + PlayerBoxOffsetX,
    y: y + PlayerBoxOffsetY,
    w: PlayerBoxWidth,
    h: PlayerBoxHeight
  )

proc playerCenterX(player: Player): int =
  ## Returns the visible center x coordinate for one player.
  player.x + GnomeSpriteSize div 2

proc playerCenterY(player: Player): int =
  ## Returns the visible center y coordinate for one player.
  player.y + GnomeSpriteSize div 2

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
  let rect = collisionRectAt(x, y)
  if rect.x < 0 or rect.y < 0 or
      rect.x + rect.w > world.width or
      rect.y + rect.h > world.height:
    return false

  for py in rect.y ..< rect.y + rect.h:
    for px in rect.x ..< rect.x + rect.w:
      if not world.isWalkable(px, py):
        return false
  true

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
    cx = x + GnomeSpriteSize div 2
    cy = y + GnomeSpriteSize div 2
  for player in sim.players:
    if player.mapIndex != mapIndex:
      continue
    if distanceSquared(
      cx,
      cy,
      player.playerCenterX(),
      player.playerCenterY()
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
        let feet = collisionRectAt(x, y)
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
        if distanceSquared(x, y, doorX, doorY) <= radius * radius and
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

proc cleanPlayerName(name: string): string =
  ## Normalizes one display name for the sprite protocol.
  result = name.cleanDisplayText(NameMaxChars)
  for ch in result.mitems:
    if ch.isSpaceAscii:
      ch = '_'

proc addPlayer(sim: SimServer, name: string): int =
  ## Adds one player at a walkable spawn.
  var usedHomes: array[HouseCount, bool]
  for player in sim.players:
    if player.homeFlag.isHomeMap():
      usedHomes[player.homeFlag - HomeMapIndexBase] = true

  var houseIndex = -1
  for i in 0 ..< HouseCount:
    if not usedHomes[i]:
      houseIndex = i
      break
  if houseIndex < 0:
    return -1

  let
    mapIndex = houseIndex.homeMapIndex()
    spawn = sim.findHomeSpawn(mapIndex)
    requestedName = name.cleanPlayerName()
    cleanName =
      if requestedName.len > 0:
        requestedName
      else:
        "player_" & $(sim.players.len + 1)
    gnomeIndex = houseIndex mod sim.gnomes.len
  sim.players.add Player(
    name: cleanName,
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
    feet = collisionRectAt(player.x, player.y)
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
  ## Returns the house containing a player's center point.
  result = -1
  if player.mapIndex != MainMapIndex:
    return
  let
    centerX = player.playerCenterX()
    centerY = player.playerCenterY()
  for i, house in sim.houses:
    if house.valid and house.rect.contains(centerX, centerY):
      return i

proc playerAtHomeExit(sim: SimServer, player: Player): bool =
  ## Returns true when a home player is standing in the exit area.
  if not player.mapIndex.isHomeMap():
    return false
  if not sim.homeResources.hasExit:
    return false
  sim.homeResources.exit.contains(
    player.playerCenterX(),
    player.playerCenterY()
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
    player.playerCenterX() - ViewportWidth div 2,
    world.width - ViewportWidth
  )

proc cameraYFor(sim: SimServer, player: Player): int =
  ## Returns the player camera y coordinate.
  let world = sim.mapFor(player.mapIndex)
  worldClampPixel(
    player.playerCenterY() - ViewportHeight div 2,
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
  cameraY: int
) =
  ## Appends all player sprite objects for one map.
  for i, player in sim.players:
    if player.mapIndex != mapIndex:
      continue
    let
      screenX = player.x - cameraX
      screenY = player.y - cameraY
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
      NameZ
    )
    packet.addSpeechBubble(
      sim,
      cache,
      player,
      i,
      screenX,
      nameY,
      ChatZ
    )

proc addGardenObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cameraX,
  cameraY: int
) =
  ## Appends garden item markers for gardens that still hold food.
  for i, garden in sim.gardens:
    if not garden.hasFood():
      continue
    let
      x = garden.rect.x + garden.rect.w div 2 - FoodSpriteSize div 2
      y = garden.rect.y + garden.rect.h div 2 - FoodSpriteSize div 2
    packet.addObject(
      GardenObjectBase + i,
      x - cameraX,
      y - cameraY,
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
    result.addScreenOverlay(
      sim,
      nextState.spriteCache,
      player,
      playerIndex
    )
    return
  result.addObject(
    BottomObjectId,
    -cameraX,
    -cameraY,
    BottomZ,
    MapLayerId,
    bottomSpriteId
  )
  if onMainMap:
    result.addGardenObjects(sim, cameraX, cameraY)
  result.addPlayerObjects(
    sim,
    nextState.spriteCache,
    player.mapIndex,
    cameraX,
    cameraY
  )
  result.addObject(
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
    result.addObject(
      DebugObjectId,
      -cameraX,
      -cameraY,
      DebugZ,
      MapLayerId,
      debugSpriteId
    )
  result.addInventoryObjects(
    sim,
    nextState.spriteCache,
    player
  )
  result.addClockObjects(sim)

proc buildGlobalPacket(
  sim: SimServer,
  state: PlayerViewerState,
  nextState: var PlayerViewerState
): seq[uint8] =
  ## Builds one sprite protocol packet for a global viewer.
  nextState =
    if state == nil:
      PlayerViewerState()
    else:
      state
  if not nextState.initialized:
    result.add(sim.globalInitPacket)
    nextState.initialized = true

  result.addClearObjects()
  if sim.scoreTicks > 0:
    let overlay = sim.scoreOverlaySprite()
    result.addRgbaSpriteCached(
      nextState.spriteCache,
      ScoreSpriteBase,
      overlay,
      "score global"
    )
    result.addObject(
      ScoreObjectBase,
      0,
      0,
      ScoreZ,
      MapLayerId,
      ScoreSpriteBase
    )
    return

  let tintIndex = sim.dayTintIndex()
  result.addObject(
    BottomObjectId,
    0,
    0,
    BottomZ,
    MapLayerId,
    mainBottomSpriteId(tintIndex)
  )
  result.addGardenObjects(sim, 0, 0)
  result.addPlayerObjects(
    sim,
    nextState.spriteCache,
    MainMapIndex,
    0,
    0
  )
  result.addObject(
    OverhangObjectId,
    0,
    0,
    OverhangZ,
    MapLayerId,
    mainOverhangSpriteId(tintIndex)
  )
  when DebugOutlines:
    result.addObject(
      DebugObjectId,
      0,
      0,
      DebugZ,
      MapLayerId,
      DebugSpriteId
    )
  result.addClockObjects(sim)

proc applyDrag(value: var int) =
  ## Applies one tick of friction to a velocity component.
  value = (value * FrictionNum) div FrictionDen
  if abs(value) <= StopThreshold:
    value = 0

proc clampVelocity(velX, velY: var int) =
  ## Clamps a velocity vector to the maximum speed.
  let magnitudeSq = velX * velX + velY * velY
  if magnitudeSq <= MaxSpeed * MaxSpeed:
    return
  let magnitude = sqrt(float(magnitudeSq))
  if magnitude <= 0.0:
    return
  velX = int(round(float(velX) * float(MaxSpeed) / magnitude))
  velY = int(round(float(velY) * float(MaxSpeed) / magnitude))

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
  if inputX != 0:
    sim.players[playerIndex].velX += inputX * Accel
  else:
    sim.players[playerIndex].velX.applyDrag()
  if inputY != 0:
    sim.players[playerIndex].velY += inputY * Accel
  else:
    sim.players[playerIndex].velY.applyDrag()
  sim.players[playerIndex].velX = sim.players[playerIndex].velX.clamp(
    -MaxSpeed,
    MaxSpeed
  )
  sim.players[playerIndex].velY = sim.players[playerIndex].velY.clamp(
    -MaxSpeed,
    MaxSpeed
  )
  clampVelocity(sim.players[playerIndex].velX, sim.players[playerIndex].velY)

proc signum(value: int): int =
  ## Returns the sign of one integer as -1, 0, or 1.
  if value < 0:
    return -1
  if value > 0:
    return 1
  0

proc nudgePathClear(
  world: WorldMap,
  player: Player,
  step,
  offset: int,
  horizontal: bool
): bool =
  ## Returns true when a nudged move path stays inside walkable space.
  let offsetSign = offset.signum()
  for i in 1 .. abs(offset):
    let nudge = offsetSign * i
    if horizontal:
      if not world.canOccupy(player.x, player.y + nudge):
        return false
      if not world.canOccupy(player.x + step, player.y + nudge):
        return false
    else:
      if not world.canOccupy(player.x + nudge, player.y):
        return false
      if not world.canOccupy(player.x + nudge, player.y + step):
        return false
  true

proc tryNudgeOffset(
  world: WorldMap,
  player: Player,
  step,
  offset: int,
  horizontal: bool,
  dx,
  dy: var int
): bool =
  ## Finds one valid nudged move for a blocked one-pixel step.
  if not world.nudgePathClear(player, step, offset, horizontal):
    return false
  if horizontal:
    dx = step
    dy = offset
  else:
    dx = offset
    dy = step
  true

proc moveWithNudge(
  world: WorldMap,
  player: Player,
  step: int,
  horizontal: bool,
  dx,
  dy: var int
): bool =
  ## Finds a direct or gently nudged one-pixel movement step.
  dx = 0
  dy = 0
  if horizontal:
    dx = step
  else:
    dy = step
  if world.canOccupy(player.x + dx, player.y + dy):
    return true

  let preferred =
    if horizontal:
      player.velY.signum()
    else:
      player.velX.signum()
  for distance in 1 .. CollisionNudgePixels:
    if preferred != 0 and world.tryNudgeOffset(
      player,
      step,
      preferred * distance,
      horizontal,
      dx,
      dy
    ):
      return true
    for direction in [-1, 1]:
      if direction == preferred:
        continue
      if world.tryNudgeOffset(
        player,
        step,
        direction * distance,
        horizontal,
        dx,
        dy
      ):
        return true

proc moveAxis(sim: SimServer, player: Player, horizontal: bool) =
  ## Moves one player along one axis using pixel collision.
  let world = sim.mapFor(player.mapIndex)
  if horizontal:
    player.carryX += player.velX
    while abs(player.carryX) >= MotionScale:
      let step =
        if player.carryX < 0:
          -1
        else:
          1
      var
        dx = 0
        dy = 0
      if world.moveWithNudge(player, step, horizontal, dx, dy):
        player.x += dx
        player.y += dy
        player.carryX -= step * MotionScale
      else:
        player.carryX = 0
        player.velX = 0
        break
  else:
    player.carryY += player.velY
    while abs(player.carryY) >= MotionScale:
      let step =
        if player.carryY < 0:
          -1
        else:
          1
      var
        dx = 0
        dy = 0
      if world.moveWithNudge(player, step, horizontal, dx, dy):
        player.x += dx
        player.y += dy
        player.carryY -= step * MotionScale
      else:
        player.carryY = 0
        player.velY = 0
        break

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
      guestNames.add(sim.players[visitorIndex].name)
      guestGnomeIndices.add(sim.players[visitorIndex].gnomeIndex)

    let
      hostFoods = host.inventory
      fedFoods = hostFoods.scaledFoods(visitors.len)
      score = hostFoods.totalItems() * visitors.len
      hostRecord = DinnerRecord(
        hostName: host.name,
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
        hostName: host.name,
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
  appState.playerViewers = initTable[WebSocket, PlayerViewerState]()
  appState.globalViewers = initTable[WebSocket, PlayerViewerState]()
  appState.playerNames = initTable[WebSocket, string]()
  appState.chatMessages = initTable[WebSocket, string]()
  appState.closedSockets = @[]
  appState.tokens = @[]

proc readSpriteInputText(message: string): string =
  ## Reads printable text from sprite player input messages.
  var offset = 0
  while offset < message.len:
    let messageType = message[offset].uint8
    inc offset
    case messageType
    of 0x81:
      if offset + 2 > message.len:
        return
      let length = int(uint16(message[offset].uint8) or
        (uint16(message[offset + 1].uint8) shl 8))
      offset += 2
      if offset + length > message.len:
        return
      for i in 0 ..< length:
        let value = message[offset + i].uint8
        if value >= 32'u8 and value < 127'u8:
          result.add(message[offset + i])
      offset += length
    of 0x82:
      if offset + 4 > message.len:
        return
      offset += 4
      if offset < message.len and message[offset].uint8 notin
          {0x81'u8, 0x82'u8, 0x83'u8, 0x84'u8}:
        inc offset
    of 0x83:
      if offset + 2 > message.len:
        return
      offset += 2
    of 0x84:
      if offset + 1 > message.len:
        return
      inc offset
    else:
      return

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
  if websocket in appState.globalViewers:
    appState.globalViewers.del(websocket)
  if websocket in appState.playerViewers:
    appState.playerViewers.del(websocket)
  if websocket in appState.playerNames:
    appState.playerNames.del(websocket)
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

proc serveClientFile(request: Request, route: string): bool =
  ## Serves one shared sprite client static file.
  if request.httpMethod != "GET":
    return false
  var headers: HttpHeaders
  headers["Cache-Control"] = "no-cache"
  var filePath = ""
  case route
  of PlayerClientRoute, PlayerClientHtmlRoute, PlayerClientLegacyHtmlRoute,
      CoworldPlayerClientRoute, GlobalClientRoute, GlobalClientHtmlRoute,
      GlobalClientLegacyHtmlRoute, CoworldGlobalClientRoute:
    filePath = clientsDir() / ClientHtml
    headers["Content-Type"] = "text/html; charset=utf-8"
  of SnappyClientRoute, SnappyClientPath, CoworldSnappyClientRoute:
    filePath = clientsDir() / SnappyClientJs
    headers["Content-Type"] = "application/javascript; charset=utf-8"
  else:
    return false
  if not fileExists(filePath):
    request.respond(404, headers, "Missing static client: " & route)
    return true
  try:
    request.respond(200, headers, readFile(filePath))
  except IOError as e:
    request.respond(500, headers, "Could not read static client: " & e.msg)
  true

proc serveSpriteStatic(request: Request): bool =
  ## Serves shared sprite client routes.
  request.serveClientFile(request.path)

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

proc playerName(request: Request): string =
  ## Returns the requested player display name.
  request.queryParams.getOrDefault("name", "").cleanPlayerName()

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
    discard request.serveClientFile(GlobalClientRoute)
  elif request.path == WebSocketPath and request.httpMethod == "GET" and
      request.isWebSocketUpgrade():
    let
      slot = request.playerSlot()
      token = request.playerToken()
      name = request.playerName()
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
        appState.playerNames[websocket] = name
        appState.inputMasks[websocket] = 0
        appState.lastAppliedMasks[websocket] = 0
  elif request.path == GlobalWebSocketPath and request.httpMethod == "GET" and
      request.isWebSocketUpgrade():
    let websocket = request.upgradeToWebSocket()
    {.gcsafe.}:
      withLock appState.lock:
        appState.globalViewers[websocket] = PlayerViewerState()
  elif request.serveSpriteStatic():
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

proc appendDailyScores(path, jsonLine: string) =
  ## Appends one daily score JSON line to a configured results file.
  if path.len == 0:
    return
  if not fileExists(path):
    writeFile(path, "")
  var file: File
  if not open(file, path, fmAppend):
    raise newException(HeartleafError, "Could not open scores file: " & path)
  try:
    file.write(jsonLine)
    file.write("\n")
  finally:
    file.close()

proc writeDailyScores(sim: SimServer, path: string) =
  ## Appends the current day scores when score saving is configured.
  if path.len == 0:
    return
  appendDailyScores(path, sim.dailyResultsJson())
  echo "Scores written: ", path, " (day ", sim.dayNumber, ", ",
    getFileSize(path), " bytes)"

proc runServerLoop*(
  host = DefaultHost,
  port = DefaultPort,
  seed = DefaultSeed,
  maxTicks = DefaultMaxTicks,
  maxGames = DefaultMaxGames,
  saveScoresPath = "",
  tokens: seq[string] = @[]
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
              appState.playerNames.getOrDefault(websocket, "")
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
      sim.writeDailyScores(saveScoresPath)
    inc runTicks

    for i in 0 ..< sockets.len:
      var nextState: PlayerViewerState
      let packet = sim.buildPlayerPacket(
        playerIndices[i],
        playerStates[i],
        nextState
      )
      try:
        sockets[i].send(blobFromBytes(packet), BinaryMessage)
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
        globalSockets[i].send(blobFromBytes(packet), BinaryMessage)
        {.gcsafe.}:
          withLock appState.lock:
            if globalSockets[i] in appState.globalViewers:
              appState.globalViewers[globalSockets[i]] = nextState
      except CatchableError:
        {.gcsafe.}:
          withLock appState.lock:
            sim.removePlayer(globalSockets[i])

    if maxTicks > 0 and runTicks >= maxTicks:
      inc gamesFinished
      if maxGames > 0 and gamesFinished >= maxGames:
        quit(0)
      sim = initSimServer(seed + gamesFinished)
      runTicks = 0
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
  let node = parseJson(jsonText)
  if node.kind != JObject:
    raise newException(HeartleafError, "Config must be a JSON object.")
  node.readConfigString("address", config.address)
  node.readConfigInt("port", config.port)
  node.readConfigInt("seed", config.seed)
  node.readConfigInt("maxTicks", config.maxTicks)
  node.readConfigInt("max-ticks", config.maxTicks)
  node.readConfigInt("maxGames", config.maxGames)
  node.readConfigInt("max-games", config.maxGames)
  node.readConfigString("saveScoresPath", config.saveScoresPath)
  node.readConfigString("save-scores", config.saveScoresPath)
  node.readConfigStrings("tokens", config.tokens)

when isMainModule:
  var
    config = RunConfig(
      address: DefaultHost,
      port: DefaultPort,
      seed: DefaultSeed,
      maxTicks: DefaultMaxTicks,
      maxGames: DefaultMaxGames,
      saveScoresPath: resultsPathFromEnv(),
      tokens: @[]
    )
    configJson = ""
    configPath = getEnv("COGAME_CONFIG_PATH")
    positional = 0
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      if positional == 0:
        config.address = key
      elif positional == 1:
        config.port = parseInt(key)
      inc positional
    of cmdLongOption:
      case key
      of "address":
        config.address = val
      of "port":
        config.port = parseInt(val)
      of "seed":
        config.seed = parseInt(val)
      of "maxTicks", "max-ticks":
        config.maxTicks = parseInt(val)
      of "maxGames", "max-games":
        config.maxGames = parseInt(val)
      of "saveScores", "save-scores":
        config.saveScoresPath = val
      of "token":
        config.tokens.add(val)
      of "config":
        configJson = val
      of "config-file":
        configPath = val
      else:
        discard
    else:
      discard
  if configPath.len > 0:
    config.update(readFile(configPath))
  if configJson.len > 0:
    config.update(configJson)
  if config.saveScoresPath.len > 0:
    echo "Using results save file: " & config.saveScoresPath
  runServerLoop(
    config.address,
    config.port,
    seed = config.seed,
    maxTicks = config.maxTicks,
    maxGames = config.maxGames,
    saveScoresPath = config.saveScoresPath,
    tokens = config.tokens
  )
