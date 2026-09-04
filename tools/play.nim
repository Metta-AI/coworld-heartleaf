## Plays one local Heartleaf game the way the tournament does: builds the
## server and the soul player, starts a nine-seat village with the league
## defaults (a week of seven days, one game), seats the nine example souls,
## opens the global viewer in a browser, and shuts everything down when
## the game ends or on Ctrl-C.
##
##   nim r tools/play.nim [--port:8080] [--days:7] [--seed:N] [--mock]
##                        [--log-dir:tmp/logs] [--no-browser] [--no-build]
##
## The game calls the models named in the souls, so Bedrock credentials
## must be in the environment (BEDROCK_KEY or AWS keys); --mock plays every
## decision as keep_gathering_plants with no model at all. Extra Nim
## flags for the builds come from HEARTLEAF_NIM_FLAGS.

import std/[algorithm, browsers, json, os, osproc, parseopt, random, sequtils, strutils, times]

const
  DefaultPort = 8080
  DefaultDays = 7
  DefaultLogDir = "tmp" / "logs"
  ServerExe = "out" / "heartleaf"
  PlayerExe = "out" / "soul_player"
  PlayerStartDelayMs = 300
  PlayerExitGraceMs = 10_000

type
  PlayOptions = object
    port: int
    days: int
    seed: int
    mock: bool
    logDir: string
    browser: bool
    build: bool
    gnomes: int

var children: seq[Process]

proc parseOptions(): PlayOptions =
  result = PlayOptions(
    port: DefaultPort, days: DefaultDays, seed: -1, logDir: DefaultLogDir,
    browser: true, build: true
  )
  for kind, key, value in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "port": result.port = parseInt(value)
      of "days": result.days = parseInt(value)
      of "seed": result.seed = parseInt(value)
      of "mock": result.mock = true
      of "log-dir": result.logDir = value
      of "no-browser": result.browser = false
      of "no-build": result.build = false
      of "gnomes": result.gnomes = parseInt(value)
      of "help", "h":
        echo "usage: nim r tools/play.nim [--port:N] [--days:N] [--seed:N] " &
          "[--mock] [--log-dir:DIR] [--no-browser] [--no-build]"
        quit(0)
      else:
        echo "play: unknown option --", key
        quit(1)
    else:
      discard

proc repoRoot(): string =
  ## The repository root, where data/ and players/ live.
  currentSourcePath().parentDir().parentDir()

proc build(source, exe: string) =
  ## Compiles one Nim program into out/.
  let flags = getEnv("HEARTLEAF_NIM_FLAGS")
  let command = "nim c --hints:off --warnings:off -d:release " & flags &
    " --out:" & exe & " " & source
  echo "play: ", command
  if execCmd(command) != 0:
    echo "play: build failed: ", source
    quit(1)

proc personaSouls(): seq[tuple[name, path: string]] =
  ## The example souls, one per players/*/soul.md, in name order.
  for kind, path in walkDir("players"):
    if kind == pcDir and fileExists(path / "soul.md"):
      result.add((name: path.extractFilename(), path: path / "soul.md"))
  result.sort(proc(a, b: tuple[name, path: string]): int = cmp(a.name, b.name))

proc token(rng: var Rand): string =
  ## One random seat token.
  for _ in 0 ..< 12:
    result.add(rng.sample({'a'..'z', '0'..'9'}.toSeq()))

proc stopChildren() =
  ## Terminates every process this tool started.
  for child in children:
    if child.running():
      child.terminate()
  for child in children:
    discard child.waitForExit(3000)
    if child.running():
      child.kill()
    child.close()
  children.setLen(0)

proc waitForHealth(port: int): bool =
  ## True once the server answers /healthz.
  for _ in 0 ..< 200:
    let probe = execCmdEx("curl -s -m 1 http://localhost:" & $port & "/healthz")
    if probe.output.strip() == "healthy":
      return true
    sleep(100)
  false

proc clearGnomeLogs(dir: string) =
  ## Removes leftover gnome logs so a new play does not splice onto the
  ## previous game.
  if not dirExists(dir):
    return
  for kind, path in walkDir(dir):
    if kind == pcFile and path.splitFile().ext == ".log":
      removeFile(path)

proc main() =
  let options = parseOptions()
  setCurrentDir(repoRoot())
  createDir(options.logDir)
  clearGnomeLogs(options.logDir)
  var souls = personaSouls()
  if options.gnomes > 0 and options.gnomes < souls.len:
    souls.setLen(options.gnomes)
  if souls.len == 0:
    echo "play: no players/*/soul.md found"
    quit(1)
  if options.build:
    build("src/heartleaf.nim", ServerExe)
    build("players/soul_player/soul_player.nim", PlayerExe)

  var rng = initRand(int(epochTime() * 1000) mod 1_000_000)
  var tokens: seq[string]
  var names = newJArray()
  for soul in souls:
    tokens.add(rng.token())
    names.add(%*{"name": soul.name})
  var config = %*{
    "tokens": tokens,
    "players": names,
    "maxDays": options.days,
    "maxGames": 1
  }
  if options.seed >= 0:
    config["seed"] = %options.seed
  config["logDir"] = %options.logDir
  config["replayPath"] = %(options.logDir / "heartleaf.bitreplay")
  if options.mock:
    config["mockReply"] = %"""{"action": "keep_gathering_plants"}"""

  setControlCHook(proc() {.noconv.} =
    echo "\nplay: stopping"
    stopChildren()
    quit(0))

  echo "play: starting the village on port ", options.port, " for ",
    options.days, " days with ", souls.len, " souls"
  let server = startProcess(
    ServerExe,
    args = ["--port:" & $options.port, "--config:" & $config],
    options = {poParentStreams}
  )
  children.add(server)
  if not waitForHealth(options.port):
    echo "play: the server did not come up"
    stopChildren()
    quit(1)

  for i, soul in souls:
    let url = "ws://localhost:" & $options.port & "/player?slot=" & $i &
      "&token=" & tokens[i]
    children.add(startProcess(
      PlayerExe,
      args = [
        "--url:" & url, "--soul:" & soul.path, "--name:" & soul.name,
        "--log-dir:" & options.logDir, "--fresh-log"
      ],
      options = {poParentStreams}
    ))
    sleep(PlayerStartDelayMs)

  let viewer = "http://localhost:" & $options.port & "/client/global"
  echo "play: watch at ", viewer, "; logs and replay in ",
    options.logDir, "/"
  if options.browser:
    openDefaultBrowser(viewer)

  discard server.waitForExit()
  echo "play: game over, waiting for the players to notice"
  sleep(PlayerExitGraceMs)
  stopChildren()

main()
