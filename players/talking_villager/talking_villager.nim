import
  std/[algorithm, json, math, options, os, parseopt, sets, strutils, times],
  bitworld/[spriteprotocol, resources],
  curly, pathy, supersnappy, whisky,
  bedrock_auth, decisions, heartleaf/[common, protocol]

const

  BedrockVersion = "bedrock-2023-05-31"
  DefaultBedrockRegion = "us-east-1"
  DefaultBedrockModel = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  DefaultBedrockTimeoutSeconds = 15
  ReconnectDelayMs = 1000
  ReconnectGiveUpSeconds = 8.0
  DefaultBedrockMaxTokens = 192
  BedrockTemperature = 0.2



  CollectActionRadius = InteractionRadius - 8
  PersonStandRadius = 30
  GoalArrivePixels = 2
  PathArrivePixels = 3
  PathRejoinPixels = 8

  MoveDeadZonePixels = 1
  PathDensifyPixels = 4
  SteerLookaheadPoints = 12
  UnstuckAfterTicks = 30
  UnstuckDurationTicks = 24
  RepathStuckTicks = 48
  MaxDrainMessages = 256
  DefaultName = "talking_villager"
  UnknownHouse = -1
  DecisionRetryTicks = 24
  DecisionStuckTicks = RepathStuckTicks * 2
  ## Transcript cap in lines. A nine-day game produces roughly 120 hourly
  ## clock lines plus 50-120 own chats plus whatever is overheard, so 600
  ## is rarely reached; when it is, whole oldest days are dropped.
  ChatHistoryLimit = 600
  ## Recent lines compared for near-duplicate chat suppression.
  RecentChatLines = 8
  ChatSimilarityThreshold = 0.85
  ## Food bands for interrupt detection only: crossing a band re-asks the
  ## LLM because "how much I carry" changed enough to matter.
  LowFoodBand = 2
  HighFoodBand = 6
  DoorGatherSlots = 5
  DoorGatherSpacing = 18
  ## After this many minutes past dinner without a dinner overlay the bot
  ## records that it missed dinner.
  DinnerMissedGraceMinutes = 5
  ## Walk-time estimates for the state report: top speed in pixels per
  ## tick from the sim (MaxSpeed 704 / MotionScale 256), a fudge for
  ## acceleration, corners, and doors, and ticks per game minute from
  ## the same DayTicks the sim uses, until the bot has measured the
  ## real clock rate.
  WalkPixelsPerTick = 2.75
  WalkTimeFudge = 1.5
  DefaultTicksPerMinute = float(DayTicks) / float(DayTotalMinutes)
  ClockRateMinMinutes = 15
  LeaveMarginMinutes = 30
  LeaveNudgeMinutes = 30
  HouseGatherMaxRadius = 96
  MorningIdentityUntilMinutes = 9 * 60
  MorningIdentityRadius = 140


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
  ScreenKind = enum
    UnknownScreen
    MainMap
    HomeMap
    OverlayScreen

  SpriteKind = enum
    SpriteUnknown
    SpriteMainBottom
    SpriteHomeBottom
    SpriteMainWalk
    SpriteHomeWalk
    SpriteGarden
    SpriteGnome
    SpriteName
    SpriteChat
    SpriteClock
    SpriteOverlay

  GoalKind = enum
    GoalIdle
    GoalCollect
    GoalGatherHouse
    GoalEnterHouse
    GoalExitHouse
    GoalStandPerson
    GoalMove

  Goal = object
    kind: GoalKind
    screenKind: ScreenKind
    x, y: int
    houseIndex: int
    gardenIndex: int
    targetName: string

  SpriteInfo = ref object
    defined: bool
    width, height: int
    label: string
    kind: SpriteKind
    glyph: char
    pixels: seq[uint8]

  ObjectState = object
    present: bool
    x, y, z: int
    layer: int
    spriteId: int

  Resources = ref object
    gardens: seq[Rect]
    houses: array[9, Rect]
    houseValid: array[9, bool]
    exit: Rect
    hasExit: bool

  ConversationMessage = object
    role: string
    content: string

  BedrockResult = object
    done: bool
    ok: bool
    statusCode: int
    tag: string
    reply: string
    error: string
    ## Token accounting from the response, for throttling diagnosis.
    usage: string
    ## Seconds the endpoint asked us to wait (Retry-After), 0 when absent.
    retryAfter: float

  TalkingVillagerError = object of CatchableError

  ChatLine = object
    normalized: string
    targetName: string

  Bot = ref object
    name: string
    playerName: string
    soulTemplate: string
    soulInstructions: string
    slot: int
    homeIndex: int
    sprites: seq[SpriteInfo]
    objects: seq[ObjectState]
    resources: Resources
    mainNav: JumpPointSpace
    homeNav: JumpPointSpace
    screenKind: ScreenKind
    previousScreenKind: ScreenKind
    currentHouse: int
    pendingHouse: int
    cameraX, cameraY: int
    localized: bool
    selfIndex: int
    selfX, selfY: int
    previousX, previousY: int
    previous2X, previous2Y: int
    velEstX, velEstY: int
    stuckTicks: int
    unstuckTicks: int
    unstuckMaskIndex: int
    minutes: int
    lastMask: uint8
    attackCooldown: int
    lastCollectTick: int
    goal: Goal
    path: seq[Point]
    gardenChecked: seq[bool]
    lastClockHour: int
    chatHistory: seq[ConversationMessage]
    heardChats: seq[string]
    currentGarden: int
    dayIndex: int
    dayEndRecorded: bool
    ## Gnome names seen and greeted since this morning; both reset daily.
    seenToday: HashSet[string]
    greetedToday: HashSet[string]
    ## Set by one-shot events (first sighting, departure time) that
    ## should re-ask the LLM; cleared when a decision is applied.
    interruptRequested: bool
    ## Last inventory text written to the transcript, so a change is
    ## recorded once rather than every frame.
    lastCarryText: string
    ## Dinner bookkeeping: what the bot still wanted at 6pm, where it
    ## was, and whether the result was written to the transcript.
    dinnerLookingBefore: string
    dinnerHouse: int
    dinnerRecorded: bool
    ## Measured game-clock rate so walk times can be given in game
    ## minutes: anchor tick and minute of the day, and the estimate.
    clockAnchorTick: int
    clockAnchorMinutes: int
    ticksPerMinute: float
    ## Set once per day when the latest departure time for dinner passes,
    ## so that moment interrupts the current action exactly once.
    leaveTimeNoted: bool
    leaveTimeNotedMinutes: int
    frameTick: int
    desiredMask: uint8
    target: Point
    hasTarget: bool
    decision: LlmDecision
    hasDecision: bool
    decisionChatSent: bool
    decisionStartedTick: int
    decisionState: string
    decisionFoodBand: int
    decisionTimePhase: int
    decisionChatSignature: string
    decisionCrowdSignature: string
    ## Gnomes visible when the current decision was made; anyone else
    ## walking into view while the bot waits at a door is a passer-by
    ## worth interrupting for.
    decisionVisibleNames: HashSet[string]
    ## Chat lines said today, newest last, for the state report and the
    ## repeated-line guard.
    saidToday: seq[string]
    ## Normalized chat lines and targets said during the whole game,
    ## newest last.
    saidGame: seq[ChatLine]
    chatSentCount: int
    chatSuppressedCount: int
    llmWaiting: bool
    llmTag: string
    llmSerial: int
    lastLlmError: string
    llmPacer: LlmPacer
    committedPartyHouse: int


var bedrockCurl = newCurly(1)

proc bedrockRegion(): string =
  ## Returns the configured AWS Region for Bedrock.
  result = getEnv("AWS_REGION").strip()
  if result.len == 0:
    result = getEnv("AWS_DEFAULT_REGION").strip()
  if result.len == 0:
    result = DefaultBedrockRegion

proc bedrockModel(): string =
  ## Returns the configured Bedrock model id.
  result = getEnv("BEDROCK_MODEL").strip()
  if result.len == 0:
    result = DefaultBedrockModel

proc bedrockToken(): string =
  ## Returns the configured Bedrock bearer token.
  result = getEnv("AWS_BEARER_TOKEN_BEDROCK").strip()
  if result.len == 0:
    result = getEnv("BEDROCK_KEY").strip()

proc mockBedrockReply(): string =
  ## Returns a configured mock LLM reply for smoke tests.
  getEnv("TALKING_VILLAGER_MOCK_REPLY").strip()

proc bedrockTimeoutSeconds(): int =
  ## Returns the configured Bedrock request timeout.
  let value = getEnv("BEDROCK_TIMEOUT_SECONDS").strip()
  if value.len == 0:
    return DefaultBedrockTimeoutSeconds
  try:
    max(1, int(parseFloat(value)))
  except ValueError:
    DefaultBedrockTimeoutSeconds

proc bedrockMaxTokens(): int =
  ## Returns the configured maximum Bedrock response tokens.
  let value = getEnv("BEDROCK_MAX_TOKENS").strip()
  if value.len == 0:
    return DefaultBedrockMaxTokens
  try:
    max(32, parseInt(value))
  except ValueError:
    DefaultBedrockMaxTokens

proc bedrockPerformanceLatency(): string =
  ## Returns the optional Bedrock latency performance setting.
  let value = getEnv("BEDROCK_PERFORMANCE_LATENCY").strip().toLowerAscii()
  if value == "standard" or value == "optimized":
    return value

proc requireBedrockConfig() =
  ## Raises when live Bedrock cannot be called.
  if mockBedrockReply().len > 0:
    return
  if bedrockToken().len == 0 and not hasAwsCredentialSignal():
    raise newException(TalkingVillagerError, BedrockNotConfiguredMessage)

proc transientBedrockError(answer: BedrockResult): bool =
  ## Returns true for Bedrock failures worth retrying later.
  let message = answer.error.toLowerAscii()
  if answer.statusCode == 408 or
      answer.statusCode == 429 or
      answer.statusCode == 500 or
      answer.statusCode == 502 or
      answer.statusCode == 503 or
      answer.statusCode == 504:
    return true
  if message.contains("timeout") or
      message.contains("timed out") or
      message.contains("timeout was reached") or
      message.contains("operation timed out") or
      message.contains("temporarily unavailable") or
      message.contains("service unavailable") or
      message.contains("throttl") or
      message.contains("rate exceeded") or
      message.contains("too many requests") or
      message.contains("connection reset") or
      message.contains("couldn't connect") or
      message.contains("could not connect"):
    return true

proc dailyQuotaError(answer: BedrockResult): bool =
  ## Returns true when the throttle is the account's daily token quota
  ## ("Too many tokens per day"), which will not clear for a long time.
  let message = answer.error.toLowerAscii()
  message.contains("per day") or message.contains("daily")

proc permanentBedrockError(answer: BedrockResult): bool =
  ## Returns true for Bedrock failures that should stop the bot: the
  ## request itself is rejected (bad model id, bad credentials, prompt too
  ## long), so retrying can only fail the same way. Anything else, including
  ## a 200 whose body we could not use, is worth playing through.
  if answer.transientBedrockError():
    return false
  if answer.statusCode == 200:
    return false
  if answer.statusCode == 400 or
      answer.statusCode == 401 or
      answer.statusCode == 403 or
      answer.statusCode == 404:
    return true
  let message = answer.error.toLowerAscii()
  if message.contains("too many tokens") or
      message.contains("input is too long") or
      message.contains("context length") or
      message.contains("maximum context") or
      message.contains("token limit") or
      message.contains("validationexception") or
      message.contains("resourcenotfoundexception") or
      message.contains("accessdenied") or
      message.contains("unauthorized") or
      message.contains("forbidden") or
      message.contains("not authorized"):
    return true

proc bedrockHost(): string =
  ## Returns the Bedrock Runtime host for the selected Region.
  "bedrock-runtime." & bedrockRegion() & ".amazonaws.com"

proc bedrockPath(): string =
  ## Returns the REST path for a Bedrock InvokeModel request.
  "/model/" & bedrockModel().awsUriEncode() & "/invoke"

proc bedrockUrl(): string =
  ## Builds the Bedrock Runtime InvokeModel URL.
  let sidecar = sidecarEndpoint()
  if sidecar.len > 0:
    return sidecar.joinUrl(bedrockPath())
  "https://" & bedrockHost() & bedrockPath()

proc bedrockHeaders(body: string): HttpHeaders =
  ## Builds one Bedrock HTTP header set for the signed request body.
  if hasSidecarEndpoint():
    result["Accept"] = "application/json"
    result["Content-Type"] = "application/json"
  elif bedrockToken().len > 0:
    result["Authorization"] = "Bearer " & bedrockToken()
    result["Accept"] = "application/json"
    result["Content-Type"] = "application/json"
  else:
    for (key, value) in signedBedrockHeaders(
      body, bedrockHost(), bedrockPath(), bedrockRegion()
    ):
      result[key] = value
  let latency = bedrockPerformanceLatency()
  if latency.len > 0:
    result["X-Amzn-Bedrock-PerformanceConfig-Latency"] = latency

var promptCacheEnabled = getEnv("BEDROCK_PROMPT_CACHE").strip() != "0"
  ## Prompt caching marks the soul and the transcript tail as cache
  ## breakpoints so the ever-growing transcript prefix is read from cache
  ## instead of being re-billed and re-counted against the shared quota on
  ## every request. Set BEDROCK_PROMPT_CACHE=0 to send plain requests; the
  ## bot also switches it off by itself if Bedrock rejects the field.

proc textBlock(text: string, cached: bool): JsonNode =
  ## Returns one Messages API text content block.
  result = %*{"type": "text", "text": text}
  if cached:
    result["cache_control"] = %*{"type": "ephemeral"}

proc bedrockBody(messages: openArray[ConversationMessage]): string =
  ## Builds one Anthropic Messages request body for Bedrock.
  ## Consecutive same-role messages are joined because the Anthropic
  ## Messages API requires user and assistant turns to alternate. The
  ## final message is the state report; it stays its own content block so
  ## the transcript before it can end with a cache breakpoint.
  var
    systemPrompt = ""
    chatMessages = newJArray()
  for i, message in messages:
    if message.role == "system":
      systemPrompt = message.content
      continue
    let isStateReport = i == messages.len - 1
    if chatMessages.elems.len == 0 and message.role == "assistant":
      chatMessages.add(%*{
        "role": "user",
        "content": [textBlock("(The day begins.)", false)]
      })
    if chatMessages.elems.len > 0 and
        chatMessages.elems[^1]["role"].getStr() == message.role and
        not isStateReport:
      let last = chatMessages.elems[^1]["content"].elems[^1]
      last["text"] = %(last["text"].getStr() & "\n" & message.content)
    elif chatMessages.elems.len > 0 and
        chatMessages.elems[^1]["role"].getStr() == message.role:
      chatMessages.elems[^1]["content"].add(
        textBlock(message.content, false)
      )
    else:
      chatMessages.add(%*{
        "role": message.role,
        "content": [textBlock(message.content, false)]
      })
  if promptCacheEnabled:
    ## Breakpoint on the last transcript block: the block right before
    ## the state report, which may live in the same user message.
    let lastMessage = chatMessages.elems[^1]
    let blocks = lastMessage["content"].elems
    if blocks.len >= 2:
      blocks[^2]["cache_control"] = %*{"type": "ephemeral"}
    elif chatMessages.elems.len >= 2:
      chatMessages.elems[^2]["content"].elems[^1]["cache_control"] =
        %*{"type": "ephemeral"}
  let body = %*{
    "anthropic_version": BedrockVersion,
    "max_tokens": bedrockMaxTokens(),
    "temperature": BedrockTemperature,
    "system": [textBlock(systemPrompt, promptCacheEnabled)],
    "messages": chatMessages
  }
  if not hasSidecarEndpoint():
    body["requestMetadata"] = bedrockRequestMetadata("talking_villager")
  $body

