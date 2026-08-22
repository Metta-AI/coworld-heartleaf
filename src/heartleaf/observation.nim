## What one villager can see this tick, computed by the simulation from
## ground truth but limited to its own screen, plus the static layout of
## the village. Pure data so the brain modules stay testable without a
## running simulation.

import heartleaf/common

type
  Scene* = enum
    Outdoors
    Indoors
    Overlay

  VisiblePlayer* = object
    name*: string
    houseIndex*: int
    foot*: Point
    distanceSquared*: int
    says*: string
      ## Current chat bubble text when its bubble is on screen.

  DinnerOutcome* = object
    present*: bool
    hostName*: string
    wasHost*: bool
    score*: int
    guests*: seq[string]
    foodsText*: string

  Observation* = object
    tick*: int
    dayNumber*: int
    minutes*: int
    ticksPerMinute*: float
    scene*: Scene
    currentHouse*: int
      ## House index when indoors, -1 otherwise.
    foot*: Point
    inventoryTotal*: int
    foodCollectedText*: string
    foodLookingForText*: string
    visiblePlayers*: seq[VisiblePlayer]
    gardenMarkerOnScreen*: seq[bool]
      ## The garden's marker spot is inside the viewport.
    gardenMarkerVisible*: seq[bool]
      ## The marker is on screen and the garden still has food.
    dinner*: DinnerOutcome
    dinnerDone*: bool
    curfewMissed*: bool
      ## The day ended with this gnome away from home: a penalty applied.

  WorldLayout* = object
    gardens*: seq[Rect]
    houses*: array[HouseCount, Rect]
    houseValid*: array[HouseCount, bool]
    exit*: Rect
    hasExit*: bool

proc sceneName*(scene: Scene): string =
  ## The map name used in the state report.
  case scene
  of Outdoors: "world"
  of Indoors: "home"
  of Overlay: "overlay"

proc visiblePlayer*(observation: Observation, name: string): int =
  ## Index into visiblePlayers of one named gnome, or -1.
  result = -1
  for i, player in observation.visiblePlayers:
    if player.name == name:
      return i

proc houseHasValid*(layout: WorldLayout, houseIndex: int): bool =
  ## True when houseIndex names a real house.
  houseIndex >= 0 and houseIndex < HouseCount and layout.houseValid[houseIndex]
