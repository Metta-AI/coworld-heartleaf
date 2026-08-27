## Carries out a villager's decision tick by tick: turns the action the
## model chose into goals, paths, button masks, and chat, and decides when
## the model should be asked again. Pure: it reads observations and writes
## villager state; the simulation applies the masks.

import
  std/[math, sets, strutils],
  bitworld/spriteprotocol,
  heartleaf/[common, protocol, decisions, observation, navigation, villager]

const
  CollectActionRadius* = InteractionRadius - 8
  ## Stand beside a gnome, not on top of it: the spot is PersonStandDistance
  ## away on the follower's side, and anything within PersonStandRadius
  ## counts as next to them (close enough to talk).
  PersonStandDistance = 32
  PersonStandRadius* = 44
  GoalArrivePixels = 2
  PathArrivePixels = 3
  PathRejoinPixels = 8
  MoveDeadZonePixels = 1
  SteerLookaheadPoints = 12
  UnstuckAfterTicks = 30
  UnstuckDurationTicks = 24
  RepathStuckTicks = 48
  DecisionRetryTicks* = 24
  DecisionStuckTicks* = RepathStuckTicks * 2
  DoorGatherSlots = 5
  DoorGatherSpacing = 18
  ## A moving target may drift this far before the follower repaths.
  GoalDriftPixels = 12
  ## Walk-time estimates for the state report: top speed in pixels per
  ## tick from the sim (MaxSpeed 704 / MotionScale 256) and a fudge for
  ## acceleration, corners, and doors.
  WalkPixelsPerTick = 2.75
  WalkTimeFudge = 1.5
  LeaveMarginMinutes* = 30
  LeaveNudgeMinutes = 30
  HouseDistanceCachePixels = 16
  UnstuckMasks = [
    ButtonUp,
    ButtonRight,
    ButtonDown,
    ButtonLeft,
    ButtonUp or ButtonRight,
    ButtonDown or ButtonRight,
    ButtonDown or ButtonLeft,
    ButtonUp or ButtonLeft
  ]

type
  BrainOutput* = object
    mask*: uint8
    chat*: string

## Walk times

proc walkMinutes*(observation: Observation, pixels: int): int =
  ## Walking distance in game minutes at this game's clock rate, rounded
  ## up to a multiple of five.
  let ticks = float(pixels) / WalkPixelsPerTick * WalkTimeFudge
  let minutes = ticks / max(0.1, observation.ticksPerMinute)
  max(5, (int(minutes) + 4) div 5 * 5)

proc dinnerLeaveAt*(observation: Observation, walk: int): int =
  ## When this gnome must start for dinner: 4pm, or earlier if the walk
  ## plus the margin would miss 6pm.
  min(DinnerDepartMinutes, DinnerMinutes - walk - LeaveMarginMinutes)

proc computeHouseDistances(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
) =
  ## Fills the cached walking distance in pixels to every house door,
  ## going through the home exit first when inside a house; -1 unknown.
  for houseIndex in 0 ..< HouseCount:
    villager.houseDistances[houseIndex] = -1
    if not layout.houseHasValid(houseIndex) or navigation == nil:
      continue
    let house = layout.houses[houseIndex]
    case observation.scene
    of Outdoors:
      let path = navigation.main.pathTo(
        observation.foot.x, observation.foot.y, house
      )
      if path.len > 0:
        villager.houseDistances[houseIndex] = path.pathLengthPixels()
    of Indoors:
      if observation.currentHouse < 0:
        continue
      if observation.currentHouse == houseIndex:
        villager.houseDistances[houseIndex] = 0
        continue
      var pixels = 0
      if layout.hasExit:
        pixels += navigation.home.pathTo(
          observation.foot.x, observation.foot.y, layout.exit
        ).pathLengthPixels()
      let here = layout.houses[observation.currentHouse].center()
      let path = navigation.main.pathTo(here.x, here.y, house)
      if path.len > 0:
        villager.houseDistances[houseIndex] = pixels + path.pathLengthPixels()
    of Overlay:
      discard
  villager.houseDistancesValid = true
  villager.houseDistancesScene = observation.scene
  villager.houseDistancesHouse = observation.currentHouse
  villager.houseDistancesFoot = observation.foot

