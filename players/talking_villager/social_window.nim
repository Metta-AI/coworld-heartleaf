import heartleaf/common

const
  SocialWindowStartMinutes* = 15 * 60
  SocialHostPantryThreshold* = DinnerEatRounds * NewFoodEatScore

proc socialWindowActive*(
  minutes, dinnerLeaveAt, pantryItems: int
): bool =
  ## Returns whether the pantry-gated late-day social window is open.
  dinnerLeaveAt >= 0 and
    minutes >= SocialWindowStartMinutes and
    minutes < dinnerLeaveAt and
    pantryItems >= SocialHostPantryThreshold

proc socialTargetNeedsRefresh*(
  currentName, nearestName: string,
  currentDistance, nearestDistance: int
): bool =
  ## Returns whether a live nearest-villager target replaced the current one.
  if nearestName.len == 0 or currentName.len == 0:
    return true
  if nearestName != currentName:
    return true
  currentDistance >= 0 and nearestDistance >= 0 and
    nearestDistance < currentDistance

proc socialDirection*(deltaX, deltaY: int): string =
  ## Returns the cardinal direction from the bot toward a villager.
  if deltaX == 0 and deltaY == 0:
    return "none"
  if abs(deltaX) >= abs(deltaY):
    if deltaX > 0:
      return "east"
    return "west"
  if deltaY > 0:
    return "south"
  "north"
