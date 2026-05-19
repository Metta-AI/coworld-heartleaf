import
  std/[algorithm, os],
  pixie, zippy,
  heartleaf/protocol

type
  AsepriteError* = object of ValueError
    ## Raised when an aseprite file cannot be decoded.

  AsepriteColorDepth* = enum
    DepthIndexed = 8
    DepthGrayscale = 16
    DepthRgba = 32

  AsepriteLayerKind* = enum
    LayerNormal
    LayerGroup
    LayerTilemap

  Facing* = enum
    FaceUp
    FaceDown
    FaceLeft
    FaceRight

  AsepriteCelKind* = enum
    CelRaw
    CelLinked
    CelCompressed
    CelTilemap

  AsepriteHeader* = object
    fileSize*, frameCount*, width*, height*: int
    colorDepth*: AsepriteColorDepth
    flags*, speed*: int
    transparentIndex*, colorCount*: int
    pixelWidth*, pixelHeight*: int
    gridX*, gridY*, gridWidth*, gridHeight*: int

  AsepriteLayer* = object
    flags*, childLevel*, blendMode*, opacity*: int
    kind*: AsepriteLayerKind
    name*: string
    tilesetIndex*: int
    uuid*: array[16, uint8]

  AsepriteCel* = object
    layerIndex*, x*, y*, opacity*, zIndex*: int
    kind*: AsepriteCelKind
    width*, height*: int
    linkedFrame*: int
    data*: seq[uint8]

  AsepriteFrame* = object
    duration*: int
    cels*: seq[AsepriteCel]

  AsepriteSprite* = object
    header*: AsepriteHeader
    layers*: seq[AsepriteLayer]
    frames*: seq[AsepriteFrame]
    palette*: seq[ColorRGBA]
    hasNewPalette: bool

  RgbaSprite* = object
    ## A simple 32-bit RGBA sprite used by the sprite protocol.
    width*, height*: int
    pixels*: seq[uint8]

  Sprite* = object
    ## A palette-indexed sprite used by the legacy framebuffer protocol.
    width*, height*: int
    pixels*: seq[uint8]

  Framebuffer* = object
    ## A packed 4-bit framebuffer for the legacy protocol.
    indices*: seq[uint8]
    packed*: seq[uint8]

const
  HeaderMagic = 0xA5E0
  FrameMagic = 0xF1FA
  ChunkOldPaletteShort = 0x0004
  ChunkOldPaletteLong = 0x0011
  ChunkLayer = 0x2004
  ChunkCel = 0x2005
  ChunkPalette = 0x2019
  HeaderBytes = 128
  FrameHeaderBytes = 16
  TransparentColorIndex* = 255'u8

proc newRgbaSprite*(width, height: int): RgbaSprite =
  ## Allocates one transparent RGBA sprite.
  result.width = width
  result.height = height
  result.pixels = newSeq[uint8](width * height * 4)

proc transparentRgbaSprite*(width, height: int): RgbaSprite =
  ## Builds one fully transparent RGBA sprite.
  newRgbaSprite(width, height)

proc pixelOffset*(sprite: RgbaSprite, x, y: int): int =
  ## Returns one RGBA byte offset inside a sprite.
  (y * sprite.width + x) * 4

proc putPixel*(sprite: var RgbaSprite, x, y: int, color: ColorRGBA) =
  ## Writes one RGBA pixel into a sprite.
  if x < 0 or y < 0 or x >= sprite.width or y >= sprite.height:
    return
  let offset = sprite.pixelOffset(x, y)
  sprite.pixels[offset] = color.r
  sprite.pixels[offset + 1] = color.g
  sprite.pixels[offset + 2] = color.b
  sprite.pixels[offset + 3] = color.a

proc pixelsMatch*(a, b: openArray[uint8]): bool =
  ## Returns true when two RGBA pixel payloads match.
  if a.len != b.len:
    return false
  for i in 0 ..< a.len:
    if a[i] != b[i]:
      return false
  true

proc copyPixels*(pixels: openArray[uint8]): seq[uint8] =
  ## Copies one RGBA pixel payload.
  result = newSeq[uint8](pixels.len)
  for i in 0 ..< pixels.len:
    result[i] = pixels[i]