proc walkPixelsToHouse*(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  houseIndex: int
): int =
  ## Walking distance in pixels to one house door, from a cache that is
  ## refreshed when the villager changes map or moves far enough.
  if houseIndex < 0 or houseIndex >= HouseCount:
    return -1
  if observation.scene == Overlay:
    return -1
  let moved = distanceSquared(
    observation.foot.x, observation.foot.y,
    villager.houseDistancesFoot.x, villager.houseDistancesFoot.y
  )
  if not villager.houseDistancesValid or
      villager.houseDistancesScene != observation.scene or
      villager.houseDistancesHouse != observation.currentHouse or
      moved > HouseDistanceCachePixels * HouseDistanceCachePixels:
    villager.computeHouseDistances(observation, navigation, layout)
  villager.houseDistances[houseIndex]

proc farthestWalkMinutes*(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
): int =
  ## The walk time in game minutes to the farthest house door.
  for houseIndex in 0 ..< HouseCount:
    let pixels = villager.walkPixelsToHouse(
      observation, navigation, layout, houseIndex
    )
    if pixels >= 0:
      result = max(result, observation.walkMinutes(pixels))

## Goals

proc gardenMarkerOnScreen(observation: Observation, gardenIndex: int): bool =
  ## True when one garden's marker spot is inside the viewport.
  gardenIndex >= 0 and gardenIndex < observation.gardenMarkerOnScreen.len and
    observation.gardenMarkerOnScreen[gardenIndex]

proc gardenHasMarker(observation: Observation, gardenIndex: int): bool =
  ## True when one garden shows its food marker on screen.
  gardenIndex >= 0 and gardenIndex < observation.gardenMarkerVisible.len and
    observation.gardenMarkerVisible[gardenIndex]

proc anyGardenMarkers(observation: Observation): bool =
  ## True when any garden still shows a marker on screen.
  for visible in observation.gardenMarkerVisible:
    if visible:
      return true

proc nearbyMarkedGarden(observation: Observation, layout: WorldLayout): int =
  ## A close marked garden that can be picked up now, or -1.
  result = -1
  if observation.scene != Outdoors:
    return
  var bestDistance = CollectActionRadius * CollectActionRadius + 1
  for i, rect in layout.gardens:
    if not observation.gardenHasMarker(i):
      continue
    let distance = pointRectDistanceSquared(
      observation.foot.x, observation.foot.y, rect
    )
    if distance <= CollectActionRadius * CollectActionRadius and
        distance < bestDistance:
      result = i
      bestDistance = distance

proc gardensExhausted(villager: Villager, observation: Observation): bool =
  ## True when the villager has checked every garden today.
  if observation.anyGardenMarkers():
    return false
  for checked in villager.gardenChecked:
    if not checked:
      return false
  true

proc collectGoal(layout: WorldLayout, gardenIndex: int): Goal =
  ## A goal for picking one garden.
  let target = layout.gardens[gardenIndex].center()
  Goal(
    kind: CollectGarden,
    scene: Outdoors,
    x: target.x,
    y: target.y,
    gardenIndex: gardenIndex,
    houseIndex: UnknownHouse
  )

