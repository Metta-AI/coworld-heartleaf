import
  std/math,
  pixie

type
  RgbaSprite* = ref object
    ## A simple 32-bit RGBA sprite used by the sprite protocol.
    width*, height*: int
    pixels*: seq[uint8]

proc newRgbaSprite*(width, height: int): RgbaSprite =
  ## Allocates one transparent RGBA sprite.
  result = RgbaSprite()
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

proc clamp01(value: float): float =
  ## Clamps one floating-point value into the unit interval.
  if value < 0.0:
    return 0.0
  if value > 1.0:
    return 1.0
  value

proc wrapHue(value: float): float =
  ## Wraps one hue value into the unit interval.
  result = value
  while result < 0.0:
    result += 1.0
  while result >= 1.0:
    result -= 1.0

proc mixHue(source, target, amount: float): float =
  ## Mixes between two hue values on the shortest color-wheel path.
  var delta = target - source
  if delta > 0.5:
    delta -= 1.0
  elif delta < -0.5:
    delta += 1.0
  wrapHue(source + delta * amount.clamp01())

proc colorToHsv(color: ColorRGBA): tuple[h, s, v: float] =
  ## Converts one RGB color to HSV values in the unit interval.
  let
    r = float(color.r) / 255.0
    g = float(color.g) / 255.0
    b = float(color.b) / 255.0
    maxValue = max(r, max(g, b))
    minValue = min(r, min(g, b))
    delta = maxValue - minValue
  result.v = maxValue
  if maxValue <= 0.0:
    return
  result.s = delta / maxValue
  if delta <= 0.0:
    return
  if maxValue == r:
    result.h = ((g - b) / delta) / 6.0
  elif maxValue == g:
    result.h = (((b - r) / delta) + 2.0) / 6.0
  else:
    result.h = (((r - g) / delta) + 4.0) / 6.0
  result.h = result.h.wrapHue()

proc hsvToColor(h, s, v: float, alpha: uint8): ColorRGBA =
  ## Converts HSV values in the unit interval to one RGBA color.
  let
    hue = h.wrapHue() * 6.0
    sector = int(floor(hue))
    fraction = hue - float(sector)
    value = v.clamp01()
    saturation = s.clamp01()
    p = value * (1.0 - saturation)
    q = value * (1.0 - saturation * fraction)
    t = value * (1.0 - saturation * (1.0 - fraction))
  var
    r = value
    g = t
    b = p
  case sector mod 6
  of 0:
    r = value
    g = t
    b = p
  of 1:
    r = q
    g = value
    b = p
  of 2:
    r = p
    g = value
    b = t
  of 3:
    r = p
    g = q
    b = value
  of 4:
    r = t
    g = p
    b = value
  else:
    r = value
    g = p
    b = q
  rgba(
    uint8(round(r * 255.0).clamp(0.0, 255.0)),
    uint8(round(g * 255.0).clamp(0.0, 255.0)),
    uint8(round(b * 255.0).clamp(0.0, 255.0)),
    alpha
  )

proc hsvTinted*(
  sprite: RgbaSprite,
  targetHue,
  hueMix,
  saturationScale,
  valueScale: float
): RgbaSprite =
  ## Builds one HSV-tinted copy of an RGBA sprite.
  result = newRgbaSprite(sprite.width, sprite.height)
  for y in 0 ..< sprite.height:
    for x in 0 ..< sprite.width:
      let offset = sprite.pixelOffset(x, y)
      if sprite.pixels[offset + 3] == 0:
        continue
      let hsv = rgba(
        sprite.pixels[offset],
        sprite.pixels[offset + 1],
        sprite.pixels[offset + 2],
        sprite.pixels[offset + 3]
      ).colorToHsv()
      result.putPixel(
        x,
        y,
        hsvToColor(
          hsv.h.mixHue(targetHue, hueMix),
          hsv.s * saturationScale,
          hsv.v * valueScale,
          sprite.pixels[offset + 3]
        )
      )

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
  x0,
  x1,
  y: int,
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
  x,
  y0,
  y1: int,
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
  x,
  y,
  width,
  height: int,
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

proc blitRgbaSprite*(
  target: var RgbaSprite,
  source: RgbaSprite,
  x,
  y: int
) =
  ## Blits one RGBA sprite onto another with alpha blending.
  for sy in 0 ..< source.height:
    let ty = y + sy
    if ty < 0 or ty >= target.height:
      continue
    for sx in 0 ..< source.width:
      let tx = x + sx
      if tx < 0 or tx >= target.width:
        continue
      let
        sourceOffset = source.pixelOffset(sx, sy)
        sourceAlpha = int(source.pixels[sourceOffset + 3])
      if sourceAlpha <= 0:
        continue
      let targetOffset = target.pixelOffset(tx, ty)
      if sourceAlpha == 255 or target.pixels[targetOffset + 3] == 0:
        for i in 0 .. 3:
          target.pixels[targetOffset + i] = source.pixels[sourceOffset + i]
        continue
      let
        targetAlpha = int(target.pixels[targetOffset + 3])
        outAlpha = sourceAlpha + targetAlpha * (255 - sourceAlpha) div 255
      if outAlpha <= 0:
        continue
      for i in 0 .. 2:
        let value =
          (
            int(source.pixels[sourceOffset + i]) * sourceAlpha +
            int(target.pixels[targetOffset + i]) * targetAlpha *
              (255 - sourceAlpha) div 255
          ) div outAlpha
        target.pixels[targetOffset + i] = value.uint8
      target.pixels[targetOffset + 3] = outAlpha.uint8

proc strokeRect*(
  sprite: var RgbaSprite,
  x,
  y,
  width,
  height: int,
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