proc imageRgbaSprite*(image: Image): RgbaSprite =
  ## Converts a Pixie image to an RGBA sprite.
  result = newRgbaSprite(image.width, image.height)
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      result.putPixel(x, y, image[x, y])

proc cellRgbaSprite*(image: Image, cellX, cellY, size: int): RgbaSprite =
  ## Slices one square cell from a Pixie image.
  result = newRgbaSprite(size, size)
  let
    baseX = cellX * size
    baseY = cellY * size
  for y in 0 ..< size:
    for x in 0 ..< size:
      result.putPixel(x, y, image[baseX + x, baseY + y])

proc drawHorizontal*(
  sprite: var RgbaSprite,
  x0, x1, y: int,
  color: ColorRGBA
) =
  ## Draws one clipped horizontal stroke.
  if y < 0 or y >= sprite.height:
    return
  let
    left = max(0, min(x0, x1))
    right = min(sprite.width - 1, max(x0, x1))
  if left > right:
    return
  for x in left .. right:
    sprite.putPixel(x, y, color)

proc drawVertical*(
  sprite: var RgbaSprite,
  x, y0, y1: int,
  color: ColorRGBA
) =
  ## Draws one clipped vertical stroke.
  if x < 0 or x >= sprite.width:
    return
  let
    top = max(0, min(y0, y1))
    bottom = min(sprite.height - 1, max(y0, y1))
  if top > bottom:
    return
  for y in top .. bottom:
    sprite.putPixel(x, y, color)

proc fillRect*(
  sprite: var RgbaSprite,
  x, y, width, height: int,
  color: ColorRGBA
) =
  ## Draws one clipped filled rectangle into a sprite.
  if width <= 0 or height <= 0:
    return
  let
    left = max(0, x)
    top = max(0, y)
    right = min(sprite.width, x + width)
    bottom = min(sprite.height, y + height)
  if left >= right or top >= bottom:
    return
  for py in top ..< bottom:
    for px in left ..< right:
      sprite.putPixel(px, py, color)

proc strokeRect*(
  sprite: var RgbaSprite,
  x, y, width, height: int,
  color: ColorRGBA
) =
  ## Draws one rectangle outline into a sprite.
  if width <= 0 or height <= 0:
    return
  let
    x1 = x + width - 1
    y1 = y + height - 1
  sprite.drawHorizontal(x, x1, y, color)
  sprite.drawHorizontal(x, x1, y1, color)
  sprite.drawVertical(x, y, y1, color)
  sprite.drawVertical(x1, y, y1, color)

proc spriteIndex*(sprite: Sprite, x, y: int): int =
  ## Returns one pixel index inside a palette-indexed sprite.
  y * sprite.width + x

proc nearestPaletteIndex*(pixel: ColorRGBA): uint8 =
  ## Returns the closest legacy palette color index for one RGBA pixel.
  if pixel.a < 20'u8:
    return TransparentColorIndex

  var best = 0
  var bestDistance = high(int)
  for index in 0 ..< Palette.len:
    let
      candidate = Palette[index]
      dr = int(pixel.r) - int(candidate.r)
      dg = int(pixel.g) - int(candidate.g)
      db = int(pixel.b) - int(candidate.b)
      da = int(pixel.a) - int(candidate.a)
      distance = dr * dr + dg * dg + db * db + da * da
    if distance < bestDistance:
      bestDistance = distance
      best = index
  best.uint8

proc spriteFromImage*(image: Image): Sprite =
  ## Converts one Pixie image to a palette-indexed sprite.
  result.width = image.width
  result.height = image.height
  result.pixels = newSeq[uint8](result.width * result.height)
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      result.pixels[result.spriteIndex(x, y)] =
        nearestPaletteIndex(image[x, y])

proc sliceSpriteStrip*(
  image: Image,
  spriteWidth,
  spriteHeight,
  count: int
): seq[Sprite] =
  ## Slices a horizontal palette-indexed sprite strip.
  for i in 0 ..< count:
    var sprite = Sprite(width: spriteWidth, height: spriteHeight)
    sprite.pixels = newSeq[uint8](spriteWidth * spriteHeight)
    let baseX = i * spriteWidth
    for y in 0 ..< spriteHeight:
      for x in 0 ..< spriteWidth:
        sprite.pixels[sprite.spriteIndex(x, y)] =
          nearestPaletteIndex(image[baseX + x, y])
    result.add(sprite)

