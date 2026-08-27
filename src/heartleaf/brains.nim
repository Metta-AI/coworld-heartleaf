## The villager brains runtime: one Villager per seat, the shared model
## client and request budget, leapfrog LLM and movement phases, and
## conversation encounters. The simulation pauses for the whole LLM
## phase until every gnome has a usable reply.

import
  std/[algorithm, options, os, sets, strutils, tables],
  heartleaf/[common, protocol, decisions, observation, navigation, villager,
    executor, report, prompt, pacing, bedrock_client, souls, encounters]

const
  PermanentConfirmations = 2
  PermanentRetrySeconds = 5.0
  ContextRetrySeconds = 2.0

type
  SeatFailureHandler* = proc(seat: int, message: string) {.closure.}
  TurnPhase* = enum
    LlmPhase
    MovePhase
  BrainOutputFor* = object
    houseIndex*: int
    output*: BrainOutput
  BrainFrame* = object
    paused*: bool
    blockedNames*: seq[string]
    outputs*: seq[BrainOutputFor]
  Brains* = ref object
    villagers*: Table[int, Villager]
    client*: BedrockClient
    budget*: RequestBudget
    navigation*: Navigation
    layout*: WorldLayout
    onSeatFailure*: SeatFailureHandler
    pausedSince*: float
    gameNumber*: int
    phase*: TurnPhase
    turnIndex*: int
    moveTicksLeft*: int
    book*: EncounterBook
    gameLog*: GameLog
      ## One village log for LLM lifecycle and world stamps.

proc newBrains*(
  navigation: Navigation,
  layout: WorldLayout,
  client: BedrockClient,
  seed: int
): Brains =
  ## A runtime with no villagers yet.
  Brains(
    villagers: initTable[int, Villager](),
    client: client,
    budget: newRequestBudget(seed),
    navigation: navigation,
    layout: layout,
    gameNumber: 1,
    phase: LlmPhase,
    turnIndex: 0,
    book: initEncounterBook(),
    gameLog: newGameLog()
  )

proc openGameLog*(brains: Brains, dir: string) =
  ## Writes LLM and world stamps to dir/game.log when dir is set.
  if dir.len == 0:
    return
  brains.gameLog.startWriting(dir / "game.log")

proc attachSoul*(brains: Brains, houseIndex: int, soul: Soul) =
  ## Brings one seat to life with its soul.
  var villager = newVillager(houseIndex, soul, brains.layout.gardens.len)
  villager.gameNumber = brains.gameNumber
  villager.gameLog = brains.gameLog
  villager.systemPrompt = systemPrompt(soul, villager.name)
  villager.logSystemPrompt()
  brains.villagers[houseIndex] = villager
  villager.logTurn("llm", brains.turnIndex)
  villager.log("soul attached model=" & soul.modelId &
    " prompt=" & $villager.systemPrompt.len & " chars")

proc resetForNewGame*(brains: Brains) =
  ## Fresh minds for a fresh village, same souls; log records start a
  ## new game number at sequence 0.
  inc brains.gameNumber
  var souls: seq[(int, Soul)]
  for houseIndex, villager in brains.villagers.pairs:
    souls.add((houseIndex, villager.soul))
  brains.villagers.clear()
  brains.phase = LlmPhase
  brains.turnIndex = 0
  brains.moveTicksLeft = 0
  brains.book = initEncounterBook()
  for (houseIndex, soul) in souls:
    brains.attachSoul(houseIndex, soul)

proc requestTag(villager: Villager): string =
  ## The tag that routes a reply back to its villager and request.
  $villager.houseIndex & ":" & $villager.requestSerial

proc villagerForTag(brains: Brains, tag: string): Villager =
  ## The villager a reply tag belongs to, nil when stale or unknown.
  let parts = tag.split(':')
  if parts.len != 2:
    return nil
  var houseIndex, serial: int
  try:
    houseIndex = parseInt(parts[0])
    serial = parseInt(parts[1])
  except ValueError:
    return nil
  if houseIndex notin brains.villagers:
    return nil
  let villager = brains.villagers[houseIndex]
  if serial != villager.requestSerial or not villager.requestInFlight:
    return nil
  villager

