import std/[json, random, strutils]

import heartleaf/[common, protocol]

const
  UnknownHouse = -1
  ## Bedrock pacing, in wall-clock seconds. Every villager in every hosted
  ## game shares one account-wide Bedrock quota, so a bot that re-asks the
  ## moment a throttled reply comes back turns one busy minute into a
  ## request storm that silences every table on the account. Three
  ## limits apply, all measured in real time (throttling is real time, so
  ## game ticks would under-wait whenever a sim runs faster than 24 Hz):
  ## a floor between two requests, a rolling per-minute budget, and an
  ## exponential backoff after a throttled or otherwise transient failure
  ## (jittered so nine bots do not retry in lockstep). A Retry-After header
  ## from the endpoint always wins over the computed wait.
  LlmMinRequestSeconds* = 4.0
  LlmRequestsPerMinute* = 10
  LlmBackoffMinSeconds* = 8.0
  LlmBackoffMaxSeconds* = 100.0
  LlmDailyBackoffMinSeconds* = 8.0
  LlmDailyBackoffMaxSeconds* = 100.0
  LlmBackoffJitter = 0.5
  LlmBudgetWindowSeconds = 60.0
  ## Fatal: a villager without an LLM must not play (scripted chat is not
  ## allowed in the league), so it exits with this message instead.
  BedrockNotConfiguredMessage* =
    "Bedrock is not configured: set AWS_BEARER_TOKEN_BEDROCK or " &
    "BEDROCK_KEY, provide AWS credentials via env keys, the container " &
    "endpoint, or IRSA web identity, or upload the policy with " &
    "coworld upload-policy --use-bedrock."

type
  LlmPacer* = object
    ## Spaces Bedrock requests, keeps them under a per-minute budget, and
    ## backs off after transient failures. Times are epoch seconds.
    requestTimes: seq[float]
    backoffSeconds: float
    blockedUntil: float
    consecutiveFailures: int
    rng: Rand

proc initLlmPacer*(seed: int): LlmPacer =
  ## Returns a pacer that allows an immediate first request.
  result.rng = initRand(seed)

proc pruneRequests(pacer: var LlmPacer, now: float) =
  ## Drops request timestamps that left the budget window.
  var keep: seq[float]
  for time in pacer.requestTimes:
    if now - time < LlmBudgetWindowSeconds:
      keep.add(time)
  pacer.requestTimes = keep

proc requestsInLastMinute*(pacer: LlmPacer, now: float): int =
  ## Returns how many requests started inside the rolling budget window.
  for time in pacer.requestTimes:
    if now - time < LlmBudgetWindowSeconds:
      inc result

proc lastRequestTime(pacer: LlmPacer): float =
  ## Returns when the most recent request started, or a distant past.
  if pacer.requestTimes.len == 0:
    return -1.0e9
  pacer.requestTimes.max()

proc canRequest*(pacer: LlmPacer, now: float): bool =
  ## Returns true when a new Bedrock request may start now: the floor
  ## since the last request has passed, the rolling minute still has
  ## budget, and no backoff is in force.
  now - pacer.lastRequestTime() >= LlmMinRequestSeconds and
    pacer.requestsInLastMinute(now) < LlmRequestsPerMinute and
    ## Tolerate the floating-point boundary at the end of a backoff.
    now + 1.0e-6 >= pacer.blockedUntil

proc noteRequest*(pacer: var LlmPacer, now: float) =
  ## Records that a request started now.
  pacer.pruneRequests(now)
  pacer.requestTimes.add(now)

proc noteSuccess*(pacer: var LlmPacer) =
  ## Clears the backoff after a usable reply.
  pacer.backoffSeconds = 0.0
  pacer.blockedUntil = 0.0
  pacer.consecutiveFailures = 0

proc noteTransientError*(
  pacer: var LlmPacer,
  now: float,
  retryAfter = 0.0,
  dailyQuota = false
): float =
  ## Doubles the backoff after a throttled or transient failure and
  ## returns how many seconds the pacer will now wait. A spent daily
  ## quota uses the long hard-stop tier, and a Retry-After from the
  ## endpoint (seconds) is honored when longer.
  inc pacer.consecutiveFailures
  if dailyQuota:
    ## A daily quota rejection is a long hard stop, not a quick retry.
    pacer.backoffSeconds = LlmDailyBackoffMaxSeconds
  else:
    pacer.backoffSeconds =
      if pacer.backoffSeconds < LlmBackoffMinSeconds:
        LlmBackoffMinSeconds
      else:
        min(pacer.backoffSeconds * 2.0, LlmBackoffMaxSeconds)
  let jitter = pacer.backoffSeconds * LlmBackoffJitter * pacer.rng.rand(1.0)
  result = max(pacer.backoffSeconds + jitter, retryAfter)
  pacer.blockedUntil = max(pacer.blockedUntil, now + result)

