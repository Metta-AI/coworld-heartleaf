## The state report: the facts one villager is told each time the model
## is asked, and the full message list for one request. The report is live:
## sent as the last user turn, logged, and not kept in history.

import
  std/strutils,
  heartleaf/[common, protocol, decisions, observation, navigation, villager,
    encounters, executor]

proc peopleNextToText(observation: Observation): string =
  ## Gnomes close enough to talk, or empty when nobody is next to you.
  var names: seq[string]
  for player in observation.visiblePlayers:
    if distanceSquared(
      observation.foot.x, observation.foot.y, player.foot.x, player.foot.y
    ) <= PersonStandRadius * PersonStandRadius:
      names.add(player.name)
  names.join(", ")

proc housesNextToText(
  observation: Observation,
  layout: WorldLayout
): string =
  ## Houses whose door you are standing at, or empty.
  var names: seq[string]
  for houseIndex in 0 ..< HouseCount:
    if not layout.houseHasValid(houseIndex):
      continue
    if pointRectDistanceSquared(
      observation.foot.x, observation.foot.y, layout.houses[houseIndex]
    ) <= HouseGatherMaxRadius * HouseGatherMaxRadius:
      names.add(houseIndex.playerNameForHouse() & "'s house")
  names.join(", ")

proc whereYouAre*(
  observation: Observation,
  layout: WorldLayout
): string =
  ## Inside a house, outside a garden door, or out in the village.
  if observation.scene == Overlay:
    return "at the dinner table"
  if observation.scene == Indoors and observation.currentHouse >= 0:
    let owner = observation.currentHouse.playerNameForHouse()
    return "inside " & owner & "'s house"
  let doors = observation.housesNextToText(layout)
  if doors.len > 0:
    return "outside " & doors.replace("'s house", "'s garden")
  "outside, in the village"

proc dinnerBellText*(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
): string =
  ## Leave-now warning when the walk to dinner is about to run out.
  if observation.minutes >= DinnerMinutes:
    return ""
  let walk = villager.farthestWalkMinutes(
    observation, navigation, layout
  )
  let leaveAt = observation.dinnerLeaveAt(walk)
  if observation.minutes < leaveAt:
    return ""
  if observation.scene == Indoors:
    return "Dinner bell: you are inside. Stay through 6:00pm to eat here."
  "Dinner bell: leave now if you want to be inside a house by 6:00pm."

proc stateReport*(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  encounter: Encounter = nil
): string =
  ## One current-state report for the model. Empty food and next-to
  ## lines are omitted. Where you are is always said.
  discard encounter
  result = "Day " & $observation.dayNumber & " " &
    observation.minutes.clockName() & "\n"
  result.add("Where: " & observation.whereYouAre(layout) & "\n")
  if villager.talking:
    result.add("Talking: yes\n")
  else:
    result.add("Talking: no\n")
  let bell = villager.dinnerBellText(observation, navigation, layout)
  if bell.len > 0:
    result.add(bell & "\n")
  if villager.lastError.len > 0:
    result.add("Last JSON was ignored: " & villager.lastError & "\n")
  let people = observation.peopleNextToText()
  if people.len > 0:
    result.add("People next to: " & people & "\n")
  let carry = observation.foodCollectedText
  if carry.len > 0 and carry != "none":
    result.add("Food collected: " & carry & "\n")
  result.add("Food looking for: " & observation.foodLookingForText & "\n")
  result.add("Return JSON now.")

proc requestMessages*(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  encounter: Encounter = nil
): seq[ConversationMessage] =
  ## The full message list for one request: the system prompt, the
  ## history, and this request's state report as a live last user turn
  ## that is logged but not kept.
  let report = villager.stateReport(
    observation, navigation, layout, encounter
  )
  villager.logLiveReport(report)
  result.add(ConversationMessage(role: "system", content: villager.systemPrompt))
  for message in villager.history:
    result.add(message)
  result.add(ConversationMessage(role: "user", content: report))