proc gardenGoal(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
): Goal =
  ## A goal for the nearest garden that may still have food.
  result = idleGoal(Outdoors)
  if observation.scene != Outdoors or navigation == nil:
    return
  let nearbyGarden = observation.nearbyMarkedGarden(layout)
  if nearbyGarden >= 0:
    villager.currentGarden = nearbyGarden
    return layout.collectGoal(nearbyGarden)

  if villager.currentGarden >= 0 and
      villager.currentGarden < villager.gardenChecked.len and
      not villager.gardenChecked[villager.currentGarden]:
    if observation.gardenMarkerOnScreen(villager.currentGarden) and
        not observation.gardenHasMarker(villager.currentGarden):
      villager.gardenChecked[villager.currentGarden] = true
      villager.currentGarden = -1
    else:
      return layout.collectGoal(villager.currentGarden)

  let preferMarkers = observation.anyGardenMarkers()
  for i in 0 ..< layout.gardens.len:
    if i < villager.gardenChecked.len and
        observation.gardenMarkerOnScreen(i) and
        not observation.gardenHasMarker(i):
      villager.gardenChecked[i] = true
  if villager.currentGarden >= 0 and
      villager.currentGarden < villager.gardenChecked.len and
      not villager.gardenChecked[villager.currentGarden]:
    return layout.collectGoal(villager.currentGarden)

  var
    bestIndex = -1
    bestPathLen = high(int)
    bestDistance = high(int)
  for i, rect in layout.gardens:
    if i < villager.gardenChecked.len and villager.gardenChecked[i]:
      continue
    if preferMarkers and observation.gardenMarkerOnScreen(i) and
        not observation.gardenHasMarker(i):
      continue
    let path = navigation.main.pathNear(
      observation.foot.x, observation.foot.y, rect, CollectActionRadius
    )
    if path.len == 0:
      if i < villager.gardenChecked.len:
        villager.gardenChecked[i] =
          observation.gardenMarkerOnScreen(i) and
          not observation.gardenHasMarker(i)
      continue
    let
      target = rect.center()
      distance = distanceSquared(
        observation.foot.x, observation.foot.y, target.x, target.y
      )
    if path.len < bestPathLen or
        (path.len == bestPathLen and distance < bestDistance):
      bestIndex = i
      bestPathLen = path.len
      bestDistance = distance
  if bestIndex < 0:
    return
  villager.currentGarden = bestIndex
  result = layout.collectGoal(bestIndex)

proc goalForRect(
  observation: Observation,
  navigation: Navigation,
  kind: GoalKind,
  rect: Rect,
  houseIndex: int
): Goal =
  ## A navigation goal for standing inside one rectangle.
  let space = navigation.spaceFor(observation.scene)
  var target = rect.center()
  if space != nil:
    target = space.nearestPointInside(rect, target.x, target.y)
  Goal(
    kind: kind,
    scene: observation.scene,
    x: target.x,
    y: target.y,
    houseIndex: houseIndex,
    gardenIndex: -1
  )

proc exitGoal(
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
): Goal =
  ## A goal for leaving the current house.
  if not layout.hasExit:
    return idleGoal(observation.scene)
  observation.goalForRect(navigation, LeaveHouse, layout.exit, UnknownHouse)

proc enterHouseGoal(
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  houseIndex: int
): Goal =
  ## A goal for entering one house from outside.
  if not layout.houseHasValid(houseIndex):
    return idleGoal(observation.scene)
  observation.goalForRect(
    navigation, EnterHouse, layout.houses[houseIndex], houseIndex
  )

proc desiredHouseGatherPoint(villager: Villager, house: Rect): Point =
  ## This villager's preferred outside door spot around one house, so
  ## nine waiting gnomes do not stack on one pixel.
  let
    slot = villager.houseIndex mod DoorGatherSlots
    offset = (slot - DoorGatherSlots div 2) * DoorGatherSpacing
  Point(
    x: house.x + house.w div 2 + offset,
    y: house.y + house.h + 4
  )

proc houseGatherPoint(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  houseIndex: int
): Point =
  ## A walkable outside gathering point near one house.
  result = observation.foot
  if navigation == nil or not layout.houseHasValid(houseIndex):
    return
  let
    house = layout.houses[houseIndex]
    desired = villager.desiredHouseGatherPoint(house)
    outside = navigation.main.nearestPointOutside(
      house, desired, HouseGatherMaxRadius
    )
  if outside.found:
    result = outside.point

proc gatherAtHouseGoal(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  houseIndex: int
): Goal =
  ## A goal that keeps the villager visible outside one house.
  case observation.scene
  of Indoors:
    observation.exitGoal(navigation, layout)
  of Overlay:
    idleGoal(observation.scene)
  of Outdoors:
    let point = villager.houseGatherPoint(
      observation, navigation, layout, houseIndex
    )
    Goal(
      kind: WaitAtDoor,
      scene: Outdoors,
      x: point.x,
      y: point.y,
      houseIndex: houseIndex,
      gardenIndex: -1
    )

proc holdPositionGoal(observation: Observation): Goal =
  ## A goal that stays right here.
  Goal(
    kind: HoldPosition,
    scene: observation.scene,
    x: observation.foot.x,
    y: observation.foot.y,
    houseIndex: observation.currentHouse,
    gardenIndex: -1
  )

