## Race the gnomes for the gardens and draw where they walk.
##
## A house is worth what its owner can actually carry home, and that is
## a question about walking rather than about how much garden lies
## inside a circle. Every plot is taken each morning, so the day is a
## race: nine gnomes leave their doors at once, each heading for the
## nearest plot nobody has taken, claiming it and moving on. Two can
## want the same plot, and the slower one has spent the walk for
## nothing — which is what happens in the game.
##
## Distances are walked over the map's own walkable layer with the same
## pathfinder the players use, so a fence between a door and a plot
## counts against that door. Straight-line distance treats a wall as a
## shortcut and rates the map wrongly.
##
## Usage:
##   gen_fairness_image [--out:path.png] [--scale:N]

import
  std/[algorithm, math, os, parseopt, strformat, strutils, times],
  pixie, pathy,
  bitworld/[aseprite, pixelfonts, resources],
  ../src/heartleaf/[common, protocol]

const
  DefaultOutPath = "docs/heartleafFairness.png"
  DefaultScale = 2
  PanelWidth = 360
  Ink = rgba(20, 20, 20, 255)
  FadedInk = rgba(105, 105, 105, 255)
  Parchment = rgba(250, 249, 242, 255)
  ## One hue per house, so a route can be traced back to its door.
  HouseHues = [
    rgba(214, 64, 52, 255),
    rgba(232, 133, 38, 255),
    rgba(188, 160, 28, 255),
    rgba(96, 176, 62, 255),
    rgba(40, 160, 140, 255),
    rgba(58, 126, 214, 255),
    rgba(124, 88, 196, 255),
    rgba(198, 74, 156, 255),
    rgba(110, 110, 110, 255)
  ]

type
  Racer = object
    index: int
    owner: string
    at: Point
    travelled: float
    gardensWon: int
    rerouted: int
    ## Every position the gnome actually stood on, in order.
    trail: seq[Point]

proc repoDir(): string =
  currentSourcePath().parentDir().parentDir()

proc layerIndex(sprite: AsepriteSprite, names: openArray[string]): int =
  for i, layer in sprite.layers:
    for name in names:
      if layer.name.normalize() == name.normalize():
        return i
  -1

proc toDensePath(steps: openArray[PathStep]): seq[Point] =
  ## Converts sparse jump-point steps into the dense line a gnome
  ## actually walks, so the drawn route follows the ground rather than
  ## cutting between waypoints.
  const DensifyPixels = 4
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
    var walked = DensifyPixels
    while walked < span:
      result.add(Point(
        x: previous.x + dx * walked div span,
        y: previous.y + dy * walked div span
      ))
      walked += DensifyPixels
    result.add(point)

proc pathLength(points: seq[Point]): float =
  ## Returns how far a dense path actually walks.
  for i in 1 ..< points.len:
    let
      dx = float(points[i].x - points[i - 1].x)
      dy = float(points[i].y - points[i - 1].y)
    result += sqrt(dx * dx + dy * dy)

proc joinFrom(start: Point, walk: seq[Point]): seq[Point] =
  ## Puts the step out of where the gnome stands back on the front of a
  ## route: the pathfinder reports waypoints from the first turn
  ## onwards, so without this a trail starts partway along and the walk
  ## reads as a jump.
  const DensifyPixels = 4
  result.add(start)
  if walk.len > 0:
    let
      dx = walk[0].x - start.x
      dy = walk[0].y - start.y
      span = max(abs(dx), abs(dy))
    var walked = DensifyPixels
    while walked < span:
      result.add(Point(
        x: start.x + dx * walked div span,
        y: start.y + dy * walked div span
      ))
      walked += DensifyPixels
  for point in walk:
    result.add(point)

proc nearestPassable(nav: JumpPointSpace, x, y: int): Point =
  ## Returns the closest walkable pixel, so a door or plot sitting a
  ## pixel inside scenery still has somewhere to stand.
  result = Point(
    x: x.clamp(0, nav.path.width - 1),
    y: y.clamp(0, nav.path.height - 1)
  )
  if nav.path.passable(result.x, result.y):
    return
  for radius in 1 .. 64:
    for dy in -radius .. radius:
      for dx in -radius .. radius:
        if abs(dx) != radius and abs(dy) != radius:
          continue
        let
          px = (x + dx).clamp(0, nav.path.width - 1)
          py = (y + dy).clamp(0, nav.path.height - 1)
        if nav.path.passable(px, py):
          return Point(x: px, y: py)

proc drawPixelText(
  image: Image,
  font: PixelFont,
  text: string,
  x, y: int,
  ink: ColorRGBA,
  textScale = 1
) =
  ## Blits one run of pixel-font text into an image.
  var
    penX = x
    penY = y
  for ch in text:
    if ch == '\n':
      penX = x
      penY += font.lineHeight() * textScale
      continue
    let glyph = font.glyphAt(ch)
    for gy in 0 ..< glyph.height:
      for gx in 0 ..< glyph.width:
        if not glyph.pixels[gy * glyph.width + gx]:
          continue
        for sy in 0 ..< textScale:
          for sx in 0 ..< textScale:
            let
              px = penX + gx * textScale + sx
              py = penY + gy * textScale + sy
            if px >= 0 and py >= 0 and px < image.width and py < image.height:
              image[px, py] = ink
    penX += (glyph.width + font.spacing) * textScale

