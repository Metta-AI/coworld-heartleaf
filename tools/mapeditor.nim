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
##   G            toggle the walked routes
##   C            centre the village in the window
##
## Usage:
##   nim r tools/mapeditor.nim

import
  std/[algorithm, math, os, strformat, strutils],
  pixie, silky, pathy,
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
  ## How much of the village must stay on screen while panning, so it
  ## can never be lost off an edge entirely.
  KeepOnScreen = 90'f32
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
  ## One hue per door, so a route can be traced back to whose it is.
  HouseHues = [
    rgbx(214, 64, 52, 255),
    rgbx(232, 133, 38, 255),
    rgbx(188, 160, 28, 255),
    rgbx(96, 176, 62, 255),
    rgbx(40, 160, 140, 255),
    rgbx(58, 126, 214, 255),
    rgbx(124, 88, 196, 255),
    rgbx(198, 74, 156, 255),
    rgbx(110, 110, 110, 255)
  ]

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

  Step = tuple[x, y: int]

  HouseScore = object
    index: int
    owner: string
    gardensWon: int
    travelled: float
    rerouted: int
    ## Every position the gnome actually stood on, in order, so the
    ## drawn trail is the walk itself rather than a summary of it.
    trail: seq[Step]
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

proc toDense(steps: openArray[PathStep]): seq[Step] =
  ## Turns sparse jump points into the line a gnome actually walks, so
  ## the drawn route bends around the scenery instead of cutting corners.
  ## A dot every couple of pixels, so the walk reads as a trail rather
  ## than a dotted line.
  const DensifyPixels = 2
  for step in steps:
    let point: Step = (x: step.x, y: step.y)
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
      result.add((
        x: previous.x + dx * walked div span,
        y: previous.y + dy * walked div span
      ))
      walked += DensifyPixels
    result.add(point)

proc joinFrom(start: Step, walk: seq[Step]): seq[Step] =
  ## Puts the step out of where the gnome stands back on the front of a
  ## route, filling the gap so the trail is unbroken.
  const DensifyPixels = 2
  result.add(start)
  if walk.len > 0:
    let
      dx = walk[0].x - start.x
      dy = walk[0].y - start.y
      span = max(abs(dx), abs(dy))
    var walked = DensifyPixels
    while walked < span:
      result.add((
        x: start.x + dx * walked div span,
        y: start.y + dy * walked div span
      ))
      walked += DensifyPixels
  for point in walk:
    result.add(point)

proc walkLength(points: seq[Step]): float =
  for i in 1 ..< points.len:
    let
      dx = float(points[i].x - points[i - 1].x)
      dy = float(points[i].y - points[i - 1].y)
    result += sqrt(dx * dx + dy * dy)

proc onWalkable(nav: JumpPointSpace, x, y: int): Step =
  ## Returns the closest walkable pixel, so a door or patch sitting a
  ## pixel inside scenery still has somewhere to stand.
  var best: Step = (
    x: x.clamp(0, nav.path.width - 1),
    y: y.clamp(0, nav.path.height - 1)
  )
  if nav.path.passable(best.x, best.y):
    return best
  for radius in 1 .. 64:
    for dy in -radius .. radius:
      for dx in -radius .. radius:
        if abs(dx) != radius and abs(dy) != radius:
          continue
        let
          px = (x + dx).clamp(0, nav.path.width - 1)
          py = (y + dy).clamp(0, nav.path.height - 1)
        if nav.path.passable(px, py):
          return (x: px, y: py)
  best