proc parseBedrockReply(body: string): string =
  ## Extracts output text from one Bedrock response body.
  let data = parseJson(body)
  for part in data["content"]:
    if part{"type"}.getStr() == "text":
      result.add(part["text"].getStr())

proc bedrockUsageText(body: string): string =
  ## Summarizes the usage block of one response as "in=N cacheRead=N
  ## cacheWrite=N out=N" so logs show how big prompts are and whether the
  ## prompt cache is hit.
  try:
    let usage = parseJson(body){"usage"}
    if usage == nil or usage.kind != JObject:
      return ""
    "in=" & $usage{"input_tokens"}.getInt() &
      " cacheRead=" & $usage{"cache_read_input_tokens"}.getInt() &
      " cacheWrite=" & $usage{"cache_creation_input_tokens"}.getInt() &
      " out=" & $usage{"output_tokens"}.getInt()
  except CatchableError:
    ""

proc startTalkToBedrock(
  messages: openArray[ConversationMessage],
  tag: string
): bool =
  ## Starts a non-blocking Bedrock request.
  if bedrockToken().len == 0 and not hasAwsCredentialSignal():
    return false
  let body = bedrockBody(messages)
  bedrockCurl.startRequest(
    "POST",
    bedrockUrl(),
    bedrockHeaders(body),
    body,
    bedrockTimeoutSeconds(),
    tag
  )
  return true

proc pollTalkToBedrock(): BedrockResult =
  ## Polls for one completed Bedrock response.
  let answer = bedrockCurl.pollForResponse()
  if answer.isNone:
    return BedrockResult(done: false)
  result.done = true
  result.tag = answer.get.response.request.tag
  if answer.get.error.len > 0:
    result.error = answer.get.error
    return
  let response = answer.get.response
  result.statusCode = response.code
  if response.code != 200:
    result.error = response.body
    ## Retry-After in seconds; HTTP-date forms are ignored.
    if response.headers.contains("Retry-After"):
      try:
        result.retryAfter = parseFloat(response.headers["Retry-After"].strip())
      except ValueError:
        discard
    return
  try:
    result.reply = response.body.parseBedrockReply()
    result.usage = response.body.bedrockUsageText()
  except CatchableError as e:
    result.error = e.msg
    return
  if result.reply.len == 0:
    result.error = "Bedrock response did not include text."
    return
  result.ok = true

proc repoDir(): string =
  ## Returns the Heartleaf repository directory.
  currentSourcePath().parentDir().parentDir().parentDir()

## Fixed notes about the state report and the actions. They live in the
## system prompt rather than in every state report so the prompt cache
## covers them and each request only re-sends what changed.
const StateReportReference =
  "State report reference:\n" &
  "timeMinutes is minutes after midnight; " & $DinnerMinutes &
  " is 6:00pm when dinner is served, " & $DayEndMinutes &
  " is 10:00pm when the day ends.\n" &
  "walkMinutesToHouse lists game minutes of walking from where you " &
  "stand to each house door; leave that early, plus a margin, to be " &
  "inside before a time. leaveForOwnHouseBy (only matters when you " &
  "host at home), leaveForCommittedPartyBy, and leaveForNightBy are " &
  "the latest clock times to start walking to be inside before dinner " &
  "or before the day ends at 10:00pm.\n" &
  "location says whether you are inside a house or outside; only " &
  "gnomes inside a house at 6:00pm eat.\n" &
  "visiblePlayers are the gnomes on screen with their positions and " &
  "current chat bubbles; visibleHouseCrowds counts gnomes near each " &
  "house door; gardenMarkers are gardens with food left.\n" &
  "yourLinesToday are lines you already said today; greetedToday and " &
  "seenTodayNotGreeted track whom you have greeted.\n" &
  "Actions: keep_gathering_plants walks the gardens outside; " &
  "find_person / stand_next_to_person / say_to_person walk to " &
  "targetName and stay by them, say_to_person says message only once " &
  "you are next to them; if targetName is not in visiblePlayers you " &
  "walk toward their house when you are outside, and simply wait when " &
  "you are inside a house (to go outside use keep_gathering_plants, " &
  "find_house or stand_at_house_garden); " &
  "find_house / stand_at_house_garden wait OUTSIDE the door of " &
  "houseIndex and leave the house if you are inside; " &
  "go_home goes INSIDE your own house and stays (it walks you OUT of " &
  "any other house first); go_to_party goes INSIDE houseIndex and " &
  "stays; stay_inside stays right where you are inside a house (from " &
  "outside it walks to the house you promised, else home). To be " &
  "inside for dinner use go_to_party, stay_inside, or go_home when you " &
  "host; every other action puts you outside.\n" &
  "untilTime is an optional field, a clock like 5:15pm; the action " &
  "then keeps going until that time (wait at a door, gather, stay " &
  "home) instead of ending when reached; while you wait at a door " &
  "you are asked again whenever a gnome walks into view.\n" &
  "commitParty true with houseIndex records a promise to be at that " &
  "house for dinner; if you cannot be asked when the time comes, the " &
  "promise is carried out for you."

proc loadSoulInstructions(bot: Bot, name: string): string =
  ## Builds the full system prompt for one player name: the soul with
  ## the name filled in, plus the fixed state report reference.
  let cleanName =
    if name.strip().len > 0:
      name.strip()
    else:
      "a Heartleaf gnome"
  result =
    if bot.soulTemplate.contains("{name}"):
      bot.soulTemplate.replace("{name}", cleanName)
    else:
      "Your name is " & cleanName & ".\n\n" & bot.soulTemplate
  result.add("\n\n" & StateReportReference)

proc loadBotResources(): Resources =
  ## Loads house, garden, and home-exit resource rectangles.
  result = Resources()
  let root = repoDir()
  for rect in loadResourceRects(root / "data" / "map.resource"):
    let name = rect.rectName()
    if name == "garden":
      result.gardens.add(rect.toRect())
    else:
      let index = name.houseIndexFromName()
      if index >= 0:
        result.houses[index] = rect.toRect()
        result.houseValid[index] = true
  for rect in loadResourceRects(root / "data" / "home_map.resource"):
    if rect.rectName() == "exit":
      result.exit = rect.toRect()
      result.hasExit = true

proc screenRectVisible(x, y, w, h: int): bool =
  ## Returns true when one screen-space rectangle overlaps the viewport.
  x < ViewportWidth and y < ViewportHeight and x + w > 0 and y + h > 0

proc playerFootX(bot: Bot): int =
  ## Returns the bot foot-center X coordinate.
  bot.selfX.footXAt()

proc playerFootY(bot: Bot): int =
  ## Returns the bot foot-center Y coordinate.
  bot.selfY.footYAt()

proc objectWorldX(bot: Bot, objectState: ObjectState): int =
  ## Converts one object X coordinate to current-map coordinates.
  objectState.x + bot.cameraX

proc objectWorldY(bot: Bot, objectState: ObjectState): int =
  ## Converts one object Y coordinate to current-map coordinates.
  objectState.y + bot.cameraY

proc objectFootX(bot: Bot, objectState: ObjectState): int =
  ## Converts one object X coordinate to current-map foot center.
  bot.objectWorldX(objectState).footXAt()

proc objectFootY(bot: Bot, objectState: ObjectState): int =
  ## Converts one object Y coordinate to current-map foot center.
  bot.objectWorldY(objectState).footYAt()

proc spriteInfo(bot: Bot, spriteId: int): SpriteInfo =
  ## Returns sprite metadata for one sprite id.
  if spriteId >= 0 and spriteId < bot.sprites.len:
    return bot.sprites[spriteId]

proc logName(bot: Bot): string =
  ## Returns the username and fixed player name for bot logs.
  if bot.playerName.len == 0:
    return bot.name
  bot.name & " (" & bot.playerName & ")"

proc clockText(bot: Bot): string =
  ## Reads the current clock text from visible glyph objects.
  var glyphs: seq[tuple[x: int, ch: char]]
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < ClockObjectBase or objectId >= ScoreObjectBase:
      continue
    let sprite = bot.spriteInfo(objectState.spriteId)
    if sprite == nil or sprite.kind != SpriteClock:
      continue
    glyphs.add((x: objectState.x, ch: sprite.glyph))
  glyphs.sort(proc(a, b: tuple[x: int, ch: char]): int = cmp(a.x, b.x))
  for glyph in glyphs:
    result.add(glyph.ch)
  result = result.strip()

proc log(bot: Bot, text: string) =
  ## Writes one bot activity log line.
  echo bot.logName(), ": ", text, " (", bot.clockText(), ")"

proc logChatSummary(bot: Bot) =
  ## Logs chat sends and duplicate suppressions for the whole game.
  bot.log("chat summary: said=" & $bot.chatSentCount & " suppressed=" &
    $bot.chatSuppressedCount)

proc visiblePlayerName(bot: Bot, playerIndex: int): string =
  ## Returns the visible name for one player index.
  let objectId = NameObjectBase + playerIndex
  if objectId < 0 or objectId >= bot.objects.len:
    return
  let objectState = bot.objects[objectId]
  if not objectState.present:
    return
  let sprite = bot.spriteInfo(objectState.spriteId)
  if sprite == nil or not sprite.label.startsWith(NameLabelPrefix):
    return
  sprite.label[NameLabelPrefix.len .. ^1]

proc visiblePlayerIndexByName(bot: Bot, name: string): int =
  ## Returns the visible player index for one fixed player name.
  result = -1
  let target = name.strip()
  if target.len == 0:
    return
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if bot.visiblePlayerName(playerIndex) == target:
      return playerIndex

proc visibleChatText(bot: Bot, playerIndex: int): string =
  ## Returns the visible chat bubble text for one player.
  let objectId = ChatObjectBase + playerIndex
  if objectId < 0 or objectId >= bot.objects.len:
    return
  let objectState = bot.objects[objectId]
  if not objectState.present:
    return
  let sprite = bot.spriteInfo(objectState.spriteId)
  if sprite == nil or not sprite.label.startsWith(ChatLabelPrefix):
    return
  sprite.label[ChatLabelPrefix.len .. ^1]

proc recordChatLine(bot: Bot, role, speaker, text: string) =
  ## Appends one heard or spoken chat line to the conversation history.
  bot.chatHistory.add(ConversationMessage(
    role: role,
    content: speaker & ": " & text
  ))

proc selfNames(bot: Bot): seq[string] =
  ## Returns the names this bot goes by, for stripping self labels.
  if bot.playerName.len > 0:
    result.add(bot.playerName)
  if bot.name.len > 0 and bot.name != bot.playerName:
    result.add(bot.name)

proc recordOwnChat(bot: Bot, text: string) =
  ## Records one chat message this bot said out loud. Own turns are
  ## stored as bare text: the soul tells the model that its earlier turns
  ## are what it said out loud, and a "Name:" label here is exactly what
  ## the model would imitate in its next line.
  bot.chatHistory.add(ConversationMessage(role: "assistant", content: text))

proc recordEvent(bot: Bot, text: string) =
  ## Records one world event the bot noticed, as a parenthesized user
  ## line: day boundaries, first sightings, what it carries, dinner.
  bot.chatHistory.add(ConversationMessage(
    role: "user",
    content: "(" & text & ")"
  ))

proc recordOwnDecision(bot: Bot, text: string) =
  ## Records what the bot decided to do, as a parenthesized own turn, so
  ## later prompts remember actions and not only spoken lines.
  bot.chatHistory.add(ConversationMessage(
    role: "assistant",
    content: "(" & text & ")"
  ))

proc dayBeginsLine(day: int): string =
  ## Returns the transcript marker that opens one day.
  "Day " & $day & " begins."

proc trimChatHistory(bot: Bot) =
  ## Keeps the transcript bounded. When it grows past ChatHistoryLimit,
  ## whole oldest days are dropped, cutting at a "Day N begins." marker so
  ## the model never sees half a day.
  if bot.chatHistory.len <= ChatHistoryLimit:
    return
  let excess = bot.chatHistory.len - ChatHistoryLimit
  var cut = -1
  for i in excess ..< bot.chatHistory.len:
    let content = bot.chatHistory[i].content
    if content.startsWith("(Day ") and content.endsWith(" begins.)"):
      cut = i
      break
  if cut <= 0:
    return
  bot.log("transcript trimmed " & $cut & " lines before day marker")
  bot.chatHistory = bot.chatHistory[cut .. ^1]

proc scanHeardChats(bot: Bot) =
  ## Records newly visible chat bubbles from other players.
  for objectId, objectState in bot.objects:
    if objectId < ChatObjectBase or objectId >= GardenObjectBase:
      continue
    let playerIndex = objectId - ChatObjectBase
    while playerIndex >= bot.heardChats.len:
      bot.heardChats.add("")
    if not objectState.present:
      bot.heardChats[playerIndex] = ""
      continue
    let text = bot.visibleChatText(playerIndex)
    if text == bot.heardChats[playerIndex]:
      continue
    bot.heardChats[playerIndex] = text
    if text.len == 0 or playerIndex == bot.selfIndex:
      continue
    let speaker = bot.visiblePlayerName(playerIndex)
    if speaker.len == 0 or speaker == bot.playerName:
      continue
    bot.recordChatLine("user", speaker, text)

proc scanSeenGnomes(bot: Bot) =
  ## Records the first sighting of each other gnome today and flags it so
  ## the current action can be interrupted to say hello.
  if not bot.localized:
    return
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if playerIndex == bot.selfIndex:
      continue
    let name = bot.visiblePlayerName(playerIndex)
    if name.len == 0 or name == bot.playerName:
      continue
    if name in bot.seenToday:
      continue
    bot.seenToday.incl(name)
    bot.interruptRequested = true
    bot.recordEvent("You see " & name & " for the first time today.")
    bot.log("first sighting " & name)

proc ensureSprite(bot: Bot, spriteId: int) =
  ## Ensures the sprite table can contain one sprite id.
  if spriteId >= bot.sprites.len:
    bot.sprites.setLen(spriteId + 1)

proc ensureObject(bot: Bot, objectId: int) =
  ## Ensures the object table can contain one object id.
  if objectId >= bot.objects.len:
    bot.objects.setLen(objectId + 1)

proc readU16(blob: string, offset: int): int =
  ## Reads one little-endian unsigned 16-bit value.
  int(uint16(blob[offset].uint8) or
    (uint16(blob[offset + 1].uint8) shl 8))

proc readI16(blob: string, offset: int): int =
  ## Reads one little-endian signed 16-bit value.
  let value = uint16(blob[offset].uint8) or
    (uint16(blob[offset + 1].uint8) shl 8)
  return int(cast[int16](value))

proc readU32(blob: string, offset: int): int =
  ## Reads one little-endian unsigned 32-bit value.
  int(uint32(blob[offset].uint8) or
    (uint32(blob[offset + 1].uint8) shl 8) or
    (uint32(blob[offset + 2].uint8) shl 16) or
    (uint32(blob[offset + 3].uint8) shl 24))

