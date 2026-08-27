## Reads Heartleaf game.log (or older per-gnome logs) and writes an
## HTML+SVG chart of every gnome's LLM calls. Y is wall-clock time, so a
## slow reply is a taller box and a retry is another box just below the
## failed one. Gray bands are leapfrog movement slices. Light red marks a
## gnome in conversation. Game hours, wakeup, dinner, sleep, and veggies
## picked sit on that same real-time axis.
##
##   nim r tools/llm_chart.nim <log-dir-or-files> [--out:llm_calls.html]
##                            [--game:N] [--tufte-dir:DIR]

import
  std/[algorithm, json, os, strutils, tables],
  heartleaf/[common, protocol]

const
  PreloadFonts = [
    "ETBembo-RomanOSF.otf",
    "ETBembo-DisplayItalic.otf",
    "ETBembo-SemiBoldOSF.otf"
  ]
  Paper = "#fffff8"
  Ink = "#111111"
  Muted = "#666666"
  HourLine = "#b0b0a8"
    ## Fainter than wakeup/dinner/veggies, still visible on gray walk bands.
  Failed = "#c8c8c0"
  TufteRed = "#f03b20"
  WalkBand = "#e8e8e4"
  ConversationBg = "#ffe8e6"
  Serif = "ETBembo, Palatino Linotype, Palatino, serif"
  ChartLeft = 88
  ChartTop = 118
  ChartRight = 108
  ChartBottom = 28
  ColWidth = 54
  BarWidth = 22
  PixelsPerSecond = 15.0
  MinBarHeight = 3
  MinWalkHeight = 1
    ## A zipped movement slice is often under a pixel; keep a 1px band.
  InterruptPad = 3
  HousePad = 4
  DayStroke = 1.25
  HourStroke = 1.0
  DollarsPerMillion = 1.0
    ## Rough cost: one dollar per million tokens, cache counted.

type
  LlmKind* = enum
    LlmRequest
    LlmReply
    LlmAbandon
    LlmInterrupt
    LlmClock
    LlmVeggies
    LlmEnter
    LlmExit
    LlmTurn
    LlmConvoEnter
    LlmConvoExit

  LlmEvent* = object
    kind*: LlmKind
    gnome*: string
    game*: int
    day*: int
    minutes*: int
    tick*: int
    now*: float
    reason*: string
    outcome*: string
    tag*: string
    house*: int
    own*: bool
    tokens*: int
    turnKind*: string
    turnIndex*: int
    members*: string

  LlmInterruptMark* = object
    day*: int
    minutes*: int
    now*: float
    reason*: string

  ChartInterrupt* = object
    gnome*: string
    day*: int
    minutes*: int
    now*: float
    reason*: string

  ClockMark* = object
    day*: int
    minutes*: int
    now*: float

  HouseStay* = object
    gnome*: string
    house*: int
    own*: bool
    startMinutes*: int
    endMinutes*: int
    startNow*: float
    endNow*: float
    pending*: bool

  LlmCall* = object
    gnome*: string
    game*: int
    startDay*: int
    startMinutes*: int
    startNow*: float
    endDay*: int
    endMinutes*: int
    endNow*: float
    outcome*: string
    pending*: bool
    tokens*: int
    turnIndex*: int
    interrupts*: seq[LlmInterruptMark]

  TurnMark* = object
    index*: int
    kind*: string
    now*: float

  TalkSpan* = object
    gnome*: string
    startTurn*: int
    endTurn*: int
    startNow*: float
    endNow*: float

proc fail(message: string) =
  ## Prints one error and stops.
  stderr.writeLine(message)
  quit(1)

proc xmlEscape(text: string): string =
  ## Escapes text for HTML and SVG.
  result = text
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")

proc fieldValue(text, key: string): string =
  ## The value of one key=value token in an LLM log line.
  let prefix = key & "="
  for part in text.splitWhitespace():
    if part.startsWith(prefix):
      return part[prefix.len .. ^1]
  ""

proc parseIntField(text, key: string, fallback = 0): int =
  ## An integer key=value token, or fallback when missing.
  let value = text.fieldValue(key)
  if value.len == 0:
    return fallback
  try:
    parseInt(value)
  except ValueError:
    fallback

proc parseFloatField(text, key: string, fallback = 0.0): float =
  ## A float key=value token, or fallback when missing.
  let value = text.fieldValue(key)
  if value.len == 0:
    return fallback
  try:
    parseFloat(value)
  except ValueError:
    fallback

proc jsonNow(node: JsonNode): float =
  ## Wall-clock seconds from one log JSON node.
  let value = node{"now"}
  if value.isNil or value.kind == JNull:
    return 0
  case value.kind
  of JFloat:
    value.getFloat()
  of JInt:
    value.getInt().float
  of JString:
    try:
      parseFloat(value.getStr())
    except ValueError:
      0.0
  else:
    0.0

proc parseKind(text: string): string =
  ## The LLM kind word from a log line, or "".
  var body = text.strip()
  let llmAt = body.find(": llm ")
  if llmAt >= 0:
    body = body[llmAt + 2 .. ^1]
  else:
    let houseAt = body.find(": house ")
    if houseAt >= 0:
      body = body[houseAt + 2 .. ^1]
    else:
      let convAt = body.find(": conversation ")
      if convAt >= 0:
        body = body[convAt + 2 .. ^1]
  if body.startsWith("llm turn"):
    return "turn"
  if body.startsWith("conversation enter"):
    return "convo-enter"
  if body.startsWith("conversation exit"):
    return "convo-exit"
  if body.startsWith("clock "):
    return "clock"
  if body.startsWith("llm request"):
    return "request"
  if body.startsWith("llm reply"):
    return "reply"
  if body.startsWith("llm abandon"):
    return "abandon"
  if body.startsWith("llm interrupt"):
    return "interrupt"
  if body.startsWith("llm clock"):
    return "clock"
  if body.startsWith("veggies"):
    return "veggies"
  if body.startsWith("house enter"):
    return "enter"
  if body.startsWith("house exit"):
    return "exit"
  ""