proc raceForGardens(
  nav: JumpPointSpace,
  gardens: seq[Garden],
  houses: seq[House]
): seq[HouseScore] =
  ## Runs the morning a step at a time. Everyone starts at their door
  ## and walks toward the nearest patch still going; reaching it picks
  ## it up and takes it off the map. If somebody else gets there first
  ## while a gnome is still on its way, that gnome turns for the next
  ## nearest patch from wherever it happens to be standing — it never
  ## finishes a walk to a patch that is already gone.
  var
    scores: seq[HouseScore]
    standing: seq[Step]
    plots: seq[Step]
    taken: seq[bool]
    route: seq[seq[Step]]
    cursor: seq[int]
    target: seq[int]
  for house in houses:
    let door = nav.onWalkable(int(house.center.x), int(house.center.y))
    scores.add(HouseScore(
      index: house.index, owner: house.owner, trail: @[door]
    ))
    standing.add(door)
    route.add(@[])
    cursor.add(0)
    target.add(-1)
  for garden in gardens:
    let middle = garden.center()
    plots.add(nav.onWalkable(int(middle.x), int(middle.y)))
    taken.add(false)
  if scores.len == 0 or plots.len == 0:
    return scores

  proc aimAtNearest(racer: int) =
    ## Points one gnome at the nearest patch still on the map, starting
    ## from exactly where it stands.
    var
      bestPlot = -1
      bestRoute: seq[Step]
      bestLength = 0.0
    for i, plot in plots:
      if taken[i]:
        continue
      var walk = nav.findPath(
        standing[racer].x, standing[racer].y, plot.x, plot.y
      ).toDense()
      if walk.len == 0:
        continue
      if walk[0] != standing[racer]:
        walk = joinFrom(standing[racer], walk)
      let length = walk.walkLength()
      if bestPlot < 0 or length < bestLength:
        bestPlot = i
        bestRoute = walk
        bestLength = length
    target[racer] = bestPlot
    route[racer] = bestRoute
    cursor[racer] = 0

  var
    remaining = plots.len
    guard = 0
  while remaining > 0 and guard < 400_000:
    inc guard

    for racer in 0 ..< scores.len:
      if target[racer] < 0:
        aimAtNearest(racer)

    var moved = false
    for racer in 0 ..< scores.len:
      if target[racer] < 0 or route[racer].len == 0:
        continue
      moved = true
      if cursor[racer] < route[racer].high:
        inc cursor[racer]
        let step = route[racer][cursor[racer]]
        let
          dx = float(step.x - standing[racer].x)
          dy = float(step.y - standing[racer].y)
        scores[racer].travelled += sqrt(dx * dx + dy * dy)
        standing[racer] = step
        scores[racer].trail.add(step)
      if cursor[racer] >= route[racer].high:
        # Arrived. The patch is ours if nobody beat us to it this tick.
        if not taken[target[racer]]:
          taken[target[racer]] = true
          inc scores[racer].gardensWon
          dec remaining
        target[racer] = -1

    # Anyone still walking toward a patch that has just gone turns for
    # the next nearest one from where they stand.
    for racer in 0 ..< scores.len:
      if target[racer] >= 0 and taken[target[racer]]:
        target[racer] = -1
        inc scores[racer].rerouted

    if not moved:
      break

  var mostWon = 1
  for score in scores:
    mostWon = max(mostWon, score.gardensWon)
  for score in scores.mitems:
    score.rating = score.gardensWon / mostWon
  scores

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

  let walkIndex = block:
    var found = -1
    for i, layer in mapSprite.layers:
      if layer.name.normalize() in ["walkable", "walk"]:
        found = i
    found
  if walkIndex < 0:
    quit("map.aseprite has no walkable layer to walk around")
  let walkImage = mapSprite.layerImage(walkIndex)
  var walkMask = newSeq[bool](walkImage.width * walkImage.height)
  for y in 0 ..< walkImage.height:
    for x in 0 ..< walkImage.width:
      walkMask[y * walkImage.width + x] = walkImage[x, y].a > 0
  let nav = newJumpPointSpace(
    walkMask, walkImage.width, walkImage.height, DiagonalPath
  )

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
    scores: seq[HouseScore]

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

  proc rerace() =
    ## Runs the morning again after the map changes, so both the
    ## standings and the drawn trails match where the plots are now.
    scores = nav.raceForGardens(gardens, houses)
    echo ""
    echo "house  owner    won   walked  turned"
    for score in scores:
      echo &"{score.index + 1:>5}  {score.owner:<7} {score.gardensWon:>4}  " &
        &"{int(score.travelled):>7}  {score.rerouted:>6}"

  rerace()

  proc reload() =
    doc = loadDoc()
    (gardens, houses) = collectPieces(doc)
    dragging = -1
    rerace()
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
      # The view may go anywhere, including past the edges, so a map
      # smaller than the window can sit in the middle of it instead of
      # being stuck against the top-left corner. The only limit is that
      # a corner of the village has to stay on screen, so it can always
      # be dragged back into view.
      let
        artWidth = float32(mapWidth) * zoom()
        artHeight = float32(mapHeight) * zoom()
      view.x = clamp(
        view.x, KeepOnScreen - float32(viewWidth), artWidth - KeepOnScreen
      )
      view.y = clamp(
        view.y, KeepOnScreen - float32(viewHeight), artHeight - KeepOnScreen
      )
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
      rerace()
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
    if window.buttonPressed[KeyC]:
      # Put the village back in the middle of whatever window it is in.
      view = vec2(
        (float32(mapWidth) * zoom() - float32(viewWidth)) / 2,
        (float32(mapHeight) * zoom() - float32(viewHeight)) / 2
      )
      status = "centred"


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
          # The walk itself: every position the gnome stood on, in its
          # door's colour, dark-edged so it reads over grass and hedge.
          for scoreIndex, score in scores:
            let hue = HouseHues[score.index mod HouseHues.len]
            var step = 0
            while step < score.trail.len:
              let at = toScreen(vec2(
                float32(score.trail[step].x), float32(score.trail[step].y)
              ))
              rectangle "edge" & $scoreIndex & "_" & $step:
                box at.x - 2.5, at.y - 2.5, 5, 5
                tint rgbx(0, 0, 0, 190)
              rectangle "step" & $scoreIndex & "_" & $step:
                box at.x - 1.5, at.y - 1.5, 3, 3
                tint hue
              step += 1

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
          characters "Patches won"
        text "subtitle":
          box 18, 44, PanelWidth - 36, 18
          tint FadedInk
          characters "all nine walk at once, nearest patch first"

        var ranked = scores
        ranked.sort(proc(a, b: HouseScore): int = cmp(b.gardensWon, a.gardensWon))
        for row, s in ranked:
          let y = 74 + row * RowHeight
          text "name" & $row:
            box 18, y, 120, 18
            tint Ink
            characters &"{s.index + 1}  {s.owner}"
          rectangle "bar" & $row:
            box 140, y + 4, 118 * s.rating, 10
            tint HouseHues[s.index mod HouseHues.len]
          text "value" & $row:
            box 268, y, 54, 18
            tint Ink
            characters $s.gardensWon
          text "detail" & $row:
            box 26, y + 18, PanelWidth - 44, 16
            tint FadedInk
            characters &"walked {int(round(s.travelled))}px, " &
              &"{s.rerouted} turned back"

        let
          best = ranked[0]
          worst = ranked[^1]
          spread =
            if worst.gardensWon > 0:
              best.gardensWon / worst.gardensWon
            else:
              0.0
        text "spread":
          box 18, 74 + ranked.len * RowHeight + 10, PanelWidth - 36, 18
          tint Ink
          characters &"spread {spread:.2f}x  even would be " &
            &"{gardens.len div max(houses.len, 1)} each"
        text "status":
          box 18, 74 + ranked.len * RowHeight + 32, PanelWidth - 36, 18
          tint rgbx(70, 90, 170, 255)
          characters status

    sk.endUi()
    window.swapBuffers()

  while not window.closeRequested:
    pollEvents()
