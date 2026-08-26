## Pacing for the villagers' model requests. In-flight calls are capped
## pod-wide, each villager is spaced from its last call, and each
## villager backs off on its own after a failed call. Times are epoch
## seconds.

import std/[os, random, strutils], heartleaf/villager

const
  DefaultMaxInFlight = 9
  DefaultMinRequestSeconds = 0.0
  DefaultVillagerMinSeconds = 2.0
  RetryMinSeconds = 2.0
  RetryMaxSeconds = 60.0
  DailyQuotaMaxSeconds = 100.0
  RetryJitter = 0.5
  ThrottleMinSeconds = 1.0
  ThrottleMaxSeconds = 16.0

type
  RequestBudget* = object
    maxInFlight*: int
    minRequestSeconds*: float
    villagerMinSeconds*: float
    lastRequestAt: float
    blockedUntil*: float
      ## Pod-wide: nobody requests before this after a throttled reply.
    throttleSeconds: float
    inFlight*: int
    rng*: Rand

proc envInt(name: string, fallback: int): int =
  ## One integer knob from the environment, at least 1.
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
    maxInFlight: envInt("HEARTLEAF_LLM_MAX_IN_FLIGHT", DefaultMaxInFlight),
    minRequestSeconds: envFloat("HEARTLEAF_LLM_MIN_REQUEST_SECONDS",
      DefaultMinRequestSeconds),
    villagerMinSeconds: envFloat("HEARTLEAF_LLM_VILLAGER_MIN_SECONDS",
      DefaultVillagerMinSeconds),
    lastRequestAt: -1.0e9,
    rng: initRand(seed)
  )

proc canRequest*(budget: RequestBudget, now: float): bool =
  ## True when a new request may start now: spaced from the last one,
  ## under the in-flight cap, and not throttled.
  now - budget.lastRequestAt >= budget.minRequestSeconds and
    budget.inFlight < budget.maxInFlight and
    now >= budget.blockedUntil

proc noteRequest*(budget: var RequestBudget, now: float) =
  ## Records that a request started now.
  budget.lastRequestAt = now
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

proc retryPending*(villager: Villager): bool =
  ## True when a failed call still owes another try after backoff.
  villager.retryAt > 0.0 and not villager.failed