proc kindFromName(name: string): LlmKind =
  ## Maps a kind word to the enum.
  case name
  of "request": LlmRequest
  of "reply": LlmReply
  of "abandon": LlmAbandon
  of "clock": LlmClock
  of "veggies": LlmVeggies
  of "enter": LlmEnter
  of "exit": LlmExit
  of "turn": LlmTurn
  of "convo-enter": LlmConvoEnter
  of "convo-exit": LlmConvoExit
  else: LlmInterrupt

proc gnomeFromPath(path: string): string =
  ## The gnome name encoded in a log file stem, if any.
  let stem = path.splitFile().name
  for name in PlayerNames:
    if stem == name or stem.endsWith("-" & name):
      return name
  ""

proc gnomeFromLine(text: string): string =
  ## The gnome prefix of a server stdout line, if any.
  for needle in [": llm ", ": house ", ": conversation "]:
    let at = text.find(needle)
    if at <= 0:
      continue
    let name = text[0 ..< at]
    if name in PlayerNames:
      return name
  ""

proc usageTokens(text: string): int =
  ## Input, cache, and output tokens on one reply line.
  text.parseIntField("in") +
    text.parseIntField("cacheRead") +
    text.parseIntField("cacheWrite") +
    text.parseIntField("out")

proc eventFromBody(
  kindName, body, gnome: string,
  game = 1
): LlmEvent =
  ## One LLM event from a parseable log body.
  result = LlmEvent(
    kind: kindName.kindFromName(),
    gnome: gnome,
    game: game,
    day: body.parseIntField("day", 1),
    minutes: body.parseIntField("minutes", DayStartMinutes),
    tick: body.parseIntField("tick"),
    now: body.parseFloatField("now"),
    reason: body.fieldValue("reason"),
    outcome: body.fieldValue("outcome"),
    tag: body.fieldValue("tag"),
    house: body.parseIntField("house"),
    own: body.fieldValue("own") == "yes",
    tokens: body.usageTokens(),
    turnKind: body.fieldValue("kind"),
    turnIndex: body.parseIntField("index", body.parseIntField("turn")),
    members: body.fieldValue("members")
  )
  if body.fieldValue("ignored").len > 0:
    result.outcome = "ignored"
  if result.day <= 0:
    result.day = 1

proc parseLlmLine*(line, gnomeHint: string): LlmEvent =
  ## Parses one JSON log frame or one stdout/audit line. kind "" means skip.
  let stripped = line.strip()
  if stripped.len == 0:
    return
  if stripped.startsWith("{"):
    try:
      let node = parseJson(stripped)
      let role = node{"role"}.getStr()
      let text = node{"text"}.getStr()
      var kindName = node{"kind"}.getStr()
      if kindName.len == 0:
        kindName = text.parseKind()
      if role == "llm" or role == "clock" or role == "veggies" or
          role == "house" or role == "conversation" or kindName.len > 0:
        if kindName.len == 0:
          return
        var gnome = node{"gnome"}.getStr()
        if gnome.len == 0:
          gnome = gnomeHint
        result = kindName.eventFromBody(
          text, gnome, node{"game"}.getInt(1)
        )
        if node.hasKey("day"):
          result.day = node{"day"}.getInt(result.day)
        if node.hasKey("minutes"):
          result.minutes = node{"minutes"}.getInt(result.minutes)
        if node.hasKey("tick"):
          result.tick = node{"tick"}.getInt(result.tick)
        let stamped = node.jsonNow()
        if stamped > 0:
          result.now = stamped
        return
    except CatchableError:
      discard
  let kindName = stripped.parseKind()
  if kindName.len == 0:
    return
  var gnome = stripped.gnomeFromLine()
  if gnome.len == 0:
    gnome = gnomeHint
  if gnome.len == 0:
    return
  result = kindName.eventFromBody(stripped, gnome)

proc parseLlmText*(text, gnomeHint: string): seq[LlmEvent] =
  ## Every LLM event in one log blob.
  for line in text.splitLines():
    let event = line.parseLlmLine(gnomeHint)
    if event.gnome.len > 0:
      result.add(event)

proc collectLogFiles(paths: seq[string]): seq[string] =
  ## Expands directories into log files. A dir with game.log is read as
  ## the village log; otherwise every *.log is used, for older plays.
  for path in paths:
    if dirExists(path):
      let gameLog = path / "game.log"
      if fileExists(gameLog):
        result.add(gameLog)
      else:
        for kind, file in walkDir(path):
          if kind == pcFile and file.endsWith(".log"):
            result.add(file)
    elif fileExists(path):
      result.add(path)
    else:
      fail("log not found: " & path)
  result.sort()

proc gameMinutes(day, minutes: int): int =
  ## Minutes from 9am on day 1, clamped to the playable day.
  let dayIndex = max(1, day) - 1
  let clamped = min(max(minutes, DayStartMinutes), DayEndMinutes)
  dayIndex * DayTotalMinutes + (clamped - DayStartMinutes)

proc inferredNow(day, minutes: int): float =
  ## A stand-in wall time from the game clock.
  gameMinutes(day, minutes).float * (SecondsPerGameHour.float / 60.0)

