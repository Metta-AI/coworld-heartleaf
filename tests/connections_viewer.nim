## Real replay + shared viewer transport. Optional output directory captures frames.
import std/[importutils, os, strutils, tables]
import heartleaf, replays, heartleaf/[connections, encounters]
import bitworld/[spriteprotocol, sprites]
import ../tools/viewer_review_render
privateAccess(SimServer)
privateAccess(PlayerViewerState)
let path = if paramCount()>0: paramStr(1) else: "out/connections-scenario.replay"
let data = loadReplay(path)
let cfg = data.replaySimConfig()
let sim = initSimServer(cfg.seed,cfg.dayTicks)
sim.attachConversationTimeline(data,path)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed,cfg.dayTicks)
replay.looping = false
sim.buildConversationQueue(replay.replayMaxTick())
var state = newReplayViewerState()
state.setViewerSize(1440,900)
proc capture(name:string,w=1440,h=900) =
  var fresh = newReplayViewerState()
  fresh.connectionDebugOpen = state.connectionDebugOpen
  fresh.connectionSelection = state.connectionSelection
  fresh.connectionReflectionPage = state.connectionReflectionPage
  fresh.setViewerSize(w,h)
  var next:PlayerViewerState
  let packet = sim.buildGlobalPacket(fresh,next,replayControls=true,
    replayPlaying=replay.playing,replayTick=sim.tickCount,replayMaxTick=replay.replayMaxTick())
  if fresh.connectionDebugOpen:
    doAssert next.connectionButtons.len == 9, "full graph includes all nine gnomes"
  if paramCount()>1:
    createDir(paramStr(2))
    render(packet,w,h,paramStr(2)/name)
proc seek(tick:int) =
  replay.applyReplaySeek(sim,tick)
  discard sim.replayViewerFrame(replay,state,true)
  doAssert not replay.hashValidationFailed
proc click(layer,x,y:int) =
  state.handleReplayViewerPacket(char(0x82)&char(x and 255)&char(x shr 8)&
    char(y and 255)&char(y shr 8)&char(layer)&char(0x83)&char(1)&char(1)&char(0x83)&char(1)&char(0))

seek(10)
doAssert sim.connectionTimeline.bondsAt(sim.tickCount).connectionScore(0) == 4
capture("01-overview.png")
var blank = newReplayViewerState()
blank.setViewerSize(1440,900)
var rendered:PlayerViewerState
let overview = sim.buildGlobalPacket(blank,rendered,replayControls=true)
var heartRows = 0
for item in overview.parseSpritePacket():
  if item.kind == spkSprite and item.sprite.id in 13_000..13_008:
    inc heartRows
    doAssert item.sprite.width == 79 and item.sprite.height == 7,
      "ten pixel hearts replace the old score and connection bars"
  if item.kind == spkObject:
    doAssert item.objectDef.id != 65_100, "debug graph is closed by default"
doAssert heartRows == 9
# Clicking where a leaderboard portrait is drawn has no debug side effect.
click(7,40,45)
doAssert not state.connectionDebugOpen
doAssert not state.connectionDebugOpen
doAssert state.connectionButtons.len == 0, "leaderboard rows do not open the debug view"
let debug = state.connectionDebugButton
click(7,debug.x+5,debug.y+5)
doAssert state.connectionDebugOpen
discard sim.replayViewerFrame(replay,state,true)
doAssert state.connectionButtons.len == 9
# Every graph node selects its own seat, with no overlapping hit targets.
for node in state.connectionButtons:
  click(7,node.rect.x+node.rect.width div 2,node.rect.y+node.rect.height div 2)
  doAssert state.connectionSelection == node.seat+1
  click(7,node.rect.x+node.rect.width div 2,node.rect.y+node.rect.height div 2)
  doAssert state.connectionSelection == 0
let button = state.connectionButtons[0]
click(7,button.rect.x+5,button.rect.y+5)
doAssert state.connectionSelection == button.seat+1
capture("02-initial-graph.png")
click(7,button.rect.x+5,button.rect.y+5)
doAssert state.connectionSelection == 0
click(7,debug.x+5,debug.y+5)
doAssert not state.connectionDebugOpen
# Play a conversation through the normal director clock.
replay.applyReplayConversation(sim,0)
replay.applyReplayCommand(sim,'p')
var frames=0
while sim.tickCount < 854 and frames<5000:
  discard sim.replayViewerFrame(replay,state,true)
  inc frames