proc ownHomeGoal(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
): Goal =
  ## The goal that gets the villager into its own house.
  case observation.scene
  of Indoors:
    if observation.currentHouse == villager.houseIndex:
      return observation.holdPositionGoal()
    observation.exitGoal(navigation, layout)
  of Outdoors:
    observation.enterHouseGoal(navigation, layout, villager.houseIndex)
  of Overlay:
    idleGoal(observation.scene)

proc standingSpotBeside(
  observation: Observation,
  navigation: Navigation,
  person: Point
): Point =
  ## A walkable spot PersonStandDistance from a gnome, on the side the
  ## villager is coming from, so followers never stack on their target.
  let
    dx = float(observation.foot.x - person.x)
    dy = float(observation.foot.y - person.y)
    length = sqrt(dx * dx + dy * dy)
  var offset = Point(x: PersonStandDistance, y: 0)
  if length >= 1.0:
    offset = Point(
      x: int(round(dx / length * float(PersonStandDistance))),
      y: int(round(dy / length * float(PersonStandDistance)))
    )
  result = Point(x: person.x + offset.x, y: person.y + offset.y)
  let space = navigation.spaceFor(observation.scene)
  if space != nil:
    result = space.nearestPassablePoint(result.x, result.y)

proc standNextToPersonGoal(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  name: string
): Goal =
  ## A goal for walking near one visible or likely gnome.
  let index = observation.visiblePlayer(name)
  if index >= 0:
    let player = observation.visiblePlayers[index]
    # Keep the spot already chosen while the gnome stays put: the spot
    # depends on where the follower approaches from, so recomputing it
    # every tick would move it as the follower moves.
    let current = villager.goal
    if current.kind == StandByPerson and current.targetName == name and
        current.scene == observation.scene and
        distanceSquared(player.foot.x, player.foot.y,
          current.anchor.x, current.anchor.y) <=
          GoalDriftPixels * GoalDriftPixels:
      return current
    let spot = observation.standingSpotBeside(navigation, player.foot)
    return Goal(
      kind: StandByPerson,
      scene: observation.scene,
      x: spot.x,
      y: spot.y,
      houseIndex: player.houseIndex,
      gardenIndex: -1,
      targetName: name,
      anchor: player.foot
    )
  # Inside a house you cannot search the world; wait here for them. Late
  # in the afternoon, do not set off across the village either: dinner
  # is close and the walk would cost it.
  if observation.scene == Outdoors and
      observation.minutes < DinnerDepartMinutes:
    let houseIndex = name.houseIndexForPlayerName()
    if houseIndex >= 0:
      return villager.gatherAtHouseGoal(
        observation, navigation, layout, houseIndex
      )
  idleGoal(observation.scene)

proc markSeenDoors*(villager: Villager, observation: Observation) =
  ## Marks every house door currently on screen as wandered-to.
  if observation.scene != Outdoors:
    return
  for i in 0 ..< HouseCount:
    if observation.houseOnScreen[i]:
      villager.wanderedDoors[i] = true

proc allDoorsWandered(villager: Villager): bool =
  ## True when this circuit has seen every house, including own.
  for i in 0 ..< HouseCount:
    if not villager.wanderedDoors[i]:
      return false
  true

proc nextWanderHouse*(villager: Villager): int =
  ## The next house in fixed order that has not been seen this circuit.
  ## Always includes the gnome's own house. Resets after all nine.
  if villager.allDoorsWandered():
    for i in 0 ..< HouseCount:
      villager.wanderedDoors[i] = false
  for i in 0 ..< HouseCount:
    if not villager.wanderedDoors[i]:
      return i
  0

proc wanderGoal(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
): Goal =
  ## Walk the village door to door, including home, then start over.
  villager.markSeenDoors(observation)
  let houseIndex = villager.nextWanderHouse()
  villager.wanderHouse = houseIndex
  villager.gatherAtHouseGoal(observation, navigation, layout, houseIndex)

