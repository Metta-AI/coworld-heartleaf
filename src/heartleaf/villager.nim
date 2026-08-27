## One villager's mind: the soul it plays, the transcript it remembers,
## what happened today, the decision it is carrying out, and its place in
## the request queue. Pure: driven by observations, never by the
## simulation directly.

import
  std/[algorithm, json, os, sets, strutils, tables],
  heartleaf/[common, protocol, decisions, observation, souls]

const
  ## Food bands for interrupt detection only: crossing a band re-asks the
  ## model because "how much I carry" changed enough to matter.
  LowFoodBand = 2
  HighFoodBand = 6
  HouseGatherMaxRadius* = 96
  ## A pantry worth hosting with; below it a gnome with no better plan
  ## goes visiting rather than home to an empty table.
  HostPantryMinimum* = 8

type
  GoalKind* = enum
    StandStill
    CollectGarden
    WaitAtDoor
    EnterHouse
    LeaveHouse
    StandByPerson
    HoldPosition

  Goal* = object
    kind*: GoalKind
    scene*: Scene
    x*, y*: int
    houseIndex*: int
    gardenIndex*: int
    targetName*: string
    anchor*: Point
      ## Where the followed gnome stood when a StandByPerson spot was
      ## chosen; the spot is kept until they move away from it.

  GameLog* = ref object
    entries*: seq[string]
      ## Village-wide LLM and world stamps, one JSON line each.
    path*: string
    file: File
    writing: bool

  Villager* = ref object
    houseIndex*: int
    name*: string
      ## The fixed gnome name (Ivan, Anton, ...), also the chat speaker.
    soul*: Soul
    systemPrompt*: string
    ## Memory: chat, events, and JSON replies. Append-only. Each request
    ## also sends a live state report that is logged but not kept.
    history*: seq[ConversationMessage]
    logEntries*: seq[string]
      ## Conversation the model sees: system, user, and assistant
      ## turns, one JSON line each, streamed to the seat's player.
    gameLog*: GameLog
      ## Shared village log for LLM lifecycle and world stamps.
    gameNumber*: int
      ## Which game of this process the villager belongs to; every log
      ## record carries it with its sequence so a collector can resume.
    dayNumber*: int
    minutes*: int
    tick*: int
      ## The simulation tick of the latest observation, stamped on logs.
    now*: float
      ## Wall-clock seconds from the brains frame, stamped on logs.
    lastClockHour*: int
    dayEndRecorded*: bool
    seenToday*: HashSet[string]
    greetedToday*: HashSet[string]
    saidToday*: seq[string]
    gardenChecked*: seq[bool]
    currentGarden*: int
    lastCarryText*: string
    lastBubbles*: Table[string, string]
    dinnerLookingBefore*: string
    dinnerHouse*: int
    dinnerRecorded*: bool
    sawGardenFood*: bool
    veggiesLogged*: bool
    insideHouse*: int
      ## 0-based house when last logged indoors, else UnknownHouse.
    curfewRecorded*: bool
    interruptRequested*: bool
      ## Unused leftover; leapfrog asks on a clock, not interrupts.
    ## The current decision and the world it was made against.
    decision*: Decision
    hasDecision*: bool
    turnReady*: bool
      ## True when this gnome has a usable action for the current LLM turn.
    encounterId*: int
      ## Shared conversation id, 0 when not talking.
    askedWhileTalking*: bool
      ## True when the in-flight request started inside a conversation,
      ## so say/bye still count if the group dissolves before the reply.
    wanderedDoors*: array[HouseCount, bool]
    wanderHouse*: int
    pendingSpeech*: string
    pendingTalkName*: string
    pendingTalkMessage*: string
    followLastHouse*: int
    decisionChatSent*: bool
    decisionStartedTick*: int
    decisionFoodBand*: int
    decisionTimePhase*: int
    decisionChatSignature*: string
    decisionCrowdSignature*: string
    decisionVisibleNames*: HashSet[string]
    ## Request slot, managed by the brains runtime.
    requestInFlight*: bool
    requestSerial*: int
    waitingSinceTick*: int
    lastHeldInterrupt*: string
      ## The last suppressed-interrupt cause logged for the in-flight
      ## request, so a sticky cause is recorded once.
    requestChatSignature*: string
    requestFoodBand*: int
    requestCrowdSignature*: string
      ## World snapshot at the start of the in-flight request, so only
      ## changes after that start queue a follow-up.
    lastRequestAt*: float
    retryAt*: float
    retryBackoffSeconds*: float
    failures*: int
    permanentHits*: int
    failed*: bool
    lastError*: string
    modelUnavailable*: bool
      ## Set each frame by the runtime: a reply cannot arrive right now
      ## (request in flight, backing off, or over budget), so promises
      ## are kept without one.
    ## Navigation.
    goal*: Goal
    path*: seq[Point]
    previousFoot*: Point
    previous2Foot*: Point
    velocity*: Point
    footKnown*: bool
    stuckTicks*: int
    unstuckTicks*: int
    unstuckMaskIndex*: int
    attackCooldown*: int
    houseDistances*: array[HouseCount, int]
    houseDistancesScene*: Scene
    houseDistancesHouse*: int
    houseDistancesFoot*: Point
    houseDistancesValid*: bool

