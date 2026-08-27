## Soul player: connects to a Heartleaf game, uploads one soul file and then
## keeps the socket alive. The simulation plays the gnome; this process
## never sends anything else.

import
  std/[algorithm, json, os, parseopt, strutils, times],
  whisky,
  heartleaf/[protocol, souls]

const
  DefaultHost = "localhost"
  DefaultPort = 8080
  DefaultSoulPath = "/soul.md"
  DefaultConnectTimeoutSeconds = 120.0
  ConnectRetryMs = 1000
  ReplyTimeoutMs = 60_000
  ReplyPollMs = 1000
  ReconnectGiveUpSeconds = 8.0

  ExitUsage = 1
  ExitNoConnection = 2
  ExitRejected = 3

type
  PlayerOptions = object
    url: string
    address: string
    port: int
    slot: int
    token: string
    name: string
    soulPath: string
    connectTimeoutSeconds: float
    once: bool
    logDir: string
      ## Where the conversation log is also written as a readable file,
      ## one per gnome, named <name>-<Gnome>.log.
    freshLog: bool
      ## Truncate the audit file and stream from sequence 0. Play uses
      ## this so a new game is not spliced onto the previous one.

proc queryEscape(text: string): string =
  ## Escapes one URL query value.
  for c in text:
    if c.isAlphaNumeric() or c in {'-', '_', '.', '~'}:
      result.add(c)
    else:
      result.add('%')
      result.add(toHex(ord(c), 2))

proc playerUrl(options: PlayerOptions): string =
  ## Builds the Heartleaf player websocket URL for local runs.
  result = "ws://" & options.address & ":" & $options.port & "/player"
  var separator = '?'
  if options.name.len > 0:
    result.add(separator)
    result.add("username=" & options.name.queryEscape())
    separator = '&'
  if options.slot >= 0:
    result.add(separator)
    result.add("slot=" & $options.slot)
    separator = '&'
  if options.token.len > 0:
    result.add(separator)
    result.add("token=" & options.token.queryEscape())

proc usage(): string =
  ## Command line help.
  """soul_player: uploads a soul file to a Heartleaf game and idles.

  --url:WS_URL       player websocket url (env COGAMES_ENGINE_WS_URL)
  --soul:PATH        soul file (env HEARTLEAF_SOUL_PATH, default /soul.md)
  --address:HOST --port:N --slot:N --token:T --name:NAME
                     build the url for a local game instead of --url
  --connect-timeout-seconds:N   give up connecting after N seconds (120)
  --once             exit right after the soul is accepted
  --log-dir:DIR      also write the conversation to DIR/<name>-<Gnome>.log
                     (env HEARTLEAF_LOG_DIR)
  --fresh-log        replace that file instead of resuming after its last
                     record. Use this for a new play so two games do not
                     share one log.

While connected the game streams the gnome's conversation: one JSON line
per frame with seat, gnome, index, role (system, user, assistant), and
text. Each line is printed to stdout as it arrives.
"""

proc parseOptions(): PlayerOptions =
  ## Reads options from the command line and environment.
  result = PlayerOptions(
    url: getEnv("COGAMES_ENGINE_WS_URL"),
    address: DefaultHost,
    port: DefaultPort,
    slot: -1,
    soulPath: getEnv("HEARTLEAF_SOUL_PATH"),
    connectTimeoutSeconds: DefaultConnectTimeoutSeconds,
    logDir: getEnv("HEARTLEAF_LOG_DIR")
  )
  if result.url.len == 0:
    result.url = getEnv("COWORLD_PLAYER_WS_URL")
  if result.soulPath.len == 0 and fileExists(DefaultSoulPath):
    result.soulPath = DefaultSoulPath
  for kind, key, value in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "url": result.url = value
      of "soul": result.soulPath = value
      of "address": result.address = value
      of "port": result.port = parseInt(value)
      of "slot": result.slot = parseInt(value)
      of "token": result.token = value
      of "name": result.name = value
      of "connect-timeout-seconds":
        result.connectTimeoutSeconds = parseFloat(value)
      of "once": result.once = true
      of "log-dir": result.logDir = value
      of "fresh-log": result.freshLog = true
      of "help", "h":
        echo usage()
        quit(0)
      else:
        echo "soul_player unknown option --", key
        echo usage()
        quit(ExitUsage)
    else:
      discard

