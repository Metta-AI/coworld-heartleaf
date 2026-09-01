## The Connection scoring model. Each pair of gnomes holds a scalar
## c in [0, 1] - fully connected, not at all, or somewhere between -
## fed by six observable events out of the same record stream that
## rebuilds the heart ledger: three positive (a real conversation
## exchange, eating at another gnome's table, sharing that table with
## the other guests) and three negative (sitting silent on your turn,
## hosting with nothing to serve, repeat freeloading on a host you
## never repay). A gnome's overall Connection score is the polar
## combination of its ties: radius r = how many live ties, angle
## theta = (1 - mean depth) * pi/2, score = r * cos(theta), which is
## identically r * sin(mean depth * pi/2), normalized by the 8
## possible partners for a 0-1 display.
##
## Like heartLinksAt, everything here is a PURE FOLD over the
## conversation and dinner records inside the one replay file, so any
## viewer rebuilds the same c at any tick, scrubbing included.
##
## Per the spec, c is kept symmetric and non-decaying for now: whether
## damage should cost more than repair (asymmetry) and whether a tie
## should fade without contact (decay) are open design questions that
## belong inside c, and this fold takes the simplest answer to both.

import std/[algorithm, math, tables], heartleaf/[common, encounters]

const
  ## Event magnitudes. The spec inventories the signals but assigns no
  ## weights - that is open design work - so these are simple, named,
  ## tunable constants. Positive events raise a pair's c, negative
  ## events lower it, and c is clamped to [0, 1] after every event.
  ConversationExchangeGain* = 0.01
    ## One real spoken exchange in a conversation (the same unit that
    ## mints a heart link: you spoke right after they did). Calibrated
    ## against the luna replay: its densest pair trades ~85 exchanges
    ## in a day, which lands at 0.85 - deep but not saturated.
  DinnerAttendanceGain* = 0.15
    ## You ate at their table: the converted invitation, the strongest
    ## single act in the game, priced accordingly.
  SharedTableGain* = 0.05
    ## You shared a served table with another guest that night.
  SilentTurnPenalty* = 0.01
    ## Your slot came in a live conversation and you said nothing:
    ## being reached for and not answering.
  ServingNothingPenalty* = 0.10
    ## Guests came and your pantry put nothing on the table. The
    ## attendance gain is withheld too: an empty table converts nothing.
  FreeloadingPenalty* = 0.05
    ## A repeat visit to a table whose host has never eaten at yours:
    ## unreciprocated taking dampens the tie's growth (the attendance
    ## gain still lands, so the net stays positive but smaller).
  LiveTieThreshold* = 0.05
    ## A pair counts as a live tie once c reaches this floor; below it
    ## the pair contributes neither radius nor depth.
  PossiblePartners* = HouseCount - 1
    ## The 0-1 normalization: 1.0 is every possible tie at full depth.

type
  ConnectionPair* = tuple[a, b: int, c: float]
  ConnectionLedger* = object
    c: Table[(int, int), float]
      ## Connection per gnome pair, low seat first. Symmetric: every
      ## event moves the one shared scalar for both sides.
    attendances: Table[(int, int), int]
      ## (guest, host) -> times the guest ate at that host's table,
      ## the directed state behind the freeloading check.
    heart: HeartLedger
      ## The spoken-turn exchange window, shared with the heart links
      ## so both folds price exactly the same exchanges.

proc nudge(ledger: var ConnectionLedger, a, b: int, delta: float) =
  ## Moves one pair's c by delta, clamped to [0, 1].
  if a == b or a < 0 or b < 0:
    return
  let key = (min(a, b), max(a, b))
  ledger.c[key] = clamp(ledger.c.getOrDefault(key) + delta, 0.0, 1.0)

proc spokenTurn*(
  ledger: var ConnectionLedger,
  encounterId, speakerSeat: int,
  members: seq[int]
) =
  ## Positive: one real conversation exchange with each member the
  ## heart ledger connects on this turn.
  for member in ledger.heart.creditTurn(encounterId, speakerSeat, members):
    ledger.nudge(speakerSeat, member, ConversationExchangeGain)

proc silentTurn*(
  ledger: var ConnectionLedger,
  seat: int,
  members: seq[int]
) =
  ## Negative: the seat's slot came and they said nothing, a recorded
  ## non-answer toward every other member of the conversation.
  for member in members:
    if member != seat:
      ledger.nudge(seat, member, -SilentTurnPenalty)

