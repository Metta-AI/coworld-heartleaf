import
  std/[algorithm, hashes, json, math, os, osproc, random, strutils, tables, times],
  flatty, jsony, pixie,
  bitworld/aseprite, bitworld/pixelfonts, bitworld/spriteprotocol,
  bitworld/resources, bitworld/sprites,
  heartleaf/common, heartleaf/protocol, heartleaf/souls,
  heartleaf/observation, heartleaf/navigation, heartleaf/encounters,
  replays

when not defined(emscripten):
  import
    std/[locks, monotimes, sysrand],
    curly, mummy,
    bitworld/client as bitworldClient,
    bitworld/runtime,
    heartleaf/brains, heartleaf/bedrock_client

const
  DefaultSeed* = 0x484541
  DefaultMaxTicks = 0
  DefaultMaxGames = 0
  MainMapIndex = 0
  HomeMapIndexBase = 1
  DefaultSoulTimeoutSeconds* = 150
  CogamePlayerFailureUriEnv = "COGAME_PLAYER_FAILURE_URI"
  LogCursorPrefix = "log-cursor "
  LogReadyMessage = "log-ready"
  FoodGridCols = 8
  FoodGridRows = 8
  DirectionCount = 4
  FoodVeggieCols = 8
  FoodMarkerCellX = 7
  FoodMarkerCellY = 7
  GardenStartFoodCount = 1
  MotionScale = 256
  Accel = 76
  FrictionNum = 144
  FrictionDen = 256
  MaxSpeed = 704
  StopThreshold = 8
  MovementSlideMaxScan = 3
  MinSpawnSpacing = 20
  SpawnScanStep = 4
  HouseSpawnMaxDistance = 96
  DinnerScreenTicks = 10 * TicksPerSecond
  DinnerTallyMinutes = DinnerMinutes
  DinnerEatRounds = 3
  NewFoodEatScore = 3
  LeftoverEatScore = 1
  DayStepMinutes = 5
  DayStepCount = DayTotalMinutes div DayStepMinutes
  DuskStartMinutes = 17 * 60
  DayTintCount = 5
  TargetFps = 24.0
  HealthzPath = "/healthz"
  WebSocketPath = "/player"
  GlobalWebSocketPath = "/global"
  ReplayWebSocketPath = "/replay"
  DirectorWebSocketPath = "/director"
  MaxWebSocketFrameBytes = 900_000
  MapLayerId = 0
  UiLayerId = 1
  ClockLayerId = 2
  GlobalPanelLayerId = 3
  ReplayCenterBottomLayerId = 4
  ReplayMismatchLayerId = 6
  MapLayerKind = 0
  GlobalPanelLayerKind = 1
  UiLayerKind = 3
  ClockLayerKind = 2
  ReplayCenterBottomLayerKind = 8
  ReplayMismatchLayerKind = 5
  MapLayerFlags = 1
  UiLayerFlags = 2
  ReplayPanelHeight = 42
    ## Tall enough for the parchment card's leafy border around the
    ## transport row and the scrubber.
  ReplayScrubberWidth = 288
  ReplayScrubberHeight = 5
  ReplayControlsBgAlpha = 204'u8
  ReplayScrubberTrackY = 2
  ReplayScrubberY = 26
  ReplayTickTextY = 11
  ReplayConvTextY = 18
    ## The "CONV N/M" queue position label sits under the tick counter,
    ## in the same clear run between the transport buttons and speeds.
  TransportButtonsX = 10
  TransportRowY = 11
  TransportButtonWidth = 12
  TransportButtonStride = 14
  TransportButtonCount = 6
  TransportRowHeight = 7
  TransportSpeedStride = 17
  TransportSpeedWidth = 16
  TransportSpeedLabels = ["1/4", "1/2", "1X", "2X", "3X", "4X", "8X", "16X"]
  TransportSpeedCommands = ['q', 'h', '1', '2', '3', '4', '8', '6']
  SpeedRowX =
    ViewportWidth - TransportSpeedStride * TransportSpeedLabels.len - 10
  TransportButtonsEndX =
    TransportButtonsX + TransportButtonCount * TransportButtonStride
    ## The tick counter is centered between the transport buttons and
    ## the speed labels, so "TICK 5074" never collides with "1/2".
  ReplayMismatchPadX = 4
  ReplayMismatchPadY = 3
  InventoryColumns = 8
  InventoryRows = (FoodVeggieSlots + InventoryColumns - 1) div InventoryColumns
  InventoryIconStep = 34
  InventoryUiWidth = InventoryColumns * InventoryIconStep
  InventoryUiHeight = InventoryRows * InventoryIconStep
  ClockUiWidth = 120
  ClockUiHeight = 12
  GlobalPanelWidth = 176
  GlobalPanelHeight = 128
  GlobalPanelPad = 2
  GlobalPanelRowHeight = 9
  GlobalPanelScoreX = 2
  GlobalPanelNameX = 22
  GlobalPanelCardPadX = 9
    ## Content inset that clears the parchment card's leafy border.
  GlobalPanelCardPadY = 8
  GlobalPanelCardSpriteId = 8290
  GlobalPanelCardObjectId = 20_090
  GlobalPanelTextR = 0x5E'u8
    ## Dark parchment ink: the score panel sits on a nine-sliced
    ## chat-banner card, the same design system as the director cards.
  GlobalPanelTextG = 0x3A'u8
  GlobalPanelTextB = 0x16'u8
  GlobalPanelScoreR = 158'u8
  GlobalPanelScoreG = 116'u8
  GlobalPanelScoreB = 66'u8
  GlobalPanelSelectedR = 255'u8
  GlobalPanelSelectedG = 226'u8
  GlobalPanelSelectedB = 92'u8
  GlobalPanelSelectedInkR = 191'u8
    ## Selected-name ink with enough contrast on parchment; the map
    ## outline highlight keeps the original gold.
  GlobalPanelSelectedInkG = 82'u8
  GlobalPanelSelectedInkB = 30'u8
  DirectorMinCropHeight = 220
    ## The tightest zoom, as a crop height in world pixels; keeps a
    ## small circle from filling the whole screen with two gnomes.
  DirectorMinCropWidth = 250
    ## The tightest zoom is also never narrower than one wrapped
    ## speech bubble with margin, so spoken lines fit the shot.
  DirectorPaddingPx = 56
    ## World pixels kept visible around the focused circle.
  DirectorTweenRate = 0.10
    ## Fraction of the remaining distance the camera covers each frame
    ## while it follows a focused ring's small drift.
  DirectorTweenFrames = 48
    ## Frames one camera glide takes - out to the wide shot, or in to
    ## the next ring. Two seconds at the 24fps loop, eased at both
    ## ends, so a cut reads as a camera move instead of a snap. The
    ## show holds its breath while a glide runs: no replay ticks land
    ## and the delay-chat cursor stays put until the camera rests.
  DirectorStickPx = 80
    ## How far a circle's center may drift between frames and still be
    ## recognized as the conversation the director is focused on.
  DirectorWideHoldTicks = 18
    ## Frames the camera dwells on the wide shot before zooming into
    ## the next waiting conversation.
  DirectorWideSnapRatio = 0.92
    ## The camera counts as "back to wide" once its crop height passes
    ## this fraction of the map height.
  DirectorFocusDwellFrames = 360
    ## Frames the camera dwells inside one conversation while others
    ## are running: about three spoken lines under show pacing, then
    ## the cut goes wide and rotates to the next ring.
  HuddleHoldFrames = 96
    ## Viewer frames an inferred ring outlives the last spoken line,
    ## bridging the quiet beats between lines of one conversation.
  DirectorDinnerHoldFrames = 240
    ## Viewer frames the director keeps showing a house interior after
    ## the last line spoken at the table; dinner talk paces slowly.
  DirectorShowFrames = 5
    ## While the director is on a conversation at 1X, the replay slows
    ## to one tick every five frames - lines recorded 24 ticks apart
    ## then land about five seconds apart, show pacing.
  QueueFastForwardTicks = 8
    ## Ticks per frame the conversation-queue playhead covers between
    ## conversations: a brisk automatic ~8X toward the next birth.
  DirectorCardMarginPx = 170
    ## Extra viewport width on each side of the director's crop. The
    ## conversation cards live in these margins, outside the map.
  DirectorCardWidth = 158
  DirectorCardPad = 5
  DirectorCardGapY = 6
  DirectorCardPortraitSize = 36
    ## Card faces are the banner portraits downscaled to about this.
  DirectorCardZ = 32_000
  DirectorCardSpriteBase = 9100
  DirectorCardObjectBase = 28_000
    ## Clear of HeartObjectBase (27_000..): the heart emotes ride the
    ## same packets as the cards in the director view.
  DirectorCardSliceInset = 10
    ## Corner size kept crisp when the chat banner's leafy frame is
    ## nine-sliced onto a conversation card.
  DirectorCardInnerPad = DirectorCardPad + 4
    ## Content padding inside a card's leafy frame.
  DirectorCardFaceSpriteBase = 9150
  DirectorCardFaceObjectBase = 28_100
  DirectorForestAspectNum = 16
  DirectorForestAspectDen = 9
    ## Target width:height of the director viewport (16:9). Shots
    ## narrower than this gain forest-only padding on each side, so
    ## common browser shapes see forest where they used to letterbox
    ## in black; the conversation cards stay next to the map. Zoomed
    ## shots are already wide and gain nothing.
  ForestMarginPx = 480
    ## World pixels of generated forest border around the main map. The
    ## director viewport pads the camera crop by DirectorCardMarginPx
    ## plus the forest-only padding on each side, so the border must
    ## reach at least that far past the map edge; it extends further so
    ## every camera position stays covered with slack.
  DirectorForestPadMax = ForestMarginPx - DirectorCardMarginPx - 22
    ## The forest-only padding cannot exceed what the generated border
    ## sprite can fill at the widest shot, slack included.
  ForestBandPx = 44
    ## Depth of the map-edge band the forest border is built from. Only
    ## the outermost band is sampled, so houses and lawns deeper in the
    ## map are never reflected into the forest.
  ForestSpriteBase = 30
    ## Sprite ids 30..35: the untinted forest underlay and its five
    ## dusk tints, after the home overhang tints (25..29).
  ForestObjectId = 3
    ## Map-layer object id for the forest underlay, after the bottom
    ## (1) and overhang (2) objects.
  DirectorBounceHops = [2, 4, 6, 6, 5, 4, 2, 0, 2, 3, 3, 2, 1, 0]
    ## The little hop a gnome does when its new line lands, in pixels
    ## of lift per frame.
  ClockPadX = 2
  ClockPadY = 1
  ClockGlyphGap = 1
  OverlayFoodColumns = 8
  OverlayFoodStep = 34
  OverlayGuestColumns = 4
  OverlayGuestCellWidth = 78
  OverlayGuestCellHeight = 32
  OverlayScoreColumns = 3
  OverlayScoreCellWidth = 104
  OverlayScoreCellHeight = 54
  BottomSpriteId = 1
  OverhangSpriteId = 2
  HomeBottomSpriteId = 4
  HomeOverhangSpriteId = 5
  MainBottomTintSpriteBase = 10
  MainOverhangTintSpriteBase = MainBottomTintSpriteBase + DayTintCount
  HomeBottomTintSpriteBase = MainOverhangTintSpriteBase + DayTintCount
  HomeOverhangTintSpriteBase = HomeBottomTintSpriteBase + DayTintCount
  FoodSpriteBase = 400
  FoodMarkerSpriteId = FoodSpriteBase + FoodVeggieSlots
  PlayerSpriteBase = 100
  NameSpriteBase = 2000
  ChatSpriteBase = 3000
  InventoryCountSpriteBase = 4000
  ClockGlyphSpriteBase = 7000
  ScoreSpriteBase = 7100
  ReplayTickSpriteId = 8400
  ReplayScrubberSpriteId = 8401
  ReplayControlsSpriteId = 8402
  ReplayMismatchSpriteId = 8403
  ReplayPanelBgSpriteId = 8404
  ReplayConvSpriteId = 8405
  GnomeOutlineSpriteBase = 8500
  TrailDotSpriteBase = 8600
  ReplayTickObjectId = 20_400
  ReplayScrubberObjectId = 20_401
  ReplayControlsObjectId = 20_402
  ReplayMismatchObjectId = 20_403
  ReplayPanelBgObjectId = 20_404
  ReplayConvObjectId = 20_405
  HouseGnomeObjectBase = 21_000
  HouseGnomeBorderObjectBase = 21_100
  PlayerBorderObjectId = 21_200
  InsetBottomObjectId = 21_300
  InsetOverhangObjectId = 21_301
  InsetPlayerObjectBase = 21_400
  HouseGnomeZ = 20_500
  HouseGnomeLift = 12
  InsetBottomZ = 31_000
  InsetPlayerZBase = 31_100
  InsetOverhangZ = 31_500
  InsetNameZ = 31_600
  InsetChatZ = 31_601
  OutlinePad = 1
  TrailObjectBase = 24_000
  HeartSpriteBase = 9200        ## emote sprites: 3 tiers x 4 fade stages,
                                ## clear of the chat-banner glyph ids
  HeartObjectBase = 27_000
  HeartLinkZ = 30_010           ## emotes float above heads and name tags
  HeartLinkMaxDistance = 190    ## px; emotes only show when the pair is near
  HeartEmotePeriod = 72         ## ticks per emote cycle (3s at 24 ticks/s)
  HeartEmoteLife = 44           ## ticks one emote lives while rising
  HeartEmoteStagger = 16        ## ticks between emotes of the same cycle
  HeartEmoteRise = 26           ## px an emote rises over its life
  HeartEmoteCount = [1, 2, 3]   ## emotes per cycle, by connection tier
  ConversationRingSpriteBase = 8900
  ConversationRingObjectBase = 26_000
  ConversationRingZ = 55
    ## Above the walk trails (50), below every gnome (their z starts at
    ## world y + 100): the ring reads as a mark on the ground.
  ConversationRingPhases = 16
    ## Animation frames for the one shared ring sprite. Playback
    ## cycles these in order; every huddle reuses the same frames.
  ConversationRingTicksPerPhase = 2
    ## Global ticks per animation frame.
  ConversationSparkles = 18
    ## Sparkles around one ring.
  ConversationRingPad = 8
    ## Extra pixels so sparkle arms are not clipped at the edge.
  TrailZ = 50
  TrailSampleTicks = 6
  TrailMaxPoints = 5
  ChatBannerSpriteId = 8700
  PortraitSpriteBase = 8701
  PortraitFlipSpriteBase = 8710
  ChatBannerGlyphSpriteBase = 8720
  ChatBannerObjectId = 25_000
  ChatBannerPortraitObjectBase = 25_001
  ChatBannerGlyphObjectBase = 25_010
  ChatBannerMaxGlyphs = 160
  ChatBannerBgZ = 0
  ChatBannerPortraitZ = 1
  ChatBannerGlyphZ = 2
  ChatBannerInkR = 0x94'u8
  ChatBannerInkG = 0x5C'u8
  ChatBannerInkB = 0x29'u8
  ChatFeedShowSeconds* = 4.0
    ## Wall-clock hold for one delay-chat banner line, independent of
    ## sim speed and of whether the viewer runs at 24 or 60 fps.
  ChatFeedMaxItems = 400
  ChatBannerMaxHearers = 3
  ChatBannerNameGap = 10
  PortraitGridColumns = 3
  ChatBannerPortraitMargin = 10
  ChatBannerPortraitY = 2
  ChatBannerTextGap = 8
  ChatBannerAreaHeight = 64
  ReplayBarTotalHeight = ChatBannerAreaHeight + ReplayPanelHeight
  GlobalPanelScoreSpriteBase = 8200
  GlobalPanelNameSpriteBase = 8300
  GlobalPanelScoreObjectBase = 20_100
  GlobalPanelNameObjectBase = 20_200
  BottomZ = int(low(int16))
  OverhangZ = 20_000
  GardenMarkerZ = OverhangZ - 1
  NameZ = 30_000
  ChatZ = 30_001
  ScoreZ = 30_002
  NameMaxChars = 14
  ChatLifetimeTicks = 5 * 24
  ChatPad = 3
  ChatWrapChars = 40
  ChatPointerHeight = 3
  ChatGapY = 3
  NamePadX = 2
  NamePadY = 1
  NameGapY = 2
  TextBackR = 0x33'u8
  TextBackG = 0x31'u8
  TextBackB = 0x36'u8
  ClockGlyphs =
    "0123456789: " &
    "abcdefghijklmnopqrstuvwxyz" &
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  TintHueTargets = [0.80, 0.78, 0.75, 0.70, 0.64]
  TintHueMixes = [0.18, 0.30, 0.43, 0.57, 0.72]
  TintSaturationScales = [1.05, 1.12, 1.20, 1.30, 1.38]
  TintValueScales = [0.86, 0.70, 0.54, 0.39, 0.25]

type
  Direction = enum
    DirDown
    DirUp
    DirRight
    DirLeft

  HeartleafError* = object of ValueError

  Rect = common.Rect

  FoodCounts = array[FoodVeggieSlots, int]

  WorldMap = ref object
    width, height: int
    bottomSprite: RgbaSprite
    overhangSprite: RgbaSprite
    bottomTints: array[DayTintCount, RgbaSprite]
    overhangTints: array[DayTintCount, RgbaSprite]
    forestSprite: RgbaSprite
    forestTints: array[DayTintCount, RgbaSprite]
    walkMask: seq[bool]

  GnomeSprites = ref object
    frames: array[Direction, RgbaSprite]

  FoodSprites = ref object
    icons: array[FoodVeggieSlots, RgbaSprite]
    marker: RgbaSprite

  Garden = object
    rect: Rect
    inventory: FoodCounts

  TrailPoint = object
    x, y: int
    mapIndex: int

  ChatFeedPerson = object
    name: string
    gnomeIndex: int

  ChatFeedItem = object
    speaker: ChatFeedPerson
    hearers: seq[ChatFeedPerson]
    message: string
    encounterId: int
      ## The conversation this line was spoken in, from the replay's
      ## records; zero when unknown (live play, dinner talk, shouts).

  ChatBannerHearer = object
    gnomeIndex: int
    name: string
    portraitX: int
    nameX: int

  House = object
    rect: Rect
    valid: bool

  HomeResources = ref object
    exit: Rect
    hasExit: bool
    washes: seq[Rect]
    cooks: seq[Rect]
    diners: seq[Rect]

  DinnerRecord = ref object
    hostName: string
    wasHost: bool
    foods: FoodCounts
    guestNames: seq[string]
    guestGnomeIndices: seq[int]
    guestCount: int
    score: int

  Player = ref object
    username: string
    playerName: string
    x, y: int
    velX, velY: int
    carryX, carryY: int
    inputX, inputY: int
    direction: Direction
    gnomeIndex: int
    homeFlag: int
    mapIndex: int
    inventory: FoodCounts
    eaten: array[FoodVeggieSlots, bool]
    dinners: seq[DinnerRecord]
    score: int
    dinnerTicks: int
    dinnerRecord: DinnerRecord
    message: string
    messageTicks: int
    attackDown: bool
    curfewMissed: bool
      ## Caught outside home at the end of the day; cleared each morning.

  SpriteCacheEntry = ref object
    spriteId: int
    width: int
    height: int
    pixels: seq[uint8]

  SimServer* = ref object
    mainMap: WorldMap
    homeMaps: array[HouseCount, WorldMap]
    resourceRects: seq[ResourceRect]
    homeResourceRects: seq[ResourceRect]
    homeResources: HomeResources
    foods: FoodSprites
    gardens: seq[Garden]
    houses: array[HouseCount, House]
    gnomes: seq[GnomeSprites]
    players: seq[Player]
    seatCount*: int
      ## Player seats this game was configured for (the hosted token
      ## count). Results report exactly this many slots, so a 4-seat
      ## experience request does not get 9 scores.
    textFont: PixelFont
    rng: Rand
    tickCount*: int
    dayTick: int
    dayTicks: int
    dayNumber: int
    scoreTicks: int
    dinnerDone: bool
    playerInitPacket: seq[uint8]
    trails: seq[seq[TrailPoint]]  ## viewer-only history, never hashed
    conversationCircles*: seq[tuple[x, y, radius: int]]
      ## Viewer-only sparkle rings. Never hashed.
    conversationTimeline: ConversationTimeline
      ## Replay chat-mode objects from game.log. Empty in live play.
    conversationAnchors: Table[int, ConversationAnchor]
      ## Frozen ring positions keyed by encounter id. Viewer-only.
    heartLinks*: seq[tuple[a, b, links: int]]
      ## Connection strengths from the heart ledger (live) or the
      ## conversation records (replay). Viewer-only, never hashed.
    heartEmoteBases: array[3, RgbaSprite]
      ## The emote sprites: neutral, smile, star-eyes, by tier.
    heartEmoteFaded: Table[int, RgbaSprite]
      ## Alpha-faded emote variants, cached by tier * 4 + fade.
    directorCamX, directorCamY, directorCamW, directorCamH: float
      ## The director cut's current crop of the main map, in world
      ## pixels. Viewer-only, advanced once per frame, never hashed.
    directorFocusActive: bool
    directorFocusX, directorFocusY, directorFocusRadius: int
      ## The conversation circle the director camera is following,
      ## tracked by proximity so it survives members shuffling.
    directorTweenLeft: int
      ## Frames left in the current camera glide; zero when the camera
      ## rests. While positive the show waits: no replay ticks, no new
      ## cards, no delay-chat advance.
    directorTweenFromX, directorTweenFromY: float
    directorTweenFromW, directorTweenFromH: float
      ## The crop the current glide started from, eased toward the
      ## target over DirectorTweenFrames frames.
    directorWideTicks: int
      ## Frames spent back on the wide shot with a conversation waiting.
    directorFocusTicks: int
      ## Frames spent inside the current cut; a long dwell with other
      ## conversations running rotates the camera to the next ring.
    directorLastFocusX, directorLastFocusY: int
    directorHasLastFocus: bool
      ## Where the camera last dwelt, so the next pick tours the other
      ## conversations instead of returning to the same ring.
    directorDinnerHouse: int
    directorDinnerTtl: int
      ## While positive, the director overlays this house's interior:
      ## a dinner party is talking indoors, where the map shows nothing.
    directorBounce: seq[int]
      ## Frames left of the hop a gnome does when its new line lands.
    directorLastMessages: seq[string]
      ## The last spoken line seen per player, to spot new ones.
    inferredHuddles: Table[int, tuple[x, y, ttl: int]]
      ## Fallback conversation rings inferred from replay state when no
      ## game.log rides next to the replay (an http replay URI), keyed
      ## by the lowest player index in the huddle. Viewer-only.
    chatBanner: RgbaSprite
    portraits: seq[RgbaSprite]
    chatFeed: seq[ChatFeedItem]   ## viewer-only delay chat, never hashed
    chatFeedIndex: int
    chatFeedShownAt: float
    directorCardLive: bool
      ## Whether the current delay-chat line's card may show on the
      ## director cut this frame. While a viewer speaks the lines
      ## aloud, the card lives exactly as long as its voice: it
      ## appears when the voice starts and leaves on voicedone. With
      ## no voice pacing the card simply rides the delay-chat cursor.
      ## Viewer-only, never hashed.
      ## epochTime when the current delay-chat line first appeared.
    convQueue*: seq[ConversationSpan]
      ## The replay's conversations in birth order, for the
      ## conversation-queue show. Viewer-only, never hashed; empty in
      ## live play and on replays without conversation records.
    convQueueIndex: int
      ## The queue item now playing (while committed) or next up.
    convQueueLast: int
      ## The most recently committed item, for the prev-conv restart;
      ## -1 before anything has played.
    convQueueCommitted: bool
      ## Whether playback is committed to convQueue[convQueueIndex]:
      ## the shot and the feed belong to that conversation until its
      ## death tick. Between commitments nothing airs.
    convQueueFurthest: int
      ## The furthest tick queue playback has reached. After a
      ## same-tick birth group's rewinds, forward playback resumes
      ## from here, so world time never repeats or skips.
    chatFeedScope: int
      ## While committed, the encounter id whose lines the delay-chat
      ## cursor may air; other circles' lines are skipped. Zero airs
      ## everything.
    directorCommitEncounter: int
      ## While positive, the director camera belongs to this
      ## encounter: no dwell rotation, no tour, until the queue
      ## releases it.

  KeyframeState = object
    ## Dynamic simulation state stored in one replay keyframe. Static
    ## assets (maps, sprites, fonts, init packet) are never serialized.
    players: seq[Player]
    gardens: seq[Garden]
    houses: array[HouseCount, House]
    rng: Rand
    tickCount: int
    dayTick: int
    dayTicks: int
    dayNumber: int
    scoreTicks: int
    dinnerDone: bool

  PlayerViewerState* = ref object
    initialized: bool
    directorMode: bool
      ## A /director viewer: the automated camera picks the shot;
      ## player and house selection are ignored.
    selectedPlayerIndex: int
    selectedHouseNumber: int  ## 0 = none, 1..HouseCount = house interior view
    pendingMapClick: bool
    pendingMapClickX: int
    pendingMapClickY: int
    spriteCache: seq[SpriteCacheEntry]
    mouseX: int
    mouseY: int
    mouseLayer: int
    mouseDown: bool
    clickPending: bool
    mousePressX: int
    mousePressY: int
    mousePressLayer: int
    scrubbingReplay: bool
    replaySeekTick: int
    replayCommands: seq[char]

  RunConfig = ref object
    address: string
    port: int
    seed: int
    maxTicks: int
    maxDays: int
      ## Game length in days, score screens included; overrides maxTicks.
    maxGames: int
    daySeconds: int
    tokens: seq[string]
    playerNames: seq[string]
      ## Per-slot display names from `players[].name`, filled by hosted
      ## dispatch with the policy or player name behind each slot.
    soulTimeoutSeconds: int
      ## How long the village waits for every seat's soul before day 1.
    soulConnectionRequired: bool
      ## Whether a seat whose socket drops after its soul is a player failure.
    mockReply: string
      ## Offline stand-in for the model, for certification and smoke runs
      ## only; empty in every hosted variant.
    logDir: string
      ## When set, LLM lifecycle and world stamps go to logDir/game.log.
    replayPath: string
      ## When set, the first game is recorded to this replay file.

when not defined(emscripten):
  type
    WebSocketAppState = ref object
      lock: Lock
      nowKey: tuple[index, gnomeIndex, messageLen: int]
      nowPlayingSerial: int
      nowPlayingSeat: int
      nowPlayingText: string
        ## The chat line the banner shows right now, published for the
        ## viewer pages' speech layer.
      voiceHoldSerial: int
      voiceDoneSerial: int
      voiceHoldSince: float
        ## While a viewer is speaking line voiceHoldSerial aloud, the
        ## replay holds; voicedone (or the timeout) releases it.
      playerSlots: Table[WebSocket, int]
        ## Seat requested by each /player socket, -1 for any free seat.
      globalViewers: Table[WebSocket, PlayerViewerState]
      replayViewers: Table[WebSocket, PlayerViewerState]
      playerUsernames: Table[WebSocket, string]
      souls: Table[int, Soul]
        ## Accepted soul per seat; a seat comes alive when its soul arrives.
      soulSockets: Table[WebSocket, int]
        ## Seat whose soul each socket delivered.
      logSent: Table[WebSocket, int]
        ## How many of the seat's log entries each soul socket has received.
        ## A socket is only streamed to once it sent log-ready or a
        ## log-cursor, so the first records never race the handshake.
      gameNumber: int
        ## One-based game of this process, matching the log records.
      closedSockets: seq[WebSocket]
      tokens: seq[string]
      playerNames: seq[string]
      replayServerMode: bool
      replayLoaded: bool
      pendingReplayUri: string
      replayRestartPending: bool
        ## A viewer connected while nobody was watching; the replay
        ## loop restarts playback from tick zero.
      replayViewerJoined: bool
        ## A viewer connected; if playback already sits at the end of
        ## the recording, the replay loop restarts from tick zero.

    ServerThreadArgs = ref object
      server: ptr Server
      address: string
      port: int

  var appState: WebSocketAppState

proc addSpriteProtocolInit(
  packet: var seq[uint8],
  sim: SimServer,
  viewportWidth,
  viewportHeight: int,
  globalPanel = false
)
proc flippedHorizontal(sprite: RgbaSprite): RgbaSprite
proc conversationRingSprite(phase: int): RgbaSprite

proc dataDir(): string =
  ## Returns the Heartleaf data directory.
  let cwdData = getCurrentDir() / "data"
  if fileExists(cwdData / "map.aseprite"):
    return cwdData
  let repoData = getCurrentDir() / "heartleaf" / "data"
  if fileExists(repoData / "map.aseprite"):
    return repoData
  let sourceData = currentSourcePath().parentDir().parentDir() / "data"
  if fileExists(sourceData / "map.aseprite"):
    return sourceData
  return currentSourcePath().parentDir() / "data"

proc layerIndexByName(
  aseprite: AsepriteSprite,
  names: openArray[string]
): int =
  ## Returns the first layer index matching one of the given names.
  for i, layer in aseprite.layers:
    for name in names:
      if layer.name.normalize() == name.normalize():
        return i
  return -1

proc requiredLayerIndex(
  aseprite: AsepriteSprite,
  names: openArray[string],
  label: string
): int =
  ## Returns a named layer index or raises a Heartleaf error.
  result = aseprite.layerIndexByName(names)
  if result < 0:
    raise newException(
      HeartleafError,
      "Map aseprite needs a " & label & " layer."
    )

proc houseIndex(rect: ResourceRect): int =
  ## Returns the zero-based house index for one resource rectangle.
  rect.rectName().houseIndexFromName()

proc loadHouses(rects: openArray[ResourceRect]): array[HouseCount, House] =
  ## Loads numbered house rectangles from parsed resource data.
  for rect in rects:
    let index = rect.houseIndex()
    if index >= 0:
      result[index] = House(rect: rect.toRect(), valid: true)

proc loadHomeResources(rects: openArray[ResourceRect]): HomeResources =
  ## Loads named interaction rectangles from home resource data.
  result = HomeResources()
  for rect in rects:
    case rect.rectName()
    of "exit":
      result.exit = rect.toRect()
      result.hasExit = true
    of "wash":
      result.washes.add(rect.toRect())
    of "cook":
      result.cooks.add(rect.toRect())
    of "diner", "diners":
      result.diners.add(rect.toRect())
    else:
      discard

proc loadGardens(
  rects: openArray[ResourceRect],
  rng: var Rand
): seq[Garden] =
  ## Loads garden rectangles and gives each garden one food item.
  for rect in rects:
    if rect.rectName() == "garden":
      var garden = Garden(rect: rect.toRect())
      for i in 0 ..< GardenStartFoodCount:
        inc garden.inventory[rng.rand(FoodVeggieSlots - 1)]
      result.add(garden)

proc loadWalkMask(walkImage: Image): seq[bool] =
  ## Builds a per-pixel walk mask from an alpha layer.
  result = newSeq[bool](walkImage.width * walkImage.height)
  for y in 0 ..< walkImage.height:
    for x in 0 ..< walkImage.width:
      result[y * walkImage.width + x] = walkImage[x, y].a > 0

proc loadWorldMap(path, label: string): WorldMap =
  ## Loads one layered map with bottom, walkable, and overhang data.
  result = WorldMap()
  let aseprite = readAseprite(path)
  if aseprite.layers.len < 2:
    raise newException(
      HeartleafError,
      label & " aseprite needs a bottom and walkable layer."
    )

  let
    bottomLayer = max(0, aseprite.layerIndexByName(["bottom"]))
    walkLayer = aseprite.requiredLayerIndex(
      ["walkable", "walk"],
      "walkable"
    )
    overhangLayer = aseprite.layerIndexByName(["overhang"])
    bottomImage = aseprite.layerImage(bottomLayer)
    walkImage = aseprite.layerImage(walkLayer)
  result.width = aseprite.header.width
  result.height = aseprite.header.height
  result.bottomSprite = bottomImage.imageRgbaSprite()
  result.overhangSprite =
    if overhangLayer >= 0:
      aseprite.layerImage(overhangLayer).imageRgbaSprite()
    else:
      transparentRgbaSprite(result.width, result.height)
  for i in 0 ..< DayTintCount:
    result.bottomTints[i] = result.bottomSprite.hsvTinted(
      TintHueTargets[i],
      TintHueMixes[i],
      TintSaturationScales[i],
      TintValueScales[i]
    )
    result.overhangTints[i] = result.overhangSprite.hsvTinted(
      TintHueTargets[i],
      TintHueMixes[i],
      TintSaturationScales[i],
      TintValueScales[i]
    )
  result.walkMask = walkImage.loadWalkMask()

proc foldIntoBand(distance, band: int): int =
  ## Maps a distance past the map edge into the edge band, mirrored
  ## back and forth so adjacent reflections join without a seam.
  let t = distance mod (band * 2)
  if t < band:
    t
  else:
    band * 2 - 1 - t

proc forestJitter(x, y: int): (int, int) =
  ## A tiny deterministic per-pixel offset that decorrelates mirrored
  ## copies of the edge band so they read as forest, not ripples.
  let hash = uint32(x * 73_856_093) xor uint32(y * 19_349_663)
  (int((hash shr 8) mod 7) - 3, int((hash shr 16) mod 7) - 3)

