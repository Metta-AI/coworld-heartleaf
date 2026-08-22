## Shared Heartleaf types, constants, and geometry helpers used by the
## game simulation and the bot players.

import bitworld/resources

const
  ViewportWidth* = 320
  ViewportHeight* = 200
  GnomeSpriteSize* = 32
  FoodSpriteSize* = 32
  FoodVeggieSlots* = 24
  HouseCount* = 9
  InteractionRadius* = 40
  PlayerBoxWidth* = 14
  PlayerBoxHeight* = 8
  PlayerBoxOffsetX* = 9
  PlayerBoxOffsetY* = 22
  FootHalfWidth* = PlayerBoxWidth div 2
  FootHalfHeight* = PlayerBoxHeight div 2
  DayStartMinutes* = 8 * 60
  DayEndMinutes* = 22 * 60
  DinnerMinutes* = 18 * 60
  ## One game day is 180 real seconds and a game is seven days, the same
  ## as the hosted league variant, so local runs, league rounds, and
  ## walk-time estimates share the same clock.
  TicksPerSecond* = 24
  DefaultDaySeconds* = 180
  DefaultDayCount* = 7
  DayTicks* = DefaultDaySeconds * TicksPerSecond
  DayTotalMinutes* = DayEndMinutes - DayStartMinutes

type
  Rect* = object
    x*, y*, w*, h*: int

  Point* = object
    x*, y*: int

proc toRect*(rect: ResourceRect): Rect =
  ## Converts one resource rectangle to a gameplay rectangle.
  Rect(x: rect.x, y: rect.y, w: rect.w, h: rect.h)

proc contains*(rect: Rect, x, y: int): bool =
  ## Returns true when a point is inside one rectangle.
  x >= rect.x and
    y >= rect.y and
    x < rect.x + rect.w and
    y < rect.y + rect.h

proc center*(rect: Rect): Point =
  ## Returns the center point for one rectangle.
  Point(x: rect.x + rect.w div 2, y: rect.y + rect.h div 2)

proc footXAt*(spriteX: int): int =
  ## Returns the foot-center x coordinate for one sprite x coordinate.
  spriteX + PlayerBoxOffsetX + PlayerBoxWidth div 2

proc footYAt*(spriteY: int): int =
  ## Returns the foot-center y coordinate for one sprite y coordinate.
  spriteY + PlayerBoxOffsetY + PlayerBoxHeight div 2

proc distanceSquared*(ax, ay, bx, by: int): int =
  ## Returns the squared distance between two points.
  let
    dx = ax - bx
    dy = ay - by
  dx * dx + dy * dy

proc rectDistanceSquared*(a, b: Rect): int =
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

proc pointRectDistanceSquared*(x, y: int, rect: Rect): int =
  ## Returns the squared distance from one point to one rectangle.
  let
    dx =
      if x < rect.x:
        rect.x - x
      elif x >= rect.x + rect.w:
        x - (rect.x + rect.w - 1)
      else:
        0
    dy =
      if y < rect.y:
        rect.y - y
      elif y >= rect.y + rect.h:
        y - (rect.y + rect.h - 1)
      else:
        0
  dx * dx + dy * dy
