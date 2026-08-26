## The state report: the facts one villager is told each time the model is
## asked, and the full message list for one request. The report is live:
## sent as the last user turn, logged, and not kept in history.

import
  heartleaf/[common, protocol, decisions, observation, navigation, villager]

proc visiblePlayersText(observation: Observation): string =
  ## The gnomes on screen, with what they are saying right now.
  for player in observation.visiblePlayers:
    if result.len > 0:
      result.add(", ")
    result.add(player.name)
    if player.says.len > 0:
      result.add(" (says \"" & player.says & "\")")
  if result.len == 0:
    result = "none"

proc houseCrowdsText(
  observation: Observation,
  layout: WorldLayout
): string =
  ## Houses with gnomes waiting at the door.
  for houseIndex in 0 ..< HouseCount:
    if not layout.houseHasValid(houseIndex):
      continue
    let crowd = observation.houseCrowdOthers(layout, houseIndex)
    if crowd == 0:
      continue
    if result.len > 0:
      result.add("; ")
    result.add(houseIndex.playerNameForHouse() & "'s house: " & $crowd)
    if observation.houseOwnerPresent(layout, houseIndex):
      result.add(" (owner there)")
  if result.len == 0:
    result = "none"

proc stateReport*(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
): string =
  ## One current-state report for the model, kept to the facts that
  ## change between turns: the clock, the bag, who is around and not yet
  ## greeted, who waits at which door. Everything else the model needs is
  ## in the history (clock lines, departure notes, dinners) or in the
  ## system prompt.
  let left = max(0, DinnerMinutes - observation.minutes)
  "Day " & $observation.dayNumber & " " & observation.minutes.clockName() &
    " (" & $left & " minutes until dinner)\n" &
    "Food collected: " & observation.foodCollectedText & "\n" &
    "Food looking for: " & observation.foodLookingForText & "\n" &
    "Seen today not greeted: " & villager.notYetGreetedText(observation) & "\n" &
    "Visible players: " & observation.visiblePlayersText() & "\n" &
    "Visible house crowds: " & observation.houseCrowdsText(layout) & "\n" &
    "Return JSON now."

proc requestMessages*(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
): seq[ConversationMessage] =
  ## The full message list for one request: the system prompt, the
  ## history, and this request's state report as a live last user turn
  ## that is logged but not kept.
  let report = villager.stateReport(observation, navigation, layout)
  villager.logLiveReport(report)
  result.add(ConversationMessage(role: "system", content: villager.systemPrompt))
  for message in villager.history:
    result.add(message)
  result.add(ConversationMessage(role: "user", content: report))