proc idleGoal*(scene: Scene): Goal =
  ## A goal that stands still.
  Goal(kind: StandStill, scene: scene, houseIndex: UnknownHouse, gardenIndex: -1)

proc newGameLog*(): GameLog =
  ## An in-memory game log, optionally later opened as a file.
  GameLog()

proc add*(log: GameLog, line: string) =
  ## Appends one JSON line in memory and, when open, to the file.
  log.entries.add(line)
  if log.writing:
    log.file.writeLine(line)
    log.file.flushFile()

proc startWriting*(log: GameLog, path: string) =
  ## Starts writing this log to a file, replacing any previous file.
  let dir = path.parentDir
  if dir.len > 0:
    createDir(dir)
  log.path = path
  log.file = open(path, fmWrite)
  log.writing = true

proc newVillager*(houseIndex: int, soul: Soul, gardenCount: int): Villager =
  ## A villager for one seat, ready for its first observation.
  result = Villager(
    houseIndex: houseIndex,
    name: houseIndex.playerNameForHouse(),
    soul: soul,
    gameLog: newGameLog(),
    dayNumber: 1,
    minutes: DayStartMinutes,
    lastClockHour: -1,
    gardenChecked: newSeq[bool](gardenCount),
    currentGarden: -1,
    dinnerHouse: UnknownHouse,
    insideHouse: UnknownHouse,
    encounterId: 0,
    wanderHouse: UnknownHouse,
    followLastHouse: UnknownHouse,
    seenToday: initHashSet[string](),
    greetedToday: initHashSet[string](),
    decisionVisibleNames: initHashSet[string](),
    lastBubbles: initTable[string, string](),
    goal: idleGoal(Indoors)
  )
  result.decision = Decision(houseIndex: UnknownHouse)

proc log*(villager: Villager, text: string) =
  ## One activity log line, tagged with the gnome and the game clock.
  echo villager.name, ": ", text, " (", villager.minutes.clockName(), ")"

proc selfNames*(villager: Villager): seq[string] =
  ## The names this villager goes by, for stripping self labels.
  @[villager.name]

proc talking*(villager: Villager): bool =
  ## True when this gnome is in a conversation.
  villager.encounterId > 0

## History and log

proc stampLine(
  villager: Villager,
  sequence: int,
  role: string,
  index: int,
  text: string,
  kind = ""
): string =
  ## One JSON log line with the game clock stamped on it.
  var node = %*{
    "game": villager.gameNumber,
    "sequence": sequence,
    "seat": villager.houseIndex,
    "gnome": villager.name,
    "index": index,
    "role": role,
    "day": villager.dayNumber,
    "minutes": villager.minutes,
    "tick": villager.tick,
    "now": villager.now,
    "text": text
  }
  if kind.len > 0:
    node["kind"] = %kind
  $node