proc forestUnderlay(bottom, overhang: RgbaSprite, margin, band: int): RgbaSprite =
  ## Extends the map outward with forest built from the map's own edge
  ## art. Pixels beyond the edge sample the outermost band of the
  ## composited map (bottom plus overhang canopy), mirrored back and
  ## forth with a slow wave along the edge and a per-pixel jitter so
  ## the reflections do not read as stripes, darkening toward
  ## deep-canopy shade so the border frames the village instead of
  ## competing with it. Sandy path pixels leaving the map fade into
  ## the canopy, so the roads disappear under the trees. The map
  ## interior stays transparent; the real map draws over that area.
  var base = newRgbaSprite(bottom.width, bottom.height)
  base.blitRgbaSprite(bottom, 0, 0)
  base.blitRgbaSprite(overhang, 0, 0)
  let
    w = base.width
    h = base.height
    fallback = rgba(26, 36, 20, 255)
  result = newRgbaSprite(w + margin * 2, h + margin * 2)
  for y in 0 ..< result.height:
    let wy = y - margin
    for x in 0 ..< result.width:
      let wx = x - margin
      if wx >= 0 and wx < w and wy >= 0 and wy < h:
        continue  # the map itself covers this area
      let
        dx =
          if wx < 0:
            -wx
          elif wx >= w:
            wx - w + 1
          else:
            0
        dy =
          if wy < 0:
            -wy
          elif wy >= h:
            wy - h + 1
          else:
            0
        outDist = max(dx, dy)
        # The jitter ramps in from zero so the first rows still join
        # the real map edge seamlessly.
        jitterRamp = min(outDist, 16)
        (rawJx, rawJy) = forestJitter(x, y)
        jx = rawJx * jitterRamp div 16
        jy = rawJy * jitterRamp div 16
      var
        sx = wx
        sy = wy
      let
        # The wave wanders more the deeper the forest goes, so the far
        # field jumbles its reflections instead of repeating in rows.
        # Its wavelength is long, so the wander reads as drifting
        # canopy rather than zigzag hedges.
        waveAmp = min(2.2, 1.0 + float(outDist) / 220.0)
      if dx > 0:
        # The wave is keyed on the along-edge coordinate so reflection
        # boundaries wander instead of forming straight ripples.
        let
          wave = int(9.0 * sin(float(wy) * 0.017) * waveAmp +
            4.0 * sin(float(wy) * 0.045 + 1.7))
          depth = foldIntoBand(max(0, dx - 1 + wave), band)
        sx =
          if wx < 0:
            depth
          else:
            w - 1 - depth
        sy = wy + jy
      if dy > 0:
        let
          wave = int(9.0 * sin(float(wx) * 0.014 + 0.9) * waveAmp +
            4.0 * sin(float(wx) * 0.039) )
          depth = foldIntoBand(max(0, dy - 1 + wave), band)
        sy =
          if wy < 0:
            depth
          else:
            h - 1 - depth
        if dx == 0:
          sx = wx + jx
      var color = base.rgbaSpriteAt(clamp(sx, 0, w - 1), clamp(sy, 0, h - 1))
      if color.a == 0:
        color = fallback
      # Sandy road pixels reflected past the edge sink into the trees.
      if int(color.r) > 160 and int(color.r) - int(color.b) > 50:
        let fade = min(1.0, float(outDist) / 70.0)
        color = rgba(
          uint8(float(color.r) + (float(fallback.r) - float(color.r)) * fade),
          uint8(float(color.g) + (float(fallback.g) - float(color.g)) * fade),
          uint8(float(color.b) + (float(fallback.b) - float(color.b)) * fade),
          255
        )
      let shade =
        1.0 - 0.55 * pow(min(1.0, float(outDist) / float(margin)), 0.75)
      result.putPixel(x, y, rgba(
        uint8(float(color.r) * shade),
        uint8(float(color.g) * shade),
        uint8(float(color.b) * shade),
        255
      ))

proc loadGnomeSprites(path: string): seq[GnomeSprites] =
  ## Loads all gnome direction sets from the sheet.
  let image = readAsepriteImage(path)
  if image.width mod GnomeSpriteSize != 0 or
      image.height mod GnomeSpriteSize != 0:
    raise newException(
      HeartleafError,
      "Gnome sheet dimensions must be multiples of " & $GnomeSpriteSize & "."
    )

  let
    cols = image.width div GnomeSpriteSize
    rows = image.height div GnomeSpriteSize
    spriteCount = cols * rows
  if spriteCount < DirectionCount or spriteCount mod DirectionCount != 0:
    raise newException(
      HeartleafError,
      "Gnome sheet must contain groups of four direction sprites."
    )

  result = newSeq[GnomeSprites](spriteCount div DirectionCount)
  for i in 0 ..< result.len:
    result[i] = GnomeSprites()
  for i in 0 ..< spriteCount:
    let
      cellX = i mod cols
      cellY = i div cols
      group = i div DirectionCount
      slot = i mod DirectionCount
      sprite = image.cellRgbaSprite(cellX, cellY, GnomeSpriteSize)
    case slot
    of 0:
      result[group].frames[DirDown] = sprite
    of 1:
      result[group].frames[DirUp] = sprite
    of 2:
      result[group].frames[DirRight] = sprite
    else:
      result[group].frames[DirLeft] = sprite

proc loadFoodSprites(path: string): FoodSprites =
  ## Loads veggie icons and the garden marker from the food sheet.
  result = FoodSprites()
  let image = readAsepriteImage(path)
  if image.width < FoodGridCols * FoodSpriteSize or
      image.height < FoodGridRows * FoodSpriteSize:
    raise newException(
      HeartleafError,
      "Food sheet must contain an 8x8 grid of 32px sprites."
    )

  for i in 0 ..< FoodVeggieSlots:
    let
      cellX = i mod FoodVeggieCols
      cellY = i div FoodVeggieCols
    result.icons[i] = image.cellRgbaSprite(cellX, cellY, FoodSpriteSize)
  result.marker = image.cellRgbaSprite(
    FoodMarkerCellX,
    FoodMarkerCellY,
    FoodSpriteSize
  )

proc loadEmoteSprite(path: string): RgbaSprite =
  ## Loads one emoji emote PNG (rasterized system emoji) into a sprite.
  let image = readImage(path)
  result = newRgbaSprite(image.width, image.height)
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      result.putPixel(x, y, image[x, y].rgba())

proc loadChatBanner(path: string): RgbaSprite =
  ## Loads and crops the delay-chat banner art to its solid bounds.
  if not fileExists(path):
    return newRgbaSprite(0, 0)
  let
    full = imageRgbaSprite(readAsepriteImage(path))
    bounds = full.solidBounds()
  if not bounds.found:
    return newRgbaSprite(0, 0)
  result = newRgbaSprite(
    bounds.maxX - bounds.minX + 1,
    bounds.maxY - bounds.minY + 1
  )
  for y in 0 ..< result.height:
    for x in 0 ..< result.width:
      result.putPixel(
        x,
        y,
        full.rgbaSpriteAt(bounds.minX + x, bounds.minY + y)
      )

proc nineSliceSprite(source: RgbaSprite, width, height, inset: int): RgbaSprite =
  ## Scales a bordered panel sprite to a new size with its corners
  ## kept crisp: corners copy, edges and the middle stretch.
  proc mapCoord(dest, destSize, srcSize, inset: int): int =
    if dest < inset:
      dest
    elif dest >= destSize - inset:
      srcSize - (destSize - dest)
    else:
      inset + (dest - inset) * (srcSize - inset * 2) div
        max(1, destSize - inset * 2)
  result = newRgbaSprite(width, height)
  for y in 0 ..< height:
    for x in 0 ..< width:
      result.putPixel(x, y, source.rgbaSpriteAt(
        clamp(mapCoord(x, width, source.width, inset), 0, source.width - 1),
        clamp(mapCoord(y, height, source.height, inset), 0, source.height - 1)
      ))

proc loadPortraits(dataRoot: string): seq[RgbaSprite] =
  ## Loads the gnome profile portraits used by the delay chat banner
  ## from a 3x3 grid sheet.
  let path = dataRoot / "gnome_faces.aseprite"
  if not fileExists(path):
    return
  let image = readAsepriteImage(path)
  if image.width mod PortraitGridColumns != 0:
    raise newException(
      HeartleafError,
      "Gnome faces sheet width must be a multiple of " &
        $PortraitGridColumns & "."
    )
  let cellSize = image.width div PortraitGridColumns
  for i in 0 ..< HouseCount:
    result.add(image.cellRgbaSprite(
      i mod PortraitGridColumns,
      i div PortraitGridColumns,
      cellSize
    ))

proc dumpForestUnderlay(map: WorldMap) =
  ## Writes the forest underlay composited under the daylight map to
  ## the PNG path in HEARTLEAF_FOREST_DUMP, for visual review of the
  ## generated border. A no-op when the variable is unset.
  let path = getEnv("HEARTLEAF_FOREST_DUMP")
  if path.len == 0:
    return
  var composite = newRgbaSprite(
    map.forestSprite.width,
    map.forestSprite.height
  )
  composite.blitRgbaSprite(map.forestSprite, 0, 0)
  composite.blitRgbaSprite(map.bottomSprite, ForestMarginPx, ForestMarginPx)
  composite.blitRgbaSprite(map.overhangSprite, ForestMarginPx, ForestMarginPx)
  var image = newImage(composite.width, composite.height)
  for y in 0 ..< composite.height:
    for x in 0 ..< composite.width:
      let color = composite.rgbaSpriteAt(x, y)
      image[x, y] = rgbx(color.r, color.g, color.b, color.a)
  image.writeFile(path)
  echo "forest underlay dumped to ", path

proc initSimServer*(seed = DefaultSeed, dayTicks = DayTicks): SimServer =
  ## Initializes the Heartleaf simulation.
  result = SimServer()
  result.dayTicks = max(TicksPerSecond, dayTicks)
  result.seatCount = HouseCount
  let dataRoot = dataDir()
  # Keep asset paths explicit here so startup shows what the game needs.
  let
    mapPath = dataRoot / "map.aseprite"
    homeMapPath = dataRoot / "home_map.aseprite"
    gnomesPath = dataRoot / "gnomes.aseprite"
    foodPath = dataRoot / "food.aseprite"
    resourcePath = dataRoot / "map.resource"
    homeResourcePath = dataRoot / "home_map.resource"
    tiny5Path = dataRoot / "tiny5.aseprite"
  result.rng = initRand(seed)
  result.resourceRects = loadResourceRects(resourcePath)
  result.homeResourceRects = loadResourceRects(homeResourcePath)
  result.homeResources = loadHomeResources(result.homeResourceRects)
  result.mainMap = loadWorldMap(mapPath, "Map")
  result.mainMap.forestSprite = forestUnderlay(
    result.mainMap.bottomSprite,
    result.mainMap.overhangSprite,
    ForestMarginPx,
    ForestBandPx
  )
  for i in 0 ..< DayTintCount:
    result.mainMap.forestTints[i] = forestUnderlay(
      result.mainMap.bottomTints[i],
      result.mainMap.overhangTints[i],
      ForestMarginPx,
      ForestBandPx
    )
  dumpForestUnderlay(result.mainMap)
  let homeMap = loadWorldMap(homeMapPath, "Home map")
  for i in 0 ..< HouseCount:
    result.homeMaps[i] = homeMap
  result.houses = loadHouses(result.resourceRects)
  result.gardens = loadGardens(result.resourceRects, result.rng)
  result.foods = loadFoodSprites(foodPath)
  result.gnomes = loadGnomeSprites(gnomesPath)
  if result.gnomes.len == 0:
    raise newException(HeartleafError, "Gnome sheet has no gnomes.")
  result.textFont = readPixelFont(tiny5Path)
  result.chatBanner = loadChatBanner(dataRoot / "chatbanner.aseprite")
  for tier in 0 ..< 3:
    result.heartEmoteBases[tier] =
      loadEmoteSprite(dataRoot / ("emote_tier" & $tier & ".png"))
  result.portraits = loadPortraits(dataRoot)
  result.conversationAnchors = initTable[int, ConversationAnchor]()
  result.chatFeedIndex = -1
  result.convQueueLast = -1
  result.directorCardLive = true
  result.players = @[]
  result.dayNumber = 1
  result.playerInitPacket.addSpriteProtocolInit(
    result,
    ViewportWidth,
    ViewportHeight,
    true
  )
  echo "init packet bytes: ", result.playerInitPacket.len

proc addRgbaSprite(
  packet: var seq[uint8],
  spriteId: int,
  sprite: RgbaSprite,
  label: string
) =
  ## Appends one RGBA sprite definition.
  packet.addSprite(spriteId, sprite.width, sprite.height, sprite.pixels, label)

proc addRgbaSpriteCached(
  packet: var seq[uint8],
  cache: var seq[SpriteCacheEntry],
  spriteId: int,
  sprite: RgbaSprite,
  label: string
) =
  ## Appends one RGBA sprite only when its pixels changed.
  for item in cache.mitems:
    if item.spriteId != spriteId:
      continue
    if item.width == sprite.width and
        item.height == sprite.height and
        item.pixels.pixelsMatch(sprite.pixels):
      return
    packet.addRgbaSprite(spriteId, sprite, label)
    item.width = sprite.width
    item.height = sprite.height
    item.pixels = sprite.pixels.copyPixels()
    return

  packet.addRgbaSprite(spriteId, sprite, label)
  cache.add(SpriteCacheEntry(
    spriteId: spriteId,
    width: sprite.width,
    height: sprite.height,
    pixels: sprite.pixels.copyPixels()
  ))

when not defined(emscripten):
  proc sendSpritePacket(websocket: WebSocket, packet: seq[uint8]) =
    ## Sends sprite protocol messages in certification-sized frames.
    var start = 0
    while start < packet.len:
      var stop = start
      while stop < packet.len:
        let messageBytes = packet.spriteMessageBytes(stop)
        if messageBytes <= 0:
          stop = packet.len
          break
        if stop > start and
            stop + messageBytes - start > MaxWebSocketFrameBytes:
          break
        stop += messageBytes
        if stop - start >= MaxWebSocketFrameBytes:
          break
      if stop == start:
        let messageBytes = packet.spriteMessageBytes(start)
        stop =
          if messageBytes > 0:
            start + messageBytes
          else:
            packet.len
      websocket.send(blobFromBytes(packet.toOpenArray(start, stop - 1)),
        BinaryMessage)
      start = stop

proc rectVisible(
  x,
  y,
  w,
  h,
  viewportWidth,
  viewportHeight: int
): bool =
  ## Returns true when one rectangle overlaps one viewport size.
  x < viewportWidth and y < viewportHeight and x + w > 0 and y + h > 0

proc chatTextWidth(sim: SimServer, text: string): int =
  ## Returns the rendered width of one chat line.
  sim.textFont.textWidth(text)

proc blitChatGlyph(
  target: var RgbaSprite,
  glyph: PixelGlyph,
  x, y: int,
  color: ColorRGBA
) =
  ## Blits one Tiny5 glyph into a sprite.
  for gy in 0 ..< glyph.height:
    for gx in 0 ..< glyph.width:
      if glyph.glyphPixel(gx, gy):
        target.putPixel(x + gx, y + gy, color)

proc blitTinyText(
  sim: SimServer,
  target: var RgbaSprite,
  text: string,
  x, y: int,
  color: ColorRGBA
) =
  ## Blits one Tiny5 text line into a sprite.
  var dx = x
  for ch in text:
    let glyph = sim.textFont.glyphAt(ch)
    target.blitChatGlyph(glyph, dx, y, color)
    dx += sim.textFont.glyphAdvance(ch)

proc blitChatText(
  sim: SimServer,
  target: var RgbaSprite,
  text: string,
  x, y: int
) =
  ## Blits white Tiny5 text into a sprite.
  sim.blitTinyText(target, text, x, y, rgba(255, 255, 255, 255))

proc chatBubbleLines(text: string): seq[string] =
  ## Wraps one chat message on spaces after the wrap width.
  var remaining = text
  while remaining.len > ChatWrapChars:
    var breakAt = -1
    for i in ChatWrapChars ..< remaining.len:
      if remaining[i] == ' ':
        breakAt = i
        break
    if breakAt <= 0 or breakAt >= remaining.len - 1:
      break
    result.add(remaining[0 ..< breakAt])
    remaining = remaining[breakAt + 1 .. ^1]
  result.add(remaining)

proc speechBubbleSprite(sim: SimServer, text: string): RgbaSprite =
  ## Builds one speech bubble sprite for a player message.
  let
    lines = chatBubbleLines(text)
    lineHeight = sim.textFont.height
  var textWidth = 6
  for line in lines:
    textWidth = max(textWidth, sim.chatTextWidth(line))
  let
    bodyWidth = textWidth + ChatPad * 2
    bodyHeight = lineHeight * lines.len + ChatPad * 2
    fill = rgba(TextBackR, TextBackG, TextBackB, 255)
  result = newRgbaSprite(bodyWidth, bodyHeight + ChatPointerHeight)
  result.fillRect(0, 0, bodyWidth, bodyHeight, fill)
  let pointerX = bodyWidth div 2
  for y in 0 ..< ChatPointerHeight:
    let span = ChatPointerHeight - y - 1
    for x in pointerX - span .. pointerX + span:
      result.putPixel(x, bodyHeight + y, fill)
  for i, line in lines:
    sim.blitChatText(
      result,
      line,
      ChatPad + (textWidth - sim.chatTextWidth(line)) div 2,
      ChatPad + i * lineHeight
    )

proc nameTagSprite(sim: SimServer, text: string): RgbaSprite =
  ## Builds one compact player name tag sprite.
  let
    width = max(1, sim.textFont.textWidth(text) + NamePadX * 2)
    height = sim.textFont.height + NamePadY * 2
    fill = rgba(TextBackR, TextBackG, TextBackB, 255)
  result = newRgbaSprite(width, height)
  result.fillRect(0, 0, width, height, fill)
  sim.blitChatText(result, text, NamePadX, NamePadY)

proc inventoryCountSprite(sim: SimServer, count: int): RgbaSprite =
  ## Builds one compact inventory count sprite.
  let
    text = $count
    width = max(1, sim.textFont.textWidth(text) + NamePadX * 2)
    height = sim.textFont.height + NamePadY * 2
    fill = rgba(TextBackR, TextBackG, TextBackB, 255)
  result = newRgbaSprite(width, height)
  result.fillRect(0, 0, width, height, fill)
  sim.blitChatText(result, text, NamePadX, NamePadY)

proc clockGlyphWidth(sim: SimServer, ch: char): int =
  ## Returns the rendered sprite width for one clock glyph.
  max(1, sim.textFont.textWidth($ch) + ClockPadX * 2)

proc clockGlyphSprite(sim: SimServer, ch: char): RgbaSprite =
  ## Builds one individual clock glyph sprite.
  let
    width = sim.clockGlyphWidth(ch)
    height = sim.textFont.height + ClockPadY * 2
    fill = rgba(TextBackR, TextBackG, TextBackB, 220)
  result = newRgbaSprite(width, height)
  result.fillRect(0, 0, width, height, fill)
  sim.blitChatText(result, $ch, ClockPadX, ClockPadY)

proc overlaySprite(): RgbaSprite =
  ## Builds one fully black viewport-sized overlay sprite.
  result = newRgbaSprite(ViewportWidth, ViewportHeight)
  result.fillRect(
    0,
    0,
    ViewportWidth,
    ViewportHeight,
    rgba(0, 0, 0, 255)
  )

proc drawFoodCounts(
  sim: SimServer,
  target: var RgbaSprite,
  foods: FoodCounts,
  x,
  y: int
) =
  ## Draws food icons with their item counts.
  var slot = 0
  for foodIndex, count in foods:
    if count <= 0:
      continue
    let
      col = slot mod OverlayFoodColumns
      row = slot div OverlayFoodColumns
      iconX = x + col * OverlayFoodStep
      iconY = y + row * OverlayFoodStep
    if iconY + FoodSpriteSize > ViewportHeight:
      return
    target.blitRgbaSprite(sim.foods.icons[foodIndex], iconX, iconY)
    let countSprite = sim.inventoryCountSprite(count)
    target.blitRgbaSprite(
      countSprite,
      iconX + FoodSpriteSize - countSprite.width,
      iconY + FoodSpriteSize - countSprite.height
    )
    inc slot

proc drawDinnerGuests(
  sim: SimServer,
  target: var RgbaSprite,
  record: DinnerRecord,
  x,
  y: int
) =
  ## Draws gnome icons with names for fed dinner guests.
  for i, name in record.guestNames:
    let
      col = i mod OverlayGuestColumns
      row = i div OverlayGuestColumns
      iconX = x + col * OverlayGuestCellWidth
      iconY = y + row * OverlayGuestCellHeight
    if iconY + GnomeSpriteSize > ViewportHeight:
      return
    if i < record.guestGnomeIndices.len:
      let gnomeIndex = record.guestGnomeIndices[i]
      if gnomeIndex >= 0 and gnomeIndex < sim.gnomes.len:
        target.blitRgbaSprite(
          sim.gnomes[gnomeIndex].frames[DirDown],
          iconX,
          iconY
        )
    sim.blitChatText(target, name, iconX + GnomeSpriteSize + 2, iconY + 12)

proc dinnerOverlaySprite(sim: SimServer, record: DinnerRecord): RgbaSprite =
  ## Builds the full-screen dinner result overlay.
  result = overlaySprite()
  if record.wasHost:
    sim.blitChatText(result, "During dinner party you fed:", 8, 4)
    sim.blitChatText(result, "+" & $record.score & " score", 8, 16)
    sim.blitChatText(result, "Guests: " & $record.guestCount, 8, 27)
    sim.drawDinnerGuests(result, record, 8, 36)
    sim.drawFoodCounts(result, record.foods, 8, 100)
  else:
    sim.blitChatText(result, "At dinner party you ate:", 8, 8)
    sim.blitChatText(result, "+" & $record.score & " score", 8, 20)
    sim.blitChatText(result, "Host: " & record.hostName, 8, 32)
    sim.drawFoodCounts(result, record.foods, 8, 44)

proc attributedDisplayName(player: Player): string =
  ## Returns the review name with username and fixed gnome name.
  if player.username.len == 0:
    return player.playerName
  return player.username & " (" & player.playerName & ")"

proc scoreOverlaySprite(sim: SimServer): RgbaSprite =
  ## Builds the full-screen cumulative score overlay.
  result = overlaySprite()
  sim.blitChatText(result, "End of day scores", 8, 8)
  for i, player in sim.players:
    let
      col = i mod OverlayScoreColumns
      row = i div OverlayScoreColumns
      x = 8 + col * OverlayScoreCellWidth
      y = 28 + row * OverlayScoreCellHeight
    if y + GnomeSpriteSize > ViewportHeight:
      return
    result.blitRgbaSprite(
      sim.gnomes[player.gnomeIndex].frames[DirDown],
      x,
      y
    )
    sim.blitChatText(
      result,
      player.playerName,
      x,
      y + GnomeSpriteSize + 2
    )
    sim.blitChatText(result, "Score: " & $player.score, x + 36, y + 12)

proc globalPanelTextSprite(
  sim: SimServer,
  text: string,
  color: ColorRGBA
): RgbaSprite =
  ## Builds one Tiny5 text sprite for the global score panel.
  result = newRgbaSprite(
    max(1, sim.textFont.textWidth(text)),
    sim.textFont.height
  )
  sim.blitTinyText(result, text, 0, 0, color)

proc globalPanelScoreText(score: int): string =
  ## Returns one global panel score label.
  $max(0, score)

proc selectedGlobalPlayerIndex(state: PlayerViewerState, sim: SimServer): int =
  ## Returns the selected global player index clamped to connected players.
  if sim.players.len == 0:
    return -1
  result = state.selectedPlayerIndex
  if result < 0:
    return -1
  if result >= sim.players.len:
    return -1

proc addGlobalScorePanel(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  selectedIndex: int
) =
  ## Appends the global top-left score and selection panel, housed in
  ## the same parchment nine-slice card as the conversation cards.
  if sim.players.len == 0:
    return
  # Size the card to its rows before drawing anything.
  var
    rows = 0
    maxRight = 0
  for i, player in sim.players:
    let rowY = GlobalPanelPad + i * GlobalPanelRowHeight
    if GlobalPanelCardPadY * 2 + rowY + GlobalPanelRowHeight >
        GlobalPanelHeight:
      break
    rows = i + 1
    maxRight = max(maxRight, GlobalPanelNameX +
      sim.textFont.textWidth(player.attributedDisplayName()))
    maxRight = max(maxRight, GlobalPanelScoreX +
      sim.textFont.textWidth(player.score.globalPanelScoreText()))
  if rows == 0:
    return
  let
    cardWidth = min(GlobalPanelWidth, GlobalPanelCardPadX * 2 + maxRight + 1)
    cardHeight = GlobalPanelCardPadY * 2 + GlobalPanelPad +
      rows * GlobalPanelRowHeight
  var card: RgbaSprite
  if sim.chatBanner.width > 0:
    card = sim.chatBanner.nineSliceSprite(
      cardWidth, cardHeight, DirectorCardSliceInset
    )
  else:
    card = newRgbaSprite(cardWidth, cardHeight)
    card.fillRect(0, 0, cardWidth, cardHeight, rgba(233, 213, 170, 245))
  packet.addRgbaSpriteCached(
    cache,
    GlobalPanelCardSpriteId,
    card,
    "global panel card " & $cardWidth & "x" & $cardHeight
  )
  packet.addObject(
    GlobalPanelCardObjectId,
    0,
    0,
    0,
    GlobalPanelLayerId,
    GlobalPanelCardSpriteId
  )
  for i, player in sim.players:
    if i >= rows:
      return
    let
      rowY = GlobalPanelCardPadY + GlobalPanelPad + i * GlobalPanelRowHeight
      scoreText = player.score.globalPanelScoreText()
      scoreSpriteId = GlobalPanelScoreSpriteBase + i
      nameSpriteId = GlobalPanelNameSpriteBase + i
      nameColor =
        if i == selectedIndex:
          rgba(
            GlobalPanelSelectedInkR,
            GlobalPanelSelectedInkG,
            GlobalPanelSelectedInkB,
            255
          )
        else:
          rgba(GlobalPanelTextR, GlobalPanelTextG, GlobalPanelTextB, 255)
    packet.addRgbaSpriteCached(
      cache,
      scoreSpriteId,
      sim.globalPanelTextSprite(
        scoreText,
        rgba(GlobalPanelScoreR, GlobalPanelScoreG, GlobalPanelScoreB, 255)
      ),
      "global value " & $i & " " & scoreText
    )
    packet.addRgbaSpriteCached(
      cache,
      nameSpriteId,
      sim.globalPanelTextSprite(player.attributedDisplayName(), nameColor),
      "global name " & $i & " " & player.attributedDisplayName() & " " &
        (if i == selectedIndex: "selected" else: "plain")
    )
    packet.addObject(
      GlobalPanelScoreObjectBase + i,
      GlobalPanelCardPadX + GlobalPanelScoreX,
      rowY,
      1,
      GlobalPanelLayerId,
      scoreSpriteId
    )
    packet.addObject(
      GlobalPanelNameObjectBase + i,
      GlobalPanelCardPadX + GlobalPanelNameX,
      rowY,
      2,
      GlobalPanelLayerId,
      nameSpriteId
    )

proc addNameTag(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  player: Player,
  playerIndex,
  screenX,
  screenY,
  z,
  viewportWidth,
  viewportHeight: int
): int =
  ## Appends a player name tag and returns its top y coordinate.
  let
    tag = sim.nameTagSprite(player.playerName)
    x = screenX + GnomeSpriteSize div 2 - tag.width div 2
    y = screenY - tag.height - NameGapY
    spriteId = NameSpriteBase + playerIndex
  if not rectVisible(
    x,
    y,
    tag.width,
    tag.height,
    viewportWidth,
    viewportHeight
  ):
    return y
  packet.addRgbaSpriteCached(cache, spriteId, tag, NameLabelPrefix & player.playerName)
  packet.addObject(
    NameObjectBase + playerIndex,
    x,
    y,
    z,
    MapLayerId,
    spriteId
  )
  return y

proc addSpeechBubble(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  player: Player,
  playerIndex,
  screenX,
  anchorY,
  z,
  viewportWidth,
  viewportHeight: int,
  placedBubbles: var seq[tuple[x, y, w, h: int]]
) =
  ## Appends a speech bubble object above one player name. A bubble
  ## that would cover one already placed this frame is lifted above it,
  ## so gnomes talking in a huddle stay readable.
  if player.message.len == 0 or player.messageTicks <= 0:
    return
  let
    bubble = sim.speechBubbleSprite(player.message)
    spriteId = ChatSpriteBase + playerIndex
  var
    x = screenX + GnomeSpriteSize div 2 - bubble.width div 2
    y = anchorY - bubble.height - ChatGapY
    lifted = true
  # A bubble that would clip at the viewport edge slides back inside;
  # its pointer stays on the speaker's column.
  if bubble.width >= viewportWidth:
    x = (viewportWidth - bubble.width) div 2
  else:
    x = clamp(x, 0, viewportWidth - bubble.width)
  while lifted:
    lifted = false
    for rect in placedBubbles:
      if x < rect.x + rect.w and rect.x < x + bubble.width and
          y < rect.y + rect.h and rect.y < y + bubble.height:
        y = rect.y - bubble.height - ChatGapY
        lifted = true
  placedBubbles.add((x: x, y: y, w: bubble.width, h: bubble.height))
  if not rectVisible(
    x,
    y,
    bubble.width,
    bubble.height,
    viewportWidth,
    viewportHeight
  ):
    return
  packet.addRgbaSpriteCached(cache, spriteId, bubble, ChatLabelPrefix & player.message)
  packet.addObject(
    ChatObjectBase + playerIndex,
    x,
    y,
    z,
    MapLayerId,
    spriteId
  )

proc directionLabel(direction: Direction): string =
  ## Returns the sprite label for one direction.
  case direction
  of DirDown:
    "down"
  of DirUp:
    "up"
  of DirRight:
    "right"
  of DirLeft:
    "left"

proc playerSpriteId(gnomeIndex: int, direction: Direction): int =
  ## Returns the sprite id for one gnome direction.
  PlayerSpriteBase + gnomeIndex * DirectionCount + ord(direction)

proc foodSpriteId(foodIndex: int): int =
  ## Returns the sprite id for one veggie inventory icon.
  FoodSpriteBase + foodIndex

proc mainBottomSpriteId(tintIndex: int): int =
  ## Returns the main map bottom sprite id for one day tint.
  if tintIndex < 0:
    return BottomSpriteId
  return MainBottomTintSpriteBase + tintIndex

proc mainOverhangSpriteId(tintIndex: int): int =
  ## Returns the main map overhang sprite id for one day tint.
  if tintIndex < 0:
    return OverhangSpriteId
  return MainOverhangTintSpriteBase + tintIndex

proc forestSpriteId(tintIndex: int): int =
  ## Returns the forest underlay sprite id for one day tint.
  if tintIndex < 0:
    return ForestSpriteBase
  return ForestSpriteBase + 1 + tintIndex

proc homeBottomSpriteId(tintIndex: int): int =
  ## Returns the home map bottom sprite id for one day tint.
  if tintIndex < 0:
    return HomeBottomSpriteId
  return HomeBottomTintSpriteBase + tintIndex

proc homeOverhangSpriteId(tintIndex: int): int =
  ## Returns the home map overhang sprite id for one day tint.
  if tintIndex < 0:
    return HomeOverhangSpriteId
  return HomeOverhangTintSpriteBase + tintIndex

proc clockGlyphIndex(ch: char): int =
  ## Returns the compact clock sprite slot for one glyph.
  for i, glyph in ClockGlyphs:
    if glyph == ch:
      return i
  for i, glyph in ClockGlyphs:
    if glyph == ' ':
      return i
  return 0

proc clockGlyphSpriteId(ch: char): int =
  ## Returns the sprite id for one clock glyph.
  ClockGlyphSpriteBase + ch.clockGlyphIndex()

proc bannerGlyphSpriteId(ch: char): int =
  ## Returns the init-packet sprite id for one banner glyph.
  var index = ord(ch) - FirstPrintableAscii
  if index < 0 or index >= PrintableAsciiCount:
    index = ord('?') - FirstPrintableAscii
  ChatBannerGlyphSpriteBase + index

proc bannerGlyphSprite(sim: SimServer, ch: char): RgbaSprite =
  ## Builds one Tiny5 glyph in banner ink on a transparent background.
  let
    glyph = sim.textFont.glyphAt(ch)
    width = max(1, glyph.width)
    height = max(1, glyph.height)
    ink = rgba(ChatBannerInkR, ChatBannerInkG, ChatBannerInkB, 255)
  result = newRgbaSprite(width, height)
  for gy in 0 ..< glyph.height:
    for gx in 0 ..< glyph.width:
      if glyph.glyphPixel(gx, gy):
        result.putPixel(gx, gy, ink)

proc portraitSpriteId(gnomeIndex: int, flipped: bool): int =
  ## Returns the init-packet sprite id for one gnome portrait.
  let slot =
    if gnomeIndex < 0:
      0
    else:
      gnomeIndex mod HouseCount
  if flipped:
    PortraitFlipSpriteBase + slot
  else:
    PortraitSpriteBase + slot

proc dailyResultsJson*(sim: SimServer): string =
  ## Returns one daily player score result as JSON.
  var
    names = newJArray()
    usernames = newJArray()
    playerNames = newJArray()
    scores = newJArray()
    results = newJObject()
  for houseIndex in 0 ..< sim.seatCount:
    let fixedPlayerName = houseIndex.playerNameForHouse()
    var player: Player = nil
    for candidate in sim.players:
      if candidate.homeFlag == HomeMapIndexBase + houseIndex:
        player = candidate
        break
    if player != nil:
      names.add(%player.attributedDisplayName())
      usernames.add(%player.username)
      playerNames.add(%player.playerName)
      scores.add(%player.score)
    else:
      names.add(%fixedPlayerName)
      usernames.add(%"")
      playerNames.add(%fixedPlayerName)
      scores.add(%0)
  results["day"] = %sim.dayNumber
  results["names"] = names
  results["usernames"] = usernames
  results["playerNames"] = playerNames
  results["scores"] = scores
  return $results

proc totalItems(foods: FoodCounts): int =
  ## Returns the total number of items in one food count set.
  for count in foods:
    result += count

proc clearFoods(foods: var FoodCounts) =
  ## Clears one food count set.
  for i in 0 ..< FoodVeggieSlots:
    foods[i] = 0

proc isHomeMap(mapIndex: int): bool =
  ## Returns true when a map id points at one of the nine home maps.
  mapIndex >= HomeMapIndexBase and mapIndex < HomeMapIndexBase + HouseCount

proc homeMapIndex(houseIndex: int): int =
  ## Converts a zero-based house index to its one-based home map id.
  HomeMapIndexBase + houseIndex

proc mapFor(sim: SimServer, mapIndex: int): WorldMap =
  ## Returns the live world map data for one map id.
  if mapIndex.isHomeMap():
    return sim.homeMaps[mapIndex - HomeMapIndexBase]
  return sim.mainMap

