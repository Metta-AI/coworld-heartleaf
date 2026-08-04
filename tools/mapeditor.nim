## Drag the gardens around and watch the house balance change.
##
## Seats never rotate, so whichever house an entrant is given is the one
## it farms for its whole career — and the houses are not equally fed.
## Moving a plot always takes from one door to give to another, which is
## hard to judge by eye, so this shows the whole village at once: every
## garden joined to the house nearest it, and a live table of what each
## door can reach. Drag a garden, watch the table move, press S to write
## the map back.
##
## Drawing runs on the GPU through Silky. The texture atlas is built at
## startup out of `tools/theme`, `tools/fonts` and the map art itself,
## so there is no generated atlas to keep in the repository.
##
## Controls:
##   drag         pick up the garden under the cursor and move it
##   drag empty   pan the village; the window can be resized freely
##   scroll       zoom about the cursor
##   arrow keys   nudge the held garden a pixel at a time
##   S            save data/map.resource in place
##   R            reload from disk, discarding changes
##   G            toggle the garden-to-house lines
##
## Usage:
##   nim r tools/mapeditor.nim

import
  std/[algorithm, math, os, strformat, strutils],
  pixie, silky,
  bitworld/[aseprite, resources],
  ../src/heartleaf/protocol

const
  PanelWidth = 340
  ## What counts as within reach of a door. Every plot is stripped in
  ## the first two hours, so this is roughly what a gnome can take
  ## before the rush reaches it.
  NearRadius = 200.0
  ## How many of the closest gardens make up a day's haul.
  NearestCount = 6
  GrabRadius = 12.0
  MapName = "heartleafmap"
  ## An atlas entry is drawn at the size it was packed, so every zoom
  ## step is packed separately at startup and zooming picks an entry
  ## rather than rebuilding the atlas.
  ZoomLevels = [
    0.5'f32, 0.7'f32, 1.0'f32, 1.4'f32, 2.0'f32, 2.8'f32, 4.0'f32
  ]
  DefaultZoom = 2
  ## Scroll travel needed before the view steps a level. A notch of a
  ## wheel reports about one, and a trackpad reports fractions, so this
  ## keeps both from racing through the range.
  ZoomScrollStep = 2.5'f32
  AtlasSize = 6144
  LineStep = 10.0
  GardenSize = 9.0
  HouseSize = 26.0
  RowHeight = 40
  ## Tints are premultiplied, so a translucent wash has to carry its
  ## colour already scaled by the alpha or it renders opaque.
  VeilAlpha = 140
  VeilTint = rgbx(
    uint8(250 * VeilAlpha div 255),
    uint8(249 * VeilAlpha div 255),
    uint8(242 * VeilAlpha div 255),
    VeilAlpha
  )
  Ink = rgbx(35, 35, 35, 255)
  FadedInk = rgbx(105, 105, 105, 255)
  Paper = rgbx(250, 249, 242, 255)

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

proc toolsDir(): string =
  currentSourcePath().parentDir()

