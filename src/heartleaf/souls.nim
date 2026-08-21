## Soul files are the one thing a Heartleaf player sends the game: a
## markdown system prompt whose first line names the model that plays the
## gnome. The simulation does everything else.

import std/[strutils, tables, unicode]

const
  SoulMaxBytes* = 32_768
  SoulModelIdMaxChars* = 128
  SoulShebang* = "#!"
  SoulAcceptedReply* = "soul accepted"
  SoulRejectedPrefix* = "soul rejected: "
  SoulModelIdChars = {'a'..'z', 'A'..'Z', '0'..'9', '.', '-', '_', ':', '/'}
  KnownModelPrefixes = [
    "anthropic.", "us.anthropic.", "eu.anthropic.", "global.anthropic.",
    "apac.anthropic."
  ]

type
  Soul* = object
    modelId*: string
      ## Bedrock model id from the shebang line.
    text*: string
      ## Body without the shebang line, line endings normalised to LF.
    raw*: string
      ## Bytes as received, so a resend can be recognised as identical.
    username*: string
      ## Display name of the seat that sent the soul.
    seat*: int
      ## House index 0..8 the soul plays.

  SoulError* = object of CatchableError

proc parseSoul*(raw: string): Soul =
  ## Validates a soul file and splits it into model id and body. Raises
  ## SoulError with the rejection reason.
  if raw.len == 0:
    raise newException(SoulError, "soul is empty")
  if raw.len > SoulMaxBytes:
    raise newException(
      SoulError,
      "soul is " & $raw.len & " bytes, the limit is " & $SoulMaxBytes
    )
  if '\0' in raw:
    raise newException(SoulError, "soul contains a NUL byte")
  if validateUtf8(raw) != -1:
    raise newException(SoulError, "soul is not valid UTF-8")
  let text = raw.replace("\r\n", "\n").replace('\r', '\n')
  let lineEnd = text.find('\n')
  let firstLine = if lineEnd < 0: text else: text[0 ..< lineEnd]
  if not firstLine.startsWith(SoulShebang):
    raise newException(
      SoulError,
      "first line must be " & SoulShebang & "<bedrock model id>"
    )
  let modelId = firstLine[SoulShebang.len .. ^1].strip()
  if modelId.len == 0:
    raise newException(SoulError, "shebang line names no model")
  if modelId.len > SoulModelIdMaxChars:
    raise newException(SoulError, "model id is longer than " &
      $SoulModelIdMaxChars & " characters")
  for c in modelId:
    if c notin SoulModelIdChars:
      raise newException(
        SoulError,
        "model id has an unexpected character: " & $c
      )
  let body = if lineEnd < 0: "" else: text[lineEnd + 1 .. ^1]
  if body.strip().len == 0:
    raise newException(SoulError, "soul has no text after the shebang line")
  Soul(modelId: modelId, text: body, raw: raw, seat: -1)

proc knownModelFamily*(modelId: string): bool =
  ## True when the model id looks like an Anthropic Bedrock model.
  for prefix in KnownModelPrefixes:
    if modelId.startsWith(prefix):
      return true
  false

proc soulReply*(soul: Soul): string =
  ## The text frame the game sends back for an accepted soul.
  SoulAcceptedReply & " seat=" & $soul.seat & " model=" & soul.modelId &
    " bytes=" & $soul.raw.len

proc soulRejection*(reason: string): string =
  ## The text frame the game sends back for a rejected soul.
  SoulRejectedPrefix & reason

proc isSoulAccepted*(reply: string): bool =
  ## True when a game reply reports an accepted soul.
  reply.startsWith(SoulAcceptedReply)

proc isSoulRejected*(reply: string): bool =
  ## True when a game reply reports a rejected soul.
  reply.startsWith(SoulRejectedPrefix)

proc seatsWaitingForSouls*(seatCount: int, souls: Table[int, Soul]): seq[int] =
  ## Seats below seatCount that have not sent a soul yet.
  for seat in 0 ..< seatCount:
    if seat notin souls:
      result.add(seat)
