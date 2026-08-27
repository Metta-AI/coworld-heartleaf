## Socket-level checks of the player protocol against a real server: the
## acceptance precedes every log frame, log records are dense per game, a
## reconnect resumes from a cursor, a new game restarts at sequence 0, and
## the uploader's audit sink never writes a record twice.
##
## Runs the server binary named by HEARTLEAF_SERVER (default out/heartleaf,
## built with `nim c src/heartleaf.nim`) from the repository root.

import
  std/[httpclient, json, os, osproc, strutils, times],
  whisky,
  heartleaf/souls,
  players/soul_player/soul_player

const
  Port = 18961
  Url = "ws://localhost:" & $Port & "/player?slot=0&token=a"
  SoulText = "#!test-model\nYour name is {name}. You test things.\n"

proc serverExe(): string =
  let configured = getEnv("HEARTLEAF_SERVER")
  if configured.len > 0:
    return configured
  "out" / "heartleaf"

proc waitForHealth() =
  ## Polls /healthz until the server answers.
  let client = newHttpClient(timeout = 1000)
  defer: client.close()
  for _ in 0 ..< 100:
    try:
      if client.getContent("http://localhost:" & $Port & "/healthz") == "healthy":
        return
    except CatchableError:
      discard
    sleep(100)
  raise newException(CatchableError, "server never became healthy")

proc collect(ws: WebSocket, seconds: float): seq[string] =
  ## Every text frame received within the window; pings are answered.
  let deadline = epochTime() + seconds
  while epochTime() < deadline:
    let message = ws.receiveMessage(200)
    if message.isNone:
      continue
    case message.get().kind
    of TextMessage:
      result.add(message.get().data)
    of Ping:
      ws.send(message.get().data, Pong)
    else:
      discard

proc records(frames: seq[string]): seq[JsonNode] =
  for frame in frames:
    if frame.startsWith("{"):
      result.add(parseJson(frame))

proc denseFrom(nodes: seq[JsonNode], game, first: int): bool =
  ## True when the records belong to `game` and count up from `first`.
  for i, node in nodes:
    if node["game"].getInt() != game or node["sequence"].getInt() != first + i:
      return false
  true

proc main() =
  doAssert fileExists(serverExe()), "build the server first: " & serverExe()
  let server = startProcess(
    serverExe(),
    args = [
      "--port:" & $Port,
      "--config:" & $(%*{
        "tokens": ["a"], "maxTicks": 300, "maxGames": 2, "daySeconds": 30,
        "soulTimeoutSeconds": 30, "seed": 3,
        "mockReply": """{"action": "keep_gathering_plants"}"""
      })
    ],
    options = {poStdErrToStdOut, poUsePath}
  )
  defer:
    server.terminate()
    discard server.waitForExit(5000)
  waitForHealth()

  echo "Testing acceptance, then nothing until log-ready"
  var first = newWebSocket(Url)
  first.send(SoulText, TextMessage)
  let beforeReady = first.collect(1.5)
  doAssert beforeReady.len == 1 and beforeReady[0].isSoulAccepted(),
    "only the acceptance arrives before the handshake, got: " & $beforeReady
  first.send("log-ready", TextMessage)
  let firstFrames = first.collect(3.0)
  doAssert firstFrames.len > 0, "the log streams after log-ready"
  let firstRecords = firstFrames.records()
  doAssert firstRecords.len > 0
  doAssert firstRecords[0]["role"].getStr() == "system"
  doAssert firstRecords.denseFrom(1, 0), "game 1 records count up from 0"
  let lastSequence = firstRecords[^1]["sequence"].getInt()
  first.close()

  echo "Testing a reconnect that resumes from its cursor"
  var second = newWebSocket(Url)
  second.send(SoulText, TextMessage)
  let reply = second.collect(1.0)
  doAssert reply.len >= 1 and reply[0].isSoulAccepted(), "resend of the same soul is accepted"
  second.send("log-cursor game=1 sequence=" & $lastSequence, TextMessage)
  let resumed = second.collect(3.0).records()
  doAssert resumed.len > 0, "streaming resumes after the cursor"
  for node in resumed:
    doAssert node["sequence"].getInt() > lastSequence,
      "nothing at or below the cursor is ever re-sent"
  doAssert resumed.denseFrom(1, lastSequence + 1),
    "resume starts exactly after the cursor"

  echo "Testing a new game restarts the log at sequence 0"
  var gameTwo: seq[JsonNode]
  let deadline = epochTime() + 60.0
  while epochTime() < deadline and gameTwo.len < 3:
    try:
      for node in second.collect(1.0).records():
        if node["game"].getInt() == 2:
          gameTwo.add(node)
    except CatchableError:
      break
  doAssert gameTwo.len >= 3, "game 2 records should arrive"
  doAssert gameTwo[0]["sequence"].getInt() == 0 and
    gameTwo[0]["role"].getStr() == "system", "game 2 opens with its prompt at 0"
  doAssert gameTwo.denseFrom(2, 0)
  second.close()

  echo "Testing the audit sink never writes a record twice"
  let dir = getTempDir() / "heartleaf-integration-logs"
  removeDir(dir)
  proc frame(game, sequence: int): string =
    $(%*{"game": game, "sequence": sequence, "seat": 0, "gnome": "Ivan",
      "index": sequence, "role": "user", "text": "line " & $sequence})
  var sink = LogSink(name: "tester", dir: dir, sequence: -1)
  for i in 0 ..< 5:
    sink.record(frame(1, i))
  for i in 2 ..< 5:
    sink.record(frame(1, i))
  sink.record(frame(2, 0))
  let audit = readFile(dir / "tester-Ivan.log")
  doAssert audit.count("=== user #") == 6, "five game-1 records and one game-2 record"
  doAssert "=== game 2 ===" in audit
  var restarted = LogSink(name: "tester", dir: dir, sequence: -1)
  restarted.loadCursor(dir / "tester-Ivan.log")
  doAssert restarted.game == 2 and restarted.sequence == 0,
    "a restarted sink resumes from the file's last record"
  doAssert restarted.readyText() == "log-cursor game=2 sequence=0"
  doAssert LogSink(sequence: -1).readyText() == "log-ready"

  echo "Testing a fresh sink replaces an old audit file"
  var fresh = LogSink(name: "tester", dir: dir, sequence: -1, fresh: true)
  fresh.record(frame(1, 0))
  let replaced = readFile(dir / "tester-Ivan.log")
  doAssert replaced.count("=== user #") == 1,
    "a fresh play must not keep the previous game"
  doAssert "line 0" in replaced
  doAssert "line 4" notin replaced
  doAssert fresh.readyText() == "log-cursor game=1 sequence=0"

  removeDir(dir)
  echo "Integration tests passed"

main()
