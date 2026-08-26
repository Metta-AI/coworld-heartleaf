## Bedrock client for the villager brains. Requests run through curly
## without blocking the simulation loop; replies are polled once per frame.
## Certification and local smoke runs have no AWS access, so a mock reply
## from the environment stands in for the model, and tests script replies
## directly.

import
  std/[json, options, os, strutils],
  curly,
  heartleaf/[bedrock_auth, decisions]

const
  BedrockVersion = "bedrock-2023-05-31"
  DefaultBedrockRegion = "us-east-1"
  DefaultBedrockTimeoutSeconds = 20
  DefaultBedrockMaxTokens = 192
  BedrockTemperature = 0.2
  CoworldPlayerSlotHeader* = "X-Coworld-Player-Slot"
  MockReplyEnv* = "HEARTLEAF_MOCK_REPLY"
  BedrockNotConfiguredMessage* =
    "Bedrock is not configured: set AWS_BEARER_TOKEN_BEDROCK or " &
    "BEDROCK_KEY, provide AWS credentials via env keys, the container " &
    "endpoint, or IRSA web identity, or set " & MockReplyEnv &
    " for an offline run."

type
  ReplyOutcome* = enum
    Usable
    Transient
    Permanent

  BedrockRequest* = object
    tag*: string
    modelId*: string
    playerSlot*: int
    playerName*: string
    messages*: seq[ConversationMessage]

  BedrockReply* = object
    tag*: string
    statusCode*: int
    text*: string
    usage*: string
    error*: string
    retryAfter*: float
      ## Seconds the endpoint asked us to wait, 0 when it did not say.
    dailyQuota*: bool
    cacheRejected*: bool
      ## The endpoint rejected the prompt cache fields.
    contextTooLong*: bool
    outcome*: ReplyOutcome

  TransportKind* = enum
    Live
    Scripted

  BedrockClient* = ref object
    kind: TransportKind
    curl: Curly
    promptCacheEnabled*: bool
    mockReply*: string
    inFlight*: int
    started*: seq[BedrockRequest]
      ## Scripted transport only: every request started, for tests.
    queued: seq[BedrockReply]
      ## Replies waiting to be polled (mock and scripted transports).

proc bedrockRegion*(): string =
  ## The AWS Region for Bedrock.
  result = getEnv("AWS_REGION").strip()
  if result.len == 0:
    result = getEnv("AWS_DEFAULT_REGION").strip()
  if result.len == 0:
    result = DefaultBedrockRegion

proc bedrockToken(): string =
  ## The configured Bedrock bearer token, if any.
  result = getEnv("AWS_BEARER_TOKEN_BEDROCK").strip()
  if result.len == 0:
    result = getEnv("BEDROCK_KEY").strip()

proc mockBedrockReply*(): string =
  ## The configured offline reply, empty when the model should be called.
  getEnv(MockReplyEnv).strip()

proc bedrockTimeoutSeconds(): int =
  ## The request timeout.
  let value = getEnv("BEDROCK_TIMEOUT_SECONDS").strip()
  if value.len == 0:
    return DefaultBedrockTimeoutSeconds
  try:
    max(1, int(parseFloat(value)))
  except ValueError:
    DefaultBedrockTimeoutSeconds

proc bedrockMaxTokens(): int =
  ## The maximum response tokens.
  let value = getEnv("BEDROCK_MAX_TOKENS").strip()
  if value.len == 0:
    return DefaultBedrockMaxTokens
  try:
    max(32, parseInt(value))
  except ValueError:
    DefaultBedrockMaxTokens

proc bedrockPerformanceLatency(): string =
  ## The optional Bedrock latency performance setting.
  let value = getEnv("BEDROCK_PERFORMANCE_LATENCY").strip().toLowerAscii()
  if value == "standard" or value == "optimized":
    return value

proc bedrockConfigured*(mockReply = ""): bool =
  ## True when the model can be called, or a mock reply stands in.
  mockReply.len > 0 or mockBedrockReply().len > 0 or
    bedrockToken().len > 0 or hasAwsCredentialSignal()

proc isAnthropicModel*(modelId: string): bool =
  ## True for Claude ids, which use the Anthropic InvokeModel body; every
  ## other provider goes through Bedrock's provider-neutral Converse API.
  let id = modelId.toLowerAscii()
  id.startsWith("anthropic.") or ".anthropic." in id

proc bedrockHost(): string =
  ## The Bedrock Runtime host for the Region.
  "bedrock-runtime." & bedrockRegion() & ".amazonaws.com"