proc classifySprite(label: string): tuple[kind: SpriteKind, glyph: char] =
  ## Classifies one Heartleaf sprite protocol label.
  let lower = label.toLowerAscii()
  result = (kind: SpriteUnknown, glyph: '\0')
  if lower == MainWalkabilityLabel:
    result.kind = SpriteMainWalk
  elif lower == HomeWalkabilityLabel:
    result.kind = SpriteHomeWalk
  elif lower.startsWith(HomeBottomLabelPrefix):
    result.kind = SpriteHomeBottom
  elif lower.startsWith(MainBottomLabelPrefix):
    result.kind = SpriteMainBottom
  elif lower == GardenMarkerLabel:
    result.kind = SpriteGarden
  elif lower.startsWith(GnomeLabelPrefix):
    result.kind = SpriteGnome
  elif lower.startsWith(NameLabelPrefix):
    result.kind = SpriteName
  elif lower.startsWith(ChatLabelPrefix):
    result.kind = SpriteChat
  elif lower.startsWith(ClockLabelPrefix):
    result.kind = SpriteClock
    if label.len > ClockLabelPrefix.len:
      result.glyph = label[ClockLabelPrefix.len]
    else:
      result.glyph = ' '
  elif lower.startsWith(ScoreLabelPrefix) or lower.startsWith(DinnerLabelPrefix):
    result.kind = SpriteOverlay

proc needsPixels(kind: SpriteKind): bool =
  ## Returns true when the bot needs sprite pixels for navigation.
  kind in {SpriteMainWalk, SpriteHomeWalk}

proc buildNavSpace(sprite: SpriteInfo): JumpPointSpace =
  ## Builds a pathy JPS+ space from one walkability sprite.
  var walkMask = newSeq[bool](sprite.width * sprite.height)
  for i in 0 ..< walkMask.len:
    walkMask[i] = sprite.pixels[i * 4 + 3] > 0
  newJumpPointSpace(walkMask, sprite.width, sprite.height, DiagonalPath)

proc nearestPassablePoint(nav: JumpPointSpace, x, y: int): Point =
  ## Returns the nearest walkable foot pixel to a position.
  result = Point(
    x: x.clamp(0, nav.path.width - 1),
    y: y.clamp(0, nav.path.height - 1)
  )
  if nav.path.passable(result.x, result.y):
    return
  let step = nav.path.nearestPassable(
    result.x,
    result.y,
    max(nav.path.width, nav.path.height)
  )
  if step.found:
    result = Point(x: step.x, y: step.y)

proc nearestPointInside(nav: JumpPointSpace, rect: Rect, x, y: int): Point =
  ## Returns the nearest walkable foot pixel inside one rectangle.
  result = rect.center()
  if nav == nil:
    return
  var bestDistance = high(int)
  for py in max(0, rect.y) ..< min(nav.path.height, rect.y + rect.h):
    for px in max(0, rect.x) ..< min(nav.path.width, rect.x + rect.w):
      if not nav.path.passable(px, py):
        continue
      let distance = distanceSquared(px, py, x, y)
      if distance < bestDistance:
        bestDistance = distance
        result = Point(x: px, y: py)

proc nearestPointOutside(
  nav: JumpPointSpace,
  rect: Rect,
  desired: Point,
  radius: int
): tuple[found: bool, point: Point] =
  ## Returns the nearest walkable point near but outside one rectangle.
  if nav == nil:
    return
  var
    bestDistance = high(int)
    bestRectDistance = high(int)
  let
    minX = max(0, rect.x - radius)
    maxX = min(nav.path.width - 1, rect.x + rect.w + radius)
    minY = max(0, rect.y - radius)
    maxY = min(nav.path.height - 1, rect.y + rect.h + radius)
  for py in minY .. maxY:
    for px in minX .. maxX:
      if rect.contains(px, py):
        continue
      if not nav.path.passable(px, py):
        continue
      let rectDistance = pointRectDistanceSquared(px, py, rect)
      if rectDistance > radius * radius:
        continue
      let distance = distanceSquared(px, py, desired.x, desired.y)
      if distance < bestDistance or
          (distance == bestDistance and rectDistance < bestRectDistance):
        bestDistance = distance
        bestRectDistance = rectDistance
        result = (found: true, point: Point(x: px, y: py))

proc toDensePath(steps: openArray[PathStep]): seq[Point] =
  ## Converts sparse jump-point steps into a dense followable path.
  for step in steps:
    let point = Point(x: step.x, y: step.y)
    if result.len == 0:
      result.add(point)
      continue
    let
      previous = result[^1]
      dx = point.x - previous.x
      dy = point.y - previous.y
      span = max(abs(dx), abs(dy))
    var walked = PathDensifyPixels
    while walked < span:
      result.add(Point(
        x: previous.x + dx * walked div span,
        y: previous.y + dy * walked div span
      ))
      walked += PathDensifyPixels
    result.add(point)

proc pathTo(
  nav: JumpPointSpace,
  startX,
  startY,
  goalX,
  goalY: int
): seq[Point] =
  ## Finds a JPS+ path between two foot pixels.
  if nav == nil:
    return
  let
    start = nav.nearestPassablePoint(startX, startY)
    goal = nav.nearestPassablePoint(goalX, goalY)
  nav.findPath(start.x, start.y, goal.x, goal.y).toDensePath()

proc pathTo(
  nav: JumpPointSpace,
  startX,
  startY: int,
  rect: Rect
): seq[Point] =
  ## Finds a JPS+ path to a walkable pixel inside one rectangle.
  if nav == nil:
    return
  let goal = nav.nearestPointInside(rect, startX, startY)
  nav.pathTo(startX, startY, goal.x, goal.y)

proc pathNear(
  nav: JumpPointSpace,
  startX,
  startY: int,
  rect: Rect,
  radius: int
): seq[Point] =
  ## Finds a JPS+ path to a pixel that can interact with one rectangle.
  if nav == nil:
    return
  if nav.path.passable(startX, startY) and
      pointRectDistanceSquared(startX, startY, rect) <= radius * radius:
    return @[Point(x: startX, y: startY)]
  var candidates: seq[tuple[distance: int, point: Point]]
  let
    minX = max(0, rect.x - radius)
    maxX = min(nav.path.width - 1, rect.x + rect.w + radius)
    minY = max(0, rect.y - radius)
    maxY = min(nav.path.height - 1, rect.y + rect.h + radius)
  for py in countup(minY, maxY, 2):
    for px in countup(minX, maxX, 2):
      if not nav.path.passable(px, py):
        continue
      if pointRectDistanceSquared(px, py, rect) > radius * radius:
        continue
      candidates.add((
        distance: distanceSquared(px, py, startX, startY),
        point: Point(x: px, y: py)
      ))
  candidates.sort(proc(a, b: tuple[distance: int, point: Point]): int =
    cmp(a.distance, b.distance))
  # Nearby candidates are usually reachable; spread later attempts out
  # across the sorted list in case the closest side is walled off.
  var tried = 0
  var index = 0
  while index < candidates.len and tried < 8:
    result = nav.pathTo(
      startX,
      startY,
      candidates[index].point.x,
      candidates[index].point.y
    )
    if result.len > 0:
      return
    inc tried
    index += max(1, candidates.len div 8)

proc sameGoal(a, b: Goal): bool =
  ## Returns true when two goals are the same navigation target.
  a.kind == b.kind and
    a.screenKind == b.screenKind and
    a.x == b.x and
    a.y == b.y and
    a.houseIndex == b.houseIndex and
    a.gardenIndex == b.gardenIndex and
    a.targetName == b.targetName

proc navForCurrentMap(bot: Bot): JumpPointSpace =
  ## Returns the navigation space for the current observed map.
  case bot.screenKind
  of MainMap:
    bot.mainNav
  of HomeMap:
    bot.homeNav
  else:
    nil

proc updateNavSprite(bot: Bot, sprite: SpriteInfo) =
  ## Stores a decoded walkability sprite as a navigation map.
  if not sprite.kind.needsPixels() or
      sprite.pixels.len != sprite.width * sprite.height * 4:
    return
  case sprite.kind
  of SpriteMainWalk:
    bot.mainNav = sprite.buildNavSpace()
  of SpriteHomeWalk:
    bot.homeNav = sprite.buildNavSpace()
  else:
    discard

proc applySpritePacket(bot: Bot, packet: string): bool =
  ## Applies one or more Heartleaf sprite protocol messages.
  var offset = 0
  while offset < packet.len:
    let messageType = packet[offset].uint8
    inc offset
    case messageType
    of 0x01:
      if offset + 10 > packet.len:
        return false
      let
        spriteId = packet.readU16(offset)
        width = packet.readU16(offset + 2)
        height = packet.readU16(offset + 4)
        compressedLen = packet.readU32(offset + 6)
      offset += 10
      if offset + compressedLen + 2 > packet.len:
        return false
      let compressedStart = offset
      offset += compressedLen
      let labelLen = packet.readU16(offset)
      offset += 2
      if offset + labelLen > packet.len:
        return false
      let label =
        if labelLen > 0:
          packet.substr(offset, offset + labelLen - 1)
        else:
          ""
      offset += labelLen
      let classified = classifySprite(label)
      var pixels: seq[uint8]
      if classified.kind.needsPixels():
        let compressed =
          if compressedLen > 0:
            packet.substr(compressedStart, compressedStart + compressedLen - 1)
          else:
            ""
        try:
          let rawPixels = supersnappy.uncompress(compressed)
          pixels = newSeq[uint8](rawPixels.len)
          for i, ch in rawPixels:
            pixels[i] = ch.uint8
        except CatchableError:
          if classified.kind.needsPixels():
            return false
          pixels.setLen(0)
        if pixels.len != width * height * 4:
          if classified.kind.needsPixels():
            return false
          pixels.setLen(0)
      bot.ensureSprite(spriteId)
      bot.sprites[spriteId] = SpriteInfo(
        defined: true,
        width: width,
        height: height,
        label: label,
        kind: classified.kind,
        glyph: classified.glyph,
        pixels: pixels
      )
      bot.updateNavSprite(bot.sprites[spriteId])
    of 0x02:
      if offset + 11 > packet.len:
        return false
      let
        objectId = packet.readU16(offset)
        x = packet.readI16(offset + 2)
        y = packet.readI16(offset + 4)
        z = packet.readI16(offset + 6)
        layer = int(packet[offset + 8].uint8)
        spriteId = packet.readU16(offset + 9)
      offset += 11
      bot.ensureObject(objectId)
      bot.objects[objectId] = ObjectState(
        present: true,
        x: x,
        y: y,
        z: z,
        layer: layer,
        spriteId: spriteId
      )
    of 0x03:
      if offset + 2 > packet.len:
        return false
      let objectId = packet.readU16(offset)
      offset += 2
      if objectId >= 0 and objectId < bot.objects.len:
        bot.objects[objectId].present = false
    of 0x04:
      for objectState in bot.objects.mitems:
        objectState.present = false
    of 0x05:
      if offset + 5 > packet.len:
        return false
      offset += 5
    of 0x06:
      if offset + 3 > packet.len:
        return false
      offset += 3
    else:
      return false
  true

proc dayNumber(bot: Bot): int =
  ## Returns the one-based day of the current game.
  bot.dayIndex + 1

proc clockAnnouncement(bot: Bot): string =
  ## Returns one neutral hourly clock line for the conversation history.
  ## What the hours mean (dinner at 6pm, night at 10pm) is the soul's job.
  let
    clock = bot.minutes.clockName()
    minutes = bot.minutes
  result = "Day " & $bot.dayNumber & ". It is " & clock & "."
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
      result.add(" Night falls within the hour.")
    else:
      result.add(" " & $hours & " hours till night.")
  else:
    result.add(" It is night.")

proc recordDayEnd(bot: Bot) =
  ## Records the end of the day once and logs the transcript size so a
  ## hosted run shows how close ChatHistoryLimit gets.
  if bot.dayEndRecorded:
    return
  bot.dayEndRecorded = true
  bot.recordEvent("Day " & $bot.dayNumber & " ends.")
  var heard, said, events, decisions, clocks = 0
  for message in bot.chatHistory:
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
  bot.log("day " & $bot.dayNumber & " ends, history len=" &
    $bot.chatHistory.len & " heard=" & $heard & " said=" & $said &
    " events=" & $events & " decisions=" & $decisions &
    " clocks=" & $clocks)

proc maybeRecordDayEnd(bot: Bot) =
  ## Records the day end when the clock reaches night time.
  if bot.minutes >= DayEndMinutes:
    bot.recordDayEnd()

proc maybeRecordClock(bot: Bot) =
  ## Records one clock line in the conversation every game hour, after
  ## the day marker on the first hour of each day.
  if bot.minutes < 0:
    return
  let hour = bot.minutes div 60
  if hour == bot.lastClockHour:
    return
  if bot.lastClockHour < 0:
    bot.recordEvent(bot.dayNumber.dayBeginsLine())
  bot.lastClockHour = hour
  bot.chatHistory.add(ConversationMessage(
    role: "user",
    content: "Clock: " & bot.clockAnnouncement()
  ))
  bot.maybeRecordDayEnd()

proc resetGardenPlan(bot: Bot) =
  ## Resets the per-day state for a new morning: the garden checklist,
  ## who was seen and greeted, dinner bookkeeping, and any pending
  ## decision or request from yesterday. lastClockHour = -1 makes the
  ## next clock line open with a "Day N begins." marker.
  bot.recordDayEnd()
  inc bot.dayIndex
  bot.gardenChecked = newSeq[bool](bot.resources.gardens.len)
  bot.currentGarden = -1
  bot.hasDecision = false
  bot.decisionChatSent = false
  bot.llmWaiting = false
  bot.lastLlmError = ""
  bot.committedPartyHouse = UnknownHouse
  bot.seenToday.clear()
  bot.greetedToday.clear()
  bot.interruptRequested = false
  bot.dayEndRecorded = false
  bot.dinnerLookingBefore = ""
  bot.dinnerHouse = UnknownHouse
  bot.dinnerRecorded = false
  bot.leaveTimeNoted = false
  bot.saidToday.setLen(0)
  bot.lastClockHour = -1
  bot.path.setLen(0)
  bot.goal = Goal(kind: GoalIdle, screenKind: UnknownScreen)

proc updateClock(bot: Bot) =
  ## Updates the bot's current day clock from the UI glyphs and measures
  ## how many ticks one game minute takes.
  let minutes = bot.clockText().parseClockMinutes()
  if minutes < 0:
    return
  if bot.minutes > minutes:
    bot.resetGardenPlan()
    bot.clockAnchorMinutes = -1
  if minutes != bot.minutes:
    if bot.clockAnchorMinutes < 0:
      bot.clockAnchorTick = bot.frameTick
      bot.clockAnchorMinutes = minutes
    elif minutes - bot.clockAnchorMinutes >= ClockRateMinMinutes:
      bot.ticksPerMinute = float(bot.frameTick - bot.clockAnchorTick) /
        float(minutes - bot.clockAnchorMinutes)
  bot.minutes = minutes

proc updateScreenKind(bot: Bot) =
  ## Updates the visible screen kind and camera offset.
  bot.previousScreenKind = bot.screenKind
  bot.screenKind = OverlayScreen
  bot.cameraX = 0
  bot.cameraY = 0
  if BottomObjectId >= bot.objects.len:
    return
  let bottom = bot.objects[BottomObjectId]
  if not bottom.present:
    return
  let sprite = bot.spriteInfo(bottom.spriteId)
  if sprite == nil:
    return
  case sprite.kind
  of SpriteMainBottom:
    bot.screenKind = MainMap
  of SpriteHomeBottom:
    bot.screenKind = HomeMap
  else:
    bot.screenKind = UnknownScreen
  bot.cameraX = -bottom.x
  bot.cameraY = -bottom.y
  if bot.screenKind != bot.previousScreenKind:
    bot.path.setLen(0)
    if bot.screenKind == HomeMap and bot.pendingHouse >= 0:
      bot.currentHouse = bot.pendingHouse
      bot.pendingHouse = UnknownHouse
    elif bot.screenKind == MainMap:
      bot.currentHouse = UnknownHouse