proc abandonRequest(villager: Villager) =
  ## Forgets a request in flight; its reply is dropped when it lands.
  if villager.requestInFlight:
    villager.logLlm("abandon", "tag=" & villager.requestTag())
  villager.requestInFlight = false
  villager.lastHeldInterrupt = ""

proc startRequest(
  brains: Brains,
  villager: Villager,
  observation: Observation,
  now: float
) =
  ## Starts one model request for a villager.
  inc villager.requestSerial
  let request = BedrockRequest(
    tag: villager.requestTag(),
    modelId: villager.soul.modelId,
    playerSlot: villager.houseIndex,
    playerName: villager.name,
    messages: villager.requestMessages(
      observation, brains.navigation, brains.layout,
      brains.book.encounter(villager.encounterId)
    )
  )
  try:
    brains.client.start(request)
  except CatchableError as e:
    villager.lastError = e.msg
    let wait = villager.noteTransientFailure(brains.budget, now)
    villager.log("llm start error " & e.msg & ", retry in " &
      formatFloat(wait, ffDecimal, 1) & "s")
    return
  villager.requestInFlight = true
  villager.lastRequestAt = now
  villager.waitingSinceTick = -1
  villager.askedWhileTalking = villager.encounterId > 0
  villager.interruptRequested = false
  villager.lastHeldInterrupt = ""
  villager.requestChatSignature = observation.visibleChatsSignature()
  villager.requestFoodBand = observation.foodBand()
  villager.requestCrowdSignature = observation.houseCrowdsSignature(
    brains.layout
  )
  brains.budget.noteRequest(now)
  villager.logLlm(
    "request",
    "tag=" & request.tag &
    " model=" & request.modelId &
    " inFlight=" & $brains.budget.inFlight
  )

proc modeError*(villager: Villager, decision: Decision): string =
  ## Why this decision is illegal in the current talk mode, or "".
  if not decision.valid:
    return decision.error
  if villager.talking:
    if decision.action notin {TalkTo, Say, Bye}:
      return "Talking: yes, so action must be talk_to, say, or bye. " &
        "bye to leave. " & decision.action.actionName() & " is rejected."
  elif decision.action in {Say, Bye} and not villager.askedWhileTalking:
    return "Talking: no, so say and bye are invalid. Use talk_to if " &
      "someone is next to you, or wait, wander, gather_plants, follow, " &
      "go_home, go_to_house, or go_to_garden."
  case decision.action
  of TalkTo:
    if decision.targetName.len == 0 or decision.message.len == 0:
      return "talk_to needs targetName and message."
  of Say, Bye:
    if decision.message.len == 0:
      return decision.action.actionName() & " needs a message."
  of Follow, GoToHouse, GoToGarden:
    if decision.namedHouse() < 0 and decision.targetName.len == 0:
      return decision.action.actionName() & " needs targetName."
  else:
    discard
  ""

proc modeAllows*(villager: Villager, decision: Decision): bool =
  ## True when this action is legal in or out of conversation.
  villager.modeError(decision).len == 0

proc setEncounter(brains: Brains, houseIndex, id: int) =
  ## Assigns a gnome to an encounter id (0 is none).
  if houseIndex notin brains.villagers:
    return
  brains.villagers[houseIndex].encounterId = id

proc conversationExtra(brains: Brains, encounter: Encounter): string =
  ## Chart fields for one conversation log line.
  "id=" & $encounter.id &
    " members=" & encounter.memberNames() &
    " turn=" & $brains.turnIndex

proc logEnter(brains: Brains, encounter: Encounter) =
  ## Logs conversation enter for every member.
  if encounter == nil:
    return
  let extra = brains.conversationExtra(encounter)
  for houseIndex in encounter.members:
    if houseIndex in brains.villagers:
      brains.villagers[houseIndex].logConversation("enter", extra)