proc logEntry(
  villager: Villager,
  role: string,
  index: int,
  text: string,
  kind = ""
): string =
  ## One JSON conversation line for the seat's player. game and sequence
  ## identify the record; index is its place in the history (-1 for a
  ## live report). Every row stamps the game clock.
  villager.stampLine(
    villager.logEntries.len, role, index, text, kind
  )

proc addGameLog(
  villager: Villager,
  role, text: string,
  kind = ""
) =
  ## Appends one stamp to the village game log.
  if villager.gameLog.isNil:
    villager.gameLog = newGameLog()
  let line = villager.stampLine(
    villager.gameLog.entries.len, role, -1, text, kind
  )
  villager.gameLog.add(line)

proc logLlm*(villager: Villager, kind, extra: string) =
  ## Records one LLM lifecycle event on stdout and in the game log.
  var text = "llm " & kind &
    " day=" & $villager.dayNumber &
    " minutes=" & $villager.minutes &
    " tick=" & $villager.tick &
    " now=" & formatFloat(villager.now, ffDecimal, 3) &
    " clock=" & villager.minutes.clockName()
  if extra.len > 0:
    text.add(" " & extra)
  villager.log(text)
  villager.addGameLog("llm", text, kind)

proc logTurn*(villager: Villager, kind: string, index: int) =
  ## Records one leapfrog phase for the chart. Log only, not sent to
  ## the model.
  villager.logLlm("turn", "kind=" & kind & " index=" & $index)

proc logConversation*(villager: Villager, kind, extra: string) =
  ## Records one conversation enter or exit for the chart.
  var text = "conversation " & kind &
    " day=" & $villager.dayNumber &
    " minutes=" & $villager.minutes &
    " tick=" & $villager.tick &
    " now=" & formatFloat(villager.now, ffDecimal, 3) &
    " clock=" & villager.minutes.clockName()
  if extra.len > 0:
    text.add(" " & extra)
  villager.log(text)
  villager.addGameLog("conversation", text, "convo-" & kind)

proc logClock*(villager: Villager) =
  ## Records one game-hour tick with the wall clock, for the chart axis.
  let text = "clock day=" & $villager.dayNumber &
    " minutes=" & $villager.minutes &
    " tick=" & $villager.tick &
    " now=" & formatFloat(villager.now, ffDecimal, 3) &
    " clock=" & villager.minutes.clockName()
  villager.addGameLog("clock", text, "clock")

proc logVeggies*(villager: Villager) =
  ## Records the moment the village gardens are empty.
  let text = "veggies day=" & $villager.dayNumber &
    " minutes=" & $villager.minutes &
    " tick=" & $villager.tick &
    " now=" & formatFloat(villager.now, ffDecimal, 3) &
    " clock=" & villager.minutes.clockName()
  villager.log("veggies picked")
  villager.addGameLog("veggies", text, "veggies")

proc maybeRecordVeggies*(
  villager: Villager,
  observation: Observation
) =
  ## Logs once per day when every garden has been picked.
  if observation.gardensWithFood > 0:
    villager.sawGardenFood = true
    return
  if not villager.sawGardenFood or villager.veggiesLogged:
    return
  villager.veggiesLogged = true
  villager.logVeggies()

proc logHouse*(villager: Villager, kind: string, houseIndex: int) =
  ## Records one enter or exit with wall time, for the house outlines.
  let own = houseIndex == villager.houseIndex
  let text = "house " & kind &
    " day=" & $villager.dayNumber &
    " minutes=" & $villager.minutes &
    " tick=" & $villager.tick &
    " now=" & formatFloat(villager.now, ffDecimal, 3) &
    " clock=" & villager.minutes.clockName() &
    " house=" & $(houseIndex + 1) &
    " own=" & (if own: "yes" else: "no")
  villager.log(text)
  villager.addGameLog("house", text, kind)

