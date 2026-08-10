## Reduce an image's palette in place. Snaps every pixel to fully
## transparent or fully opaque, then merges the most similar color
## pairs together (weighted by pixel count) until at most the requested
## number of colors remain.
##
## Usage:
##   reduce_palette [--colors:N] [--out:PATH] <image.png>

import std/[os, parseopt, strutils, tables], pixie, chroma

const
  DefaultColors = 64
  AlphaOpaqueThreshold = 128
  UsageText = "Usage: reduce_palette [--colors:N] [--out:PATH] <image.png>"

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
  var image = readImage(config.inputPath)

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

  image.writeFile(config.outputPath)
  echo "Wrote ", config.outputPath, ": ", uniqueBefore, " -> ",
    uniqueAfter, " colors (target ", config.colors, ")."