proc fillMissingNow*(events: var seq[LlmEvent]) =
  ## Fills events that have no wall time. If any event is stamped, the
  ## rest are placed relative to it using the game clock; otherwise the
  ## default seconds-per-hour stand-in is used.
  var
    stamped = false
    refNow = 0.0
    refGame = 0.0
  for event in events:
    if event.now > 0:
      stamped = true
      refNow = event.now
      refGame = gameMinutes(event.day, event.minutes).float
      break
  for event in events.mitems:
    if event.now > 0:
      continue
    let game = gameMinutes(event.day, event.minutes).float
    event.now =
      if stamped:
        refNow + (game - refGame) * (SecondsPerGameHour.float / 60.0)
      else:
        inferredNow(event.day, event.minutes)

proc loadLlmEvents*(paths: seq[string]): seq[LlmEvent] =
  ## Reads LLM events from log files and directories.
  for path in paths.collectLogFiles():
    result.add(readFile(path).parseLlmText(path.gnomeFromPath()))
  result.fillMissingNow()

proc eventNow(event: LlmEvent): float =
  ## Wall time for one event, falling back to the game clock.
  if event.now > 0:
    event.now
  else:
    inferredNow(event.day, event.minutes)

proc pairLlmCalls*(events: seq[LlmEvent], game: int): seq[LlmCall] =
  ## Turns a stream of events into one bar per in-flight request.
  var open: Table[string, LlmCall]
  var lastAt: Table[string, tuple[day, minutes: int, now: float]]
  var lastTurn: Table[string, int]
  for event in events:
    if game > 0 and event.game != game:
      continue
    if event.gnome.len == 0:
      continue
    let at = event.eventNow()
    if event.kind != LlmClock and event.kind != LlmVeggies:
      lastAt[event.gnome] = (event.day, event.minutes, at)
    case event.kind
    of LlmClock, LlmVeggies, LlmEnter, LlmExit, LlmTurn,
        LlmConvoEnter, LlmConvoExit:
      if event.kind == LlmTurn:
        lastTurn[event.gnome] = event.turnIndex
    of LlmRequest:
      if event.gnome in open:
        var previous = open[event.gnome]
        previous.endDay = event.day
        previous.endMinutes = event.minutes
        previous.endNow = at
        previous.pending = false
        result.add(previous)
      open[event.gnome] = LlmCall(
        gnome: event.gnome,
        game: event.game,
        startDay: event.day,
        startMinutes: event.minutes,
        startNow: at,
        endDay: event.day,
        endMinutes: event.minutes,
        endNow: at,
        pending: true,
        turnIndex: lastTurn.getOrDefault(event.gnome, event.turnIndex)
      )
    of LlmReply, LlmAbandon:
      if event.gnome in open:
        var call = open[event.gnome]
        call.endDay = event.day
        call.endMinutes = event.minutes
        call.endNow = at
        call.pending = false
        if event.kind == LlmAbandon:
          call.outcome = "abandon"
        else:
          call.outcome = event.outcome
        call.tokens = event.tokens
        result.add(call)
        open.del(event.gnome)
    of LlmInterrupt:
      if event.gnome in open:
        var call = open[event.gnome]
        call.interrupts.add(LlmInterruptMark(
          day: event.day,
          minutes: event.minutes,
          now: at,
          reason: event.reason
        ))
        open[event.gnome] = call
  for gnome, call in open.pairs:
    var closed = call
    if gnome in lastAt:
      closed.endDay = lastAt[gnome].day
      closed.endMinutes = lastAt[gnome].minutes
      closed.endNow = lastAt[gnome].now
    result.add(closed)
  result.sort(proc(a, b: LlmCall): int =
    result = cmp(a.gnome, b.gnome)
    if result == 0:
      result = cmp(a.startNow, b.startNow)
    if result == 0:
      result = cmp(a.startDay, b.startDay)
    if result == 0:
      result = cmp(a.startMinutes, b.startMinutes))

proc collectClockMarks*(events: seq[LlmEvent], game: int): seq[ClockMark] =
  ## The first wall time each game hour was seen, from clock stamps.
  var first: Table[(int, int), float]
  var anyClock = false
  for event in events:
    if game > 0 and event.game != game:
      continue
    if event.kind == LlmClock:
      anyClock = true
      break
  for event in events:
    if game > 0 and event.game != game:
      continue
    if anyClock:
      if event.kind != LlmClock:
        continue
    elif event.minutes mod 60 != 0:
      continue
    let at = event.eventNow()
    let hour = (event.minutes div 60) * 60
    let key = (max(1, event.day), hour)
    if key notin first or at < first[key]:
      first[key] = at
  for key, at in first.pairs:
    result.add(ClockMark(day: key[0], minutes: key[1], now: at))
  result.sort(proc(a, b: ClockMark): int =
    result = cmp(a.now, b.now)
    if result == 0:
      result = cmp(a.day, b.day)
    if result == 0:
      result = cmp(a.minutes, b.minutes))

proc collectVeggieMarks*(events: seq[LlmEvent], game: int): seq[ClockMark] =
  ## The first wall time each day the gardens were empty.
  var first: Table[int, ClockMark]
  for event in events:
    if game > 0 and event.game != game:
      continue
    if event.kind != LlmVeggies:
      continue
    let
      day = max(1, event.day)
      at = event.eventNow()
    if day notin first or at < first[day].now:
      first[day] = ClockMark(
        day: day, minutes: event.minutes, now: at
      )
  for mark in first.values:
    result.add(mark)
  result.sort(proc(a, b: ClockMark): int =
    result = cmp(a.now, b.now)
    if result == 0:
      result = cmp(a.day, b.day))

proc collectInterruptMarks*(
  events: seq[LlmEvent],
  game: int
): seq[ChartInterrupt] =
  ## Every interrupt, including those that happened between calls.
  for event in events:
    if game > 0 and event.game != game:
      continue
    if event.kind != LlmInterrupt:
      continue
    if event.gnome.len == 0:
      continue
    result.add(ChartInterrupt(
      gnome: event.gnome,
      day: event.day,
      minutes: event.minutes,
      now: event.eventNow(),
      reason: event.reason
    ))
  result.sort(proc(a, b: ChartInterrupt): int =
    result = cmp(a.now, b.now)
    if result == 0:
      result = cmp(a.gnome, b.gnome))

