## Per-sprite byte accounting for the Heartleaf init packet.
##
## Builds the simulation exactly like the server does, walks the init
## packet with the bitworld sprite protocol parser, and prints one row
## per sprite definition: the bytes it costs on the wire, the encoding
## it travels with, its dimensions, its unique color count, and what
## the same pixels cost as a legacy raw-RGBA Snappy definition. Rows are
## sorted by wire bytes, largest first.
##
##   nim r tools/init_packet_report.nim            # top 15, encoded
##   nim r tools/init_packet_report.nim --all      # every sprite
##   nim r tools/init_packet_report.nim --legacy   # the raw-RGBA packet
##   nim r tools/init_packet_report.nim --csv      # machine readable

import
  std/[algorithm, os, sets, strformat, strutils, tables],
  bitworld/spriteprotocol,
  heartleaf

type
  SpriteRow = object
    id: int
    label: string
    width, height: int
    encoding: string
    wireBytes: int      ## full message bytes in the packet
    legacyBytes: int    ## the same sprite as a legacy raw-RGBA Snappy message
    rawBytes: int       ## width * height * 4
    colors: int         ## unique RGBA values

proc uniqueColors(pixels: seq[uint8]): int =
  var seen = initHashSet[uint32]()
  var i = 0
  while i + 3 < pixels.len:
    let value =
      uint32(pixels[i]) or
      (uint32(pixels[i + 1]) shl 8) or
      (uint32(pixels[i + 2]) shl 16) or
      (uint32(pixels[i + 3]) shl 24)
    seen.incl(value)
    i += 4
  seen.len

proc encodingName(def: SpritePacketSpriteDef, legacyMessage: bool): string =
  if legacyMessage:
    return "legacy"
  case def.encoding
  of SpriteEncodingRgbaSnappy: "rgba-snappy"
  of SpriteEncodingRgbaDeflate: "rgba-deflate"
  of SpriteEncodingIndexed: "indexed"
  of SpriteEncodingPaletteSwap: "palette-swap"
  else: "?" & $def.encoding

proc report(rows: seq[SpriteRow], limit: int, csv: bool) =
  var
    total = 0
    legacyTotal = 0
  for row in rows:
    total += row.wireBytes
    legacyTotal += row.legacyBytes
  if csv:
    echo "id,label,width,height,encoding,wire_bytes,legacy_bytes,raw_bytes,colors"
    for row in rows:
      echo &"{row.id},\"{row.label}\",{row.width},{row.height}," &
        &"{row.encoding},{row.wireBytes},{row.legacyBytes},{row.rawBytes}," &
        &"{row.colors}"
    return
  echo &"sprites: {rows.len}  sprite wire bytes: {total}  " &
    &"as legacy raw-RGBA snappy: {legacyTotal}"
  echo ""
  echo alignLeft("id", 6), alignLeft("label", 26), alignLeft("size", 11),
    alignLeft("encoding", 14), align("wire", 9), align("legacy", 9),
    align("raw", 10), align("colors", 7)
  var shown = 0
  var shownBytes = 0
  for row in rows:
    if shown >= limit:
      break
    inc shown
    shownBytes += row.wireBytes
    echo alignLeft($row.id, 6),
      alignLeft(row.label[0 ..< min(25, row.label.len)], 26),
      alignLeft(&"{row.width}x{row.height}", 11),
      alignLeft(row.encoding, 14),
      align($row.wireBytes, 9), align($row.legacyBytes, 9),
      align($row.rawBytes, 10), align($row.colors, 7)
  echo ""
  echo &"top {shown} sprites: {shownBytes} bytes " &
    &"({100 * shownBytes div max(1, total)}% of sprite bytes)"

proc main() =
  var
    showAll = false
    csv = false
    legacy = false
  for i in 1 .. paramCount():
    case paramStr(i)
    of "--all": showAll = true
    of "--csv": csv = true
    of "--legacy": legacy = true
    else: discard
  let sim = initSimServer()
  let packet =
    if legacy:
      sim.buildInitPacket(encoded = false)
    else:
      sim.playerInitPacketBytes()
  echo &"init packet bytes: {packet.len}"
  var rows: seq[SpriteRow]
  var decoded = initTable[int, DecodedSprite]()
  var offset = 0
  while offset < packet.len:
    let size = packet.spriteMessageBytes(offset)
    let messages = packet[offset ..< offset + size].parseSpritePacket()
    let legacyMessage = packet[offset] == SpriteMessageSprite
    offset += size
    if messages.len != 1 or messages[0].kind != spkSprite:
      continue
    let def = messages[0].sprite
    var source: DecodedSprite
    let sourceId = def.paletteSwapSourceId()
    if sourceId >= 0 and decoded.hasKey(sourceId):
      source = decoded[sourceId]
    let sprite = def.decodeSprite(source)
    decoded[def.id] = sprite
    var legacyPacket: seq[uint8]
    legacyPacket.addSprite(
      def.id, def.width, def.height, sprite.pixels, def.label
    )
    rows.add(SpriteRow(
      id: def.id,
      label: def.label,
      width: def.width,
      height: def.height,
      encoding: def.encodingName(legacyMessage),
      wireBytes: size,
      legacyBytes: legacyPacket.len,
      rawBytes: sprite.pixels.len,
      colors: sprite.pixels.uniqueColors()
    ))
  rows.sort(proc(a, b: SpriteRow): int = b.wireBytes - a.wireBytes)
  report(rows, (if showAll: rows.len else: 15), csv)

main()
