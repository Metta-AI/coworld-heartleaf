## Small, hand-authored pixel faces using the game's parchment palette.
## One source pixel stays one world pixel. No font emoji or interpolation.
import pixie, bitworld/sprites

const PixelEmoteSize* = 16

proc pixelEmote*(tier: int): RgbaSprite =
  const face = [
    ".....oooooo.....",
    "...ooYYYYYYoo...",
    "..oYYyyyyyyyyo..",
    ".oYYyyyyyyyyyyo.",
    ".oYyyyyyyyyyyyo.",
    "oYyyyyyyyyyyyyyo",
    "oYyyyyyyyyyyyyyo",
    "oYyyyyyyyyyyyyyo",
    "oyyyyyyyyyyyyyyo",
    "oyyyyyyyyyyyyyyo",
    ".oyyyyyyyyyyyyo.",
    ".oyyyyyyyyyyyyo.",
    "..oyyyyyyyyyyo..",
    "...ooyyyyyyoo...",
    ".....oooooo.....",
    "................"
  ]
  let
    outline = rgba(94, 58, 22, 255)
    fill = rgba(224, 175, 72, 255)
    light = rgba(248, 220, 136, 255)
  result = newRgbaSprite(PixelEmoteSize, PixelEmoteSize)
  proc dot(sprite: var RgbaSprite, x, y: int, color: ColorRGBA) =
    sprite.putPixel(x, y, color)
  for y, row in face:
    for x, ch in row:
      case ch
      of 'o': result.dot(x, y, outline)
      of 'y': result.dot(x, y, fill)
      of 'Y': result.dot(x, y, light)
      else: discard
  for x in [5, 10]:
    result.dot(x, 5, outline)
    result.dot(x, 6, outline)
    if tier == 1:
      result.dot(x - 1, 5, outline)
      result.dot(x + 1, 5, outline)
      result.dot(x, 4, outline)
  if tier < 2:
    result.dot(4, 9, outline)
    result.dot(11, 9, outline)
    result.dot(5, 10, outline)
    result.dot(10, 10, outline)
    for x in 6 .. 9: result.dot(x, 11, outline)
    if tier == 1:
      for y in 9..10:
        for x in 6..9: result.dot(x,y,outline)
      for x in 7..8: result.dot(x,11,rgba(197,89,59,255))
  else:
    for x in 6..9: result.dot(x,9,outline)
    result.dot(5,10,outline)
    result.dot(10,10,outline)
    if tier == 3:
      for x in [4,11]:
        for y in 7..10: result.dot(x,y,rgba(113,171,198,255))

proc pixelHearts*(strength: float, count = 3, spacing = 2): RgbaSprite =
  ## Reuse the same seven-pixel hearts in dialogue and the leaderboard.
  # A seven by six silhouette drawn explicitly, with dark empty interiors.
  const rows = [".oo.oo.","orrrrro","orrrrro",".orrro.","..oro..","...o..."]
  let pitch = 7 + spacing
  result = newRgbaSprite(max(1,count*pitch-spacing),7)
  for heart in 0..<count:
    let fill = max(0.0,min(1.0,strength*count.float-heart.float))
    for y,row in rows:
      for x,ch in row:
        if ch == 'o': result.putPixel(heart*pitch+x,y,rgba(107,66,35,255))
        elif ch == 'r':
          let color = if (x.float-1.0)/5.0 < fill: rgba(177,59,52,255)
            else: rgba(211,174,119,255)
          result.putPixel(heart*pitch+x,y,color)