proc maybeRecordHouse*(
  villager: Villager,
  observation: Observation
) =
  ## Logs when the gnome steps into or out of a house.
  let inside =
    if observation.scene == Outdoors or observation.currentHouse < 0:
      UnknownHouse
    else:
      observation.currentHouse
  if inside == villager.insideHouse:
    return
  if villager.insideHouse >= 0:
    villager.logHouse("exit", villager.insideHouse)
  if inside >= 0:
    villager.logHouse("enter", inside)
  villager.insideHouse = inside

proc appendHistory*(villager: Villager, role, text: string) =
  ## Appends one turn to the conversation the model sees and logs it.
  ## The history is never rewritten: what was kept stays kept.
  villager.history.add(ConversationMessage(role: role, content: text))
  villager.logEntries.add(villager.logEntry(role, villager.history.high, text))

proc noteLog*(villager: Villager, text: string) =
  ## Logs something the model never sees: errors, retries, shrinks.
  villager.addGameLog("note", text)

proc logLiveReport*(villager: Villager, text: string) =
  ## Logs the live state report sent this call. It is not a history
  ## turn: the next call gets a fresh report instead.
  villager.logEntries.add(villager.logEntry("user", -1, text))

proc logSystemPrompt*(villager: Villager) =
  ## Logs the system prompt once; it heads every request but is not a
  ## turn of the history.
  villager.logEntries.add(villager.logEntry("system", -1, villager.systemPrompt))

proc recordHeardLine*(villager: Villager, speaker, text: string) =
  ## One chat line heard from another gnome.
  villager.appendHistory("user", speaker & ": " & text)

proc recordTalkLine*(villager: Villager, speaker, message: string) =
  ## One spoken encounter line as its own user turn, once.
  if message.len == 0:
    return
  if speaker == villager.name:
    villager.appendHistory("user", "You: " & message)
  else:
    villager.appendHistory("user", speaker & ": " & message)

proc recordEvent*(villager: Villager, text: string) =
  ## One world event the villager noticed, as a parenthesized user line.
  villager.appendHistory("user", "(" & text & ")")

proc dayBeginsLine(day: int): string =
  ## The history marker that opens one day.
  "Day " & $day & " begins."

proc shrinkHistory*(villager: Villager) =
  ## Emergency only: the model rejected the prompt as too long, so the
  ## oldest day is dropped. The game log keeps a note so a watcher knows
  ## the prefix the model sees no longer starts at the beginning.
  var cut = -1
  for i in 1 ..< villager.history.len:
    let content = villager.history[i].content
    if content.startsWith("(Day ") and content.endsWith(" begins.)"):
      cut = i
      break
  if cut <= 0:
    let half = villager.history.len div 2
    if half <= 0:
      return
    cut = half
  villager.log("history shrunk " & $cut & " lines after a too-long prompt")
  villager.noteLog("history shrunk: the oldest " & $cut &
    " turns were dropped from what the model sees")
  villager.history = villager.history[cut .. ^1]

## Day bookkeeping

proc clockAnnouncement(villager: Villager): string =
  ## One neutral hourly clock line. What the hours mean is the soul's job.
  let
    clock = villager.minutes.clockName()
    minutes = villager.minutes
  result = "Day " & $villager.dayNumber & ". It is " & clock & "."
  if minutes < DinnerMinutes:
    let hours = (DinnerMinutes - minutes) div 60
    if hours <= 0:
      result.add(" Dinner is served within the hour.")
    elif hours == 1:
      result.add(" One hour till dinner.")
    else:
      result.add(" " & $hours & " hours till dinner.")
  elif minutes < DayEndMinutes:
    let hours = (DayEndMinutes - minutes) div 60
    if hours <= 0:
      result.add(" The party ends within the hour.")
    elif hours == 1:
      result.add(" One hour of party left.")
    else:
      result.add(" " & $hours & " hours of party left.")
  else:
    result.add(" The portal takes you now.")