proc currentDayMinutes(sim: SimServer): int =
  ## Returns the current in-game minute of the day.
  let step = min(DayStepCount, sim.dayTick * DayStepCount div sim.dayTicks)
  return DayStartMinutes + step * DayStepMinutes

proc clockText(sim: SimServer): string =
  ## Returns the current weekday and game clock as 12-hour text.
  sim.dayNumber.weekdayName() & " " & sim.currentDayMinutes().clockName()

proc dayTintIndex(sim: SimServer): int =
  ## Returns the active dusk tint index, or -1 during full daylight.
  let minutes = sim.currentDayMinutes()
  if minutes < DuskStartMinutes:
    return -1
  return min(
    DayTintCount - 1,
    (minutes - DuskStartMinutes) * DayTintCount div
      (DayEndMinutes - DuskStartMinutes)
  )

proc addSpriteProtocolInit(
  packet: var seq[uint8],
  sim: SimServer,
  viewportWidth,
  viewportHeight: int,
  globalPanel = false
) =
  ## Appends static sprite protocol setup for one viewer.
  packet.addViewport(MapLayerId, viewportWidth, viewportHeight)
  packet.addViewport(UiLayerId, InventoryUiWidth, InventoryUiHeight)
  packet.addViewport(ClockLayerId, ClockUiWidth, ClockUiHeight)
  if globalPanel:
    packet.addViewport(
      GlobalPanelLayerId,
      GlobalPanelWidth,
      GlobalPanelHeight
    )
  packet.addLayer(MapLayerId, MapLayerKind, MapLayerFlags)
  packet.addLayer(UiLayerId, UiLayerKind, UiLayerFlags)
  packet.addLayer(ClockLayerId, ClockLayerKind, UiLayerFlags)
  if globalPanel:
    packet.addLayer(
      GlobalPanelLayerId,
      GlobalPanelLayerKind,
      UiLayerFlags
    )
  packet.addRgbaSprite(
    BottomSpriteId,
    sim.mainMap.bottomSprite,
    MainBottomLabelPrefix
  )
  packet.addRgbaSprite(
    OverhangSpriteId,
    sim.mainMap.overhangSprite,
    MainOverhangLabelPrefix
  )
  for i in 0 ..< DayTintCount:
    packet.addRgbaSprite(
      mainBottomSpriteId(i),
      sim.mainMap.bottomTints[i],
      MainBottomLabelPrefix & " tint " & $i
    )
    packet.addRgbaSprite(
      mainOverhangSpriteId(i),
      sim.mainMap.overhangTints[i],
      MainOverhangLabelPrefix & " tint " & $i
    )
  if sim.mainMap.forestSprite.width > 0:
    packet.addRgbaSprite(
      forestSpriteId(-1),
      sim.mainMap.forestSprite,
      "forest underlay"
    )
    for i in 0 ..< DayTintCount:
      packet.addRgbaSprite(
        forestSpriteId(i),
        sim.mainMap.forestTints[i],
        "forest underlay tint " & $i
      )
  packet.addRgbaSprite(
    HomeBottomSpriteId,
    sim.homeMaps[0].bottomSprite,
    HomeBottomLabelPrefix
  )
  packet.addRgbaSprite(
    HomeOverhangSpriteId,
    sim.homeMaps[0].overhangSprite,
    HomeOverhangLabelPrefix
  )
  for i in 0 ..< DayTintCount:
    packet.addRgbaSprite(
      homeBottomSpriteId(i),
      sim.homeMaps[0].bottomTints[i],
      HomeBottomLabelPrefix & " tint " & $i
    )
    packet.addRgbaSprite(
      homeOverhangSpriteId(i),
      sim.homeMaps[0].overhangTints[i],
      HomeOverhangLabelPrefix & " tint " & $i
    )
  for ch in ClockGlyphs:
    packet.addRgbaSprite(
      ch.clockGlyphSpriteId(),
      sim.clockGlyphSprite(ch),
      ClockLabelPrefix & $ch
    )
  for foodIndex, icon in sim.foods.icons:
    packet.addRgbaSprite(foodSpriteId(foodIndex), icon, foodIndex.foodName())
  packet.addRgbaSprite(
    FoodMarkerSpriteId,
    sim.foods.marker,
    GardenMarkerLabel
  )
  for gnomeIndex, gnome in sim.gnomes:
    for direction in Direction:
      packet.addRgbaSprite(
        playerSpriteId(gnomeIndex, direction),
        gnome.frames[direction],
        GnomeLabelPrefix & $gnomeIndex & " " & direction.directionLabel()
      )
  if sim.chatBanner.width > 0:
    packet.addRgbaSprite(
      ChatBannerSpriteId,
      sim.chatBanner,
      "chat banner"
    )
  for i, portrait in sim.portraits:
    packet.addRgbaSprite(
      PortraitSpriteBase + i,
      portrait,
      "portrait " & $i
    )
    packet.addRgbaSprite(
      PortraitFlipSpriteBase + i,
      portrait.flippedHorizontal(),
      "portrait flip " & $i
    )
  for code in FirstPrintableAscii .. LastPrintableAscii:
    let ch = char(code)
    packet.addRgbaSprite(
      ch.bannerGlyphSpriteId(),
      sim.bannerGlyphSprite(ch),
      "banner glyph " & $ch
    )
  for phase in 0 ..< ConversationRingPhases:
    packet.addRgbaSprite(
      ConversationRingSpriteBase + phase,
      conversationRingSprite(phase),
      "conversation ring " & $phase
    )

proc worldClampPixel(value, maxValue: int): int =
  ## Clamps one pixel coordinate into a non-negative world range.
  value.clamp(0, max(0, maxValue))

proc playerFootX(player: Player): int =
  ## Returns the foot-center x coordinate for one player.
  player.x.footXAt()

proc playerFootY(player: Player): int =
  ## Returns the foot-center y coordinate for one player.
  player.y.footYAt()

proc playerIsWalking(player: Player): bool =
  ## True when this gnome is moving. Conversation members stand still.
  abs(player.velX) >= StopThreshold or
    abs(player.velY) >= StopThreshold or
    player.inputX != 0 or
    player.inputY != 0

proc outdoorConversationFeet*(
  sim: SimServer,
  seatPlayers: openArray[int],
  stillOnly = false
): Table[int, Point] =
  ## Outdoor foot positions keyed by house seat, for sparkle rings.
  ## stillOnly skips walkers: a moving gnome has left the huddle.
  for seat in 0 ..< min(seatPlayers.len, HouseCount):
    let playerIndex = seatPlayers[seat]
    if playerIndex < 0 or playerIndex >= sim.players.len:
      continue
    let player = sim.players[playerIndex]
    if player.mapIndex != MainMapIndex:
      continue
    if stillOnly and player.playerIsWalking():
      continue
    result[seat] = Point(
      x: player.playerFootX(),
      y: player.playerFootY()
    )

proc isWalkable(world: WorldMap, x, y: int): bool =
  ## Returns true when one world pixel is walkable.
  if x < 0 or y < 0 or x >= world.width or y >= world.height:
    return false
  return world.walkMask[y * world.width + x]

proc canOccupy(world: WorldMap, x, y: int): bool =
  ## Returns true when a gnome can stand at one sprite position.
  ## Gnomes occupy a single foot-center pixel, like crewrift crew.
  world.isWalkable(x.footXAt(), y.footYAt())

proc hasFood(garden: Garden): bool =
  ## Returns true when a garden still has food to collect.
  for count in garden.inventory:
    if count > 0:
      return true

proc spawnClear(sim: SimServer, mapIndex, x, y: int): bool =
  ## Returns true when a spawn is walkable and away from other players.
  let world = sim.mapFor(mapIndex)
  if not world.canOccupy(x, y):
    return false
  let
    cx = x.footXAt()
    cy = y.footYAt()
  for player in sim.players:
    if player.mapIndex != mapIndex:
      continue
    if distanceSquared(
      cx,
      cy,
      player.playerFootX(),
      player.playerFootY()
    ) < MinSpawnSpacing * MinSpawnSpacing:
      return false
  return true

proc findHouseSpawn(
  sim: SimServer,
  houseIndex: int,
  spawnX,
  spawnY: var int
): bool =
  ## Finds a walkable spawn near one numbered house.
  if houseIndex < 0 or houseIndex >= HouseCount:
    return false
  if not sim.houses[houseIndex].valid:
    return false

  let
    house = sim.houses[houseIndex].rect
    maxX = max(0, sim.mainMap.width - GnomeSpriteSize)
    maxY = max(0, sim.mainMap.height - GnomeSpriteSize)
  var radius = 0
  while radius <= HouseSpawnMaxDistance:
    let
      minX = max(0, house.x - radius - GnomeSpriteSize)
      minY = max(0, house.y - radius - GnomeSpriteSize)
      maxScanX = min(maxX, house.x + house.w + radius)
      maxScanY = min(maxY, house.y + house.h + radius)
    var y = minY
    while y <= maxScanY:
      var x = minX
      while x <= maxScanX:
        let feet = Rect(x: x.footXAt(), y: y.footYAt(), w: 1, h: 1)
        if feet.rectDistanceSquared(house) <= radius * radius and
            sim.spawnClear(MainMapIndex, x, y):
          spawnX = x
          spawnY = y
          return true
        x += SpawnScanStep
      y += SpawnScanStep
    radius += SpawnScanStep

proc findMainSpawn(sim: SimServer, houseIndex = -1): tuple[x, y: int] =
  ## Returns a walkable main map spawn position.
  var
    spawnX = 0
    spawnY = 0
  if sim.findHouseSpawn(houseIndex, spawnX, spawnY):
    return (spawnX, spawnY)

  let
    maxX = max(0, sim.mainMap.width - GnomeSpriteSize)
    maxY = max(0, sim.mainMap.height - GnomeSpriteSize)
  for _ in 0 ..< 5000:
    let
      x = sim.rng.rand(maxX)
      y = sim.rng.rand(maxY)
    if sim.spawnClear(MainMapIndex, x, y):
      return (x, y)

  var y = 0
  while y <= maxY:
    var x = 0
    while x <= maxX:
      if sim.spawnClear(MainMapIndex, x, y):
        return (x, y)
      x += SpawnScanStep
    y += SpawnScanStep

  raise newException(HeartleafError, "Map has no walkable spawn.")

proc findHomeSpawn(sim: SimServer, mapIndex: int): tuple[x, y: int] =
  ## Returns a walkable spawn near the top center door of a home map.
  let
    world = sim.mapFor(mapIndex)
    doorX = max(0, (world.width - GnomeSpriteSize) div 2)
    doorY = 0
    doorFootX = doorX.footXAt()
    doorFootY = doorY.footYAt()
    maxX = max(0, world.width - GnomeSpriteSize)
    maxY = max(0, world.height - GnomeSpriteSize)
    maxRadius = max(world.width, world.height)
  var radius = 0
  while radius <= maxRadius:
    let
      minX = max(0, doorX - radius)
      minY = max(0, doorY - radius)
      maxScanX = min(maxX, doorX + radius)
      maxScanY = min(maxY, doorY + radius)
    var y = minY
    while y <= maxScanY:
      var x = minX
      while x <= maxScanX:
        if distanceSquared(
          x.footXAt(),
          y.footYAt(),
          doorFootX,
          doorFootY
        ) <= radius * radius and
            sim.spawnClear(mapIndex, x, y):
          return (x, y)
        x += SpawnScanStep
      y += SpawnScanStep
    radius += SpawnScanStep

  raise newException(HeartleafError, "Home map has no walkable spawn.")

proc chatCharSupported(ch: char): bool =
  ## Returns true when Heartleaf can draw one chat character.
  ch >= ' ' and ch <= '~'

proc cleanDisplayText(text: string, maxChars: int): string =
  ## Normalizes one printable Tiny5 text field.
  for ch in text.strip():
    if result.len >= maxChars:
      return
    if ch.chatCharSupported():
      result.add(ch)

proc cleanChatMessage(message: string): string =
  ## Normalizes one submitted player chat message.
  message.cleanDisplayText(ChatMaxChars)

proc cleanUsername(username: string): string =
  ## Normalizes one connection username for score display.
  result = username.cleanDisplayText(NameMaxChars)
  for ch in result.mitems:
    if ch.isSpaceAscii:
      ch = '_'

proc addPlayer*(sim: SimServer, username: string, requestedSlot = -1): int =
  ## Adds one player at a walkable spawn.
  var usedHomes: array[HouseCount, bool]
  for player in sim.players:
    if player.homeFlag.isHomeMap():
      usedHomes[player.homeFlag - HomeMapIndexBase] = true

  var houseIndex = -1
  if requestedSlot >= 0 and
      requestedSlot < HouseCount and
      not usedHomes[requestedSlot]:
    houseIndex = requestedSlot
  else:
    for i in 0 ..< HouseCount:
      if not usedHomes[i]:
        houseIndex = i
        break
  if houseIndex < 0:
    return -1

  let
    mapIndex = houseIndex.homeMapIndex()
    spawn = sim.findHomeSpawn(mapIndex)
    requestedUsername = username.cleanUsername()
    safeUsername =
      if requestedUsername.len > 0:
        requestedUsername
      else:
        "player_" & $(houseIndex + 1)
    playerName = houseIndex.playerNameForHouse()
    gnomeIndex = houseIndex mod sim.gnomes.len
  sim.players.add Player(
    username: safeUsername,
    playerName: playerName,
    x: spawn.x,
    y: spawn.y,
    direction: DirDown,
    gnomeIndex: gnomeIndex,
    homeFlag: mapIndex,
    mapIndex: mapIndex
  )
  return sim.players.high

proc gardenInReach(sim: SimServer, player: Player): int =
  ## Returns the closest harvestable garden in reach.
  result = -1
  if player.mapIndex != MainMapIndex:
    return
  let
    feet = Rect(
      x: player.playerFootX(),
      y: player.playerFootY(),
      w: 1,
      h: 1
    )
    maxDistance = InteractionRadius * InteractionRadius
  var bestDistance = maxDistance + 1
  for i, garden in sim.gardens:
    if not garden.hasFood():
      continue
    let distance = feet.rectDistanceSquared(garden.rect)
    if distance <= maxDistance and distance < bestDistance:
      result = i
      bestDistance = distance

proc collectGarden(sim: SimServer, playerIndex, gardenIndex: int) =
  ## Moves all food at one garden into a player's inventory.
  for foodIndex in 0 ..< FoodVeggieSlots:
    let count = sim.gardens[gardenIndex].inventory[foodIndex]
    if count <= 0:
      continue
    sim.players[playerIndex].inventory[foodIndex] += count
    sim.gardens[gardenIndex].inventory[foodIndex] = 0

proc houseContaining(sim: SimServer, player: Player): int =
  ## Returns the house containing a player's foot-center point.
  result = -1
  if player.mapIndex != MainMapIndex:
    return
  let
    footX = player.playerFootX()
    footY = player.playerFootY()
  for i, house in sim.houses:
    if house.valid and house.rect.contains(footX, footY):
      return i

proc playerAtHomeExit(sim: SimServer, player: Player): bool =
  ## Returns true when a home player is standing in the exit area.
  if not player.mapIndex.isHomeMap():
    return false
  if not sim.homeResources.hasExit:
    return false
  return sim.homeResources.exit.contains(
    player.playerFootX(),
    player.playerFootY()
  )

proc teleportPlayer(
  sim: SimServer,
  playerIndex,
  mapIndex,
  x,
  y: int,
  direction: Direction
) =
  ## Moves one player to a map and clears movement state.
  sim.players[playerIndex].mapIndex = mapIndex
  sim.players[playerIndex].x = x
  sim.players[playerIndex].y = y
  sim.players[playerIndex].direction = direction
  sim.players[playerIndex].velX = 0
  sim.players[playerIndex].velY = 0
  sim.players[playerIndex].carryX = 0
  sim.players[playerIndex].carryY = 0

proc interact(sim: SimServer, playerIndex: int) =
  ## Applies one A-button interaction for a player.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  if sim.players[playerIndex].mapIndex.isHomeMap():
    if not sim.playerAtHomeExit(sim.players[playerIndex]):
      return
    let
      houseIndex = sim.players[playerIndex].mapIndex - HomeMapIndexBase
      spawn = sim.findMainSpawn(houseIndex)
    sim.teleportPlayer(
      playerIndex,
      MainMapIndex,
      spawn.x,
      spawn.y,
      DirDown
    )
    return

  let gardenIndex = sim.gardenInReach(sim.players[playerIndex])
  if gardenIndex >= 0:
    sim.collectGarden(playerIndex, gardenIndex)
    return

  let houseIndex = sim.houseContaining(sim.players[playerIndex])
  if houseIndex >= 0:
    let
      mapIndex = houseIndex.homeMapIndex()
      spawn = sim.findHomeSpawn(mapIndex)
    sim.teleportPlayer(
      playerIndex,
      mapIndex,
      spawn.x,
      spawn.y,
      DirDown
    )

proc cameraXFor(sim: SimServer, player: Player): int =
  ## Returns the player camera x coordinate.
  let world = sim.mapFor(player.mapIndex)
  return worldClampPixel(
    player.playerFootX() - ViewportWidth div 2,
    world.width - ViewportWidth
  )

proc cameraYFor(sim: SimServer, player: Player): int =
  ## Returns the player camera y coordinate.
  let world = sim.mapFor(player.mapIndex)
  return worldClampPixel(
    player.playerFootY() - ViewportHeight div 2,
    world.height - ViewportHeight
  )

proc foodListText(foods: FoodCounts): string =
  ## Returns "Carrot x2, Beet" style text for one food count set.
  for foodIndex, count in foods:
    if count <= 0:
      continue
    if result.len > 0:
      result.add(", ")
    result.add(foodIndex.foodName())
    if count > 1:
      result.add(" x" & $count)
  if result.len == 0:
    result = "none"

proc addScreenOverlay(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  player: Player,
  playerIndex: int
) =
  ## Appends one full-screen dinner or score overlay.
  var
    overlay: RgbaSprite
    label = ""
  if player.dinnerTicks > 0 and player.dinnerRecord != nil:
    overlay = sim.dinnerOverlaySprite(player.dinnerRecord)
    label = DinnerLabelPrefix & $playerIndex
  elif sim.scoreTicks > 0:
    overlay = sim.scoreOverlaySprite()
    label = ScoreLabelPrefix & $playerIndex
  else:
    return

  let spriteId = ScoreSpriteBase + playerIndex
  packet.addRgbaSpriteCached(cache, spriteId, overlay, label)
  packet.addObject(
    ScoreObjectBase + playerIndex,
    0,
    0,
    ScoreZ,
    MapLayerId,
    spriteId
  )

const
  OutlineWhite = ColorRGBA(r: 255, g: 255, b: 255, a: 255)
  OutlineYellow = ColorRGBA(
    r: GlobalPanelSelectedR,
    g: GlobalPanelSelectedG,
    b: GlobalPanelSelectedB,
    a: 255
  )
  TrailColors = [
    ColorRGBA(r: 235, g: 90, b: 80, a: 220),
    ColorRGBA(r: 245, g: 150, b: 60, a: 220),
    ColorRGBA(r: 250, g: 220, b: 80, a: 220),
    ColorRGBA(r: 120, g: 210, b: 90, a: 220),
    ColorRGBA(r: 90, g: 220, b: 210, a: 220),
    ColorRGBA(r: 100, g: 150, b: 250, a: 220),
    ColorRGBA(r: 175, g: 110, b: 250, a: 220),
    ColorRGBA(r: 245, g: 120, b: 200, a: 220),
    ColorRGBA(r: 245, g: 245, b: 245, a: 220)
  ]

proc gnomeOutlineSprite(
  sim: SimServer,
  gnomeIndex: int,
  direction: Direction,
  color: ColorRGBA
): RgbaSprite =
  ## Builds a 1px pixel outline hugging one gnome frame's silhouette.
  let frame = sim.gnomes[gnomeIndex].frames[direction]
  result = newRgbaSprite(
    frame.width + OutlinePad * 2,
    frame.height + OutlinePad * 2
  )
  for y in 0 ..< result.height:
    for x in 0 ..< result.width:
      if frame.rgbaSpriteAt(x - OutlinePad, y - OutlinePad).a > 0:
        continue
      block neighbors:
        for dy in -1 .. 1:
          for dx in -1 .. 1:
            if frame.rgbaSpriteAt(
              x - OutlinePad + dx,
              y - OutlinePad + dy
            ).a > 0:
              result.putPixel(x, y, color)
              break neighbors

proc gnomeOutlineSpriteId(
  gnomeIndex: int,
  direction: Direction,
  yellow: bool
): int =
  ## Returns the sprite id for one cached gnome outline variant.
  GnomeOutlineSpriteBase +
    (gnomeIndex * DirectionCount + ord(direction)) * 2 +
    ord(yellow)

proc addGnomeOutline(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  gnomeIndex: int,
  direction: Direction,
  yellow: bool,
  objectId,
  screenX,
  screenY,
  z: int
) =
  ## Appends one silhouette outline object behind a gnome sprite.
  let
    spriteId = gnomeOutlineSpriteId(gnomeIndex, direction, yellow)
    color =
      if yellow:
        OutlineYellow
      else:
        OutlineWhite
  packet.addRgbaSpriteCached(
    cache,
    spriteId,
    sim.gnomeOutlineSprite(gnomeIndex, direction, color),
    "gnome outline " & $gnomeIndex & " " & directionLabel(direction) &
      (if yellow: " yellow" else: " white")
  )
  packet.addObject(
    objectId,
    screenX - OutlinePad,
    screenY - OutlinePad,
    z,
    MapLayerId,
    spriteId
  )

proc trailDotSprite(color: ColorRGBA): RgbaSprite =
  ## Builds one 5x5 round trail dot with a dark rim.
  let
    fill = ColorRGBA(r: color.r, g: color.g, b: color.b, a: 255)
    rim = ColorRGBA(
      r: fill.r div 3,
      g: fill.g div 3,
      b: fill.b div 3,
      a: 255
    )
  result = newRgbaSprite(5, 5)
  for y in 0 ..< 5:
    for x in 0 ..< 5:
      if (x == 0 or x == 4) and (y == 0 or y == 4):
        continue
      result.putPixel(x, y, rim)
  for y in 1 .. 3:
    for x in 1 .. 3:
      result.putPixel(x, y, fill)

proc addTrailObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  cameraX = 0,
  cameraY = 0
) =
  ## Appends per-player movement trail dots on the main map.
  for i, trail in sim.trails:
    if trail.len == 0:
      continue
    let
      colorIndex = i mod TrailColors.len
      spriteId = TrailDotSpriteBase + colorIndex
    packet.addRgbaSpriteCached(
      cache,
      spriteId,
      trailDotSprite(TrailColors[colorIndex]),
      "trail dot " & $colorIndex
    )
    for j, point in trail:
      if point.mapIndex != MainMapIndex:
        continue
      packet.addObject(
        TrailObjectBase + i * TrailMaxPoints + j,
        point.x - 2 - cameraX,
        point.y - 2 - cameraY,
        TrailZ,
        MapLayerId,
        spriteId
      )

proc putSparklePixel(sprite: var RgbaSprite, x, y: int, color: ColorRGBA) =
  ## One sparkle pixel, ignoring anything off the sprite.
  if x >= 0 and x < sprite.width and y >= 0 and y < sprite.height:
    sprite.putPixel(x, y, color)

proc drawSparkle(sprite: var RgbaSprite, x, y, twinkle: int) =
  ## One four-pointed glint. The twinkle variant cycles a sparkle from a
  ## small star through a full star with diagonal rays and back, so the
  ## ring shimmers.
  let
    core = rgba(255, 253, 240, 255)
    glow = rgba(255, 214, 110, 240)
    haze = rgba(255, 228, 160, 170)
  sprite.putSparklePixel(x, y, core)
  case twinkle mod 4
  of 0:
    sprite.putSparklePixel(x - 1, y, haze)
    sprite.putSparklePixel(x + 1, y, haze)
    sprite.putSparklePixel(x, y - 1, haze)
    sprite.putSparklePixel(x, y + 1, haze)
  of 1, 3:
    for arm in 1 .. 2:
      sprite.putSparklePixel(x - arm, y, glow)
      sprite.putSparklePixel(x + arm, y, glow)
      sprite.putSparklePixel(x, y - arm, glow)
      sprite.putSparklePixel(x, y + arm, glow)
  else:
    sprite.putSparklePixel(x - 1, y, core)
    sprite.putSparklePixel(x + 1, y, core)
    sprite.putSparklePixel(x, y - 1, core)
    sprite.putSparklePixel(x, y + 1, core)
    for arm in 2 .. 3:
      sprite.putSparklePixel(x - arm, y, glow)
      sprite.putSparklePixel(x + arm, y, glow)
      sprite.putSparklePixel(x, y - arm, glow)
      sprite.putSparklePixel(x, y + arm, glow)
    sprite.putSparklePixel(x - 1, y - 1, haze)
    sprite.putSparklePixel(x + 1, y - 1, haze)
    sprite.putSparklePixel(x - 1, y + 1, haze)
    sprite.putSparklePixel(x + 1, y + 1, haze)

proc conversationRingSprite(phase: int): RgbaSprite =
  ## One animation frame of the shared sparkle ring. Glints crawl a
  ## fraction of a slot per phase. Built once for the init packet.
  let
    size = ConversationRingRadius * 2 + ConversationRingPad
    center = float(size) / 2.0
    slot = 2.0 * PI / float(ConversationSparkles)
  result = newRgbaSprite(size, size)
  let band = rgba(255, 222, 150, 80)
  for y in 0 ..< size:
    for x in 0 ..< size:
      let
        dx = float(x) + 0.5 - center
        dy = float(y) + 0.5 - center
        dist = sqrt(dx * dx + dy * dy)
      if abs(dist - float(ConversationRingRadius)) <= 1.2:
        result.putPixel(x, y, band)
  for i in 0 ..< ConversationSparkles:
    let
      angle = float(i) * slot +
        float(phase) * slot / float(ConversationRingPhases)
      x = int(center + cos(angle) * float(ConversationRingRadius))
      y = int(center + sin(angle) * float(ConversationRingRadius))
    result.drawSparkle(x, y, i * 3 + phase)

proc addConversationCircles(
  packet: var seq[uint8],
  sim: SimServer,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
) =
  ## Appends conversation circles as the shared 16-frame sparkle ring.
  ## Sprite pixels live in the init packet; frames only cycle object
  ## sprite ids.
  let
    phase =
      (sim.tickCount div ConversationRingTicksPerPhase) mod
        ConversationRingPhases
    size = ConversationRingRadius * 2 + ConversationRingPad
    spriteId = ConversationRingSpriteBase + phase
  for ci, circle in sim.conversationCircles:
    let
      screenX = circle.x - size div 2 - cameraX
      screenY = circle.y - size div 2 - cameraY
    if not rectVisible(
      screenX,
      screenY,
      size,
      size,
      viewportWidth,
      viewportHeight
    ):
      continue
    packet.addObject(
      ConversationRingObjectBase + ci,
      screenX,
      screenY,
      ConversationRingZ,
      MapLayerId,
      spriteId
    )

proc inferHuddleCircles(sim: SimServer) =
  ## Fallback rings for a replay with no game.log next to it (an http
  ## replay URI): outdoor gnomes standing together while one of them
  ## holds a speech bubble read as a conversation huddle. Anchors
  ## freeze where the huddle first forms and outlive the quiet beats
  ## between lines, like the logged rings.
  var
    feet: seq[Point]
    indexes: seq[int]
    speaking: seq[bool]
  for i, player in sim.players:
    if player.mapIndex != MainMapIndex:
      continue
    if player.playerIsWalking():
      continue
    feet.add(Point(x: player.playerFootX(), y: player.playerFootY()))
    indexes.add(i)
    speaking.add(player.message.len > 0 and player.messageTicks > 0)
  # Label propagation: standing gnomes within conversation range of any
  # member share one huddle. Nine gnomes at most, so n squared is fine.
  var labels = newSeq[int](feet.len)
  for i in 0 ..< labels.len:
    labels[i] = i
  var changed = true
  while changed:
    changed = false
    for a in 0 ..< feet.len:
      for b in a + 1 ..< feet.len:
        if labels[a] == labels[b]:
          continue
        let
          dx = feet[a].x - feet[b].x
          dy = feet[a].y - feet[b].y
        if dx * dx + dy * dy <=
            ConversationExitRadius * ConversationExitRadius:
          let merged = min(labels[a], labels[b])
          labels[a] = merged
          labels[b] = merged
          changed = true
  for label in 0 ..< feet.len:
    var
      huddle: seq[Point]
      key = high(int)
      heard = false
    for i in 0 ..< feet.len:
      if labels[i] != label:
        continue
      huddle.add(feet[i])
      key = min(key, indexes[i])
      heard = heard or speaking[i]
    if huddle.len < 2 or not heard:
      continue
    if key in sim.inferredHuddles:
      var kept = sim.inferredHuddles[key]
      kept.ttl = HuddleHoldFrames
      sim.inferredHuddles[key] = kept
    else:
      let circle = huddle.conversationCircle()
      sim.inferredHuddles[key] =
        (x: circle.x, y: circle.y, ttl: HuddleHoldFrames)
  var keys: seq[int]
  for key in sim.inferredHuddles.keys:
    keys.add(key)
  for key in keys:
    var entry = sim.inferredHuddles[key]
    dec entry.ttl
    if entry.ttl <= 0:
      sim.inferredHuddles.del(key)
    else:
      sim.inferredHuddles[key] = entry
      sim.conversationCircles.add(
        (entry.x, entry.y, ConversationRingRadius)
      )

proc inferConversationCircles*(sim: SimServer) =
  ## Places one frozen sparkle ring on every open conversation. Replay
  ## uses the game.log enter/exit timeline. Walkers are treated as
  ## having left; one gnome left dissolves the ring. A joiner recenters
  ## the ring once. Live play overwrites this from the encounter book.
  sim.conversationCircles.setLen(0)
  if sim.conversationTimeline.events.len == 0:
    sim.inferHuddleCircles()
    return
  var liveIds: seq[int]
  for group in sim.conversationTimeline.encounterGroupsAt(sim.tickCount):
    var
      huddle: seq[Point]
      seats: seq[int]
    for houseIndex in group.members:
      var player: Player = nil
      for candidate in sim.players:
        if candidate.homeFlag == HomeMapIndexBase + houseIndex:
          player = candidate
          break
      if player == nil or player.mapIndex != MainMapIndex:
        continue
      if player.playerIsWalking():
        continue
      huddle.add(Point(x: player.playerFootX(), y: player.playerFootY()))
      seats.add(houseIndex)
    if huddle.len < 2:
      sim.conversationAnchors.del(group.id)
      continue
    liveIds.add(group.id)
    let old = sim.conversationAnchors.getOrDefault(group.id)
    if old.seats.len == 0 or old.seats.seatsHaveJoin(seats):
      sim.conversationAnchors[group.id] =
        huddle.placeConversationAnchor(seats)
    else:
      var kept = old
      kept.seats = seats
      sim.conversationAnchors[group.id] = kept
    let anchor = sim.conversationAnchors[group.id]
    sim.conversationCircles.add((
      anchor.x, anchor.y, ConversationRingRadius
    ))
  var gone: seq[int]
  for id in sim.conversationAnchors.keys:
    if id notin liveIds:
      gone.add(id)
  for id in gone:
    sim.conversationAnchors.del(id)

proc attachConversationTimeline*(
  sim: SimServer,
  data: ReplayData,
  replayPath: string
) =
  ## Loads chat-mode enter/exit events so rings follow conversations,
  ## not nearby walkers. The replay's own conversation records come
  ## first - they travel inside the one file, so hosted and wasm
  ## viewers get rings too; a game.log next to the replay is the
  ## fallback for replays recorded before the records existed.
  sim.conversationTimeline = ConversationTimeline()
  sim.conversationAnchors.clear()
  let recorded = data.conversationLogText()
  if recorded.len > 0:
    # Older replays share the record channel with circle rows and may
    # hold no conversation events at all - only records that actually
    # parse count, or the game.log fallback below still gets its turn.
    sim.conversationTimeline = parseConversationTimeline(recorded)
    if sim.conversationTimeline.events.len > 0:
      echo "Conversation records: ",
        sim.conversationTimeline.events.len, " events from the replay"
      return
  if replayPath.len == 0:
    return
  sim.conversationTimeline =
    loadConversationTimeline(replayPath.parentDir / "game.log")

proc cliLoadReplayPath(): string =
  ## The --load-replay path from argv, or empty.
  const Prefix = "--load-replay:"
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg.startsWith(Prefix):
      return arg[Prefix.len .. ^1]

proc heartNoise(a, b, c: int): float =
  ## Deterministic hash noise in -1.0 .. 1.0, stable across replays.
  var h = a * 73856093 xor b * 19349663 xor c * 83492791
  h = h xor (h shr 13)
  h = h *% 1274126177
  h = h xor (h shr 16)
  float((h and 1023) - 512) / 512.0

proc heartLinkTier(links: int): int =
  ## Maps one pair's conversation history to an emote tier: a neutral
  ## face for a fresh acquaintance, a smile for a friend, star-eyes
  ## for a strong bond.
  clamp((links - 1) div 4, 0, 2)

proc heartEmoteSprite(sim: SimServer, tier, fade: int): RgbaSprite =
  ## The tier's emoji emote, alpha-faded for one life stage; cached.
  let key = clamp(tier, 0, 2) * 4 + clamp(fade, 0, 3)
  if key in sim.heartEmoteFaded:
    return sim.heartEmoteFaded[key]
  let
    base = sim.heartEmoteBases[clamp(tier, 0, 2)]
    alpha = [255, 210, 150, 80][clamp(fade, 0, 3)]
  var sprite = newRgbaSprite(base.width, base.height)
  for y in 0 ..< base.height:
    for x in 0 ..< base.width:
      var color = base.rgbaSpriteAt(x, y)
      color.a = uint8(int(color.a) * alpha div 255)
      sprite.putPixel(x, y, color)
  sim.heartEmoteFaded[key] = sprite
  sprite