proc findSelfIndexByName(bot: Bot): int =
  ## Returns the player index whose name tag matches this bot.
  result = -1
  if bot.playerName.len == 0:
    return
  let expected = NameLabelPrefix & bot.playerName
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < NameObjectBase or objectId >= GardenObjectBase:
      continue
    let sprite = bot.spriteInfo(objectState.spriteId)
    if sprite != nil and sprite.label == expected:
      return objectId - NameObjectBase

proc findSelfIndexByCamera(bot: Bot): int =
  ## Returns the player index closest to the camera center.
  result = -1
  var bestDistance = high(int)
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let distance = distanceSquared(
      objectState.x.footXAt(),
      objectState.y.footYAt(),
      ViewportWidth div 2,
      ViewportHeight div 2
    )
    if distance < bestDistance:
      bestDistance = distance
      result = objectId - PlayerObjectBase

proc adoptHomeIdentity(bot: Bot, homeIndex: int) =
  ## Learns the controlled gnome name from its fixed home number.
  if bot.playerName.len > 0:
    return
  if homeIndex < 0 or homeIndex >= PlayerNames.len:
    return
  let name = homeIndex.playerNameForHouse()
  bot.playerName = name
  bot.soulInstructions = bot.loadSoulInstructions(name)
  bot.homeIndex = homeIndex
  bot.currentHouse =
    if bot.screenKind == HomeMap:
      homeIndex
    else:
      UnknownHouse
  bot.pendingHouse = UnknownHouse
  bot.committedPartyHouse = UnknownHouse
  bot.hasDecision = false
  bot.currentGarden = -1
  bot.path.setLen(0)
  bot.goal = Goal(kind: GoalIdle, screenKind: UnknownScreen)

proc nearestMorningHome(bot: Bot): int =
  ## Returns the nearest home inferred from the morning world spawn.
  result = UnknownHouse
  if bot.screenKind != MainMap or bot.minutes > MorningIdentityUntilMinutes:
    return
  var bestDistance = MorningIdentityRadius * MorningIdentityRadius + 1
  for i, house in bot.resources.houses:
    if not bot.resources.houseValid[i]:
      continue
    let distance = pointRectDistanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      house
    )
    if distance <= MorningIdentityRadius * MorningIdentityRadius and
        distance < bestDistance:
      bestDistance = distance
      result = i

proc adoptVisibleIdentity(bot: Bot, selfIndex: int) =
  ## Learns the controlled gnome name from its visible name tag.
  let name = bot.visiblePlayerName(selfIndex)
  if name.len == 0:
    return
  bot.adoptHomeIdentity(name.houseIndexForPlayerName())

proc updateSelf(bot: Bot) =
  ## Updates the bot's own player position from actor objects.
  bot.localized = false
  let cameraIndex = bot.findSelfIndexByCamera()
  var selfIndex = -1
  if bot.slot >= 0:
    selfIndex = bot.findSelfIndexByName()
    if selfIndex < 0:
      selfIndex = cameraIndex
  elif bot.playerName.len == 0:
    selfIndex = cameraIndex
  elif cameraIndex >= 0 and
      bot.visiblePlayerName(cameraIndex) == bot.playerName:
    selfIndex = cameraIndex
  else:
    selfIndex = bot.findSelfIndexByName()
    if selfIndex < 0:
      selfIndex = cameraIndex
  let objectId = PlayerObjectBase + selfIndex
  if selfIndex < 0 or objectId >= bot.objects.len:
    return
  let objectState = bot.objects[objectId]
  if not objectState.present:
    return
  bot.selfIndex = selfIndex
  bot.selfX = bot.objectWorldX(objectState)
  bot.selfY = bot.objectWorldY(objectState)
  if bot.slot < 0 and bot.playerName.len == 0:
    let homeIndex = bot.nearestMorningHome()
    if homeIndex >= 0:
      bot.adoptHomeIdentity(homeIndex)
    else:
      bot.adoptVisibleIdentity(selfIndex)
  bot.localized = true

proc updateStuck(bot: Bot, mask: uint8) =
  ## Updates stuck detection and jitter recovery state.
  let moving = (mask and (
    ButtonUp or ButtonDown or ButtonLeft or ButtonRight
  )) != 0
  let
    footX = bot.playerFootX()
    footY = bot.playerFootY()
    blocked = footX == bot.previousX and footY == bot.previousY
    wobbling = footX == bot.previous2X and footY == bot.previous2Y and
      not blocked
  if moving and (blocked or wobbling):
    inc bot.stuckTicks
  else:
    bot.stuckTicks = 0
  bot.velEstX = footX - bot.previousX
  bot.velEstY = footY - bot.previousY
  bot.previous2X = bot.previousX
  bot.previous2Y = bot.previousY
  bot.previousX = footX
  bot.previousY = footY
  if bot.unstuckTicks > 0:
    dec bot.unstuckTicks
  elif bot.stuckTicks >= UnstuckAfterTicks and
      bot.stuckTicks mod UnstuckAfterTicks == 0:
    bot.unstuckTicks = UnstuckDurationTicks
    bot.unstuckMaskIndex = (bot.unstuckMaskIndex + 1) mod UnstuckMasks.len
    bot.path.setLen(0)
    bot.log("unstuck jitter " & $bot.unstuckMaskIndex)

proc gardenHasMarker(bot: Bot, gardenIndex: int): bool =
  ## Returns true when the current view has a garden exclamation marker.
  let objectId = GardenObjectBase + gardenIndex
  if objectId < 0 or objectId >= bot.objects.len:
    return false
  bot.objects[objectId].present

proc gardenMarkerVisible(bot: Bot, gardenIndex: int): bool =
  ## Returns true when one garden marker position is inside the viewport.
  if gardenIndex < 0 or gardenIndex >= bot.resources.gardens.len:
    return false
  let
    rect = bot.resources.gardens[gardenIndex]
    x = rect.x + rect.w div 2 - FoodSpriteSize div 2 - bot.cameraX
    y = rect.y + rect.h div 2 - FoodSpriteSize div 2 - bot.cameraY
  screenRectVisible(x, y, FoodSpriteSize, FoodSpriteSize)

proc anyGardenMarkers(bot: Bot): bool =
  ## Returns true when any known garden still has a visible marker.
  for i in 0 ..< bot.resources.gardens.len:
    if bot.gardenHasMarker(i):
      return true

proc nearbyMarkedGarden(bot: Bot): int =
  ## Returns a close marked garden that can be picked up now.
  result = -1
  if bot.screenKind != MainMap:
    return
  var bestDistance = CollectActionRadius * CollectActionRadius + 1
  for i, rect in bot.resources.gardens:
    if not bot.gardenHasMarker(i):
      continue
    let distance = pointRectDistanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      rect
    )
    if distance <= CollectActionRadius * CollectActionRadius and
        distance < bestDistance:
      result = i
      bestDistance = distance

proc parseInventoryCount(label: string): int =
  ## Parses a count from one inventory count sprite label.
  let parts = strutils.splitWhitespace(label)
  if parts.len == 0:
    return 0
  try:
    result = parseInt(parts[^1])
  except ValueError:
    result = 0

proc inventoryCountAt(bot: Bot, foodIndex: int): int =
  ## Returns how many of one named food this bot is carrying.
  let countObjectId = InventoryCountObjectBase + foodIndex
  if countObjectId < bot.objects.len and
      bot.objects[countObjectId].present:
    let sprite = bot.spriteInfo(bot.objects[countObjectId].spriteId)
    if sprite != nil:
      return sprite.label.parseInventoryCount()
  let iconObjectId = InventoryObjectBase + foodIndex
  if iconObjectId < bot.objects.len and bot.objects[iconObjectId].present:
    return 1

proc inventoryTotal(bot: Bot): int =
  ## Returns how many food items this bot is carrying.
  for foodIndex in 0 ..< FoodVeggieSlots:
    result += bot.inventoryCountAt(foodIndex)

proc collectedFoodsText(bot: Bot): string =
  ## Returns named foods in this bot's inventory for the LLM prompt.
  for foodIndex in 0 ..< FoodVeggieSlots:
    let count = bot.inventoryCountAt(foodIndex)
    if count <= 0:
      continue
    if result.len > 0:
      result.add(", ")
    result.add(foodIndex.foodName())
    if count > 1:
      result.add(" x" & $count)
  if result.len == 0:
    result = "none"

proc lookingForFoodsText(bot: Bot): string =
  ## Returns named foods this bot has not eaten yet this game.
  if LookingForObjectId < bot.objects.len and
      bot.objects[LookingForObjectId].present:
    let sprite = bot.spriteInfo(bot.objects[LookingForObjectId].spriteId)
    if sprite != nil and sprite.label.startsWith(LookingForLabelPrefix):
      let rest = sprite.label[LookingForLabelPrefix.len .. ^1].strip()
      if rest.len > 0:
        return rest
  FoodNames.join(", ")

proc gardensExhausted(bot: Bot): bool =
  ## Returns true when the bot has checked every known garden.
  if bot.gardenChecked.len != bot.resources.gardens.len:
    return false
  if bot.anyGardenMarkers():
    return false
  for checked in bot.gardenChecked:
    if not checked:
      return false
  true

proc shouldGather(bot: Bot): bool =
  ## Returns true while there are gardens left to check today.
  not bot.gardensExhausted()

proc maybeRecordCarry(bot: Bot) =
  ## Records what the bot carries whenever it changes, so the transcript
  ## remembers pickups and the emptied pantry after hosting.
  if bot.screenKind == OverlayScreen:
    return
  ## Only a change in which foods are carried is worth a line; a second
  ## carrot is not.
  let carry = bot.collectedFoodsText()
  let names = carry.foodNamesIn().join(", ")
  if names == bot.lastCarryText:
    return
  bot.lastCarryText = names
  if carry == "none":
    bot.recordEvent("You carry no food now.")
  else:
    bot.recordEvent("You now carry: " & carry & ".")

proc visibleDinnerLabel(bot: Bot): string =
  ## Returns the dinner overlay label when the dinner result is on
  ## screen, else "".
  for objectId in ScoreObjectBase ..< LookingForObjectId:
    if objectId >= bot.objects.len or not bot.objects[objectId].present:
      continue
    let sprite = bot.spriteInfo(bot.objects[objectId].spriteId)
    if sprite != nil and sprite.label.startsWith(DinnerLabelPrefix):
      return sprite.label

proc dinnerSummary(bot: Bot, label: string): string =
  ## Turns one dinner overlay label into a transcript line. Labels from
  ## older game builds carry only the player index, so the summary then
  ## falls back to what the bot saw itself at 6pm.
  let
    host = label.dinnerLabelField("host")
    wasHost = label.dinnerLabelField("wasHost") == "true"
    score = label.dinnerLabelField("score")
    guestsText = label.dinnerLabelField("guests")
    foodsText = label.dinnerLabelField("foods")
  var guests: seq[string]
  for name in guestsText.split(","):
    if name.strip().len > 0 and name.strip() != bot.playerName:
      guests.add(name.strip())
  let others =
    if guests.len == 0:
      "nobody else"
    else:
      guests.join(", ")
  if host.len == 0:
    ## Legacy label: infer from position and the looking-for list.
    let hostName =
      if bot.dinnerHouse >= 0:
        bot.dinnerHouse.playerNameForHouse()
      else:
        ""
    if hostName.len == 0:
      return "Dinner was served but you do not know where you were."
    if bot.dinnerHouse == bot.homeIndex:
      return "Dinner: you hosted at your house and served your pantry."
    var ate: seq[string]
    let stillLooking = bot.lookingForFoodsText().foodNamesIn()
    for name in bot.dinnerLookingBefore.foodNamesIn():
      if name notin stillLooking:
        ate.add(name)
    result = "Dinner: you ate at " & hostName & "'s house."
    if ate.len > 0:
      result.add(" You ate " & ate.join(", ") & ", which you still wanted.")
    return
  let scoreText =
    if score.len > 0:
      " (+" & score & " score)"
    else:
      ""
  if wasHost:
    return "Dinner: you hosted " & others & " at your house and served " &
      foodsText & scoreText & ". Your pantry is empty now."
  var wanted: seq[string]
  let before = bot.dinnerLookingBefore.foodNamesIn()
  for name in foodsText.foodNamesIn():
    if name in before:
      wanted.add(name)
  result = "Dinner: you ate at " & host & "'s house with " & others &
    ". You ate " & foodsText & scoreText & "."
  if wanted.len > 0:
    result.add(" You had wanted " & wanted.join(", ") & " and got it.")
  let stillLooking = bot.lookingForFoodsText()
  if stillLooking.len > 0 and stillLooking != "none":
    result.add(" Still looking for: " & stillLooking & ".")

proc maybeRecordDinner(bot: Bot) =
  ## Remembers, until dinner, where the bot is and what it still wants,
  ## then records the dinner result once the dinner overlay shows, or that
  ## dinner was missed if it never does. The clock is hidden while the
  ## overlay is up, so the label is checked every frame regardless of the
  ## last clock reading.
  if bot.dinnerRecorded:
    return
  if bot.minutes < DinnerMinutes and bot.screenKind != OverlayScreen:
    if LookingForObjectId < bot.objects.len and
        bot.objects[LookingForObjectId].present:
      bot.dinnerLookingBefore = bot.lookingForFoodsText()
    bot.dinnerHouse =
      if bot.screenKind == HomeMap:
        bot.currentHouse
      else:
        UnknownHouse
  let label = bot.visibleDinnerLabel()
  if label.len > 0:
    bot.dinnerRecorded = true
    let summary = bot.dinnerSummary(label)
    bot.recordEvent(summary)
    bot.log("dinner " & label)
    return
  if bot.minutes < DinnerMinutes + DinnerMissedGraceMinutes:
    return
  bot.dinnerRecorded = true
  let missed =
    if bot.dinnerHouse < 0:
      "Dinner: you were outside at 6pm and missed dinner."
    elif bot.dinnerHouse == bot.homeIndex:
      "Dinner: you were home at 6pm but nobody came, so there was no dinner."
    else:
      "Dinner: you were at " & bot.dinnerHouse.playerNameForHouse() &
        "'s house at 6pm but no dinner was served there (the host was " &
        "not inside)."
  bot.recordEvent(missed)
  bot.log("dinner missed: " & missed)

proc analyze(bot: Bot) =
  ## Rebuilds high-level bot state from decoded objects.
  bot.updateClock()
  bot.updateScreenKind()
  bot.updateSelf()
  if bot.screenKind == HomeMap and bot.currentHouse == UnknownHouse and
      bot.playerName.len > 0:
    bot.currentHouse = bot.homeIndex

proc homeIndexFromName(name: string): int =
  ## Guesses a zero-based home index from trailing name digits.
  var start = name.len
  while start > 0 and name[start - 1].isDigit():
    dec start
  if start >= name.len:
    return 0
  try:
    result = (parseInt(name[start .. ^1]) - 1).clamp(0, 8)
  except ValueError:
    result = 0