proc readRequiredSprite*(path: string): Sprite
    {.raises: [IOError, PixieError].} =
  ## Reads one required palette-indexed sprite image from disk.
  if not fileExists(path):
    raise newException(IOError, "Missing sprite asset: " & path)
  spriteFromImage(readImage(path))

proc initFramebuffer*(): Framebuffer =
  ## Allocates one legacy framebuffer.
  result.indices = newSeq[uint8](ScreenWidth * ScreenHeight)
  result.packed = newSeq[uint8](ProtocolBytes)

proc clearFrame*(fb: var Framebuffer, bg: uint8 = 3) =
  ## Fills one framebuffer with a palette color index.
  for i in 0 ..< fb.indices.len:
    fb.indices[i] = bg

proc putPixel*(fb: var Framebuffer, x, y: int, index: uint8) =
  ## Writes one palette color index into a framebuffer.
  if x < 0 or y < 0 or
      x >= ScreenWidth or y >= ScreenHeight or
      index == TransparentColorIndex:
    return
  fb.indices[y * ScreenWidth + x] = index

proc blitSprite*(
  fb: var Framebuffer,
  sprite: Sprite,
  worldX,
  worldY,
  cameraX,
  cameraY: int,
  facing = FaceDown
) =
  ## Blits one palette-indexed sprite into a framebuffer.
  let
    screenX = worldX - cameraX
    screenY = worldY - cameraY
  for y in 0 ..< sprite.height:
    for x in 0 ..< sprite.width:
      let colorIndex = sprite.pixels[sprite.spriteIndex(x, y)]
      if colorIndex == TransparentColorIndex:
        continue
      var
        dx = 0
        dy = 0
      case facing
      of FaceDown:
        dx = x
        dy = y
      of FaceUp:
        dx = sprite.width - 1 - x
        dy = sprite.height - 1 - y
      of FaceLeft:
        dx = y
        dy = sprite.width - 1 - x
      of FaceRight:
        dx = sprite.height - 1 - y
        dy = x
      fb.putPixel(screenX + dx, screenY + dy, colorIndex)

proc blitSpriteTinted*(
  fb: var Framebuffer,
  sprite: Sprite,
  worldX,
  worldY,
  cameraX,
  cameraY: int,
  tint: uint8,
  facing = FaceDown
) =
  ## Blits one palette-indexed sprite as a single palette color.
  let
    screenX = worldX - cameraX
    screenY = worldY - cameraY
  for y in 0 ..< sprite.height:
    for x in 0 ..< sprite.width:
      let colorIndex = sprite.pixels[sprite.spriteIndex(x, y)]
      if colorIndex == TransparentColorIndex:
        continue
      var
        dx = 0
        dy = 0
      case facing
      of FaceDown:
        dx = x
        dy = y
      of FaceUp:
        dx = sprite.width - 1 - x
        dy = sprite.height - 1 - y
      of FaceLeft:
        dx = y
        dy = sprite.width - 1 - x
      of FaceRight:
        dx = sprite.height - 1 - y
        dy = x
      fb.putPixel(screenX + dx, screenY + dy, tint)

proc packFramebuffer*(fb: var Framebuffer) =
  ## Packs two 4-bit palette pixels into each protocol byte.
  for i in 0 ..< fb.packed.len:
    let
      lo = fb.indices[i * 2] and 0x0f
      hi = fb.indices[i * 2 + 1] and 0x0f
    fb.packed[i] = lo or (hi shl 4)

proc fail(message: string) {.raises: [AsepriteError].} =
  ## Raises a formatted aseprite decoder error.
  raise newException(AsepriteError, message)

proc ensure(data: string, pos, bytes: int) {.raises: [AsepriteError].} =
  ## Ensures that a read can consume bytes from the buffer.
  if bytes < 0 or pos < 0 or pos + bytes > data.len:
    fail("Invalid aseprite data, unexpected end of file")

proc readU8(data: string, pos: var int): int {.raises: [AsepriteError].} =
  ## Reads one unsigned byte.
  data.ensure(pos, 1)
  result = ord(data[pos])
  inc pos