proc namedHouse*(decision: Decision): int =
  ## The house a named gnome owns, or the JSON houseIndex.
  if decision.targetName.len > 0:
    let named = decision.targetName.houseIndexForPlayerName()
    if named >= 0:
      return named
  decision.houseIndex

proc decisionHouse*(villager: Villager, decision: Decision): int =
  ## The best house target for one decision.
  discard villager
  decision.namedHouse()

proc partyHouseGoal(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  houseIndex: int
): Goal =
  ## Enter one house and stay inside.
  discard villager
  if houseIndex < 0:
    return idleGoal(observation.scene)
  case observation.scene
  of Indoors:
    if observation.currentHouse == houseIndex:
      return observation.holdPositionGoal()
    observation.exitGoal(navigation, layout)
  of Outdoors:
    observation.enterHouseGoal(navigation, layout, houseIndex)
  of Overlay:
    idleGoal(observation.scene)

proc gardenDoorGoal(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  houseIndex: int
): Goal =
  ## Wait outside that gnome's door; go inside just before dinner.
  if houseIndex < 0:
    return idleGoal(observation.scene)
  if observation.minutes >= DinnerMinutes - MovementTurnMinutes:
    return villager.partyHouseGoal(observation, navigation, layout, houseIndex)
  villager.gatherAtHouseGoal(observation, navigation, layout, houseIndex)

proc followGoal(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  name: string
): Goal =
  ## Stay with a named gnome; if they go indoors, go in after them.
  let index = observation.visiblePlayer(name)
  if index >= 0:
    let player = observation.visiblePlayers[index]
    if observation.scene == Indoors:
      villager.followLastHouse = observation.currentHouse
    else:
      var best = player.houseIndex
      var bestDist = high(int)
      for i in 0 ..< HouseCount:
        if not layout.houseHasValid(i):
          continue
        let d = pointRectDistanceSquared(
          player.foot.x, player.foot.y, layout.houses[i]
        )
        if d < bestDist:
          bestDist = d
          best = i
      villager.followLastHouse = best
    return villager.standNextToPersonGoal(
      observation, navigation, layout, name
    )
  if observation.scene == Indoors:
    return observation.holdPositionGoal()
  if villager.followLastHouse >= 0:
    return observation.enterHouseGoal(
      navigation, layout, villager.followLastHouse
    )
  villager.wanderGoal(observation, navigation, layout)

proc talkGoal(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  name: string
): Goal =
  ## Walk to a visible gnome, or wander until they appear.
  if name.len > 0 and observation.visiblePlayer(name) >= 0:
    return villager.standNextToPersonGoal(
      observation, navigation, layout, name
    )
  villager.wanderGoal(observation, navigation, layout)

proc decisionGoal(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
): Goal =
  ## Converts the current decision into a navigation goal.
  ## Talking gnomes stand still. A walker has left the conversation.
  if villager.encounterId > 0:
    return idleGoal(observation.scene)
  let decision = villager.decision
  case decision.action
  of GatherPlants:
    case observation.scene
    of Indoors:
      observation.exitGoal(navigation, layout)
    of Outdoors:
      if villager.gardensExhausted(observation):
        idleGoal(observation.scene)
      else:
        villager.gardenGoal(observation, navigation, layout)
    of Overlay:
      idleGoal(observation.scene)
  of TalkTo:
    villager.talkGoal(
      observation, navigation, layout, decision.targetName
    )
  of Follow:
    villager.followGoal(
      observation, navigation, layout, decision.targetName
    )
  of GoHome:
    villager.ownHomeGoal(observation, navigation, layout)
  of GoToHouse:
    villager.partyHouseGoal(
      observation, navigation, layout, decision.namedHouse()
    )
  of GoToGarden:
    villager.gardenDoorGoal(
      observation, navigation, layout, decision.namedHouse()
    )
  of Wander:
    villager.wanderGoal(observation, navigation, layout)
  of Say, Bye, Wait, Invalid:
    idleGoal(observation.scene)