proc initBot(name: string, slot: int, soul: string): Bot =
  ## Builds a new talking Villager bot state.
  result = Bot()
  result.soulTemplate = soul.strip()
  result.name =
    if name.len > 0:
      name
    else:
      DefaultName
  result.slot = slot
  result.llmPacer = initLlmPacer(
    slot * 7919 + int(epochTime() * 1000) mod 100_000
  )
  result.homeIndex =
    if slot >= 0 and slot < 9:
      slot
    else:
      result.name.homeIndexFromName()
  result.playerName =
    if slot >= 0 and slot < 9:
      result.homeIndex.playerNameForHouse()
    else:
      ""
  result.soulInstructions =
    if result.playerName.len > 0:
      result.loadSoulInstructions(result.playerName)
    else:
      result.loadSoulInstructions(DefaultName)
  result.resources = loadBotResources()
  result.currentHouse =
    if result.playerName.len > 0:
      result.homeIndex
    else:
      UnknownHouse
  result.pendingHouse = UnknownHouse
  result.minutes = DayStartMinutes
  result.selfIndex = -1
  result.goal = Goal(kind: GoalIdle, screenKind: UnknownScreen)
  result.currentGarden = -1
  result.hasDecision = false
  result.decisionChatSent = false
  result.llmWaiting = false
  result.committedPartyHouse = UnknownHouse
  result.dayIndex = 0
  result.gardenChecked = newSeq[bool](result.resources.gardens.len)
  result.lastClockHour = -1
  result.seenToday = initHashSet[string]()
  result.greetedToday = initHashSet[string]()
  result.dinnerHouse = UnknownHouse
  result.clockAnchorMinutes = -1
  result.ticksPerMinute = DefaultTicksPerMinute

proc gardenGoal(bot: Bot): Goal =
  ## Returns a goal for the nearest garden that may still have food.
  result = Goal(kind: GoalIdle, screenKind: MainMap)
  if bot.screenKind != MainMap or bot.mainNav == nil:
    return
  if bot.gardenChecked.len != bot.resources.gardens.len:
    bot.resetGardenPlan()

  let nearbyGarden = bot.nearbyMarkedGarden()
  if nearbyGarden >= 0:
    let target = bot.resources.gardens[nearbyGarden].center()
    bot.currentGarden = nearbyGarden
    return Goal(
      kind: GoalCollect,
      screenKind: MainMap,
      x: target.x,
      y: target.y,
      gardenIndex: nearbyGarden,
      houseIndex: UnknownHouse
    )

  if bot.currentGarden >= 0 and
      bot.currentGarden < bot.gardenChecked.len and
      not bot.gardenChecked[bot.currentGarden]:
    if bot.gardenMarkerVisible(bot.currentGarden) and
        not bot.gardenHasMarker(bot.currentGarden):
      bot.gardenChecked[bot.currentGarden] = true
      bot.currentGarden = -1
    else:
      let rect = bot.resources.gardens[bot.currentGarden]
      let target = rect.center()
      return Goal(
        kind: GoalCollect,
        screenKind: MainMap,
        x: target.x,
        y: target.y,
        gardenIndex: bot.currentGarden,
        houseIndex: UnknownHouse
      )

  let preferMarkers = bot.anyGardenMarkers()
  for i in 0 ..< bot.resources.gardens.len:
    if i < bot.gardenChecked.len and
        bot.gardenMarkerVisible(i) and
        not bot.gardenHasMarker(i):
      bot.gardenChecked[i] = true
  if bot.currentGarden >= 0 and
      bot.currentGarden < bot.gardenChecked.len and
      not bot.gardenChecked[bot.currentGarden]:
    let rect = bot.resources.gardens[bot.currentGarden]
    let target = rect.center()
    return Goal(
        kind: GoalCollect,
        screenKind: MainMap,
        x: target.x,
        y: target.y,
        gardenIndex: bot.currentGarden,
        houseIndex: UnknownHouse
    )

  var
    bestIndex = -1
    bestPathLen = high(int)
    bestDistance = high(int)
  for i, rect in bot.resources.gardens:
    if i < bot.gardenChecked.len and bot.gardenChecked[i]:
      continue
    if preferMarkers and bot.gardenMarkerVisible(i) and
        not bot.gardenHasMarker(i):
      continue
    let path = bot.mainNav.pathNear(
      bot.playerFootX(),
      bot.playerFootY(),
      rect,
      CollectActionRadius
    )
    if path.len == 0:
      if i < bot.gardenChecked.len:
        bot.gardenChecked[i] =
          bot.gardenMarkerVisible(i) and not bot.gardenHasMarker(i)
      continue
    let
      target = rect.center()
      distance = distanceSquared(
        bot.playerFootX(),
        bot.playerFootY(),
        target.x,
        target.y
      )
    if path.len < bestPathLen or
        (path.len == bestPathLen and distance < bestDistance):
      bestIndex = i
      bestPathLen = path.len
      bestDistance = distance
  if bestIndex < 0:
    return

  bot.currentGarden = bestIndex
  let target = bot.resources.gardens[bestIndex].center()
  result = Goal(
    kind: GoalCollect,
    screenKind: MainMap,
    x: target.x,
    y: target.y,
    gardenIndex: bestIndex,
    houseIndex: UnknownHouse
  )

proc goalForRect(
  bot: Bot,
  kind: GoalKind,
  rect: Rect,
  houseIndex: int
): Goal =
  ## Returns a navigation goal for standing inside one rectangle.
  let nav = bot.navForCurrentMap()
  var target = rect.center()
  if nav != nil:
    target = nav.nearestPointInside(rect, target.x, target.y)
  Goal(
    kind: kind,
    screenKind: bot.screenKind,
    x: target.x,
    y: target.y,
    houseIndex: houseIndex,
    gardenIndex: -1
  )

proc exitGoal(bot: Bot): Goal =
  ## Returns a goal for leaving the current home map.
  if not bot.resources.hasExit:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  bot.goalForRect(GoalExitHouse, bot.resources.exit, UnknownHouse)

proc enterHouseGoal(bot: Bot, houseIndex: int): Goal =
  ## Returns a goal for entering one main-map house.
  if houseIndex < 0 or houseIndex >= bot.resources.houseValid.len or
      not bot.resources.houseValid[houseIndex]:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  bot.goalForRect(GoalEnterHouse, bot.resources.houses[houseIndex], houseIndex)

proc playerNearHouse(
  bot: Bot,
  objectState: ObjectState,
  houseIndex: int
): bool =
  ## Returns true when a player object is waiting near one house.
  if houseIndex < 0 or
      houseIndex >= bot.resources.houseValid.len or
      not bot.resources.houseValid[houseIndex]:
    return false
  pointRectDistanceSquared(
    bot.objectFootX(objectState),
    bot.objectFootY(objectState),
    bot.resources.houses[houseIndex]
  ) <= HouseGatherMaxRadius * HouseGatherMaxRadius

proc visiblePlayerHome(bot: Bot, playerIndex: int): int =
  ## Returns the fixed home index for one visible player.
  bot.visiblePlayerName(playerIndex).houseIndexForPlayerName()

proc houseOwnerPresent(bot: Bot, houseIndex: int): bool =
  ## Returns true when a home owner is visible near their house.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if bot.visiblePlayerHome(playerIndex) != houseIndex:
      continue
    if bot.playerNearHouse(objectState, houseIndex):
      return true

proc houseHasGuest(bot: Bot, houseIndex: int): bool =
  ## Returns true when another visible player waits near one house.
  if houseIndex < 0 or
      houseIndex >= bot.resources.houseValid.len or
      not bot.resources.houseValid[houseIndex]:
    return false
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    if objectId - PlayerObjectBase == bot.selfIndex:
      continue
    if bot.playerNearHouse(objectState, houseIndex):
      return true

proc houseCrowdOthers(bot: Bot, houseIndex: int): int =
  ## Returns how many other visible gnomes are gathered near one house.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if playerIndex == bot.selfIndex:
      continue
    if bot.visiblePlayerName(playerIndex) == bot.playerName:
      continue
    if bot.playerNearHouse(objectState, houseIndex):
      inc result

proc desiredHouseGatherPoint(bot: Bot, house: Rect): Point =
  ## Returns this bot's preferred outside door spot around one house.
  let
    slot = bot.homeIndex mod DoorGatherSlots
    offset = (slot - DoorGatherSlots div 2) * DoorGatherSpacing
  return Point(
    x: house.x + house.w div 2 + offset,
    y: house.y + house.h + 4
  )

proc houseGatherPoint(bot: Bot, houseIndex: int): Point =
  ## Returns a walkable outside gathering point near one house.
  result = Point(x: bot.playerFootX(), y: bot.playerFootY())
  if bot.mainNav == nil or
      houseIndex < 0 or
      houseIndex >= bot.resources.houseValid.len or
      not bot.resources.houseValid[houseIndex]:
    return
  let
    house = bot.resources.houses[houseIndex]
    desired = bot.desiredHouseGatherPoint(house)
    outside = bot.mainNav.nearestPointOutside(
      house,
      desired,
      HouseGatherMaxRadius
    )
  if outside.found:
    result = outside.point

proc gatherAtHouseGoal(bot: Bot, houseIndex: int): Goal =
  ## Returns a goal that keeps the bot visible outside one house.
  if bot.screenKind == HomeMap:
    return bot.exitGoal()
  if bot.screenKind != MainMap:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  let point = bot.houseGatherPoint(houseIndex)
  Goal(
    kind: GoalGatherHouse,
    screenKind: MainMap,
    x: point.x,
    y: point.y,
    houseIndex: houseIndex,
    gardenIndex: -1
  )

proc firstDinerGoal(bot: Bot): Goal =
  ## Returns a small idle movement goal away from the home exit.
  Goal(
    kind: GoalMove,
    screenKind: bot.screenKind,
    x: bot.playerFootX(),
    y: bot.playerFootY(),
    houseIndex: bot.currentHouse,
    gardenIndex: -1
  )

proc ownHomeGoal(bot: Bot): Goal =
  ## Returns the goal that gets the bot into its own house.
  if bot.screenKind == HomeMap:
    if bot.currentHouse == bot.homeIndex:
      return bot.firstDinerGoal()
    return bot.exitGoal()
  if bot.screenKind == MainMap:
    return bot.enterHouseGoal(bot.homeIndex)
  Goal(kind: GoalIdle, screenKind: bot.screenKind)

proc visiblePlayerNear(bot: Bot, name: string): bool =
  ## Returns true when one named visible player is close enough to talk.
  let playerIndex = bot.visiblePlayerIndexByName(name)
  if playerIndex < 0:
    return false
  let objectId = PlayerObjectBase + playerIndex
  if objectId < 0 or objectId >= bot.objects.len:
    return false
  let objectState = bot.objects[objectId]
  if not objectState.present:
    return false
  distanceSquared(
    bot.playerFootX(),
    bot.playerFootY(),
    bot.objectFootX(objectState),
    bot.objectFootY(objectState)
  ) <= PersonStandRadius * PersonStandRadius

proc standNextToPersonGoal(bot: Bot, name: string): Goal =
  ## Returns a goal for walking near one visible or likely player.
  let playerIndex = bot.visiblePlayerIndexByName(name)
  if playerIndex >= 0:
    let objectState = bot.objects[PlayerObjectBase + playerIndex]
    return Goal(
      kind: GoalStandPerson,
      screenKind: bot.screenKind,
      x: bot.objectFootX(objectState),
      y: bot.objectFootY(objectState),
      houseIndex: bot.visiblePlayerHome(playerIndex),
      gardenIndex: -1,
      targetName: name
    )
  ## Inside a house you cannot search the world; wait here for them.
  if bot.screenKind == HomeMap:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  if bot.screenKind == MainMap:
    let houseIndex = name.houseIndexForPlayerName()
    if houseIndex >= 0:
      return bot.gatherAtHouseGoal(houseIndex)
  Goal(kind: GoalIdle, screenKind: bot.screenKind)

proc decisionHouse(bot: Bot, decision: LlmDecision): int =
  ## Returns the best house target for one LLM decision.
  result = decision.houseIndex
  if result < 0 and decision.targetName.len > 0:
    result = decision.targetName.houseIndexForPlayerName()
  if result < 0 and bot.committedPartyHouse >= 0:
    result = bot.committedPartyHouse

proc inferSocialCommitment(bot: Bot, decision: LlmDecision): LlmDecision =
  ## Fills in the house a commitment refers to. Only what the JSON says
  ## counts: commitParty true (with houseIndex, else targetName's house,
  ## else the bot's own house when it is inviting) or go_to_party. Chat
  ## wording is never read as a promise; that guess once sent a bot to
  ## the wrong house.
  result = decision
  if result.houseIndex < 0 and result.targetName.len > 0 and
      (result.action == LlmGoToParty or result.commitParty):
    result.houseIndex = result.targetName.houseIndexForPlayerName()
  if result.commitParty and result.houseIndex < 0 and
      result.action == LlmSayToPerson:
    result.houseIndex = bot.homeIndex

proc timePhase(bot: Bot): int =
  ## Returns the game hour; a new hour re-asks the LLM so it can react to
  ## the clock line that just landed in the transcript.
  bot.minutes div 60

proc foodBand(bot: Bot): int =
  ## Returns a coarse inventory band for interrupt detection.
  let food = bot.inventoryTotal()
  if food <= LowFoodBand:
    return 0
  if food >= HighFoodBand:
    return 2
  return 1

proc screenNameForPrompt(kind: ScreenKind): string =
  ## Returns a readable screen name for the LLM prompt.
  case kind
  of UnknownScreen:
    "unknown"
  of MainMap:
    "world"
  of HomeMap:
    "home"
  of OverlayScreen:
    "overlay"

proc visiblePlayersText(bot: Bot): string =
  ## Returns visible player facts for the LLM prompt.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let
      playerIndex = objectId - PlayerObjectBase
      name = bot.visiblePlayerName(playerIndex)
    if name.len == 0 or playerIndex == bot.selfIndex or
        name == bot.playerName:
      continue
    if result.len > 0:
      result.add("\n")
    let
      footX = bot.objectFootX(objectState)
      footY = bot.objectFootY(objectState)
      distance = distanceSquared(
        bot.playerFootX(),
        bot.playerFootY(),
        footX,
        footY
      )
      chat = bot.visibleChatText(playerIndex)
    result.add(
      "- " & name &
      " homeOwner=" & name &
      " homeHouseIndex=" & $(name.houseIndexForPlayerName() + 1) &
      " x=" & $footX &
      " y=" & $footY &
      " distanceSquared=" & $distance
    )
    if chat.len > 0:
      result.add(" says=\"" & chat & "\"")
  if result.len == 0:
    result = "- none"

proc visibleChatsSignature(bot: Bot): string =
  ## Returns a compact signature of visible chat bubbles.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < ChatObjectBase or objectId >= GardenObjectBase:
      continue
    let playerIndex = objectId - ChatObjectBase
    let chat = bot.visibleChatText(playerIndex)
    if chat.len == 0:
      continue
    result.add(bot.visiblePlayerName(playerIndex) & ":" & chat & "|")

