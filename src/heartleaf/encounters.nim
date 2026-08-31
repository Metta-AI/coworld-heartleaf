## Shared conversation encounters: one group of gnomes talking, up to
## nine, with a line log every member sees. Pure data plus join and
## leave helpers used by the brains runtime.

import std/[algorithm, json, math, os, strutils, tables], heartleaf/[common, protocol]

type
  Encounter* = ref object
    id*: int
    members*: seq[int]
    lines*: seq[string]
    anchorX*: int
    anchorY*: int
    hasAnchor*: bool
    anchorSeats*: seq[int]
      ## Outdoor still members the last time the ring was placed.
      ## The ring only moves when someone new joins.
  EncounterBook* = object
    encounters*: Table[int, Encounter]
    nextId*: int
  ConversationEvent* = object
    tick*: int
    enter*: bool
    encounterId*: int
    seat*: int
    members*: seq[int]
    spokenTurn*: bool
      ## A convo-tick row where the seat actually spoke: the unit that
      ## mints heart connections.
  ConversationTimeline* = object
    events*: seq[ConversationEvent]
  ConversationGroup* = object
    id*: int
    members*: seq[int]
  ConversationAnchor* = object
    x*: int
    y*: int
    seats*: seq[int]

proc initEncounterBook*(): EncounterBook =
  ## An empty book of conversations.
  EncounterBook(encounters: initTable[int, Encounter]())

proc encounter*(book: EncounterBook, id: int): Encounter =
  ## The encounter with this id, or nil.
  if id > 0 and id in book.encounters:
    book.encounters[id]
  else:
    nil

proc memberNames*(encounter: Encounter): string =
  ## Sorted gnome names in this conversation.
  if encounter == nil:
    return ""
  var names: seq[string]
  for houseIndex in encounter.members:
    names.add(houseIndex.playerNameForHouse())
  names.sort()
  names.join(",")

proc addLine*(encounter: Encounter, speaker, message: string) =
  ## Appends one spoken line everyone in the group will see.
  if encounter == nil or message.len == 0:
    return
  encounter.lines.add(speaker & ": " & message)

proc splitTalkLine*(line: string): (string, string) =
  ## Speaker and message from one "Name: text" encounter line.
  let at = line.find(": ")
  if at <= 0:
    return ("", line)
  (line[0 ..< at], line[at + 2 .. ^1])

proc conversationText*(encounter: Encounter, selfName: string): string =
  ## The encounter log for a live report. Own lines are labeled You.
  if encounter == nil or encounter.lines.len == 0:
    return ""
  var rows: seq[string]
  for line in encounter.lines:
    let at = line.find(": ")
    if at > 0 and line[0 ..< at] == selfName:
      rows.add("You: " & line[at + 2 .. ^1])
    else:
      rows.add(line)
  rows.join("\n")

proc hasMember*(encounter: Encounter, houseIndex: int): bool =
  ## True when this gnome is already in the group.
  if encounter == nil:
    return false
  for member in encounter.members:
    if member == houseIndex:
      return true
  false

proc addMember*(encounter: Encounter, houseIndex: int) =
  ## Adds a gnome to the group if they are not already in it.
  if houseIndex < 0:
    return
  for member in encounter.members:
    if member == houseIndex:
      return
  if encounter.members.len >= HouseCount:
    return
  encounter.members.add(houseIndex)

proc removeMember*(encounter: Encounter, houseIndex: int) =
  ## Drops a gnome from the group.
  var next: seq[int]
  for member in encounter.members:
    if member != houseIndex:
      next.add(member)
  encounter.members = next

proc startEncounter*(
  book: var EncounterBook,
  a, b: int
): Encounter =
  ## A new two-gnome conversation.
  inc book.nextId
  result = Encounter(id: book.nextId, members: @[a, b])
  book.encounters[result.id] = result

proc dissolve*(book: var EncounterBook, encounter: Encounter) =
  ## Forgets one conversation.
  if encounter == nil:
    return
  book.encounters.del(encounter.id)

proc seatsHaveJoin*(oldSeats, newSeats: seq[int]): bool =
  ## True when newSeats contains a house that oldSeats did not.
  for seat in newSeats:
    var found = false
    for old in oldSeats:
      if old == seat:
        found = true
        break
    if not found:
      return true