proc logJoin(brains: Brains, encounter: Encounter, houseIndex: int) =
  ## Logs conversation enter for one gnome who just joined.
  if encounter == nil:
    return
  if houseIndex in brains.villagers:
    brains.villagers[houseIndex].logConversation(
      "enter", brains.conversationExtra(encounter)
    )

proc dissolveIfAlone(brains: Brains, encounter: Encounter) =
  ## Drops a group that has 0 or 1 members left.
  if encounter == nil:
    return
  if encounter.members.len >= 2:
    return
  for houseIndex in encounter.members:
    if houseIndex in brains.villagers:
      let villager = brains.villagers[houseIndex]
      villager.logConversation(
        "exit", "id=" & $encounter.id & " turn=" & $brains.turnIndex
      )
      villager.encounterId = 0
  brains.book.dissolve(encounter)

proc replayTalk*(
  brains: Brains,
  villager: Villager,
  encounter: Encounter
) =
  ## Copies the encounter so far into one gnome's history, once.
  if encounter == nil:
    return
  for line in encounter.lines:
    let (speaker, message) = line.splitTalkLine()
    villager.recordTalkLine(speaker, message)

proc joinOrStartTalk*(
  brains: Brains,
  speaker: Villager,
  targetName: string
): Encounter =
  ## Puts speaker into a conversation with targetName, joining an
  ## existing group when the target is already talking.
  let targetHouse = targetName.houseIndexForPlayerName()
  if targetHouse < 0 or targetHouse notin brains.villagers:
    return nil
  let target = brains.villagers[targetHouse]
  if speaker.talking:
    result = brains.book.encounter(speaker.encounterId)
    if result != nil:
      if not result.hasMember(targetHouse):
        result.addMember(targetHouse)
        brains.setEncounter(targetHouse, result.id)
        brains.replayTalk(target, result)
        brains.logJoin(result, targetHouse)
      return
  if target.talking:
    result = brains.book.encounter(target.encounterId)
    if result != nil:
      if not result.hasMember(speaker.houseIndex):
        result.addMember(speaker.houseIndex)
        brains.setEncounter(speaker.houseIndex, result.id)
        brains.replayTalk(speaker, result)
        brains.logJoin(result, speaker.houseIndex)
      return
  result = brains.book.startEncounter(speaker.houseIndex, targetHouse)
  brains.setEncounter(speaker.houseIndex, result.id)
  brains.setEncounter(targetHouse, result.id)
  brains.logEnter(result)

proc speakInEncounter*(
  brains: Brains,
  speaker: Villager,
  message: string
) =
  ## Adds a line to the shared log, each member's history, and the bubble.
  if message.len == 0:
    return
  speaker.pendingSpeech = message
  let encounter = brains.book.encounter(speaker.encounterId)
  if encounter != nil:
    encounter.addLine(speaker.name, message)
    for houseIndex in encounter.members:
      if houseIndex in brains.villagers:
        brains.villagers[houseIndex].recordTalkLine(speaker.name, message)
  if speaker.pendingTalkName.len > 0:
    speaker.greetedToday.incl(speaker.pendingTalkName)

proc leaveEncounter*(brains: Brains, speaker: Villager) =
  ## Removes a gnome from their conversation; a leftover singleton leaves.
  let encounter = brains.book.encounter(speaker.encounterId)
  if encounter == nil:
    speaker.encounterId = 0
    return
  speaker.logConversation(
    "exit", "id=" & $encounter.id & " turn=" & $brains.turnIndex
  )
  encounter.removeMember(speaker.houseIndex)
  speaker.encounterId = 0
  brains.dissolveIfAlone(encounter)

