## Drag the gardens around and watch the house balance change.
##
## Seats never rotate, so whichever house an entrant is given is the one
## it farms for its whole career — and the houses are not equally fed.
## Moving a garden always takes from one door to give to another, which
## is hard to judge by eye, so this shows the whole village at once:
## every garden joined to the house nearest it, and a live table of what
## each door can reach. Drag a garden, watch the table move, press S to
## write the map back.
##
## Controls:
##   drag         move the garden under the cursor
##   S            save data/map.resource in place
##   R            reload from disk, discarding changes
##   G            toggle the garden-to-house lines
##
## Usage:
##   nim r -d:useCpu tools/mapeditor.nim
##   nim r -d:useCpu tools/mapeditor.nim --shot:balance.png
##
## The window is drawn on the CPU with Pixie and handed to Windy as a
## finished image, which Windy only accepts in its CPU mode — without
## that define the window comes up empty. `--shot` renders one frame to
## a file and exits, which needs no window at all.

when not defined(useCpu):
  {.error: "Build the map editor with -d:useCpu: it draws with Pixie " &
    "and presents the finished image, which Windy only does in CPU mode.".}

import
  std/[algorithm, math, os, parseopt, strformat, strutils],
  pixie, windy,
  bitworld/[aseprite, pixelfonts, resources],
  ../src/heartleaf/protocol

const
  PanelWidth = 330
  ## What counts as within reach of a door. Every plot is stripped in
  ## the first two hours, so this is roughly what a gnome can take
  ## before the rush reaches it.
  NearRadius = 200.0
  ## How many of the closest gardens make up a day's haul.
  NearestCount = 6
  GrabRadius = 14.0
  Ink = rgba(25, 25, 25, 255)
  Parchment = rgba(250, 249, 242, 255)

type
  Garden = object
    ## One draggable plot. blockIndex points back at the block it came
    ## from in map.resource so it can be written to the same place.
    blockIndex: int
    pos: Vec2
    size: Vec2

  House = object
    index: int
    owner: string
    center: Vec2

  HouseScore = object
    index: int
    owner: string
    nearCount: int
    haulDistance: float
    rating: float

  MapDoc = object
    ## The resource file split on its block comments, kept verbatim so
    ## saving only rewrites the coordinates that actually moved.
    segments: seq[string]
    names: seq[string]

proc repoDir(): string =
  currentSourcePath().parentDir().parentDir()

proc resourcePath(): string =
  repoDir() / "data" / "map.resource"

proc splitBlocks(text: string): MapDoc =
  ## Splits a resource file into a leading segment plus one segment per
  ## named block, preserving every byte.
  var
    index = 0
    lastCut = 0
  result.names.add("")
  while true:
    let open = text.find("/*", index)
    if open < 0:
      break
    let close = text.find("*/", open)
    if close < 0:
      break
    result.segments.add(text[lastCut ..< open])
    result.names.add(text[open + 2 ..< close].strip())
    lastCut = close + 2
    index = close + 2
  result.segments.add(text[lastCut .. ^1])

proc readIntProperty(segment: string, key: string): int =
  ## Reads "key: <n>px;" out of one block segment, or -1.
  result = -1
  let at = segment.find(key & ":")
  if at < 0:
    return
  var i = at + key.len + 1
  while i < segment.len and segment[i] in {' ', '\t'}:
    inc i
  var digits = ""
  if i < segment.len and segment[i] == '-':
    digits.add('-')
    inc i
  while i < segment.len and segment[i].isDigit():
    digits.add(segment[i])
    inc i
  if digits.len == 0 or digits == "-":
    return
  try:
    result = parseInt(digits)
  except ValueError:
    result = -1

proc writeIntProperty(segment: var string, key: string, value: int) =
  ## Rewrites "key: <n>px;" in place, leaving the rest of the block
  ## exactly as it was.
  let at = segment.find(key & ":")
  if at < 0:
    return
  var i = at + key.len + 1
  while i < segment.len and segment[i] in {' ', '\t'}:
    inc i
  var stop = i
  if stop < segment.len and segment[stop] == '-':
    inc stop
  while stop < segment.len and segment[stop].isDigit():
    inc stop
  segment = segment[0 ..< i] & $value & segment[stop .. ^1]

proc loadDoc(): MapDoc =
  splitBlocks(readFile(resourcePath()))