proc houseCrowdsText(bot: Bot): string =
  ## Returns visible house crowd facts for the LLM prompt.
  for step in 0 ..< HouseCount:
    let houseIndex = (bot.homeIndex + 1 + step) mod HouseCount
    if not bot.resources.houseValid[houseIndex]:
      continue
    if result.len > 0:
      result.add("\n")
    result.add(
      "- houseOwner=" & houseIndex.playerNameForHouse() &
      " houseIndex=" & $(houseIndex + 1) &
      " otherCrowd=" & $bot.houseCrowdOthers(houseIndex) &
      " ownerPresent=" & $bot.houseOwnerPresent(houseIndex) &
      " hasGuest=" & $bot.houseHasGuest(houseIndex)
    )

proc houseCrowdsSignature(bot: Bot): string =
  ## Returns a compact signature of visible house crowds.
  for houseIndex in 0 ..< HouseCount:
    let crowd = bot.houseCrowdOthers(houseIndex)
    if crowd > 0:
      result.add($(houseIndex + 1) & ":" & $crowd & ",")
  if result.len == 0:
    result = "none"

proc gardenMarkersText(bot: Bot): string =
  ## Returns visible garden marker facts for the LLM prompt.
  var count = 0
  for i in 0 ..< bot.resources.gardens.len:
    if bot.gardenHasMarker(i):
      inc count
      if result.len > 0:
        result.add(", ")
      result.add($i)
  if result.len == 0:
    result = "none"
  result = "visible=" & $count & " indices=" & result

proc decisionStateSignature(bot: Bot): string =
  ## Returns the interrupt signature for the current strategic state.
  "phase=" & $bot.timePhase() &
    "|food=" & $bot.foodBand() &
    "|chats=" & bot.visibleChatsSignature() &
    "|crowds=" & bot.houseCrowdsSignature() &
    "|commit=" & $bot.committedPartyHouse &
    "|looking=" & bot.lookingForFoodsText() &
    "|day=" & $bot.dayNumber

proc namesText(names: HashSet[string]): string =
  ## Returns a sorted, comma separated name list or "none".
  var sorted: seq[string]
  for name in names:
    sorted.add(name)
  sorted.sort()
  if sorted.len == 0:
    return "none"
  sorted.join(", ")

proc visibleGnomeNames(bot: Bot): HashSet[string] =
  ## Returns the names of the other gnomes on screen right now.
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if playerIndex == bot.selfIndex:
      continue
    let name = bot.visiblePlayerName(playerIndex)
    if name.len > 0 and name != bot.playerName:
      result.incl(name)

proc notYetGreetedText(bot: Bot): string =
  ## Returns visible gnomes this bot has not greeted today.
  var pending: HashSet[string]
  for objectId, objectState in bot.objects:
    if not objectState.present:
      continue
    if objectId < PlayerObjectBase or objectId >= NameObjectBase:
      continue
    let playerIndex = objectId - PlayerObjectBase
    if playerIndex == bot.selfIndex:
      continue
    let name = bot.visiblePlayerName(playerIndex)
    if name.len == 0 or name == bot.playerName:
      continue
    if name notin bot.greetedToday:
      pending.incl(name)
  pending.namesText()

proc pathLengthPixels(points: openArray[Point]): int =
  ## Returns the walked length of one dense path in pixels.
  for i in 1 ..< points.len:
    result += int(sqrt(float(distanceSquared(
      points[i - 1].x, points[i - 1].y, points[i].x, points[i].y
    ))))

proc walkMinutes(bot: Bot, pixels: int): int =
  ## Converts a walking distance into game minutes at this game's clock
  ## rate, rounded up to a multiple of five.
  let ticks = float(pixels) / WalkPixelsPerTick * WalkTimeFudge
  let minutes = ticks / max(0.1, bot.ticksPerMinute)
  max(5, (int(minutes) + 4) div 5 * 5)

proc walkPixelsToHouse(bot: Bot, houseIndex: int): int =
  ## Returns the walking distance in pixels to one house door, going
  ## through the home exit first when inside a house. -1 when unknown.
  if houseIndex < 0 or houseIndex >= bot.resources.houseValid.len or
      not bot.resources.houseValid[houseIndex] or bot.mainNav == nil:
    return -1
  let house = bot.resources.houses[houseIndex]
  if bot.screenKind == MainMap:
    let path = bot.mainNav.pathTo(bot.playerFootX(), bot.playerFootY(), house)
    if path.len == 0:
      return -1
    return path.pathLengthPixels()
  if bot.screenKind == HomeMap and bot.currentHouse >= 0:
    if bot.currentHouse == houseIndex:
      return 0
    var pixels = 0
    if bot.homeNav != nil and bot.resources.hasExit:
      pixels += bot.homeNav.pathTo(
        bot.playerFootX(), bot.playerFootY(), bot.resources.exit
      ).pathLengthPixels()
    let here = bot.resources.houses[bot.currentHouse].center()
    let path = bot.mainNav.pathTo(here.x, here.y, house)
    if path.len == 0:
      return -1
    return pixels + path.pathLengthPixels()
  -1

proc walkMinutesText(bot: Bot): string =
  ## Returns "Anton=35, Yura=70, ..." walk times in game minutes to each
  ## house door from where the bot stands now, so it can leave in time.
  for houseIndex in 0 ..< HouseCount:
    let pixels = bot.walkPixelsToHouse(houseIndex)
    if pixels < 0:
      continue
    if result.len > 0:
      result.add(", ")
    result.add(houseIndex.playerNameForHouse() & "=" &
      $bot.walkMinutes(pixels))
  if result.len == 0:
    result = "unknown"

proc leaveByText(bot: Bot, houseIndex: int): string =
  ## Returns the latest clock time to start walking to one house and be
  ## inside before dinner, with a small margin, or "now, you are late".
  let pixels = bot.walkPixelsToHouse(houseIndex)
  if pixels < 0:
    return "unknown"
  let leaveAt = DinnerMinutes - bot.walkMinutes(pixels) - LeaveMarginMinutes
  if bot.minutes >= DinnerMinutes:
    return "dinner has passed"
  if bot.minutes >= leaveAt:
    return "now, you are late"
  leaveAt.clockName()

proc nightLeaveByText(bot: Bot): string =
  ## Returns the latest clock time to start walking home to be inside
  ## when the day ends at 10:00pm.
  let pixels = bot.walkPixelsToHouse(bot.homeIndex)
  if pixels < 0:
    return "unknown"
  let leaveAt = DayEndMinutes - bot.walkMinutes(pixels) - LeaveMarginMinutes
  if bot.minutes >= leaveAt:
    return "now, you are late"
  leaveAt.clockName()

proc dinnerTimingText(bot: Bot): string =
  ## Returns dinner countdown facts: minutes left, when to leave for home,
  ## and when to leave for the committed party house.
  let left = DinnerMinutes - bot.minutes
  result =
    if left > 0:
      "minutesUntilDinner=" & $left & "\n"
    else:
      "minutesUntilDinner=0 (dinner time has passed today)\n"
  result.add("leaveForOwnHouseBy=" & bot.leaveByText(bot.homeIndex) &
    " (only if you host at home; nobody eats at home alone)\n")
  result.add("leaveForNightBy=" & bot.nightLeaveByText() & "\n")
  if bot.committedPartyHouse >= 0 and
      bot.committedPartyHouse != bot.homeIndex:
    result.add("leaveForCommittedPartyBy=" &
      bot.leaveByText(bot.committedPartyHouse) & " (" &
      bot.committedPartyHouse.playerNameForHouse() & "'s house)\n")

proc saidTodayText(bot: Bot): string =
  ## Returns the last few lines the bot said today, oldest first, so the
  ## model can avoid saying them again.
  const MaxLines = 8
  if bot.saidToday.len == 0:
    return "none"
  let start = max(0, bot.saidToday.len - MaxLines)
  for i in start ..< bot.saidToday.len:
    if result.len > 0:
      result.add(" | ")
    result.add("\"" & bot.saidToday[i] & "\"")

proc locationText(bot: Bot): string =
  ## Says plainly whether the bot is inside a house or outside, because
  ## dinner is only served to gnomes who are inside at 6pm.
  if bot.screenKind == HomeMap and bot.currentHouse >= 0:
    if bot.currentHouse == bot.homeIndex:
      return "inside your own house"
    return "inside " & bot.currentHouse.playerNameForHouse() & "'s house"
  if bot.screenKind == MainMap:
    return "outside on the world map (not inside any house)"
  "unknown"

proc llmUserPrompt(bot: Bot): string =
  ## Builds one current-state report for the LLM. Facts only: what the
  ## clock says, where the bot is, what it carries and still wants, whom
  ## it sees and has greeted, and which actions exist. Strategy and
  ## manners live in the soul.
  let
    commitment =
      if bot.committedPartyHouse >= 0:
        bot.committedPartyHouse.playerNameForHouse() & "'s house"
      else:
        "none"
    commitmentIndex =
      if bot.committedPartyHouse >= 0:
        $(bot.committedPartyHouse + 1)
      else:
        "none"
    currentHouse =
      if bot.currentHouse >= 0:
        $(bot.currentHouse + 1)
      else:
        "none"
    currentHouseOwner =
      if bot.currentHouse >= 0:
        bot.currentHouse.playerNameForHouse()
      else:
        "none"
  result =
    "Current Heartleaf state:\n" &
    "day=" & $bot.dayNumber & "\n" &
    "clock=" & bot.minutes.clockName() & "\n" &
    "timeMinutes=" & $bot.minutes & "\n" &
    "map=" & bot.screenKind.screenNameForPrompt() & "\n" &
    "location=" & bot.locationText() & "\n" &
    "walkMinutesToHouse=" & bot.walkMinutesText() & "\n" &
    bot.dinnerTimingText() &
    "homeOwner=" & bot.homeIndex.playerNameForHouse() & "\n" &
    "homeHouseIndex=" & $(bot.homeIndex + 1) & "\n" &
    "currentHouseOwner=" & currentHouseOwner & "\n" &
    "currentHouseIndex=" & currentHouse & "\n" &
    "foodTotal=" & $bot.inventoryTotal() & "\n" &
    "foodCollected=" & bot.collectedFoodsText() & "\n" &
    "foodLookingFor=" & bot.lookingForFoodsText() & "\n" &
    "partyCommitment=" & commitment & "\n" &
    "partyCommitmentHouseIndex=" & commitmentIndex & "\n" &
    "yourLinesToday=" & bot.saidTodayText() & "\n" &
    "greetedToday=" & bot.greetedToday.namesText() & "\n" &
    "seenTodayNotGreeted=" & bot.notYetGreetedText() & "\n" &
    "visiblePlayers:\n" & bot.visiblePlayersText() & "\n" &
    "visibleHouseCrowds:\n" & bot.houseCrowdsText() & "\n" &
    "gardenMarkers=" & bot.gardenMarkersText() & "\n" &
    "Return JSON now."

proc dueCommitment(bot: Bot): LlmDecision =
  ## Returns the decision that carries out what the model itself already
  ## committed to (commitParty in an earlier reply), once its time has
  ## come: go_to_party at the house it promised, or go_home when it
  ## invited people to its own table, from the latest departure time
  ## until dinner is over. Invalid when nothing is due. This adds no
  ## policy of its own: it only keeps a promise the soul-driven model
  ## made, and only while the LLM cannot be asked; a fresh reply always
  ## replaces it.
  result = LlmDecision(valid: false, action: LlmInvalid,
    houseIndex: UnknownHouse, untilMinutes: -1)
  if bot.committedPartyHouse < 0 or bot.minutes >= DinnerMinutes + 60:
    return
  let pixels = bot.walkPixelsToHouse(bot.committedPartyHouse)
  if pixels < 0:
    return
  let leaveAt = DinnerMinutes - bot.walkMinutes(pixels) - LeaveMarginMinutes
  if bot.minutes < leaveAt:
    return
  if bot.committedPartyHouse == bot.homeIndex:
    result = LlmDecision(valid: true, action: LlmGoHome,
      houseIndex: UnknownHouse, untilMinutes: -1,
      reason: "fallback: keeping the promise to host at home")
  else:
    result = LlmDecision(valid: true, action: LlmGoToParty,
      houseIndex: bot.committedPartyHouse,
      targetName: bot.committedPartyHouse.playerNameForHouse(),
      commitParty: true, untilMinutes: -1,
      reason: "fallback: keeping the promise to dine at " &
        bot.committedPartyHouse.playerNameForHouse() & "'s house")

proc fallbackDecision(bot: Bot): LlmDecision =
  ## Returns the decision to play while the LLM is unavailable: a due
  ## commitment the model made earlier, else keep doing what the model
  ## last asked for, minus any chat (a fallback never speaks, so a
  ## pending say_to_person becomes standing next to that person), or
  ## gather plants when nothing was decided yet today.
  let due = bot.dueCommitment()
  if due.valid:
    return due
  if bot.hasDecision and bot.decision.valid:
    result = bot.decision
    result.message = ""
    result.reason = "fallback: repeating last decision"
    if result.action == LlmSayToPerson:
      result.action = LlmStandNextToPerson
    return
  LlmDecision(
    valid: true,
    action: LlmKeepGatheringPlants,
    houseIndex: UnknownHouse,
    reason: "fallback"
  )

proc sameDecisionTarget(a, b: LlmDecision): bool =
  ## Returns true when two decisions steer toward the same place, so the
  ## current path can continue instead of being rebuilt.
  a.action == b.action and
    a.targetName == b.targetName and
    a.houseIndex == b.houseIndex

proc decisionText(decision: LlmDecision): string =
  ## Returns one short prose line describing a decision for the
  ## transcript.
  result = "I decide: " & decision.action.actionName()
  if decision.targetName.len > 0:
    result.add(" " & decision.targetName)
  if decision.houseIndex >= 0:
    result.add(" at " & decision.houseIndex.playerNameForHouse() & "'s house")
  if decision.untilMinutes >= 0:
    result.add(" until " & decision.untilMinutes.clockName())
  if decision.reason.len > 0:
    result.add(" - " & decision.reason)

proc applyDecision(bot: Bot, decision: LlmDecision, fromLlm = false) =
  ## Stores one decision and updates the party commitment bookkeeping.
  ## The current path survives when the new decision heads for the same
  ## place, so a repeated "keep gathering" does not stutter. Only real
  ## model decisions are written to the transcript.
  var nextDecision =
    if decision.valid:
      decision
    else:
      bot.fallbackDecision()
  nextDecision = bot.inferSocialCommitment(nextDecision)
  let commitHouse =
    if nextDecision.houseIndex >= 0:
      nextDecision.houseIndex
    elif nextDecision.commitParty:
      bot.homeIndex
    else:
      UnknownHouse
  if nextDecision.action == LlmGoToParty and commitHouse >= 0:
    bot.committedPartyHouse = commitHouse
    nextDecision.houseIndex = commitHouse
    nextDecision.commitParty = true
  elif nextDecision.commitParty and commitHouse >= 0:
    bot.committedPartyHouse = commitHouse
    nextDecision.houseIndex = commitHouse
  let keepPath = bot.hasDecision and
    bot.decision.sameDecisionTarget(nextDecision)
  bot.decision = nextDecision
  bot.hasDecision = true
  bot.decisionChatSent = false
  bot.decisionStartedTick = bot.frameTick
  bot.decisionState = bot.decisionStateSignature()
  bot.decisionFoodBand = bot.foodBand()
  bot.decisionTimePhase = bot.timePhase()
  bot.decisionChatSignature = bot.visibleChatsSignature()
  bot.decisionCrowdSignature = bot.houseCrowdsSignature()
  bot.decisionVisibleNames = bot.visibleGnomeNames()
  bot.interruptRequested = false
  if not keepPath:
    bot.path.setLen(0)
    bot.goal = Goal(kind: GoalIdle, screenKind: UnknownScreen)
  ## A decision that merely continues the previous one (another "keep
  ## gathering") is not worth a transcript line.
  if fromLlm and decision.valid and not keepPath:
    bot.recordOwnDecision(nextDecision.decisionText())
  bot.log(
    "llm action " & nextDecision.action.actionName() &
    " house=" & $(nextDecision.houseIndex + 1) &
    " target=" & nextDecision.targetName &
    " message=" & nextDecision.message &
    " reason=" & nextDecision.reason
  )