proc addHeartEmoteObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  mapIndex,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
) =
  ## Appends Sims-style emote emojis: each gnome standing near a
  ## connected partner sends its own emoji drifting up from its head
  ## and fading. The connection tier picks the face - a plain smile for
  ## a fresh acquaintance up to heart-eyes for the strongest bonds -
  ## and how many rise per cycle. In replays the strengths come from a
  ## pure fold of the conversation records inside the replay file, so
  ## the animation is identical everywhere.
  let pairs =
    if sim.conversationTimeline.events.len > 0:
      sim.conversationTimeline.heartLinksAt(sim.tickCount)
    else:
      sim.heartLinks
  if pairs.len == 0:
    return
  var byHouse: array[HouseCount, int]
  for h in 0 ..< HouseCount:
    byHouse[h] = -1
  for i, player in sim.players:
    let house = player.homeFlag - HomeMapIndexBase
    if house >= 0 and house < HouseCount:
      byHouse[house] = i
  var bestTier: array[HouseCount, int]
  for h in 0 ..< HouseCount:
    bestTier[h] = -1
  for pair in pairs:
    if pair.links <= 0:
      continue
    if pair.a < 0 or pair.a >= HouseCount or
        pair.b < 0 or pair.b >= HouseCount:
      continue
    if byHouse[pair.a] < 0 or byHouse[pair.b] < 0:
      continue
    let
      a = sim.players[byHouse[pair.a]]
      b = sim.players[byHouse[pair.b]]
    if a.mapIndex != mapIndex or b.mapIndex != mapIndex:
      continue
    let
      dxi = b.x - a.x
      dyi = b.y - a.y
    if dxi * dxi + dyi * dyi > HeartLinkMaxDistance * HeartLinkMaxDistance:
      continue
    let tier = heartLinkTier(pair.links)
    bestTier[pair.a] = max(bestTier[pair.a], tier)
    bestTier[pair.b] = max(bestTier[pair.b], tier)
  for house in 0 ..< HouseCount:
    if bestTier[house] < 0 or byHouse[house] < 0:
      continue
    let
      player = sim.players[byHouse[house]]
      tier = bestTier[house]
    for k in 0 ..< HeartEmoteCount[tier]:
      let
        age = (sim.tickCount + house * 13 + k * HeartEmoteStagger) mod
          HeartEmotePeriod
      if age >= HeartEmoteLife:
        continue
      let
        progress = age.float / HeartEmoteLife.float
        fade = clamp(int(progress * 4.0), 0, 3)
        cycle = (sim.tickCount + house * 13 + k * HeartEmoteStagger) div
          HeartEmotePeriod
        sway = heartNoise(house, k, cycle) * 5.0
        sprite = sim.heartEmoteSprite(tier, fade)
        spriteId = HeartSpriteBase + clamp(tier, 0, 2) * 4 + fade
        ex = player.x + GnomeSpriteSize div 2 - sprite.width div 2 +
          int(sway)
        ey = player.y - 10 - int(progress * HeartEmoteRise.float)
        screenX = ex - cameraX
        screenY = ey - cameraY
      if not rectVisible(
        screenX,
        screenY,
        sprite.width,
        sprite.height,
        viewportWidth,
        viewportHeight
      ):
        continue
      packet.addRgbaSpriteCached(
        cache,
        spriteId,
        sprite,
        "heart emote t" & $tier & " f" & $fade
      )
      packet.addObject(
        HeartObjectBase + house * 4 + k,
        screenX,
        screenY,
        HeartLinkZ,
        MapLayerId,
        spriteId
      )

proc addPlayerObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  mapIndex,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int,
  highlightIndex = -1,
  includeBubbles = true
) =
  ## Appends all player sprite objects for one map.
  if mapIndex == MainMapIndex:
    packet.addConversationCircles(
      sim, cameraX, cameraY, viewportWidth, viewportHeight
    )
    packet.addHeartEmoteObjects(
      sim, cache, mapIndex, cameraX, cameraY, viewportWidth, viewportHeight
    )
  var bubbleRects: seq[tuple[x, y, w, h: int]]
  for i, player in sim.players:
    if player.mapIndex != mapIndex:
      continue
    let
      screenX = player.x - cameraX
      screenY = player.y - cameraY
    if not rectVisible(
      screenX,
      screenY,
      GnomeSpriteSize,
      GnomeSpriteSize,
      viewportWidth,
      viewportHeight
    ):
      continue
    packet.addObject(
      PlayerObjectBase + i,
      screenX,
      screenY,
      player.y + 100,
      MapLayerId,
      playerSpriteId(player.gnomeIndex, player.direction)
    )
    if i == highlightIndex:
      packet.addGnomeOutline(
        sim,
        cache,
        player.gnomeIndex,
        player.direction,
        yellow = true,
        PlayerBorderObjectId,
        screenX,
        screenY,
        player.y + 99
      )
    let nameY = packet.addNameTag(
      sim,
      cache,
      player,
      i,
      screenX,
      screenY,
      NameZ,
      viewportWidth,
      viewportHeight
    )
    if includeBubbles:
      packet.addSpeechBubble(
        sim,
        cache,
        player,
        i,
        screenX,
        nameY,
        ChatZ,
        viewportWidth,
        viewportHeight,
        bubbleRects
      )

proc addHouseGnomeObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  cameraX = 0,
  cameraY = 0
) =
  ## Draws gnomes who are inside a house on the outside map in one
  ## horizontal row centered above the house door, outlined white for
  ## guests and yellow for the house owner.
  var occupants: array[HouseCount, seq[int]]
  for i, player in sim.players:
    let houseIndex = player.mapIndex - HomeMapIndexBase
    if houseIndex < 0 or houseIndex >= HouseCount:
      continue
    if not sim.houses[houseIndex].valid:
      continue
    occupants[houseIndex].add(i)
  for houseIndex in 0 ..< HouseCount:
    if occupants[houseIndex].len == 0:
      continue
    let
      rect = sim.houses[houseIndex].rect
      stride = GnomeSpriteSize + OutlinePad * 2 + 2
      rowWidth = stride * occupants[houseIndex].len - 2
      startX = rect.x + rect.w div 2 - rowWidth div 2
      rowY = rect.y - GnomeSpriteSize - HouseGnomeLift - cameraY
    for slot, i in occupants[houseIndex]:
      let
        player = sim.players[i]
        x = startX + slot * stride - cameraX
        isOwner = player.homeFlag == HomeMapIndexBase + houseIndex
      packet.addObject(
        HouseGnomeObjectBase + i,
        x,
        rowY,
        HouseGnomeZ + slot * 2 + 1,
        MapLayerId,
        playerSpriteId(player.gnomeIndex, DirDown)
      )
      packet.addGnomeOutline(
        sim,
        cache,
        player.gnomeIndex,
        DirDown,
        yellow = isOwner,
        HouseGnomeBorderObjectBase + i,
        x,
        rowY,
        HouseGnomeZ + slot * 2
      )

proc addHouseInsetView(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  houseIndex: int,
  offsetX = 0
) =
  ## Draws one house interior centered over the global map view.
  ## offsetX shifts the inset right, for viewports wider than the map.
  let
    homeMap = sim.homeMaps[houseIndex]
    tintIndex = sim.dayTintIndex()
    insetX = max(0, (sim.mainMap.width - homeMap.width) div 2) + offsetX
    insetY = max(0, (sim.mainMap.height - homeMap.height) div 2)
    mapIndex = houseIndex.homeMapIndex()
  packet.addObject(
    InsetBottomObjectId,
    insetX,
    insetY,
    InsetBottomZ,
    MapLayerId,
    homeBottomSpriteId(tintIndex)
  )
  var bubbleRects: seq[tuple[x, y, w, h: int]]
  for i, player in sim.players:
    if player.mapIndex != mapIndex:
      continue
    let
      screenX = insetX + player.x
      screenY = insetY + player.y
    packet.addObject(
      InsetPlayerObjectBase + i,
      screenX,
      screenY,
      clamp(
        InsetPlayerZBase + player.y,
        InsetPlayerZBase,
        InsetOverhangZ - 1
      ),
      MapLayerId,
      playerSpriteId(player.gnomeIndex, player.direction)
    )
    let nameY = packet.addNameTag(
      sim,
      cache,
      player,
      i,
      screenX,
      screenY,
      InsetNameZ,
      sim.mainMap.width,
      sim.mainMap.height
    )
    packet.addSpeechBubble(
      sim,
      cache,
      player,
      i,
      screenX,
      nameY,
      InsetChatZ,
      sim.mainMap.width,
      sim.mainMap.height,
      bubbleRects
    )
  packet.addObject(
    InsetOverhangObjectId,
    insetX,
    insetY,
    InsetOverhangZ,
    MapLayerId,
    homeOverhangSpriteId(tintIndex)
  )

proc addGardenObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
) =
  ## Appends garden item markers for gardens that still hold food.
  for i, garden in sim.gardens:
    if not garden.hasFood():
      continue
    let
      x = garden.rect.x + garden.rect.w div 2 - FoodSpriteSize div 2
      y = garden.rect.y + garden.rect.h div 2 - FoodSpriteSize div 2
      screenX = x - cameraX
      screenY = y - cameraY
    if not rectVisible(
      screenX,
      screenY,
      FoodSpriteSize,
      FoodSpriteSize,
      viewportWidth,
      viewportHeight
    ):
      continue
    packet.addObject(
      GardenObjectBase + i,
      screenX,
      screenY,
      GardenMarkerZ,
      MapLayerId,
      FoodMarkerSpriteId
    )

proc addInventoryObjects(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  player: Player
) =
  ## Appends a compact bottom-right inventory UI for one player.
  var slot = 0
  for foodIndex, count in player.inventory:
    if count <= 0:
      continue
    let
      col = slot mod InventoryColumns
      row = slot div InventoryColumns
      x = InventoryUiWidth - FoodSpriteSize - col * InventoryIconStep
      y = InventoryUiHeight - FoodSpriteSize - row * InventoryIconStep
    packet.addObject(
      InventoryObjectBase + foodIndex,
      x,
      y,
      0,
      UiLayerId,
      foodSpriteId(foodIndex)
    )
    let
      countSprite = sim.inventoryCountSprite(count)
      countX = x + FoodSpriteSize - countSprite.width
      countY = y + FoodSpriteSize - countSprite.height
      spriteId = InventoryCountSpriteBase + foodIndex
    packet.addRgbaSpriteCached(
      cache,
      spriteId,
      countSprite,
      "inventory " & foodIndex.foodName() & " " & $count
    )
    packet.addObject(
      InventoryCountObjectBase + foodIndex,
      countX,
      countY,
      1,
      UiLayerId,
      spriteId
    )
    inc slot

proc addClockObjects(packet: var seq[uint8], sim: SimServer) =
  ## Appends the upper-right clock using individual glyph objects.
  let text = sim.clockText()
  var totalWidth = 0
  for ch in text:
    totalWidth += sim.clockGlyphWidth(ch)
  totalWidth += max(0, text.len - 1) * ClockGlyphGap

  var x = max(0, ClockUiWidth - totalWidth)
  for i, ch in text:
    packet.addObject(
      ClockObjectBase + i,
      x,
      0,
      0,
      ClockLayerId,
      ch.clockGlyphSpriteId()
    )
    x += sim.clockGlyphWidth(ch) + ClockGlyphGap

proc addPlayerView(
  packet: var seq[uint8],
  sim: SimServer,
  playerIndex: int,
  cache: var seq[SpriteCacheEntry],
  highlight = false
): bool =
  ## Appends one selected player's map and UI view.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  let
    player = sim.players[playerIndex]
    onMainMap = player.mapIndex == MainMapIndex
    tintIndex = sim.dayTintIndex()
    cameraX = sim.cameraXFor(player)
    cameraY = sim.cameraYFor(player)
    bottomSpriteId =
      if onMainMap:
        mainBottomSpriteId(tintIndex)
      else:
        homeBottomSpriteId(tintIndex)
    overhangSpriteId =
      if onMainMap:
        mainOverhangSpriteId(tintIndex)
      else:
        homeOverhangSpriteId(tintIndex)
  if player.dinnerTicks > 0 or sim.scoreTicks > 0:
    packet.addScreenOverlay(
      sim,
      cache,
      player,
      playerIndex
    )
    return true
  packet.addObject(
    BottomObjectId,
    -cameraX,
    -cameraY,
    BottomZ,
    MapLayerId,
    bottomSpriteId
  )
  if onMainMap:
    packet.addGardenObjects(
      sim,
      cameraX,
      cameraY,
      ViewportWidth,
      ViewportHeight
    )
  packet.addPlayerObjects(
    sim,
    cache,
    player.mapIndex,
    cameraX,
    cameraY,
    ViewportWidth,
    ViewportHeight,
    highlightIndex =
      if highlight:
        playerIndex
      else:
        -1
  )
  packet.addObject(
    OverhangObjectId,
    -cameraX,
    -cameraY,
    OverhangZ,
    MapLayerId,
    overhangSpriteId
  )
  packet.addInventoryObjects(
    sim,
    cache,
    player
  )
  packet.addClockObjects(sim)
  return true

proc addGlobalWorldView(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry]
) =
  ## Appends the full main map view for an unselected global viewer.
  let tintIndex = sim.dayTintIndex()
  packet.addViewport(MapLayerId, sim.mainMap.width, sim.mainMap.height)
  packet.addObject(
    BottomObjectId,
    0,
    0,
    BottomZ,
    MapLayerId,
    mainBottomSpriteId(tintIndex)
  )
  packet.addGardenObjects(
    sim,
    0,
    0,
    sim.mainMap.width,
    sim.mainMap.height
  )
  packet.addTrailObjects(sim, cache)
  packet.addPlayerObjects(
    sim,
    cache,
    MainMapIndex,
    0,
    0,
    sim.mainMap.width,
    sim.mainMap.height
  )
  packet.addHouseGnomeObjects(sim, cache)
  packet.addObject(
    OverhangObjectId,
    0,
    0,
    OverhangZ,
    MapLayerId,
    mainOverhangSpriteId(tintIndex)
  )
  packet.addClockObjects(sim)

proc startDirectorTween(sim: SimServer) =
  ## Begins a timed camera glide from the current crop. The target is
  ## recomputed every frame, so a glide can chase a drifting ring and
  ## still land exactly on it when the countdown runs out.
  sim.directorTweenLeft = DirectorTweenFrames
  sim.directorTweenFromX = sim.directorCamX
  sim.directorTweenFromY = sim.directorCamY
  sim.directorTweenFromW = sim.directorCamW
  sim.directorTweenFromH = sim.directorCamH

proc releaseDirectorCommit(sim: SimServer) =
  ## Ends the camera's queue commitment: the shot glides back out to
  ## the wide view and the feed scope opens up again.
  sim.directorCommitEncounter = 0
  sim.chatFeedScope = 0
  if sim.directorFocusActive:
    sim.directorFocusActive = false
    sim.directorLastFocusX = sim.directorFocusX
    sim.directorLastFocusY = sim.directorFocusY
    sim.directorHasLastFocus = true
    sim.startDirectorTween()
    echo "Director commit out at tick ", sim.tickCount

proc updateDirectorCamera*(sim: SimServer) =
  ## Advances the director cut's camera one frame. The cut is fully
  ## automated: the wide shot of the village while nothing happens, a
  ## smooth zoom onto the sparkle ring while a conversation runs, back
  ## out to the wide shot when it ends, then into the next ring. The
  ## crop keeps the map's aspect, so the zoom never stretches.
  let
    mapW = float(sim.mainMap.width)
    mapH = float(sim.mainMap.height)
  if sim.directorCamW <= 0 or sim.directorCamH <= 0:
    sim.directorCamX = 0
    sim.directorCamY = 0
    sim.directorCamW = mapW
    sim.directorCamH = mapH
  # A gnome hops when its new line lands, so the eye finds the speaker.
  if sim.directorBounce.len < sim.players.len:
    sim.directorBounce.setLen(sim.players.len)
    sim.directorLastMessages.setLen(sim.players.len)
  for i, player in sim.players:
    if player.message.len > 0 and
        player.message != sim.directorLastMessages[i]:
      sim.directorLastMessages[i] = player.message
      sim.directorBounce[i] = DirectorBounceHops.len
    elif sim.directorBounce[i] > 0:
      dec sim.directorBounce[i]
  # A dinner party happens indoors, where the outdoor map shows
  # nothing: track the busiest house holding a real gathering so the
  # view can overlay its interior.
  var
    dinnerHouse = -1
    dinnerCount = 0
  for houseIndex in 0 ..< HouseCount:
    if not sim.houses[houseIndex].valid:
      continue
    var occupants = 0
    for player in sim.players:
      if player.mapIndex == HomeMapIndexBase + houseIndex:
        inc occupants
    if occupants >= 3 and occupants > dinnerCount:
      dinnerCount = occupants
      dinnerHouse = houseIndex
  if dinnerHouse >= 0:
    sim.directorDinnerHouse = dinnerHouse
    sim.directorDinnerTtl = DirectorDinnerHoldFrames
  elif sim.directorDinnerTtl > 0:
    dec sim.directorDinnerTtl
    var occupants = 0
    for player in sim.players:
      if player.mapIndex == HomeMapIndexBase + sim.directorDinnerHouse:
        inc occupants
    if occupants < 2:  # the party is over the moment the table empties
      sim.directorDinnerTtl = 0
  # A queue commitment owns the camera: the shot belongs to one
  # conversation, addressed by its encounter id, from birth to death.
  # No dwell rotation and no tour - the DirectorFocusDwellFrames
  # behavior is subsumed while committed. The focus point prefers the
  # anchored ring; before the ring anchors (members still walking into
  # place at the birth tick) the committed span's own members give a
  # centroid, so the glide-in starts the frame the queue commits
  # instead of ticks later - ticks the show may not even be stepping.
  # A briefly dispersed huddle keeps the last framing, never drops it.
  if sim.directorCommitEncounter > 0:
    var
      focusX = sim.directorFocusX
      focusY = sim.directorFocusY
      haveFocus = false
    if sim.directorCommitEncounter in sim.conversationAnchors:
      let anchor = sim.conversationAnchors[sim.directorCommitEncounter]
      focusX = anchor.x
      focusY = anchor.y
      haveFocus = true
    elif sim.convQueueCommitted and
        sim.convQueueIndex < sim.convQueue.len and
        sim.convQueue[sim.convQueueIndex].id == sim.directorCommitEncounter:
      var sumX, sumY, count = 0
      for seat in sim.convQueue[sim.convQueueIndex].members:
        for player in sim.players:
          if player.homeFlag == HomeMapIndexBase + seat and
              player.mapIndex == MainMapIndex:
            sumX += player.playerFootX()
            sumY += player.playerFootY()
            inc count
            break
      if count > 0:
        focusX = sumX div count
        focusY = sumY div count
        haveFocus = true
    if haveFocus:
      if not sim.directorFocusActive:
        sim.directorFocusActive = true
        sim.directorWideTicks = 0
        sim.directorFocusTicks = 0
        sim.startDirectorTween()
        echo "Director commit in at tick ", sim.tickCount,
          ": encounter ", sim.directorCommitEncounter
      sim.directorFocusX = focusX
      sim.directorFocusY = focusY
      sim.directorFocusRadius = ConversationRingRadius
  # Keep following the focused ring while its conversation lives; the
  # ring is anchored but replacements land nearby, so it is matched by
  # proximity.
  elif sim.directorFocusActive:
    var found = false
    for circle in sim.conversationCircles:
      if abs(circle.x - sim.directorFocusX) <= DirectorStickPx and
          abs(circle.y - sim.directorFocusY) <= DirectorStickPx:
        sim.directorFocusX = circle.x
        sim.directorFocusY = circle.y
        sim.directorFocusRadius = circle.radius
        found = true
        break
    if found:
      inc sim.directorFocusTicks
      if sim.conversationCircles.len > 1 and
          sim.directorFocusTicks >= DirectorFocusDwellFrames:
        # This ring had its turn on screen; go wide, then the next.
        found = false
    if not found:
      sim.directorFocusActive = false
      sim.directorLastFocusX = sim.directorFocusX
      sim.directorLastFocusY = sim.directorFocusY
      sim.directorHasLastFocus = true
      sim.startDirectorTween()
      echo "Director cut out at tick ", sim.tickCount
  # Only pick the next conversation once the camera has finished its
  # glide back to the wide shot and dwelt there a beat, so every cut
  # is out-then-in and neither leg ever snaps. With a conversation
  # queue attached (replay playback) the tour never picks: between
  # conversations the playhead fast-forwards in the wide shot, and
  # commitment alone brings the camera in. Live games keep the tour.
  if not sim.directorFocusActive and sim.directorCommitEncounter == 0 and
      sim.convQueue.len == 0:
    if sim.conversationCircles.len > 0 and
        sim.directorTweenLeft <= 0 and
        sim.directorCamH >= mapH * DirectorWideSnapRatio:
      inc sim.directorWideTicks
      if sim.directorWideTicks >= DirectorWideHoldTicks:
        # The rings tour in a stable order, so with several
        # conversations running the cut after a dwell is the next ring
        # along and every huddle gets its screen time.
        var order: seq[int]
        for i in 0 ..< sim.conversationCircles.len:
          order.add(i)
        order.sort(proc(a, b: int): int =
          cmp(
            (sim.conversationCircles[a].y, sim.conversationCircles[a].x),
            (sim.conversationCircles[b].y, sim.conversationCircles[b].x)
          ))
        var best = order[0]
        if sim.directorHasLastFocus:
          for pos, i in order:
            let circle = sim.conversationCircles[i]
            if abs(circle.x - sim.directorLastFocusX) <= DirectorStickPx and
                abs(circle.y - sim.directorLastFocusY) <= DirectorStickPx:
              best = order[(pos + 1) mod order.len]
              break
        else:
          for i in order:
            if sim.conversationCircles[i].radius >
                sim.conversationCircles[best].radius:
              best = i
        let circle = sim.conversationCircles[best]
        sim.directorFocusActive = true
        sim.directorFocusX = circle.x
        sim.directorFocusY = circle.y
        sim.directorFocusRadius = circle.radius
        sim.directorWideTicks = 0
        sim.directorFocusTicks = 0
        sim.startDirectorTween()
        echo "Director cut in at tick ", sim.tickCount,
          ": circle at ", circle.x, ",", circle.y
    else:
      sim.directorWideTicks = 0
  var
    targetX = 0.0
    targetY = 0.0
    targetW = mapW
    targetH = mapH
  if sim.directorFocusActive:
    targetH = clamp(
      float(sim.directorFocusRadius * 2 + DirectorPaddingPx * 2),
      float(DirectorMinCropHeight),
      mapH
    )
    targetW = targetH * mapW / mapH
    if targetW < float(DirectorMinCropWidth):
      targetW = min(float(DirectorMinCropWidth), mapW)
      targetH = targetW * mapH / mapW
    targetX = clamp(float(sim.directorFocusX) - targetW / 2, 0.0, mapW - targetW)
    targetY = clamp(float(sim.directorFocusY) - targetH / 2, 0.0, mapH - targetH)
  if sim.directorTweenLeft > 0:
    # A cut glides: the crop eases from where the glide started to the
    # target over a fixed run of frames, slow-fast-slow, and lands on
    # the target exactly when the countdown ends.
    dec sim.directorTweenLeft
    let
      t = 1.0 -
        float(sim.directorTweenLeft) / float(DirectorTweenFrames)
      eased = t * t * (3.0 - 2.0 * t)
    sim.directorCamX =
      sim.directorTweenFromX + (targetX - sim.directorTweenFromX) * eased
    sim.directorCamY =
      sim.directorTweenFromY + (targetY - sim.directorTweenFromY) * eased
    sim.directorCamW =
      sim.directorTweenFromW + (targetW - sim.directorTweenFromW) * eased
    sim.directorCamH =
      sim.directorTweenFromH + (targetH - sim.directorTweenFromH) * eased
  else:
    # At rest the camera only follows the focused ring's small drift.
    sim.directorCamX += (targetX - sim.directorCamX) * DirectorTweenRate
    sim.directorCamY += (targetY - sim.directorCamY) * DirectorTweenRate
    sim.directorCamW += (targetW - sim.directorCamW) * DirectorTweenRate
    sim.directorCamH += (targetH - sim.directorCamH) * DirectorTweenRate

proc wrapCardLines(sim: SimServer, text: string, maxWidth: int): seq[string] =
  ## Word-wraps one spoken line to a pixel width in the Tiny5 font.
  var line = ""
  for word in text.split(' '):
    let candidate =
      if line.len == 0:
        word
      else:
        line & " " & word
    if line.len == 0 or sim.chatTextWidth(candidate) <= maxWidth:
      line = candidate
    else:
      result.add(line)
      line = word
  if line.len > 0:
    result.add(line)

proc cardPortraitSprite(sim: SimServer, gnomeIndex: int): RgbaSprite =
  ## The banner portrait downscaled for one conversation card.
  if sim.portraits.len == 0:
    return newRgbaSprite(DirectorCardPortraitSize, DirectorCardPortraitSize)
  let
    source = sim.portraits[gnomeIndex mod sim.portraits.len]
    step = max(1, source.width div DirectorCardPortraitSize)
  result = newRgbaSprite(source.width div step, source.height div step)
  for y in 0 ..< result.height:
    for x in 0 ..< result.width:
      result.putPixel(x, y, source.rgbaSpriteAt(x * step, y * step))

proc directorCardSprite(
  sim: SimServer,
  player: Player,
  spokenLine: string,
  relation: string,
  connections: int,
  portrait: RgbaSprite
): RgbaSprite =
  ## One conversation card for the director cut, framed like the chat
  ## banner: the speaker's name beside their full spoken line, then a
  ## ruled footer with their points, connections, and the relation to
  ## their listener. The face is a separate object over the reserved
  ## left area, so it can hop when the line is new. The line comes
  ## from the delay-chat feed, which trails the sim: the card shows
  ## the line being spoken, not whatever the gnome said last.
  let
    nameInk = rgba(94, 58, 22, 255)
    textInk = rgba(ChatBannerInkR, ChatBannerInkG, ChatBannerInkB, 255)
    relationInk = rgba(158, 116, 66, 255)
    ruleInk = rgba(178, 138, 90, 255)
    pad = DirectorCardInnerPad
    textX = pad + portrait.width + 4
    textWidth = DirectorCardWidth - textX - pad
    lines = sim.wrapCardLines(spokenLine, textWidth)
    lineHeight = sim.textFont.height + 1
    bodyHeight = max(portrait.height, (lines.len + 1) * lineHeight + 2)
    relationHeight =
      if relation.len > 0:
        lineHeight + 1
      else:
        0
    footerHeight = 5 + lineHeight + relationHeight
    height = bodyHeight + footerHeight + pad * 2
    pointsText = "Points: " & $player.score
    connectionsText = "Connections: " & $connections
    ruleY = pad + bodyHeight + 2
    statsY = ruleY + 3
  if sim.chatBanner.width > 0:
    result = sim.chatBanner.nineSliceSprite(
      DirectorCardWidth, height, DirectorCardSliceInset
    )
  else:
    result = newRgbaSprite(DirectorCardWidth, height)
    result.fillRect(0, 0, DirectorCardWidth, height, rgba(233, 213, 170, 245))
  sim.blitTinyText(result, player.playerName, textX, pad, nameInk)
  for i, line in lines:
    sim.blitTinyText(
      result,
      line,
      textX,
      pad + (i + 1) * lineHeight + 2,
      textInk
    )
  result.fillRect(pad, ruleY, DirectorCardWidth - pad * 2, 1, ruleInk)
  sim.blitTinyText(result, pointsText, pad, statsY, textInk)
  sim.blitTinyText(
    result,
    connectionsText,
    DirectorCardWidth - pad - sim.chatTextWidth(connectionsText),
    statsY,
    textInk
  )
  if relation.len > 0:
    sim.blitTinyText(result, relation, pad, statsY + lineHeight + 1, relationInk)

proc addDirectorConversationCards(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  cropX, cropY, cropW, cropH, paddedWidth, forestPad: int
) =
  ## Draws the parchment card for the line now being spoken, in the
  ## margin beside the map crop: left of the shot's center on the
  ## left, otherwise on the right. The card lives exactly as long as
  ## its line does - it appears when the line's voice starts (or when
  ## the delay-chat cursor reaches it, for muted viewers) and leaves
  ## when the line finishes, so voices and cards can never drift
  ## apart. Only the framed circle's own gnomes get a card, so a
  ## zoomed conversation shows its own voices and no other huddle's.
  if not sim.directorCardLive:
    return
  if sim.chatFeedIndex < 0 or sim.chatFeedIndex >= sim.chatFeed.len:
    return
  let
    item = sim.chatFeed[sim.chatFeedIndex]
    viewHeight = cropH
    worldCenterX = cropX + cropW div 2
    reach = sim.directorFocusRadius + ConversationExitRadius div 2 +
      GnomeSpriteSize div 2
  # The framed circle's members: the card only shows for one of them,
  # and the relation footer reads against the same group.
  var
    speakers: seq[int]
    speaker = -1
  for i, player in sim.players:
    if player.mapIndex != MainMapIndex:
      continue
    let
      dx = player.playerFootX() - sim.directorFocusX
      dy = player.playerFootY() - sim.directorFocusY
    if dx * dx + dy * dy > reach * reach:
      continue
    speakers.add(i)
    if player.playerName == item.speaker.name:
      speaker = i
  if speaker < 0:
    # The line on air belongs to another huddle; this cut stays quiet.
    return
  let speakingPlayer = sim.players[speaker]
  if speakingPlayer.x + GnomeSpriteSize <= cropX or
      speakingPlayer.x >= cropX + cropW or
      speakingPlayer.y + GnomeSpriteSize <= cropY or
      speakingPlayer.y >= cropY + cropH:
    return
  # The heart ledger: pair strengths keyed by house seat, folded from
  # the conversation records in a replay or the live encounter book.
  let heartPairs =
    if sim.conversationTimeline.events.len > 0:
      sim.conversationTimeline.heartLinksAt(sim.tickCount)
    else:
      sim.heartLinks
  proc houseOf(i: int): int =
    sim.players[i].homeFlag - HomeMapIndexBase
  proc connectionPoints(i: int): int =
    ## The speaker's connection points: turns spent together, summed
    ## across every partner.
    let house = houseOf(i)
    for pair in heartPairs:
      if pair.a == house or pair.b == house:
        result += pair.links
  proc relationLabel(i: int): string =
    ## The tier toward the nearest other speaker, from the pair's
    ## strength in the ledger.
    var
      other = -1
      best = high(int)
    for j in speakers:
      if j == i:
        continue
      let
        dx = sim.players[j].x - sim.players[i].x
        dy = sim.players[j].y - sim.players[i].y
        dist = dx * dx + dy * dy
      if dist < best:
        best = dist
        other = j
    if other < 0:
      return ""
    let
      myHouse = houseOf(i)
      otherHouse = houseOf(other)
    var links = 0
    for pair in heartPairs:
      if (pair.a == myHouse and pair.b == otherHouse) or
          (pair.a == otherHouse and pair.b == myHouse):
        links = pair.links
        break
    const moods = ["neutral with ", "friend with ", "best friend with "]
    moods[heartLinkTier(links)] & sim.players[other].playerName
  let
    onLeft = speakingPlayer.x < worldCenterX
    columnX =
      if onLeft:
        forestPad + 4
      else:
        paddedWidth - forestPad - DirectorCardWidth - 4
    # The score panel overlays the window's top left, so a card on
    # the left starts below it.
    topInset =
      if onLeft:
        viewHeight div 4
      else:
        8
    relation = relationLabel(speaker)
    face = sim.cardPortraitSprite(speakingPlayer.gnomeIndex)
    sprite = sim.directorCardSprite(
      speakingPlayer, item.message, relation, connectionPoints(speaker), face
    )
    # The delay-chat banner overlays the window's bottom edge; keep
    # the card clear of it.
    bottomLimit = viewHeight - viewHeight div 6
  var y = max(topInset, (viewHeight - sprite.height) div 2)
  if y + sprite.height > bottomLimit:
    y = max(topInset, bottomLimit - sprite.height)
  packet.addRgbaSpriteCached(
    cache,
    DirectorCardSpriteBase + speaker,
    sprite,
    "director card " & $speaker & " " & $speakingPlayer.score & " " &
      $connectionPoints(speaker) & " " & relation & " " & item.message
  )
  packet.addObject(
    DirectorCardObjectBase + speaker,
    columnX,
    y,
    DirectorCardZ,
    MapLayerId,
    DirectorCardSpriteBase + speaker
  )
  # The face rides over the card as its own object so it can hop
  # while the card is fresh on screen.
  var hop = 0
  let hopIndex = int((epochTime() - sim.chatFeedShownAt) * 24.0)
  if hopIndex >= 0 and hopIndex < DirectorBounceHops.len:
    hop = DirectorBounceHops[hopIndex]
  packet.addRgbaSpriteCached(
    cache,
    DirectorCardFaceSpriteBase + speakingPlayer.gnomeIndex,
    face,
    "director card face " & $speakingPlayer.gnomeIndex
  )
  packet.addObject(
    DirectorCardFaceObjectBase + speaker,
    columnX + DirectorCardInnerPad,
    y + DirectorCardInnerPad - hop,
    DirectorCardZ + 1,
    MapLayerId,
    DirectorCardFaceSpriteBase + speakingPlayer.gnomeIndex
  )

