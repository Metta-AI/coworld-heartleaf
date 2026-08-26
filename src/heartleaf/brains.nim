## The villager brains runtime: one Villager per seat, the shared model
## client and request budget, and the per-frame advance that polls
## replies, starts requests, keeps promises, and produces every gnome's
## input for the tick. The simulation only pauses when every villager is
## waiting on the model with nothing left to do.

import
  std/[algorithm, options, strutils, tables],
  heartleaf/[decisions, observation, navigation, villager, executor, report,
    prompt, pacing, bedrock_client, souls]

const
  PermanentConfirmations = 2
  PermanentRetrySeconds = 5.0
  ContextRetrySeconds = 2.0

type
  SeatFailureHandler* = proc(seat: int, message: string) {.closure.}

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
      ## One-based game of this process; stamped on every log record.

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
    gameNumber: 1
  )

proc attachSoul*(brains: Brains, houseIndex: int, soul: Soul) =
  ## Brings one seat to life with its soul.
  var villager = newVillager(houseIndex, soul, brains.layout.gardens.len)
  villager.gameNumber = brains.gameNumber
  villager.systemPrompt = systemPrompt(soul, villager.name)
  villager.logSystemPrompt()
  brains.villagers[houseIndex] = villager
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
      observation, brains.navigation, brains.layout
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
    if decision.valid:
      villager.noteUsableReply()
      brains.budget.noteHealthy()
      var extra = "tag=" & reply.tag & " outcome=usable took=" & took & "s"
      if reply.usage.len > 0:
        extra.add(" " & reply.usage)
      villager.logLlm("reply", extra)
      villager.applyDecision(
        observation, brains.layout, decision, fromModel = true
      )
    else:
      villager.lastError = decision.error
      let wait = villager.noteTransientFailure(brains.budget, now)
      villager.logLlm("reply", "tag=" & reply.tag &
        " outcome=parse took=" & took & "s")
      villager.log("llm parse error " & decision.error & " reply=" &
        reply.text.replace("\n", " ") & ", retry in " &
        formatFloat(wait, ffDecimal, 1) & "s")
      villager.noteLog("reply could not be used: " & decision.error)
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
  ## Starts requests for villagers that need a decision, or that still
  ## owe a retry after a failed call. Fairest first: those with no
  ## decision at all, then the longest waiting. A retry waits only for
  ## backoff, not for the current action to finish.
  var ready: seq[Villager]
  for houseIndex, villager in brains.villagers.pairs:
    if houseIndex notin observations:
      continue
    let observation = observations[houseIndex]
    if villager.requestInFlight or villager.failed:
      continue
    if observation.scene == Overlay:
      continue
    if not villager.retryPending:
      if not villager.needsFreshDecision(observation, brains.layout):
        villager.waitingSinceTick = -1
        continue
    if villager.waitingSinceTick < 0:
      villager.waitingSinceTick = observation.tick
    if now < villager.retryAt:
      continue
    if now - villager.lastRequestAt < brains.budget.villagerMinSeconds:
      continue
    ready.add(villager)
  ready.sort(proc(a, b: Villager): int =
    result = cmp(a.hasDecision, b.hasDecision)
    if result == 0:
      result = cmp(a.waitingSinceTick, b.waitingSinceTick)
    if result == 0:
      result = cmp(a.houseIndex, b.houseIndex))
  for villager in ready:
    if not brains.budget.canRequest(now):
      break
    brains.startRequest(villager, observations[villager.houseIndex], now)

proc advance*(
  brains: Brains,
  observations: Table[int, Observation],
  now: float
): BrainFrame =
  ## One frame of thinking for every villager: update memories, collect
  ## replies, start requests, keep promises, and, unless everyone is
  ## waiting on the model, produce each gnome's input for the tick.
  for houseIndex, villager in brains.villagers.pairs:
    if houseIndex notin observations:
      continue
    let observation = observations[houseIndex]
    villager.now = now
    if observation.dayNumber != villager.dayNumber and villager.dayNumber > 0:
      villager.abandonRequest()
    villager.observeWorld(observation, brains.navigation, brains.layout)
    villager.maybeLogHeldInterrupt(observation, brains.layout)
  brains.pollReplies(observations, now)
  brains.scheduleRequests(observations, now)
  if brains.client.mockReply.len > 0:
    brains.pollReplies(observations, now)
  let budgetOpen = brains.budget.canRequest(now)
  var anyExecutable = false
  var counted = 0
  for houseIndex, villager in brains.villagers.pairs:
    if houseIndex notin observations:
      continue
    let observation = observations[houseIndex]
    villager.modelUnavailable = villager.requestInFlight or
      now < villager.retryAt or not budgetOpen
    villager.keepPromise(observation, brains.navigation, brains.layout)
    inc counted
    if observation.scene == Overlay or
        villager.hasExecutableDecision(observation):
      anyExecutable = true
    else:
      result.blockedNames.add(villager.name)
  # An empty village waits too: the morning starts when the first soul
  # arrives, not while the seats are still filling.
  result.paused = not anyExecutable
  if result.paused:
    return
  for houseIndex, villager in brains.villagers.pairs:
    if houseIndex notin observations:
      continue
    result.outputs.add(BrainOutputFor(
      houseIndex: houseIndex,
      output: villager.villagerTick(
        observations[houseIndex], brains.navigation, brains.layout
      )
    ))

proc allFailed*(brains: Brains): bool =
  ## True when no villager can play any more.
  for villager in brains.villagers.values:
    if not villager.failed:
      return false
  brains.villagers.len > 0
