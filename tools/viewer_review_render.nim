## Offline compositor for review evidence, following pinned Bitworld protocol semantics.
import std/[algorithm, math, tables]
import pixie, supersnappy
import bitworld/[sprites, spriteprotocol]

type Layer = object
  width, height, kind, flags: int

proc decodeReviewPixels(compressed: seq[uint8]): seq[uint8] =
  # The pinned decoder reads a 32-bit trailer even for a final 1/2-byte
  # Snappy copy offset. Keep readable padding outside the logical input
  # length; a page-aligned allocation otherwise faults in native release.
  var padded = newSeq[uint8](compressed.len + 8)
  for i, value in compressed: padded[i] = value
  padded.setLen(compressed.len)
  uncompress(padded)

proc render*(packet: seq[uint8], width, height: int, path: string) =
  var
    sprites = initTable[int, RgbaSprite]()
    layers = initTable[int, Layer]()
    objects: seq[SpritePacketObject]
  for msg in parseSpritePacket(packet):
    case msg.kind
    of spkSprite:
      sprites[msg.sprite.id] = RgbaSprite(width: msg.sprite.width,
        height: msg.sprite.height, pixels: decodeReviewPixels(msg.sprite.compressedPixels))
    of spkLayer:
      layers.mgetOrPut(msg.layer.layer, Layer()).kind = msg.layer.kind
      layers[msg.layer.layer].flags = msg.layer.flags
    of spkViewport:
      layers.mgetOrPut(msg.viewport.layer, Layer()).width = msg.viewport.width
      layers[msg.viewport.layer].height = msg.viewport.height
    of spkObject: objects.add(msg.objectDef)
    of spkClearObjects: objects.setLen(0)
    else: discard
  var uiZoom = 3
  for layer in layers.values:
    if (layer.flags and 2) == 0: continue
    let fit = min(float(width) / float(layer.width), float(height) / float(layer.height))
    var zoom = 1
    for scale in countdown(3,2):
      if fit >= float(scale) * 1.5:
        zoom = scale
        break
    uiZoom = min(uiZoom, zoom)
  var order: seq[int]
  for id in layers.keys: order.add(id)
  proc rank(layer: Layer): int =
    if layer.kind == 0: 0 elif layer.kind == 9: 1 else: 2
  order.sort(proc(a,b: int): int = cmp(
    (rank(layers[a]), layers[a].kind, a), (rank(layers[b]), layers[b].kind, b)))
  objects.sort(proc(a,b: SpritePacketObject): int = cmp((a.z,a.y,a.id),(b.z,b.y,b.id)))
  var canvas = solidRgbaSprite(width,height,rgba(0,0,0,255))
  for id in order:
    let layer = layers[id]
    if layer.width <= 0 or layer.height <= 0: continue
    var buffer = newRgbaSprite(layer.width,layer.height)
    # Bitworld overwrites nontransparent sprite pixels within a layer,
    # then alpha-composites each complete layer with nearest sampling.
    for obj in objects:
      if obj.layer != id or obj.spriteId notin sprites: continue
      let sprite = sprites[obj.spriteId]
      for y in max(0,-obj.y) ..< min(sprite.height,layer.height-obj.y):
        for x in max(0,-obj.x) ..< min(sprite.width,layer.width-obj.x):
          let pixel = sprite.rgbaSpriteAt(x,y)
          if pixel.a > 0: buffer.putPixel(obj.x+x,obj.y+y,pixel)
    let scale = if layer.kind in [0,9]:
      min(float(width)/float(layer.width),float(height)/float(layer.height))
      else: float(uiZoom)
    let w = float(layer.width)*scale
    let h = float(layer.height)*scale
    var x0,y0: float
    case layer.kind
    of 0,9: x0=floor((float(width)-w)/2); y0=floor((float(height)-h)/2)
    of 2: x0=float(width)-w
    of 3: x0=float(width)-w; y0=float(height)-h
    of 4: y0=float(height)-h
    of 5: x0=(float(width)-w)/2
    of 8: x0=(float(width)-w)/2; y0=float(height)-h
    else: discard
    for y in max(0,int(y0)) ..< min(height,int(ceil(y0+h))):
      for x in max(0,int(x0)) ..< min(width,int(ceil(x0+w))):
        let pixel = buffer.rgbaSpriteAt(int((float(x)-x0)/scale),int((float(y)-y0)/scale))
        if pixel.a == 0: continue
        let old = canvas.rgbaSpriteAt(x,y)
        let a = int(pixel.a)
        canvas.putPixel(x,y,rgba(
          uint8((int(pixel.r)*a+int(old.r)*(255-a)) div 255),
          uint8((int(pixel.g)*a+int(old.g)*(255-a)) div 255),
          uint8((int(pixel.b)*a+int(old.b)*(255-a)) div 255),255))
  let image = newImage(width,height)
  for y in 0..<height:
    for x in 0..<width: image[x,y]=canvas.rgbaSpriteAt(x,y)
  image.writeFile(path)