proc recordDayEnd*(villager: Villager) =
  ## Records the end of the day once and logs the transcript size.
  if villager.dayEndRecorded or villager.dayNumber <= 0:
    return
  villager.dayEndRecorded = true
  villager.recordEvent("Day " & $villager.dayNumber & " ends.")
  var heard, said, events, decisions, clocks = 0
  for message in villager.history:
    if message.content.startsWith("Clock: "):
      inc clocks
    elif message.content.startsWith("("):
      if message.role == "user":
        inc events
      else:
        inc decisions
    elif message.role == "user":
      inc heard
    else:
      inc said
  villager.log("day " & $villager.dayNumber & " ends, history len=" &
    $villager.history.len & " heard=" & $heard & " said=" & $said &
    " events=" & $events & " decisions=" & $decisions &
    " clocks=" & $clocks)

proc startNewDay*(villager: Villager, dayNumber: int) =
  ## Resets the per-day state for a new morning: the garden checklist,
  ## who was seen and greeted, dinner bookkeeping, and any decision from
  ## yesterday. lastClockHour = -1 makes the next clock line open with a
  ## "Day N begins." marker.
  villager.recordDayEnd()
  villager.dayNumber = dayNumber
  for i in 0 ..< villager.gardenChecked.len:
    villager.gardenChecked[i] = false
  villager.currentGarden = -1
  villager.hasDecision = false
  villager.turnReady = false
  villager.decisionChatSent = false
  villager.encounterId = 0
  villager.askedWhileTalking = false
  villager.pendingSpeech = ""
  villager.pendingTalkName = ""
  villager.pendingTalkMessage = ""
  villager.wanderHouse = UnknownHouse
  villager.followLastHouse = UnknownHouse
  for i in 0 ..< HouseCount:
    villager.wanderedDoors[i] = false
  villager.seenToday.clear()
  villager.greetedToday.clear()
  villager.interruptRequested = false
  villager.lastHeldInterrupt = ""
  villager.dayEndRecorded = false
  villager.dinnerLookingBefore = ""
  villager.dinnerHouse = UnknownHouse
  villager.dinnerRecorded = false
  villager.sawGardenFood = false
  villager.veggiesLogged = false
  villager.insideHouse = UnknownHouse
  villager.curfewRecorded = false
  villager.saidToday.setLen(0)
  villager.lastClockHour = -1
  villager.lastBubbles.clear()
  villager.houseDistancesValid = false
  villager.path.setLen(0)
  villager.goal = idleGoal(Indoors)

proc maybeRecordClock*(villager: Villager, observation: Observation) =
  ## Records one clock line every game hour, after the day marker on the
  ## first hour of each day.
  villager.minutes = observation.minutes
  let hour = observation.minutes div 60
  if hour == villager.lastClockHour:
    return
  if villager.lastClockHour < 0:
    villager.recordEvent(villager.dayNumber.dayBeginsLine())
  villager.lastClockHour = hour
  villager.appendHistory("user", "Clock: " & villager.clockAnnouncement())
  villager.logClock()
  if observation.minutes >= DayEndMinutes:
    villager.recordDayEnd()

## Seeing and hearing

proc invitesToOwnHouse*(message: string): bool =
  ## True when a chat line invites someone to the speaker's own table.
  let text = message.toLowerAscii()
  for phrase in ["my house", "my place", "my table", "at mine", "my door"]:
    if phrase in text:
      return true

