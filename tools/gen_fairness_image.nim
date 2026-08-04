## Draw a balancing map of the village and score every house on how
## well it is placed.
##
## The platform gives an entrant the same seat in every round, and the
## game seats a slot in the house of the same number, so an entrant
## plays one house for its whole career. That is only fair if the houses
## are equally good, and they are not: garden within reach varies by
## more than a factor of two, which sets a ceiling on what a gnome can
## carry home before the plots are picked clean. This renders the map
## with every house marked and linked to the gardens it reaches first,
## rates each door, and prints the table the picture is drawn from.
##
## Usage:
##   gen_fairness_image [--out path.png] [--scale N] [--radius PX]

import
  std/[algorithm, math, os, parseopt, strformat, strutils],
  pixie,
  bitworld/[aseprite, pixelfonts, resources],
  ../src/heartleaf/protocol

const
  DefaultOutPath = "docs/heartleafFairness.png"
  DefaultScale = 2
  ## A garden this far from a door is close enough to be worth an early
  ## trip. Every plot on the map is stripped inside the first two hours,
  ## so what a house can reach before the rush is what it actually gets.
  DefaultRadius = 200.0
  ## How many of the closest gardens make up the early haul.
  NearestCount = 6
  PanelWidth = 340
  Ink = rgba(20, 20, 20, 255)
  Parchment = rgba(250, 249, 242, 255)

type
  HouseStats = object
    index: int
    owner: string
    center: Vec2
    nearCount: int
    nearestDistance: float
    haulDistance: float
    meanDistance: float
    neighbourDistance: float
    rating: float

proc repoDir(): string =
  ## Returns the repository root.
  currentSourcePath().parentDir().parentDir()

proc drawPixelText(
  image: Image,
  font: PixelFont,
  text: string,
  x, y: int,
  ink: ColorRGBA,
  scale = 1
) =
  ## Blits one run of pixel-font text into an image.
  var
    penX = x
    penY = y
  for ch in text:
    if ch == '\n':
      penX = x
      penY += font.lineHeight() * scale
      continue
    let glyph = font.glyphAt(ch)
    for gy in 0 ..< glyph.height:
      for gx in 0 ..< glyph.width:
        if not glyph.pixels[gy * glyph.width + gx]:
          continue
        for sy in 0 ..< scale:
          for sx in 0 ..< scale:
            let
              px = penX + gx * scale + sx
              py = penY + gy * scale + sy
            if px >= 0 and py >= 0 and px < image.width and py < image.height:
              image[px, py] = ink
    penX += (glyph.width + font.spacing) * scale

proc bottomLayerIndex(sprite: AsepriteSprite): int =
  ## Returns the index of the map's bottom art layer.
  for i, layer in sprite.layers:
    if layer.name.normalize() == "bottom":
      return i
  0

proc houseCenter(rect: ResourceRect): Vec2 =
  vec2(float(rect.x) + float(rect.w) / 2, float(rect.y) + float(rect.h) / 2)

proc ratingColor(rating: float): ColorRGBA =
  ## Green for a well placed house, red for a starved one.
  let t = clamp(rating, 0.0, 1.0)
  rgba(
    uint8(230 - t * 190),
    uint8(70 + t * 130),
    uint8(70),
    255
  )

proc collectStats(
  houses: seq[(int, ResourceRect)],
  gardens: seq[Vec2],
  radius: float
): seq[HouseStats] =
  ## Measures each house against the gardens and its neighbours.
  for (index, rect) in houses:
    var
      stats = HouseStats(
        index: index,
        owner: index.playerNameForHouse(),
        center: rect.houseCenter()
      )
      distances: seq[float]
    for garden in gardens:
      distances.add(stats.center.dist(garden))
    distances.sort()
    for distance in distances:
      if distance <= radius:
        inc stats.nearCount
      stats.meanDistance += distance
    if distances.len > 0:
      stats.meanDistance = stats.meanDistance / float(distances.len)
      stats.nearestDistance = distances[0]
      let take = min(NearestCount, distances.len)
      for i in 0 ..< take:
        stats.haulDistance += distances[i]
      stats.haulDistance = stats.haulDistance / float(take)
    stats.neighbourDistance = 1e9
    for (otherIndex, otherRect) in houses:
      if otherIndex == index:
        continue
      stats.neighbourDistance = min(
        stats.neighbourDistance,
        stats.center.dist(otherRect.houseCenter())
      )
    result.add(stats)