proc collectTurns*(events: seq[LlmEvent], game: int): seq[TurnMark] =
  ## Wall-clock start of each leapfrog phase, from llm turn stamps.
  var seen: Table[int, TurnMark]
  for event in events:
    if game > 0 and event.game != game:
      continue
    if event.kind != LlmTurn:
      continue
    if event.turnIndex notin seen:
      seen[event.turnIndex] = TurnMark(
        index: event.turnIndex,
        kind: event.turnKind,
        now: event.eventNow()
      )
  for mark in seen.values:
    result.add(mark)
  result.sort(proc(a, b: TurnMark): int =
    cmp(a.index, b.index))

proc collectTalks*(events: seq[LlmEvent], game: int): seq[TalkSpan] =
  ## Conversation spans in wall time, for the light red column fill.
  var open: Table[string, tuple[turn: int, now: float]]
  var lastTurn = 0
  var lastNow = 0.0
  for event in events:
    if game > 0 and event.game != game:
      continue
    let at = event.eventNow()
    if at > lastNow:
      lastNow = at
    if event.kind == LlmTurn:
      lastTurn = max(lastTurn, event.turnIndex)
    elif event.kind == LlmConvoEnter:
      if event.gnome.len > 0 and event.gnome notin open:
        open[event.gnome] = (event.turnIndex, at)
    elif event.kind == LlmConvoExit:
      if event.gnome.len == 0:
        continue
      let start = open.getOrDefault(event.gnome, (event.turnIndex, at))
      result.add(TalkSpan(
        gnome: event.gnome,
        startTurn: start.turn,
        endTurn: event.turnIndex,
        startNow: start.now,
        endNow: at
      ))
      open.del(event.gnome)
  for gnome, start in open.pairs:
    result.add(TalkSpan(
      gnome: gnome,
      startTurn: start.turn,
      endTurn: lastTurn,
      startNow: start.now,
      endNow: lastNow
    ))

proc pairHouseStays*(events: seq[LlmEvent], game: int): seq[HouseStay] =
  ## Turns enter/exit events into one dashed stay per visit.
  var open: Table[string, HouseStay]
  var lastAt: Table[string, tuple[minutes: int, now: float]]
  for event in events:
    if game > 0 and event.game != game:
      continue
    if event.gnome.len == 0:
      continue
    let at = event.eventNow()
    lastAt[event.gnome] = (event.minutes, at)
    case event.kind
    of LlmEnter:
      if event.gnome in open:
        var previous = open[event.gnome]
        previous.endMinutes = event.minutes
        previous.endNow = at
        previous.pending = false
        result.add(previous)
      open[event.gnome] = HouseStay(
        gnome: event.gnome,
        house: event.house,
        own: event.own,
        startMinutes: event.minutes,
        endMinutes: event.minutes,
        startNow: at,
        endNow: at,
        pending: true
      )
    of LlmExit:
      if event.gnome in open:
        var stay = open[event.gnome]
        stay.endMinutes = event.minutes
        stay.endNow = at
        stay.pending = false
        result.add(stay)
        open.del(event.gnome)
    else:
      discard
  for gnome, stay in open.pairs:
    var closed = stay
    if gnome in lastAt:
      closed.endMinutes = lastAt[gnome].minutes
      closed.endNow = lastAt[gnome].now
    result.add(closed)
  result.sort(proc(a, b: HouseStay): int =
    result = cmp(a.gnome, b.gnome)
    if result == 0:
      result = cmp(a.startNow, b.startNow))

proc selectedGame*(events: seq[LlmEvent], requested: int): int =
  ## The game to chart: the request, else the latest game in the logs.
  if requested > 0:
    return requested
  for event in events:
    if event.game > result:
      result = event.game
  if result <= 0:
    result = 1

proc latestRunStart*(events: seq[LlmEvent], game: int): float =
  ## Wall time of the last day-1 9:00am cluster when logs were appended
  ## from another play of the same game. Zero when there is only one run.
  var starts: seq[float]
  for event in events:
    if game > 0 and event.game != game:
      continue
    if event.kind == LlmClock and event.day == 1 and
        event.minutes == DayStartMinutes and event.now > 0:
      starts.add(event.now)
  starts.sort()
  var clusters: seq[float]
  for t in starts:
    if clusters.len == 0 or t - clusters[^1] > 60.0:
      clusters.add(t)
  if clusters.len <= 1:
    return 0
  clusters[^1]

proc eventsFrom*(events: seq[LlmEvent], startNow: float): seq[LlmEvent] =
  ## Drops an older appended play that started before startNow.
  if startNow <= 0:
    return events
  for event in events:
    if event.now >= startNow - 2.0:
      result.add(event)

proc chartDays*(calls: seq[LlmCall]): int =
  ## How many days the chart must cover.
  result = 1
  for call in calls:
    result = max(result, call.startDay)
    result = max(result, call.endDay)
  result = max(1, min(result, DefaultDayCount))

proc hourLabel(minutes: int): string =
  ## A short clock label, noon for 12:00pm.
  let wrapped = ((minutes mod (24 * 60)) + (24 * 60)) mod (24 * 60)
  var hour = wrapped div 60
  if hour == 12:
    return "noon"
  let suffix =
    if hour >= 12:
      "pm"
    else:
      "am"
  hour = hour mod 12
  if hour == 0:
    hour = 12
  $hour & suffix

proc hourSideLabel(minutes: int): string =
  ## Right-side label for hours that are also day events.
  if minutes == DayStartMinutes:
    return "wakeup"
  if minutes == DinnerMinutes:
    return "dinner"
  if minutes == DayEndMinutes:
    return "sleep"
  ""