proc awaitReply(ws: WebSocket): string =
  ## Waits for the game's accepted or rejected reply, answering pings.
  ## Nothing else is streamed before the collector says it is ready.
  let deadline = epochTime() + ReplyTimeoutMs / 1000
  while epochTime() < deadline:
    let message = ws.receiveMessage(ReplyPollMs)
    if message.isNone:
      continue
    case message.get().kind
    of Ping:
      ws.send(message.get().data, Pong)
    of TextMessage:
      let text = message.get().data
      if text.isSoulAccepted() or text.isSoulRejected():
        return text
    of BinaryMessage, Pong:
      discard
  raise newException(CatchableError, "no reply to the soul within " &
    $(ReplyTimeoutMs div 1000) & "s")

proc acceptedSeat(reply: string): int =
  ## The seat named in a "soul accepted seat=N ..." reply, or -1.
  result = -1
  for part in reply.splitWhitespace():
    if part.startsWith("seat="):
      try:
        return parseInt(part[5 .. ^1])
      except ValueError:
        return -1

type
  LogSink* = ref object
    ## Where received log frames go: stdout always, plus a readable file.
    ## Tracks the last (game, sequence) written so a replayed backlog
    ## after a reconnect is never written twice.
    name*: string
    dir*: string
    file: File
    path*: string
    game*: int
    sequence*: int
    fresh*: bool
      ## Open the audit file for write and do not send a resume cursor.

proc readableEntry*(line: string): string =
  ## One log frame as a readable block for the audit file. The header
  ## carries the record's game and sequence so a restarted collector can
  ## pick up where the file ends.
  try:
    let node = parseJson(line)
    let role = node{"role"}.getStr()
    let index = node{"index"}.getInt(-1)
    let cursor = " (game " & $node{"game"}.getInt(0) & ", seq " &
      $node{"sequence"}.getInt(-1) & ")"
    let header =
      if index >= 0:
        "=== " & role & " #" & $index & " ===" & cursor
      else:
        "=== " & role & " ===" & cursor
    header & "\n" & node{"text"}.getStr() & "\n\n"
  except CatchableError:
    line & "\n"

proc loadCursor*(sink: LogSink, path: string) =
  ## Reads the last (game, seq) header of an existing audit file so the
  ## next session resumes after it instead of duplicating the backlog.
  if not fileExists(path):
    return
  for line in lines(path):
    if not line.startsWith("=== "):
      continue
    let at = line.rfind(" (game ")
    if at < 0:
      continue
    let parts = line[at + 7 .. ^1].replace(")", "").split(", seq ")
    if parts.len != 2:
      continue
    try:
      sink.game = parseInt(parts[0].strip())
      sink.sequence = parseInt(parts[1].strip())
    except ValueError:
      discard

proc readyText*(sink: LogSink): string =
  ## The handshake that starts the log stream: resume after what the
  ## audit file already holds, else from the beginning.
  if sink.sequence >= 0:
    "log-cursor game=" & $sink.game & " sequence=" & $sink.sequence
  else:
    "log-ready"

proc openFile(sink: LogSink, gnome: string) =
  ## Opens the audit file for this gnome. A fresh sink replaces the file
  ## and starts from sequence 0; otherwise the last cursor is resumed.
  createDir(sink.dir)
  let stem = if sink.name.len > 0: sink.name else: "player"
  sink.path = sink.dir / (stem & (if gnome.len > 0: "-" & gnome else: "") & ".log")
  if sink.fresh:
    sink.game = 0
    sink.sequence = -1
    sink.file = open(sink.path, fmWrite)
    echo "soul_player writing model log to ", sink.path
  else:
    sink.loadCursor(sink.path)
    sink.file = open(sink.path, fmAppend)
    echo "soul_player writing model log to ", sink.path,
      (if sink.sequence >= 0: " (resuming after game " & $sink.game &
        " seq " & $sink.sequence & ")" else: "")

proc record*(sink: LogSink, line: string) =
  ## Prints one log frame and appends it to the audit file, skipping
  ## records already seen and marking a new game.
  var game = 0
  var sequence = -1
  var gnome = ""
  try:
    let node = parseJson(line)
    game = node{"game"}.getInt(0)
    sequence = node{"sequence"}.getInt(-1)
    gnome = node{"gnome"}.getStr()
  except CatchableError:
    discard
  if sink.dir.len > 0 and sink.file == nil:
    sink.openFile(gnome)
  if sequence >= 0:
    if game == sink.game and sequence <= sink.sequence:
      return
    if game != sink.game and sink.file != nil and sink.game > 0:
      sink.file.write("=== game " & $game & " ===\n\n")
    sink.game = game
    sink.sequence = sequence
  echo line
  if sink.file == nil:
    return
  sink.file.write(line.readableEntry())
  sink.file.flushFile()