proc backoffSeconds*(pacer: LlmPacer): float =
  ## Returns the current backoff length without jitter, 0 when healthy.
  pacer.backoffSeconds

proc consecutiveFailures*(pacer: LlmPacer): int =
  ## Returns how many transient failures happened since the last success.
  pacer.consecutiveFailures

proc secondsUntilRequest*(pacer: LlmPacer, now: float): float =
  ## Returns how long until the pacer would allow a request, 0 when open.
  ## The budget window is approximated by the oldest request's expiry.
  var waitUntil = max(pacer.blockedUntil,
    pacer.lastRequestTime() + LlmMinRequestSeconds)
  if pacer.requestsInLastMinute(now) >= LlmRequestsPerMinute:
    var oldest = now
    for time in pacer.requestTimes:
      if now - time < LlmBudgetWindowSeconds and time < oldest:
        oldest = time
    waitUntil = max(waitUntil, oldest + LlmBudgetWindowSeconds)
  max(0.0, waitUntil - now)

type
  LlmActionKind* = enum
    LlmInvalid
    LlmKeepGatheringPlants
    LlmFindPerson
    LlmFindHouse
    LlmGoHome
    LlmStandAtHouseGarden
    LlmStandNextToPerson
    LlmSayToPerson
    LlmGoToParty
    LlmStayInside

  LlmDecision* = object
    valid*: bool
    action*: LlmActionKind
    targetName*: string
    houseIndex*: int
    message*: string
    commitParty*: bool
    ## Optional clock (day minutes) until which the action keeps going,
    ## e.g. wait at the door until 5:15pm; -1 when the action just runs
    ## to completion.
    untilMinutes*: int
    reason*: string
    error*: string

proc cleanDecisionText*(text: string): string =
  ## Returns a printable ASCII chat string capped to Heartleaf chat size.
  for ch in text.strip():
    if result.len >= ChatMaxChars:
      break
    let value = ord(ch)
    if value >= 32 and value < 127:
      result.add(ch)

proc stripOneSelfPrefix(text: string, name: string): string =
  ## Removes one leading "Name:" label naming this bot, tolerating
  ## markdown or bracket decoration like "**Name:**" or "[Name]:".
  ## Returns the text unchanged when it does not start with the label.
  result = text
  if name.len == 0:
    return
  var at = 0
  while at < text.len and text[at] in {'*', '[', '(', '"', ' '}:
    inc at
  if at + name.len > text.len:
    return
  if text[at ..< at + name.len].toLowerAscii() != name.toLowerAscii():
    return
  at += name.len
  while at < text.len and text[at] in {'*', ']', ')', '"', ' '}:
    inc at
  if at >= text.len or text[at] != ':':
    return
  inc at
  while at < text.len and text[at] in {'*', '"', ' '}:
    inc at
  result = text[at .. ^1]

proc stripSelfPrefix*(text: string, selfNames: openArray[string]): string =
  ## Removes leading speaker labels the model wrote for itself, so a bot
  ## named Vova never says "Vova: hello"; the game already shows who is
  ## talking. Repeats until no self label is left.
  result = text.strip()
  while true:
    var changed = false
    for name in selfNames:
      let stripped = result.stripOneSelfPrefix(name)
      if stripped != result:
        result = stripped.strip()
        changed = true
    if not changed or result.len == 0:
      return

proc actionName*(action: LlmActionKind): string =
  ## Returns the JSON action name for one LLM action.
  case action
  of LlmInvalid:
    "invalid"
  of LlmKeepGatheringPlants:
    "keep_gathering_plants"
  of LlmFindPerson:
    "find_person"
  of LlmFindHouse:
    "find_house"
  of LlmGoHome:
    "go_home"
  of LlmStandAtHouseGarden:
    "stand_at_house_garden"
  of LlmStandNextToPerson:
    "stand_next_to_person"
  of LlmSayToPerson:
    "say_to_person"
  of LlmGoToParty:
    "go_to_party"
  of LlmStayInside:
    "stay_inside"

proc parseLlmAction*(text: string): LlmActionKind =
  ## Parses one strict JSON action name.
  case text.strip().toLowerAscii()
  of "keep_gathering_plants":
    LlmKeepGatheringPlants
  of "find_person":
    LlmFindPerson
  of "find_house":
    LlmFindHouse
  of "go_home":
    LlmGoHome
  of "stand_at_house_garden":
    LlmStandAtHouseGarden
  of "stand_next_to_person":
    LlmStandNextToPerson
  of "say_to_person":
    LlmSayToPerson
  of "go_to_party":
    LlmGoToParty
  of "stay_inside", "stay", "stay_here", "wait_inside":
    LlmStayInside
  else:
    LlmInvalid