proc collectPieces(doc: MapDoc): (seq[Garden], seq[House]) =
  ## Pulls the gardens and houses out of the parsed document.
  var
    gardens: seq[Garden]
    houses: seq[House]
  for i in 1 ..< doc.names.len:
    let
      name = doc.names[i]
      segment = doc.segments[i]
      left = segment.readIntProperty("left")
      top = segment.readIntProperty("top")
      width = segment.readIntProperty("width")
      height = segment.readIntProperty("height")
    if left < 0 or top < 0:
      continue
    if name == "garden":
      gardens.add(Garden(
        blockIndex: i,
        pos: vec2(float(left), float(top)),
        size: vec2(float(max(width, 1)), float(max(height, 1)))
      ))
    elif name.startsWith("house") and name.len > 5:
      try:
        let index = parseInt(name[5 .. ^1]) - 1
        houses.add(House(
          index: index,
          owner: index.playerNameForHouse(),
          center: vec2(
            float(left) + float(max(width, 1)) / 2,
            float(top) + float(max(height, 1)) / 2
          )
        ))
      except ValueError:
        discard
  houses.sort(proc(a, b: House): int = cmp(a.index, b.index))
  (gardens, houses)

proc center(garden: Garden): Vec2 =
  garden.pos + garden.size / 2

proc nearestHouse(houses: seq[House], at: Vec2): int =
  ## Returns the index into houses of the closest door.
  result = -1
  var best = 1e9
  for i, house in houses:
    let distance = float(house.center.dist(at))
    if distance < best:
      best = distance
      result = i

proc scoreHouses(gardens: seq[Garden], houses: seq[House]): seq[HouseScore] =
  ## Rates every door on what it can reach, relative to the rest.
  for house in houses:
    var
      score = HouseScore(index: house.index, owner: house.owner)
      distances: seq[float]
    for garden in gardens:
      distances.add(float(house.center.dist(garden.center())))
    distances.sort()
    for distance in distances:
      if distance <= NearRadius:
        inc score.nearCount
    let take = min(NearestCount, distances.len)
    for i in 0 ..< take:
      score.haulDistance += distances[i]
    if take > 0:
      score.haulDistance = score.haulDistance / float(take)
    result.add(score)

  var
    mostNear = 0
    fewestNear = int.high
    shortestHaul = 1e9
    longestHaul = 0.0
  for s in result:
    mostNear = max(mostNear, s.nearCount)
    fewestNear = min(fewestNear, s.nearCount)
    shortestHaul = min(shortestHaul, s.haulDistance)
    longestHaul = max(longestHaul, s.haulDistance)
  for s in result.mitems:
    let
      reachSpan = float(max(mostNear - fewestNear, 1))
      haulSpan = max(longestHaul - shortestHaul, 1.0)
      reach = float(s.nearCount - fewestNear) / reachSpan
      haul = 1.0 - (s.haulDistance - shortestHaul) / haulSpan
    s.rating = (reach + haul) / 2

proc ratingColor(rating: float): ColorRGBA =
  let t = clamp(rating, 0.0, 1.0)
  rgba(uint8(230 - t * 190), uint8(70 + t * 130), 70, 255)

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
  for i, layer in sprite.layers:
    if layer.name.normalize() == "bottom":
      return i
  0

