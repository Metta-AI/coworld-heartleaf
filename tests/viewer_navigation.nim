## Left leaderboard geometry, narrow toggle, glyph caching and presentation isolation.
import std/[importutils, tables]
import heartleaf, heartleaf/viewer_layout, replays
import bitworld/[spriteprotocol, sprites]
privateAccess(SimServer)
privateAccess(PlayerViewerState)
let path = "docs/viewer-stability/local-viewer-scenario.replay"
let data = loadReplay(path)
let cfg = data.replaySimConfig()
let sim = initSimServer(cfg.seed,cfg.dayTicks)
sim.attachConversationTimeline(data,path)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed,cfg.dayTicks)
sim.buildConversationQueue(replay.replayMaxTick())
replay.looping = false
var state = newReplayViewerState()
state.setViewerSize(1280,720)
replay.applyReplaySeek(sim,799)
let initialHash = sim.gameHash()
let first = sim.replayViewerFrame(replay,state,true)
var glyphHeights: seq[int]
for msg in parseSpritePacket(first):
  if msg.kind == spkSprite and msg.sprite.id >= 8720 and msg.sprite.id <= 8814:
    if msg.sprite.height notin glyphHeights:glyphHeights.add(msg.sprite.height)
  if msg.kind == spkObject:
    doAssert msg.objectDef.id != 50_001, "removed right panel must not render"
doAssert glyphHeights == @[6], "use the original unscaled font glyphs"
for size in [(1280,720),(1440,900),(1920,1080),(1468,798),(1366,1024)]:
  let layout = frameLayout(0,0,748,941,size[0],size[1],true,true,sidebars=true)
  doAssert layout.railWidth == ViewerRailWidth
  doAssert layout.scene.height == layout.canvasHeight
  doAssert layout.stage.width == layout.canvasWidth - ViewerRailWidth
  let centeredX = (layout.canvasWidth - layout.scene.width) div 2
  if centeredX >= ViewerRailWidth:
    let rightMargin = layout.canvasWidth - layout.scene.x - layout.scene.width
    doAssert abs(layout.scene.x-rightMargin) <= 1, "equal margins around the village"
  let start = frameLayout(0,0,748,941,size[0],size[1],true,true,
    conversation=true,worldWidth=748,worldHeight=941,focusBlend=0.001,sidebars=true)
  doAssert start.scene == layout.scene, "the zoom must start at the centered overview"
  doAssert layout.scene.x >= ViewerRailWidth
  doAssert layout.scene.x + layout.scene.width <= layout.canvasWidth
  let zoom = frameLayout(200,200,250,314,size[0],size[1],true,true,100,
    conversation=true,worldWidth=748,worldHeight=941,sidebars=true)
  doAssert zoom.railWidth == 0
  doAssert zoom.scene.x == 0 and zoom.scene.y == 0
  doAssert zoom.scene.width == zoom.canvasWidth and zoom.scene.height == zoom.canvasHeight

# The rail and its hit target disappear from actual conversation packets.
replay.applyReplaySeek(sim,850)
let zoomPacket = sim.replayViewerFrame(replay,state,true)
for msg in parseSpritePacket(zoomPacket):
  if msg.kind == spkObject:
    doAssert msg.objectDef.id notin [50_000,50_003,50_005]
doAssert state.leaderboardButton.width == 0
replay.applyReplaySeek(sim,799)
state.setViewerSize(390,844)
discard sim.replayViewerFrame(replay,state,true)
proc toggle() =
  let r = state.leaderboardButton
  let x = r.x+r.width div 2
  let y = r.y+r.height div 2
  state.handleReplayViewerPacket(char(0x82)&char(x and 255)&char(x shr 8)&
    char(y and 255)&char(y shr 8)&char(7)&
    char(0x83)&char(1)&char(1)&char(0x83)&char(1)&char(0))
  discard sim.replayViewerFrame(replay,state,true)
toggle()
doAssert state.openPanel == 1
toggle()
doAssert state.openPanel == 0
let steady = sim.replayViewerFrame(replay,state,true)
for msg in parseSpritePacket(steady):
  doAssert msg.kind != spkSprite, "stationary UI must reuse all sprite components"
doAssert sim.gameHash() == initialHash

# Panel height follows its rows, never the viewport. Short desktop windows
# must retain every gnome; all portrait pixels use the same sampling step.
let compact = initSimServer(42)
for i in 0..1: discard compact.addPlayer(if i == 0: "host" else: "guest",i)
proc checkPanel(width,height,count: int): int =
  var viewer = newReplayViewerState()
  viewer.setViewerSize(width,height)
  var next: PlayerViewerState
  let packet = compact.buildGlobalPacket(viewer,next,replayControls=true)
  var panel: ViewerRect
  var faces: seq[SpritePacketObject]
  for msg in parseSpritePacket(packet):
    if msg.kind == spkSprite:
      doAssert msg.sprite.id != 9855, "removed logo must not be uploaded"
      if msg.sprite.id == 9850:
        panel.width = msg.sprite.width
        panel.height = msg.sprite.height
    if msg.kind == spkObject:
      doAssert msg.objectDef.id != 50_005, "removed logo must not be displayed"
      if msg.objectDef.id == 50_000:
        panel.x = msg.objectDef.x
        panel.y = msg.objectDef.y
      if msg.objectDef.spriteId in 10240..10248: faces.add(msg.objectDef)
  doAssert faces.len == count, "every gnome must remain visible"
  privateAccess(typeof(next.spriteCache[0]))
  var bottom = 0
  for face in faces:
    for entry in next.spriteCache:
      if entry.spriteId != face.spriteId: continue
      doAssert entry.width == 27 and entry.height == 27
      let source = compact.portraits[entry.spriteId-10240]
      let icon = RgbaSprite(width:entry.width,height:entry.height,pixels:entry.pixels)
      for y in 0..<icon.height:
        for x in 0..<icon.width:
          doAssert icon.rgbaSpriteAt(x,y) == source.rgbaSpriteAt(x*2,y*2),
            "portrait sampling must not alternate pixel widths"
      bottom = max(bottom,face.y+entry.height)
  doAssert bottom < panel.y+panel.height
  doAssert panel.y+panel.height-bottom <= 12, "no stretched empty tail"
  result = panel.height
let twoHeight = checkPanel(1280,720,2)
doAssert checkPanel(1440,900,2) == twoHeight
for i in 2..8: discard compact.addPlayer("guest " & $i,i)
let nineHeight = checkPanel(1280,600,9)
doAssert nineHeight > twoHeight
doAssert checkPanel(1440,900,9) == nineHeight
echo "Left rail, content-fit rows, uniform portraits, original font, narrow toggle, sprite reuse and unchanged game state passed"