proc yAt(now, origin: float): float =
  ## SVG y for one wall-clock time.
  ChartTop.float + (now - origin) * PixelsPerSecond

proc callFailed(call: LlmCall): bool =
  ## True when the reply was not a usable decision.
  call.outcome.len > 0 and call.outcome != "usable" and
    call.outcome != "ignored"

proc callInvalid(call: LlmCall): bool =
  ## True when the model sent illegal JSON or an illegal action.
  call.outcome == "ignored" or call.outcome == "parse"

proc colCenter(index: int): float =
  ## Column center x for one house.
  ChartLeft.float + index.float * ColWidth.float + ColWidth.float / 2.0

proc timeBounds(
  calls: seq[LlmCall],
  clocks: seq[ClockMark],
  houses: seq[HouseStay] = @[],
  ticks: seq[ChartInterrupt] = @[],
  veggies: seq[ClockMark] = @[],
  turns: seq[TurnMark] = @[],
  talks: seq[TalkSpan] = @[]
): (float, float) =
  ## The wall-clock span of the chart.
  var
    lo = 1.0e300
    hi = -1.0e300
  template note(at: float) =
    lo = min(lo, at)
    hi = max(hi, at)
  for call in calls:
    note(call.startNow)
    note(call.endNow)
    for mark in call.interrupts:
      note(mark.now)
  for mark in clocks:
    note(mark.now)
  for stay in houses:
    note(stay.startNow)
    note(stay.endNow)
  for mark in ticks:
    note(mark.now)
  for mark in veggies:
    note(mark.now)
  for mark in turns:
    note(mark.now)
  for span in talks:
    note(span.startNow)
    note(span.endNow)
  if hi < lo:
    (0.0, 1.0)
  else:
    (lo, max(hi, lo + 1.0))

proc sideLabelSvg(x, y: float, text: string): string =
  ## One muted label to the right of the plot.
  result.add "<text x=\"" & $x & "\" y=\"" & $(y + 4)
  result.add "\" text-anchor=\"start\" fill=\"" & Muted
  result.add "\" font-family=\"" & Serif
  result.add "\" font-size=\"13\">"
  result.add text.xmlEscape()
  result.add "</text>\n"

proc interruptTickSvg(
  gnome: string,
  now: float,
  reason: string,
  origin: float
): string =
  ## One red interrupt tick on a gnome column.
  let house = gnome.houseIndexForPlayerName()
  if house < 0:
    return
  let x = colCenter(house) - BarWidth.float / 2.0
  let my = yAt(now, origin)
  let x1 = x - InterruptPad.float
  let x2 = x + BarWidth.float + InterruptPad.float
  result.add "<line x1=\"" & $x1 & "\" y1=\"" & $my
  result.add "\" x2=\"" & $x2 & "\" y2=\"" & $my
  result.add "\" stroke=\"" & TufteRed
  result.add "\" stroke-width=\"1.75\">"
  result.add "<title>"
  result.add (gnome & " interrupt " & reason).xmlEscape()
  result.add "</title></line>\n"

proc moveWindows(turns: seq[TurnMark]): seq[tuple[a, b: float]] =
  ## Wall-clock span of each movement phase.
  for i, mark in turns:
    if mark.kind != "move" or mark.now <= 0:
      continue
    let b =
      if i + 1 < turns.len and turns[i + 1].now > mark.now:
        turns[i + 1].now
      else:
        mark.now + 0.01
    result.add((mark.now, b))

