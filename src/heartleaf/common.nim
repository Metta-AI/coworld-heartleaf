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
  ## The clock in round numbers: a day is the twelve hours from 9am to
  ## 9pm and lasts three real minutes, so four game hours pass every real
  ## minute (15 seconds a game hour, 360 ticks at 24 frames a second); a
  ## game is a week of seven days, each ending with a ten-second score
  ## screen, about 22 minutes in all. Local runs, league rounds, and
  ## walk-time estimates all share this clock.
  DayStartMinutes* = 9 * 60
  DayEndMinutes* = 21 * 60
  DinnerMinutes* = 18 * 60
  DinnerDepartMinutes* = 16 * 60
    ## Kept for the clock; dinner no longer auto-walks at 4pm.
  DayTotalMinutes* = DayEndMinutes - DayStartMinutes
  TicksPerSecond* = 24
  SecondsPerGameHour* = 15
  DefaultDaySeconds* = SecondsPerGameHour * (DayTotalMinutes div 60)
  DefaultDayCount* = 7
  DayTicks* = DefaultDaySeconds * TicksPerSecond
  ## Leapfrog movement slice: one game hour, 15 sim-seconds at 24 ticks,
  ## 12 slices per day. Game time advances only here. Wall time is not
  ## paced to those ticks.
  MovementTurnSeconds* = SecondsPerGameHour
  MovementTurnTicks* = MovementTurnSeconds * TicksPerSecond
  ## One movement turn in game minutes (15s at 15s per game hour = 60).
  MovementTurnMinutes* = MovementTurnSeconds * 60 div SecondsPerGameHour
  MovementTurnsPerDay* = DefaultDaySeconds div MovementTurnSeconds
  ScoreScreenSeconds* = 10
  ScoreScreenTicks* = ScoreScreenSeconds * TicksPerSecond
  ## Points lost for not being inside your own house when the day ends.
  CurfewPenalty* = 3
  ## Hosted episodes must finish inside the deadline the manifest sets
  ## (episode_timeout_minutes); the rest is for soul upload and pauses.
  HostedDeadlineSeconds* = 40 * 60

type
  Rect* = object
    x*, y*, w*, h*: int

  Point* = object
    x*, y*: int

proc gameTicksForDays*(days, dayTicks: int): int =
  ## The ticks a game of `days` days takes, score screens included.
  days * (dayTicks + ScoreScreenTicks)

proc hostedDeadlineProblem*(maxTicks: int): string =
  ## Why a game of maxTicks ticks cannot run hosted, or "" when it fits
  ## inside HostedDeadlineSeconds. Pauses add real time on top, so the
  ## tick budget alone must fit.
  if maxTicks <= 0:
    return ""
  let seconds = maxTicks div TicksPerSecond
  if seconds > HostedDeadlineSeconds:
    return "a game of " & $maxTicks & " ticks runs " & $(seconds div 60) &
      " minutes at " & $TicksPerSecond & " fps, past the " &
      $(HostedDeadlineSeconds div 60) & " minute hosted deadline"

static:
  doAssert hostedDeadlineProblem(gameTicksForDays(DefaultDayCount, DayTicks)) == "",
    "the default week must fit the hosted deadline"
  doAssert DefaultDaySeconds mod MovementTurnSeconds == 0
  doAssert MovementTurnsPerDay == 12
  doAssert MovementTurnTicks == 360

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
