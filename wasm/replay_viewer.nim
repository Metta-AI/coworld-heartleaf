## Standalone Heartleaf replay viewer: the game simulation and the
## bitworld global renderer client linked into one binary with an
## in-memory packet transport — no server process and no websockets.
##
## Native:      nim c wasm/replay_viewer.nim
##              ./out/replay_viewer --load-replay:out/round2303_1.replay
## Emscripten:  nim c -d:emscripten wasm/replay_viewer.nim
##              serve wasm/dist/ and open
##              replay_viewer.html?replay=<url-or-relative-path>
##              Coworld hosts the same files as index.html?replay=
##
## Replays load three ways: a CLI path (native), a `?replay=` query
## or `#replay=` fragment parameter fetched over HTTP, or a file
## dropped onto the window.

import
  std/[os, parseopt, uri],
  windy,
  bitworld/spriteprotocol,
  heartleaf, replays,
  client/global_client

when not defined(emscripten):
  import std/monotimes

const
  RepoDir = currentSourcePath().parentDir().parentDir()
  BitworldClientDir = RepoDir.parentDir() / "bitworld" / "client"

type
  ReplayViewer = ref object
    app: GlobalApp
    sim: SimServer
    replay: ReplayPlayer
    state: PlayerViewerState
    inputPackets: seq[string]
    loaded: bool
    directorMode: bool
      ## The director cut: automated camera, conversation queue,
      ## cards, forest border. On by default; `director=0` in the
      ## URL falls back to the plain wide view.

when defined(emscripten):
  {.emit: """
#include <emscripten.h>

EM_JS(int, heartleaf_pop_key, (), {
  if (!window._heartleafKeys) {
    window._heartleafKeys = [];
    window.addEventListener('keydown', function(e) {
      if (e.key && e.key.length == 1 &&
          !e.ctrlKey && !e.metaKey && !e.altKey) {
        window._heartleafKeys.push(e.key.charCodeAt(0));
        if (window._heartleafKeys.length > 32) {
          window._heartleafKeys.shift();
        }
      }
    });
  }
  return window._heartleafKeys.length ? window._heartleafKeys.shift() : 0;
});
""".}
  proc heartleaf_pop_key(): cint {.importc, nodecl.}

proc addInputPacket(viewer: ReplayViewer, packet: string) =
  ## Queues one local sprite protocol client packet.
  viewer.inputPackets.add(packet)

proc initReplayViewer(): ReplayViewer =
  ## Creates a replay viewer with an in-memory sprite transport.
  result = ReplayViewer()
  result.state = newReplayViewerState()
  result.sim = initSimServer()
  let viewer = result
  let
    atlasPath =
      when defined(emscripten):
        "dist/atlas.png"
      else:
        BitworldClientDir / "dist" / "atlas.png"
    palettePath =
      when defined(emscripten):
        "data/pallete.png"
      else:
        RepoDir / "data" / "pallete.png"
  result.app = initGlobalApp(
    options = GlobalOptions(
      title: "Heartleaf Replay Viewer",
      atlasPath: atlasPath,
      palettePath: palettePath,
      packetSink: proc(packet: string) =
        viewer.addInputPacket(packet)
    )
  )
  result.app.setStatus("Drop a replay file")

proc loadReplayBytes(viewer: ReplayViewer, name, bytes: string) =
  ## Loads replay bytes and reports any parsing error in the overlay.
  try:
    let
      data = parseReplayBytes(bytes)
      config = data.replaySimConfig()
    viewer.sim = initSimServer(config.seed, config.dayTicks)
    viewer.sim.attachConversationTimeline(data, name)
    viewer.replay = initReplayPlayer(data)
    viewer.replay.buildReplayKeyframes(config.seed, config.dayTicks)
    viewer.sim.buildConversationQueue(viewer.replay.replayMaxTick())
    viewer.state = newReplayViewerState()
    viewer.state.directorMode = viewer.directorMode
    viewer.inputPackets.setLen(0)
    viewer.loaded = true
    viewer.app.resetProtocolState()
    viewer.app.setStatus("")
  except CatchableError as e:
    viewer.loaded = false
    viewer.app.setStatus("Could not load replay: " & e.msg)
    echo "Could not load replay ", name, ": ", e.msg