proc idle(ws: WebSocket, sink: LogSink) =
  ## Keeps the socket open until the game closes it, answering pings and
  ## recording every model log frame the game streams.
  while true:
    let message = ws.receiveMessage(-1)
    if message.isNone:
      continue
    case message.get().kind
    of Ping:
      ws.send(message.get().data, Pong)
    of TextMessage:
      sink.record(message.get().data)
    of BinaryMessage, Pong:
      discard

proc run(options: PlayerOptions, soul: Soul) =
  ## Uploads the soul, then idles and reconnects until the game is gone.
  let connectUrl =
    if options.url.len > 0:
      options.url
    else:
      options.playerUrl()
  let startedAt = epochTime()
  let sink = LogSink(
    name: options.name, dir: options.logDir, sequence: -1,
    fresh: options.freshLog
  )
  var
    accepted = false
    disconnectedAt = 0.0
  sink.sequence = -1
  while true:
    try:
      let ws = newWebSocket(connectUrl)
      echo "soul_player connected ", connectUrl
      disconnectedAt = 0.0
      ws.send(soul.raw, TextMessage)
      let reply = ws.awaitReply()
      echo "soul_player ", reply
      if reply.isSoulRejected():
        ws.close()
        quit(ExitRejected)
      accepted = true
      if options.once:
        ws.close()
        quit(0)
      # Open (or resume) the audit file for this seat's gnome before asking
      # for the log, so the cursor is known and nothing is replayed.
      if sink.dir.len > 0 and sink.file == nil:
        sink.openFile(reply.acceptedSeat().playerNameForHouse())
      ws.send(sink.readyText(), TextMessage)
      ws.idle(sink)
    except CatchableError as e:
      echo "soul_player reconnecting: ", e.msg
      if not accepted and epochTime() - startedAt > options.connectTimeoutSeconds:
        echo "soul_player could not connect within ",
          options.connectTimeoutSeconds, "s, exiting"
        quit(ExitNoConnection)
      if accepted:
        if disconnectedAt == 0.0:
          disconnectedAt = epochTime()
        elif epochTime() - disconnectedAt > ReconnectGiveUpSeconds:
          echo "soul_player server gone for ", ReconnectGiveUpSeconds,
            "s, exiting"
          quit(0)
      sleep(ConnectRetryMs)

proc personaSouls(roots: seq[string]): seq[string] =
  ## Every players/*/soul.md under the first root that has any, sorted.
  for root in roots:
    let dir = root / "players"
    if not dirExists(dir):
      continue
    for kind, path in walkDir(dir):
      if kind == pcDir and fileExists(path / "soul.md"):
        result.add(path / "soul.md")
    if result.len > 0:
      result.sort()
      return

proc soulForName(name: string): string =
  ## The soul a launcher meant by a bot name: "grumpy_villager1" is
  ## players/grumpy_villager/soul.md, and "soul_player3" is the third
  ## persona soul in the repository, so one launcher group can field
  ## every persona. Empty when nothing matches.
  var stem = name
  while stem.len > 0 and stem[^1].isDigit():
    stem.setLen(stem.len - 1)
  let number =
    if stem.len < name.len:
      parseInt(name[stem.len .. ^1])
    else:
      0
  let roots = @[
    getCurrentDir(), getCurrentDir().parentDir(),
    getAppDir(), getAppDir().parentDir()
  ]
  if stem.len > 0 and stem != "soul_player":
    for root in roots:
      for candidate in [root / "players" / stem / "soul.md", root / stem / "soul.md"]:
        if fileExists(candidate):
          return candidate
  let souls = personaSouls(roots)
  if souls.len > 0 and number > 0:
    return souls[(number - 1) mod souls.len]

proc soulPlayerMain*() =
  ## Runs the uploader. The soul comes from --soul, then the environment,
  ## then a soul.md beside the binary, then the persona the bot name
  ## refers to.
  var options = parseOptions()
  var raw = ""
  var source = options.soulPath
  if options.soulPath.len > 0 and fileExists(options.soulPath):
    raw = readFile(options.soulPath)
  elif fileExists("soul.md"):
    raw = readFile("soul.md")
    source = "soul.md"
  else:
    let named = soulForName(options.name)
    if named.len > 0:
      raw = readFile(named)
      source = named
    else:
      echo "soul_player soul file not found: ", options.soulPath,
        " (and no persona matches the name ", options.name, ")"
      quit(ExitUsage)
  var soul: Soul
  try:
    soul = parseSoul(raw)
  except SoulError as e:
    echo "soul_player invalid soul ", source, ": ", e.msg
    quit(ExitUsage)
  echo "soul_player soul ", source, " model=", soul.modelId,
    " bytes=", soul.raw.len
  run(options, soul)

when isMainModule:
  soulPlayerMain()