proc dinner*(
  ledger: var ConnectionLedger,
  host: int,
  guests: seq[int],
  served: int
) =
  ## One dinner record lands. A served table pays attendance to every
  ## guest-host pair and shared-table to every guest-guest pair; an
  ## empty table converts nothing and costs the host instead. A repeat
  ## guest whose host has never eaten at their table freeloads.
  for i, guest in guests:
    if served <= 0:
      ledger.nudge(host, guest, -ServingNothingPenalty)
    else:
      ledger.nudge(host, guest, DinnerAttendanceGain)
      if ledger.attendances.getOrDefault((guest, host)) >= 1 and
          ledger.attendances.getOrDefault((host, guest)) == 0:
        ledger.nudge(host, guest, -FreeloadingPenalty)
      for j in i + 1 ..< guests.len:
        ledger.nudge(guest, guests[j], SharedTableGain)
    ledger.attendances[(guest, host)] =
      ledger.attendances.getOrDefault((guest, host)) + 1

proc connectionPairs*(ledger: ConnectionLedger): seq[ConnectionPair] =
  ## Every pair with nonzero history, in a stable order.
  for key, c in ledger.c:
    result.add((a: key[0], b: key[1], c: c))
  result.sort(proc(x, y: ConnectionPair): int =
    cmp((x.a, x.b), (y.a, y.b)))

proc applyConnectionEvent*(
  ledger: var ConnectionLedger,
  groups: var Table[int, seq[int]],
  event: ConversationEvent
) =
  ## Folds one record row into the ledger, maintaining the open
  ## conversation groups the same way heartLinksAt does.
  if event.dinner:
    ledger.dinner(event.seat, event.dinnerGuests, event.dinnerServed)
  elif event.spokenTurn:
    ledger.spokenTurn(event.encounterId, event.seat,
      groups.getOrDefault(event.encounterId))
  elif event.silentTurn:
    ledger.silentTurn(event.seat,
      groups.getOrDefault(event.encounterId))
  elif event.enter:
    if event.members.len > 0:
      groups[event.encounterId] = event.members
    else:
      var members = groups.getOrDefault(event.encounterId)
      var found = false
      for member in members:
        if member == event.seat:
          found = true
          break
      if not found and event.seat >= 0:
        members.add(event.seat)
      groups[event.encounterId] = members
  else:
    var next: seq[int]
    for member in groups.getOrDefault(event.encounterId):
      if member != event.seat:
        next.add(member)
    groups[event.encounterId] = next

proc foldConnections*(
  events: seq[ConversationEvent],
  tick = high(int)
): seq[ConnectionPair] =
  ## The pair connections after folding every record up to one tick: a
  ## pure fold, so the same records give the same c anywhere.
  var
    ledger: ConnectionLedger
    groups: Table[int, seq[int]]
  for event in events:
    if event.tick > tick:
      break
    ledger.applyConnectionEvent(groups, event)
  ledger.connectionPairs()

proc connectionsAt*(
  timeline: ConversationTimeline,
  tick: int
): seq[ConnectionPair] =
  ## The pair connections at one replay tick, rebuilt purely from the
  ## records inside the replay file, exactly like heartLinksAt.
  foldConnections(timeline.events, tick)

proc polarConnectionScore*(depths: seq[float]): float =
  ## The decided aggregation over one gnome's live-tie depths:
  ## r = count of ties, qbar = mean depth, theta = (1 - qbar) * pi/2,
  ## score = r * cos(theta) = r * sin(qbar * pi/2), then divided by
  ## the 8 possible partners so 1.0 is every tie at full depth.
  if depths.len == 0:
    return 0.0
  var total = 0.0
  for depth in depths:
    total += depth
  let qbar = total / depths.len.float
  depths.len.float * sin(qbar * PI / 2.0) / PossiblePartners.float

proc connectionScore*(pairs: seq[ConnectionPair], seat: int): float =
  ## One gnome's Connection score from the pair fold: its live ties
  ## (c at or above LiveTieThreshold) through the polar combination.
  var depths: seq[float]
  for pair in pairs:
    if (pair.a == seat or pair.b == seat) and pair.c >= LiveTieThreshold:
      depths.add(pair.c)
  polarConnectionScore(depths)

proc pairConnection*(pairs: seq[ConnectionPair], a, b: int): float =
  ## One pair's c out of the fold, or 0 for strangers.
  let key = (min(a, b), max(a, b))
  for pair in pairs:
    if pair.a == key[0] and pair.b == key[1]:
      return pair.c
  0.0