proc renderLlmChart*(
  calls: seq[LlmCall],
  clocks: seq[ClockMark],
  veggies: seq[ClockMark] = @[],
  houses: seq[HouseStay] = @[],
  ticks: seq[ChartInterrupt] = @[],
  turns: seq[TurnMark] = @[],
  talks: seq[TalkSpan] = @[]
): string =
  ## One vertical Gantt: gnomes across, wall-clock time down.
  let
    (origin, last) = calls.timeBounds(
      clocks, houses, ticks, veggies, turns, talks
    )
    plotHeight = max(HourStroke, (last - origin) * PixelsPerSecond)
    width = ChartLeft + PlayerNames.len * ColWidth + ChartRight
    height = int(ChartTop.float + plotHeight + ChartBottom.float + 0.5)
    plotRight = ChartLeft + PlayerNames.len * ColWidth
    plotWidth = PlayerNames.len * ColWidth
  result.add "<svg class=\"llm-chart-svg\" width=\"" & $width
  result.add "\" height=\"" & $height & "\" viewBox=\"0 0 "
  result.add $width & " " & $height
  result.add "\" role=\"img\" aria-label=\"Heartleaf LLM calls\">\n"
  result.add "<rect x=\"0\" y=\"0\" width=\"" & $width
  result.add "\" height=\"" & $height & "\" fill=\"" & Paper & "\"/>\n"
  for window in turns.moveWindows():
    var y1 = yAt(window.a, origin)
    var y2 = yAt(window.b, origin)
    if y2 < y1:
      swap(y1, y2)
    if y2 - y1 < MinWalkHeight.float:
      y2 = y1 + MinWalkHeight.float
    result.add "<rect x=\"" & $ChartLeft & "\" y=\"" & $y1
    result.add "\" width=\"" & $plotWidth & "\" height=\""
    result.add $(y2 - y1) & "\" fill=\"" & WalkBand & "\"/>\n"
  for span in talks:
    let house = span.gnome.houseIndexForPlayerName()
    if house < 0:
      continue
    var y1 = yAt(span.startNow, origin)
    var y2 = yAt(span.endNow, origin)
    if y2 < y1:
      swap(y1, y2)
    if y2 - y1 < MinBarHeight.float:
      y2 = y1 + MinBarHeight.float
    let x = colCenter(house) - BarWidth.float / 2.0
    result.add "<rect x=\"" & $x & "\" y=\"" & $y1
    result.add "\" width=\"" & $BarWidth & "\" height=\""
    result.add $(y2 - y1) & "\" fill=\"" & ConversationBg
    result.add "\"><title>"
    result.add (span.gnome & " conversation").xmlEscape()
    result.add "</title></rect>\n"
  for i, name in PlayerNames:
    let x = colCenter(i)
    let y = ChartTop.float - 10.0
    result.add "<text x=\"" & $x & "\" y=\"" & $y
    result.add "\" text-anchor=\"start\" fill=\"" & Ink
    result.add "\" font-family=\"" & Serif
    result.add "\" font-size=\"16\" transform=\"rotate(-45 "
    result.add $x & " " & $y & ")\">"
    result.add name.xmlEscape()
    result.add "</text>\n"
  for call in calls:
    let house = call.gnome.houseIndexForPlayerName()
    if house < 0:
      continue
    let x = colCenter(house) - BarWidth.float / 2.0
    var y1 = yAt(call.startNow, origin)
    var y2 = yAt(call.endNow, origin)
    if y2 < y1:
      swap(y1, y2)
    if y2 - y1 < MinBarHeight.float:
      y2 = y1 + MinBarHeight.float
    var dash = ""
    if call.pending:
      dash = " stroke-dasharray=\"3 2\""
    elif call.callInvalid:
      dash = " stroke-dasharray=\"1 2\""
    let took = max(0.0, call.endNow - call.startNow)
    let title = call.gnome & " " &
      call.startMinutes.clockName() & "–" &
      call.endMinutes.clockName() & " " &
      formatFloat(took, ffDecimal, 1) & "s" &
      (if call.outcome.len > 0: " " & call.outcome else: "")
    let fill =
      if call.callFailed:
        Failed
      else:
        Paper
    result.add "<rect x=\"" & $x & "\" y=\"" & $y1
    result.add "\" width=\"" & $BarWidth & "\" height=\""
    result.add $(y2 - y1) & "\" fill=\"" & fill
    result.add "\" stroke=\"" & Ink & "\" stroke-width=\"1\""
    result.add dash & "><title>"
    result.add title.xmlEscape()
    result.add "</title></rect>\n"
  for mark in ticks:
    result.add interruptTickSvg(
      mark.gnome, mark.now, mark.reason, origin
    )
  for stay in houses:
    let col = stay.gnome.houseIndexForPlayerName()
    if col < 0:
      continue
    let x = colCenter(col) - BarWidth.float / 2.0 - HousePad.float
    var y1 = yAt(stay.startNow, origin)
    var y2 = yAt(stay.endNow, origin)
    if y2 < y1:
      swap(y1, y2)
    if y2 - y1 < MinBarHeight.float:
      y2 = y1 + MinBarHeight.float
    let stroke =
      if stay.own:
        TufteRed
      else:
        Ink
    let where =
      if stay.own:
        "own house"
      elif stay.house >= 1:
        (stay.house - 1).playerNameForHouse() & "'s house"
      else:
        "a house"
    let title = stay.gnome & " in " & where & " " &
      stay.startMinutes.clockName() & "–" &
      stay.endMinutes.clockName()
    result.add "<rect x=\"" & $x & "\" y=\"" & $y1
    result.add "\" width=\"" & $(BarWidth + HousePad * 2)
    result.add "\" height=\"" & $(y2 - y1)
    result.add "\" fill=\"none\" stroke=\"" & stroke
    result.add "\" stroke-width=\"1.25\" stroke-dasharray=\"3 2\">"
    result.add "<title>"
    result.add title.xmlEscape()
    result.add "</title></rect>\n"
  for mark in clocks:
    let y = yAt(mark.now, origin)
    let dayStart = mark.minutes == DayStartMinutes
    let dayEnd = mark.minutes == DayEndMinutes
    let stroke =
      if dayStart or dayEnd:
        Ink
      else:
        HourLine
    let weight =
      if dayStart or dayEnd:
        $DayStroke
      else:
        $HourStroke
    result.add "<line x1=\"" & $ChartLeft & "\" y1=\"" & $y
    result.add "\" x2=\"" & $plotRight & "\" y2=\"" & $y
    result.add "\" stroke=\"" & stroke & "\" stroke-width=\""
    result.add weight & "\"/>\n"
    if dayStart:
      result.add "<text x=\"" & $(ChartLeft - 10) & "\" y=\"" & $(y - 10)
      result.add "\" text-anchor=\"end\" fill=\"" & Ink
      result.add "\" font-family=\"" & Serif
      result.add "\" font-size=\"16\">Day " & $mark.day & "</text>\n"
    result.add "<text x=\"" & $(ChartLeft - 10) & "\" y=\"" & $(y + 4)
    result.add "\" text-anchor=\"end\" fill=\"" & Muted
    result.add "\" font-family=\"" & Serif
    result.add "\" font-size=\"13\">"
    result.add hourLabel(mark.minutes).xmlEscape()
    result.add "</text>\n"
    let side = mark.minutes.hourSideLabel()
    if side.len > 0:
      result.add sideLabelSvg(plotRight.float + 8.0, y, side)
  for mark in veggies:
    let y = yAt(mark.now, origin)
    result.add "<line x1=\"" & $ChartLeft & "\" y1=\"" & $y
    result.add "\" x2=\"" & $plotRight & "\" y2=\"" & $y
    result.add "\" stroke=\"" & Muted & "\" stroke-width=\"1\""
    result.add " stroke-dasharray=\"4 3\"/>\n"
    result.add sideLabelSvg(
      plotRight.float + 8.0, y, "veggies picked"
    )
  result.add "</svg>\n"