proc applySocial(
  brains: Brains,
  villager: Villager,
  observation: Observation,
  decision: Decision
) =
  ## Starts, joins, speaks in, or leaves a conversation when the action
  ## is already in range. talk_to out of range waits for movement.
  case decision.action
  of Say:
    brains.speakInEncounter(villager, decision.message)
  of Bye:
    brains.speakInEncounter(villager, decision.message)
    brains.leaveEncounter(villager)
  of TalkTo:
    if villager.visiblePlayerNear(
      observation, decision.targetName, PersonStandRadius
    ):
      discard brains.joinOrStartTalk(villager, decision.targetName)
      brains.speakInEncounter(villager, decision.message)
      villager.pendingTalkName = ""
      villager.pendingTalkMessage = ""
  else:
    discard

proc tickTalks(brains: Brains, observations: Table[int, Observation]) =
  ## During movement, delivers a pending talk_to once the gnome is next
  ## to its target.
  for houseIndex, villager in brains.villagers.pairs:
    if houseIndex notin observations:
      continue
    if villager.pendingTalkName.len == 0 or villager.pendingTalkMessage.len == 0:
      continue
    let observation = observations[houseIndex]
    if not villager.visiblePlayerNear(
      observation, villager.pendingTalkName, PersonStandRadius
    ):
      continue
    discard brains.joinOrStartTalk(villager, villager.pendingTalkName)
    brains.speakInEncounter(villager, villager.pendingTalkMessage)
    villager.pendingTalkName = ""
    villager.pendingTalkMessage = ""

proc logPhase(brains: Brains, kind: string) =
  ## Stamps the current turn on every gnome for the chart.
  for villager in brains.villagers.values:
    villager.logTurn(kind, brains.turnIndex)

proc handleReply(
  brains: Brains,
  villager: Villager,
  observation: Observation,
  reply: BedrockReply,
  now: float
) =
  ## Applies one reply to its villager.
  villager.requestInFlight = false
  villager.lastHeldInterrupt = ""
  let took = formatFloat(now - villager.lastRequestAt, ffDecimal, 1)
  case reply.outcome
  of Usable:
    villager.appendHistory("assistant", reply.text)
    let decision = parseDecision(reply.text, villager.selfNames())
    if decision.malformed:
      villager.lastError = decision.error
      let wait = villager.noteTransientFailure(brains.budget, now)
      villager.logLlm("reply", "tag=" & reply.tag &
        " outcome=parse took=" & took & "s")
      villager.log("llm parse error " & decision.error & " reply=" &
        reply.text.replace("\n", " ") & ", retry in " &
        formatFloat(wait, ffDecimal, 1) & "s")
      villager.noteLog("reply could not be used: " & decision.error)
    else:
      villager.noteUsableReply()
      brains.budget.noteHealthy()
      var extra = "tag=" & reply.tag & " outcome=usable took=" & took & "s"
      if reply.usage.len > 0:
        extra.add(" " & reply.usage)
      if decision.valid and villager.modeAllows(decision):
        villager.logLlm("reply", extra)
        villager.applyDecision(
          observation, brains.layout, decision, fromModel = true
        )
        brains.applySocial(villager, observation, decision)
      else:
        let error =
          if decision.valid:
            villager.modeError(decision)
          else:
            decision.error
        villager.lastError = error
        extra.add(" ignored=wait")
        villager.logLlm("reply", extra)
        villager.recordEvent("Your action was ignored: " & error)
        villager.applyDecision(
          observation, brains.layout, waitDecision(), fromModel = true
        )
        villager.log("llm ignored " & error & ", waiting")
      villager.turnReady = true
  of Transient:
    villager.lastError = reply.error
    villager.logLlm("reply", "tag=" & reply.tag &
      " outcome=transient took=" & took & "s")
    villager.log("llm error status=" & $reply.statusCode & " " &
      reply.error.replace("\n", " "))
    villager.noteLog("llm error status=" & $reply.statusCode & " " &
      reply.error.replace("\n", " ") & " (will retry)")
    if reply.cacheRejected and brains.client.promptCacheEnabled:
      brains.client.promptCacheEnabled = false
      villager.log("llm prompt caching rejected, disabled for this game")
      villager.retryAt = now
    elif reply.contextTooLong:
      villager.shrinkHistory()
      villager.retryAt = now + ContextRetrySeconds
    else:
      let wait = villager.noteTransientFailure(
        brains.budget, now, reply.retryAfter, reply.dailyQuota
      )
      if reply.statusCode == 429:
        let throttle = brains.budget.noteThrottle(now, reply.retryAfter)
        villager.log("llm throttled, everyone waits " &
          formatFloat(throttle, ffDecimal, 1) & "s")
      villager.log(
        (if reply.dailyQuota: "llm daily quota spent" else: "llm retry") &
        " in " & formatFloat(wait, ffDecimal, 1) & "s (failure " &
        $villager.failures & ")"
      )
  of Permanent:
    villager.lastError = reply.error
    inc villager.permanentHits
    villager.logLlm("reply", "tag=" & reply.tag &
      " outcome=permanent took=" & took & "s")
    villager.log("llm error status=" & $reply.statusCode & " " &
      reply.error.replace("\n", " "))
    villager.noteLog("llm error status=" & $reply.statusCode & " " &
      reply.error.replace("\n", " "))
    if villager.permanentHits < PermanentConfirmations:
      villager.retryAt = now + PermanentRetrySeconds
      villager.log("llm permanent-looking error, one more try in " &
        $int(PermanentRetrySeconds) & "s")
    else:
      villager.failed = true
      villager.turnReady = true
      let message = "Bedrock rejected the soul's model '" &
        villager.soul.modelId & "' for seat " & $villager.houseIndex &
        ": HTTP " & $reply.statusCode & " " & reply.error.replace("\n", " ")
      villager.log("llm permanent error, seat fails: " & message)
      if brains.onSeatFailure != nil:
        brains.onSeatFailure(villager.houseIndex, message)

