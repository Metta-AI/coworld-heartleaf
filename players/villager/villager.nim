import
  std/[algorithm, heapqueue, options, os, parseopt, strutils],
  bitworld/[protocol, resources],
  supersnappy, whisky

when defined(gui):
  import
    pixie, silky, vmath, windy

const
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
  GreetingRadius = 90
  NavStep = 2
  PathArrivePixels = 3
  PathRejoinPixels = 8
  MoveDeadZonePixels = 1
  PathLookaheadPixels = 4
  StuckLookaheadPixels = 10
  StuckLookaheadTicks = 18
  RepathStuckTicks = 48
  MaxDrainMessages = 256
  DefaultName = "villager"
  UnknownHouse = -1
  HouseCount = 9
  DoorGatherSlots = 5
  DoorGatherSpacing = 18
  DayStartMinutes = 8 * 60
  HouseEnterMinutes = 17 * 60
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
  GardenObjectBase = 4000
  InventoryObjectBase = 5000
  InventoryCountObjectBase = 6000
  ClockObjectBase = 7000
  ScoreObjectBase = 7100
  GreetingWords = ["Hey", "Hi", "Hello"]
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
    SpriteClock
    SpriteOverlay

  GoalKind = enum
    GoalIdle
    GoalCollect
    GoalGatherHouse
    GoalEnterHouse
    GoalExitHouse
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

  Bot = ref object
    name: string
    playerName: string
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
    goal: Goal
    path: seq[Point]
    gardenChecked: seq[bool]
    greetedNames: seq[string]
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

proc repoDir(): string =
  ## Returns the Heartleaf repository directory.
  currentSourcePath().parentDir().parentDir().parentDir()

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

proc hasGreeted(bot: Bot, name: string): bool =
  ## Returns true when this bot has greeted a name today.
  for greetedName in bot.greetedNames:
    if greetedName == name:
      return true

proc greetingText(bot: Bot, name: string): string =
  ## Returns one short greeting for a nearby player.
  let word = GreetingWords[
    (bot.selfIndex + bot.greetedNames.len) mod GreetingWords.len
  ]
  word & " " & name

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
    a.gardenIndex == b.gardenIndex

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

proc resetGardenPlan(bot: Bot) =
  ## Resets the static garden checklist and greetings for a new day.
  inc bot.dayIndex
  bot.gardenChecked = newSeq[bool](bot.resources.gardens.len)
  bot.greetedNames.setLen(0)
  bot.currentGarden = -1
  bot.partyHouse = UnknownHouse
  bot.searchHouse = UnknownHouse
  bot.hostUntilMinutes = -1
  bot.hostCommitted = false
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
  bot.homeIndex = homeIndex
  bot.currentHouse =
    if bot.mapKind == MapHome:
      homeIndex
    else:
      UnknownHouse
  bot.pendingHouse = UnknownHouse
  bot.partyHouse = UnknownHouse
  bot.searchHouse = UnknownHouse
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

proc maybeGreetNearby(bot: Bot, ws: WebSocket) =
  ## Greets newly seen nearby players once per day.
  if not bot.localized or bot.mapKind == MapOverlay:
    return
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
    ws.send(blobFromChat(message), BinaryMessage)
    bot.log("chat " & message)
    return

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
  ## Builds a new Villager bot state.
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
  result.dayIndex = 0
  result.gardenChecked = newSeq[bool](result.resources.gardens.len)
  result.greetedNames = @[]

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

proc chooseGoal(bot: Bot): Goal =
  ## Chooses the current Heartleaf day-plan goal.
  if not bot.localized or bot.navForCurrentMap() == nil:
    return Goal(kind: GoalIdle, mapKind: bot.mapKind)
  if bot.mapKind == MapOverlay:
    return Goal(kind: GoalIdle, mapKind: bot.mapKind)
  if bot.shouldGather():
    if bot.mapKind == MapHome:
      return bot.exitGoal()
    let garden = bot.gardenGoal()
    if garden.kind != GoalIdle:
      return garden
  if bot.minutes < HouseEnterMinutes:
    return bot.dinnerGatherGoal()
  if bot.minutes < PartyLeaveMinutes:
    return bot.partyGoal()
  if bot.minutes < DayEndMinutes:
    return bot.ownHomeGoal()
  Goal(kind: GoalIdle, mapKind: bot.mapKind)

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

proc decideNextMask(bot: Bot): uint8 =
  ## Chooses the next input mask for one game frame.
  bot.analyze()
  if not bot.localized:
    bot.desiredMask = 0
    bot.hasTarget = false
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
      title = "Heartleaf Villager Viewer",
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
  gui: bool,
  exitOnDisconnect: bool
) =
  ## Connects the Villager bot to a Heartleaf sprite player endpoint.
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
  let viewer =
    if useGui:
      initViewerApp()
    else:
      nil
  var
    connected = false
    hadConnection = false
  while viewer.viewerOpen():
    try:
      let ws = newWebSocket(connectUrl)
      echo "villager connected to ", connectUrl
      connected = true
      hadConnection = true
      bot.lastMask = 0xff'u8
      while viewer.viewerOpen():
        if not ws.receiveUpdates(bot, useGui):
          if useGui:
            viewer.pumpViewer(bot, connected, connectUrl)
            if not viewer.viewerOpen():
              ws.close()
              break
          continue
        let nextMask = bot.decideNextMask()
        bot.maybeGreetNearby(ws)
        if nextMask != bot.lastMask:
          ws.send(blobFromMask(nextMask), BinaryMessage)
          bot.lastMask = nextMask
        if useGui:
          viewer.pumpViewer(bot, connected, connectUrl)
          if not viewer.viewerOpen():
            ws.close()
            break
    except CatchableError as e:
      connected = false
      echo "villager reconnecting: ", e.msg
      if not useGui and exitOnDisconnect and hadConnection:
        break
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
  let exitOnDisconnect = url.len > 0
  runBot(
    address,
    port,
    name,
    token,
    slot,
    url,
    gui,
    exitOnDisconnect
  )
