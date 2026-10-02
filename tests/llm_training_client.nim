## Actual native client and production decision parser checkpoint smoke.
import std/[json, options, os, times]
import heartleaf/[bedrock_client, decisions]

putEnv("COWORLD_LLM_ENDPOINT", paramStr(1))
putEnv("COWORLD_LLM_MODEL", paramStr(2))
putEnv("COWORLD_LLM_TEMPERATURE", getEnv("COWORLD_LLM_TEMPERATURE", "0"))
putEnv("BEDROCK_MAX_TOKENS", "32")
putEnv("BEDROCK_TIMEOUT_SECONDS", "20")
delEnv("HEARTLEAF_MOCK_REPLY")
let client = newBedrockClient(1)
client.start(BedrockRequest(tag: "0:1", modelId: paramStr(2), playerSlot: 0,
  playerName: "Yura", messages: @[
    ConversationMessage(role: "system", content: "Keep the private Heartleaf system prompt exact."),
    ConversationMessage(role: "user", content: "Current private report")
  ]))
let deadline = epochTime() + 25
while true:
  let reply = client.poll()
  if reply.isSome:
    let value = reply.get
    doAssert value.outcome == Usable, value.error
    let decision = parseDecision(value.text)
    doAssert decision.error.len == 0, decision.error
    doAssert value.platformCallId.len > 0
    echo $(%*{"action": $decision.action, "platform_call_id": value.platformCallId,
      "stop_reason": value.stopReason, "response": value.text})
    break
  doAssert epochTime() < deadline, "native checkpoint request timed out"
  sleep(5)