proc addDirectorWorldView(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry]
) =
  ## Appends the main map cropped to the director camera. The browser
  ## client scales the declared viewport to fit its window, so a
  ## shrinking crop plays as a zoom. The viewport is wider than the
  ## crop by a margin on each side, where the conversation cards live.
  let
    tintIndex = sim.dayTintIndex()
    cameraY = int(sim.directorCamY)
    viewW = max(1, int(sim.directorCamW))
    viewH = max(1, int(sim.directorCamH))
    # Forest-only padding widens tall shots toward the target frame
    # shape; the cards keep hugging the map crop.
    forestPad = clamp(
      (viewH * DirectorForestAspectNum div DirectorForestAspectDen -
        viewW - DirectorCardMarginPx * 2) div 2,
      0,
      DirectorForestPadMax
    )
    cameraX = int(sim.directorCamX) - DirectorCardMarginPx - forestPad
    paddedW = viewW + (DirectorCardMarginPx + forestPad) * 2
  packet.addViewport(MapLayerId, paddedW, viewH)
  if sim.mainMap.forestSprite.width > 0:
    # The generated forest border sits behind the map, filling the
    # card margins and any camera slack, so the village reads as a
    # clearing in a larger forest instead of floating on black. It
    # shares BottomZ; its smaller y draws it before the map bottom.
    packet.addObject(
      ForestObjectId,
      -cameraX - ForestMarginPx,
      -cameraY - ForestMarginPx,
      BottomZ,
      MapLayerId,
      forestSpriteId(tintIndex)
    )
  packet.addObject(
    BottomObjectId,
    -cameraX,
    -cameraY,
    BottomZ,
    MapLayerId,
    mainBottomSpriteId(tintIndex)
  )
  packet.addGardenObjects(sim, cameraX, cameraY, paddedW, viewH)
  packet.addTrailObjects(sim, cache, cameraX, cameraY)
  packet.addPlayerObjects(
    sim,
    cache,
    MainMapIndex,
    cameraX,
    cameraY,
    paddedW,
    viewH,
    includeBubbles = false
  )
  packet.addHouseGnomeObjects(sim, cache, cameraX, cameraY)
  packet.addObject(
    OverhangObjectId,
    -cameraX,
    -cameraY,
    OverhangZ,
    MapLayerId,
    mainOverhangSpriteId(tintIndex)
  )
  # A talking dinner party pulls up its house interior, but only from
  # the wide shot: an outdoor conversation keeps the camera.
  if sim.directorDinnerTtl > 0 and not sim.directorFocusActive and
      sim.directorTweenLeft <= 0 and
      sim.directorCamH >= float(sim.mainMap.height) * DirectorWideSnapRatio:
    packet.addHouseInsetView(
      sim,
      cache,
      sim.directorDinnerHouse,
      offsetX = DirectorCardMarginPx + forestPad
    )
  # Cards belong to the cut: they appear only once the camera has
  # finished its glide in on a conversation, and frame that circle's
  # speakers.
  if sim.directorFocusActive and sim.directorTweenLeft <= 0 and
      sim.directorCamH < float(sim.mainMap.height) * DirectorWideSnapRatio:
    packet.addDirectorConversationCards(
      sim,
      cache,
      int(sim.directorCamX),
      cameraY,
      viewW,
      viewH,
      paddedW,
      forestPad
    )
  packet.addClockObjects(sim)

proc replayCommandAt(layer, x, y: int): char =
  ## Returns the replay transport command under a UI coordinate. The
  ## transport buttons and speed labels share one row on the center bar.
  if layer != ReplayCenterBottomLayerId:
    return '\0'
  let localY = y - ChatBannerAreaHeight - TransportRowY
  if localY < 0 or localY >= TransportRowHeight:
    return '\0'
  let buttonX = x - TransportButtonsX
  if buttonX >= 0 and
      buttonX < TransportButtonCount * TransportButtonStride:
    let index = buttonX div TransportButtonStride
    if buttonX - index * TransportButtonStride >= TransportButtonWidth:
      return '\0'
    case index
    of 0: return '<'
    of 1: return 'N'  # prev conversation
    of 2: return ' '
    of 3: return 'n'  # next conversation
    of 4: return 'e'
    else: return 'r'
  let speedX = x - SpeedRowX
  if speedX >= 0 and
      speedX < TransportSpeedCommands.len * TransportSpeedStride:
    let index = speedX div TransportSpeedStride
    if speedX - index * TransportSpeedStride >= TransportSpeedWidth:
      return '\0'
    return TransportSpeedCommands[index]
  '\0'

const ReplayControlsBg = ColorRGBA(r: 0, g: 0, b: 0, a: ReplayControlsBgAlpha)

proc replayScrubTickAt(
  layer, x, y, maxTick: int,
  requireInside = true
): int =
  ## Returns the replay tick under the scrubber pointer.
  if layer != ReplayCenterBottomLayerId or maxTick < 0:
    return -1
  let
    scrubberX = max(0, (ViewportWidth - ReplayScrubberWidth) div 2)
    localX = x - scrubberX
    localY = y - ChatBannerAreaHeight - ReplayScrubberY
  if requireInside and (
      localX < 0 or localX >= ReplayScrubberWidth or
      localY < 0 or localY >= ReplayScrubberHeight
    ):
    return -1
  if ReplayScrubberWidth <= 1:
    return 0
  let clampedX = clamp(localX, 0, ReplayScrubberWidth - 1)
  clamp((clampedX * maxTick) div (ReplayScrubberWidth - 1), 0, maxTick)

proc buildReplayScrubberSprite(tick, maxTick, dayTicks: int): RgbaSprite =
  ## Builds the compact replay scrubber sprite with dinner-time pips.
  result = newRgbaSprite(ReplayScrubberWidth, ReplayScrubberHeight)
  let
    track = rgba(178, 138, 90, 255)
    knob = rgba(94, 58, 22, 255)
    knobEdge = rgba(140, 100, 60, 255)
    pip = rgba(205, 118, 32, 255)
    knobX =
      if maxTick > 0:
        clamp(
          (tick * (ReplayScrubberWidth - 1)) div maxTick,
          0,
          ReplayScrubberWidth - 1
        )
      else:
        0
  for x in 0 ..< ReplayScrubberWidth:
    result.putPixel(x, ReplayScrubberTrackY, track)
  if maxTick > 0 and dayTicks > 0:
    let dinnerOffset =
      dayTicks * (DinnerMinutes - DayStartMinutes) div DayTotalMinutes
    var dinnerTick = dinnerOffset
    while dinnerTick <= maxTick:
      let x = clamp(
        (dinnerTick * (ReplayScrubberWidth - 1)) div maxTick,
        0,
        ReplayScrubberWidth - 1
      )
      for y in 0 ..< ReplayScrubberHeight:
        result.putPixel(x, y, pip)
      dinnerTick += dayTicks
  for x in 0 .. knobX:
    result.putPixel(x, ReplayScrubberTrackY, knob)
  for y in 0 ..< ReplayScrubberHeight:
    result.putPixel(knobX, y, knob)
  if knobX > 0:
    result.putPixel(knobX - 1, ReplayScrubberTrackY, knobEdge)
  if knobX < ReplayScrubberWidth - 1:
    result.putPixel(knobX + 1, ReplayScrubberTrackY, knobEdge)

proc buildReplayControlsSprite(
  sim: SimServer,
  playing: bool,
  looping: bool,
  speedIndex: int
): RgbaSprite =
  ## Builds the one-row transport buttons and speed labels sprite.
  result = newRgbaSprite(ViewportWidth, TransportRowHeight)
  let
    bright = rgba(94, 58, 22, 255)
    dim = rgba(178, 138, 90, 255)
    buttons = [
      "<<",
      "[<",
      if playing: "||" else: "|>",
      ">]",
      ">|",
      "R"
    ]
  for i, label in buttons:
    let color =
      if i == 5:
        if looping: bright else: dim
      elif i == 1 or i == 3:
        # Prev/next conversation: greyed out on a day whose replay
        # holds no conversations to queue.
        if sim.convQueue.len > 0: bright else: dim
      else:
        bright
    sim.blitTinyText(
      result,
      label,
      TransportButtonsX + i * TransportButtonStride,
      0,
      color
    )
  for i, label in TransportSpeedLabels:
    let color =
      if i == speedIndex:
        bright
      else:
        dim
    sim.blitTinyText(
      result,
      label,
      SpeedRowX + i * TransportSpeedStride,
      0,
      color
    )

proc addReplayControlLayers(packet: var seq[uint8]) =
  ## Adds the fixed UI layer shared by the delay chat banner and the
  ## replay timing controls.
  packet.addLayer(
    ReplayCenterBottomLayerId,
    ReplayCenterBottomLayerKind,
    UiLayerFlags
  )
  packet.addViewport(
    ReplayCenterBottomLayerId,
    ViewportWidth,
    ReplayBarTotalHeight
  )

proc addReplayMismatchWarning(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  tick: int
) =
  ## Adds a fixed top-center replay hash mismatch warning.
  if tick < 0:
    return
  let
    label = "HASH MISMATCH AT TICK " & $tick
    textWidth = sim.textFont.textWidth(label)
  var warning = newRgbaSprite(
    textWidth + ReplayMismatchPadX * 2,
    sim.textFont.height + ReplayMismatchPadY * 2
  )
  warning.fillRect(
    0,
    0,
    warning.width,
    warning.height,
    rgba(220, 20, 20, 255)
  )
  sim.blitTinyText(
    warning,
    label,
    ReplayMismatchPadX,
    ReplayMismatchPadY,
    rgba(255, 255, 255, 255)
  )
  packet.addLayer(
    ReplayMismatchLayerId,
    ReplayMismatchLayerKind,
    UiLayerFlags
  )
  packet.addViewport(ReplayMismatchLayerId, warning.width, warning.height)
  packet.addRgbaSpriteCached(
    cache,
    ReplayMismatchSpriteId,
    warning,
    "replay mismatch " & $tick
  )
  packet.addObject(
    ReplayMismatchObjectId,
    0,
    0,
    0,
    ReplayMismatchLayerId,
    ReplayMismatchSpriteId
  )

proc addReplayControls(
  packet: var seq[uint8],
  sim: SimServer,
  cache: var seq[SpriteCacheEntry],
  replayTick,
  replaySpeedIndex,
  replayMaxTick: int,
  playing,
  looping: bool,
  mismatchTick = -1
) =
  ## Adds the replay timing controls for one replay viewer frame. The
  ## controls live on the same parchment nine-slice card as the
  ## conversation cards and the score panel.
  packet.addReplayControlLayers()
  var panelBg: RgbaSprite
  if sim.chatBanner.width > 0:
    panelBg = sim.chatBanner.nineSliceSprite(
      ViewportWidth, ReplayPanelHeight, DirectorCardSliceInset
    )
  else:
    panelBg = newRgbaSprite(ViewportWidth, ReplayPanelHeight)
    panelBg.fillRect(0, 0, panelBg.width, panelBg.height, ReplayControlsBg)
  packet.addRgbaSpriteCached(
    cache,
    ReplayPanelBgSpriteId,
    panelBg,
    "replay panel card"
  )
  packet.addObject(
    ReplayPanelBgObjectId,
    0,
    ChatBannerAreaHeight,
    -1,
    ReplayCenterBottomLayerId,
    ReplayPanelBgSpriteId
  )
  let
    controlTick = max(0, replayTick)
    controlMaxTick = max(controlTick, replayMaxTick)
    tickText = sim.globalPanelTextSprite(
      "TICK " & $controlTick,
      rgba(GlobalPanelTextR, GlobalPanelTextG, GlobalPanelTextB, 255)
    )
    scrubber = buildReplayScrubberSprite(
      controlTick,
      controlMaxTick,
      sim.dayTicks
    )
    controls = sim.buildReplayControlsSprite(playing, looping, replaySpeedIndex)
  packet.addRgbaSpriteCached(
    cache,
    ReplayTickSpriteId,
    tickText,
    "replay tick " & $controlTick
  )
  packet.addObject(
    ReplayTickObjectId,
    # Centered in the clear run between the transport buttons and the
    # speed labels, where the counter can never touch either.
    TransportButtonsEndX + max(0,
      (SpeedRowX - TransportButtonsEndX - tickText.width) div 2),
    ChatBannerAreaHeight + ReplayTickTextY,
    0,
    ReplayCenterBottomLayerId,
    ReplayTickSpriteId
  )
  if sim.convQueue.len > 0:
    # The queue position label, under the tick counter: the cursor in
    # the birth-ordered conversation list.
    let
      convText = sim.globalPanelTextSprite(
        "CONV " & $min(sim.convQueueIndex + 1, sim.convQueue.len) &
          "/" & $sim.convQueue.len,
        rgba(GlobalPanelTextR, GlobalPanelTextG, GlobalPanelTextB, 255)
      )
    packet.addRgbaSpriteCached(
      cache,
      ReplayConvSpriteId,
      convText,
      "replay conv position"
    )
    packet.addObject(
      ReplayConvObjectId,
      TransportButtonsEndX + max(0,
        (SpeedRowX - TransportButtonsEndX - convText.width) div 2),
      ChatBannerAreaHeight + ReplayConvTextY,
      0,
      ReplayCenterBottomLayerId,
      ReplayConvSpriteId
    )
  packet.addRgbaSpriteCached(
    cache,
    ReplayScrubberSpriteId,
    scrubber,
    "replay scrubber"
  )
  packet.addObject(
    ReplayScrubberObjectId,
    max(0, (ViewportWidth - ReplayScrubberWidth) div 2),
    ChatBannerAreaHeight + ReplayScrubberY,
    0,
    ReplayCenterBottomLayerId,
    ReplayScrubberSpriteId
  )
  packet.addRgbaSpriteCached(
    cache,
    ReplayControlsSpriteId,
    controls,
    "replay controls"
  )
  packet.addObject(
    ReplayControlsObjectId,
    0,
    ChatBannerAreaHeight + TransportRowY,
    0,
    ReplayCenterBottomLayerId,
    ReplayControlsSpriteId
  )
  packet.addReplayMismatchWarning(sim, cache, mismatchTick)

proc flippedHorizontal(sprite: RgbaSprite): RgbaSprite =
  ## Returns one horizontally mirrored sprite.
  result = newRgbaSprite(sprite.width, sprite.height)
  for y in 0 ..< sprite.height:
    for x in 0 ..< sprite.width:
      result.putPixel(sprite.width - 1 - x, y, sprite.rgbaSpriteAt(x, y))

proc bannerPortrait(sim: SimServer, gnomeIndex: int): RgbaSprite =
  ## Returns the profile portrait for one gnome index.
  if sim.portraits.len == 0:
    return newRgbaSprite(0, 0)
  sim.portraits[gnomeIndex mod sim.portraits.len]

proc bannerMessageLines(
  sim: SimServer,
  text: string,
  maxWidth: int
): seq[string] =
  ## Greedily wraps banner text into pixel-width limited lines.
  var line = ""
  for word in text.splitWhitespace():
    let candidate =
      if line.len == 0:
        word
      else:
        line & " " & word
    if line.len > 0 and sim.chatTextWidth(candidate) > maxWidth:
      result.add(line)
      line = word
    else:
      line = candidate
  if line.len > 0:
    result.add(line)

proc layoutBannerHearers(
  sim: SimServer,
  item: ChatFeedItem,
  bannerWidth: int
): seq[ChatBannerHearer] =
  ## Packs up to three hearers from the right, spaced by names.
  var nameRight = bannerWidth - ChatBannerPortraitMargin
  for h in 0 ..< min(item.hearers.len, ChatBannerMaxHearers):
    let
      person = item.hearers[h]
      portrait = sim.bannerPortrait(person.gnomeIndex)
      nameWidth = sim.chatTextWidth(person.name)
    if portrait.width == 0 or nameWidth == 0:
      continue
    let
      nameX = nameRight - nameWidth
      portraitX = nameX + nameWidth div 2 - portrait.width div 2
    result.add(ChatBannerHearer(
      gnomeIndex: person.gnomeIndex,
      name: person.name,
      portraitX: portraitX,
      nameX: nameX
    ))
    nameRight = nameX - ChatBannerNameGap

proc glyphHasInk(glyph: PixelGlyph): bool =
  ## Returns true when a glyph draws at least one foreground pixel.
  for pixel in glyph.pixels:
    if pixel:
      return true

proc addBannerGlyphs(
  packet: var seq[uint8],
  sim: SimServer,
  text: string,
  x, y: int,
  glyphSlot: var int
) =
  ## Places one banner text run as individual glyph objects.
  var dx = x
  for ch in text:
    if glyphSlot >= ChatBannerMaxGlyphs:
      return
    let glyph = sim.textFont.glyphAt(ch)
    if glyphHasInk(glyph):
      packet.addObject(
        ChatBannerGlyphObjectBase + glyphSlot,
        dx,
        y,
        ChatBannerGlyphZ,
        ReplayCenterBottomLayerId,
        ch.bannerGlyphSpriteId()
      )
      inc glyphSlot
    dx += sim.textFont.glyphAdvance(ch)

proc chatFeedNowPlaying*(
  sim: SimServer
): tuple[index, gnomeIndex, messageLen: int] =
  ## The chat line the banner shows right now, for viewer sound hooks.
  ## Index is -1 when no line shows; a change in the tuple means a new
  ## line started.
  if sim.chatFeedIndex < 0 or sim.chatFeedIndex >= sim.chatFeed.len:
    return (-1, -1, 0)
  let item = sim.chatFeed[sim.chatFeedIndex]
  (sim.chatFeedIndex, item.speaker.gnomeIndex, item.message.len)

proc chatFeedNowText*(sim: SimServer): string =
  ## The text of the banner's current chat line, for viewer speech.
  if sim.chatFeedIndex < 0 or sim.chatFeedIndex >= sim.chatFeed.len:
    return ""
  sim.chatFeed[sim.chatFeedIndex].message

proc addChatBanner(
  packet: var seq[uint8],
  sim: SimServer,
  declareLayer: bool
) =
  ## Appends the paced delay-chat banner at the top of the center bar.
  ## Background, portraits, and glyphs are init-packet sprites; this
  ## only places objects. The replay controls declare the shared layer;
  ## standalone callers declare it here instead.
  if sim.chatFeedIndex < 0 or sim.chatFeedIndex >= sim.chatFeed.len:
    return
  if sim.chatBanner.width == 0:
    return
  let
    item = sim.chatFeed[sim.chatFeedIndex]
    banner = sim.chatBanner
    originX = max(0, (ViewportWidth - banner.width) div 2)
    speakerPortrait = sim.bannerPortrait(item.speaker.gnomeIndex)
    hearers = sim.layoutBannerHearers(item, banner.width)
    nameY = banner.height - sim.textFont.height - 2
  if declareLayer:
    packet.addLayer(
      ReplayCenterBottomLayerId,
      ReplayCenterBottomLayerKind,
      UiLayerFlags
    )
    packet.addViewport(
      ReplayCenterBottomLayerId,
      ViewportWidth,
      ChatBannerAreaHeight
    )
  packet.addObject(
    ChatBannerObjectId,
    originX,
    0,
    ChatBannerBgZ,
    ReplayCenterBottomLayerId,
    ChatBannerSpriteId
  )
  if speakerPortrait.width > 0:
    packet.addObject(
      ChatBannerPortraitObjectBase,
      originX + ChatBannerPortraitMargin,
      ChatBannerPortraitY,
      ChatBannerPortraitZ,
      ReplayCenterBottomLayerId,
      portraitSpriteId(item.speaker.gnomeIndex, true)
    )
  for h, hearer in hearers:
    packet.addObject(
      ChatBannerPortraitObjectBase + 1 + h,
      originX + hearer.portraitX,
      ChatBannerPortraitY,
      ChatBannerPortraitZ,
      ReplayCenterBottomLayerId,
      portraitSpriteId(hearer.gnomeIndex, false)
    )
  var glyphSlot = 0
  packet.addBannerGlyphs(
    sim,
    item.speaker.name,
    originX + ChatBannerPortraitMargin +
      speakerPortrait.width div 2 -
      sim.chatTextWidth(item.speaker.name) div 2,
    nameY,
    glyphSlot
  )
  for hearer in hearers:
    packet.addBannerGlyphs(
      sim,
      hearer.name,
      originX + hearer.nameX,
      nameY,
      glyphSlot
    )
  var huddleLeft = banner.width - ChatBannerPortraitMargin
  for hearer in hearers:
    huddleLeft = min(huddleLeft, hearer.portraitX)
    huddleLeft = min(huddleLeft, hearer.nameX)
  let
    textLeft =
      ChatBannerPortraitMargin + speakerPortrait.width +
        ChatBannerTextGap
    maxWidth = max(20, huddleLeft - ChatBannerTextGap - textLeft)
    lines = sim.bannerMessageLines(item.message, maxWidth)
    lineHeight = sim.textFont.height + 1
    blockTop = max(
      ChatBannerPortraitY,
      (banner.height - 8 - lines.len * lineHeight) div 2
    )
  for i, line in lines:
    packet.addBannerGlyphs(
      sim,
      line,
      originX + textLeft +
        (maxWidth - sim.chatTextWidth(line)) div 2,
      blockTop + i * lineHeight,
      glyphSlot
    )

proc buildGlobalPacket*(
  sim: SimServer,
  state: PlayerViewerState,
  nextState: var PlayerViewerState,
  replayControls = false,
  replayTick = -1,
  replaySpeedIndex = DefaultSpeedIndex,
  replayMaxTick = -1,
  replayPlaying = false,
  replayLooping = false,
  replayMismatchTick = -1
): seq[uint8] =
  ## Builds one sprite protocol packet for a global viewer.
  nextState =
    if state == nil:
      PlayerViewerState(selectedPlayerIndex: -1)
    else:
      state
  if not nextState.initialized:
    result.add(sim.playerInitPacket)
    nextState.initialized = true

  result.addClearObjects()
  if nextState.directorMode:
    # The director cut ignores clicks and selection: the automated
    # camera picks the shot for everyone watching.
    nextState.pendingMapClick = false
    nextState.selectedPlayerIndex = -1
    result.addDirectorWorldView(sim, nextState.spriteCache)
    result.addGlobalScorePanel(sim, nextState.spriteCache, -1)
    if replayControls:
      result.addReplayControls(
        sim,
        nextState.spriteCache,
        replayTick,
        replaySpeedIndex,
        replayMaxTick,
        replayPlaying,
        replayLooping,
        replayMismatchTick
      )
    # No delay-chat banner: the conversation cards carry the lines.
    return
  if nextState.pendingMapClick:
    nextState.pendingMapClick = false
    let
      clickX = nextState.pendingMapClickX
      clickY = nextState.pendingMapClickY
    if nextState.selectedPlayerIndex >= 0:
      nextState.selectedPlayerIndex = -1
    elif nextState.selectedHouseNumber > 0 and
        nextState.selectedHouseNumber <= HouseCount:
      let
        homeMap = sim.homeMaps[nextState.selectedHouseNumber - 1]
        inset = Rect(
          x: max(0, (sim.mainMap.width - homeMap.width) div 2),
          y: max(0, (sim.mainMap.height - homeMap.height) div 2),
          w: homeMap.width,
          h: homeMap.height
        )
      if not inset.contains(clickX, clickY):
        nextState.selectedHouseNumber = 0
    else:
      for i, house in sim.houses:
        if house.valid and house.rect.contains(clickX, clickY):
          nextState.selectedHouseNumber = i + 1
          break
  let selectedIndex = nextState.selectedGlobalPlayerIndex(sim)
  nextState.selectedPlayerIndex = selectedIndex
  if selectedIndex >= 0:
    result.addViewport(MapLayerId, ViewportWidth, ViewportHeight)
    discard result.addPlayerView(
      sim,
      selectedIndex,
      nextState.spriteCache,
      highlight = true
    )
  else:
    result.addGlobalWorldView(sim, nextState.spriteCache)
    if nextState.selectedHouseNumber > 0 and
        nextState.selectedHouseNumber <= HouseCount:
      result.addHouseInsetView(
        sim,
        nextState.spriteCache,
        nextState.selectedHouseNumber - 1
      )
  result.addGlobalScorePanel(sim, nextState.spriteCache, selectedIndex)
  if replayControls:
    result.addReplayControls(
      sim,
      nextState.spriteCache,
      replayTick,
      replaySpeedIndex,
      replayMaxTick,
      replayPlaying,
      replayLooping,
      replayMismatchTick
    )
  result.addChatBanner(sim, declareLayer = not replayControls)

proc updateDirection(player: var Player, input: InputState) =
  ## Updates the player's facing direction from held input.
  let
    x =
      if input.left:
        -1
      elif input.right:
        1
      else:
        0
    y =
      if input.up:
        -1
      elif input.down:
        1
      else:
        0
  if abs(x) > abs(y):
    player.direction =
      if x < 0:
        DirLeft
      else:
        DirRight
  elif y != 0:
    player.direction =
      if y < 0:
        DirUp
      else:
        DirDown

proc applyInput(sim: SimServer, playerIndex: int, input: InputState) =
  ## Applies one player's held movement input.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  var
    inputX = 0
    inputY = 0
  if input.left:
    dec inputX
  if input.right:
    inc inputX
  if input.up:
    dec inputY
  if input.down:
    inc inputY

  sim.players[playerIndex].updateDirection(input)
  let player = sim.players[playerIndex]
  player.inputX = inputX
  player.inputY = inputY
  if inputX != 0:
    player.velX = clamp(
      player.velX + inputX * Accel,
      -MaxSpeed,
      MaxSpeed
    )
  else:
    player.velX = (player.velX * FrictionNum) div FrictionDen
    if abs(player.velX) < StopThreshold:
      player.velX = 0
  if inputY != 0:
    player.velY = clamp(
      player.velY + inputY * Accel,
      -MaxSpeed,
      MaxSpeed
    )
  else:
    player.velY = (player.velY * FrictionNum) div FrictionDen
    if abs(player.velY) < StopThreshold:
      player.velY = 0

proc signum(value: int): int =
  ## Returns the sign of one integer as -1, 0, or 1.
  if value < 0:
    return -1
  if value > 0:
    return 1
  return 0

proc slideScanRadius(carry, velocity: int): int =
  ## Returns the perpendicular scan radius for blocked movement.
  let
    pending = abs(carry) div MotionScale
    speed = (abs(velocity) + MotionScale - 1) div MotionScale
  return clamp(max(1, max(pending, speed)), 1, MovementSlideMaxScan)

proc canSlideHorizontal(world: WorldMap, x, y, step, offset: int): bool =
  ## Returns true when a horizontal step can slide by one offset.
  if offset == 0:
    return false
  let slideStep = offset.signum()
  for i in 1 .. abs(offset):
    if not world.canOccupy(x, y + slideStep * i):
      return false
  return world.canOccupy(x + step, y + offset)

proc canSlideVertical(world: WorldMap, x, y, step, offset: int): bool =
  ## Returns true when a vertical step can slide by one offset.
  if offset == 0:
    return false
  let slideStep = offset.signum()
  for i in 1 .. abs(offset):
    if not world.canOccupy(x + slideStep * i, y):
      return false
  return world.canOccupy(x + offset, y + step)

proc trySlideOffset(
  world: WorldMap,
  player: Player,
  step,
  offset: int,
  horizontal: bool
): bool =
  ## Tries one candidate slide offset for a blocked movement step.
  if horizontal:
    if not world.canSlideHorizontal(player.x, player.y, step, offset):
      return false
    player.x += step
    player.y += offset
  else:
    if not world.canSlideVertical(player.x, player.y, step, offset):
      return false
    player.x += offset
    player.y += step
  return true

proc trySlideMove(
  world: WorldMap,
  player: Player,
  step,
  radius,
  preferredSlide: int,
  horizontal: bool
): bool =
  ## Tries nearby slide offsets for one blocked movement step.
  if radius <= 0:
    return false
  let preferred = preferredSlide.signum()
  for distance in 1 .. radius:
    if preferred != 0:
      if world.trySlideOffset(player, step, preferred * distance, horizontal):
        return true
      if world.trySlideOffset(player, step, -preferred * distance, horizontal):
        return true
    else:
      if world.trySlideOffset(player, step, -distance, horizontal):
        return true
      if world.trySlideOffset(player, step, distance, horizontal):
        return true

proc applyMomentumAxis(
  world: WorldMap,
  player: Player,
  carry: var int,
  velocity,
  preferredSlide: int,
  horizontal: bool
) =
  ## Applies one fixed-point movement axis with collision sliding.
  carry += velocity
  while abs(carry) >= MotionScale:
    let step =
      if carry < 0:
        -1
      else:
        1
    let
      nx =
        if horizontal:
          player.x + step
        else:
          player.x
      ny =
        if horizontal:
          player.y
        else:
          player.y + step
    if world.canOccupy(nx, ny):
      if horizontal:
        player.x = nx
      else:
        player.y = ny
      carry -= step * MotionScale
    else:
      let radius = slideScanRadius(carry, velocity)
      if world.trySlideMove(player, step, radius, preferredSlide, horizontal):
        carry -= step * MotionScale
      else:
        carry = 0
        break

proc moveAxis(sim: SimServer, player: Player, horizontal: bool) =
  ## Moves one player along one axis with crewrift-style sliding.
  let world = sim.mapFor(player.mapIndex)
  if horizontal:
    let preferredSlide =
      if player.inputY != 0:
        player.inputY
      else:
        player.velY.signum()
    world.applyMomentumAxis(
      player,
      player.carryX,
      player.velX,
      preferredSlide,
      true
    )
  else:
    let preferredSlide =
      if player.inputX != 0:
        player.inputX
      else:
        player.velX.signum()
    world.applyMomentumAxis(
      player,
      player.carryY,
      player.velY,
      preferredSlide,
      false
    )

proc updateMessages(sim: SimServer) =
  ## Clears transient player panels when their lifetime expires.
  for player in sim.players.mitems:
    if player.dinnerTicks > 0:
      dec player.dinnerTicks
      if player.dinnerTicks <= 0:
        player.dinnerRecord = nil
    if player.messageTicks <= 0:
      if player.message.len > 0:
        player.message = ""
      continue
    dec player.messageTicks
    if player.messageTicks <= 0:
      player.message = ""

proc teleportPlayerToOwnHome(sim: SimServer, playerIndex: int) =
  ## Teleports one player to their assigned home map.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  let
    mapIndex = sim.players[playerIndex].homeFlag
    spawn = sim.findHomeSpawn(mapIndex)
  sim.teleportPlayer(
    playerIndex,
    mapIndex,
    spawn.x,
    spawn.y,
    DirDown
  )

proc clearInventory(player: Player) =
  ## Clears one player inventory.
  player.inventory.clearFoods()

proc homeHostIndex(sim: SimServer, mapIndex: int): int =
  ## Returns the player index for the host assigned to one home map.
  result = -1
  for i, player in sim.players:
    if player.homeFlag == mapIndex:
      return i

proc homeVisitors(sim: SimServer, mapIndex, hostIndex: int): seq[int] =
  ## Returns player indices visiting one occupied home map.
  for i, player in sim.players:
    if i == hostIndex:
      continue
    if player.mapIndex == mapIndex:
      result.add(i)

proc recordDinner(
  player: Player,
  record: DinnerRecord
) =
  ## Stores and shows one dinner result for a player.
  player.dinners.add(record)
  player.dinnerRecord = record
  player.dinnerTicks = DinnerScreenTicks

proc chooseDinnerBite*(
  eaten: array[FoodVeggieSlots, bool],
  pantry: array[FoodVeggieSlots, int],
  rng: var Rand
): int =
  ## Returns one host-pantry food index to eat, or -1 when empty.
  var wanted: seq[int]
  for i in 0 ..< FoodVeggieSlots:
    if pantry[i] > 0 and not eaten[i]:
      wanted.add(i)
  if wanted.len > 0:
    return wanted[rng.rand(wanted.len - 1)]
  let total = pantry.totalItems()
  if total <= 0:
    return -1
  var pick = rng.rand(total - 1)
  for i in 0 ..< FoodVeggieSlots:
    if pick < pantry[i]:
      return i
    pick -= pantry[i]
  -1

proc applyDinnerBite(
  eaten: var array[FoodVeggieSlots, bool],
  pantry: var FoodCounts,
  ate: var FoodCounts,
  foodIndex: int
): int =
  ## Takes one pantry item and returns the bite score.
  if foodIndex < 0 or foodIndex >= FoodVeggieSlots:
    return 0
  if pantry[foodIndex] <= 0:
    return 0
  let isNew = not eaten[foodIndex]
  eaten[foodIndex] = true
  dec pantry[foodIndex]
  inc ate[foodIndex]
  if isNew:
    NewFoodEatScore
  else:
    LeftoverEatScore

proc eatDinnerRounds*(
  eaten: var seq[array[FoodVeggieSlots, bool]],
  pantry: var array[FoodVeggieSlots, int],
  rng: var Rand
): tuple[
  scores: seq[int],
  foods: seq[array[FoodVeggieSlots, int]]
] =
  ## Runs three shared rounds of one bite each from a host pantry.
  result.scores = newSeq[int](eaten.len)
  result.foods = newSeq[array[FoodVeggieSlots, int]](eaten.len)
  for r in 0 ..< DinnerEatRounds:
    for i in 0 ..< eaten.len:
      let foodIndex = chooseDinnerBite(eaten[i], pantry, rng)
      result.scores[i] += applyDinnerBite(
        eaten[i],
        pantry,
        result.foods[i],
        foodIndex
      )

proc startDinnerParties(sim: SimServer) =
  ## Resolves all valid 6pm dinner parties in occupied homes.
  sim.dinnerDone = true
  for homeIndex in 0 ..< HouseCount:
    let
      mapIndex = homeIndex.homeMapIndex()
      hostIndex = sim.homeHostIndex(mapIndex)
    if hostIndex < 0:
      continue
    let host = sim.players[hostIndex]
    if host.mapIndex != mapIndex:
      continue
    let visitors = sim.homeVisitors(mapIndex, hostIndex)
    if visitors.len == 0:
      continue

    var
      guestNames: seq[string]
      guestGnomeIndices: seq[int]
      diners = @[hostIndex]
    for visitorIndex in visitors:
      guestNames.add(sim.players[visitorIndex].playerName)
      guestGnomeIndices.add(sim.players[visitorIndex].gnomeIndex)
      diners.add(visitorIndex)
    sim.rng.shuffle(diners)

    var
      dinerEaten = newSeq[array[FoodVeggieSlots, bool]](diners.len)
      pantry = host.inventory
    for i, dinerIndex in diners:
      dinerEaten[i] = sim.players[dinerIndex].eaten
    let
      served = host.inventory
      hostScore = served.totalItems() * visitors.len
      eatenMeals = eatDinnerRounds(dinerEaten, pantry, sim.rng)
    for i, dinerIndex in diners:
      sim.players[dinerIndex].eaten = dinerEaten[i]
      sim.players[dinerIndex].score += eatenMeals.scores[i]

    let hostRecord = DinnerRecord(
      hostName: host.playerName,
      wasHost: true,
      foods: served,
      guestNames: guestNames,
      guestGnomeIndices: guestGnomeIndices,
      guestCount: visitors.len,
      score: hostScore
    )
    host.score += hostScore
    host.recordDinner(hostRecord)
    host.clearInventory()

    for visitorIndex in visitors:
      let visitor = sim.players[visitorIndex]
      var
        ate: FoodCounts
        eatScore = 0
      for i, dinerIndex in diners:
        if dinerIndex == visitorIndex:
          ate = eatenMeals.foods[i]
          eatScore = eatenMeals.scores[i]
          break
      visitor.recordDinner(
        DinnerRecord(
          hostName: host.playerName,
          wasHost: false,
          foods: ate,
          guestNames: guestNames,
          guestGnomeIndices: guestGnomeIndices,
          guestCount: visitors.len,
          score: eatScore
        )
      )

