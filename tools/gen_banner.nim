import
  std/[os, strutils],
  pixie,
  bitworld/aseprite

proc colorFromCel(
  aseprite: AsepriteSprite,
  cel: AsepriteCel,
  pixelIndex: int
): ColorRGBA =
  ## Converts one decoded aseprite cel pixel to RGBA.
  case aseprite.header.colorDepth
  of DepthRgba:
    let base = pixelIndex * 4
    rgba(
      cel.data[base],
      cel.data[base + 1],
      cel.data[base + 2],
      cel.data[base + 3]
    )
  of DepthGrayscale:
    let base = pixelIndex * 2
    rgba(cel.data[base], cel.data[base], cel.data[base], cel.data[base + 1])
  of DepthIndexed:
    let index = cel.data[pixelIndex].int
    if index == aseprite.header.transparentIndex:
      rgba(0, 0, 0, 0)
    elif index < aseprite.palette.len:
      aseprite.palette[index]
    else:
      rgba(0, 0, 0, 0)

proc layerIndexByName(aseprite: AsepriteSprite, name: string): int =
  ## Finds the first layer whose name matches one requested name.
  for i, layer in aseprite.layers:
    if layer.name.toLowerAscii() == name.toLowerAscii():
      return i
  -1

proc renderLayer(aseprite: AsepriteSprite, layerIndex: int): Image =
  ## Renders one aseprite layer from the first frame.
  result = newImage(aseprite.header.width, aseprite.header.height)
  result.fill(rgba(255, 255, 255, 255))
  if aseprite.frames.len == 0 or layerIndex < 0:
    return
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
        let pixel = aseprite.colorFromCel(cel, y * cel.width + x)
        if pixel.a > 0:
          result[dstX, dstY] = pixel

let
  map = readAseprite("data/map.aseprite")
  bottom = map.layerIndexByName("bottom")
  image = map.renderLayer(bottom)

createDir("docs")
image.writeFile("docs/heartleafMap.png")