proc applyLlmReply(bot: Bot, reply: string) =
  ## Parses and applies one LLM reply.
  let decision = reply.parseLlmDecision(bot.selfNames())
  if not decision.valid:
    bot.lastLlmError = decision.error
    bot.log("llm parse error " & decision.error)
  bot.applyDecision(decision, fromLlm = true)

proc startLlmDecision(bot: Bot): bool =
  ## Starts a Bedrock decision request or applies an immediate fallback.
  let mockReply = mockBedrockReply()
  if mockReply.len > 0:
    bot.applyLlmReply(mockReply)
    return false
  inc bot.llmSerial
  bot.llmTag = "decision-" & $bot.llmSerial
  bot.trimChatHistory()
  var messages = @[
    ConversationMessage(role: "system", content: bot.soulInstructions)
  ]
  for message in bot.chatHistory:
    messages.add(message)
  messages.add(
    ConversationMessage(role: "user", content: bot.llmUserPrompt())
  )
  var started = false
  try:
    started = startTalkToBedrock(messages, bot.llmTag)
  except CatchableError as e:
    let answer = BedrockResult(done: true, error: e.msg)
    if answer.transientBedrockError():
      bot.lastLlmError = e.msg
      let wait = bot.llmPacer.noteTransientError(epochTime())
      bot.log("llm transient start error " & e.msg & ", backing off " &
        formatFloat(wait, ffDecimal, 1) & "s, using fallback")
      bot.applyDecision(bot.fallbackDecision())
      return false
    raise newException(
      TalkingVillagerError,
      "Could not start Bedrock request: " & e.msg
    )
  if not started:
    raise newException(TalkingVillagerError, BedrockNotConfiguredMessage)
  bot.llmWaiting = true
  let now = epochTime()
  bot.llmPacer.noteRequest(now)
  bot.decisionStartedTick = bot.frameTick
  let latency = bedrockPerformanceLatency()
  let latencyName =
    if latency.len > 0:
      latency
    else:
      "default"
  ## rpm is this bot's requests in the trailing real minute, including
  ## this one, so a log can be profiled for request rate at a glance.
  bot.log(
    "llm request " & bot.llmTag &
    " model=" & bedrockModel() &
    " region=" & bedrockRegion() &
    " latency=" & latencyName &
    " rpm=" & $bot.llmPacer.requestsInLastMinute(now)
  )
  return true

proc pollLlmDecision(bot: Bot): bool =
  ## Polls and applies a completed LLM request.
  if not bot.llmWaiting:
    return false
  let answer = pollTalkToBedrock()
  if not answer.done:
    return false
  if answer.tag != bot.llmTag:
    return false
  bot.llmWaiting = false
  if answer.ok:
    bot.llmPacer.noteSuccess()
    bot.log("llm reply " & answer.tag & " " & answer.usage)
    bot.applyLlmReply(answer.reply)
  else:
    bot.lastLlmError = answer.error
    bot.log("llm error status=" & $answer.statusCode & " " & answer.error)
    if promptCacheEnabled and answer.statusCode == 400 and
        answer.error.toLowerAscii().contains("cache"):
      ## The endpoint rejected cache_control; send plain requests from
      ## now on instead of treating this as a fatal request error.
      promptCacheEnabled = false
      bot.log("llm prompt caching rejected, disabled for this game")
      bot.applyDecision(bot.fallbackDecision())
      return true
    if answer.permanentBedrockError():
      raise newException(
        TalkingVillagerError,
        "Bedrock request failed: " & answer.error
      )
    ## Transient errors and unusable 200 bodies (empty text, parse
    ## failures) both keep the bot in the game on the scripted fallback.
    if answer.transientBedrockError():
      let daily = answer.dailyQuotaError()
      let wait = bot.llmPacer.noteTransientError(
        epochTime(), answer.retryAfter, daily
      )
      bot.log(
        (if daily: "llm daily quota spent" else: "llm transient error") &
        ", failure " & $bot.llmPacer.consecutiveFailures() &
        " in a row, backing off " & formatFloat(wait, ffDecimal, 1) &
        "s" &
        (if answer.retryAfter > 0.0:
          " (retry-after " & formatFloat(answer.retryAfter, ffDecimal, 0) & "s)"
        else:
          "") &
        ", using fallback"
      )
    else:
      bot.log("llm error is not permanent, using fallback")
    bot.applyDecision(bot.fallbackDecision())
  return true

proc decisionGoal(bot: Bot, decision: LlmDecision): Goal =
  ## Converts one LLM decision into a deterministic navigation goal.
  case decision.action
  of LlmKeepGatheringPlants:
    if bot.screenKind == HomeMap:
      return bot.exitGoal()
    if bot.screenKind == MainMap:
      let garden = bot.gardenGoal()
      if garden.kind != GoalIdle:
        return garden
    Goal(kind: GoalIdle, screenKind: bot.screenKind)
  of LlmFindPerson, LlmStandNextToPerson, LlmSayToPerson:
    bot.standNextToPersonGoal(decision.targetName)
  of LlmFindHouse, LlmStandAtHouseGarden:
    let houseIndex = bot.decisionHouse(decision)
    if houseIndex < 0:
      return Goal(kind: GoalIdle, screenKind: bot.screenKind)
    bot.gatherAtHouseGoal(houseIndex)
  of LlmGoHome:
    bot.ownHomeGoal()
  of LlmGoToParty:
    let houseIndex = bot.decisionHouse(decision)
    if houseIndex < 0:
      return bot.ownHomeGoal()
    if bot.screenKind == HomeMap:
      if bot.currentHouse == houseIndex:
        return bot.firstDinerGoal()
      return bot.exitGoal()
    if bot.screenKind == MainMap:
      return bot.enterHouseGoal(houseIndex)
    Goal(kind: GoalIdle, screenKind: bot.screenKind)
  of LlmStayInside:
    ## Stay where you are when inside; when outside, head for the house
    ## you promised, else home.
    if bot.screenKind == HomeMap:
      return bot.firstDinerGoal()
    if bot.screenKind == MainMap:
      let houseIndex =
        if bot.committedPartyHouse >= 0:
          bot.committedPartyHouse
        else:
          bot.homeIndex
      return bot.enterHouseGoal(houseIndex)
    Goal(kind: GoalIdle, screenKind: bot.screenKind)
  of LlmInvalid:
    Goal(kind: GoalIdle, screenKind: bot.screenKind)

proc chooseGoal(bot: Bot): Goal =
  ## Chooses the current LLM-backed Heartleaf goal.
  if not bot.localized or bot.navForCurrentMap() == nil:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  if bot.screenKind == OverlayScreen:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  if not bot.hasDecision:
    return Goal(kind: GoalIdle, screenKind: bot.screenKind)
  bot.decisionGoal(bot.decision)

proc goalReached(bot: Bot, goal: Goal): bool =
  ## Returns true when the bot is close enough to a goal to act.
  case goal.kind
  of GoalCollect:
    if goal.gardenIndex >= 0 and
        goal.gardenIndex < bot.resources.gardens.len:
      return pointRectDistanceSquared(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.gardens[goal.gardenIndex]
      ) <= CollectActionRadius * CollectActionRadius
    distanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    ) <= CollectActionRadius * CollectActionRadius
  of GoalEnterHouse:
    let house = bot.resources.houses[goal.houseIndex]
    house.contains(bot.playerFootX(), bot.playerFootY())
  of GoalExitHouse:
    bot.resources.exit.contains(bot.playerFootX(), bot.playerFootY())
  of GoalStandPerson:
    distanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    ) <= PersonStandRadius * PersonStandRadius
  of GoalGatherHouse, GoalMove:
    distanceSquared(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    ) <= GoalArrivePixels * GoalArrivePixels
  of GoalIdle:
    true

proc goalLabel(goal: Goal): string =
  ## Returns a short debug label for one goal.
  case goal.kind
  of GoalIdle:
    "idle"
  of GoalCollect:
    "collect garden " & $goal.gardenIndex
  of GoalGatherHouse:
    "gather outside house " & $(goal.houseIndex + 1)
  of GoalEnterHouse:
    "enter house " & $(goal.houseIndex + 1)
  of GoalExitHouse:
    "exit house"
  of GoalStandPerson:
    "stand next to " & goal.targetName
  of GoalMove:
    "wait"

proc interactionMask(bot: Bot, goal: Goal): uint8 =
  ## Returns an A-button pulse when an interaction goal is ready.
  if bot.attackCooldown > 0:
    dec bot.attackCooldown
    return 0
  if not bot.goalReached(goal):
    return 0
  return case goal.kind
  of GoalCollect:
    bot.attackCooldown = 8
    bot.lastCollectTick = bot.frameTick
    if bot.currentGarden == goal.gardenIndex:
      bot.currentGarden = -1
    bot.path.setLen(0)
    bot.log(goal.goalLabel())
    ButtonA
  of GoalExitHouse:
    bot.attackCooldown = 8
    bot.log(goal.goalLabel())
    ButtonA
  of GoalEnterHouse:
    bot.attackCooldown = 8
    bot.pendingHouse = goal.houseIndex
    bot.log(goal.goalLabel())
    ButtonA
  else:
    0

proc decisionComplete(bot: Bot): bool =
  ## Returns true when the current LLM action has completed. A decision
  ## with untilTime keeps going (waiting at a door, gathering, staying
  ## home) until the clock reaches it; interrupts still apply.
  if not bot.hasDecision:
    return true
  if bot.decision.untilMinutes >= 0 and
      bot.decision.action != LlmSayToPerson:
    if bot.decision.action == LlmKeepGatheringPlants and
        not bot.shouldGather():
      return true
    return bot.minutes >= bot.decision.untilMinutes
  return case bot.decision.action
  of LlmKeepGatheringPlants:
    not bot.shouldGather()
  of LlmFindPerson, LlmStandNextToPerson:
    bot.visiblePlayerNear(bot.decision.targetName)
  of LlmSayToPerson:
    bot.decisionChatSent
  of LlmFindHouse, LlmStandAtHouseGarden:
    bot.goal.kind == GoalGatherHouse and bot.goalReached(bot.goal)
  of LlmGoHome:
    bot.screenKind == HomeMap and bot.currentHouse == bot.homeIndex
  of LlmGoToParty:
    let houseIndex = bot.decisionHouse(bot.decision)
    bot.screenKind == HomeMap and bot.currentHouse == houseIndex
  of LlmStayInside:
    ## Staying is open-ended: it ends on untilTime (handled above) or an
    ## interrupt, never by itself.
    false
  of LlmInvalid:
    true

proc farthestWalkMinutes(bot: Bot): int =
  ## Returns the walk time in game minutes to the farthest house door.
  for houseIndex in 0 ..< HouseCount:
    let pixels = bot.walkPixelsToHouse(houseIndex)
    if pixels >= 0:
      result = max(result, bot.walkMinutes(pixels))

proc maybeNoteLeaveTime(bot: Bot) =
  ## Records that a departure time has arrived and flags an interrupt so
  ## the model gets to react; repeats every LeaveNudgeMinutes while the
  ## bot is still outside, since being late gets worse by the minute.
  ## Before dinner the reference point is the committed house, or, with
  ## no commitment, the farthest table (so an undecided bot is told to
  ## choose, not sent home). In the evening it is home, for 10:00pm.
  if bot.screenKind != MainMap or not bot.localized:
    return
  if bot.leaveTimeNoted and
      bot.minutes - bot.leaveTimeNotedMinutes < LeaveNudgeMinutes:
    return
  var text = ""
  if bot.minutes < DinnerMinutes:
    if bot.committedPartyHouse >= 0:
      let pixels = bot.walkPixelsToHouse(bot.committedPartyHouse)
      if pixels < 0:
        return
      let walk = bot.walkMinutes(pixels)
      if bot.minutes < DinnerMinutes - walk - LeaveMarginMinutes:
        return
      let where =
        if bot.committedPartyHouse == bot.homeIndex:
          "your own house, where you host"
        else:
          bot.committedPartyHouse.playerNameForHouse() & "'s house"
      text = "Latest departure time for dinner: walking to " & where &
        " takes about " & $walk & " minutes and dinner is at 6:00pm."
    else:
      let walk = bot.farthestWalkMinutes()
      if walk <= 0 or bot.minutes < DinnerMinutes - walk - LeaveMarginMinutes:
        return
      text = "Latest departure time for dinner: you have not promised " &
        "any table yet; the farthest house is about " & $walk &
        " minutes away and dinner is at 6:00pm. Nobody eats at home " &
        "alone; pick a table and go, or host with guests coming."
  elif bot.minutes < DayEndMinutes:
    let pixels = bot.walkPixelsToHouse(bot.homeIndex)
    if pixels < 0:
      return
    let walk = bot.walkMinutes(pixels)
    if bot.minutes < DayEndMinutes - walk - LeaveMarginMinutes:
      return
    text = "Latest departure time for the night: walking home takes " &
      "about " & $walk & " minutes and the day ends at 10:00pm."
  else:
    return
  bot.leaveTimeNoted = true
  bot.leaveTimeNotedMinutes = bot.minutes
  bot.interruptRequested = true
  bot.recordEvent(text)
  bot.log("leave time: " & text)

proc decisionInterrupted(bot: Bot): bool =
  ## Returns true when something happened that the model should react to:
  ## the bot is stuck, a new chat bubble appeared, a gnome was seen for
  ## the first time today, the hour changed, the food band changed, or the
  ## visible house crowds changed. Interrupts wait DecisionRetryTicks after
  ## a decision so a burst of events costs one request, not several.
  if not bot.hasDecision:
    return true
  if bot.frameTick - bot.decisionStartedTick < DecisionRetryTicks:
    return false
  if bot.stuckTicks >= DecisionStuckTicks:
    return true
  if bot.interruptRequested:
    return true
  ## Waiting at a door is for meeting people: a gnome who walks into
  ## view is a reason to ask the model again right now.
  if bot.decision.action in {LlmStandAtHouseGarden, LlmFindHouse}:
    for name in bot.visibleGnomeNames():
      if name notin bot.decisionVisibleNames:
        return true
  let chatSignature = bot.visibleChatsSignature()
  if chatSignature.len > 0 and chatSignature != bot.decisionChatSignature:
    return true
  if bot.timePhase() != bot.decisionTimePhase:
    return true
  if bot.foodBand() != bot.decisionFoodBand:
    return true
  bot.houseCrowdsSignature() != bot.decisionCrowdSignature

proc needsFreshDecision(bot: Bot): bool =
  ## Returns true when the bot should ask the LLM again.
  if bot.llmWaiting:
    return false
  if not bot.hasDecision:
    return true
  bot.decisionComplete() or bot.decisionInterrupted()

proc mayAskLlm(bot: Bot): bool =
  ## Returns true when pacing allows a Bedrock request right now. While
  ## spaced, over the minute budget, or backing off, the bot keeps
  ## playing its current or fallback decision instead (the fallback
  ## never chats).
  bot.llmPacer.canRequest(epochTime())