proc scanHeardChats*(villager: Villager, observation: Observation) =
  ## Records each chat bubble of another gnome once, when it appears or
  ## changes, and remembers who last invited people to their table.
  var seen = initHashSet[string]()
  for player in observation.visiblePlayers:
    seen.incl(player.name)
    let previous = villager.lastBubbles.getOrDefault(player.name, "")
    if player.says == previous:
      continue
    villager.lastBubbles[player.name] = player.says
    if player.says.len > 0 and villager.encounterId == 0:
      villager.recordHeardLine(player.name, player.says)
  var gone: seq[string]
  for name in villager.lastBubbles.keys:
    if name notin seen:
      gone.add(name)
  for name in gone:
    villager.lastBubbles.del(name)

proc scanSeenGnomes*(villager: Villager, observation: Observation) =
  ## Records the first sighting of each other gnome today and flags it so
  ## the current action can be interrupted to say hello.
  if observation.scene == Overlay:
    return
  for player in observation.visiblePlayers:
    if player.name in villager.seenToday:
      continue
    villager.seenToday.incl(player.name)
    villager.recordEvent("You see " & player.name & " for the first time today.")
    villager.log("first sighting " & player.name)

proc maybeRecordCarry*(villager: Villager, observation: Observation) =
  ## Records what the villager carries whenever the set of foods changes.
  if observation.scene == Overlay:
    return
  let carry = observation.foodCollectedText
  let names = carry.foodNamesIn().join(", ")
  if names == villager.lastCarryText:
    return
  villager.lastCarryText = names
  if carry == "none":
    villager.recordEvent("You carry no food now.")
  else:
    villager.recordEvent("You now carry: " & carry & ".")

proc dinnerSummary(villager: Villager, observation: Observation): string =
  ## Turns the dinner outcome into a transcript line.
  let dinner = observation.dinner
  var guests: seq[string]
  for name in dinner.guests:
    if name.len > 0 and name != villager.name:
      guests.add(name)
  let others =
    if guests.len == 0:
      "nobody else"
    else:
      guests.join(", ")
  let scoreText = " (+" & $dinner.score & " score)"
  if dinner.wasHost:
    return "Dinner: you hosted " & others & " at your house and served " &
      dinner.foodsText & scoreText & ". Your pantry is empty now."
  var wanted: seq[string]
  let before = villager.dinnerLookingBefore.foodNamesIn()
  for name in dinner.foodsText.foodNamesIn():
    if name in before:
      wanted.add(name)
  result = "Dinner: you ate at " & dinner.hostName & "'s house with " &
    others & ". You ate " & dinner.foodsText & scoreText & "."
  if wanted.len > 0:
    result.add(" You had wanted " & wanted.join(", ") & " and got it.")
  let stillLooking = observation.foodLookingForText
  if stillLooking.len > 0 and stillLooking != "none":
    result.add(" Still looking for: " & stillLooking & ".")

proc maybeRecordDinner*(villager: Villager, observation: Observation) =
  ## Remembers, until dinner, where the villager is and what it still
  ## wants, then records the dinner result the moment dinner is tallied,
  ## or that dinner was missed.
  if villager.dinnerRecorded:
    return
  if not observation.dinnerDone:
    villager.dinnerLookingBefore = observation.foodLookingForText
    villager.dinnerHouse = observation.currentHouse
    return
  villager.dinnerRecorded = true
  if observation.dinner.present:
    let summary = villager.dinnerSummary(observation)
    villager.recordEvent(summary)
    villager.log("dinner " & summary)
    return
  let missed =
    if villager.dinnerHouse < 0:
      "Dinner: you were outside at 6pm and missed dinner."
    elif villager.dinnerHouse == villager.houseIndex:
      "Dinner: you were home at 6pm but nobody came, so there was no dinner."
    else:
      "Dinner: you were at " & villager.dinnerHouse.playerNameForHouse() &
        "'s house at 6pm but no dinner was served there (the host was " &
        "not inside)."
  villager.recordEvent(missed)
  villager.log("dinner missed: " & missed)

