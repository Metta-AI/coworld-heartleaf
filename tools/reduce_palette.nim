## Reduce an image's palette in place. Snaps every pixel to fully
## transparent or fully opaque, then merges the most similar color
## pairs together (weighted by pixel count) until at most the requested
## number of colors remain.
##
## Reads PNG and aseprite files; the writer is picked by the output
## extension, so an aseprite input can also be exported to PNG via
## --out. Aseprite inputs are flattened (frame 0, all visible layers)
## and written back as one full-canvas RGBA layer.
##
## Usage:
##   reduce_palette [--colors:N] [--out:PATH] <image.(png|aseprite)>

import std/[os, parseopt, strutils, tables], pixie, chroma, zippy
import bitworld/aseprite

const
  DefaultColors = 64
  AlphaOpaqueThreshold = 128
  AsepriteHeaderBytes = 128
  AsepriteHeaderMagic = 0xA5E0
  AsepriteFrameMagic = 0xF1FA
  AsepriteLayerChunk = 0x2004
  AsepriteCelChunk = 0x2005
  UsageText =
    "Usage: reduce_palette [--colors:N] [--out:PATH] <image.(png|aseprite)>"

type
  CliConfig = object
    inputPath: string
    outputPath: string
    colors: int

  ColorCluster = object
    red, green, blue: float
    weight: float
    alive: bool

proc fail(message: string) =
  ## Prints one error with usage and exits.
  echo message
  echo UsageText
  quit(1)

proc parseArgs(): CliConfig =
  ## Parses command-line options for the palette reducer.
  result.colors = DefaultColors
  for kind, key, value in getopt():
    case kind
    of cmdArgument:
      if result.inputPath.len > 0:
        fail("Only one input image is supported.")
      result.inputPath = key
    of cmdLongOption:
      case key
      of "colors":
        if value.len == 0:
          fail("--colors requires a value.")
        try:
          result.colors = parseInt(value)
        except ValueError:
          fail("--colors must be an integer.")
        if result.colors < 1:
          fail("--colors must be 1 or greater.")
      of "out":
        if value.len == 0:
          fail("--out requires a value.")
        result.outputPath = value
      else:
        fail("Unknown option: --" & key)
    of cmdShortOption:
      fail("Unknown option: -" & key)
    of cmdEnd:
      discard
  if result.inputPath.len == 0:
    fail("An input image path is required.")
  if not fileExists(result.inputPath):
    fail("Input image not found: " & result.inputPath)
  if result.outputPath.len == 0:
    result.outputPath = result.inputPath

proc addU8(bytes: var string, value: int) =
  ## Appends one unsigned byte.
  bytes.add(char(value and 0xff))

proc addU16(bytes: var string, value: int) =
  ## Appends one little-endian unsigned word.
  bytes.addU8(value)
  bytes.addU8(value shr 8)

proc addU32(bytes: var string, value: int) =
  ## Appends one little-endian unsigned dword.
  bytes.addU16(value)
  bytes.addU16(value shr 16)

proc addZeros(bytes: var string, count: int) =
  ## Appends a run of zero bytes.
  for _ in 0 ..< count:
    bytes.addU8(0)

proc asepriteLayerChunk(): string =
  ## Builds one normal, visible, full-opacity layer chunk body.
  let name = "Layer"
  result.addU16(3)         # flags: visible + editable
  result.addU16(0)         # type: normal
  result.addU16(0)         # child level
  result.addU16(0)         # default width, ignored
  result.addU16(0)         # default height, ignored
  result.addU16(0)         # blend mode: normal
  result.addU8(255)        # opacity
  result.addZeros(3)
  result.addU16(name.len)
  result.add(name)