proc repoDir(): string =
  toolsDir().parentDir()

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
        pos: vec2(float32(left), float32(top)),
        size: vec2(float32(max(width, 1)), float32(max(height, 1)))
      ))
    elif name.startsWith("house") and name.len > 5:
      try:
        let index = parseInt(name[5 .. ^1]) - 1
        houses.add(House(
          index: index,
          owner: index.playerNameForHouse(),
          center: vec2(
            float32(left) + float32(max(width, 1)) / 2,
            float32(top) + float32(max(height, 1)) / 2
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
  var best = 1e9'f32
  for i, house in houses:
    let distance = house.center.dist(at)
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

proc ratingTint(rating: float): ColorRGBX =
  ## Green for a well fed door, red for a starved one.
  let t = clamp(rating, 0.0, 1.0)
  rgbx(uint8(230 - t * 190), uint8(70 + t * 130), 70, 255)

proc bottomLayerIndex(sprite: AsepriteSprite): int =
  for i, layer in sprite.layers:
    if layer.name.normalize() == "bottom":
      return i
  0

when isMainModule:
  var doc = loadDoc()
  var (gardens, houses) = collectPieces(doc)
  if gardens.len == 0 or houses.len == 0:
    quit("map.resource has no gardens or houses to edit")

  let
    mapSprite = readAseprite(repoDir() / "data" / "map.aseprite")
    mapImage = mapSprite.layerImage(mapSprite.bottomLayerIndex())

  let
    mapWidth = mapImage.width
    mapHeight = mapImage.height
    windowWidth = min(mapWidth + PanelWidth, 1500)
    windowHeight = min(mapHeight, 1000)

  # Bake the atlas at startup: theme, font and the map art itself, so
  # nothing generated has to live in the repository.
  let
    atlasPath = getTempDir() / "heartleaf-mapeditor-atlas.png"
    fontPath = toolsDir() / "fonts" / "IBMPlexSans-Regular.ttf"
    themeDir = toolsDir() / "theme"
    builder = newAtlasBuilder(AtlasSize, 4)
  builder.addDir(themeDir & "/", themeDir & "/")
  builder.addFont(fontPath, "Default", 15.0)
  builder.addFont(fontPath, "H1", 22.0)
  # Pack the art once per zoom step. A level that will not fit is
  # dropped rather than fatal, so the tool still opens on a small atlas.
  ## Largest first: the packer places blocks in the order it is given
  ## them, and the biggest one cannot find a gap once the small ones
  ## have been scattered across the sheet.
  var zoomAvailable: array[ZoomLevels.len, bool]
  for i in countdown(ZoomLevels.high, 0):
    let
      level = ZoomLevels[i]
      packed = mapImage.resize(
        int(float32(mapImage.width) * level),
        int(float32(mapImage.height) * level)
      )
    zoomAvailable[i] = builder.addImage(MapName & $i, packed)
    if not zoomAvailable[i]:
      echo "zoom ", level, "x does not fit the atlas; that step is disabled"
  if not zoomAvailable[DefaultZoom]:
    quit("the map art does not fit the atlas; raise AtlasSize")
  builder.write(atlasPath)

  let window = newWindow(
    "Heartleaf map editor",
    ivec2(int32(windowWidth), int32(windowHeight)),
    vsync = true
  )
  makeContextCurrent(window)
  loadExtensions()
  let sk = newSilky(window, atlasPath)

  var
    dragging = -1
    hovered = -1
    dragOffset = vec2(0, 0)
    showLines = true
    ## Top-left map pixel currently shown at the top-left of the view.
    view = vec2(0, 0)
    zoomIndex = DefaultZoom
    ## Scroll travel banked since the last step, so a step needs a
    ## deliberate roll rather than a twitch.
    zoomScroll = 0'f32
    panning = false
    panFrom = vec2(0, 0)
    panView = vec2(0, 0)
    status = "drag a garden, drag the ground to pan — S saves, R reloads"

  proc zoom(): float32 =
    ZoomLevels[zoomIndex]

  proc toScreen(mapPoint: Vec2): Vec2 =
    mapPoint * zoom() - view

  proc toMap(screen: Vec2): Vec2 =
    (screen + view) / zoom()

  proc save() =
    ## Writes every garden's position back into its own block, leaving
    ## every other byte of the file alone.
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
    dragging = -1
    status = "reloaded from disk"

  proc pickGarden(at: Vec2): int =
    ## Returns the garden nearest a map-space point, within reach. The
    ## grab radius is in screen pixels, so it stays the same size to the
    ## hand however far the view is zoomed.
    result = -1
    var best = GrabRadius / zoom()
    for i, garden in gardens:
      let distance = garden.center().dist(at)
      if distance <= best:
        best = distance
        result = i

  window.onFrame = proc() =
    # The window is resizable, so the layout is measured every frame:
    # the panel keeps to the right edge and the view takes the rest.
    let
      viewWidth = max(window.size.x.int - PanelWidth, 200)
      viewHeight = max(window.size.y.int, 200)
      mouse = window.mousePos.vec2
      overMap = mouse.x < float32(viewWidth)
      atMap = toMap(mouse)

    # Keep the village within reach of the view, so panning cannot
    # strand it off screen when the window changes size.
    proc clampView() =
      let
        maxX = max(float32(mapWidth) * zoom() - float32(viewWidth), 0'f32)
        maxY = max(float32(mapHeight) * zoom() - float32(viewHeight), 0'f32)
      view.x = clamp(view.x, 0'f32, maxX)
      view.y = clamp(view.y, 0'f32, maxY)
    clampView()

    # Zoom about the cursor: whatever map point is under the pointer
    # stays under it, which is what makes scrolling feel anchored.
    if overMap and window.scrollDelta.y != 0:
      zoomScroll += window.scrollDelta.y
    elif window.scrollDelta.y == 0 and abs(zoomScroll) < ZoomScrollStep:
      # Let a half-finished roll decay so it does not bank forever.
      zoomScroll = zoomScroll * 0.92'f32

    if overMap and abs(zoomScroll) >= ZoomScrollStep:
      let
        held = toMap(mouse)
        stepUp = zoomScroll > 0
      zoomScroll = 0
      var wanted =
        if stepUp:
          min(zoomIndex + 1, ZoomLevels.high)
        else:
          max(zoomIndex - 1, 0)
      while wanted != zoomIndex and not zoomAvailable[wanted]:
        if stepUp:
          inc wanted
        else:
          dec wanted
        if wanted < 0 or wanted > ZoomLevels.high:
          wanted = zoomIndex
      if wanted != zoomIndex:
        zoomIndex = wanted
        view = held * zoom() - mouse
        clampView()
        status = &"zoom {zoom():.2f}x"


    hovered =
      if overMap:
        pickGarden(atMap)
      else:
        -1

    if window.buttonPressed[MouseLeft] and overMap:
      let picked = pickGarden(atMap)
      if picked >= 0:
        dragging = picked
        dragOffset = gardens[picked].pos - atMap
        status = "moving a garden"
      else:
        # Nothing under the cursor, so the drag moves the view instead.
        panning = true
        panFrom = mouse
        panView = view

    if panning:
      if window.buttonDown[MouseLeft]:
        view = panView - (mouse - panFrom)
        clampView()
      else:
        panning = false
    if window.buttonDown[MouseLeft] and dragging >= 0:
      gardens[dragging].pos = atMap + dragOffset
    elif dragging >= 0:
      gardens[dragging].pos = vec2(
        round(gardens[dragging].pos.x), round(gardens[dragging].pos.y)
      )
      dragging = -1
      status = "moved — press S to save"

    if dragging >= 0:
      if window.buttonPressed[KeyLeft]:
        gardens[dragging].pos.x = gardens[dragging].pos.x - 1
      if window.buttonPressed[KeyRight]:
        gardens[dragging].pos.x = gardens[dragging].pos.x + 1
      if window.buttonPressed[KeyUp]:
        gardens[dragging].pos.y = gardens[dragging].pos.y - 1
      if window.buttonPressed[KeyDown]:
        gardens[dragging].pos.y = gardens[dragging].pos.y + 1

    if window.buttonPressed[KeyS]:
      save()
    if window.buttonPressed[KeyR]:
      reload()
    if window.buttonPressed[KeyG]:
      showLines = not showLines

    let scores = scoreHouses(gardens, houses)

    sk.beginUi(window, window.size)
    ui:
      # Everything to do with the village lives inside the viewport, so
      # it is clipped to the view and moves with the pan rather than
      # spilling under the panel.
      rectangle "viewport":
        box 0, 0, viewWidth, viewHeight
        tint Paper
        clipContent true

        let
          artWidth = float32(mapWidth) * zoom()
          artHeight = float32(mapHeight) * zoom()

        rectangle "map":
          box -view.x, -view.y, artWidth, artHeight
          image MapName & $zoomIndex

        rectangle "veil":
          box -view.x, -view.y, artWidth, artHeight
          tint VeilTint

        if showLines:
          for gardenIndex, garden in gardens:
            let nearest = houses.nearestHouse(garden.center())
            if nearest < 0:
              continue
            let
              fromPoint = garden.center().toScreen()
              toPoint = houses[nearest].center.toScreen()
              span = toPoint - fromPoint
              steps = max(int(span.length / LineStep), 1)
              shade = scores[nearest].rating.ratingTint()
            for step in 1 ..< steps:
              let at = fromPoint + span * (float32(step) / float32(steps))
              rectangle "line" & $gardenIndex & "_" & $step:
                box at.x - 1.5, at.y - 1.5, 3, 3
                tint shade

        for gardenIndex, garden in gardens:
          let at = garden.center().toScreen()
          rectangle "garden" & $gardenIndex:
            box at.x - GardenSize / 2, at.y - GardenSize / 2,
              GardenSize, GardenSize
            if gardenIndex == dragging:
              tint rgbx(255, 210, 60, 255)
            elif gardenIndex == hovered:
              tint rgbx(150, 235, 130, 255)
            else:
              tint rgbx(60, 150, 60, 235)

        for houseIndex, house in houses:
          let at = house.center.toScreen()
          rectangle "house" & $houseIndex:
            box at.x - HouseSize / 2, at.y - HouseSize / 2, HouseSize, HouseSize
            tint scores[houseIndex].rating.ratingTint()
            text "houselabel" & $houseIndex:
              box 0, 5, HouseSize, 18
              tint rgbx(255, 255, 255, 255)
              characters $(house.index + 1)

      rectangle "panel":
        box viewWidth, 0, PanelWidth, viewHeight
        tint Paper

        text "title":
          box 18, 14, PanelWidth - 36, 26
          font "H1"
          tint Ink
          characters "House balance"
        text "subtitle":
          box 18, 44, PanelWidth - 36, 18
          tint FadedInk
          characters &"within {int(NearRadius)}px, walk to {NearestCount}"

        var ranked = scores
        ranked.sort(proc(a, b: HouseScore): int = cmp(b.rating, a.rating))
        for row, s in ranked:
          let y = 74 + row * RowHeight
          text "name" & $row:
            box 18, y, 120, 18
            tint Ink
            characters &"{s.index + 1}  {s.owner}"
          rectangle "bar" & $row:
            box 140, y + 4, 118 * s.rating, 10
            tint s.rating.ratingTint()
          text "value" & $row:
            box 268, y, 54, 18
            tint Ink
            characters $int(round(s.rating * 100))
          text "detail" & $row:
            box 26, y + 18, PanelWidth - 44, 16
            tint FadedInk
            characters &"{s.nearCount} near, haul " &
              &"{int(round(s.haulDistance))}px"

        let
          best = ranked[0]
          worst = ranked[^1]
          spread =
            if worst.nearCount > 0:
              float(best.nearCount) / float(worst.nearCount)
            else:
              0.0
        text "spread":
          box 18, 74 + ranked.len * RowHeight + 10, PanelWidth - 36, 18
          tint Ink
          characters &"spread {spread:.2f}x  best {best.index + 1}, " &
            &"worst {worst.index + 1}"
        text "status":
          box 18, 74 + ranked.len * RowHeight + 32, PanelWidth - 36, 18
          tint rgbx(70, 90, 170, 255)
          characters status

    sk.endUi()
    window.swapBuffers()

  while not window.closeRequested:
    pollEvents()