proc goalReached(
  observation: Observation,
  layout: WorldLayout,
  goal: Goal
): bool =
  ## True when the villager is close enough to a goal to act.
  let foot = observation.foot
  case goal.kind
  of CollectGarden:
    if goal.gardenIndex >= 0 and goal.gardenIndex < layout.gardens.len:
      return pointRectDistanceSquared(
        foot.x, foot.y, layout.gardens[goal.gardenIndex]
      ) <= CollectActionRadius * CollectActionRadius
    distanceSquared(foot.x, foot.y, goal.x, goal.y) <=
      CollectActionRadius * CollectActionRadius
  of EnterHouse:
    layout.houseHasValid(goal.houseIndex) and
      layout.houses[goal.houseIndex].contains(foot.x, foot.y)
  of LeaveHouse:
    layout.exit.contains(foot.x, foot.y)
  of StandByPerson, WaitAtDoor, HoldPosition:
    distanceSquared(foot.x, foot.y, goal.x, goal.y) <=
      GoalArrivePixels * GoalArrivePixels
  of StandStill:
    true

proc goalLabel(goal: Goal): string =
  ## A short log label for one goal.
  case goal.kind
  of StandStill: "idle"
  of CollectGarden: "collect garden " & $goal.gardenIndex
  of WaitAtDoor: "gather outside house " & $(goal.houseIndex + 1)
  of EnterHouse: "enter house " & $(goal.houseIndex + 1)
  of LeaveHouse: "exit house"
  of StandByPerson: "stand next to " & goal.targetName
  of HoldPosition: "wait"

proc sameGoal(a, b: Goal): bool =
  ## True when two goals are the same navigation target. A StandByPerson
  ## goal is reused while its gnome stays near its anchor (see
  ## standNextToPersonGoal), so equality is exact here.
  if a.kind != b.kind or a.scene != b.scene or a.houseIndex != b.houseIndex or
      a.gardenIndex != b.gardenIndex or a.targetName != b.targetName:
    return false
  a.x == b.x and a.y == b.y

proc interactionMask(
  villager: Villager,
  observation: Observation,
  layout: WorldLayout,
  goal: Goal
): uint8 =
  ## An A-button pulse when an interaction goal is ready.
  if villager.attackCooldown > 0:
    dec villager.attackCooldown
    return 0
  if not observation.goalReached(layout, goal):
    return 0
  case goal.kind
  of CollectGarden:
    villager.attackCooldown = 8
    if villager.currentGarden == goal.gardenIndex:
      villager.currentGarden = -1
    villager.path.setLen(0)
    villager.log(goal.goalLabel())
    ButtonA
  of LeaveHouse, EnterHouse:
    villager.attackCooldown = 8
    villager.log(goal.goalLabel())
    ButtonA
  else:
    0'u8

## Decisions

proc sameDecisionTarget*(a, b: Decision): bool =
  ## True when two decisions steer toward the same place, so the current
  ## path can continue instead of being rebuilt.
  a.action == b.action and a.targetName == b.targetName and
    a.houseIndex == b.houseIndex

proc applyDecision*(
  villager: Villager,
  observation: Observation,
  layout: WorldLayout,
  decision: Decision,
  fromModel: bool
) =
  ## Stores one decision. The current path survives when the new decision
  ## heads for the same place.
  discard fromModel
  var nextDecision = decision
  nextDecision.houseIndex = nextDecision.namedHouse()
  let keepPath = villager.hasDecision and
    villager.decision.sameDecisionTarget(nextDecision)
  villager.decision = nextDecision
  villager.hasDecision = true
  villager.decisionChatSent = false
  villager.decisionStartedTick = observation.tick
  villager.pendingTalkName = ""
  villager.pendingTalkMessage = ""
  if nextDecision.action == TalkTo:
    villager.pendingTalkName = nextDecision.targetName
    villager.pendingTalkMessage = nextDecision.message
  if not keepPath:
    villager.path.setLen(0)
    villager.goal = idleGoal(observation.scene)
  villager.log(
    "llm action " & nextDecision.action.actionName() &
    " house=" & $(nextDecision.houseIndex + 1) &
    " target=" & nextDecision.targetName &
    " message=" & nextDecision.message &
    " reason=" & nextDecision.reason
  )

proc hasExecutableDecision*(villager: Villager, observation: Observation): bool =
  ## True when the villager has an action to carry out this tick.
  discard observation
  villager.hasDecision