doAssert frames < 5000 and not replay.hashValidationFailed
capture("03-conversation.png")
replay.applyReplayCommand(sim,'P')
let frozen = (sim.tickCount,sim.directorCamX,sim.directorCamY,
  sim.connectionTimeline.bondsAt(sim.tickCount))
for _ in 0..<30: discard sim.replayViewerFrame(replay,state,true)
doAssert frozen == (sim.tickCount,sim.directorCamX,sim.directorCamY,
  sim.connectionTimeline.bondsAt(sim.tickCount))
capture("04-conversation-laptop.png",1280,720)
capture("05-conversation-narrow.png",768,1024)
seek(4700)
doAssert sim.connectionTimeline.bondsAt(sim.tickCount).strength(0,1) == 1
capture("06-day-two-overview.png")
state.connectionDebugOpen = true
state.connectionSelection = 1
capture("07-bedtime-results.png")
state.setViewerSize(1280,600)
discard sim.replayViewerFrame(replay,state,true)
let paging = state.connectionNextPage
doAssert paging.width > 0
click(7,paging.x+3,paging.y+3)
doAssert state.connectionReflectionPage == 1
capture("09-more-reflections.png",1280,600)
capture("10-compact-inspector.png",1280,480)
state.connectionSelection = 0
state.connectionDebugOpen = false
seek(10)
doAssert sim.connectionTimeline.bondsAt(sim.tickCount).strength(0,1) == 0.5
capture("08-rewound-overview.png")
# Mix pause, next, speed, previous, end, restart after the bond update.
seek(4700)
for command in ['p','n','n','P','1','p','2','N','b','P','e','p']:
  replay.applyReplayCommand(sim,command)
  for _ in 0..<5: discard sim.replayViewerFrame(replay,state,true)
  doAssert not replay.hashValidationFailed
# Replay all simulation hashes, plus random-access snapshots through both days.
for tick in [8880,4000,9000,10,4560,4320,100,9119]:
  seek(tick)
  let strength = sim.connectionTimeline.bondsAt(sim.tickCount).strength(0,1)
  doAssert strength == (if tick>=4320:1.0 else:0.5)
block:
  # A nearby bystander can hear speech before the actual peer in player order.
  # The connection card must still describe the recorded conversation partner.
  let audience = initSimServer(42)
  for seat in [3, 4, 8]:
    let index = audience.addPlayer("audience", seat)
    privateAccess(typeof(audience.players[0]))
    audience.players[index].mapIndex = 0
    audience.players[index].x = 320 + index * 10
    audience.players[index].y = 300
  audience.conversationTimeline = parseConversationTimeline("""
{"kind":"convo-enter","tick":0,"day":1,"seat":3,"text":"conversation id=1 members=Sasha,Egor turn=1"}
""")
  audience.applyPlayerChat(0, "Hello, Egor!")
  audience.step(newSeq[InputState](3))
  privateAccess(typeof(audience.chatFeed[0]))
  privateAccess(typeof(audience.chatFeed[0].hearers[0]))
  doAssert audience.chatFeed.len == 1
  doAssert audience.chatFeed[0].hearers[0].name == "Maxim"
  doAssert audience.chatFeed[0].connectionPartner == "Egor",
    "a bystander must not replace the speaker's conversation peer"
  doAssert audience.chatFeed[0].hearers.len == 2,
    "connection display must not change who actually heard the speech"
  audience.conversationTimeline = ConversationTimeline()
  audience.applyPlayerChat(0, "Hello, everyone!")
  audience.step(newSeq[InputState](3))
  doAssert audience.chatFeed[^1].connectionPartner.len == 0
  doAssert audience.chatFeed[^1].hearers.len == 2,
    "live and legacy conversations retain the nearby-listener fallback"
echo "Connection viewer: recorded scenario, ten-heart rows, default-hidden full graph, node selection, pause, mixed transport, backward seeks and recorded-peer cards passed."
