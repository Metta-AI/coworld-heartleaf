## Presentation geometry. World coordinates and gameplay stay unchanged.
import std/math

const
  ViewerBorder* = 10
  ViewerCardWidth* = 188
  ViewerRailWidth* = 150

type
  ViewerRect* = object
    x*, y*, width*, height*: int
  ViewerLayout* = object
    width*, height*, x*, y*: int
    canvasWidth*, canvasHeight*: int
    scene*, card*, stage*: ViewerRect
    railWidth*: int

proc frameLayout*(
  cropX, cropY, cropWidth, cropHeight: float,
  frameWidth, frameHeight: int,
  hasPlayers, replayControls: bool,
  cardHeight = 0,
  conversation = false,
  worldWidth = 0, worldHeight = 0,
  focusBlend = 1.0, overviewAspect = 0.0, sidebars = false
): ViewerLayout =
  ## Center the village on the window, keeping clear of the optional leaderboard.
  ## Conversation shots fill the window, hide the rail and overlay the cards.
  let
    fw = float(if frameWidth > 0: frameWidth else: 1280)
    fh = float(if frameHeight > 0: frameHeight else: 720)
  var uiZoom = 1.0
  for zoom in countdown(3, 2):
    if fw >= 320.0 * float(zoom) * 1.5 and
        fh >= 128.0 * float(zoom) * 1.5:
      uiZoom = float(zoom)
      break
  if sidebars and fw < 1800 and uiZoom > 2: uiZoom = 2
  result.canvasWidth = int(fw / uiZoom)
  result.canvasHeight = int(fh / uiZoom)
  let
    cw = result.canvasWidth
    ch = result.canvasHeight
    bottom = if replayControls: 50 else: 8
    overviewRail = if sidebars and cw >= 600 and cw > ch: ViewerRailWidth else: 0
    rail = if conversation: 0 else: overviewRail
    sw = cw - rail
  result.railWidth = rail
  result.stage = ViewerRect(x: rail, width: sw, height: ch)
  if conversation:
    result.scene = ViewerRect(x: rail, width: sw, height: ch)
    let blend = clamp(focusBlend, 0.0, 1.0)
    if blend == 0 and worldWidth > 0:
      return frameLayout(cropX,cropY,cropWidth,cropHeight,
        frameWidth,frameHeight,hasPlayers,replayControls, sidebars = sidebars)
    var boundsWidth = float(worldWidth)
    if worldWidth > 0 and worldHeight > 0:
      # Interpolate the visible frame as well as the camera crop. Switching
      # directly to a full-window frame would force an instant zoom just
      # to keep that wider rectangle inside the map.
      let wideWidth = max(float(worldWidth), float(worldHeight) * overviewAspect)
      let overviewStage = cw - overviewRail
      let wideScale = min(float(overviewStage - ViewerBorder * 2) / wideWidth,
        float(ch - ViewerBorder * 2) / float(worldHeight))
      let wideW = int(round(wideWidth * wideScale)) + ViewerBorder * 2
      let wideH = int(round(float(worldHeight) * wideScale)) + ViewerBorder * 2
      result.scene.width = int(round(float(wideW) + float(sw - wideW) * blend))
      result.scene.height = int(round(float(wideH) + float(ch - wideH) * blend))
      let wideX = max(overviewRail, (cw - wideW) div 2)
      result.scene.x = int(round(float(wideX) * (1.0 - blend)))
      result.scene.y = (ch - result.scene.height) div 2
      boundsWidth = wideWidth + (float(worldWidth) - wideWidth) * blend
    let
      innerWidth = float(result.scene.width - ViewerBorder * 2)
      # A room's circular exterior must remain wholly visible above
      # the transport even though its surrounding frame is full-screen.
      roomTransport = if worldHeight == 0 and replayControls: 50 else: 0
      innerHeight = float(result.scene.height - ViewerBorder * 2 - roomTransport)
    var scale = min(innerWidth / max(1.0, cropWidth),
      innerHeight / max(1.0, cropHeight))
    # Near a village edge, pan within the actual art. Very wide
    # windows may need a tighter crop to avoid exposing empty space.
    if worldWidth > 0: scale = max(scale, innerWidth / boundsWidth)
    if worldHeight > 0: scale = max(scale, innerHeight / float(worldHeight))
    scale = max(scale, max(float(cw), float(ch)) / 8192.0)
    # The protocol uses integer viewport sizes. Round inward and use the
    # resulting scale for bounds, so an ultrawide viewport cannot expose
    # artwork beyond the edge through accumulated rounding error.
    result.width = max(1, int(floor(float(cw) / scale)))
    result.height = max(1, int(floor(float(ch) / scale)))
    scale = min(float(cw) / float(result.width), float(ch) / float(result.height))
    var
      left = cropX + cropWidth / 2 - innerWidth / scale / 2
      top = cropY + cropHeight / 2 - innerHeight / scale / 2
    if worldWidth > 0:
      let minX = (float(worldWidth) - boundsWidth) / 2
      left = clamp(left, minX, minX + max(0.0, boundsWidth - innerWidth / scale))
    if worldHeight > 0: top = clamp(top, 0.0, max(0.0, float(worldHeight) - innerHeight / scale))
    result.x = int(round(left - float(result.scene.x + ViewerBorder) / scale))
    result.y = int(round(top - float(result.scene.y + ViewerBorder) / scale))
    if cardHeight > 0:
      result.card = ViewerRect(width: ViewerCardWidth, height: cardHeight,
        x: rail + (sw - ViewerCardWidth) div 2,
        y: ch - bottom - cardHeight - 4)
    return
  let
    availableWidth = max(32, sw)
    availableHeight = max(32, ch)
  let
    scale = max(max(float(cw), float(ch)) / 8192.0,
      min(float(max(1, availableWidth - ViewerBorder * 2)) / max(1.0, cropWidth),
        float(max(1, availableHeight - ViewerBorder * 2)) / max(1.0, cropHeight)))
    sceneWidth = int(round(cropWidth * scale)) + ViewerBorder * 2
    sceneHeight = int(round(cropHeight * scale)) + ViewerBorder * 2
  result.scene = ViewerRect(
    x: max(rail, (cw - sceneWidth) div 2),
    y: (availableHeight - sceneHeight) div 2,
    width: sceneWidth, height: sceneHeight)
  result.width = max(1, int(ceil(float(cw) / scale)))
  result.height = max(1, int(ceil(float(ch) / scale)))
  result.x = int(round(cropX - float(result.scene.x + ViewerBorder) / scale))
  result.y = int(round(cropY - float(result.scene.y + ViewerBorder) / scale))