proc readU16(data: string, pos: var int): int {.raises: [AsepriteError].} =
  ## Reads one little-endian unsigned word.
  data.ensure(pos, 2)
  result = ord(data[pos]) or (ord(data[pos + 1]) shl 8)
  pos += 2

proc readI16(data: string, pos: var int): int {.raises: [AsepriteError].} =
  ## Reads one little-endian signed short.
  let value = data.readU16(pos)
  if value >= 0x8000:
    result = value - 0x10000
  else:
    result = value

proc readU32(data: string, pos: var int): int {.raises: [AsepriteError].} =
  ## Reads one little-endian unsigned dword.
  data.ensure(pos, 4)
  result =
    ord(data[pos]) or
    (ord(data[pos + 1]) shl 8) or
    (ord(data[pos + 2]) shl 16) or
    (ord(data[pos + 3]) shl 24)
  pos += 4

proc readString(
  data: string,
  pos: var int
): string {.raises: [AsepriteError].} =
  ## Reads an aseprite length-prefixed UTF-8 string.
  let len = data.readU16(pos)
  data.ensure(pos, len)
  result = data[pos ..< pos + len]
  pos += len

proc skipTo(pos: var int, target: int) {.raises: [AsepriteError].} =
  ## Moves the stream position to an already validated target.
  if target < pos:
    fail("Invalid aseprite data, chunk reader passed its boundary")
  pos = target

proc defaultPalette(): seq[ColorRGBA] {.raises: [].} =
  ## Creates a transparent palette used before palette chunks are read.
  result = newSeq[ColorRGBA](256)
  for i in 0 ..< result.len:
    result[i] = rgba(0, 0, 0, 0)

proc parseHeader(data: string, pos: var int): AsepriteHeader
    {.raises: [AsepriteError].} =
  ## Reads the fixed 128-byte aseprite header.
  data.ensure(pos, HeaderBytes)
  let start = pos
  result.fileSize = data.readU32(pos)
  if data.readU16(pos) != HeaderMagic:
    fail("Invalid aseprite magic number")
  result.frameCount = data.readU16(pos)
  result.width = data.readU16(pos)
  result.height = data.readU16(pos)
  if result.width <= 0 or result.height <= 0:
    fail("Invalid aseprite dimensions")
  let depth = data.readU16(pos)
  case depth
  of 8:
    result.colorDepth = DepthIndexed
  of 16:
    result.colorDepth = DepthGrayscale
  of 32:
    result.colorDepth = DepthRgba
  else:
    fail("Unsupported aseprite color depth: " & $depth)
  result.flags = data.readU32(pos)
  result.speed = data.readU16(pos)
  discard data.readU32(pos)
  discard data.readU32(pos)
  result.transparentIndex = data.readU8(pos)
  pos += 3
  result.colorCount = data.readU16(pos)
  if result.colorCount == 0:
    result.colorCount = 256
  result.pixelWidth = data.readU8(pos)
  result.pixelHeight = data.readU8(pos)
  result.gridX = data.readI16(pos)
  result.gridY = data.readI16(pos)
  result.gridWidth = data.readU16(pos)
  result.gridHeight = data.readU16(pos)
  pos.skipTo(start + HeaderBytes)

proc bytesPerPixel(depth: AsepriteColorDepth): int {.raises: [].} =
  ## Returns the byte width of one decoded cel pixel.
  case depth
  of DepthIndexed:
    1
  of DepthGrayscale:
    2
  of DepthRgba:
    4

proc visible(layer: AsepriteLayer): bool {.raises: [].} =
  ## Checks whether a layer is visible.
  (layer.flags and 1) != 0

proc parseLayer(
  data: string,
  pos: var int,
  chunkEnd: int,
  header: AsepriteHeader
): AsepriteLayer {.raises: [AsepriteError].} =
  ## Reads a layer chunk.
  result.flags = data.readU16(pos)
  let kind = data.readU16(pos)
  case kind
  of 0:
    result.kind = LayerNormal
  of 1:
    result.kind = LayerGroup
  of 2:
    result.kind = LayerTilemap
  else:
    fail("Unsupported aseprite layer type: " & $kind)
  result.childLevel = data.readU16(pos)
  discard data.readU16(pos)
  discard data.readU16(pos)
  result.blendMode = data.readU16(pos)
  result.opacity = data.readU8(pos)
  pos += 3
  result.name = data.readString(pos)
  if result.kind == LayerTilemap and pos + 4 <= chunkEnd:
    result.tilesetIndex = data.readU32(pos)
  if (header.flags and 4) != 0 and pos + 16 <= chunkEnd:
    for i in 0 ..< result.uuid.len:
      result.uuid[i] = data.readU8(pos).uint8
  pos.skipTo(chunkEnd)

