## Shared Heartleaf sprite-protocol definitions used by the game
## simulation and the bot players: object id layout, sprite labels,
## fixed player names, chat limits, clock text, and resource names.

import std/strutils

import bitworld/resources

import common

const
  BottomObjectId* = 1
  OverhangObjectId* = 2
  PlayerObjectBase* = 1000
  NameObjectBase* = 2000
  ChatObjectBase* = 3000
  GardenObjectBase* = 4000
  InventoryObjectBase* = 5000
  InventoryCountObjectBase* = 6000
  ClockObjectBase* = 7000
  ScoreObjectBase* = 7100
  LookingForObjectId* = 7200
  ChatMaxChars* = 96
  MainWalkabilityLabel* = "heartleaf main walkability"
  HomeWalkabilityLabel* = "heartleaf home walkability"
  MainBottomLabelPrefix* = "heartleaf bottom"
  HomeBottomLabelPrefix* = "heartleaf home bottom"
  MainOverhangLabelPrefix* = "heartleaf overhang"
  HomeOverhangLabelPrefix* = "heartleaf home overhang"
  GardenMarkerLabel* = "garden marker"
  GnomeLabelPrefix* = "gnome "
  NameLabelPrefix* = "name "
  ChatLabelPrefix* = "chat "
  ClockLabelPrefix* = "clock "
  ScoreLabelPrefix* = "score "
  DinnerLabelPrefix* = "dinner "
  LookingForLabelPrefix* = "looking "
  WeekdayNames* = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
  FoodNames* = [
    "Lettuce",
    "Carrot",
    "Apple",
    "Tomato",
    "Cucumber",
    "Yellow Squash",
    "Beet",
    "Pear",
    "Cabbage",
    "Purple Cabbage",
    "Grapes",
    "Strawberries",
    "Yam",
    "Potato",
    "Wheat",
    "Rice",
    "Avocado",
    "Red Pepper",
    "Green Pepper",
    "Blueberries",
    "Corn",
    "Radish",
    "Garlic",
    "Onion"
  ]
  PlayerNames* = [
    "Ivan",
    "Anton",
    "Yura",
    "Sasha",
    "Maxim",
    "Nikita",
    "Vova",
    "Dima",
    "Egor"
  ]

when FoodNames.len != FoodVeggieSlots:
  {.error: "FoodNames must match FoodVeggieSlots.".}

proc foodName*(foodIndex: int): string =
  ## Returns the display name for one garden food slot.
  if foodIndex >= 0 and foodIndex < FoodNames.len:
    return FoodNames[foodIndex]
  "food " & $foodIndex

proc lookingForLabel*(eaten: openArray[bool]): string =
  ## Returns the sprite label listing foods not yet eaten this game.
  var names: seq[string]
  for i in 0 ..< FoodNames.len:
    let alreadyEaten = i < eaten.len and eaten[i]
    if not alreadyEaten:
      names.add(FoodNames[i])
  result = LookingForLabelPrefix
  if names.len == 0:
    result.add("none")
  else:
    result.add(names.join(", "))

proc playerNameForHouse*(houseIndex: int): string =
  ## Returns the fixed in-game player name for one house.
  if houseIndex >= 0 and houseIndex < PlayerNames.len:
    return PlayerNames[houseIndex]
  ""

proc houseIndexForPlayerName*(name: string): int =
  ## Returns the fixed house index for one in-game player name.
  result = -1
  for i, playerName in PlayerNames:
    if playerName == name:
      return i

proc weekdayName*(dayNumber: int): string =
  ## Returns the weekday label for one one-based day number.
  WeekdayNames[(max(1, dayNumber) - 1) mod WeekdayNames.len]

proc clockName*(minutes: int): string =
  ## Formats day minutes as one AM/PM clock string like 3:00pm.
  let wrapped = ((minutes mod (24 * 60)) + (24 * 60)) mod (24 * 60)
  var hour = wrapped div 60
  let minute = wrapped mod 60
  let suffix =
    if hour >= 12:
      "pm"
    else:
      "am"
  hour = hour mod 12
  if hour == 0:
    hour = 12
  let minuteText =
    if minute < 10:
      "0" & $minute
    else:
      $minute
  $hour & ":" & minuteText & suffix

proc parseClockMinutes*(text: string): int =
  ## Parses one Heartleaf AM/PM clock string into day minutes.
  result = -1
  let parts = strutils.splitWhitespace(text)
  if parts.len == 0:
    return
  let token = parts[^1]
  if token.len < 4:
    return
  let suffix = token[^2 .. ^1].toLowerAscii()
  if suffix != "am" and suffix != "pm":
    return
  let timeParts = token[0 .. ^3].split(':')
  if timeParts.len != 2:
    return
  try:
    var hour = parseInt(timeParts[0])
    let minute = parseInt(timeParts[1])
    if suffix == "pm" and hour < 12:
      hour += 12
    elif suffix == "am" and hour == 12:
      hour = 0
    result = hour * 60 + minute
  except ValueError:
    result = -1

proc rectName*(rect: ResourceRect): string =
  ## Returns one normalized resource rectangle name.
  rect.name.strip().toLowerAscii()

proc houseIndexFromName*(name: string): int =
  ## Returns the zero-based house index in one resource name.
  if not name.startsWith("house"):
    return -1
  if name.len <= "house".len:
    return -1
  try:
    result = parseInt(name["house".len ..< name.len]) - 1
  except ValueError:
    return -1
  if result < 0 or result >= HouseCount:
    return -1