proc normalizedChatLine(message: string): string =
  ## Normalizes chat for whole-game duplicate detection.
  var pendingWhitespace = false
  for ch in message.toLowerAscii:
    if (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9'):
      if pendingWhitespace and result.len > 0:
        result.add(' ')
      result.add(ch)
      pendingWhitespace = false
    elif ch in {' ', '\t', '\r', '\n'}:
      pendingWhitespace = true

proc chatTokenSet(message: string): HashSet[string] =
  ## Splits a normalized chat line into unique word tokens.
  result = initHashSet[string]()
  for token in message.splitWhitespace:
    result.incl(token)

proc chatLinesHighlySimilar(left, right: string): bool =
  ## Returns true when two chat lines have at least 85% token overlap.
  let leftTokens = chatTokenSet(left)
  let rightTokens = chatTokenSet(right)
  if leftTokens.len == 0 or rightTokens.len == 0:
    return false
  var intersection = 0
  for token in leftTokens:
    if token in rightTokens:
      inc intersection
  let unionSize = leftTokens.len + rightTokens.len - intersection
  float(intersection) / float(unionSize) >= ChatSimilarityThreshold

proc duplicateChatReason(
  bot: Bot,
  normalized,
  targetName: string
): string =
  ## Returns why a normalized chat line should be suppressed, if any.
  if normalized.len == 0:
    return
  for prior in bot.saidToday:
    if normalizedChatLine(prior) == normalized:
      return "already said today"
  var gameCount = 0
  for prior in bot.saidGame:
    if prior.normalized != normalized:
      continue
    inc gameCount
    if prior.targetName == targetName:
      if targetName.len > 0:
        return "already said to " & targetName
      return "already said with the same target"
  if gameCount >= 2:
    return "already said twice in game"
  let start = max(0, bot.saidGame.len - RecentChatLines)
  for i in start ..< bot.saidGame.len:
    if bot.saidGame[i].normalized == normalized:
      continue
    if chatLinesHighlySimilar(normalized, bot.saidGame[i].normalized):
      return "similar to a recent line"

proc maybeSendDecisionChat(bot: Bot, ws: WebSocket) =
  ## Sends the chat text chosen by the current LLM decision.
  if not bot.hasDecision or bot.decisionChatSent:
    return
  if bot.decision.action != LlmSayToPerson:
    return
  if bot.decision.message.len == 0:
    bot.decisionChatSent = true
    return
  if bot.decision.targetName.len > 0 and
      not bot.visiblePlayerNear(bot.decision.targetName):
    return
  let normalized = normalizedChatLine(bot.decision.message)
  let duplicateReason = bot.duplicateChatReason(
    normalized,
    bot.decision.targetName
  )
  if duplicateReason.len > 0:
    bot.decisionChatSent = true
    inc bot.chatSuppressedCount
    bot.log("chat suppressed, " & duplicateReason & ": " &
      bot.decision.message)
    return
  ws.send(blobFromChat(bot.decision.message), BinaryMessage)
  bot.recordOwnChat(bot.decision.message)
  bot.saidToday.add(bot.decision.message)
  bot.saidGame.add(ChatLine(
    normalized: normalized,
    targetName: bot.decision.targetName
  ))
  inc bot.chatSentCount
  bot.decisionChatSent = true
  if bot.decision.targetName.len > 0:
    bot.greetedToday.incl(bot.decision.targetName)
  bot.log("chat " & bot.decision.message)

proc ensurePath(bot: Bot, goal: Goal) =
  ## Recomputes the path when the navigation goal changes.
  let changed = not bot.goal.sameGoal(goal)
  if not changed and bot.path.len > 0 and bot.stuckTicks < RepathStuckTicks:
    return
  if changed:
    bot.log("goal " & goal.goalLabel())
  bot.goal = goal
  bot.path.setLen(0)
  let nav = bot.navForCurrentMap()
  if nav == nil or goal.kind == GoalIdle:
    return
  case goal.kind
  of GoalCollect:
    if goal.gardenIndex >= 0 and
        goal.gardenIndex < bot.resources.gardens.len:
      bot.path = nav.pathNear(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.gardens[goal.gardenIndex],
        CollectActionRadius
      )
  of GoalEnterHouse:
    if goal.houseIndex >= 0 and
        goal.houseIndex < bot.resources.houseValid.len and
        bot.resources.houseValid[goal.houseIndex]:
      bot.path = nav.pathTo(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.houses[goal.houseIndex]
      )
  of GoalExitHouse:
    if bot.resources.hasExit:
      bot.path = nav.pathTo(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.resources.exit
      )
  else:
    bot.path = nav.pathTo(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    )
  if bot.path.len == 0:
    bot.path = nav.pathTo(
      bot.playerFootX(),
      bot.playerFootY(),
      goal.x,
      goal.y
    )

proc pathTarget(bot: Bot, goal: Goal): Point =
  ## Returns the current lookahead point along the path.
  if goal.kind == GoalIdle:
    # An idle goal has no coordinates; stand still instead of
    # marching toward the map origin.
    return Point(x: bot.playerFootX(), y: bot.playerFootY())
  result = Point(x: goal.x, y: goal.y)
  if bot.path.len > 1:
    var
      bestIndex = 0
      bestDistance = high(int)
    for i, point in bot.path:
      let distance = distanceSquared(
        bot.playerFootX(),
        bot.playerFootY(),
        point.x,
        point.y
      )
      if distance < bestDistance:
        bestIndex = i
        bestDistance = distance
    if bestIndex > 0 and
        bestDistance <= PathRejoinPixels * PathRejoinPixels:
      for _ in 0 ..< bestIndex:
        bot.path.delete(0)
  while bot.path.len > 0 and
      distanceSquared(
        bot.playerFootX(),
        bot.playerFootY(),
        bot.path[0].x,
        bot.path[0].y
      ) <= PathArrivePixels * PathArrivePixels:
    bot.path.delete(0)
  if bot.path.len > 0:
    result = bot.path[0]
    let nav = bot.navForCurrentMap()
    if nav != nil and nav.path != nil:
      # Steer toward the farthest waypoint with a clear line of sight,
      # like notsus, so paths cut corners instead of hugging waypoints.
      for i in 0 ..< min(bot.path.len, SteerLookaheadPoints):
        if nav.path.linePassable(
          bot.playerFootX(),
          bot.playerFootY(),
          bot.path[i].x,
          bot.path[i].y
        ):
          result = bot.path[i]
        else:
          break

proc needsMovement(bot: Bot, target: Point): bool =
  ## Returns true when a target is far enough to require button input.
  abs(target.x - bot.playerFootX()) > MoveDeadZonePixels or
    abs(target.y - bot.playerFootY()) > MoveDeadZonePixels

proc coastPixels(speed: int): int =
  ## Approximates how far crewrift friction coasts one speed estimate.
  ## Friction 144/256 leaves a geometric tail of about 9/7 of one tick.
  (abs(speed) * 9) div 7

proc axisMask(delta, speed: int, negativeMask, positiveMask: uint8): uint8 =
  ## Returns one axis input, coasting when momentum already arrives.
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

proc movementMask(bot: Bot, target: Point): uint8 =
  ## Builds a directional input mask with arrival coasting so momentum
  ## does not overshoot the target and wobble back and forth.
  axisMask(
    target.x - bot.playerFootX(),
    bot.velEstX,
    ButtonLeft,
    ButtonRight
  ) or axisMask(
    target.y - bot.playerFootY(),
    bot.velEstY,
    ButtonUp,
    ButtonDown
  )

proc firstMovingPathTarget(bot: Bot, goal: Goal): Point =
  ## Returns the first path point that can actually produce movement.
  if goal.kind == GoalIdle:
    return Point(x: bot.playerFootX(), y: bot.playerFootY())
  for point in bot.path:
    if bot.needsMovement(point):
      return point
  result = Point(x: goal.x, y: goal.y)

proc decideNextMask(bot: Bot, ws: WebSocket): uint8 =
  ## Chooses the next input mask for one game frame. A Bedrock request in
  ## flight never stops the bot: it keeps walking, collecting, and
  ## chatting on its current decision until the reply replaces it. Stuck
  ## detection is paused while waiting so a stale decision cannot trigger
  ## a stuck interrupt before the new one lands.
  bot.analyze()
  bot.scanHeardChats()
  bot.scanSeenGnomes()
  bot.maybeRecordClock()
  bot.maybeRecordCarry()
  bot.maybeRecordDinner()
  bot.maybeNoteLeaveTime()
  if not bot.localized:
    bot.desiredMask = 0
    bot.hasTarget = false
    return 0
  discard bot.pollLlmDecision()
  if bot.needsFreshDecision():
    if bot.mayAskLlm():
      discard bot.startLlmDecision()
    else:
      let fallback = bot.fallbackDecision()
      if not bot.hasDecision or
          not bot.decision.sameDecisionTarget(fallback):
        bot.applyDecision(fallback)
  elif bot.llmWaiting:
    ## A request may hang for seconds that are hours of game time; a
    ## commitment that comes due meanwhile is carried out at once, and
    ## the reply, when it lands, still replaces it.
    let due = bot.dueCommitment()
    if due.valid and not bot.decision.sameDecisionTarget(due):
      bot.applyDecision(due)
  let goal = bot.chooseGoal()
  let action = bot.interactionMask(goal)
  if action != 0:
    bot.desiredMask = action
    bot.hasTarget = false
    bot.updateStuck(if bot.llmWaiting: 0'u8 else: action)
    return action
  bot.ensurePath(goal)
  var target = bot.pathTarget(goal)
  bot.target = target
  bot.hasTarget = goal.kind != GoalIdle
  result = bot.movementMask(target)
  if result == 0 and not bot.goalReached(goal):
    target = bot.firstMovingPathTarget(goal)
    bot.target = target
    result = bot.movementMask(target)
  if bot.unstuckTicks > 0 and result != 0:
    result = UnstuckMasks[bot.unstuckMaskIndex]
  bot.desiredMask = result
  bot.updateStuck(if bot.llmWaiting: 0'u8 else: result)

proc queryEscape(value: string): string =
  ## Escapes a query string component.
  const Hex = "0123456789ABCDEF"
  for ch in value:
    if ch.isAlphaNumeric() or ch in {'-', '_', '.', '~'}:
      result.add(ch)
    else:
      let byte = ord(ch)
      result.add('%')
      result.add(Hex[(byte shr 4) and 0x0f])
      result.add(Hex[byte and 0x0f])

proc queryParam(url, name: string): string =
  ## Returns one raw query parameter value from a URL.
  let queryAt = url.find('?')
  if queryAt < 0:
    return
  var stop = url.find('#')
  if stop < 0:
    stop = url.len
  if queryAt + 1 >= stop:
    return
  for part in url[queryAt + 1 ..< stop].split('&'):
    let equalsAt = part.find('=')
    if equalsAt < 0:
      if part == name:
        return ""
      continue
    if part[0 ..< equalsAt] == name:
      return part[equalsAt + 1 .. ^1]

proc slotFromUrl(url: string): int =
  ## Returns the slot query value from a Coworld websocket URL.
  result = -1
  let text = url.queryParam("slot")
  if text.len == 0:
    return
  try:
    result = parseInt(text)
  except ValueError:
    result = -1

proc playerUrl(
  host: string,
  port: int,
  name,
  token: string,
  slot: int
): string =
  ## Builds the Heartleaf player websocket URL.
  result = "ws://" & host & ":" & $port & "/player"
  var sep = '?'
  if name.len > 0:
    result.add(sep)
    result.add("username=" & name.queryEscape())
    sep = '&'
  if slot >= 0:
    result.add(sep)
    result.add("slot=" & $slot)
    sep = '&'
  if token.len > 0:
    result.add(sep)
    result.add("token=" & token.queryEscape())

proc acceptServerMessage(ws: WebSocket, message: Message, bot: Bot): bool =
  ## Handles one websocket message and updates sprite state.
  case message.kind
  of BinaryMessage:
    result = bot.applySpritePacket(message.data)
    inc bot.frameTick
  of Ping:
    ws.send(message.data, Pong)
  of TextMessage, Pong:
    discard

proc receiveUpdates(ws: WebSocket, bot: Bot): bool =
  ## Receives and applies all currently queued sprite updates.
  let firstMessage = ws.receiveMessage(-1)
  if firstMessage.isNone:
    return false
  if ws.acceptServerMessage(firstMessage.get(), bot):
    result = true
  var drained = 0
  while drained < MaxDrainMessages:
    let message = ws.receiveMessage(0)
    if message.isNone:
      break
    if ws.acceptServerMessage(message.get(), bot):
      result = true
    inc drained

proc runBot(
  host: string,
  port: int,
  name,
  token: string,
  slot: int,
  url: string,
  soul: string,
  exitOnDisconnect: bool
) =
  ## Connects the talking Villager bot to a Heartleaf sprite player endpoint.
  let connectUrl =
    if url.len > 0:
      url
    else:
      playerUrl(host, port, name, token, slot)
  var bot = initBot(name, slot, soul)
  try:
    requireBedrockConfig()
  except TalkingVillagerError as e:
    echo bot.name, " fatal: ", e.msg
    bot.logChatSummary()
    quit(1)
  ## Hosted runs (exitOnDisconnect) keep reconnecting through mid-game
  ## drops and only exit once the server has been unreachable for
  ## ReconnectGiveUpSeconds, which is what the end of the game looks like.
  var hadConnection = false
  var disconnectedAt = 0.0
  while true:
    try:
      let ws = newWebSocket(connectUrl)
      echo bot.name, " connected to ", connectUrl
      hadConnection = true
      disconnectedAt = 0.0
      bot.lastMask = 0xff'u8
      while true:
        if not ws.receiveUpdates(bot):
          continue
        let nextMask = bot.decideNextMask(ws)
        bot.maybeSendDecisionChat(ws)
        if nextMask != bot.lastMask:
          ws.send(blobFromMask(nextMask), BinaryMessage)
          bot.lastMask = nextMask
    except TalkingVillagerError as e:
      echo bot.name, " fatal: ", e.msg
      bot.logChatSummary()
      quit(1)
    except CatchableError as e:
      echo bot.name, " reconnecting: ", e.msg
      if exitOnDisconnect and hadConnection:
        if disconnectedAt == 0.0:
          disconnectedAt = epochTime()
        elif epochTime() - disconnectedAt > ReconnectGiveUpSeconds:
          echo bot.name, " server gone for ", ReconnectGiveUpSeconds,
            "s, exiting"
          break
      sleep(ReconnectDelayMs)
  bot.logChatSummary()

proc talkingVillagerMain*(defaultName = DefaultName, soul: string) =
  ## Parses bot CLI options and runs one talking Villager bot.
  var
    address = DefaultHost
    port = DefaultPort
    name = defaultName
    token = ""
    slot = -1
    url = getEnv("COGAMES_ENGINE_WS_URL")
  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "address":
        address = val
      of "port":
        port = parseInt(val)
      of "name":
        name = val
      of "token":
        token = val
      of "slot":
        slot = parseInt(val)
      of "url":
        url = val
      else:
        discard
    else:
      discard
  if slot < 0 and url.len > 0:
    slot = url.slotFromUrl()
  runBot(address, port, name, token, slot, url, soul, url.len > 0)

when isMainModule:
  const ExampleSoulMarkdown = staticRead("soul.md")
  talkingVillagerMain(DefaultName, ExampleSoulMarkdown)