proc pendingChat(villager: Villager, observation: Observation): string =
  ## Speech queued by talk, say, or bye.
  discard observation
  if villager.pendingSpeech.len == 0:
    return ""
  result = villager.pendingSpeech
  villager.pendingSpeech = ""
  if result in villager.saidToday:
    villager.log("chat suppressed, already said today: " & result)
    return ""
  villager.saidToday.add(result)
  villager.decisionChatSent = true
  villager.log("chat " & result)

## Steering

proc ensurePath(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout,
  goal: Goal
) =
  ## Recomputes the path when the navigation goal changes.
  let changed = not villager.goal.sameGoal(goal)
  if not changed and villager.path.len > 0 and
      villager.stuckTicks < RepathStuckTicks:
    return
  if changed:
    villager.log("goal " & goal.goalLabel())
  villager.goal = goal
  villager.path.setLen(0)
  let space = navigation.spaceFor(observation.scene)
  if space == nil or goal.kind == StandStill:
    return
  let foot = observation.foot
  case goal.kind
  of CollectGarden:
    if goal.gardenIndex >= 0 and goal.gardenIndex < layout.gardens.len:
      villager.path = space.pathNear(
        foot.x, foot.y, layout.gardens[goal.gardenIndex], CollectActionRadius
      )
  of EnterHouse:
    if layout.houseHasValid(goal.houseIndex):
      villager.path = space.pathTo(foot.x, foot.y, layout.houses[goal.houseIndex])
  of LeaveHouse:
    if layout.hasExit:
      villager.path = space.pathTo(foot.x, foot.y, layout.exit)
  else:
    villager.path = space.pathTo(foot.x, foot.y, goal.x, goal.y)
  if villager.path.len == 0:
    villager.path = space.pathTo(foot.x, foot.y, goal.x, goal.y)

proc pathTarget(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  goal: Goal
): Point =
  ## The current lookahead point along the path.
  let foot = observation.foot
  if goal.kind == StandStill:
    return foot
  result = Point(x: goal.x, y: goal.y)
  if villager.path.len > 1:
    var
      bestIndex = 0
      bestDistance = high(int)
    for i, point in villager.path:
      let distance = distanceSquared(foot.x, foot.y, point.x, point.y)
      if distance < bestDistance:
        bestIndex = i
        bestDistance = distance
    if bestIndex > 0 and bestDistance <= PathRejoinPixels * PathRejoinPixels:
      villager.path = villager.path[bestIndex .. ^1]
  while villager.path.len > 0 and
      distanceSquared(foot.x, foot.y, villager.path[0].x, villager.path[0].y) <=
        PathArrivePixels * PathArrivePixels:
    villager.path.delete(0)
  if villager.path.len > 0:
    result = villager.path[0]
    let space = navigation.spaceFor(observation.scene)
    # Steer toward the farthest waypoint with a clear line of sight, so
    # paths cut corners instead of hugging waypoints.
    for i in 0 ..< min(villager.path.len, SteerLookaheadPoints):
      if space.linePassable(foot.x, foot.y, villager.path[i].x, villager.path[i].y):
        result = villager.path[i]
      else:
        break

proc needsMovement(foot, target: Point): bool =
  ## True when a target is far enough to require button input.
  abs(target.x - foot.x) > MoveDeadZonePixels or
    abs(target.y - foot.y) > MoveDeadZonePixels

proc coastPixels(speed: int): int =
  ## How far the sim's friction coasts one speed estimate: friction
  ## 144/256 leaves a geometric tail of about 9/7 of one tick.
  (abs(speed) * 9) div 7

proc axisMask(delta, speed: int, negativeMask, positiveMask: uint8): uint8 =
  ## One axis input, coasting when momentum already arrives.
  if abs(delta) <= MoveDeadZonePixels:
    return 0
  let towardSpeed =
    if delta > 0:
      speed
    else:
      -speed
  if towardSpeed > 0 and coastPixels(towardSpeed) >= abs(delta):
    return 0
  if delta > 0:
    positiveMask
  else:
    negativeMask