proc startDay(sim: SimServer) =
  ## Starts a new morning while keeping long-game player progress.
  inc sim.dayNumber
  sim.dayTick = 0
  sim.scoreTicks = 0
  sim.dinnerDone = false
  sim.gardens = loadGardens(sim.resourceRects, sim.rng)
  for player in sim.players.mitems:
    player.dinnerTicks = 0
    player.dinnerRecord = nil
    player.curfewMissed = false
  for i in 0 ..< sim.players.len:
    sim.teleportPlayerToOwnHome(i)

proc startScoreScreen(sim: SimServer) =
  ## Starts the end-of-day scoring screen. The portal takes every gnome
  ## home with no curfew penalty.
  sim.dayTick = sim.dayTicks
  sim.scoreTicks = ScoreScreenTicks
  for player in sim.players.mitems:
    player.dinnerTicks = 0
    player.dinnerRecord = nil
    player.curfewMissed = false
  for i in 0 ..< sim.players.len:
    sim.teleportPlayerToOwnHome(i)

proc scoreScreenActive*(sim: SimServer): bool =
  ## True while the end-of-day score screen is up.
  sim.scoreTicks > 0

proc playerScore*(sim: SimServer, playerIndex: int): int =
  ## One player's cumulative score.
  sim.players[playerIndex].score

proc replayChatVisibleTo(sim: SimServer, speaker, viewer: Player): bool =
  ## Whether `viewer` would see `speaker`'s current speech bubble — the
  ## in-game "hearing range". Chat has no explicit radius: a bubble is only
  ## delivered to a viewer when it lands inside that viewer's viewport (the
  ## camera follows the viewer, clamped at map edges). This mirrors the exact
  ## geometry of `addNameTag` + `addSpeechBubble` on the render path.
  if speaker.message.len == 0 or speaker.messageTicks <= 0:
    return false
  if speaker.mapIndex != viewer.mapIndex:  # a house wall blocks the bubble
    return false
  let
    cameraX = sim.cameraXFor(viewer)
    cameraY = sim.cameraYFor(viewer)
    screenX = speaker.x - cameraX
    screenY = speaker.y - cameraY
    tag = sim.nameTagSprite(speaker.playerName)
    nameY = screenY - tag.height - NameGapY
    bubble = sim.speechBubbleSprite(speaker.message)
    bubbleX = screenX + GnomeSpriteSize div 2 - bubble.width div 2
    bubbleY = nameY - bubble.height - ChatGapY
  rectVisible(bubbleX, bubbleY, bubble.width, bubble.height,
    ViewportWidth, ViewportHeight)

proc replayChatAudience*(sim: SimServer, speakerSlot: int): seq[int] =
  ## Slots of the OTHER players who would currently see `speakerSlot`'s chat
  ## bubble — everyone in hearing range at this tick. Empty when the speaker
  ## has no active message. Evaluate it on the tick the message is set; the
  ## bubble then lingers (`ChatLifetimeTicks`), so someone who walks up later
  ## can also see it — this captures the audience at the moment of speaking.
  if speakerSlot < 0 or speakerSlot >= sim.players.len:
    return @[]
  let speaker = sim.players[speakerSlot]
  for slot, viewer in sim.players:
    if slot != speakerSlot and sim.replayChatVisibleTo(speaker, viewer):
      result.add(slot)

proc playerMapIndex*(sim: SimServer, playerIndex: int): int =
  ## The map one player is on: 0 outdoors, 1..9 inside that house.
  sim.players[playerIndex].mapIndex

proc playerMessage*(sim: SimServer, playerIndex: int): string =
  ## One player's current chat bubble text.
  sim.players[playerIndex].message

proc worldLayoutFor*(sim: SimServer): WorldLayout =
  ## The static village layout the villager brains navigate.
  for garden in sim.gardens:
    result.gardens.add(garden.rect)
  for i in 0 ..< HouseCount:
    result.houses[i] = sim.houses[i].rect
    result.houseValid[i] = sim.houses[i].valid
  result.exit = sim.homeResources.exit
  result.hasExit = sim.homeResources.hasExit

proc navigationFor*(sim: SimServer): Navigation =
  ## Navigation spaces over the same walk masks the simulation uses.
  let home = sim.homeMaps[0]
  newNavigation(
    sim.mainMap.walkMask, sim.mainMap.width, sim.mainMap.height,
    home.walkMask, home.width, home.height
  )

proc nameTagVisible(sim: SimServer, player: Player, screenX, screenY: int): bool =
  ## Whether a gnome's name tag would be drawn, using the same geometry as
  ## addNameTag without rendering the sprite.
  let
    width = max(1, sim.textFont.textWidth(player.playerName) + NamePadX * 2)
    height = sim.textFont.height + NamePadY * 2
    x = screenX + GnomeSpriteSize div 2 - width div 2
    y = screenY - height - NameGapY
  rectVisible(x, y, width, height, ViewportWidth, ViewportHeight)

proc observe*(sim: SimServer, playerIndex: int): Observation =
  ## What one gnome can see this tick: exactly what its own player view
  ## would draw, read from ground truth instead of sprites.
  let player = sim.players[playerIndex]
  result.tick = sim.tickCount
  result.dayNumber = sim.dayNumber
  result.minutes = sim.currentDayMinutes()
  result.ticksPerMinute = float(sim.dayTicks) / float(DayTotalMinutes)
  result.scene =
    if player.dinnerTicks > 0 or sim.scoreTicks > 0:
      Overlay
    elif player.mapIndex.isHomeMap():
      Indoors
    else:
      Outdoors
  result.currentHouse =
    if player.mapIndex.isHomeMap():
      player.mapIndex - HomeMapIndexBase
    else:
      -1
  result.foot = Point(x: player.playerFootX(), y: player.playerFootY())
  result.inventoryTotal = player.inventory.totalItems()
  result.foodCollectedText = player.inventory.foodListText()
  result.foodLookingForText = player.eaten.foodsNotEatenText()
  result.dinnerDone = sim.dinnerDone
  result.curfewMissed = player.curfewMissed
  if player.dinnerTicks > 0 and player.dinnerRecord != nil:
    let record = player.dinnerRecord
    result.dinner = DinnerOutcome(
      present: true,
      hostName: record.hostName,
      wasHost: record.wasHost,
      score: record.score,
      guests: record.guestNames,
      foodsText: record.foods.foodListText()
    )
  result.gardensWithFood = 0
  for garden in sim.gardens:
    if garden.hasFood():
      inc result.gardensWithFood
  if result.scene == Overlay:
    return
  let
    cameraX = sim.cameraXFor(player)
    cameraY = sim.cameraYFor(player)
  for i, other in sim.players:
    if i == playerIndex or other.mapIndex != player.mapIndex:
      continue
    let
      screenX = other.x - cameraX
      screenY = other.y - cameraY
    if not rectVisible(screenX, screenY, GnomeSpriteSize, GnomeSpriteSize,
        ViewportWidth, ViewportHeight):
      continue
    if not sim.nameTagVisible(other, screenX, screenY):
      continue
    var visible = VisiblePlayer(
      name: other.playerName,
      houseIndex: other.homeFlag - HomeMapIndexBase,
      foot: Point(x: other.playerFootX(), y: other.playerFootY())
    )
    visible.distanceSquared = distanceSquared(
      result.foot.x, result.foot.y, visible.foot.x, visible.foot.y
    )
    if other.message.len > 0 and other.messageTicks > 0 and
        sim.replayChatVisibleTo(other, player):
      visible.says = other.message
    result.visiblePlayers.add(visible)
  result.gardenMarkerOnScreen = newSeq[bool](sim.gardens.len)
  result.gardenMarkerVisible = newSeq[bool](sim.gardens.len)
  if result.scene == Outdoors:
    for i, garden in sim.gardens:
      let
        center = garden.rect.center()
        x = center.x - FoodSpriteSize div 2 - cameraX
        y = center.y - FoodSpriteSize div 2 - cameraY
      result.gardenMarkerOnScreen[i] = rectVisible(
        x, y, FoodSpriteSize, FoodSpriteSize, ViewportWidth, ViewportHeight
      )
      result.gardenMarkerVisible[i] =
        result.gardenMarkerOnScreen[i] and garden.hasFood()
    for i, house in sim.houses:
      if house.valid:
        result.houseOnScreen[i] = rectVisible(
          house.rect.x - cameraX, house.rect.y - cameraY,
          house.rect.w, house.rect.h,
          ViewportWidth, ViewportHeight
        )

proc encounterIdForSeat(sim: SimServer, seat: int): int =
  ## The open conversation this house seat sits in at the current
  ## tick, from the replay's conversation records; zero in live play
  ## or when the seat is not in one.
  if seat < 0 or sim.conversationTimeline.events.len == 0:
    return 0
  for group in sim.conversationTimeline.encounterGroupsAt(sim.tickCount):
    for member in group.members:
      if member == seat:
        return group.id
  0

proc captureChatFeed(sim: SimServer) =
  ## Queues freshly spoken chats with their audience for the delay chat.
  ## Messages nobody heard are skipped.
  for i, player in sim.players:
    if player.message.len == 0 or player.messageTicks != ChatLifetimeTicks:
      continue
    let audience = sim.replayChatAudience(i)
    if audience.len == 0:
      continue
    let seat =
      if player.homeFlag.isHomeMap():
        player.homeFlag - HomeMapIndexBase
      else:
        -1
    var item = ChatFeedItem(
      speaker: ChatFeedPerson(
        name: player.playerName,
        gnomeIndex: player.gnomeIndex
      ),
      message: player.message,
      encounterId: sim.encounterIdForSeat(seat)
    )
    for slot in audience:
      item.hearers.add(ChatFeedPerson(
        name: sim.players[slot].playerName,
        gnomeIndex: sim.players[slot].gnomeIndex
      ))
    sim.chatFeed.add(item)
  while sim.chatFeed.len > ChatFeedMaxItems and sim.chatFeedIndex > 0:
    sim.chatFeed.delete(0)
    dec sim.chatFeedIndex

proc delayChatMessage*(sim: SimServer): string =
  ## The delay-chat banner line currently on screen, or empty.
  if sim.chatFeedIndex < 0 or sim.chatFeedIndex >= sim.chatFeed.len:
    return ""
  sim.chatFeed[sim.chatFeedIndex].message

proc queueDelayChat*(sim: SimServer, speaker, message: string) =
  ## Appends one delay-chat banner line. Viewer-only; not hashed.
  sim.chatFeed.add(ChatFeedItem(
    speaker: ChatFeedPerson(name: speaker, gnomeIndex: 0),
    message: message
  ))

proc chatFeedScopeMatches(sim: SimServer, index: int): bool =
  ## Whether the feed scope admits this line. Scope zero admits every
  ## line; a committed conversation admits only its own.
  sim.chatFeedScope == 0 or
    sim.chatFeed[index].encounterId == sim.chatFeedScope

proc chatFeedNextIndex(sim: SimServer, fromIndex: int): int =
  ## The first feed line at or after fromIndex that the current scope
  ## admits, or -1 when none has been captured yet.
  var i = max(fromIndex, 0)
  while i < sim.chatFeed.len:
    if sim.chatFeedScopeMatches(i):
      return i
    inc i
  -1

proc advanceChatFeed*(sim: SimServer, now = epochTime()) =
  ## Advances the delay-chat cursor by wall clock, not sim ticks or
  ## render frames. Each queued line stays up ChatFeedShowSeconds so it
  ## can be read while the sim zips or the viewer runs at 60fps. While
  ## a queue commitment scopes the feed, the cursor steps only through
  ## the committed conversation's lines and skips every other
  ## circle's: cards and the banner follow the cursor, so scoping it
  ## scopes the whole show.
  if sim.convQueue.len > 0 and not sim.convQueueCommitted:
    # Between queue commitments nothing airs: the wide fast-forward is
    # silent instead of narrating the skipped time, and the cursor
    # waits where it is for the next committed conversation.
    sim.chatFeedShownAt = now
    return
  if sim.directorTweenLeft > 0:
    # The camera is mid-glide: the line on screen keeps its full read
    # time once the shot settles, and nothing new starts meanwhile.
    sim.chatFeedShownAt = now
    return
  if sim.chatFeedIndex < 0:
    let first = sim.chatFeedNextIndex(0)
    if first >= 0:
      sim.chatFeedIndex = first
      sim.chatFeedShownAt = now
    return
  if sim.chatFeedIndex >= sim.chatFeed.len or
      not sim.chatFeedScopeMatches(sim.chatFeedIndex):
    # The cursor sits on another circle's line (a scope landed
    # mid-feed): jump to the next admitted line, or park past the end
    # until one is captured.
    let next = sim.chatFeedNextIndex(sim.chatFeedIndex)
    if next >= 0:
      sim.chatFeedIndex = next
      sim.chatFeedShownAt = now
    else:
      sim.chatFeedIndex = sim.chatFeed.len
    return
  if now - sim.chatFeedShownAt < ChatFeedShowSeconds:
    return
  let next = sim.chatFeedNextIndex(sim.chatFeedIndex + 1)
  if next >= 0:
    sim.chatFeedIndex = next
    sim.chatFeedShownAt = now

proc advanceChatFeedNow*(sim: SimServer, now = epochTime()) =
  ## Steps the delay chat to the next line right away: the voice for
  ## the line on screen has finished, so its card leaves with it
  ## instead of lingering out the wall-clock timer.
  if sim.convQueue.len > 0 and not sim.convQueueCommitted:
    # Between queue commitments nothing airs; see advanceChatFeed.
    sim.chatFeedShownAt = now
    return
  if sim.directorTweenLeft > 0:
    sim.chatFeedShownAt = now
    return
  if sim.chatFeedIndex < 0 or
      sim.chatFeedIndex >= sim.chatFeed.len or
      not sim.chatFeedScopeMatches(sim.chatFeedIndex):
    sim.advanceChatFeed(now)
    return
  let next = sim.chatFeedNextIndex(sim.chatFeedIndex + 1)
  if next >= 0:
    sim.chatFeedIndex = next
    sim.chatFeedShownAt = now

proc step*(sim: SimServer, inputs: openArray[InputState]) =
  ## Advances the Heartleaf simulation by one tick.
  inc sim.tickCount
  if sim.scoreTicks > 0:
    dec sim.scoreTicks
    sim.updateMessages()
    if sim.scoreTicks <= 0:
      sim.startDay()
    return

  sim.captureChatFeed()
  for i in 0 ..< sim.players.len:
    let input =
      if i < inputs.len:
        inputs[i]
      else:
        InputState()
    let attackPressed = input.attack and not sim.players[i].attackDown
    if attackPressed:
      sim.interact(i)
    sim.players[i].attackDown = input.attack
    sim.applyInput(i, input)
  for i in 0 ..< sim.players.len:
    sim.moveAxis(sim.players[i], true)
    sim.moveAxis(sim.players[i], false)
  if sim.tickCount mod TrailSampleTicks == 0:
    while sim.trails.len < sim.players.len:
      sim.trails.add(@[])
    for i, player in sim.players:
      sim.trails[i].add(TrailPoint(
        x: player.playerFootX(),
        y: player.playerFootY(),
        mapIndex: player.mapIndex
      ))
      if sim.trails[i].len > TrailMaxPoints:
        sim.trails[i].delete(0)
  sim.updateMessages()
  inc sim.dayTick
  if not sim.dinnerDone and sim.currentDayMinutes() >= DinnerTallyMinutes:
    sim.startDinnerParties()
  if sim.dayTick >= sim.dayTicks:
    sim.startScoreScreen()

proc mixHash(hash: var uint64, value: uint64) =
  ## Mixes one value into a running FNV-1a style hash.
  hash = (hash xor value) * 1099511628211'u64

proc mixHashInt(hash: var uint64, value: int) =
  ## Mixes one integer into a running hash.
  hash.mixHash(cast[uint64](int64(value)))

proc gameHash*(sim: SimServer): uint64 =
  ## Returns a deterministic hash of gameplay state.
  result = 14695981039346656037'u64
  result.mixHashInt(sim.tickCount)
  result.mixHashInt(sim.dayTick)
  result.mixHashInt(sim.dayNumber)
  result.mixHashInt(sim.scoreTicks)
  result.mixHashInt(ord(sim.dinnerDone))
  result.mixHashInt(sim.players.len)
  for player in sim.players:
    result.mixHashInt(player.x)
    result.mixHashInt(player.y)
    result.mixHashInt(player.velX)
    result.mixHashInt(player.velY)
    result.mixHashInt(player.carryX)
    result.mixHashInt(player.carryY)
    result.mixHashInt(ord(player.direction))
    result.mixHashInt(player.gnomeIndex)
    result.mixHashInt(player.homeFlag)
    result.mixHashInt(player.mapIndex)
    result.mixHashInt(player.score)
    result.mixHashInt(player.dinnerTicks)
    result.mixHashInt(player.messageTicks)
    result.mixHashInt(player.message.len)
    result.mixHashInt(ord(player.attackDown))
    for count in player.inventory:
      result.mixHashInt(count)
    for eatenFlag in player.eaten:
      result.mixHashInt(ord(eatenFlag))
  result.mixHashInt(sim.gardens.len)
  for garden in sim.gardens:
    for count in garden.inventory:
      result.mixHashInt(count)

proc applyPlayerChat*(sim: SimServer, playerIndex: int, message: string) =
  ## Shows one chat message above a player's head.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  sim.players[playerIndex].message = message
  sim.players[playerIndex].messageTicks = ChatLifetimeTicks

proc removePlayerAt*(sim: SimServer, playerIndex: int) =
  ## Removes one player from the simulation, compacting indices.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  sim.players.delete(playerIndex)

proc applyReplayEvents(replay: var ReplayPlayer, sim: SimServer) =
  ## Applies replay leaves, joins, inputs, and chats for the current tick.
  let time = tickTime(sim.tickCount)
  while replay.leaveIndex < replay.data.leaves.len and
      replay.data.leaves[replay.leaveIndex].time <= time:
    let leave = replay.data.leaves[replay.leaveIndex]
    if int(leave.player) < 0 or int(leave.player) >= sim.players.len:
      raise newException(ReplayError, "Replay player leave is invalid")
    sim.removePlayerAt(int(leave.player))
    if int(leave.player) < replay.masks.len:
      replay.masks.delete(int(leave.player))
    inc replay.leaveIndex

  while replay.joinIndex < replay.data.joins.len and
      replay.data.joins[replay.joinIndex].time <= time:
    let join = replay.data.joins[replay.joinIndex]
    if int(join.player) != sim.players.len:
      raise newException(ReplayError, "Replay player join order is invalid")
    if sim.addPlayer(join.name, join.slot) != int(join.player):
      raise newException(ReplayError, "Replay player join was rejected")
    replay.ensureReplayPlayer(int(join.player))
    inc replay.joinIndex

  while replay.inputIndex < replay.data.inputs.len and
      replay.data.inputs[replay.inputIndex].time <= time:
    let input = replay.data.inputs[replay.inputIndex]
    replay.ensureReplayPlayer(int(input.player))
    replay.masks[int(input.player)] = input.keys
    inc replay.inputIndex

  while replay.chatIndex < replay.data.chats.len and
      replay.data.chats[replay.chatIndex].time <= time:
    let chat = replay.data.chats[replay.chatIndex]
    sim.applyPlayerChat(int(chat.player), chat.message)
    inc replay.chatIndex

proc checkReplayHash(replay: var ReplayPlayer, sim: SimServer) =
  ## Checks the recorded hash for the current tick, leniently.
  if replay.hashValidationFailed:
    if sim.tickCount >= replay.replayMaxTick():
      replay.playing = false
    return
  if replay.hashIndex >= replay.data.hashes.len:
    replay.playing = false
    return
  let expected = replay.data.hashes[replay.hashIndex]
  if int(expected.tick) < sim.tickCount:
    stderr.writeLine "Replay hash tick is missing at tick " & $sim.tickCount & "."
    replay.hashValidationFailed = true
    replay.hashMismatchTick = sim.tickCount
    return
  if int(expected.tick) > sim.tickCount:
    return
  let hash = sim.gameHash()
  if hash != expected.hash:
    stderr.writeLine "Replay hash mismatch at tick " & $sim.tickCount &
      "; expected " & $expected.hash & ", got " & $hash & "."
    replay.hashValidationFailed = true
    replay.hashMismatchTick = sim.tickCount
    return
  inc replay.hashIndex

proc stepReplay*(replay: var ReplayPlayer, sim: SimServer) =
  ## Advances replay playback by one simulation tick, holding on the
  ## final recorded tick so the counter never outruns the recording.
  if sim.tickCount >= replay.replayMaxTick():
    replay.playing = false
    return
  replay.applyReplayEvents(sim)
  var inputs = newSeq[InputState](sim.players.len)
  for playerIndex in 0 ..< sim.players.len:
    replay.ensureReplayPlayer(playerIndex)
    inputs[playerIndex] = decodeInputMask(replay.masks[playerIndex])
  sim.step(inputs)
  replay.checkReplayHash(sim)

proc saveKeyframe(sim: SimServer): string =
  ## Serializes dynamic simulation state for one replay keyframe.
  KeyframeState(
    players: sim.players,
    gardens: sim.gardens,
    houses: sim.houses,
    rng: sim.rng,
    tickCount: sim.tickCount,
    dayTick: sim.dayTick,
    dayTicks: sim.dayTicks,
    dayNumber: sim.dayNumber,
    scoreTicks: sim.scoreTicks,
    dinnerDone: sim.dinnerDone
  ).toFlatty()

proc restoreKeyframe(sim: SimServer, bytes: string) =
  ## Restores dynamic simulation state from one replay keyframe,
  ## keeping loaded asset references untouched.
  let state = bytes.fromFlatty(KeyframeState)
  sim.players = state.players
  sim.gardens = state.gardens
  sim.houses = state.houses
  sim.rng = state.rng
  sim.tickCount = state.tickCount
  sim.dayTick = state.dayTick
  sim.dayTicks = state.dayTicks
  sim.dayNumber = state.dayNumber
  sim.scoreTicks = state.scoreTicks
  sim.dinnerDone = state.dinnerDone

proc buildReplayKeyframes*(
  replay: var ReplayPlayer,
  seed = DefaultSeed,
  dayTicks = DayTicks,
  interval = ReplayKeyframeTicks
) =
  ## Builds serialized seek keyframes across the whole replay.
  replay.keyframes = @[]
  let sim = initSimServer(seed, dayTicks)
  var builder = initReplayPlayer(replay.data)
  builder.looping = false
  replay.keyframes.add(
    builder.saveReplayKeyframe(sim.tickCount, sim.saveKeyframe())
  )
  let maxTick = builder.replayMaxTick()
  while builder.playing and sim.tickCount < maxTick:
    builder.stepReplay(sim)
    if sim.tickCount mod max(interval, 1) == 0 or sim.tickCount == maxTick:
      replay.keyframes.add(
        builder.saveReplayKeyframe(sim.tickCount, sim.saveKeyframe())
      )

proc seekReplay*(replay: var ReplayPlayer, sim: SimServer, tick: int) =
  ## Seeks replay playback to a target tick using seek keyframes.
  if replay.keyframes.len == 0:
    return
  inc replay.seekSerial
  let keyframe = replay.keyframes[replay.replayKeyframeIndex(tick)]
  sim.restoreKeyframe(keyframe.simBytes)
  replay.restoreReplayKeyframeCursors(keyframe)
  sim.trails.setLen(0)
  sim.chatFeed.setLen(0)
  sim.chatFeedIndex = -1
  sim.chatFeedShownAt = 0.0
  sim.conversationCircles.setLen(0)
  sim.conversationAnchors.clear()
  # Bound stepping by the last recorded tick, not by the hash cursor:
  # after a hash mismatch the cursor stops advancing and would let a
  # past-the-end seek step the simulation far beyond the recording.
  let endTick = min(tick, replay.replayMaxTick())
  while sim.tickCount < endTick:
    replay.stepReplay(sim)

proc buildConversationQueue*(sim: SimServer, finalTick: int) =
  ## Builds the conversation queue from the attached timeline: every
  ## conversation in birth order, same-tick births together in a
  ## stable order. An empty queue (a day with no conversations) keeps
  ## plain playback.
  sim.convQueue = sim.conversationTimeline.conversationSpans(finalTick)
  sim.convQueueIndex = 0
  sim.convQueueLast = -1
  sim.convQueueCommitted = false
  sim.convQueueFurthest = 0
  sim.chatFeedScope = 0
  sim.directorCommitEncounter = 0
  if sim.convQueue.len > 0:
    echo "Conversation queue: ", sim.convQueue.len, " conversations"

proc commitConversation(
  sim: SimServer,
  replay: var ReplayPlayer,
  index: int,
  atBirth = true
) =
  ## Commits playback to one queue item: the camera and feed belong to
  ## the conversation until its death tick. With atBirth the playhead
  ## moves to its birth tick (the rewind, when the playhead already
  ## ran past it in a same-tick birth group); a scrub that lands
  ## mid-span commits in place instead and plays from there.
  let item = sim.convQueue[index]
  sim.convQueueIndex = index
  sim.convQueueLast = index
  sim.convQueueCommitted = true
  if sim.directorCommitEncounter != item.id and sim.directorFocusActive:
    # Jumping between commitments keeps the glide grammar: the camera
    # tweens from the old ring instead of snapping.
    sim.startDirectorTween()
  if atBirth and sim.tickCount != item.birthTick:
    replay.seekReplay(sim, item.birthTick)
  sim.directorCommitEncounter = item.id
  sim.chatFeedScope = item.id

proc alignConversationQueue(
  sim: SimServer,
  replay: var ReplayPlayer
) =
  ## A manual seek moved the playhead: derive the queue cursor from
  ## it. Inside a conversation's span (first in birth order) the show
  ## commits there and plays it out from the scrubbed tick; otherwise
  ## the playhead fast-forwards to the next birth. One player, one
  ## behavior - scrubbing just moves the clock.
  if sim.convQueue.len == 0:
    return
  sim.convQueueCommitted = false
  sim.releaseDirectorCommit()
  for i, span in sim.convQueue:
    if span.birthTick <= sim.tickCount and sim.tickCount < span.deathTick:
      sim.commitConversation(replay, i, atBirth = false)
      # Only lines spoken from here on air: the keyframe replay behind
      # a seek refills the feed with lines from before the target.
      sim.chatFeedIndex = sim.chatFeed.len
      sim.chatFeedShownAt = epochTime()
      return
  var next = sim.convQueue.len
  for i, span in sim.convQueue:
    if span.birthTick >= sim.tickCount:
      next = i
      break
  sim.convQueueIndex = next

proc restartConversationQueue(sim: SimServer) =
  ## Playback restarted from tick zero: the queue starts over from
  ## the top.
  sim.convQueueIndex = 0
  sim.convQueueLast = -1
  sim.convQueueCommitted = false
  sim.convQueueFurthest = 0
  sim.releaseDirectorCommit()

proc stepConversationQueue(
  sim: SimServer,
  replay: var ReplayPlayer
) =
  ## One frame of conversation-queue bookkeeping, run while playback
  ## advances. Commits to the queue head when the playhead reaches its
  ## birth; at a death tick releases the shot and either rewinds to
  ## the next same-group birth or resumes forward from the furthest
  ## tick already reached, so world time never repeats or skips.
  if sim.convQueue.len == 0:
    return
  sim.convQueueFurthest = max(sim.convQueueFurthest, sim.tickCount)
  if sim.convQueueCommitted:
    let item = sim.convQueue[sim.convQueueIndex]
    if sim.tickCount >= item.deathTick:
      # This conversation has played end-to-end.
      sim.convQueueCommitted = false
      sim.releaseDirectorCommit()
      let next = sim.convQueueIndex + 1
      if next < sim.convQueue.len and
          sim.convQueue[next].birthTick <= sim.tickCount:
        # The concurrent case: the next queue item was born at or
        # before the playhead. Seek back and play it whole.
        sim.commitConversation(replay, next)
      else:
        sim.convQueueIndex = next
        if sim.tickCount < sim.convQueueFurthest:
          # The group is played out; resume from the furthest tick
          # already shown, then fast-forward to the next birth.
          replay.seekReplay(sim, sim.convQueueFurthest)
  elif sim.convQueueIndex < sim.convQueue.len:
    if sim.tickCount >= sim.convQueue[sim.convQueueIndex].birthTick:
      sim.commitConversation(replay, sim.convQueueIndex)

proc applyReplaySeek*(replay: var ReplayPlayer, sim: SimServer, tick: int) =
  ## Seeks replay playback and pauses on the target tick, then derives
  ## the queue position from the new playhead.
  replay.playing = false
  replay.seekReplay(sim, clamp(tick, 0, replay.replayMaxTick()))
  sim.alignConversationQueue(replay)

proc applyReplayCommand*(
  replay: var ReplayPlayer,
  sim: SimServer,
  command: char
) =
  ## Applies one replay viewer transport command.
  case command
  of ' ':
    replay.playing = not replay.playing
  of 'p':
    replay.playing = true
  of 'P':
    replay.playing = false
  of '+', '=':
    replay.speedIndex = min(replay.speedIndex + 1, PlaybackSpeedTicks.high)
  of '-', '_':
    replay.speedIndex = max(replay.speedIndex - 1, 0)
  of 'q':
    replay.speedIndex = 0
  of 'h':
    replay.speedIndex = 1
  of '1':
    replay.speedIndex = 2
  of '2':
    replay.speedIndex = 3
  of '3':
    replay.speedIndex = 4
  of '4':
    replay.speedIndex = 5
  of '8':
    replay.speedIndex = 6
  of '6':
    replay.speedIndex = 7
  of ',', '<':
    replay.playing = false
    sim.restartConversationQueue()
    replay.seekReplay(sim, 0)
  of 'b':
    replay.playing = false
    replay.seekReplay(sim, max(0, sim.tickCount - 1))
    sim.alignConversationQueue(replay)
  of 'e':
    replay.playing = false
    replay.seekReplay(sim, replay.replayMaxTick())
    sim.alignConversationQueue(replay)
  of 'r':
    replay.looping = not replay.looping
  of '.', '>':
    replay.playing = false
    replay.seekReplay(sim, sim.tickCount + ReplayFps * 5)
    sim.alignConversationQueue(replay)
  of 'n':
    # Next conversation: move the cursor forward and commit at that
    # item's birth. No-op on an empty queue or past the last item.
    if sim.convQueue.len > 0:
      let target =
        if sim.convQueueCommitted:
          sim.convQueueIndex + 1
        else:
          sim.convQueueIndex
      if target < sim.convQueue.len:
        sim.commitConversation(replay, target)
  of 'N':
    # Prev conversation: restart the last-committed or current item
    # from its birth tick. No-op before anything has committed and on
    # an empty queue.
    if sim.convQueue.len > 0 and sim.convQueueLast >= 0:
      sim.commitConversation(replay, sim.convQueueLast)
  else:
    discard

when not defined(emscripten):
  proc initAppState() =
    ## Initializes shared websocket state.
    appState = WebSocketAppState()
    initLock(appState.lock)
    appState.playerSlots = initTable[WebSocket, int]()
    appState.globalViewers = initTable[WebSocket, PlayerViewerState]()
    appState.replayViewers = initTable[WebSocket, PlayerViewerState]()
    appState.playerUsernames = initTable[WebSocket, string]()
    appState.souls = initTable[int, Soul]()
    appState.soulSockets = initTable[WebSocket, int]()
    appState.logSent = initTable[WebSocket, int]()
    appState.gameNumber = 1
    appState.closedSockets = @[]
    appState.tokens = @[]
    appState.replayServerMode = false
    appState.replayLoaded = false
    appState.pendingReplayUri = ""

proc publishNowPlaying(sim: SimServer) =
  ## Mirrors the banner's current chat line into shared state, so the
  ## /nowplaying route can hand it to the viewer pages' speech layer.
  let now = sim.chatFeedNowPlaying()
  {.gcsafe.}:
    withLock appState.lock:
      if now != appState.nowKey:
        appState.nowKey = now
        if now.index >= 0:
          inc appState.nowPlayingSerial
          appState.nowPlayingSeat = now.gnomeIndex
          appState.nowPlayingText = sim.chatFeedNowText()


proc globalPanelClickedPlayer(data: string): int =
  ## Returns the clicked global score-panel player index or -1.
  result = -1
  var
    x = 0
    y = 0
    layer = -1
  for item in data.parseSpriteClientMessages():
    case item.kind
    of SpriteClientMouseMoveMessage:
      x = item.x
      y = item.y
      layer =
        if item.hasLayer:
          item.layer
        else:
          -1
    of SpriteClientMouseButtonMessage:
      if layer != GlobalPanelLayerId or item.button != 1'u8 or
          not item.down:
        continue
      if x < GlobalPanelCardPadX + GlobalPanelNameX or
          x >= GlobalPanelWidth:
        continue
      if y < GlobalPanelCardPadY + GlobalPanelPad:
        continue
      let row = (y - GlobalPanelCardPadY - GlobalPanelPad) div
        GlobalPanelRowHeight
      if row >= 0 and row < HouseCount:
        return row
    of SpriteClientChatMessage, SpriteClientInputMessage,
        SpriteClientReadyMessage, SpriteClientDebugSpriteMessage,
        SpriteClientSpritesOffMessage:
      discard

proc globalMapClickAt(data: string): tuple[hit: bool, x, y: int] =
  ## Returns the map-layer click position in one viewer packet.
  result = (false, 0, 0)
  var
    x = 0
    y = 0
    layer = -1
  for item in data.parseSpriteClientMessages():
    case item.kind
    of SpriteClientMouseMoveMessage:
      x = item.x
      y = item.y
      layer =
        if item.hasLayer:
          item.layer
        else:
          -1
    of SpriteClientMouseButtonMessage:
      if layer == MapLayerId and item.button == 1'u8 and item.down:
        return (true, x, y)
    of SpriteClientChatMessage, SpriteClientInputMessage,
        SpriteClientReadyMessage, SpriteClientDebugSpriteMessage,
        SpriteClientSpritesOffMessage:
      discard

