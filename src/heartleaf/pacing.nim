## Pacing for the villagers' model requests. The whole game shares one
## Bedrock budget (the hosted sidecar allows a fixed number of requests a
## minute per pod), so requests are spaced pod-wide, and each villager
## backs off on its own after a failed call. Times are epoch seconds.

import std/[os, random, strutils], heartleaf/villager

const
  DefaultRequestsPerMinute = 30
  DefaultMaxInFlight = 9
  DefaultMinRequestSeconds = 0.0
    ## No pod-wide floor by default: the sidecar's limiter is a bucket that
    ## admits bursts, and nine gnomes all wake up at 8:00am.
  DefaultVillagerMinSeconds = 2.0
  BudgetWindowSeconds = 60.0
  RetryMinSeconds = 2.0
  RetryMaxSeconds = 60.0
  DailyQuotaMaxSeconds = 100.0
  RetryJitter = 0.5
  ThrottleMinSeconds = 1.0
  ThrottleMaxSeconds = 16.0

type
  RequestBudget* = object
    requestsPerMinute*: int
    maxInFlight*: int
    minRequestSeconds*: float
    villagerMinSeconds*: float
    requestTimes: seq[float]
    blockedUntil*: float
      ## Pod-wide: nobody requests before this after a throttled reply.
    throttleSeconds: float
    inFlight*: int
    rng*: Rand

proc envInt(name: string, fallback: int): int =
  ## One integer knob from the environment.
  let value = getEnv(name).strip()
  if value.len == 0:
    return fallback
  try:
    max(1, parseInt(value))
  except ValueError:
    fallback

proc envFloat(name: string, fallback: float): float =
  ## One float knob from the environment.
  let value = getEnv(name).strip()
  if value.len == 0:
    return fallback
  try:
    max(0.0, parseFloat(value))
  except ValueError:
    fallback

proc newRequestBudget*(seed: int): RequestBudget =
  ## A budget from the environment knobs, allowing an immediate first
  ## request.
  RequestBudget(
    requestsPerMinute: envInt("HEARTLEAF_LLM_REQUESTS_PER_MINUTE",
      DefaultRequestsPerMinute),
    maxInFlight: envInt("HEARTLEAF_LLM_MAX_IN_FLIGHT", DefaultMaxInFlight),
    minRequestSeconds: envFloat("HEARTLEAF_LLM_MIN_REQUEST_SECONDS",
      DefaultMinRequestSeconds),
    villagerMinSeconds: envFloat("HEARTLEAF_LLM_VILLAGER_MIN_SECONDS",
      DefaultVillagerMinSeconds),
    rng: initRand(seed)
  )

proc pruneRequests(budget: var RequestBudget, now: float) =
  ## Drops request timestamps that left the budget window.
  var keep: seq[float]
  for time in budget.requestTimes:
    if now - time < BudgetWindowSeconds:
      keep.add(time)
  budget.requestTimes = keep

proc requestsInLastMinute*(budget: RequestBudget, now: float): int =
  ## How many requests started inside the rolling budget window.
  for time in budget.requestTimes:
    if now - time < BudgetWindowSeconds:
      inc result

proc lastRequestTime(budget: RequestBudget): float =
  ## When the most recent request started, or a distant past.
  if budget.requestTimes.len == 0:
    return -1.0e9
  budget.requestTimes[^1]

proc canRequest*(budget: RequestBudget, now: float): bool =
  ## True when a new request may start now: spaced from the last one,
  ## inside the rolling minute budget, under the in-flight cap, and not
  ## throttled.
  now - budget.lastRequestTime() >= budget.minRequestSeconds and
    budget.requestsInLastMinute(now) < budget.requestsPerMinute and
    budget.inFlight < budget.maxInFlight and
    now >= budget.blockedUntil

proc noteRequest*(budget: var RequestBudget, now: float) =
  ## Records that a request started now.
  budget.pruneRequests(now)
  budget.requestTimes.add(now)
  inc budget.inFlight

proc noteReply*(budget: var RequestBudget) =
  ## Records that one request finished, however it went.
  budget.inFlight = max(0, budget.inFlight - 1)

proc noteHealthy*(budget: var RequestBudget) =
  ## Clears the pod-wide throttle after a usable reply.
  budget.throttleSeconds = 0.0

proc noteThrottle*(budget: var RequestBudget, now, retryAfter: float): float =
  ## Blocks everyone for a while after the endpoint throttled a request,
  ## honouring its Retry-After when longer. Returns the wait in seconds.
  budget.throttleSeconds =
    if budget.throttleSeconds < ThrottleMinSeconds:
      ThrottleMinSeconds
    else:
      min(budget.throttleSeconds * 2.0, ThrottleMaxSeconds)
  result = max(budget.throttleSeconds, retryAfter)
  budget.blockedUntil = max(budget.blockedUntil, now + result)

proc noteTransientFailure*(
  villager: Villager,
  budget: var RequestBudget,
  now: float,
  retryAfter = 0.0,
  dailyQuota = false
): float =
  ## Doubles this villager's backoff after a transient failure and
  ## returns how many seconds it will now wait. A spent daily quota has a
  ## longer cap; a Retry-After from the endpoint wins when longer.
  inc villager.failures
  let maxSeconds =
    if dailyQuota: DailyQuotaMaxSeconds else: RetryMaxSeconds
  villager.retryBackoffSeconds =
    if villager.retryBackoffSeconds < RetryMinSeconds:
      RetryMinSeconds
    else:
      min(villager.retryBackoffSeconds * 2.0, maxSeconds)
  let jitter = villager.retryBackoffSeconds * RetryJitter * budget.rng.rand(1.0)
  result = max(villager.retryBackoffSeconds + jitter, retryAfter)
  villager.retryAt = max(villager.retryAt, now + result)

proc noteUsableReply*(villager: Villager) =
  ## Clears this villager's backoff after a usable reply.
  villager.failures = 0
  villager.permanentHits = 0
  villager.retryBackoffSeconds = 0.0
  villager.retryAt = 0.0
  villager.lastError = ""