proc applyRatings(stats: var seq[HouseStats]) =
  ## Rates each house 0..1 against the best and worst on this map.
  ## Reaching many gardens counts as much as not walking far to them,
  ## because a day's food is whatever a gnome can carry home before the
  ## plots are stripped.
  var
    mostNear = 0
    fewestNear = int.high
    shortestHaul = 1e9
    longestHaul = 0.0
  for s in stats:
    mostNear = max(mostNear, s.nearCount)
    fewestNear = min(fewestNear, s.nearCount)
    shortestHaul = min(shortestHaul, s.haulDistance)
    longestHaul = max(longestHaul, s.haulDistance)
  for s in stats.mitems:
    let
      reachSpan = float(max(mostNear - fewestNear, 1))
      haulSpan = max(longestHaul - shortestHaul, 1.0)
      reach = float(s.nearCount - fewestNear) / reachSpan
      haul = 1.0 - (s.haulDistance - shortestHaul) / haulSpan
    s.rating = (reach + haul) / 2

proc drawPanel(
  image: Image,
  font: PixelFont,
  stats: seq[HouseStats],
  radius: float,
  x: int
) =
  ## Writes the ranked table down the side panel.
  var ranked = stats
  ranked.sort(proc(a, b: HouseStats): int = cmp(b.rating, a.rating))
  var y = 18
  image.drawPixelText(font, "HOUSE BALANCE", x, y, Ink, 2)
  y += 30
  image.drawPixelText(
    font,
    &"gardens within {int(radius)}px, and the walk",
    x, y, rgba(90, 90, 90, 255), 1
  )
  y += 12
  image.drawPixelText(
    font, &"to the {NearestCount} nearest", x, y, rgba(90, 90, 90, 255), 1
  )
  y += 24
  for s in ranked:
    let bar = int(round(s.rating * 12))
    image.drawPixelText(
      font,
      &"{s.index + 1} {s.owner}",
      x, y, Ink, 2
    )
    image.drawPixelText(
      font, repeat('|', bar), x + 90, y, s.rating.ratingColor(), 2
    )
    image.drawPixelText(
      font, &"{int(round(s.rating * 100)):>3}", x + 250, y, Ink, 2
    )
    y += 18
    image.drawPixelText(
      font,
      &"{s.nearCount} near, haul {int(round(s.haulDistance))}px, " &
        &"door {int(round(s.neighbourDistance))}px",
      x + 12, y, rgba(90, 90, 90, 255), 1
    )
    y += 22

proc render(
  stats: seq[HouseStats],
  gardens: seq[Vec2],
  background: Image,
  font: PixelFont,
  radius: float,
  scale: int,
  outPath: string
) =
  ## Draws the balancing map: gardens, houses, each house linked to the
  ## gardens it reaches first, and the ranked table beside it.
  let
    scaled = float(scale)
    mapWidth = int(float(background.width) * scaled)
    mapHeight = int(float(background.height) * scaled)
    image = newImage(mapWidth + PanelWidth, max(mapHeight, 420))
  image.fill(Parchment)

  let mapImage = background.resize(mapWidth, mapHeight)
  image.draw(mapImage, translate(vec2(0, 0)))
  let veil = newImage(mapWidth, mapHeight)
  veil.fill(rgba(250, 249, 242, 165))
  image.draw(veil, translate(vec2(0, 0)))

  for s in stats:
    var distances: seq[(float, Vec2)]
    for garden in gardens:
      distances.add((float(s.center.dist(garden)), garden))
    distances.sort(proc(a, b: (float, Vec2)): int = cmp(a[0], b[0]))
    let context = newContext(image)
    context.strokeStyle = s.rating.ratingColor()
    context.lineWidth = 1.5
    for i in 0 ..< min(NearestCount, distances.len):
      context.strokeSegment(
        segment(s.center * scaled, distances[i][1] * scaled)
      )

  for s in stats:
    var nearestHouse = Vec2()
    var nearestFound = false
    for other in stats:
      if other.index == s.index:
        continue
      if not nearestFound or
          s.center.dist(other.center) < s.center.dist(nearestHouse):
        nearestHouse = other.center
        nearestFound = true
    if nearestFound:
      let context = newContext(image)
      context.strokeStyle = rgba(70, 90, 170, 120)
      context.lineWidth = 3
      context.strokeSegment(
        segment(s.center * scaled, nearestHouse * scaled)
      )

  for s in stats:
    let context = newContext(image)
    context.strokeStyle = rgba(60, 160, 60, 90)
    context.lineWidth = 1
    context.strokeCircle(circle(s.center * scaled, float(radius) * scaled))

  for garden in gardens:
    let context = newContext(image)
    context.fillStyle = rgba(60, 150, 60, 235)
    context.fillCircle(circle(garden * scaled, 4))

  for s in stats:
    let
      context = newContext(image)
      at = s.center * scaled
    context.fillStyle = s.rating.ratingColor()
    context.fillRect(rect(at - vec2(14, 14), vec2(28, 28)))
    context.strokeStyle = Ink
    context.lineWidth = 2
    context.strokeRect(rect(at - vec2(14, 14), vec2(28, 28)))
    let
      label = $(s.index + 1)
      labelScale = 2
    image.drawPixelText(
      font,
      label,
      int(at.x) - font.textWidth(label) * labelScale div 2,
      int(at.y) - font.height * labelScale div 2,
      rgba(255, 255, 255, 255),
      labelScale
    )

  image.drawPanel(font, stats, radius, mapWidth + 20)
  createDir(outPath.parentDir())
  image.writeFile(outPath)