proc bedrockPath(modelId: string): string =
  ## The REST path for one request: InvokeModel for Claude, Converse for
  ## every other provider.
  if modelId.isAnthropicModel():
    "/model/" & modelId.awsUriEncode() & "/invoke"
  else:
    "/model/" & modelId.awsUriEncode() & "/converse"

proc bedrockUrl(modelId: string): string =
  ## The InvokeModel URL, through the sidecar when one is configured.
  let sidecar = sidecarEndpoint()
  if sidecar.len > 0:
    return sidecar.joinUrl(bedrockPath(modelId))
  "https://" & bedrockHost() & bedrockPath(modelId)

proc bedrockHeaders*(body, modelId: string, playerSlot: int): HttpHeaders =
  ## One header set for the request body.
  if hasSidecarEndpoint():
    result["Accept"] = "application/json"
    result["Content-Type"] = "application/json"
    result[CoworldPlayerSlotHeader] = $playerSlot
  elif bedrockToken().len > 0:
    result["Authorization"] = "Bearer " & bedrockToken()
    result["Accept"] = "application/json"
    result["Content-Type"] = "application/json"
  else:
    for (key, value) in signedBedrockHeaders(
      body, bedrockHost(), bedrockPath(modelId), bedrockRegion()
    ):
      result[key] = value
  let latency = bedrockPerformanceLatency()
  if latency.len > 0:
    result["X-Amzn-Bedrock-PerformanceConfig-Latency"] = latency

type
  ModelTuning* = object
    ## How one model family wants its request shaped. Newer families
    ## reject sampling parameters and think by default; thinking eats the
    ## output budget, so it is switched off where allowed and kept short
    ## where it cannot be.
    sampling*: bool
      ## temperature is accepted.
    disableThinking*: bool
      ## send thinking: disabled.
    lowEffort*: bool
      ## send output_config effort low (thinking cannot be disabled).
    minMaxTokens*: int
      ## floor for max_tokens so thinking leaves room for the reply.
    minTimeoutSeconds*: int
      ## floor for the request timeout; reasoning models take their time.

proc modelTuning*(modelId: string): ModelTuning =
  ## Request shape for one Bedrock model id.
  let id = modelId.toLowerAscii()
  result.minMaxTokens = 0
  if not modelId.isAnthropicModel():
    # Reasoning models (Grok, GPT-5.x, gpt-oss, GLM, DeepSeek) spend output
    # tokens thinking before the reply and reject sampling parameters, so
    # give them room and send none; plain chat models keep the temperature.
    let reasoning = "xai." in id or "openai." in id or "zai." in id or
      "deepseek." in id or "minimax." in id or "thinking" in id
    result.sampling = not reasoning
    if reasoning:
      result.minMaxTokens = 1024
      result.minTimeoutSeconds = 60
    return
  let fiveFamily = "opus-5" in id or "sonnet-5" in id or "fable-5" in id or
    "mythos" in id
  let noSampling = fiveFamily or "opus-4-7" in id or "opus-4-8" in id
  result.sampling = not noSampling
  if "fable-5" in id or "mythos" in id:
    result.lowEffort = true
    result.minMaxTokens = 1024
    result.minTimeoutSeconds = 60
  elif "opus-5" in id or "sonnet-5" in id:
    result.disableThinking = true

proc textBlock(text: string, cached: bool): JsonNode =
  ## One Messages API text content block.
  result = %*{"type": "text", "text": text}
  if cached:
    result["cache_control"] = %*{"type": "ephemeral"}

proc bedrockBody*(
  messages: openArray[ConversationMessage],
  playerName: string,
  promptCache: bool,
  modelId = ""
): string =
  ## One Anthropic Messages request body for Bedrock. Consecutive
  ## same-role messages are joined because the API requires user and
  ## assistant turns to alternate. The final message is the state report;
  ## it stays its own content block so the transcript before it can end
  ## with a cache breakpoint.
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
  if promptCache and chatMessages.elems.len > 0:
    # Breakpoint on the last transcript block: the block right before the
    # state report, which may live in the same user message.
    let lastMessage = chatMessages.elems[^1]
    let blocks = lastMessage["content"].elems
    if blocks.len >= 2:
      blocks[^2]["cache_control"] = %*{"type": "ephemeral"}
    elif chatMessages.elems.len >= 2:
      chatMessages.elems[^2]["content"].elems[^1]["cache_control"] =
        %*{"type": "ephemeral"}
  let tuning = modelTuning(modelId)
  let body = %*{
    "anthropic_version": BedrockVersion,
    "max_tokens": max(bedrockMaxTokens(), tuning.minMaxTokens),
    "system": [textBlock(systemPrompt, promptCache)],
    "messages": chatMessages
  }
  if tuning.sampling:
    body["temperature"] = %BedrockTemperature
  if tuning.disableThinking:
    body["thinking"] = %*{"type": "disabled"}
  if tuning.lowEffort:
    body["output_config"] = %*{"effort": "low"}
  if not hasSidecarEndpoint():
    body["requestMetadata"] = bedrockRequestMetadata(playerName)
  $body