proc placeEncounterCircle(
  encounter: Encounter,
  huddle: seq[Point],
  seats: seq[int]
) =
  ## Anchors the ring on this huddle. Called at start and when a gnome
  ## joins, not while members stand or walk.
  let circle = huddle.conversationCircle()
  encounter.anchorX = circle.x
  encounter.anchorY = circle.y
  encounter.hasAnchor = true
  encounter.anchorSeats = seats

proc encounterCircles*(
  book: EncounterBook,
  feet: Table[int, Point]
): seq[tuple[x, y, radius: int]] =
  ## One frozen sparkle ring per outdoor conversation of two or more
  ## still gnomes. Walkers should be omitted from feet: they have left.
  ## A new joiner recenters the ring once; a walker does not drag it.
  for encounter in book.encounters.values:
    var
      huddle: seq[Point]
      seats: seq[int]
    for houseIndex in encounter.members:
      if houseIndex in feet:
        huddle.add(feet[houseIndex])
        seats.add(houseIndex)
    if huddle.len < 2:
      encounter.hasAnchor = false
      encounter.anchorSeats.setLen(0)
      continue
    if not encounter.hasAnchor or
        encounter.anchorSeats.seatsHaveJoin(seats):
      encounter.placeEncounterCircle(huddle, seats)
    else:
      encounter.anchorSeats = seats
    result.add((
      encounter.anchorX,
      encounter.anchorY,
      ConversationRingRadius
    ))

proc intAfter(text, key: string): int =
  ## Digits after one key in a conversation log line, or 0.
  let at = text.find(key)
  if at < 0:
    return 0
  var i = at + key.len
  while i < text.len and text[i] in {'0'..'9'}:
    result = result * 10 + ord(text[i]) - ord('0')
    inc i

proc parseMemberSeats(text: string): seq[int] =
  ## House seats from the members= field of one conversation log line.
  let at = text.find("members=")
  if at < 0:
    return
  var rest = text[at + "members=".len .. ^1]
  let turnAt = rest.find(" turn=")
  if turnAt >= 0:
    rest = rest[0 ..< turnAt]
  for name in rest.split(','):
    let house = name.strip().houseIndexForPlayerName()
    if house >= 0:
      result.add(house)

proc parseConversationLine(line: string): ConversationEvent =
  ## One game.log conversation enter or exit, or an empty event.
  try:
    let node = parseJson(line)
    let kind = node{"kind"}.getStr()
    if kind notin ["convo-enter", "convo-exit", "convo-tick"]:
      return
    result.tick = node{"tick"}.getInt()
    result.seat = node{"seat"}.getInt()
    let text = node{"text"}.getStr()
    result.encounterId = text.intAfter(" id=")
    if kind == "convo-tick":
      if " silent=true" in text:
        result.encounterId = 0  # a silent slot mints nothing; drop it
      else:
        result.spokenTurn = true
      return
    result.enter = kind == "convo-enter"
    if result.enter:
      result.members = text.parseMemberSeats()
  except CatchableError:
    discard

proc parseConversationTimeline*(text: string): ConversationTimeline =
  ## Conversation enter and exit events from one game.log body.
  for line in text.splitLines():
    if line.len == 0:
      continue
    let event = parseConversationLine(line)
    if event.encounterId > 0:
      result.events.add(event)

proc loadConversationTimeline*(path: string): ConversationTimeline =
  ## Conversation enter and exit events from one game.log file.
  if path.len == 0 or not fileExists(path):
    return
  parseConversationTimeline(readFile(path))

proc addUniqueSeat(members: var seq[int], seat: int) =
  ## Appends a house seat if it is not already in the list.
  if seat < 0:
    return
  for member in members:
    if member == seat:
      return
  members.add(seat)

proc encounterGroupsAt*(
  timeline: ConversationTimeline,
  tick: int
): seq[ConversationGroup] =
  ## Open conversations at this tick, each with its member seats.
  var groups: Table[int, seq[int]]
  for event in timeline.events:
    if event.tick > tick:
      continue
    if event.spokenTurn:
      # A convo-tick row is a spoken turn, not an exit: the speaker
      # stays in the group.
      continue
    if event.enter:
      if event.members.len > 0:
        groups[event.encounterId] = event.members
      else:
        var members = groups.getOrDefault(event.encounterId)
        members.addUniqueSeat(event.seat)
        groups[event.encounterId] = members
    else:
      var next: seq[int]
      for member in groups.getOrDefault(event.encounterId):
        if member != event.seat:
          next.add(member)
      if next.len >= 2:
        groups[event.encounterId] = next
      else:
        groups.del(event.encounterId)
  for id, members in groups.pairs:
    if members.len >= 2:
      result.add(ConversationGroup(id: id, members: members))