when isMainModule:
  var shotPath = ""
  for kind, key, value in getopt():
    if kind == cmdLongOption and key == "shot":
      shotPath = value

  var doc = loadDoc()
  var (gardens, houses) = collectPieces(doc)
  if gardens.len == 0 or houses.len == 0:
    quit("map.resource has no gardens or houses to edit")

  let
    mapSprite = readAseprite(repoDir() / "data" / "map.aseprite")
    background = mapSprite.layerImage(mapSprite.bottomLayerIndex())
    font = readTiny5Font()

  # Fit the map to something that comfortably fits a screen.
  var scale = 1.0
  while float(background.height) * scale > 900:
    scale -= 0.1
  scale = max(scale, 0.3)

  let
    mapWidth = int(float(background.width) * scale)
    mapHeight = int(float(background.height) * scale)
    windowWidth = mapWidth + PanelWidth
    windowHeight = max(mapHeight, 520)
    scaledMap = background.resize(mapWidth, mapHeight)

  let window =
    if shotPath.len > 0:
      nil
    else:
      newWindow(
        "Heartleaf map editor",
        ivec2(int32(windowWidth), int32(windowHeight))
      )

  var
    dragging = -1
    dragOffset = vec2(0, 0)
    showLines = true
    status = "drag a garden, S saves, R reloads"
    frame = newImage(windowWidth, windowHeight)

  proc toMap(screen: Vec2): Vec2 =
    screen / scale

  proc toScreen(mapPoint: Vec2): Vec2 =
    mapPoint * scale

  proc save() =
    ## Writes every garden's current position back into its own block.
    for garden in gardens:
      doc.segments[garden.blockIndex].writeIntProperty(
        "left", int(round(garden.pos.x))
      )
      doc.segments[garden.blockIndex].writeIntProperty(
        "top", int(round(garden.pos.y))
      )
    var rebuilt = ""
    for i, segment in doc.segments:
      if i > 0:
        rebuilt.add("/* " & doc.names[i] & " */")
      rebuilt.add(segment)
    writeFile(resourcePath(), rebuilt)
    status = &"saved {gardens.len} gardens to data/map.resource"

  proc reload() =
    doc = loadDoc()
    (gardens, houses) = collectPieces(doc)
    status = "reloaded from disk"

  proc composeFrame() =
    frame.fill(Parchment)
    frame.draw(scaledMap, translate(vec2(0, 0)))
    let veil = newImage(mapWidth, mapHeight)
    veil.fill(rgba(250, 249, 242, 150))
    frame.draw(veil, translate(vec2(0, 0)))

    let scores = scoreHouses(gardens, houses)

    if showLines:
      for garden in gardens:
        let nearest = houses.nearestHouse(garden.center())
        if nearest < 0:
          continue
        let context = newContext(frame)
        context.strokeStyle = scores[nearest].rating.ratingColor()
        context.lineWidth = 1.5
        context.strokeSegment(segment(
          garden.center().toScreen(), houses[nearest].center.toScreen()
        ))

    for i, garden in gardens:
      let context = newContext(frame)
      context.fillStyle =
        if i == dragging:
          rgba(255, 210, 60, 255)
        else:
          rgba(60, 150, 60, 235)
      context.fillCircle(circle(garden.center().toScreen(), 5))

    for i, house in houses:
      let
        context = newContext(frame)
        at = house.center.toScreen()
      context.fillStyle = scores[i].rating.ratingColor()
      context.fillRect(rect(at - vec2(13, 13), vec2(26, 26)))
      context.strokeStyle = Ink
      context.lineWidth = 2
      context.strokeRect(rect(at - vec2(13, 13), vec2(26, 26)))
      let label = $(house.index + 1)
      frame.drawPixelText(
        font,
        label,
        int(at.x) - font.textWidth(label),
        int(at.y) - font.height,
        rgba(255, 255, 255, 255),
        2
      )

    var ranked = scores
    ranked.sort(proc(a, b: HouseScore): int = cmp(b.rating, a.rating))
    var y = 16
    frame.drawPixelText(font, "HOUSE BALANCE", mapWidth + 16, y, Ink, 2)
    y += 26
    frame.drawPixelText(
      font,
      &"within {int(NearRadius)}px, walk to {NearestCount}",
      mapWidth + 16, y, rgba(95, 95, 95, 255), 1
    )
    y += 22
    for s in ranked:
      frame.drawPixelText(
        font, &"{s.index + 1} {s.owner}", mapWidth + 16, y, Ink, 2
      )
      frame.drawPixelText(
        font,
        repeat('|', int(round(s.rating * 12))),
        mapWidth + 110, y, s.rating.ratingColor(), 2
      )
      frame.drawPixelText(
        font, &"{int(round(s.rating * 100)):>3}", mapWidth + 262, y, Ink, 2
      )
      y += 16
      frame.drawPixelText(
        font,
        &"{s.nearCount} near, haul {int(round(s.haulDistance))}px",
        mapWidth + 28, y, rgba(95, 95, 95, 255), 1
      )
      y += 20

    y += 8
    let
      best = ranked[0]
      worst = ranked[^1]
      spread =
        if worst.nearCount > 0:
          float(best.nearCount) / float(worst.nearCount)
        else:
          0.0
    frame.drawPixelText(
      font, &"spread {spread:.2f}x gardens", mapWidth + 16, y, Ink, 1
    )
    y += 14
    frame.drawPixelText(
      font,
      &"best {best.index + 1}, worst {worst.index + 1}",
      mapWidth + 16, y, Ink, 1
    )
    y += 22
    frame.drawPixelText(font, status, mapWidth + 16, y, rgba(70, 90, 170, 255), 1)

  if shotPath.len > 0:
    composeFrame()
    createDir(shotPath.parentDir())
    frame.writeFile(shotPath)
    echo "wrote ", shotPath
    quit(0)

  window.onFrame = proc() =
    let mouse = window.mousePos.vec2

    if window.buttonPressed[MouseLeft] and mouse.x < float(mapWidth):
      let atMap = mouse.toMap()
      var
        best = -1
        bestDistance = GrabRadius / scale
      for i, garden in gardens:
        let distance = float(garden.center().dist(atMap))
        if distance <= bestDistance:
          bestDistance = distance
          best = i
      if best >= 0:
        dragging = best
        dragOffset = gardens[best].pos - atMap
        status = "moving a garden"

    if window.buttonDown[MouseLeft] and dragging >= 0:
      gardens[dragging].pos = mouse.toMap() + dragOffset
    elif dragging >= 0:
      dragging = -1
      status = "moved — press S to save"

    if window.buttonPressed[KeyS]:
      save()
    if window.buttonPressed[KeyR]:
      reload()
    if window.buttonPressed[KeyG]:
      showLines = not showLines

    composeFrame()
    window.presentPixels(frame)

  while not window.closeRequested:
    pollEvents()