proc converseBody*(
  messages: openArray[ConversationMessage],
  modelId: string
): string =
  ## One Bedrock Converse request body for a non-Claude model: the same
  ## turns, with consecutive same-role turns joined and a leading
  ## assistant turn seeded with a user line, as the Anthropic body does.
  var
    systemPrompt = ""
    turns = newJArray()
  for message in messages:
    if message.role == "system":
      systemPrompt = message.content
      continue
    if turns.elems.len == 0 and message.role == "assistant":
      turns.add(%*{"role": "user", "content": [{"text": "(The day begins.)"}]})
    if turns.elems.len > 0 and turns.elems[^1]["role"].getStr() == message.role:
      let last = turns.elems[^1]["content"].elems[^1]
      last["text"] = %(last["text"].getStr() & "\n" & message.content)
    else:
      turns.add(%*{"role": message.role, "content": [{"text": message.content}]})
  let tuning = modelTuning(modelId)
  var inference = %*{"maxTokens": max(bedrockMaxTokens(), tuning.minMaxTokens)}
  if tuning.sampling:
    inference["temperature"] = %BedrockTemperature
  let body = %*{"messages": turns, "inferenceConfig": inference}
  if systemPrompt.len > 0:
    body["system"] = %*[{"text": systemPrompt}]
  $body

proc parseBedrockText(body: string): string =
  ## The output text of one response body, Anthropic or Converse shaped.
  let data = parseJson(body)
  if data.hasKey("output"):
    for part in data["output"]["message"]["content"]:
      if part.hasKey("text"):
        result.add(part["text"].getStr())
    return
  for part in data["content"]:
    if part{"type"}.getStr() == "text":
      result.add(part["text"].getStr())

proc bedrockUsageText*(body: string): string =
  ## The usage block of one response as "in=N cacheRead=N cacheWrite=N
  ## out=N", so logs show prompt sizes and whether the cache is hit.
  try:
    let usage = parseJson(body){"usage"}
    if usage == nil or usage.kind != JObject:
      return ""
    if usage.hasKey("inputTokens"):
      return "in=" & $usage{"inputTokens"}.getInt() &
        " cacheRead=" & $usage{"cacheReadInputTokens"}.getInt() &
        " cacheWrite=" & $usage{"cacheWriteInputTokens"}.getInt() &
        " out=" & $usage{"outputTokens"}.getInt()
    "in=" & $usage{"input_tokens"}.getInt() &
      " cacheRead=" & $usage{"cache_read_input_tokens"}.getInt() &
      " cacheWrite=" & $usage{"cache_creation_input_tokens"}.getInt() &
      " out=" & $usage{"output_tokens"}.getInt()
  except CatchableError:
    ""

proc transientError(reply: BedrockReply): bool =
  ## True for failures worth retrying later.
  let message = reply.error.toLowerAscii()
  if reply.statusCode in [408, 429, 500, 502, 503, 504]:
    return true
  for needle in [
    "timeout", "timed out", "temporarily unavailable",
    "service unavailable", "throttl", "rate exceeded", "too many requests",
    "connection reset", "couldn't connect", "could not connect",
    "rate limit"
  ]:
    if message.contains(needle):
      return true

proc permanentError(reply: BedrockReply): bool =
  ## True when the request itself is rejected (bad model id, bad
  ## credentials), so retrying can only fail the same way.
  if reply.statusCode in [400, 401, 403, 404]:
    return true
  let message = reply.error.toLowerAscii()
  for needle in [
    "validationexception", "resourcenotfoundexception", "accessdenied",
    "unauthorized", "forbidden", "not authorized"
  ]:
    if message.contains(needle):
      return true