proc jsonText(text: string): string =
  ## Extracts the first JSON object from model text.
  let
    start = text.find('{')
    stop = text.rfind('}')
  if start < 0 or stop < start:
    return ""
  text[start .. stop]

proc stringField(node: JsonNode, name: string): string =
  ## Reads one optional string field.
  if not node.hasKey(name) or node[name].kind != JString:
    return ""
  node[name].getStr().strip()

proc boolField(node: JsonNode, name: string): bool =
  ## Reads one optional boolean field.
  if not node.hasKey(name) or node[name].kind != JBool:
    return false
  node[name].getBool()

proc houseField(node: JsonNode, name: string): int =
  ## Reads one optional one-based house index as a zero-based index.
  result = UnknownHouse
  if not node.hasKey(name):
    return
  var value = 0
  case node[name].kind
  of JInt:
    value = node[name].getInt()
  of JString:
    try:
      value = parseInt(node[name].getStr().strip())
    except ValueError:
      return
  else:
    return
  if value >= 1 and value <= HouseCount:
    result = value - 1

proc parseUntilMinutes*(node: JsonNode): int =
  ## Reads the optional untilTime field as day minutes: a clock string
  ## like "5:15pm" or "17:15", or an integer of minutes after midnight.
  ## Returns -1 when absent or unreadable.
  result = -1
  if not node.hasKey("untilTime"):
    return
  let value = node["untilTime"]
  case value.kind
  of JInt:
    let minutes = value.getInt()
    if minutes >= 0 and minutes < 24 * 60:
      result = minutes
  of JString:
    let text = value.getStr().strip().toLowerAscii()
    if text.len == 0:
      return
    let clock = text.parseClockMinutes()
    if clock >= 0:
      return clock
    let parts = text.split(':')
    if parts.len == 2:
      try:
        let hour = parseInt(parts[0].strip())
        let minute = parseInt(parts[1].strip())
        if hour in 0 .. 23 and minute in 0 .. 59:
          result = hour * 60 + minute
      except ValueError:
        discard
    else:
      try:
        let minutes = parseInt(text)
        if minutes >= 0 and minutes < 24 * 60:
          result = minutes
      except ValueError:
        discard
  else:
    discard

proc parseLlmDecision*(
  text: string,
  selfNames: openArray[string] = []
): LlmDecision =
  ## Parses one strict LLM decision JSON object. selfNames are the names
  ## this bot goes by; a message that starts with one as a speaker label
  ## has that label removed.
  result = LlmDecision(
    valid: false,
    action: LlmInvalid,
    houseIndex: UnknownHouse,
    untilMinutes: -1
  )
  let body = text.jsonText()
  if body.len == 0:
    result.error = "Decision did not contain a JSON object."
    return
  var node: JsonNode
  try:
    node = parseJson(body)
  except JsonParsingError as e:
    result.error = "Decision JSON could not parse: " & e.msg
    return
  if node.kind != JObject:
    result.error = "Decision JSON must be an object."
    return

  let action = node.stringField("action").parseLlmAction()
  if action == LlmInvalid:
    result.error = "Decision action is missing or unknown."
    return

  result.valid = true
  result.action = action
  result.targetName = node.stringField("targetName")
  result.houseIndex = node.houseField("houseIndex")
  result.message = node.stringField("message")
    .stripSelfPrefix(selfNames).cleanDecisionText()
  result.commitParty = node.boolField("commitParty")
  result.untilMinutes = node.parseUntilMinutes()
  result.reason = node.stringField("reason")

proc foodNamesIn*(text: string): seq[string] =
  ## Returns the food names in "Carrot x2, Beet" style text.
  for part in text.split(","):
    var name = part.strip()
    let at = name.rfind(" x")
    if at > 0 and at + 2 < name.len and name[at + 2].isDigit():
      name = name[0 ..< at]
    if name.len > 0 and name != "none":
      result.add(name)

proc dinnerLabelField*(label, key: string): string =
  ## Returns the value of one "key=value" field in a dinner label. Values
  ## run to the next " key=" or the end, so foods= (which contains
  ## spaces) must be the last field.
  let start = label.find(" " & key & "=")
  if start < 0:
    return ""
  let valueStart = start + key.len + 2
  var stop = label.len
  for other in ["host", "wasHost", "score", "guests", "foods"]:
    if other == key:
      continue
    let at = label.find(" " & other & "=", valueStart)
    if at >= 0 and at < stop:
      stop = at
  label[valueStart ..< stop].strip()