proc maybeRecordCurfew*(villager: Villager, observation: Observation) =
  ## Records the curfew penalty once, the moment the day ends with the
  ## gnome away from home.
  if villager.curfewRecorded or not observation.curfewMissed:
    return
  villager.curfewRecorded = true
  let text = "Curfew: you were not inside your own house at " &
    DayEndMinutes.clockName() & ", so you lost " & $CurfewPenalty & " points."
  villager.recordEvent(text)
  villager.log("curfew missed: -" & $CurfewPenalty)

## Interrupt signatures

proc timePhase*(observation: Observation): int =
  ## The game hour; a new hour re-asks the model so it can react to the
  ## clock line that just landed in the transcript.
  observation.minutes div 60

proc foodBand*(observation: Observation): int =
  ## A coarse inventory band for interrupt detection.
  if observation.inventoryTotal <= LowFoodBand:
    return 0
  if observation.inventoryTotal >= HighFoodBand:
    return 2
  return 1

proc visibleGnomeNames*(observation: Observation): HashSet[string] =
  ## The names of the other gnomes on screen right now.
  for player in observation.visiblePlayers:
    result.incl(player.name)

proc visibleChatsSignature*(observation: Observation): string =
  ## A compact signature of visible chat bubbles.
  for player in observation.visiblePlayers:
    if player.says.len > 0:
      result.add(player.name & ":" & player.says & "|")

proc playerNearHouse(
  player: VisiblePlayer,
  layout: WorldLayout,
  houseIndex: int
): bool =
  ## True when a visible gnome is waiting near one house.
  if not layout.houseHasValid(houseIndex):
    return false
  pointRectDistanceSquared(
    player.foot.x, player.foot.y, layout.houses[houseIndex]
  ) <= HouseGatherMaxRadius * HouseGatherMaxRadius

proc houseCrowdOthers*(
  observation: Observation,
  layout: WorldLayout,
  houseIndex: int
): int =
  ## How many other visible gnomes are gathered near one house.
  for player in observation.visiblePlayers:
    if player.playerNearHouse(layout, houseIndex):
      inc result

proc houseOwnerPresent*(
  observation: Observation,
  layout: WorldLayout,
  houseIndex: int
): bool =
  ## True when a house owner is visible near their house.
  for player in observation.visiblePlayers:
    if player.houseIndex == houseIndex and
        player.playerNearHouse(layout, houseIndex):
      return true

proc houseHasGuest*(
  observation: Observation,
  layout: WorldLayout,
  houseIndex: int
): bool =
  ## True when another visible gnome waits near one house.
  for player in observation.visiblePlayers:
    if player.playerNearHouse(layout, houseIndex):
      return true

proc houseCrowdsSignature*(
  observation: Observation,
  layout: WorldLayout
): string =
  ## A compact signature of visible house crowds.
  for houseIndex in 0 ..< HouseCount:
    let crowd = observation.houseCrowdOthers(layout, houseIndex)
    if crowd > 0:
      result.add($(houseIndex + 1) & ":" & $crowd & ",")
  if result.len == 0:
    result = "none"

proc namesText*(names: HashSet[string]): string =
  ## A sorted, comma separated name list or "none".
  var sorted: seq[string]
  for name in names:
    sorted.add(name)
  sorted.sort()
  if sorted.len == 0:
    return "none"
  sorted.join(", ")

proc notYetGreetedText*(villager: Villager, observation: Observation): string =
  ## Visible gnomes this villager has not greeted today.
  var pending: HashSet[string]
  for player in observation.visiblePlayers:
    if player.name notin villager.greetedToday:
      pending.incl(player.name)
  pending.namesText()

proc visiblePlayerNear*(
  villager: Villager,
  observation: Observation,
  name: string,
  radius: int
): bool =
  ## True when one named visible gnome is within radius of the villager.
  let index = observation.visiblePlayer(name)
  if index < 0:
    return false
  let player = observation.visiblePlayers[index]
  distanceSquared(
    observation.foot.x, observation.foot.y, player.foot.x, player.foot.y
  ) <= radius * radius
