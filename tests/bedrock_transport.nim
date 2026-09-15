## Driven by test_bedrock_transport.py against a local fake sidecar.
import std/[json, options, os, times]
import heartleaf/[bedrock_client, decisions]

putEnv("AWS_ENDPOINT_URL_BEDROCK_RUNTIME", paramStr(1))
putEnv("BEDROCK_TIMEOUT_SECONDS", "20")
delEnv("HEARTLEAF_MOCK_REPLY")

let client = newBedrockClient(9)

proc startSeat(wave, seat: int) =
  client.start(BedrockRequest(
    tag: $wave & ":" & $seat,
    modelId: "test/transport-wave-" & $wave,
    playerSlot: seat,
    playerName: "test",
    messages: @[ConversationMessage(role: "user", content: "test")]
  ))

for wave in 0 .. 1:
  startSeat(wave, 0)
  # The harness confirms the first request is blocked at the server before
  # allowing the remaining eight to start on the same client.
  discard stdin.readLine()
  for seat in 1 .. 8:
    startSeat(wave, seat)
  let started = epochTime()
  var received = 0
  while received < 9:
    let reply = client.poll()
    if reply.isSome:
      let value = reply.get
      echo $(%*{"tag": value.tag, "outcome": $value.outcome,
        "status": value.statusCode, "error": value.error})
      inc received
      doAssert value.outcome == Usable, value.error
    else:
      doAssert epochTime() - started < 25, "transport did not finish"
      sleep(5)
  doAssert client.inFlight == 0