proc parseCel(
  data: string,
  pos: var int,
  chunkEnd: int,
  header: AsepriteHeader
): AsepriteCel {.raises: [AsepriteError].} =
  ## Reads a cel chunk and stores its raw decoded bytes.
  result.layerIndex = data.readU16(pos)
  result.x = data.readI16(pos)
  result.y = data.readI16(pos)
  result.opacity = data.readU8(pos)
  let kind = data.readU16(pos)
  case kind
  of 0:
    result.kind = CelRaw
  of 1:
    result.kind = CelLinked
  of 2:
    result.kind = CelCompressed
  of 3:
    result.kind = CelTilemap
  else:
    fail("Unsupported aseprite cel type: " & $kind)
  result.zIndex = data.readI16(pos)
  pos += 5

  case result.kind
  of CelRaw:
    result.width = data.readU16(pos)
    result.height = data.readU16(pos)
    let len = result.width * result.height * bytesPerPixel(header.colorDepth)
    data.ensure(pos, len)
    result.data = newSeq[uint8](len)
    for i in 0 ..< len:
      result.data[i] = data.readU8(pos).uint8
  of CelLinked:
    result.linkedFrame = data.readU16(pos)
  of CelCompressed:
    result.width = data.readU16(pos)
    result.height = data.readU16(pos)
    let compressed = data[pos ..< chunkEnd]
    try:
      let raw = uncompress(compressed)
      result.data = newSeq[uint8](raw.len)
      for i in 0 ..< raw.len:
        result.data[i] = raw[i].uint8
    except CatchableError:
      fail("Invalid aseprite compressed cel data")
    let expected =
      result.width * result.height * bytesPerPixel(header.colorDepth)
    if result.data.len != expected:
      fail("Invalid aseprite compressed cel size")
  of CelTilemap:
    result.width = data.readU16(pos)
    result.height = data.readU16(pos)
    discard data.readU16(pos)
    discard data.readU32(pos)
    discard data.readU32(pos)
    discard data.readU32(pos)
    discard data.readU32(pos)
    pos += 10
    result.data = @[]

  pos.skipTo(chunkEnd)

proc parseOldPalette(
  aseprite: var AsepriteSprite,
  data: string,
  pos: var int,
  chunkEnd: int,
  scale63: bool
) {.raises: [AsepriteError].} =
  ## Reads one of the legacy palette chunks.
  if aseprite.hasNewPalette:
    pos.skipTo(chunkEnd)
    return
  var index = 0
  let packets = data.readU16(pos)
  for i in 0 ..< packets:
    index += data.readU8(pos)
    var count = data.readU8(pos)
    if count == 0:
      count = 256
    for j in 0 ..< count:
      let
        r = data.readU8(pos)
        g = data.readU8(pos)
        b = data.readU8(pos)
        rr = if scale63: (r * 255 div 63).uint8 else: r.uint8
        gg = if scale63: (g * 255 div 63).uint8 else: g.uint8
        bb = if scale63: (b * 255 div 63).uint8 else: b.uint8
      if index + j >= aseprite.palette.len:
        aseprite.palette.setLen(index + j + 1)
      aseprite.palette[index + j] = rgba(rr, gg, bb, 255)
    index += count
  pos.skipTo(chunkEnd)

proc parsePalette(
  aseprite: var AsepriteSprite,
  data: string,
  pos: var int,
  chunkEnd: int
) {.raises: [AsepriteError].} =
  ## Reads the current palette chunk.
  aseprite.hasNewPalette = true
  let
    size = data.readU32(pos)
    first = data.readU32(pos)
    last = data.readU32(pos)
  pos += 8
  aseprite.palette.setLen(size)
  for index in first .. last:
    let flags = data.readU16(pos)
    let
      r = data.readU8(pos).uint8
      g = data.readU8(pos).uint8
      b = data.readU8(pos).uint8
      a = data.readU8(pos).uint8
    if index >= aseprite.palette.len:
      aseprite.palette.setLen(index + 1)
    aseprite.palette[index] = rgba(r, g, b, a)
    if (flags and 1) != 0:
      discard data.readString(pos)
  pos.skipTo(chunkEnd)