proc movementMask(villager: Villager, foot, target: Point): uint8 =
  ## A directional input mask with arrival coasting so momentum does not
  ## overshoot the target and wobble back and forth.
  axisMask(target.x - foot.x, villager.velocity.x, ButtonLeft, ButtonRight) or
    axisMask(target.y - foot.y, villager.velocity.y, ButtonUp, ButtonDown)

proc firstMovingPathTarget(villager: Villager, foot: Point, goal: Goal): Point =
  ## The first path point that can actually produce movement.
  if goal.kind == StandStill:
    return foot
  for point in villager.path:
    if foot.needsMovement(point):
      return point
  Point(x: goal.x, y: goal.y)

proc updateStuck(villager: Villager, foot: Point, mask: uint8) =
  ## Updates stuck detection and jitter recovery state.
  let moving = (mask and (ButtonUp or ButtonDown or ButtonLeft or ButtonRight)) != 0
  let
    blocked = foot == villager.previousFoot
    wobbling = foot == villager.previous2Foot and not blocked
  if moving and (blocked or wobbling):
    inc villager.stuckTicks
  else:
    villager.stuckTicks = 0
  villager.previous2Foot = villager.previousFoot
  villager.previousFoot = foot
  if villager.unstuckTicks > 0:
    dec villager.unstuckTicks
  elif villager.stuckTicks >= UnstuckAfterTicks and
      villager.stuckTicks mod UnstuckAfterTicks == 0:
    villager.unstuckTicks = UnstuckDurationTicks
    villager.unstuckMaskIndex = (villager.unstuckMaskIndex + 1) mod UnstuckMasks.len
    villager.path.setLen(0)
    villager.log("unstuck jitter " & $villager.unstuckMaskIndex)

## Per tick

proc observeWorld*(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
) =
  ## Updates memory from one observation: the day, what was heard and
  ## seen, the clock, the bag, dinner, and curfew. Runs every
  ## frame, including paused ones, so nothing is missed.
  villager.tick = observation.tick
  if villager.footKnown:
    villager.velocity = Point(
      x: observation.foot.x - villager.previousFoot.x,
      y: observation.foot.y - villager.previousFoot.y
    )
  else:
    villager.previousFoot = observation.foot
    villager.previous2Foot = observation.foot
    villager.footKnown = true
  if observation.dayNumber != villager.dayNumber:
    villager.startNewDay(observation.dayNumber)
  villager.scanHeardChats(observation)
  villager.scanSeenGnomes(observation)
  villager.maybeRecordClock(observation)
  villager.maybeRecordVeggies(observation)
  villager.maybeRecordHouse(observation)
  villager.maybeRecordCarry(observation)
  villager.maybeRecordDinner(observation)
  villager.maybeRecordCurfew(observation)

proc villagerTick*(
  villager: Villager,
  observation: Observation,
  navigation: Navigation,
  layout: WorldLayout
): BrainOutput =
  ## The input for one simulation tick: carries out the current decision.
  ## Stuck detection is paused while a reply is pending so a stale
  ## decision cannot trigger a stuck interrupt before the new one lands.
  if observation.scene == Overlay:
    villager.updateStuck(observation.foot, 0)
    return BrainOutput()
  if not villager.hasDecision:
    villager.updateStuck(observation.foot, 0)
    return BrainOutput()
  let stuckMaskFor = proc(mask: uint8): uint8 =
    if villager.requestInFlight: 0'u8 else: mask
  let goal = villager.decisionGoal(observation, navigation, layout)
  let action = villager.interactionMask(observation, layout, goal)
  if action != 0:
    villager.updateStuck(observation.foot, stuckMaskFor(action))
    return BrainOutput(mask: action, chat: villager.pendingChat(observation))
  villager.ensurePath(observation, navigation, layout, goal)
  var target = villager.pathTarget(observation, navigation, goal)
  var mask = villager.movementMask(observation.foot, target)
  if mask == 0 and not observation.goalReached(layout, goal):
    target = villager.firstMovingPathTarget(observation.foot, goal)
    mask = villager.movementMask(observation.foot, target)
  if villager.unstuckTicks > 0 and mask != 0:
    mask = UnstuckMasks[villager.unstuckMaskIndex]
  villager.updateStuck(observation.foot, stuckMaskFor(mask))
  BrainOutput(mask: mask, chat: villager.pendingChat(observation))