proc applyReplayViewerMessage(state: PlayerViewerState, data: string) =
  ## Applies mouse and replay command input from one viewer message.
  for item in data.parseSpriteClientMessages():
    case item.kind
    of SpriteClientMouseMoveMessage:
      state.mouseX = item.x
      state.mouseY = item.y
      state.mouseLayer =
        if item.hasLayer:
          item.layer
        else:
          MapLayerId
    of SpriteClientMouseButtonMessage:
      if item.button == 0x01'u8:
        state.mouseDown = item.down
        if item.down:
          state.clickPending = true
          state.mousePressX = state.mouseX
          state.mousePressY = state.mouseY
          state.mousePressLayer = state.mouseLayer
        else:
          state.scrubbingReplay = false
    of SpriteClientChatMessage:
      for ch in item.text:
        state.replayCommands.add(ch)
    of SpriteClientInputMessage, SpriteClientReadyMessage,
        SpriteClientDebugSpriteMessage, SpriteClientSpritesOffMessage:
      discard

proc drainReplayViewerInput(
  state: PlayerViewerState,
  maxTick: int,
  seekTicks: var seq[int],
  commands: var seq[char]
) =
  ## Collects pending replay seeks and commands from one viewer.
  ## Score-panel clicks are handled first in the websocket handler;
  ## the panel, scrubber, and transport live on distinct layers, so
  ## a panel click never reaches the scrubber or transport checks.
  state.replaySeekTick = -1
  if state.clickPending:
    state.clickPending = false
    let seekTick = replayScrubTickAt(
      state.mousePressLayer,
      state.mousePressX,
      state.mousePressY,
      maxTick
    )
    if seekTick >= 0:
      state.scrubbingReplay = true
      state.replaySeekTick = seekTick
    else:
      let command = replayCommandAt(
        state.mousePressLayer,
        state.mousePressX,
        state.mousePressY
      )
      if command != '\0':
        state.replayCommands.add(command)
  if state.mouseDown and state.scrubbingReplay:
    let seekTick = replayScrubTickAt(
      state.mouseLayer,
      state.mouseX,
      state.mouseY,
      maxTick
    )
    if seekTick >= 0:
      state.replaySeekTick = seekTick
  if state.replaySeekTick >= 0:
    seekTicks.add(state.replaySeekTick)
  state.replaySeekTick = -1
  for command in state.replayCommands:
    commands.add(command)
  state.replayCommands.setLen(0)

proc newReplayViewerState*(): PlayerViewerState =
  ## Creates one replay viewer state with nothing selected.
  PlayerViewerState(selectedPlayerIndex: -1)

proc handleReplayViewerPacket*(state: PlayerViewerState, data: string) =
  ## Applies one raw sprite-client packet from a local viewer: the
  ## score-panel selection toggle, house-inset map clicks, and mouse,
  ## scrubber, and transport state. Mirrors websocketHandler.
  when defined(replayViewerDebug):
    for item in data.parseSpriteClientMessages():
      case item.kind
      of SpriteClientMouseMoveMessage:
        echo "debug mouse move x=", item.x, " y=", item.y,
          " layer=", (if item.hasLayer: item.layer else: -1)
      of SpriteClientMouseButtonMessage:
        echo "debug mouse button=", item.button, " down=", item.down
      else:
        discard
  let clickedPlayer = data.globalPanelClickedPlayer()
  if clickedPlayer >= 0:
    state.selectedPlayerIndex =
      if state.selectedPlayerIndex == clickedPlayer:
        -1
      else:
        clickedPlayer
    when defined(replayViewerDebug):
      echo "debug clickedPlayer=", clickedPlayer,
        " selected=", state.selectedPlayerIndex
  let mapClick = data.globalMapClickAt()
  if mapClick.hit:
    state.pendingMapClick = true
    state.pendingMapClickX = mapClick.x
    state.pendingMapClickY = mapClick.y
  state.applyReplayViewerMessage(data)

proc replayViewerFrame*(
  sim: SimServer,
  replay: var ReplayPlayer,
  state: var PlayerViewerState,
  replayLoaded: bool
): seq[uint8] =
  ## Advances one replay viewer frame for a single local viewer and
  ## returns the sprite packet to render: pending seeks and transport
  ## commands, playback stepping with loop restart, the delay chat
  ## pacing, and the global packet build.
  var
    seekTicks: seq[int]
    commands: seq[char]
  state.drainReplayViewerInput(replay.replayMaxTick(), seekTicks, commands)
  if replayLoaded:
    for seekTick in seekTicks:
      replay.applyReplaySeek(sim, seekTick)
    for command in commands:
      replay.applyReplayCommand(sim, command)
    if replay.playing:
      for _ in 0 ..< replay.replayTicksThisFrame():
        if replay.playing:
          replay.stepReplay(sim)
      if replay.looping and not replay.playing and
          replay.replayMaxTick() > 0:
        replay.seekReplay(sim, 0)
        replay.playing = true
  if replay.circlesTimeline.len > 0:
    # The replay recorded its circles; they beat any re-derivation.
    sim.conversationCircles =
      replay.circlesTimeline.circlesAtTick(sim.tickCount)
  else:
    sim.inferConversationCircles()
  sim.advanceChatFeed()
  sim.publishNowPlaying()
  sim.updateDirectorCamera()
  var nextState: PlayerViewerState
  result = sim.buildGlobalPacket(
    state,
    nextState,
    replayControls = replayLoaded,
    replayTick = sim.tickCount,
    replaySpeedIndex = replay.replaySpeedIndex(),
    replayMaxTick = replay.replayMaxTick(),
    replayPlaying = replay.playing,
    replayLooping = replay.looping,
    replayMismatchTick = replay.hashMismatchTick
  )
  state = nextState

when not defined(emscripten):
  proc removePlayer(sim: SimServer, websocket: WebSocket) =
    ## Forgets one websocket. Gnomes are owned by their souls, not their
    ## sockets, so a dropped player connection leaves the village as it is.
    if websocket in appState.replayViewers:
      appState.replayViewers.del(websocket)
    if websocket in appState.globalViewers:
      appState.globalViewers.del(websocket)
    if websocket in appState.playerSlots:
      appState.playerSlots.del(websocket)
    if websocket in appState.playerUsernames:
      appState.playerUsernames.del(websocket)
    if websocket in appState.soulSockets:
      appState.soulSockets.del(websocket)
    if websocket in appState.logSent:
      appState.logSent.del(websocket)

  proc resetConnectedPlayers() =
    ## Resets log cursors for a fresh simulation: the next game's log
    ## starts again at sequence 0.
    for websocket in appState.logSent.keys:
      appState.logSent[websocket] = 0

  proc freeSeatForSoul(): int =
    ## The lowest seat without a soul, or -1 when the village is full.
    let seatLimit =
      if appState.tokens.len > 0:
        appState.tokens.len
      else:
        HouseCount
    for seat in 0 ..< seatLimit:
      if seat notin appState.souls:
        return seat
    -1

  proc acceptSoul(websocket: WebSocket, raw: string): string =
    ## Stores the soul a player socket sent and returns the reply text.
    ## Souls are immutable for the episode; an identical resend is fine.
    if websocket in appState.soulSockets:
      let seat = appState.soulSockets[websocket]
      if appState.souls[seat].raw == raw:
        return appState.souls[seat].soulReply()
      return soulRejection("seat " & $seat & " already has a soul")
    var soul: Soul
    try:
      soul = parseSoul(raw)
    except SoulError as e:
      echo "soul rejected from ", appState.playerUsernames.getOrDefault(
        websocket, ""), ": ", e.msg
      return soulRejection(e.msg)
    var seat = appState.playerSlots.getOrDefault(websocket, -1)
    if seat < 0:
      seat = freeSeatForSoul()
      if seat < 0:
        return soulRejection("no free seat")
    if seat >= HouseCount:
      return soulRejection("seat " & $seat & " does not exist")
    if seat in appState.souls:
      if appState.souls[seat].raw == raw:
        appState.soulSockets[websocket] = seat
        return appState.souls[seat].soulReply()
      return soulRejection("seat " & $seat & " already has a soul")
    soul.seat = seat
    soul.username = appState.playerUsernames.getOrDefault(websocket, "")
    appState.souls[seat] = soul
    appState.soulSockets[websocket] = seat
    appState.playerSlots[websocket] = seat
    echo "soul accepted seat=", seat, " model=", soul.modelId,
      " bytes=", raw.len, " username=", soul.username
    if not soul.modelId.knownModelFamily():
      echo "soul seat=", seat, " names an unfamiliar model: ", soul.modelId
    soul.soulReply()

  proc parseLogCursor(text: string): tuple[game, sequence: int] =
    ## Reads "log-cursor game=N sequence=M"; missing parts read as 0 / -1.
    result = (game: 0, sequence: -1)
    for part in text[LogCursorPrefix.len .. ^1].splitWhitespace():
      let pair = part.split('=')
      if pair.len != 2:
        continue
      try:
        if pair[0] == "game":
          result.game = parseInt(pair[1])
        elif pair[0] == "sequence":
          result.sequence = parseInt(pair[1])
      except ValueError:
        discard

  proc declarePlayerFailure(seat: int, message: string) =
    ## Reports one seat as the reason the episode cannot go on. Hosted runs
    ## write the Coworld player failure artifact and exit without results;
    ## local runs only log it.
    echo "player failure seat=", seat, ": ", message
    if getEnv(CogamePlayerFailureUriEnv).len == 0:
      return
    writeCogameEnv(
      CogamePlayerFailureUriEnv,
      $(%*{"message": message, "failed_policy_index": seat}),
      "application/json"
    )
    quit(1)

  proc isWebSocketUpgrade(request: Request): bool =
    ## Returns true when the request is a websocket upgrade.
    request.headers["Sec-WebSocket-Key"].len > 0

  proc respondPlain(request: Request, status: int, body: string) =
    ## Sends a no-cache plain text response.
    var headers: HttpHeaders
    headers["Content-Type"] = "text/plain; charset=utf-8"
    headers["Cache-Control"] = "no-cache"
    request.respond(status, headers, body)

  proc serveHealthz(request: Request): bool =
    ## Serves the container health check endpoint.
    if request.path != HealthzPath or request.httpMethod notin ["GET", "HEAD"]:
      return false
    request.respondPlain(200, "healthy")
    return true

  proc playerSlot(request: Request): int =
    ## Returns the requested zero-based slot or -1 for automatic assignment.
    let text = request.queryParams.getOrDefault("slot", "").strip()
    if text.len == 0:
      return -1
    try:
      result = parseInt(text)
    except ValueError:
      return int.high
    if result < 0:
      return int.high

  proc playerToken(request: Request): string =
    ## Returns the requested player token.
    request.queryParams.getOrDefault("token", "").strip()

  proc playerUsername(request: Request, slot: int): string =
    ## Returns the display username for one joining player. The hosted
    ## `players[].name` config entry for the slot is authoritative; the
    ## `username` or `name` query parameter is the local-play fallback.
    if slot >= 0 and slot < appState.playerNames.len and
        appState.playerNames[slot].len > 0:
      return appState.playerNames[slot].cleanUsername()
    let username = request.queryParams.getOrDefault("username", "")
    if username.len > 0:
      return username.cleanUsername()
    return request.queryParams.getOrDefault("name", "").cleanUsername()

  proc playerJoinAllowed(slot: int, token: string): bool =
    ## Returns true when the configured token list accepts a join.
    if appState.tokens.len == 0:
      return true
    if slot >= 0 and slot < appState.tokens.len:
      return token == appState.tokens[slot]
    if slot == -1:
      return token in appState.tokens
    return false

  proc replayFilePath(uri: string): string =
    ## Resolves one local replay URI to a host path.
    const FilePrefix = "file://"
    if uri.startsWith(FilePrefix):
      return uri[FilePrefix.len .. ^1]
    if "://" in uri:
      return ""
    uri

  let replayDownloadPool = newCurlPool(1)

  proc loadReplayUri(uri: string): ReplayData =
    ## Loads a replay from a local file URI or HTTP(S) URL.
    parseReplayBytes(readCogameUri(uri, CogameLoadReplayUriEnv))

  proc readableReplayUri(uri: string): bool =
    ## Returns true when a replay URI can be opened by this server.
    if uri.len == 0:
      return false
    if uri.startsWith("http://") or uri.startsWith("https://"):
      return replayDownloadPool.head(uri).code == 200
    let path = replayFilePath(uri)
    path.len > 0 and fileExists(path)

  proc replayRequestUri(request: Request): string =
    ## Returns the replay artifact URI requested by a Coworld replay client.
    request.queryParams.getOrDefault("uri", "").strip()

  proc checkReplayRequest(request: Request): bool =
    ## Validates one replay page or websocket request, capturing the
    ## requested replay URI for the playback loop. Returns false after
    ## responding with an error.
    result = true
    var
      replayServerMode = false
      replayLoaded = false
    {.gcsafe.}:
      withLock appState.lock:
        replayServerMode = appState.replayServerMode
        replayLoaded = appState.replayLoaded
    if not replayServerMode:
      return true
    let uri = request.replayRequestUri()
    if uri.len == 0:
      if replayLoaded:
        return true
      request.respondPlain(400, "missing replay uri\n")
      return false
    var readable = false
    {.gcsafe.}:
      readable = uri.readableReplayUri()
    if not readable:
      request.respondPlain(404, "replay uri is not readable\n")
      return false
    {.gcsafe.}:
      withLock appState.lock:
        appState.pendingReplayUri = uri
    return true

  const DirectorFitSnippet = """
<script>(function(){
  // The director cut frames every shot itself, so the page must stay
  // auto-fitted. The stock viewer drops auto-fit on the first click or
  // scroll (meant for hand-panning the plain global view), which
  // freezes zoom and pan at that moment's crop - the next wide shot
  // then renders far off center, stranded in a corner. Re-arm the fit
  // after every gesture; the server ignores director clicks anyway.
  function rearm(){if(!autoFit){autoFit=true;fit();}}
  addEventListener("pointerup",rearm);
  addEventListener("wheel",rearm);
  setInterval(rearm,1000);
})();</script>
"""

  const DirectorAudioSnippet = """
<button id="hlRadio" style="position:absolute;top:12px;right:12px;z-index:40;
  font:bold 18px monospace;color:#cfc7a8;background:#2a2620;border:2px solid
  #4a4436;border-radius:8px;padding:12px 20px;cursor:pointer;opacity:0.92;">
  &#9834; sound: off</button>
<audio id="hlMusic" src="/music.m4a" loop preload="none"></audio>
<script>(function(){
  var b=document.getElementById("hlRadio"),a=document.getElementById("hlMusic");
  a.volume=0.55;var on=false;
  function setOn(next){
    on=next;
    if(on){a.play();b.innerHTML="&#9834; sound: on";
      b.style.color="#ffe9a0";b.style.borderColor="#8a7c4e";}
    else{a.pause();v.pause();
      if(inFlight>=0)lineDone(inFlight);
      b.innerHTML="&#9834; sound: off";
      b.style.color="#cfc7a8";b.style.borderColor="#4a4436";}
  }
  b.addEventListener("click",function(e){e.stopPropagation();setOn(!on);});
  // The first click or key anywhere starts the sound: the gesture the
  // browser requires, without hunting for the button.
  function firstGesture(){
    if(!on)setOn(true);
    document.removeEventListener("pointerdown",firstGesture);
    document.removeEventListener("keydown",firstGesture);
  }
  document.addEventListener("pointerdown",firstGesture);
  document.addEventListener("keydown",firstGesture);
  // Server-made voices: each new banner line arrives as a small AAC
  // clip from /voice.m4a, one macOS voice per seat. The server holds
  // the replay until /voicedone, so the next card pops when the voice
  // finishes. Music ducks while a gnome speaks.
  var v=new Audio();var last=-1;var speaking=false;var inFlight=-1;
  function lineDone(serial){
    speaking=false;inFlight=-1;a.volume=0.55;
    fetch("/voicedone?serial="+serial).catch(function(){});
  }
  window.addEventListener("pagehide",function(){
    if(inFlight>=0)navigator.sendBeacon("/voicedone?serial="+inFlight);
  });
  setInterval(function(){
    if(!on||speaking)return;
    fetch("/nowplaying").then(function(r){return r.json();})
      .then(function(d){
        if(d.serial===last||!d.text)return;
        if(last<0){last=d.serial;return;}
        last=d.serial;speaking=true;inFlight=d.serial;a.volume=0.25;
        v.src="/voice.m4a?serial="+d.serial;
        v.onended=function(){lineDone(d.serial);};
        v.onerror=function(){lineDone(d.serial);};
        v.play().catch(function(){lineDone(d.serial);});
      }).catch(function(){});
  },150);
})();</script>
"""

  const
    VoiceHoldMaxSeconds = 8.0
    VoicePacedWindowSeconds = 30.0
      ## How long after the last voice hold the show still counts as
      ## voice-paced. While voice-paced, cards live exactly as long as
      ## their spoken line; once the window lapses (the listening
      ## viewer left, or sound never started) the show falls back to
      ## the wall-clock delay-chat pacing, so muted viewers never
      ## stall.
    ## The ElevenLabs cast, seat by seat, matched to the persona souls.
    ## An empty id falls back to the macOS voice for that seat. Override
    ## with HEARTLEAF_ELEVEN_VOICES, a comma list of voice ids.
    ElevenCast = [
      "nzeAacJi50IvxcyDnMXa",  # Ivan (chatty)    - Marshal, exuberant professor
      "ouL9IsyrSnUkCmfnD02u",  # Anton (curious)  - Grimblewood, snarky gnome
      "M4zkunnpRihDKTNF0D7f",  # Yura (fatherly)  - Klaus Santa, warm and jolly
      "ZUz67EWNNT6d1i38Xmcm",  # Sasha (friendly) - Robert, warm baritone
      "LRpNiUBlcqgIsKUzcrlN",  # Maxim (funny)    - Georg, funny and emotional
      "0pkdtmrxitYBWv6q9NJO",  # Nikita (grumpy)  - Potato, deep wooden stoic
      "B52raBK48m23qWYbwchQ",  # Vova (jolly)     - Matthew Schmitz, warm teller
      "gSYqSbtMajxq5LUT0bNl",  # Dima (poet)      - Elder, epic storyteller
      "LxiqOV1uxBCgYTeitAHf"   # Egor (shy)       - Bowo, hoarse and quiet
    ]

  proc elevenKey(): string =
    ## The ElevenLabs API key: the environment first, then the key
    ## file, so the key never has to travel through a chat or a repo.
    result = getEnv("ELEVENLABS_API_KEY").strip()
    if result.len == 0:
      let keyFile = getHomeDir() / ".elevenlabs_key"
      if fileExists(keyFile):
        result = readFile(keyFile).strip()

  proc elevenVoiceFor(seat: int): string =
    ## The ElevenLabs voice id for one seat, or empty for the fallback.
    let listed = getEnv("HEARTLEAF_ELEVEN_VOICES").strip()
    if listed.len > 0:
      let ids = listed.split(',')
      if seat >= 0 and seat < ids.len:
        return ids[seat].strip()
      return ""
    if seat >= 0 and seat < ElevenCast.len:
      return ElevenCast[seat]
    ""

  proc elevenClip(seat: int, text: string): string =
    ## One spoken line from ElevenLabs as mp3 bytes, cached by voice
    ## and text so a replay costs credits once. Empty on any failure -
    ## the caller falls back to the macOS voice.
    let key = elevenKey()
    if key.len == 0:
      return ""
    let voiceId = elevenVoiceFor(seat)
    if voiceId.len == 0:
      return ""
    let cacheDir = getTempDir() / "heartleaf-eleven"
    createDir(cacheDir)
    let clipPath = cacheDir / voiceId & "-" & $abs(hash(text)) & ".mp3"
    if fileExists(clipPath):
      return readFile(clipPath)
    let bodyPath = cacheDir / "request.json"
    writeFile(bodyPath, $(%*{
      "text": text,
      "model_id": "eleven_flash_v2_5"
    }))
    discard execProcess("/usr/bin/curl", args = [
      "-s", "-f", "--max-time", "15",
      "-X", "POST",
      "https://api.elevenlabs.io/v1/text-to-speech/" & voiceId &
        "?output_format=mp3_44100_64",
      "-H", "xi-api-key: " & key,
      "-H", "Content-Type: application/json",
      "--data-binary", "@" & bodyPath,
      "-o", clipPath
    ], options = {poUsePath})
    removeFile(bodyPath)
    if fileExists(clipPath) and getFileSize(clipPath) > 500:
      return readFile(clipPath)
    if fileExists(clipPath):
      removeFile(clipPath)
    ""

  const
    VoiceCast = [
      ("Grandpa (English (US))", 185),
      ("Junior", 200),
      ("Jester", 205),
      ("Eddy (English (US))", 200),
      ("Ralph", 190),
      ("Reed (English (US))", 190),
      ("Daniel", 195),
      ("Fred", 185),
      ("Rishi", 200)
    ]

  proc serveVoiceClip(request: Request): bool =
    ## Speaks the current banner line as a small AAC clip, one voice
    ## per seat, and holds the replay until the viewer reports the
    ## line finished (or the hold times out).
    if request.path != "/voice.m4a" or request.httpMethod != "GET":
      return false
    var serial, seat: int
    var text: string
    {.gcsafe.}:
      withLock appState.lock:
        serial = appState.nowPlayingSerial
        seat = appState.nowPlayingSeat
        text = appState.nowPlayingText
    let wanted = request.queryParams.getOrDefault("serial", "").strip()
    if wanted != $serial or text.len == 0:
      request.respondPlain(409, "line has moved on\n")
      return true
    {.gcsafe.}:
      withLock appState.lock:
        appState.voiceHoldSerial = serial
        appState.voiceHoldSince = epochTime()
    let premium = elevenClip(seat, text)
    if premium.len > 0:
      var headers: HttpHeaders
      headers["Content-Type"] = "audio/mpeg"
      headers["Cache-Control"] = "no-cache"
      request.respond(200, headers, premium)
      return true
    let
      voice = VoiceCast[seat mod VoiceCast.len]
      base = getTempDir() / "heartleaf-voice-" & $serial
    discard execProcess("/usr/bin/say", args = [
      "-v", voice[0], "-r", $voice[1], "-o", base & ".aiff", text
    ], options = {poUsePath})
    discard execProcess("/usr/bin/afconvert", args = [
      "-f", "m4af", "-d", "aac", base & ".aiff", base & ".m4a"
    ], options = {poUsePath})
    if not fileExists(base & ".m4a"):
      {.gcsafe.}:
        withLock appState.lock:
          appState.voiceDoneSerial = max(appState.voiceDoneSerial, serial)
      request.respondPlain(404, "voice synthesis failed\n")
      return true
    let body = readFile(base & ".m4a")
    removeFile(base & ".aiff")
    removeFile(base & ".m4a")
    var headers: HttpHeaders
    headers["Content-Type"] = "audio/mp4"
    headers["Cache-Control"] = "no-cache"
    request.respond(200, headers, body)
    true

  proc serveVoiceDone(request: Request): bool =
    ## The viewer finished speaking one line; the replay may move on.
    if request.path != "/voicedone" or request.httpMethod != "GET":
      return false
    let serial = request.queryParams.getOrDefault("serial", "").strip()
    {.gcsafe.}:
      withLock appState.lock:
        try:
          appState.voiceDoneSerial =
            max(appState.voiceDoneSerial, parseInt(serial))
        except ValueError:
          discard
    request.respondPlain(200, "ok\n")
    true

  proc serveMusicFile(request: Request): bool =
    ## Streams the village background music. HEARTLEAF_MUSIC_FILE names a
    ## custom track when set; otherwise the placeholder loop committed in
    ## data/village_music.m4a plays, so music works out of the box.
    if request.path notin ["/music.mp3", "/music.m4a"] or
        request.httpMethod != "GET":
      return false
    var path = getEnv("HEARTLEAF_MUSIC_FILE")
    if path.len == 0 or not fileExists(path):
      path = dataDir() / "village_music.m4a"
    if not fileExists(path):
      request.respondPlain(404, "no music configured\n")
      return true
    var headers: HttpHeaders
    headers["Content-Type"] =
      if path.toLowerAscii().endsWith(".m4a"): "audio/mp4"
      else: "audio/mpeg"
    headers["Cache-Control"] = "no-cache"
    request.respond(200, headers, readFile(path))
    true

  proc httpHandler(request: Request) =
    ## Handles Heartleaf HTTP and websocket routes.
    if request.serveHealthz():
      discard
    elif request.path == WebSocketPath and request.httpMethod == "GET" and
        not request.isWebSocketUpgrade():
      request.respondPlain(426, "websocket required\n")
    elif request.path in ["/", GlobalWebSocketPath, DirectorWebSocketPath] and
        request.httpMethod == "GET" and
        not request.isWebSocketUpgrade():
      # The root and /director serve the same viewer page; the page
      # connects its websocket back to its own path, which lands in
      # the upgrade branch below and flags the viewer as a director
      # watcher. The director cut is the main page.
      if request.path != GlobalWebSocketPath and
          not request.checkReplayRequest():
        return
      if request.path != GlobalWebSocketPath:
        # Director pages (the root and the /director alias) keep the
        # stock viewer auto-fitted via the fit snippet, and get a small
        # audio layer injected, fed by /music.m4a and /voice.m4a below.
        var page = bitworldClient.clientStaticBody(
          bitworldClient.GlobalClientRoute,
          bitworldClient.GlobalClientRoute
        )
        page = page.replace("</body>", DirectorFitSnippet & "</body>")
        page = page.replace("</body>", DirectorAudioSnippet & "</body>")
        var headers: HttpHeaders
        headers["Content-Type"] = "text/html"
        headers["Cache-Control"] = "no-cache"
        request.respond(200, headers, page)
      else:
        discard bitworldClient.serveClientFile(
          request,
          bitworldClient.GlobalClientRoute,
          bitworldClient.GlobalClientRoute
        )
    elif request.serveMusicFile():
      discard
    elif request.serveVoiceClip():
      discard
    elif request.serveVoiceDone():
      discard
    elif request.path == "/nowplaying" and request.httpMethod == "GET":
      var serial, seat: int
      var text: string
      {.gcsafe.}:
        withLock appState.lock:
          serial = appState.nowPlayingSerial
          seat = appState.nowPlayingSeat
          text = appState.nowPlayingText
      var headers: HttpHeaders
      headers["Content-Type"] = "application/json"
      headers["Cache-Control"] = "no-cache"
      request.respond(200, headers,
        $(%*{"serial": serial, "seat": seat, "text": text}))
    elif request.path == ReplayWebSocketPath and request.httpMethod == "GET" and
        not request.isWebSocketUpgrade():
      if not request.checkReplayRequest():
        return
      discard bitworldClient.serveClientFile(
        request,
        bitworldClient.ReplayClientRoute,
        bitworldClient.GlobalClientRoute
      )
    elif request.path == WebSocketPath and request.httpMethod == "GET" and
        request.isWebSocketUpgrade():
      let
        slot = request.playerSlot()
        token = request.playerToken()
      var
        allowed = false
        username = ""
      {.gcsafe.}:
        withLock appState.lock:
          allowed = playerJoinAllowed(slot, token)
          username = request.playerUsername(slot)
      if not allowed:
        request.respondPlain(403, "player token rejected\n")
        return
      let websocket = request.upgradeToWebSocket()
      {.gcsafe.}:
        withLock appState.lock:
          appState.playerSlots[websocket] = slot
          appState.playerUsernames[websocket] = username
    elif request.path in ["/", GlobalWebSocketPath, DirectorWebSocketPath] and
        request.httpMethod == "GET" and
        request.isWebSocketUpgrade():
      if request.path != GlobalWebSocketPath and
          not request.checkReplayRequest():
        return
      let websocket = request.upgradeToWebSocket()
      {.gcsafe.}:
        withLock appState.lock:
          if appState.replayServerMode:
            if appState.globalViewers.len == 0 and
                appState.replayViewers.len == 0:
              appState.replayRestartPending = true
            appState.replayViewerJoined = true
          appState.globalViewers[websocket] = PlayerViewerState(
            selectedPlayerIndex: -1,
            directorMode: request.path != GlobalWebSocketPath
          )
    elif request.path == ReplayWebSocketPath and request.httpMethod == "GET" and
        request.isWebSocketUpgrade():
      if not request.checkReplayRequest():
        return
      let websocket = request.upgradeToWebSocket()
      {.gcsafe.}:
        withLock appState.lock:
          if appState.replayServerMode:
            if appState.globalViewers.len == 0 and
                appState.replayViewers.len == 0:
              appState.replayRestartPending = true
            appState.replayViewerJoined = true
          appState.replayViewers[websocket] = PlayerViewerState(
            selectedPlayerIndex: -1
          )
    elif request.path in [
        bitworldClient.ReplayClientRoute,
        bitworldClient.CoworldReplayClientRoute
      ] and request.httpMethod == "GET":
      if not request.checkReplayRequest():
        return
      discard bitworldClient.serveClientFile(
        request,
        request.path,
        bitworldClient.GlobalClientRoute
      )
    elif bitworldClient.serveClientRoute(
      request,
      bitworldClient.GlobalClientRoute
    ):
      discard
    else:
      request.respondPlain(200, "Heartleaf sprite protocol server")

  proc websocketHandler(
    websocket: WebSocket,
    event: WebSocketEvent,
    message: Message
  ) =
    ## Handles websocket ping, soul uploads, viewer clicks, and close events.
    case event
    of OpenEvent:
      discard
    of MessageEvent:
      if message.kind == Ping:
        websocket.send(message.data, Pong)
        return
      if message.kind == Pong:
        return
      if message.kind == TextMessage:
        {.gcsafe.}:
          withLock appState.lock:
            if websocket in appState.soulSockets and
                message.data.strip() == LogReadyMessage:
              # The collector is ready for the log from the beginning.
              appState.logSent[websocket] = 0
            elif websocket in appState.soulSockets and
                message.data.startsWith(LogCursorPrefix):
              # A collector that already holds part of the log says where
              # it stopped, so streaming resumes there instead of replaying.
              let cursor = parseLogCursor(message.data)
              if cursor.game == appState.gameNumber:
                appState.logSent[websocket] = max(0, cursor.sequence + 1)
              else:
                appState.logSent[websocket] = 0
            elif websocket in appState.playerSlots:
              # Reply while still holding the lock: the loop streams log
              # records under the same lock, so nothing can overtake the
              # acceptance on this socket.
              let reply = acceptSoul(websocket, message.data)
              if reply.len > 0:
                websocket.send(reply, TextMessage)
        return
      let clickedPlayer =
        if message.kind == BinaryMessage:
          message.data.globalPanelClickedPlayer()
        else:
          -1
      if clickedPlayer >= 0:
        {.gcsafe.}:
          withLock appState.lock:
            if websocket in appState.globalViewers:
              let state = appState.globalViewers[websocket]
              state.selectedPlayerIndex =
                if state.selectedPlayerIndex == clickedPlayer:
                  -1
                else:
                  clickedPlayer
            elif websocket in appState.replayViewers:
              let state = appState.replayViewers[websocket]
              state.selectedPlayerIndex =
                if state.selectedPlayerIndex == clickedPlayer:
                  -1
                else:
                  clickedPlayer
      let mapClick =
        if message.kind == BinaryMessage:
          message.data.globalMapClickAt()
        else:
          (hit: false, x: 0, y: 0)
      if mapClick.hit:
        {.gcsafe.}:
          withLock appState.lock:
            var state: PlayerViewerState
            if websocket in appState.globalViewers:
              state = appState.globalViewers[websocket]
            elif websocket in appState.replayViewers:
              state = appState.replayViewers[websocket]
            if state != nil:
              state.pendingMapClick = true
              state.pendingMapClickX = mapClick.x
              state.pendingMapClickY = mapClick.y
      if message.kind == BinaryMessage:
        {.gcsafe.}:
          withLock appState.lock:
            if appState.replayServerMode:
              if websocket in appState.replayViewers:
                appState.replayViewers[websocket].applyReplayViewerMessage(
                  message.data
                )
              elif websocket in appState.globalViewers:
                appState.globalViewers[websocket].applyReplayViewerMessage(
                  message.data
                )
      # Button masks and chat from /player sockets are ignored: souls play.
    of ErrorEvent:
      discard
    of CloseEvent:
      {.gcsafe.}:
        withLock appState.lock:
          appState.closedSockets.add(websocket)

  proc serverThreadProc(args: ServerThreadArgs) {.thread.} =
    ## Runs the mummy server on a background thread.
    args.server[].serve(Port(args.port), args.address)

  proc runFrameLimiter(previousTick: var MonoTime) =
    ## Sleeps until the next 24fps frame while waiting on LLM replies.
    ## Movement, overlay, and score ticks skip this and run as fast as
    ## the CPU can. Replays keep their own 24fps loop.
    let frameDuration = initDuration(milliseconds = int(1000.0 / TargetFps))
    let elapsed = getMonoTime() - previousTick
    if elapsed < frameDuration:
      sleep(int((frameDuration - elapsed).inMilliseconds))
    previousTick = getMonoTime()

  proc writeArtifacts(
    sim: SimServer,
    runtimeConfig: RuntimeConfig
  ) =
    ## Writes the results artifact for the current day.
    runtimeConfig.writeResults(sim.dailyResultsJson() & "\n")

  proc runServerLoop*(
    host = DefaultHost,
    port = DefaultPort,
    seed = DefaultSeed,
    maxTicks = DefaultMaxTicks,
    maxDays = 0,
    maxGames = DefaultMaxGames,
    daySeconds = DefaultDaySeconds,
    tokens: seq[string] = @[],
    playerNames: seq[string] = @[],
    soulTimeoutSeconds = DefaultSoulTimeoutSeconds,
    soulConnectionRequired = false,
    mockReply = "",
    logDir = "",
    saveReplayPath = "",
    runtimeConfig = RuntimeConfig()
  ) =
    ## Runs the Heartleaf websocket game server. A seat comes alive when its
    ## soul arrives; with tokens configured the village waits for every seat
    ## (or the soul timeout) before day 1 starts, so nobody misses a morning.
    initAppState()
    appState.tokens = tokens
    appState.playerNames = playerNames
    let dayTicks = max(1, daySeconds) * TicksPerSecond
    let totalTicks =
      if maxDays > 0:
        gameTicksForDays(maxDays, dayTicks)
      else:
        maxTicks
    let deadlineProblem = hostedDeadlineProblem(totalTicks)
    if deadlineProblem.len > 0:
      echo "fatal: ", deadlineProblem
      quit(1)
    var replayWriter = openReplayWriter(
      saveReplayPath,
      $(%*{
        "seed": seed,
        "maxTicks": totalTicks,
        "maxGames": maxGames,
        "daySeconds": daySeconds,
        "tokenCount": tokens.len
      })
    )
    var
      sim = initSimServer(seed, dayTicks)
      lastTick: MonoTime
      runTicks = 0
      gamesFinished = 0
      lastWrittenDay = 0
      seatPlayers: array[HouseCount, int]
      simStarted = tokens.len == 0
      pausedSince = 0.0
    for seat in 0 ..< HouseCount:
      seatPlayers[seat] = -1
    if tokens.len > 0:
      sim.seatCount = tokens.len
    if tokens.len > 0 and not bedrockConfigured(mockReply):
      echo "fatal: ", BedrockNotConfiguredMessage
      quit(1)
    if mockReply.len > 0:
      echo "model mocked by config: every decision is ", mockReply
    let brains = newBrains(
      sim.navigationFor(),
      sim.worldLayoutFor(),
      newBedrockClient(HouseCount, mockReply),
      seed
    )
    brains.onSeatFailure = proc(seat: int, message: string) =
      declarePlayerFailure(seat, message)
    if logDir.len > 0:
      brains.openGameLog(logDir)
      echo "game log: ", logDir / "game.log"
    # Load assets before healthz so /global can send on the first tick.
    let httpServer = newServer(
      httpHandler,
      websocketHandler,
      workerThreads = 4,
      tcpNoDelay = true
    )
    var serverThread: Thread[ServerThreadArgs]
    var serverPtr = cast[ptr Server](unsafeAddr httpServer)
    createThread(
      serverThread,
      serverThreadProc,
      ServerThreadArgs(server: serverPtr, address: host, port: port)
    )
    httpServer.waitUntilReady()
    lastTick = getMonoTime()
    let soulDeadline = epochTime() + soulTimeoutSeconds.float
    if not simStarted:
      echo "waiting for ", tokens.len, " souls (", soulTimeoutSeconds, "s)"

    proc applyUnpausedFrame(frame: BrainFrame) =
      ## Applies one unpaused brain frame and steps the sim.
      var stepInputs = newSeq[InputState](sim.players.len)
      for item in frame.outputs:
        let playerIndex = seatPlayers[item.houseIndex]
        if playerIndex < 0 or playerIndex >= stepInputs.len:
          continue
        stepInputs[playerIndex] = decodeInputMask(item.output.mask)
        replayWriter.writeInputMaskChange(
          tickTime(sim.tickCount),
          playerIndex,
          item.output.mask
        )
        let chatText = item.output.chat.cleanChatMessage()
        if chatText.len > 0:
          sim.applyPlayerChat(playerIndex, chatText)
          replayWriter.writeChat(
            tickTime(sim.tickCount),
            playerIndex,
            chatText
          )
      # Conversation enter/exit rows ride inside the replay so playback
      # can rebuild the ring timeline from the one file.
      if not brains.gameLog.isNil and
          brains.gameLog.conversationLines.len > 0:
        if replayWriter.enabled:
          for line in brains.gameLog.conversationLines:
            replayWriter.writeConversationRecord(
              tickTime(sim.tickCount), line
            )
        brains.gameLog.conversationLines.setLen(0)
      let wasScoring = sim.scoreTicks > 0
      sim.step(stepInputs)
      sim.advanceChatFeed()
      sim.publishNowPlaying()
      replayWriter.writeHash(uint32(sim.tickCount), sim.gameHash())
      if not wasScoring and sim.scoreTicks > 0:
        sim.writeArtifacts(runtimeConfig)
        lastWrittenDay = sim.dayNumber
      inc runTicks

    while true:
      var
        globalSockets: seq[WebSocket] = @[]
        globalStates: seq[PlayerViewerState] = @[]
        waitingSeats: seq[int] = @[]

      {.gcsafe.}:
        withLock appState.lock:
          for websocket in appState.closedSockets:
            if soulConnectionRequired and websocket in appState.soulSockets:
              let seat = appState.soulSockets[websocket]
              declarePlayerFailure(
                seat,
                "Seat " & $seat & " disconnected after sending its soul"
              )
            sim.removePlayer(websocket)
          appState.closedSockets.setLen(0)

          for seat, soul in appState.souls.pairs:
            if seatPlayers[seat] >= 0:
              continue
            let playerIndex = sim.addPlayer(soul.username, seat)
            if playerIndex < 0:
              continue
            seatPlayers[seat] = playerIndex
            echo "seat ", seat, " joined as ",
              sim.players[playerIndex].playerName, " (", soul.username, ")"
            brains.attachSoul(seat, soul)
            if replayWriter.enabled:
              replayWriter.writeJoin(
                tickTime(sim.tickCount),
                playerIndex,
                soul.username,
                seat,
                soul.modelId
              )
              while replayWriter.lastMasks.len < sim.players.len:
                replayWriter.lastMasks.add(0)

          if not simStarted:
            waitingSeats = seatsWaitingForSouls(tokens.len, appState.souls)

          for websocket, state in appState.globalViewers.pairs:
            globalSockets.add(websocket)
            globalStates.add(state)

      if not simStarted:
        if waitingSeats.len == 0:
          simStarted = true
          echo "all souls received, starting day 1"
        elif epochTime() >= soulDeadline:
          declarePlayerFailure(
            waitingSeats[0],
            "Seat " & $waitingSeats[0] & " sent no soul file within " &
              $soulTimeoutSeconds & "s"
          )
          echo "starting without seats ", waitingSeats.join(", ")
          simStarted = true

      var observations = initTable[int, Observation]()
      for seat in 0 ..< HouseCount:
        if seatPlayers[seat] >= 0:
          observations[seat] = sim.observe(seatPlayers[seat])
      var frame = brains.advance(observations, epochTime())
      sim.heartLinks = brains.heartPairs()
      sim.conversationCircles = brains.syncConversationCircles(
        sim.outdoorConversationFeet(seatPlayers),
        sim.outdoorConversationFeet(seatPlayers, stillOnly = true)
      )
      let paused = not simStarted or frame.paused
      if paused:
        if pausedSince == 0.0:
          pausedSince = epochTime()
          if simStarted:
            echo "sim paused: waiting on ", frame.blockedNames.join(", ")
        sim.advanceChatFeed()
        sim.publishNowPlaying()
      else:
        if pausedSince > 0.0:
          echo "sim resumed after ",
            formatFloat(epochTime() - pausedSince, ffDecimal, 1), "s"
          pausedSince = 0.0
        applyUnpausedFrame(frame)
        # Zip every sim tick until the village is waiting on an LLM
        # reply: movement, dinner overlay, and the score screen.
        while true:
          if totalTicks > 0 and runTicks >= totalTicks:
            break
          observations = initTable[int, Observation]()
          for seat in 0 ..< HouseCount:
            if seatPlayers[seat] >= 0:
              observations[seat] = sim.observe(seatPlayers[seat])
          frame = brains.advance(observations, epochTime())
          sim.conversationCircles = brains.syncConversationCircles(
            sim.outdoorConversationFeet(seatPlayers),
            sim.outdoorConversationFeet(seatPlayers, stillOnly = true)
          )
          if frame.paused:
            break
          applyUnpausedFrame(frame)

      # Stream each seat's conversation to the player that sent its soul
      # and said it is ready: system, user, and assistant turns, exactly
      # once. Batches are gathered under the lock and sent after it is
      # released so a slow socket never stalls the simulation.
      var deliveries: seq[tuple[websocket: WebSocket, batch: seq[string]]]
      {.gcsafe.}:
        withLock appState.lock:
          for websocket, seat in appState.soulSockets.pairs:
            if websocket notin appState.logSent or seat notin brains.villagers:
              continue
            let entries = brains.villagers[seat].logEntries
            let sent = appState.logSent[websocket]
            if sent < entries.len:
              deliveries.add((websocket, entries[sent ..< entries.len]))
              appState.logSent[websocket] = entries.len
      var logDrops: seq[WebSocket]
      for delivery in deliveries:
        try:
          for entry in delivery.batch:
            delivery.websocket.send(entry, TextMessage)
        except CatchableError:
          logDrops.add(delivery.websocket)
      if logDrops.len > 0:
        {.gcsafe.}:
          withLock appState.lock:
            for websocket in logDrops:
              sim.removePlayer(websocket)

      sim.updateDirectorCamera()
      for i in 0 ..< globalSockets.len:
        var nextState: PlayerViewerState
        let packet = sim.buildGlobalPacket(globalStates[i], nextState)
        try:
          globalSockets[i].sendSpritePacket(packet)
          {.gcsafe.}:
            withLock appState.lock:
              if globalSockets[i] in appState.globalViewers:
                appState.globalViewers[globalSockets[i]] = nextState
        except CatchableError:
          {.gcsafe.}:
            withLock appState.lock:
              sim.removePlayer(globalSockets[i])

      if totalTicks > 0 and runTicks >= totalTicks:
        if lastWrittenDay == 0:
          sim.writeArtifacts(runtimeConfig)
        if replayWriter.enabled:
          # Only the first game of a run is recorded and uploaded.
          replayWriter.closeReplayWriter()
          if fileExists(saveReplayPath):
            echo "Replay written: ", saveReplayPath,
              " (", getFileSize(saveReplayPath), " bytes)"
            runtimeConfig.writeReplay(readFile(saveReplayPath))
        inc gamesFinished
        if maxGames > 0 and gamesFinished >= maxGames:
          quit(0)
        sim = initSimServer(seed + gamesFinished, dayTicks)
        if tokens.len > 0:
          sim.seatCount = tokens.len
        runTicks = 0
        lastWrittenDay = 0
        for seat in 0 ..< HouseCount:
          seatPlayers[seat] = -1
        brains.resetForNewGame()
        {.gcsafe.}:
          withLock appState.lock:
            appState.gameNumber = brains.gameNumber
            resetConnectedPlayers()

      if paused:
        runFrameLimiter(lastTick)
      else:
        lastTick = getMonoTime()