proc classify*(reply: var BedrockReply) =
  ## Fills the outcome and the flags the brains act on.
  let message = reply.error.toLowerAscii()
  reply.dailyQuota = message.contains("per day") or message.contains("daily")
  reply.cacheRejected = reply.statusCode == 400 and message.contains("cache")
  reply.contextTooLong = message.contains("input is too long") or
    message.contains("context length") or message.contains("maximum context")
  if reply.error.len == 0 and reply.statusCode == 200:
    reply.outcome = Usable
  elif reply.cacheRejected or reply.contextTooLong:
    reply.outcome = Transient
  elif reply.transientError():
    reply.outcome = Transient
  elif reply.permanentError():
    reply.outcome = Permanent
  else:
    reply.outcome = Transient

proc newBedrockClient*(maxInFlight: int, mockReply = ""): BedrockClient =
  ## A client for the live endpoint, or the mock when one is configured
  ## (by game config, or by the environment for local runs). Hosted games
  ## never set a mock: the certification fixture does, through config, so
  ## league rounds always call the model a soul names.
  result = BedrockClient(
    kind: Live,
    promptCacheEnabled: getEnv("BEDROCK_PROMPT_CACHE").strip() != "0",
    mockReply: if mockReply.len > 0: mockReply else: mockBedrockReply()
  )
  if result.mockReply.len == 0:
    result.curl = newCurly(max(1, maxInFlight))

proc newScriptedBedrockClient*(): BedrockClient =
  ## A client whose replies tests push with scriptReply.
  BedrockClient(kind: Scripted, promptCacheEnabled: true)

proc scriptReply*(client: BedrockClient, reply: BedrockReply) =
  ## Queues one reply for the next poll (scripted transport).
  var copy = reply
  copy.classify()
  client.queued.add(copy)

proc start*(client: BedrockClient, request: BedrockRequest) =
  ## Starts one request without blocking.
  inc client.inFlight
  if client.mockReply.len > 0:
    client.queued.add(BedrockReply(
      tag: request.tag,
      statusCode: 200,
      text: client.mockReply,
      outcome: Usable
    ))
    return
  case client.kind
  of Scripted:
    client.started.add(request)
  of Live:
    let body =
      if request.modelId.isAnthropicModel():
        bedrockBody(
          request.messages,
          request.playerName,
          client.promptCacheEnabled,
          request.modelId
        )
      else:
        converseBody(request.messages, request.modelId)
    client.curl.startRequest(
      "POST",
      bedrockUrl(request.modelId),
      bedrockHeaders(body, request.modelId, request.playerSlot),
      body,
      max(bedrockTimeoutSeconds(), modelTuning(
          request.modelId).minTimeoutSeconds),
      request.tag
    )

proc retryAfterSeconds(headers: HttpHeaders): float =
  ## The wait the endpoint asked for, from Retry-After (seconds) or the
  ## sidecar's Retry-After-Ms; HTTP-date forms are ignored.
  if headers.contains("Retry-After-Ms"):
    try:
      return parseFloat(headers["Retry-After-Ms"].strip()) / 1000.0
    except ValueError:
      discard
  if headers.contains("Retry-After"):
    try:
      return parseFloat(headers["Retry-After"].strip())
    except ValueError:
      discard

proc pollLive(client: BedrockClient): Option[BedrockReply] =
  ## One completed live response, if any.
  let answer = client.curl.pollForResponse()
  if answer.isNone:
    return none(BedrockReply)
  var reply = BedrockReply(tag: answer.get.response.request.tag)
  if answer.get.error.len > 0:
    reply.error = answer.get.error
  else:
    let response = answer.get.response
    reply.statusCode = response.code
    if response.code != 200:
      reply.error = response.body
      reply.retryAfter = response.headers.retryAfterSeconds()
    else:
      try:
        reply.text = response.body.parseBedrockText()
        reply.usage = response.body.bedrockUsageText()
      except CatchableError as e:
        reply.error = "Bedrock response could not be read: " & e.msg
      if reply.error.len == 0 and reply.text.len == 0:
        reply.error = "Bedrock response did not include text."
  reply.classify()
  some(reply)

proc poll*(client: BedrockClient): Option[BedrockReply] =
  ## One completed reply, if any; each started request yields exactly one.
  if client.queued.len > 0:
    result = some(client.queued[0])
    client.queued.delete(0)
  elif client.kind == Live and client.mockReply.len == 0:
    result = client.pollLive()
  else:
    return none(BedrockReply)
  if result.isSome:
    dec client.inFlight