proc reportStats(stats: seq[HouseStats], radius: float) =
  ## Prints the table the picture is drawn from.
  var ranked = stats
  ranked.sort(proc(a, b: HouseStats): int = cmp(b.rating, a.rating))
  echo &"{\"house\":>5}  {\"owner\":<7} {\"rating\":>6}  " &
    &"{\"near\":>4}  {\"closest\":>7}  {\"haul\":>6}  {\"mean\":>5}  {\"neighbour\":>9}"
  for s in ranked:
    echo &"{s.index + 1:>5}  {s.owner:<7} {int(round(s.rating * 100)):>6}  " &
      &"{s.nearCount:>4}  {int(round(s.nearestDistance)):>7}  " &
      &"{int(round(s.haulDistance)):>6}  {int(round(s.meanDistance)):>5}  " &
      &"{int(round(s.neighbourDistance)):>9}"
  let
    best = ranked[0]
    worst = ranked[^1]
  echo ""
  echo &"near   = gardens within {int(radius)}px of the door"
  echo &"haul   = mean walk to the {NearestCount} closest gardens"
  echo ""
  echo &"best placed:  house {best.index + 1} ({best.owner}) — " &
    &"{best.nearCount} gardens near, haul {int(round(best.haulDistance))}px"
  echo &"worst placed: house {worst.index + 1} ({worst.owner}) — " &
    &"{worst.nearCount} gardens near, haul {int(round(worst.haulDistance))}px"
  echo &"spread: the best door reaches " &
    &"{float(best.nearCount) / float(max(worst.nearCount, 1)):.2f}x the gardens " &
    &"and walks {worst.haulDistance / max(best.haulDistance, 1.0):.2f}x less far"
  echo ""
  echo "Seats are handed out by entrant order and never rotate, so this"
  echo "spread is a permanent handicap unless the map is levelled or the"
  echo "seating is shuffled per game."

when isMainModule:
  var
    outPath = DefaultOutPath
    scale = DefaultScale
    radius = DefaultRadius
  for kind, key, value in getopt():
    case kind
    of cmdLongOption:
      case key
      of "out": outPath = value
      of "scale": scale = max(1, parseInt(value))
      of "radius": radius = max(1.0, parseFloat(value))
      else: discard
    else: discard

  let
    dataDir = repoDir() / "data"
    rects = loadResourceRects(dataDir / "map.resource")
  var
    houses: seq[(int, ResourceRect)]
    gardens: seq[Vec2]
  for rect in rects:
    let name = rect.rectName()
    if name == "garden":
      gardens.add(vec2(
        float(rect.x) + float(rect.w) / 2,
        float(rect.y) + float(rect.h) / 2
      ))
    elif name.startsWith("house") and name.len > 5:
      try:
        houses.add((parseInt(name[5 .. ^1]) - 1, rect))
      except ValueError:
        discard
  houses.sort(proc(a, b: (int, ResourceRect)): int = cmp(a[0], b[0]))
  if houses.len == 0 or gardens.len == 0:
    quit("map.resource has no houses or gardens to measure")

  var stats = collectStats(houses, gardens, radius)
  stats.applyRatings()

  let
    mapSprite = readAseprite(dataDir / "map.aseprite")
    bottom = mapSprite.layerImage(mapSprite.bottomLayerIndex())
    font = readTiny5Font()
  render(stats, gardens, bottom, font, radius, scale, outPath)
  reportStats(stats, radius)
  echo ""
  echo &"wrote {outPath} ({gardens.len} gardens, {houses.len} houses)"