proc loadReplayPath(viewer: ReplayViewer, path: string) =
  ## Loads a native replay file from disk.
  if path.len == 0:
    return
  try:
    viewer.loadReplayBytes(path, readFile(path))
  except CatchableError as e:
    viewer.app.setStatus("Could not read replay: " & e.msg)

proc urlParam(windowUrl, name: string): string =
  ## Returns one parameter from a URL. Both the query string and the
  ## fragment are honored, the fragment winning: the observatory
  ## loads the bundle as `index.html?v=2#replay=<urlencoded URL>`.
  let parsed = parseUri(windowUrl)
  for key, value in decodeQuery(parsed.query):
    if key == name:
      result = value
  for key, value in decodeQuery(parsed.anchor):
    if key == name:
      result = value

proc replayUrl(windowUrl: string): string =
  ## Returns the replay parameter from one URL.
  urlParam(windowUrl, "replay")

proc directorEnabled(windowUrl: string): bool =
  ## The director cut is the default; `director=0` (or false/off)
  ## keeps the plain wide view.
  urlParam(windowUrl, "director") notin ["0", "false", "off"]

proc downloadReplay(viewer: ReplayViewer, url: string) =
  ## Downloads a replay file and loads it when the response arrives.
  if url.len == 0:
    return
  viewer.app.setStatus("Downloading replay")
  let request = startHttpRequest(url)
  request.onError = proc(message: string) =
    viewer.loaded = false
    viewer.app.setStatus("Could not download replay: " & message)
  request.onResponse = proc(response: HttpResponse) =
    if response.code < 200 or response.code >= 300:
      viewer.loaded = false
      viewer.app.setStatus(
        "Could not download replay: HTTP " & $response.code
      )
      return
    viewer.loadReplayBytes(url, response.body)

proc installFileDrop(viewer: ReplayViewer) =
  ## Hooks browser and desktop file drops into replay loading.
  viewer.app.setFileDropCallback(
    proc(fileName, fileData: string) =
      viewer.loadReplayBytes(fileName, fileData)
  )

proc drainInput(viewer: ReplayViewer) =
  ## Applies queued local viewer input packets to the viewer state.
  for packet in viewer.inputPackets:
    viewer.state.handleReplayViewerPacket(packet)
  viewer.inputPackets.setLen(0)

proc pollBrowserKeys(viewer: ReplayViewer) =
  ## Feeds browser keydown characters into the replay transport: the
  ## client library only forwards keystrokes in player mode, so the
  ## viewer polls its own keydown queue ('n'/'N' step conversations,
  ## space toggles play, and so on).
  when defined(emscripten):
    for _ in 0 ..< 8:
      let key = heartleaf_pop_key()
      if key <= 0:
        break
      let ch = char(key)
      if ch >= ' ' and ch <= '~':
        viewer.state.queueReplayCommand(ch)

proc tick(viewer: ReplayViewer) =
  ## Pumps one replay viewer frame.
  viewer.app.handleInput()
  viewer.pollBrowserKeys()
  viewer.drainInput()
  let packet = replayViewerFrame(
    viewer.sim,
    viewer.replay,
    viewer.state,
    viewer.loaded
  )
  if packet.len > 0:
    viewer.app.parseMessage(blobFromBytes(packet))
  viewer.app.maybeFit()
  viewer.app.draw()

proc parseReplayPathArg(): string =
  ## Returns the replay path from the command line, if any.
  for kind, key, value in getopt():
    case kind
    of cmdArgument:
      return key
    of cmdLongOption:
      if key == "load-replay" and value.len > 0:
        return value
    else:
      discard

proc runReplayViewer*() =
  ## Runs the standalone replay viewer until the window closes.
  let viewer = initReplayViewer()
  when not defined(emscripten):
    var lastTick = getMonoTime()
  viewer.installFileDrop()
  viewer.directorMode = directorEnabled(viewer.app.windowUrl())
  viewer.state.directorMode = viewer.directorMode
  viewer.loadReplayPath(parseReplayPathArg())
  viewer.downloadReplay(replayUrl(viewer.app.windowUrl()))
  while viewer.app.windowOpen:
    pollEvents()
    viewer.tick()
    when not defined(emscripten):
      runFrameLimiter(lastTick)
  viewer.app.shutdown()

when isMainModule:
  runReplayViewer()