proc asepriteCelChunk(image: Image): string =
  ## Builds one zlib-compressed full-canvas RGBA cel chunk body.
  var raw = newString(image.data.len * 4)
  for i, color in image.data:
    # Alpha is snapped to 0 or 255 upstream, so premultiplied pixie
    # pixels are already straight RGBA.
    raw[i * 4] = char(color.r)
    raw[i * 4 + 1] = char(color.g)
    raw[i * 4 + 2] = char(color.b)
    raw[i * 4 + 3] = char(color.a)
  result.addU16(0)         # layer index
  result.addU16(0)         # x position
  result.addU16(0)         # y position
  result.addU8(255)        # opacity
  result.addU16(2)         # cel type: compressed image
  result.addU16(0)         # z-index
  result.addZeros(5)
  result.addU16(image.width)
  result.addU16(image.height)
  result.add(compress(raw, BestCompression, dfZlib))

proc addAsepriteChunk(bytes: var string, chunkType: int, body: string) =
  ## Appends one chunk with its size and type header.
  bytes.addU32(body.len + 6)
  bytes.addU16(chunkType)
  bytes.add(body)

proc writeAsepriteRgba(path: string, image: Image) =
  ## Writes one image as a single-frame, single-layer RGBA aseprite
  ## file, mirroring the field order of bitworld's aseprite parser.
  var frame = ""
  frame.addU16(AsepriteFrameMagic)
  frame.addU16(2)          # old chunk count
  frame.addU16(100)        # frame duration in ms
  frame.addZeros(2)
  frame.addU32(2)          # new chunk count
  frame.addAsepriteChunk(AsepriteLayerChunk, asepriteLayerChunk())
  frame.addAsepriteChunk(AsepriteCelChunk, asepriteCelChunk(image))

  var frameBytes = ""
  frameBytes.addU32(frame.len + 4)
  frameBytes.add(frame)

  var header = ""
  header.addU32(AsepriteHeaderBytes + frameBytes.len)
  header.addU16(AsepriteHeaderMagic)
  header.addU16(1)         # frame count
  header.addU16(image.width)
  header.addU16(image.height)
  header.addU16(32)        # color depth: RGBA
  header.addU32(1)         # flags: layer opacity is valid
  header.addU16(100)       # legacy speed
  header.addU32(0)
  header.addU32(0)
  header.addU8(0)          # transparent palette index
  header.addZeros(3)
  header.addU16(0)         # color count, 0 means 256
  header.addU8(1)          # pixel width
  header.addU8(1)          # pixel height
  header.addU16(0)         # grid x
  header.addU16(0)         # grid y
  header.addU16(16)        # grid width
  header.addU16(16)        # grid height
  header.addZeros(AsepriteHeaderBytes - header.len)

  writeFile(path, header & frameBytes)

proc isAsepritePath(path: string): bool =
  ## Returns true for aseprite file extensions.
  let ext = path.splitFile().ext.toLowerAscii()
  ext == ".aseprite" or ext == ".ase"

proc readInputImage(path: string): Image =
  ## Loads one PNG or flattened aseprite image.
  if path.isAsepritePath():
    readAsepriteImage(path)
  else:
    readImage(path)

proc writeOutputImage(path: string, image: Image) =
  ## Writes one image as PNG or aseprite based on the extension.
  if path.isAsepritePath():
    writeAsepriteRgba(path, image)
  else:
    image.writeFile(path)

proc colorKey(color: ColorRGBA): uint32 =
  ## Packs one opaque color into a table key.
  uint32(color.r) or (uint32(color.g) shl 8) or (uint32(color.b) shl 16)

proc clusterDistance(a, b: ColorCluster): float =
  ## Returns the squared RGB distance between two cluster means.
  let
    dr = a.red - b.red
    dg = a.green - b.green
    db = a.blue - b.blue
  dr * dr + dg * dg + db * db

proc nearestCluster(clusters: seq[ColorCluster], index: int): (int, float) =
  ## Finds the closest other living cluster to one cluster.
  result = (-1, 0.0)
  for i, cluster in clusters:
    if i == index or not cluster.alive:
      continue
    let distance = clusterDistance(clusters[index], cluster)
    if result[0] < 0 or distance < result[1]:
      result = (i, distance)