proc pollReplies(
  brains: Brains,
  observations: Table[int, Observation],
  now: float
) =
  ## Routes every completed reply to its villager.
  while true:
    let polled = brains.client.poll()
    if polled.isNone:
      break
    brains.budget.noteReply()
    let reply = polled.get()
    let villager = brains.villagerForTag(reply.tag)
    if villager == nil:
      echo "llm stale reply dropped tag=", reply.tag
      continue
    if villager.houseIndex notin observations:
      continue
    brains.handleReply(villager, observations[villager.houseIndex], reply, now)

proc scheduleRequests(
  brains: Brains,
  observations: Table[int, Observation],
  now: float
) =
  ## Starts requests for villagers that still owe an action this LLM turn.
  if brains.phase != LlmPhase:
    return
  var ready: seq[Villager]
  for houseIndex, villager in brains.villagers.pairs:
    if houseIndex notin observations:
      continue
    let observation = observations[houseIndex]
    if villager.requestInFlight or villager.failed or villager.turnReady:
      continue
    if observation.scene == Overlay:
      villager.turnReady = true
      continue
    if villager.waitingSinceTick < 0:
      villager.waitingSinceTick = observation.tick
    if now < villager.retryAt:
      continue
    ready.add(villager)
  ready.sort(proc(a, b: Villager): int =
    result = cmp(a.waitingSinceTick, b.waitingSinceTick)
    if result == 0:
      result = cmp(a.houseIndex, b.houseIndex))
  for villager in ready:
    if not brains.budget.canRequest(now):
      break
    brains.startRequest(villager, observations[villager.houseIndex], now)

proc everyoneReady(
  brains: Brains,
  observations: Table[int, Observation]
): bool =
  ## True when every seated gnome has a usable action or has failed.
  var counted = 0
  for houseIndex, villager in brains.villagers.pairs:
    if houseIndex notin observations:
      continue
    inc counted
    if observations[houseIndex].scene == Overlay:
      continue
    if villager.failed:
      continue
    if not villager.turnReady:
      return false
  counted > 0