proc encounterMembersAt*(
  timeline: ConversationTimeline,
  tick: int
): seq[seq[int]] =
  ## Member seats of every conversation that is open at this tick.
  for group in timeline.encounterGroupsAt(tick):
    result.add(group.members)

proc placeConversationAnchor*(
  huddle: seq[Point],
  seats: seq[int]
): ConversationAnchor =
  ## Frozen ring position for one conversation huddle.
  let circle = huddle.conversationCircle()
  ConversationAnchor(x: circle.x, y: circle.y, seats: seats)

## Heart connections: one rule on top of the conversation turns. A
## spoken turn connects the speaker with every member who spoke within
## the last full round of that conversation; the pair earns +1, held by
## both sides. A gnome's connection score is the sum of sqrt(links)
## over its partners, so real talks with many gnomes beat many words
## with one. Everything else - shouts, silent lurking, dinners - earns
## nothing by construction.

type
  HeartLedger* = object
    links*: Table[(int, int), int]
      ## Connection strength per gnome pair, low seat first.
    lastTurn: Table[(int, int), int]
      ## (encounterId, seat) -> ordinal of that seat's last spoken turn.
    turnCount: Table[int, int]
      ## encounterId -> spoken turns so far.

proc creditTurn*(
  ledger: var HeartLedger,
  encounterId, speakerSeat: int,
  members: seq[int]
) =
  ## One spoken conversation turn lands: connect the speaker with every
  ## member whose own last spoken turn is within the last round.
  let turn = ledger.turnCount.getOrDefault(encounterId) + 1
  ledger.turnCount[encounterId] = turn
  let
    window = members.len + 1
    ownLast = ledger.lastTurn.getOrDefault(
      (encounterId, speakerSeat), low(int) div 2)
  for member in members:
    if member == speakerSeat:
      continue
    let last = ledger.lastTurn.getOrDefault(
      (encounterId, member), low(int) div 2)
    # the member must have spoken since our own last turn (a real
    # exchange, not a monologue) and within the last round
    if last > ownLast and turn - last <= window:
      let key = (min(speakerSeat, member), max(speakerSeat, member))
      ledger.links[key] = ledger.links.getOrDefault(key) + 1
  ledger.lastTurn[(encounterId, speakerSeat)] = turn

proc heartPairs*(ledger: HeartLedger): seq[tuple[a, b, links: int]] =
  ## Every connected pair with its strength, in a stable order.
  for key, links in ledger.links:
    result.add((a: key[0], b: key[1], links: links))
  result.sort(proc(x, y: tuple[a, b, links: int]): int =
    cmp((x.a, x.b), (y.a, y.b)))

proc connectionScore*(ledger: HeartLedger, seat: int): float =
  ## One gnome's score: the sum of sqrt(links) over its partners.
  for key, links in ledger.links:
    if key[0] == seat or key[1] == seat:
      result += sqrt(float(links))

proc heartLinksAt*(
  timeline: ConversationTimeline,
  tick: int
): seq[tuple[a, b, links: int]] =
  ## The pair strengths at one replay tick: a pure fold of the
  ## conversation records up to that tick, so any viewer can rebuild
  ## the connections from the one replay file.
  var
    ledger: HeartLedger
    groups: Table[int, seq[int]]
  for event in timeline.events:
    if event.tick > tick:
      break
    if event.spokenTurn:
      ledger.creditTurn(event.encounterId, event.seat,
        groups.getOrDefault(event.encounterId))
    elif event.enter:
      if event.members.len > 0:
        groups[event.encounterId] = event.members
      else:
        var members = groups.getOrDefault(event.encounterId)
        members.addUniqueSeat(event.seat)
        groups[event.encounterId] = members
    else:
      var next: seq[int]
      for member in groups.getOrDefault(event.encounterId):
        if member != event.seat:
          next.add(member)
      groups[event.encounterId] = next
  ledger.heartPairs()