proc tokenCost(tokens: int): string =
  ## Dollars at one dollar per million tokens.
  "$" & formatFloat(
    tokens.float / 1_000_000.0 * DollarsPerMillion, ffDecimal, 2
  )

proc avgSeconds(seconds: float, calls: int): string =
  ## Mean call duration, or a dash with no calls.
  if calls > 0:
    formatFloat(seconds / calls.float, ffDecimal, 1)
  else:
    "-"

proc callCounts(calls: seq[LlmCall]): seq[
    tuple[
      gnome: string,
      calls, interrupts, tokens: int,
      seconds: float
    ]
] =
  ## Per-gnome totals for the summary table.
  var byName: Table[string, tuple[
    calls, interrupts, tokens: int, seconds: float
  ]]
  for name in PlayerNames:
    byName[name] = (0, 0, 0, 0.0)
  for call in calls:
    if call.gnome notin byName:
      continue
    var row = byName[call.gnome]
    inc row.calls
    row.interrupts += call.interrupts.len
    row.tokens += call.tokens
    row.seconds += max(0.0, call.endNow - call.startNow)
    byName[call.gnome] = row
  for name in PlayerNames:
    let row = byName[name]
    result.add((
      name, row.calls, row.interrupts, row.tokens, row.seconds
    ))

proc summaryRow(
  name: string,
  calls, interrupts, tokens: int,
  seconds, idle: float
): string =
  ## One summary table row.
  result.add "<tr><td>"
  result.add name.xmlEscape()
  result.add "</td><td>"
  result.add $calls
  result.add "</td><td>"
  result.add formatFloat(seconds, ffDecimal, 1)
  result.add "</td><td>"
  result.add avgSeconds(seconds, calls)
  result.add "</td><td>"
  result.add formatFloat(idle, ffDecimal, 1)
  result.add "</td><td>"
  result.add $interrupts
  result.add "</td><td>"
  result.add $tokens
  result.add "</td><td>"
  result.add tokens.tokenCost()
  result.add "</td></tr>\n"

proc renderSummary(
  calls: seq[LlmCall],
  clocks: seq[ClockMark] = @[]
): string =
  ## A compact table of calls, averages, idle time, tokens, and cost.
  let (origin, last) = calls.timeBounds(clocks)
  let span = max(0.0, last - origin)
  result.add "<table class=\"wide\">\n"
  result.add "<caption>LLM calls by gnome, in wall-clock seconds. "
  result.add "Non-LLM is time with no call in flight. Cost is $1 per "
  result.add "million tokens, counting input, cache, and output."
  result.add "</caption>\n"
  result.add "<thead><tr><th>Gnome</th><th>Calls</th>"
  result.add "<th>LLM seconds</th><th>Avg LLM Seconds</th>"
  result.add "<th>Non-LLM seconds</th><th>Interrupts held</th>"
  result.add "<th>Tokens</th><th>Cost</th>"
  result.add "</tr></thead>\n"
  result.add "<tbody>\n"
  var
    totalCalls = 0
    totalInterrupts = 0
    totalTokens = 0
    totalSeconds = 0.0
    totalIdle = 0.0
  for row in calls.callCounts():
    let idle = max(0.0, span - row.seconds)
    result.add summaryRow(
      row.gnome, row.calls, row.interrupts, row.tokens, row.seconds, idle
    )
    totalCalls += row.calls
    totalInterrupts += row.interrupts
    totalTokens += row.tokens
    totalSeconds += row.seconds
    totalIdle += idle
  result.add "</tbody>\n<tfoot>\n"
  result.add summaryRow(
    "Total", totalCalls, totalInterrupts, totalTokens,
    totalSeconds, totalIdle
  )
  result.add "</tfoot></table>\n"

proc formatWallSpan*(seconds: float): string =
  ## A short real-time length: 45s, 3 min, 5 min 10s, 1 hr 2 min.
  let total = max(0, seconds.int)
  let hours = total div 3600
  let mins = (total mod 3600) div 60
  let secs = total mod 60
  if hours > 0:
    if mins == 0:
      return $hours & " hr"
    return $hours & " hr " & $mins & " min"
  if mins > 0:
    if secs == 0:
      return $mins & " min"
    return $mins & " min " & $secs & "s"
  $secs & "s"

proc wallSpanLine(
  calls: seq[LlmCall],
  clocks: seq[ClockMark],
  veggies: seq[ClockMark] = @[],
  houses: seq[HouseStay] = @[],
  ticks: seq[ChartInterrupt] = @[],
  turns: seq[TurnMark] = @[],
  talks: seq[TalkSpan] = @[]
): string =
  ## One sentence for how long the chart is in real time.
  let (origin, last) = calls.timeBounds(
    clocks, houses, ticks, veggies, turns, talks
  )
  let span = max(0.0, last - origin)
  "This run took " & span.formatWallSpan() &
    " of real time, top to bottom."

proc extraCss(): string =
  ## Chart-specific rules on top of tufte.css.
  "    main { max-width: 960px; }\n" &
  "    .llm-chart { margin: 1.5rem 0; overflow-x: auto; }\n" &
  "    .llm-chart-svg { display: block; max-width: 100%; height: auto; }\n" &
  "    .llm-chart-svg text { shape-rendering: auto; }\n"

