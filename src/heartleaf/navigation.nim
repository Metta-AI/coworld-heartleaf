## Pathfinding for the villager brains: jump point search over the walk
## masks the simulation already has, plus the helpers that pick walkable
## spots inside, outside, or near a rectangle.

import std/[algorithm, math], pathy, heartleaf/[common, observation]

const
  PathDensifyPixels = 4

type
  Navigation* = ref object
    main*: JumpPointSpace
    home*: JumpPointSpace

proc newNavigation*(
  mainMask: seq[bool],
  mainWidth, mainHeight: int,
  homeMask: seq[bool],
  homeWidth, homeHeight: int
): Navigation =
  ## Builds the two navigation spaces from walk masks.
  Navigation(
    main: newJumpPointSpace(mainMask, mainWidth, mainHeight, DiagonalPath),
    home: newJumpPointSpace(homeMask, homeWidth, homeHeight, DiagonalPath)
  )

proc spaceFor*(navigation: Navigation, scene: Scene): JumpPointSpace =
  ## The navigation space for one scene, nil during overlays.
  if navigation == nil:
    return nil
  case scene
  of Outdoors: navigation.main
  of Indoors: navigation.home
  of Overlay: nil

proc nearestPassablePoint*(space: JumpPointSpace, x, y: int): Point =
  ## The nearest walkable foot pixel to a position.
  result = Point(
    x: x.clamp(0, space.path.width - 1),
    y: y.clamp(0, space.path.height - 1)
  )
  if space.path.passable(result.x, result.y):
    return
  let step = space.path.nearestPassable(
    result.x,
    result.y,
    max(space.path.width, space.path.height)
  )
  if step.found:
    result = Point(x: step.x, y: step.y)

proc nearestPointInside*(space: JumpPointSpace, rect: Rect, x, y: int): Point =
  ## The nearest walkable foot pixel inside one rectangle.
  result = rect.center()
  if space == nil:
    return
  var bestDistance = high(int)
  for py in max(0, rect.y) ..< min(space.path.height, rect.y + rect.h):
    for px in max(0, rect.x) ..< min(space.path.width, rect.x + rect.w):
      if not space.path.passable(px, py):
        continue
      let distance = distanceSquared(px, py, x, y)
      if distance < bestDistance:
        bestDistance = distance
        result = Point(x: px, y: py)

proc nearestPointOutside*(
  space: JumpPointSpace,
  rect: Rect,
  desired: Point,
  radius: int
): tuple[found: bool, point: Point] =
  ## The nearest walkable point near but outside one rectangle.
  if space == nil:
    return
  var
    bestDistance = high(int)
    bestRectDistance = high(int)
  let
    minX = max(0, rect.x - radius)
    maxX = min(space.path.width - 1, rect.x + rect.w + radius)
    minY = max(0, rect.y - radius)
    maxY = min(space.path.height - 1, rect.y + rect.h + radius)
  for py in minY .. maxY:
    for px in minX .. maxX:
      if rect.contains(px, py):
        continue
      if not space.path.passable(px, py):
        continue
      let rectDistance = pointRectDistanceSquared(px, py, rect)
      if rectDistance > radius * radius:
        continue
      let distance = distanceSquared(px, py, desired.x, desired.y)
      if distance < bestDistance or
          (distance == bestDistance and rectDistance < bestRectDistance):
        bestDistance = distance
        bestRectDistance = rectDistance
        result = (found: true, point: Point(x: px, y: py))

proc toDensePath(steps: openArray[PathStep]): seq[Point] =
  ## Converts sparse jump-point steps into a dense followable path.
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
    var walked = PathDensifyPixels
    while walked < span:
      result.add(Point(
        x: previous.x + dx * walked div span,
        y: previous.y + dy * walked div span
      ))
      walked += PathDensifyPixels
    result.add(point)

proc pathTo*(
  space: JumpPointSpace,
  startX, startY, goalX, goalY: int
): seq[Point] =
  ## A path between two foot pixels.
  if space == nil:
    return
  let
    start = space.nearestPassablePoint(startX, startY)
    goal = space.nearestPassablePoint(goalX, goalY)
  space.findPath(start.x, start.y, goal.x, goal.y).toDensePath()

proc pathTo*(
  space: JumpPointSpace,
  startX, startY: int,
  rect: Rect
): seq[Point] =
  ## A path to a walkable pixel inside one rectangle.
  if space == nil:
    return
  let goal = space.nearestPointInside(rect, startX, startY)
  space.pathTo(startX, startY, goal.x, goal.y)

proc pathNear*(
  space: JumpPointSpace,
  startX, startY: int,
  rect: Rect,
  radius: int
): seq[Point] =
  ## A path to a pixel that can interact with one rectangle.
  if space == nil:
    return
  if space.path.passable(startX, startY) and
      pointRectDistanceSquared(startX, startY, rect) <= radius * radius:
    return @[Point(x: startX, y: startY)]
  var candidates: seq[tuple[distance: int, point: Point]]
  let
    minX = max(0, rect.x - radius)
    maxX = min(space.path.width - 1, rect.x + rect.w + radius)
    minY = max(0, rect.y - radius)
    maxY = min(space.path.height - 1, rect.y + rect.h + radius)
  for py in countup(minY, maxY, 2):
    for px in countup(minX, maxX, 2):
      if not space.path.passable(px, py):
        continue
      if pointRectDistanceSquared(px, py, rect) > radius * radius:
        continue
      candidates.add((
        distance: distanceSquared(px, py, startX, startY),
        point: Point(x: px, y: py)
      ))
  candidates.sort(proc(a, b: tuple[distance: int, point: Point]): int =
    cmp(a.distance, b.distance))
  # Nearby candidates are usually reachable; spread later attempts out
  # across the sorted list in case the closest side is walled off.
  var tried = 0
  var index = 0
  while index < candidates.len and tried < 8:
    result = space.pathTo(
      startX,
      startY,
      candidates[index].point.x,
      candidates[index].point.y
    )
    if result.len > 0:
      return
    inc tried
    index += max(1, candidates.len div 8)

proc pathLengthPixels*(points: openArray[Point]): int =
  ## The walked length of one dense path in pixels.
  for i in 1 ..< points.len:
    result += int(sqrt(float(distanceSquared(
      points[i - 1].x, points[i - 1].y, points[i].x, points[i].y
    ))))

proc linePassable*(space: JumpPointSpace, ax, ay, bx, by: int): bool =
  ## True when a straight line between two points crosses only walkable
  ## pixels.
  space != nil and space.path != nil and space.path.linePassable(ax, ay, bx, by)