proc readConfigString(node: JsonNode, name: string, value: var string) =
  ## Reads one optional string config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JString:
    raise newException(
      HeartleafError,
      "Config field " & name & " must be a string."
    )
  value = item.getStr()

proc readConfigInt(node: JsonNode, name: string, value: var int) =
  ## Reads one optional integer config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JInt:
    raise newException(
      HeartleafError,
      "Config field " & name & " must be an integer."
    )
  value = item.getInt()

proc readConfigBool(node: JsonNode, name: string, value: var bool) =
  ## Reads one optional boolean config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JBool:
    raise newException(
      HeartleafError,
      "Config field " & name & " must be a boolean."
    )
  value = item.getBool()

proc readConfigStrings(node: JsonNode, name: string, value: var seq[string]) =
  ## Reads one optional string array config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JArray:
    raise newException(
      HeartleafError,
      "Config field " & name & " must be an array."
    )
  value.setLen(0)
  for child in item.items:
    if child.kind != JString:
      raise newException(
        HeartleafError,
        "Config field " & name & " items must be strings."
      )
    value.add(child.getStr())

proc readConfigPlayerNames(node: JsonNode, value: var seq[string]) =
  ## Reads the optional Coworld `players[].name` display names by slot.
  if not node.hasKey("players"):
    return
  let item = node["players"]
  if item.kind != JArray:
    raise newException(HeartleafError, "Config field players must be an array.")
  value.setLen(0)
  for child in item.items:
    if child.kind != JObject or not child.hasKey("name") or
        child["name"].kind != JString:
      raise newException(
        HeartleafError,
        "Config field players items must be objects with a string name."
      )
    value.add(child["name"].getStr())

proc seedPinned*(configJson: string): bool =
  ## True when the runtime config pins a seed other than DefaultSeed.
  if configJson.len == 0:
    return false
  try:
    let node = parseJson(configJson)
    node.kind == JObject and node.hasKey("seed") and
      node["seed"].getInt != DefaultSeed
  except CatchableError:
    false

proc randomSeed*(): int =
  ## A crypto-random 31-bit seed from the OS.
  when defined(emscripten):
    raise newException(HeartleafError, "OS entropy source unavailable.")
  else:
    var buf: array[4, byte]
    if not urandom(buf):
      raise newException(HeartleafError, "OS entropy source unavailable.")
    (int(buf[0]) shl 24 or int(buf[1]) shl 16 or
      int(buf[2]) shl 8 or int(buf[3])) and 0x7FFF_FFFF

proc stripUnpinnedSeed*(configJson: string): string =
  ## Drops the DefaultSeed sentinel so it cannot clobber a randomized seed.
  if configJson.len == 0:
    return configJson
  try:
    let node = parseJson(configJson)
    if node.kind == JObject and node.hasKey("seed"):
      node.delete("seed")
    $node
  except CatchableError:
    configJson

proc update(config: var RunConfig, jsonText: string) =
  ## Updates the run config from a JSON object.
  if jsonText.len == 0:
    return
  var node: JsonNode
  try:
    node = fromJson(jsonText)
  except jsony.JsonError as e:
    raise newException(
      HeartleafError,
      "Could not parse config JSON: " & e.msg
    )
  if node.kind != JObject:
    raise newException(HeartleafError, "Config must be a JSON object.")
  node.readConfigString("address", config.address)
  node.readConfigInt("port", config.port)
  node.readConfigInt("seed", config.seed)
  node.readConfigInt("maxTicks", config.maxTicks)
  node.readConfigInt("max-ticks", config.maxTicks)
  node.readConfigInt("maxDays", config.maxDays)
  node.readConfigInt("maxGames", config.maxGames)
  node.readConfigInt("max-games", config.maxGames)
  node.readConfigInt("daySeconds", config.daySeconds)
  node.readConfigInt("day-seconds", config.daySeconds)
  node.readConfigInt("soulTimeoutSeconds", config.soulTimeoutSeconds)
  node.readConfigBool("soulConnectionRequired", config.soulConnectionRequired)
  node.readConfigString("mockReply", config.mockReply)
  node.readConfigString("logDir", config.logDir)
  node.readConfigString("replayPath", config.replayPath)
  node.readConfigStrings("tokens", config.tokens)
  # Seat i spawns in house i, so more tokens than houses can never all
  # join. Fewer tokens is fine: the remaining houses simply stay empty.
  if config.tokens.len > HouseCount:
    raise newException(
      HeartleafError,
      "Config field tokens lists " & $config.tokens.len &
        " seats but Heartleaf has only " & $HouseCount &
        " houses; use at most " & $HouseCount & " tokens."
    )
  node.readConfigPlayerNames(config.playerNames)

proc limitText(value: int): string =
  ## Returns a readable text value for a numeric limit.
  if value > 0:
    $value
  else:
    "infinite"

proc echoStartupConfig(config: RunConfig) =
  ## Prints the effective startup config without token secrets.
  echo "Heartleaf config: host=", config.address,
    " port=", config.port,
    " seed=", config.seed,
    " tokens=", config.tokens.len,
    " playerNames=", config.playerNames.len,
    " maxTicks=", config.maxTicks.limitText(),
    " maxDays=", config.maxDays.limitText(),
    " maxGames=", config.maxGames.limitText(),
    " daySeconds=", config.daySeconds,
    " soulTimeoutSeconds=", config.soulTimeoutSeconds,
    " soulConnectionRequired=", config.soulConnectionRequired,
    " mockReply=", (if config.mockReply.len > 0: "yes" else: "no"),
    " logDir=", (if config.logDir.len > 0: config.logDir else: "off"),
    " replayPath=", (if config.replayPath.len > 0: config.replayPath else: "off")

proc replayRunConfigFor(data: ReplayData): RunConfig =
  ## Reads the recorded simulation config from a replay header.
  result = RunConfig(
    address: DefaultHost,
    port: DefaultPort,
    seed: DefaultSeed,
    maxTicks: DefaultMaxTicks,
    maxGames: DefaultMaxGames,
    daySeconds: DefaultDaySeconds,
    tokens: @[],
    soulTimeoutSeconds: DefaultSoulTimeoutSeconds
  )
  result.update(data.configJson)

# ---------------------------------------------------------------------------
# Replay inspection (tooling)
#
# A small, read-only snapshot API for off-line replay analysis (see
# tools/expand_replay.nim). The core `Player`/`SimServer`/`Garden` fields are
# module-private, so this exposes exactly the per-tick state an analysis tool
# needs to re-simulate a replay and read out positions and events — no more.
# ---------------------------------------------------------------------------

type
  ReplayPlayerSnapshot* = object
    slot*: int                ## player index (join order == gnome slot)
    username*: string         ## connection username (varies game to game)
    playerName*: string       ## chosen display name (stable identity)
    x*, y*: int               ## foot-centre position in the CURRENT map's pixels
    direction*: string        ## "north" | "south" | "east" | "west"
    mapIndex*: int            ## 0 = main map, 1..HouseCount = a home map
    houseIndex*: int          ## -1 on the main map, else the house they are inside
    homeIndex*: int           ## the player's OWN house (0-based), -1 if unassigned
    inventory*: seq[int]      ## per-veggie carried counts (len == FoodVeggieSlots)
    inventoryTotal*: int      ## sum of `inventory`
    score*: int               ## cumulative hosting score
    message*: string          ## current chat-bubble text ("" when none)
    messageTicks*: int        ## ticks the current message has left
    dinnerCount*: int         ## number of completed dinners recorded so far
    dinnerTicks*: int         ## ticks into the current dinner (0 when not dining)
    lastDinnerHost*: string   ## host name of the most recent completed dinner
    lastDinnerWasHost*: bool  ## whether THIS player hosted that dinner
    lastDinnerGuests*: int    ## guest count of that dinner
    lastDinnerFood*: int      ## total food served at it
    lastDinnerScore*: int     ## score it awarded

  ReplayGardenSnapshot* = object
    index*: int               ## garden index (matches sim garden order)
    centerX*, centerY*: int   ## garden-rect centre in main-map pixels
    foodTotal*: int           ## total food currently available in the garden

proc replayFoodNames*(): seq[string] =
  ## Veggie names indexed by inventory slot (for naming harvest events).
  @FoodNames

proc replaySimConfig*(data: ReplayData): tuple[seed: int, dayTicks: int] =
  ## Seed + day length recorded in a replay header, ready for `initSimServer`.
  let config = data.replayRunConfigFor()
  (seed: config.seed, dayTicks: max(1, config.daySeconds) * TicksPerSecond)

proc replaySimDay*(sim: SimServer): tuple[dayNumber, dayTick, dayTicks: int] =
  ## The simulation's day-cycle position (event context).
  (dayNumber: sim.dayNumber, dayTick: sim.dayTick, dayTicks: sim.dayTicks)

proc replayDirectionName(direction: Direction): string =
  ## Human-readable facing, matching the sprite gnome labels.
  case direction
  of DirDown: "south"
  of DirUp: "north"
  of DirRight: "east"
  of DirLeft: "west"

proc snapshotReplayPlayers*(sim: SimServer): seq[ReplayPlayerSnapshot] =
  ## One snapshot per connected player at the simulation's current tick.
  result = newSeqOfCap[ReplayPlayerSnapshot](sim.players.len)
  for slot, player in sim.players:
    var inventoryTotal = 0
    for count in player.inventory:
      inventoryTotal += count
    var snapshot = ReplayPlayerSnapshot(
      slot: slot,
      username: player.username,
      playerName: player.playerName,
      x: player.x.footXAt(),
      y: player.y.footYAt(),
      direction: replayDirectionName(player.direction),
      mapIndex: player.mapIndex,
      houseIndex:
        if player.mapIndex.isHomeMap(): player.mapIndex - HomeMapIndexBase
        else: -1,
      homeIndex:
        if player.homeFlag.isHomeMap(): player.homeFlag - HomeMapIndexBase
        else: -1,
      inventory: @(player.inventory),
      inventoryTotal: inventoryTotal,
      score: player.score,
      message: player.message,
      messageTicks: player.messageTicks,
      dinnerCount: player.dinners.len,
      dinnerTicks: player.dinnerTicks
    )
    if player.dinners.len > 0:
      let dinner = player.dinners[^1]
      var foodTotal = 0
      for count in dinner.foods:
        foodTotal += count
      snapshot.lastDinnerHost = dinner.hostName
      snapshot.lastDinnerWasHost = dinner.wasHost
      snapshot.lastDinnerGuests = dinner.guestCount
      snapshot.lastDinnerFood = foodTotal
      snapshot.lastDinnerScore = dinner.score
    result.add(snapshot)

proc snapshotReplayGardens*(sim: SimServer): seq[ReplayGardenSnapshot] =
  ## One snapshot per garden at the simulation's current tick.
  result = newSeqOfCap[ReplayGardenSnapshot](sim.gardens.len)
  for index, garden in sim.gardens:
    var foodTotal = 0
    for count in garden.inventory:
      foodTotal += count
    result.add(ReplayGardenSnapshot(
      index: index,
      centerX: garden.rect.x + garden.rect.w div 2,
      centerY: garden.rect.y + garden.rect.h div 2,
      foodTotal: foodTotal
    ))

when not defined(emscripten):
  proc runReplayServerLoop*(
    host = DefaultHost,
    port = DefaultPort,
    runtimeConfig = RuntimeConfig()
  ) =
    ## Serves recorded Heartleaf replays to replay and global viewers.
    initAppState()
    appState.replayServerMode = true

    var
      replayData = ReplayData()
      replaySeed = DefaultSeed
      replayDayTicks = DefaultDaySeconds * TicksPerSecond
      replayLoaded = false
    if runtimeConfig.replay.len > 0:
      replayData = parseReplayBytes(runtimeConfig.replay)
      let replayConfig = replayData.replayRunConfigFor()
      replaySeed = replayConfig.seed
      replayDayTicks = max(1, replayConfig.daySeconds) * TicksPerSecond
      replayLoaded = true
    appState.replayLoaded = replayLoaded

    var
      sim = initSimServer(replaySeed, replayDayTicks)
      replay =
        if replayLoaded:
          initReplayPlayer(replayData)
        else:
          ReplayPlayer()
      lastTick: MonoTime
    if replayLoaded:
      sim.attachConversationTimeline(replayData, cliLoadReplayPath())
      replay.buildReplayKeyframes(replaySeed, replayDayTicks)
      sim.buildConversationQueue(replay.replayMaxTick())
    # The server holds paused on the final tick instead of looping, so
    # a page load never lands mid-recording; "r" re-enables looping.
    replay.looping = false
    # Load assets before healthz so replay viewers get frames immediately.
    let httpServer = newServer(
      httpHandler,
      websocketHandler,
      workerThreads = 4,
      tcpNoDelay = true
    )
    var serverThread: Thread[ServerThreadArgs]
    var serverPtr = cast[ptr Server](unsafeAddr httpServer)
    createThread(
      serverThread,
      serverThreadProc,
      ServerThreadArgs(server: serverPtr, address: host, port: port)
    )
    httpServer.waitUntilReady()
    lastTick = getMonoTime()
    var
      directorShowAccum = 0
      lastSeekSerial = replay.seekSerial

    while true:
      var
        pendingReplayUri = ""
        viewerSockets: seq[WebSocket] = @[]
        viewerStates: seq[PlayerViewerState] = @[]
        viewerIsReplay: seq[bool] = @[]
        seekTicks: seq[int] = @[]
        commands: seq[char] = @[]
        restartPending = false
        viewerJoined = false

      {.gcsafe.}:
        withLock appState.lock:
          pendingReplayUri = appState.pendingReplayUri
          appState.pendingReplayUri = ""
          restartPending = appState.replayRestartPending
          appState.replayRestartPending = false
          viewerJoined = appState.replayViewerJoined
          appState.replayViewerJoined = false
          for websocket in appState.closedSockets:
            sim.removePlayer(websocket)
          appState.closedSockets.setLen(0)

      var
        voiceHolding = false
        voicePaced = false
        voiceSpeaking = false
        voiceLineDone = false
        restartShow = false
      {.gcsafe.}:
        withLock appState.lock:
          let voiceNow = epochTime()
          voiceHolding =
            appState.voiceHoldSerial > appState.voiceDoneSerial and
            voiceNow - appState.voiceHoldSince < VoiceHoldMaxSeconds
          # Voice-paced means some viewer spoke a line recently; the
          # cards then live exactly as long as their voices.
          voicePaced = appState.voiceHoldSerial > 0 and
            voiceNow - appState.voiceHoldSince < VoicePacedWindowSeconds
          voiceSpeaking = voiceHolding and
            appState.voiceHoldSerial == appState.nowPlayingSerial
          voiceLineDone =
            appState.voiceHoldSerial == appState.nowPlayingSerial and
            appState.voiceDoneSerial >= appState.voiceHoldSerial
          restartShow = appState.replayRestartPending
          appState.replayRestartPending = false
      if restartShow and replayLoaded and replay.replayMaxTick() > 0:
        replay.seekReplay(sim, 0)
        replay.playing = true

      if pendingReplayUri.len > 0:
        try:
          replayData = loadReplayUri(pendingReplayUri)
          let replayConfig = replayData.replayRunConfigFor()
          replaySeed = replayConfig.seed
          replayDayTicks = max(1, replayConfig.daySeconds) * TicksPerSecond
          sim = initSimServer(replaySeed, replayDayTicks)
          sim.attachConversationTimeline(
            replayData, replayFilePath(pendingReplayUri)
          )
          replay = initReplayPlayer(replayData)
          replay.buildReplayKeyframes(replaySeed, replayDayTicks)
          sim.buildConversationQueue(replay.replayMaxTick())
          replay.looping = false
          replayLoaded = true
          {.gcsafe.}:
            withLock appState.lock:
              appState.replayLoaded = true
        except CatchableError as e:
          echo "Could not load replay uri: ", e.msg

      {.gcsafe.}:
        withLock appState.lock:
          for websocket, state in appState.replayViewers.pairs:
            viewerSockets.add(websocket)
            viewerStates.add(state)
            viewerIsReplay.add(true)
            state.drainReplayViewerInput(
              replay.replayMaxTick(),
              seekTicks,
              commands
            )
          for websocket, state in appState.globalViewers.pairs:
            viewerSockets.add(websocket)
            viewerStates.add(state)
            viewerIsReplay.add(false)
            state.drainReplayViewerInput(
              replay.replayMaxTick(),
              seekTicks,
              commands
            )

      if replayLoaded:
        # A fresh viewer restarts playback from tick zero when nobody
        # was watching, or when playback already ran to the end.
        if restartPending or
            (viewerJoined and sim.tickCount >= replay.replayMaxTick()):
          sim.restartConversationQueue()
          replay.seekReplay(sim, 0)
          replay.playing = true
        for seekTick in seekTicks:
          replay.applyReplaySeek(sim, seekTick)
        for command in commands:
          replay.applyReplayCommand(sim, command)
        if replay.playing:
          # Queue-mode bookkeeping: commit at births, release at
          # deaths, rewind through same-tick birth groups, resume
          # from the furthest tick shown.
          sim.stepConversationQueue(replay)
          # With a director watching, a conversation on screen slows
          # 1X playback to show pacing: recorded lines land about five
          # seconds apart. Other speeds respect the transport.
          var directorWatching = false
          for state in viewerStates:
            if state.directorMode:
              directorWatching = true
              break
          let showPacing = directorWatching and
            (sim.directorFocusActive or sim.directorDinnerTtl > 0) and
            replay.replaySpeedIndex() == DefaultSpeedIndex
          var ticksThisFrame = 0
          if showPacing:
            inc directorShowAccum
            if directorShowAccum >= DirectorShowFrames:
              directorShowAccum = 0
              ticksThisFrame = 1
          else:
            directorShowAccum = 0
            ticksThisFrame = replay.replayTicksThisFrame()
          # Between conversations the queue's playhead fast-forwards
          # briskly to the next birth; committed playback never runs
          # past its item's death tick. The clamps land the playhead
          # exactly on each boundary.
          if sim.convQueue.len > 0:
            if not sim.convQueueCommitted and
                replay.replaySpeedIndex() == DefaultSpeedIndex:
              ticksThisFrame = QueueFastForwardTicks
            if sim.convQueueCommitted:
              ticksThisFrame = min(ticksThisFrame, max(0,
                sim.convQueue[sim.convQueueIndex].deathTick - sim.tickCount))
            elif sim.convQueueIndex < sim.convQueue.len:
              ticksThisFrame = min(ticksThisFrame, max(0,
                sim.convQueue[sim.convQueueIndex].birthTick - sim.tickCount))
          # A camera glide is a held breath: at show speed the replay
          # pauses until the shot settles, so cuts never swallow lines.
          if directorWatching and sim.directorTweenLeft > 0 and
              replay.replaySpeedIndex() == DefaultSpeedIndex:
            ticksThisFrame = 0
          # While a viewer speaks the current line aloud, the show
          # waits: no ticks, so the next card pops when the voice ends.
          if voiceHolding:
            ticksThisFrame = 0
          for _ in 0 ..< ticksThisFrame:
            if replay.playing:
              replay.stepReplay(sim)
          if replay.looping and not replay.playing and
              replay.replayMaxTick() > 0:
            sim.restartConversationQueue()
            replay.seekReplay(sim, 0)
            replay.playing = true
      # Any seek strands a viewer mid-line: the clip it is speaking
      # belongs to a feed that no longer exists, and its voicedone
      # would otherwise be the only thing releasing the hold. Release
      # it here so a queue rewind, a next/prev jump, or a scrub never
      # freezes the show for the full hold timeout; the stale clip
      # plays out client-side and its late voicedone lands harmlessly.
      if replay.seekSerial != lastSeekSerial:
        lastSeekSerial = replay.seekSerial
        {.gcsafe.}:
          withLock appState.lock:
            if appState.voiceHoldSerial > appState.voiceDoneSerial:
              appState.voiceDoneSerial = appState.voiceHoldSerial
      # Rings always come from the production path - the conversation
      # timeline's frozen anchors, or the huddle fallback - so replays
      # look exactly like live play. Raw recorded circle rows (the old
      # 0.1.x format) stay readable for tooling but no longer drive
      # rendering: they move with the gnomes, which prod rings do not.
      sim.inferConversationCircles()
      if not voiceHolding:
        if voicePaced:
          # The card left with its voice; bring up the next line as
          # soon as the release lands. A line whose voice never
          # started (the viewer left, or synthesis failed silently)
          # falls forward on the hold timeout instead of stalling.
          if voiceLineDone or
              epochTime() - sim.chatFeedShownAt >= VoiceHoldMaxSeconds:
            sim.advanceChatFeedNow()
        else:
          sim.advanceChatFeed()
      sim.directorCardLive = not voicePaced or voiceSpeaking
      sim.publishNowPlaying()
      sim.updateDirectorCamera()

      for i in 0 ..< viewerSockets.len:
        var nextState: PlayerViewerState
        let packet = sim.buildGlobalPacket(
          viewerStates[i],
          nextState,
          replayControls = replayLoaded,
          replayTick = sim.tickCount,
          replaySpeedIndex = replay.replaySpeedIndex(),
          replayMaxTick = replay.replayMaxTick(),
          replayPlaying = replay.playing,
          replayLooping = replay.looping,
          replayMismatchTick = replay.hashMismatchTick
        )
        try:
          viewerSockets[i].sendSpritePacket(packet)
          {.gcsafe.}:
            withLock appState.lock:
              if viewerIsReplay[i]:
                if viewerSockets[i] in appState.replayViewers:
                  appState.replayViewers[viewerSockets[i]] = nextState
              elif viewerSockets[i] in appState.globalViewers:
                appState.globalViewers[viewerSockets[i]] = nextState
        except CatchableError:
          {.gcsafe.}:
            withLock appState.lock:
              sim.removePlayer(viewerSockets[i])

      runFrameLimiter(lastTick)

when isMainModule and not defined(emscripten):
  let runtimeConfig = readRuntimeConfig()
  var
    config = RunConfig(
      address: runtimeConfig.host,
      port: runtimeConfig.port,
      seed: DefaultSeed,
      maxTicks: DefaultMaxTicks,
      maxGames: DefaultMaxGames,
      daySeconds: DefaultDaySeconds,
      tokens: @[],
      soulTimeoutSeconds: DefaultSoulTimeoutSeconds
    )
  if seedPinned(runtimeConfig.config):
    config.update(runtimeConfig.config)
  else:
    config.seed = randomSeed()
    config.update(stripUnpinnedSeed(runtimeConfig.config))
    echo "seed not pinned; randomized"
  config.echoStartupConfig()
  if runtimeConfig.resultsUri.len > 0:
    echo "Using results target: " & runtimeConfig.resultsUri
  if runtimeConfig.replayUri.len > 0:
    echo "Using replay target: " & runtimeConfig.replayUri
  if runtimeConfig.replayMode:
    runReplayServerLoop(config.address, config.port, runtimeConfig)
    quit(0)
  let localReplayPath =
    if config.replayPath.len > 0:
      config.replayPath
    elif runtimeConfig.replayUri.len > 0:
      getTempDir() / ("heartleaf-replay-" & $getCurrentProcessId() &
        ".bitreplay")
    else:
      ""
  runServerLoop(
    config.address,
    config.port,
    seed = config.seed,
    maxTicks = config.maxTicks,
    maxDays = config.maxDays,
    maxGames = config.maxGames,
    daySeconds = config.daySeconds,
    tokens = config.tokens,
    playerNames = config.playerNames,
    soulTimeoutSeconds = config.soulTimeoutSeconds,
    soulConnectionRequired = config.soulConnectionRequired,
    mockReply = config.mockReply,
    logDir = config.logDir,
    saveReplayPath = localReplayPath,
    runtimeConfig = runtimeConfig
  )