when isMainModule:
  var
    outPath = DefaultOutPath
    scale = DefaultScale
  for kind, key, value in getopt():
    case kind
    of cmdLongOption:
      case key
      of "out": outPath = value
      of "scale": scale = max(1, parseInt(value))
      else: discard
    else: discard

  let
    dataDir = repoDir() / "data"
    rects = loadResourceRects(dataDir / "map.resource")
  var
    houseRects: seq[(int, ResourceRect)]
    gardenPoints: seq[Point]
  for rect in rects:
    let name = rect.rectName()
    if name == "garden":
      gardenPoints.add(Point(x: rect.x + rect.w div 2, y: rect.y + rect.h div 2))
    elif name.startsWith("house") and name.len > 5:
      try:
        houseRects.add((parseInt(name[5 .. ^1]) - 1, rect))
      except ValueError:
        discard
  houseRects.sort(proc(a, b: (int, ResourceRect)): int = cmp(a[0], b[0]))
  if houseRects.len == 0 or gardenPoints.len == 0:
    quit("map.resource has no houses or gardens to race over")

  let
    mapSprite = readAseprite(dataDir / "map.aseprite")
    bottomIndex = mapSprite.layerIndex(["bottom"])
    walkIndex = mapSprite.layerIndex(["walkable", "walk"])
  if walkIndex < 0:
    quit("map.aseprite has no walkable layer to path over")
  let
    background = mapSprite.layerImage(max(bottomIndex, 0))
    walkImage = mapSprite.layerImage(walkIndex)

  var mask = newSeq[bool](walkImage.width * walkImage.height)
  for y in 0 ..< walkImage.height:
    for x in 0 ..< walkImage.width:
      mask[y * walkImage.width + x] = walkImage[x, y].a > 0
  let nav = newJumpPointSpace(
    mask, walkImage.width, walkImage.height, DiagonalPath
  )

  var
    racers: seq[Racer]
    gardens: seq[Point]
  for (index, rect) in houseRects:
    racers.add(Racer(
      index: index,
      owner: index.playerNameForHouse(),
      at: nav.nearestPassable(rect.x + rect.w div 2, rect.y + rect.h div 2)
    ))
    racers[^1].trail.add(racers[^1].at)
  for point in gardenPoints:
    gardens.add(nav.nearestPassable(point.x, point.y))
  var taken = newSeq[bool](gardens.len)

  ## The morning runs a step at a time. Everyone starts at their door
  ## and walks toward the nearest plot still going; reaching it picks
  ## it up and takes it off the map. A gnome whose plot is taken while
  ## it is still on its way turns for the next nearest one from where
  ## it stands, so nobody ever finishes a walk to a plot that is gone.
  var
    targetOf = newSeq[int](racers.len)
    routeOf = newSeq[seq[Point]](racers.len)
    cursorOf = newSeq[int](racers.len)
  for racer in 0 ..< racers.len:
    targetOf[racer] = -1

  proc chooseTarget(racer: int) =
    ## Sends one gnome to the nearest plot nobody has taken yet,
    ## starting from exactly where it stands.
    var
      bestGarden = -1
      bestRoute: seq[Point]
      bestLength = 0.0
    for i, garden in gardens:
      if taken[i]:
        continue
      var route = nav.findPath(
        racers[racer].at.x, racers[racer].at.y, garden.x, garden.y
      ).toDensePath()
      if route.len == 0:
        continue
      if route[0] != racers[racer].at:
        route = joinFrom(racers[racer].at, route)
      let length = route.pathLength()
      if bestGarden < 0 or length < bestLength:
        bestGarden = i
        bestRoute = route
        bestLength = length
    targetOf[racer] = bestGarden
    routeOf[racer] = bestRoute
    cursorOf[racer] = 0

  let started = epochTime()
  var remaining = gardens.len
  while remaining > 0:
    for racer in 0 ..< racers.len:
      if targetOf[racer] < 0:
        chooseTarget(racer)

    var moved = false
    for racer in 0 ..< racers.len:
      if targetOf[racer] < 0 or routeOf[racer].len == 0:
        continue
      moved = true
      if cursorOf[racer] < routeOf[racer].high:
        inc cursorOf[racer]
        let
          step = routeOf[racer][cursorOf[racer]]
          dx = float(step.x - racers[racer].at.x)
          dy = float(step.y - racers[racer].at.y)
        racers[racer].travelled += sqrt(dx * dx + dy * dy)
        racers[racer].at = step
        racers[racer].trail.add(step)
      if cursorOf[racer] >= routeOf[racer].high:
        if not taken[targetOf[racer]]:
          taken[targetOf[racer]] = true
          inc racers[racer].gardensWon
          dec remaining
        targetOf[racer] = -1

    for racer in 0 ..< racers.len:
      if targetOf[racer] >= 0 and taken[targetOf[racer]]:
        targetOf[racer] = -1
        inc racers[racer].rerouted

    if not moved:
      break

  echo &"raced {gardens.len} gardens over the walkable map in " &
    &"{epochTime() - started:.1f}s"

  let
    scaled = float(scale)
    mapWidth = int(float(background.width) * scaled)
    mapHeight = int(float(background.height) * scaled)
    image = newImage(mapWidth + PanelWidth, max(mapHeight, 520))
    font = readTiny5Font()
  image.fill(Parchment)
  image.draw(background.resize(mapWidth, mapHeight), translate(vec2(0, 0)))
  let veil = newImage(mapWidth, mapHeight)
  veil.fill(rgba(250, 249, 242, 175))
  image.draw(veil, translate(vec2(0, 0)))

  for racer in racers:
    let
      hue = HouseHues[racer.index mod HouseHues.len]
      edge = newContext(image)
      line = newContext(image)
    # Lay a dark stroke under the coloured one so a trail stays legible
    # over grass, path and hedge alike.
    edge.strokeStyle = rgba(0, 0, 0, 190)
    edge.lineWidth = 4.5
    line.strokeStyle = hue
    line.lineWidth = 2.4
    for i in 1 ..< racer.trail.len:
      edge.strokeSegment(segment(
        vec2(float(racer.trail[i - 1].x), float(racer.trail[i - 1].y)) * scaled,
        vec2(float(racer.trail[i].x), float(racer.trail[i].y)) * scaled
      ))
    for i in 1 ..< racer.trail.len:
      line.strokeSegment(segment(
        vec2(float(racer.trail[i - 1].x), float(racer.trail[i - 1].y)) * scaled,
        vec2(float(racer.trail[i].x), float(racer.trail[i].y)) * scaled
      ))

  for garden in gardens:
    let context = newContext(image)
    context.fillStyle = rgba(60, 60, 60, 210)
    context.fillCircle(circle(vec2(float(garden.x), float(garden.y)) * scaled, 3))

  for racer in racers:
    let
      context = newContext(image)
      houseRect = houseRects[racer.index][1]
      at = vec2(
        float(houseRect.x + houseRect.w div 2),
        float(houseRect.y + houseRect.h div 2)
      ) * scaled
      hue = HouseHues[racer.index mod HouseHues.len]
    context.fillStyle = hue
    context.fillRect(rect(at - vec2(13, 13), vec2(26, 26)))
    context.strokeStyle = Ink
    context.lineWidth = 2
    context.strokeRect(rect(at - vec2(13, 13), vec2(26, 26)))
    let label = $(racer.index + 1)
    image.drawPixelText(
      font, label,
      int(at.x) - font.textWidth(label),
      int(at.y) - font.height,
      rgba(255, 255, 255, 255), 2
    )

  var ranked = racers
  ranked.sort(proc(a, b: Racer): int = cmp(b.gardensWon, a.gardensWon))

  var y = 18
  let panelX = mapWidth + 18
  image.drawPixelText(font, "GARDENS WON", panelX, y, Ink, 2)
  y += 26
  image.drawPixelText(
    font, "all nine walk at once, nearest plot first", panelX, y, FadedInk, 1
  )
  y += 12
  image.drawPixelText(
    font, "routes follow the walkable layer", panelX, y, FadedInk, 1
  )
  y += 24
  let mostWon = max(ranked[0].gardensWon, 1)
  for racer in ranked:
    let
      hue = HouseHues[racer.index mod HouseHues.len]
      barWidth = 90 * racer.gardensWon div mostWon
    image.drawPixelText(
      font, &"{racer.index + 1} {racer.owner}", panelX, y, Ink, 2
    )
    for bx in 0 ..< barWidth:
      for by in 0 ..< 9:
        let
          px = panelX + 112 + bx
          py = y + by
        if px < image.width and py < image.height:
          image[px, py] = hue
    image.drawPixelText(
      font, &"{racer.gardensWon:>2}", panelX + 212, y, Ink, 2
    )
    y += 17
    image.drawPixelText(
      font,
      &"walked {int(racer.travelled)}px, {racer.rerouted} turned back",
      panelX + 10, y, FadedInk, 1
    )
    y += 21

  createDir(outPath.parentDir())
  image.writeFile(outPath)

  echo ""
  echo "house  owner    won   walked  turned"
  for racer in ranked:
    echo &"{racer.index + 1:>5}  {racer.owner:<7} {racer.gardensWon:>4}  " &
      &"{int(racer.travelled):>7}  {racer.rerouted:>6}"
  let
    best = ranked[0]
    worst = ranked[^1]
  echo ""
  echo &"best  house {best.index + 1} ({best.owner}) takes " &
    &"{best.gardensWon} of {gardens.len}"
  echo &"worst house {worst.index + 1} ({worst.owner}) takes {worst.gardensWon}"
  if worst.gardensWon > 0:
    echo &"spread {best.gardensWon / worst.gardensWon:.2f}x"
  echo &"an even map would give each door about {gardens.len div racers.len}"
  echo "wrote ", outPath