proc advance*(
  brains: Brains,
  observations: Table[int, Observation],
  now: float
): BrainFrame =
  ## One frame: memories, LLM wait-for-all, or one movement tick.
  for houseIndex, villager in brains.villagers.pairs:
    if houseIndex notin observations:
      continue
    let observation = observations[houseIndex]
    villager.now = now
    if observation.dayNumber != villager.dayNumber and villager.dayNumber > 0:
      villager.abandonRequest()
      villager.turnReady = false
      brains.phase = LlmPhase
      brains.moveTicksLeft = 0
    villager.observeWorld(observation, brains.navigation, brains.layout)
  brains.pollReplies(observations, now)
  brains.scheduleRequests(observations, now)
  if brains.client.mockReply.len > 0:
    brains.pollReplies(observations, now)
  var overlay = false
  var counted = 0
  for houseIndex, villager in brains.villagers.pairs:
    if houseIndex notin observations:
      continue
    inc counted
    villager.modelUnavailable = villager.requestInFlight or
      now < villager.retryAt
    if observations[houseIndex].scene == Overlay:
      overlay = true
    elif not villager.turnReady and not villager.failed:
      result.blockedNames.add(villager.name)
  if counted == 0:
    result.paused = true
    return
  if overlay:
    result.paused = false
    for houseIndex, villager in brains.villagers.pairs:
      if houseIndex notin observations:
        continue
      result.outputs.add(BrainOutputFor(
        houseIndex: houseIndex,
        output: villager.villagerTick(
          observations[houseIndex], brains.navigation, brains.layout
        )
      ))
    return
  if brains.phase == LlmPhase:
    if brains.everyoneReady(observations):
      brains.phase = MovePhase
      inc brains.turnIndex
      brains.moveTicksLeft = MovementTurnTicks
      brains.logPhase("move")
    else:
      result.paused = true
      return
  brains.tickTalks(observations)
  result.paused = false
  for houseIndex, villager in brains.villagers.pairs:
    if houseIndex notin observations:
      continue
    result.outputs.add(BrainOutputFor(
      houseIndex: houseIndex,
      output: villager.villagerTick(
        observations[houseIndex], brains.navigation, brains.layout
      )
    ))
  dec brains.moveTicksLeft
  if brains.moveTicksLeft <= 0:
    brains.phase = LlmPhase
    inc brains.turnIndex
    for villager in brains.villagers.values:
      villager.turnReady = false
    brains.logPhase("llm")

proc dropWalkers*(
  brains: Brains,
  outdoorFeet,
  stillFeet: Table[int, Point]
) =
  ## A talking gnome who is outdoors but walking has left the huddle.
  ## One gnome left dissolves the conversation.
  var leavers: seq[int]
  for houseIndex, villager in brains.villagers.pairs:
    if not villager.talking:
      continue
    if houseIndex in outdoorFeet and houseIndex notin stillFeet:
      leavers.add(houseIndex)
  for houseIndex in leavers:
    brains.leaveEncounter(brains.villagers[houseIndex])

proc encounterCircles*(
  brains: Brains,
  feet: Table[int, Point]
): seq[tuple[x, y, radius: int]] =
  ## Sparkle-ring geometry for outdoor conversations this frame.
  brains.book.encounterCircles(feet)

proc syncConversationCircles*(
  brains: Brains,
  outdoorFeet,
  stillFeet: Table[int, Point]
): seq[tuple[x, y, radius: int]] =
  ## Drops walkers from chat mode, then returns frozen outdoor rings.
  brains.dropWalkers(outdoorFeet, stillFeet)
  brains.encounterCircles(stillFeet)

proc allFailed*(brains: Brains): bool =
  ## True when no villager can play any more.
  for villager in brains.villagers.values:
    if not villager.failed:
      return false
  brains.villagers.len > 0
