## Soul player: connects to a Heartleaf game, uploads one soul file and then
## keeps the socket alive. The simulation plays the gnome; this process
## never sends anything else.

import std/[json, os, parseopt, strutils, times], whisky, heartleaf/souls

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
      ## Where the model log is also written as a readable file, one per
      ## gnome, named <name>-<Gnome>.log.

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
  --log-dir:DIR      also write the model log to DIR/<name>-<Gnome>.log
                     (env HEARTLEAF_LOG_DIR)

While connected the game streams the gnome's model log: one JSON line per
frame with seat, gnome, index, role (system, user, assistant, note), and
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

type
  LogSink = ref object
    ## Where received log frames go: stdout always, plus a readable file.
    name: string
    dir: string
    file: File
    path: string

proc readableEntry(line: string): string =
  ## One log frame as a readable block for the audit file.
  try:
    let node = parseJson(line)
    let role = node{"role"}.getStr()
    let index = node{"index"}.getInt(-1)
    let header =
      if index >= 0:
        "=== " & role & " #" & $index & " ==="
      else:
        "=== " & role & " ==="
    header & "\n" & node{"text"}.getStr() & "\n\n"
  except CatchableError:
    line & "\n"

proc record(sink: LogSink, line: string) =
  ## Prints one log frame and appends it to the audit file.
  echo line
  if sink.dir.len == 0:
    return
  if sink.file == nil:
    var gnome = ""
    try:
      gnome = parseJson(line){"gnome"}.getStr()
    except CatchableError:
      discard
    createDir(sink.dir)
    let stem = if sink.name.len > 0: sink.name else: "player"
    sink.path = sink.dir / (stem & (if gnome.len > 0: "-" & gnome else: "") & ".log")
    sink.file = open(sink.path, fmAppend)
    echo "soul_player writing model log to ", sink.path
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
  let sink = LogSink(name: options.name, dir: options.logDir)
  var
    accepted = false
    disconnectedAt = 0.0
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

proc soulPlayerMain*(embeddedSoul = "") =
  ## Runs the uploader. The soul comes from --soul, then the environment,
  ## then the soul embedded at compile time (persona wrappers), then a
  ## soul.md beside the binary.
  var options = parseOptions()
  var raw = ""
  var source = options.soulPath
  if options.soulPath.len > 0 and fileExists(options.soulPath):
    raw = readFile(options.soulPath)
  elif embeddedSoul.len > 0:
    raw = embeddedSoul
    source = "embedded soul"
  elif fileExists("soul.md"):
    raw = readFile("soul.md")
    source = "soul.md"
  else:
    echo "soul_player soul file not found: ", options.soulPath
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