proc parseFrame(
  aseprite: var AsepriteSprite,
  data: string,
  pos: var int
): AsepriteFrame {.raises: [AsepriteError].} =
  ## Reads one frame and all of its chunks.
  let
    frameStart = pos
    frameBytes = data.readU32(pos)
    frameEnd = frameStart + frameBytes
  if frameBytes < FrameHeaderBytes:
    fail("Invalid aseprite frame size")
  data.ensure(frameStart, frameBytes)
  if data.readU16(pos) != FrameMagic:
    fail("Invalid aseprite frame magic number")
  let oldChunkCount = data.readU16(pos)
  result.duration = data.readU16(pos)
  pos += 2
  let newChunkCount = data.readU32(pos)
  let chunkCount =
    if newChunkCount != 0:
      newChunkCount
    else:
      oldChunkCount

  for i in 0 ..< chunkCount:
    let
      chunkStart = pos
      chunkSize = data.readU32(pos)
      chunkType = data.readU16(pos)
      chunkEnd = chunkStart + chunkSize
    if chunkSize < 6:
      fail("Invalid aseprite chunk size")
    data.ensure(chunkStart, chunkSize)
    case chunkType
    of ChunkLayer:
      aseprite.layers.add(parseLayer(data, pos, chunkEnd, aseprite.header))
    of ChunkCel:
      result.cels.add(parseCel(data, pos, chunkEnd, aseprite.header))
    of ChunkOldPaletteShort:
      parseOldPalette(aseprite, data, pos, chunkEnd, false)
    of ChunkOldPaletteLong:
      parseOldPalette(aseprite, data, pos, chunkEnd, true)
    of ChunkPalette:
      parsePalette(aseprite, data, pos, chunkEnd)
    else:
      pos.skipTo(chunkEnd)

  pos.skipTo(frameEnd)

proc decodeAseprite*(data: string): AsepriteSprite {.raises: [AsepriteError].} =
  ## Decodes an aseprite file from memory.
  var pos = 0
  result.header = parseHeader(data, pos)
  result.palette = defaultPalette()
  result.frames = newSeq[AsepriteFrame](result.header.frameCount)
  for i in 0 ..< result.header.frameCount:
    result.frames[i] = parseFrame(result, data, pos)

proc readAseprite*(path: string): AsepriteSprite
    {.raises: [AsepriteError, IOError].} =
  ## Reads and decodes an aseprite file from disk.
  if not fileExists(path):
    raise newException(IOError, "Missing aseprite asset: " & path)
  decodeAseprite(readFile(path))

proc pixelAt(
  aseprite: AsepriteSprite,
  cel: AsepriteCel,
  i: int,
  transparentIndex: bool
): ColorRGBA {.raises: [].} =
  ## Converts one cel pixel to straight RGBA.
  case aseprite.header.colorDepth
  of DepthRgba:
    let base = i * 4
    rgba(
      cel.data[base],
      cel.data[base + 1],
      cel.data[base + 2],
      cel.data[base + 3]
    )
  of DepthGrayscale:
    let base = i * 2
    rgba(cel.data[base], cel.data[base], cel.data[base], cel.data[base + 1])
  of DepthIndexed:
    let index = cel.data[i].int
    if transparentIndex and index == aseprite.header.transparentIndex:
      rgba(0, 0, 0, 0)
    elif index < aseprite.palette.len:
      aseprite.palette[index]
    else:
      rgba(0, 0, 0, 0)