proc renderLlmPage*(
  calls: seq[LlmCall],
  clocks: seq[ClockMark],
  veggies: seq[ClockMark] = @[],
  houses: seq[HouseStay] = @[],
  ticks: seq[ChartInterrupt] = @[],
  cssHref = "tufte.css",
  turns: seq[TurnMark] = @[],
  talks: seq[TalkSpan] = @[]
): string =
  ## A full Tufte HTML page around the LLM chart.
  result.add "<!doctype html>\n<html lang=\"en\">\n<head>\n"
  result.add "  <meta charset=\"utf-8\">\n"
  result.add "  <meta name=\"viewport\" content=\"width=device-width, "
  result.add "initial-scale=1\">\n"
  result.add "  <title>Heartleaf LLM Calls</title>\n"
  for font in PreloadFonts:
    result.add "  <link rel=\"preload\" href=\"fonts/"
    result.add font.xmlEscape()
    result.add "\" as=\"font\" type=\"font/otf\" crossorigin>\n"
  result.add "  <link rel=\"stylesheet\" href=\""
  result.add cssHref.xmlEscape()
  result.add "\">\n  <style>\n"
  result.add extraCss()
  result.add "  </style>\n</head>\n<body>\n<main>\n"
  result.add "  <h1>Heartleaf LLM Calls</h1>\n"
  result.add "  <p>Each column is one gnome. The vertical axis is real "
  result.add "time, top to bottom. A box is an LLM call, stretched by "
  result.add "how long the reply actually took. A gray box failed; a "
  result.add "retry is another box just below it. Game hours are ticks "
  result.add "at the wall times they occurred, so a pause waiting on the "
  result.add "model stretches that hour. Empty space is when that gnome "
  result.add "was not waiting on a reply. A gray band is a leapfrog "
  result.add "movement slice. A light red fill is a gnome in a "
  result.add "conversation. A <mark>red tick</mark> is an interrupt: "
  result.add "an hour, a sighting, chat, or other change. A dotted "
  result.add "border is an illegal reply that was ignored or could "
  result.add "not parse.</p>\n"
  result.add "  <figure class=\"wide llm-chart\">\n"
  result.add renderLlmChart(
    calls, clocks, veggies, houses, ticks, turns, talks
  )
  result.add "    <figcaption>Day and hour labels follow the game clock. "
  result.add "Their spacing follows wall time. Wakeup, dinner, and sleep "
  result.add "sit on those hours. A dashed line marks when the gardens "
  result.add "were empty. A red tick is an interrupt, including the "
  result.add "hourly dummy, even when no call was in flight. A dashed "
  result.add "outline is time inside a house: red for home, black for "
  result.add "someone else's. Gray boxes failed. A dotted border is "
  result.add "an illegal action that was ignored, or JSON that could "
  result.add "not parse. "
  result.add "Dashed boxes are calls that had not finished when the log "
  result.add "ended.</figcaption>\n"
  result.add "  </figure>\n"
  result.add "  <p>"
  result.add wallSpanLine(
    calls, clocks, veggies, houses, ticks, turns, talks
  ).xmlEscape()
  result.add "</p>\n"
  result.add renderSummary(calls, clocks)
  result.add "</main>\n</body>\n</html>\n"
when isMainModule:
  const
    UsageText = "Usage: llm_chart <log-dir-or-files> " &
      "[--out:llm_calls.html] [--game:N] [--tufte-dir:DIR]"
    RepoRoot = currentSourcePath().parentDir().parentDir()
    DefaultTufteDir = RepoRoot.parentDir() / "offstream" / "tufte"
    DefaultOutName = "llm_calls.html"

  proc copyAssets(outDir, tufteDir: string) =
    ## Copies Tufte CSS and fonts next to the HTML page.
    if not fileExists(tufteDir / "tufte.css"):
      fail("tufte.css not found in " & tufteDir)
    createDir(outDir)
    writeFile(outDir / "tufte.css", readFile(tufteDir / "tufte.css"))
    let fontsDir = tufteDir / "fonts"
    if dirExists(fontsDir):
      createDir(outDir / "fonts")
      for file in walkFiles(fontsDir / "*"):
        copyFile(file, outDir / "fonts" / extractFilename(file))

  type
    ChartOptions = object
      inputs: seq[string]
      outPath: string
      tufteDir: string
      game: int

  proc parseOptions(): ChartOptions =
    ## Command line options for the chart tool.
    result.tufteDir = DefaultTufteDir
    result.outPath = DefaultOutName
    let args = commandLineParams()
    var i = 0
    while i < args.len:
      let arg = args[i]
      if arg in ["--help", "-h"]:
        echo UsageText
        quit(0)
      elif arg.startsWith("--out:"):
        result.outPath = arg[6 .. ^1]
      elif arg.startsWith("--game:"):
        result.game = parseInt(arg[7 .. ^1])
      elif arg.startsWith("--tufte-dir:"):
        result.tufteDir = arg[12 .. ^1]
      elif arg.startsWith("--"):
        fail("unknown option: " & arg & "\n" & UsageText)
      else:
        result.inputs.add(arg)
      inc i
    if result.inputs.len == 0:
      fail(UsageText)

  proc main() =
    ## Reads logs and writes the HTML chart.
    let options = parseOptions()
    var events = options.inputs.loadLlmEvents()
    let game = events.selectedGame(options.game)
    events = events.eventsFrom(events.latestRunStart(game))
    let calls = events.pairLlmCalls(game)
    let clocks = events.collectClockMarks(game)
    let veggies = events.collectVeggieMarks(game)
    let houses = events.pairHouseStays(game)
    let ticks = events.collectInterruptMarks(game)
    let turns = events.collectTurns(game)
    let talks = events.collectTalks(game)
    var outPath = options.outPath
    if dirExists(outPath) or outPath.endsWith("/"):
      outPath = outPath / DefaultOutName
    let outDir = outPath.parentDir()
    let dest = if outDir.len == 0: getCurrentDir() else: outDir
    dest.copyAssets(options.tufteDir)
    writeFile(
      outPath,
      calls.renderLlmPage(clocks, veggies, houses, ticks, turns = turns,
        talks = talks)
    )
    echo "wrote ", outPath, " (" & $calls.len & " calls, game " & $game & ")"

  main()