proc mergeSimilarColors(
  clusters: var seq[ColorCluster],
  parents: var seq[int],
  targetColors: int
) =
  ## Repeatedly merges the closest pair of clusters, most similar
  ## colors first, until only the target number remain.
  var
    nearest = newSeq[int](clusters.len)
    nearestDistance = newSeq[float](clusters.len)
    aliveCount = clusters.len
  for i in 0 ..< clusters.len:
    let (index, distance) = clusters.nearestCluster(i)
    nearest[i] = index
    nearestDistance[i] = distance

  while aliveCount > targetColors:
    var
      bestIndex = -1
      bestDistance = 0.0
    for i, cluster in clusters:
      if not cluster.alive or nearest[i] < 0:
        continue
      if bestIndex < 0 or nearestDistance[i] < bestDistance:
        bestIndex = i
        bestDistance = nearestDistance[i]
    if bestIndex < 0:
      break

    let
      keep = bestIndex
      drop = nearest[bestIndex]
      total = clusters[keep].weight + clusters[drop].weight
    clusters[keep].red =
      (clusters[keep].red * clusters[keep].weight +
        clusters[drop].red * clusters[drop].weight) / total
    clusters[keep].green =
      (clusters[keep].green * clusters[keep].weight +
        clusters[drop].green * clusters[drop].weight) / total
    clusters[keep].blue =
      (clusters[keep].blue * clusters[keep].weight +
        clusters[drop].blue * clusters[drop].weight) / total
    clusters[keep].weight = total
    clusters[drop].alive = false
    parents[drop] = keep
    dec aliveCount

    for i, cluster in clusters:
      if not cluster.alive:
        continue
      if i == keep or nearest[i] == keep or nearest[i] == drop:
        let (index, distance) = clusters.nearestCluster(i)
        nearest[i] = index
        nearestDistance[i] = distance

proc resolveParent(parents: seq[int], index: int): int =
  ## Follows merge links to the final surviving cluster.
  result = index
  while parents[result] != result:
    result = parents[result]

when isMainModule:
  let config = parseArgs()
  var image = readInputImage(config.inputPath)

  # Snap alpha to fully transparent or fully opaque.
  for i in 0 ..< image.data.len:
    let color = image.data[i].rgba()
    if int(color.a) < AlphaOpaqueThreshold:
      image.data[i] = rgbx(0, 0, 0, 0)
    else:
      image.data[i] = rgba(color.r, color.g, color.b, 255).rgbx()

  # Collect the unique opaque colors with their pixel counts.
  var counts = initTable[uint32, int]()
  for i in 0 ..< image.data.len:
    let color = image.data[i].rgba()
    if color.a == 0:
      continue
    counts.mgetOrPut(color.colorKey(), 0) += 1

  var
    clusters: seq[ColorCluster]
    clusterIndex = initTable[uint32, int]()
  for key, count in counts:
    clusterIndex[key] = clusters.len
    clusters.add(ColorCluster(
      red: float(key and 0xff),
      green: float((key shr 8) and 0xff),
      blue: float((key shr 16) and 0xff),
      weight: float(count),
      alive: true
    ))
  let uniqueBefore = clusters.len

  var parents = newSeq[int](clusters.len)
  for i in 0 ..< parents.len:
    parents[i] = i
  clusters.mergeSimilarColors(parents, config.colors)

  # Remap every opaque pixel to its surviving cluster color.
  for i in 0 ..< image.data.len:
    let color = image.data[i].rgba()
    if color.a == 0:
      continue
    let
      cluster = clusters[
        parents.resolveParent(clusterIndex[color.colorKey()])
      ]
      snapped = rgba(
        uint8(clamp(cluster.red, 0.0, 255.0)),
        uint8(clamp(cluster.green, 0.0, 255.0)),
        uint8(clamp(cluster.blue, 0.0, 255.0)),
        255
      )
    image.data[i] = snapped.rgbx()

  var uniqueAfter = 0
  for cluster in clusters:
    if cluster.alive:
      inc uniqueAfter

  writeOutputImage(config.outputPath, image)
  echo "Wrote ", config.outputPath, ": ", uniqueBefore, " -> ",
    uniqueAfter, " colors (target ", config.colors, ")."