proc layerImage*(aseprite: AsepriteSprite, layerIndex: int): Image
    {.raises: [AsepriteError].} =
  ## Renders one aseprite layer from the first frame.
  if aseprite.frames.len == 0:
    fail("aseprite has no frames")
  if layerIndex < 0 or layerIndex >= aseprite.layers.len:
    fail("aseprite layer index out of range: " & $layerIndex)
  try:
    result = newImage(aseprite.header.width, aseprite.header.height)
  except PixieError:
    fail("Invalid aseprite dimensions")
  result.fill(rgba(0, 0, 0, 0))
  for cel in aseprite.frames[0].cels:
    if cel.layerIndex != layerIndex:
      continue
    if cel.kind notin {CelRaw, CelCompressed}:
      continue
    for y in 0 ..< cel.height:
      let dstY = cel.y + y
      if dstY < 0 or dstY >= result.height:
        continue
      for x in 0 ..< cel.width:
        let dstX = cel.x + x
        if dstX < 0 or dstX >= result.width:
          continue
        let pixel = aseprite.pixelAt(cel, y * cel.width + x, true)
        if pixel.a > 0:
          result[dstX, dstY] = pixel

proc blendPixel(dst, src: ColorRGBA, opacity: int): ColorRGBA {.raises: [].} =
  ## Blends one straight RGBA source pixel over one destination pixel.
  let
    sa = int(src.a) * opacity div 255
    da = int(dst.a)
    outA = sa + da * (255 - sa) div 255
  if outA == 0:
    return rgba(0, 0, 0, 0)
  let
    r = (int(src.r) * sa + int(dst.r) * da * (255 - sa) div 255) div outA
    g = (int(src.g) * sa + int(dst.g) * da * (255 - sa) div 255) div outA
    b = (int(src.b) * sa + int(dst.b) * da * (255 - sa) div 255) div outA
  rgba(r.uint8, g.uint8, b.uint8, outA.uint8)

proc sourceCel(
  aseprite: AsepriteSprite,
  frameIndex: int,
  cel: AsepriteCel
): AsepriteCel {.raises: [].} =
  ## Resolves linked cels to their source image cel when possible.
  discard frameIndex
  if cel.kind != CelLinked:
    return cel
  if cel.linkedFrame < 0 or cel.linkedFrame >= aseprite.frames.len:
    return cel
  for source in aseprite.frames[cel.linkedFrame].cels:
    if source.layerIndex == cel.layerIndex and source.kind != CelLinked:
      result = source
      result.x = cel.x
      result.y = cel.y
      result.opacity = cel.opacity
      result.zIndex = cel.zIndex
      return
  cel

proc drawCel(
  image: Image,
  aseprite: AsepriteSprite,
  cel: AsepriteCel
) {.raises: [].} =
  ## Draws a cel onto a rendered frame image.
  if cel.kind notin {CelRaw, CelCompressed}:
    return
  if cel.layerIndex < 0 or cel.layerIndex >= aseprite.layers.len:
    return
  let layer = aseprite.layers[cel.layerIndex]
  if layer.kind != LayerNormal or not layer.visible:
    return
  let opacity = cel.opacity * layer.opacity div 255
  if opacity <= 0:
    return
  let isBackground = (layer.flags and 8) != 0
  for y in 0 ..< cel.height:
    let dstY = cel.y + y
    if dstY < 0 or dstY >= image.height:
      continue
    for x in 0 ..< cel.width:
      let dstX = cel.x + x
      if dstX < 0 or dstX >= image.width:
        continue
      let src = aseprite.pixelAt(cel, y * cel.width + x, not isBackground)
      if src.a == 0:
        continue
      image[dstX, dstY] = blendPixel(image[dstX, dstY], src, opacity)

proc renderFrame*(aseprite: AsepriteSprite, frameIndex = 0): Image
    {.raises: [AsepriteError].} =
  ## Renders one aseprite frame with normal layer alpha blending.
  if frameIndex < 0 or frameIndex >= aseprite.frames.len:
    fail("aseprite frame index out of range: " & $frameIndex)
  try:
    result = newImage(aseprite.header.width, aseprite.header.height)
  except PixieError:
    fail("Invalid aseprite dimensions")
  result.fill(rgba(0, 0, 0, 0))
  var cels = aseprite.frames[frameIndex].cels
  cels.sort(
    proc(a, b: AsepriteCel): int =
      cmp(a.layerIndex + a.zIndex, b.layerIndex + b.zIndex)
  )
  for cel in cels:
    result.drawCel(aseprite, aseprite.sourceCel(frameIndex, cel))

proc readAsepriteImage*(path: string, frameIndex = 0): Image
    {.raises: [AsepriteError, IOError].} =
  ## Reads an aseprite file and renders one frame as a Pixie image.
  readAseprite(path).renderFrame(frameIndex)
