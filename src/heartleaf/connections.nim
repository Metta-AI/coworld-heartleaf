## Persistent, symmetric relationships. Recorded events are the source of truth
## for live viewers and for deterministic replay at any tick.
import std/[algorithm, json, math, strutils, tables]
import heartleaf/[common, protocol]

type
  Emotion* = enum
    Happy, VeryHappy, Sad, VerySad
  Bond* = object
    a*, b*: int
    strength*: float
  Ranking* = object
    seat*: int
    reason*: string
  Interview* = object
    seat*, day*: int
    valid*: bool
    error*: string
    ranking*: seq[Ranking]
  ConnectionEvent* = object
    tick*, day*, seat*, target*: int
    kind*: string
    action*, reason*: string
    emotion*: Emotion
    seats*: seq[int]
    bonds*: seq[Bond]
    interview*: Interview
  ConnectionTimeline* = object
    events*: seq[ConnectionEvent]
  NightlyReview* = object
    tick*, day*: int
    seats*: seq[int]
    interviews*: seq[Interview]
    before*, after*: seq[Bond]
  ConnectionLedger* = object
    seats*: seq[int]
    bonds*: seq[Bond]
    appliedDay*: int

proc emotionName*(emotion: Emotion): string =
  ["happy", "very_happy", "sad", "very_sad"][ord(emotion)]

proc parseEmotion*(name: string, emotion: var Emotion): bool =
  for value in Emotion:
    if name == value.emotionName:
      emotion = value
      return true

proc initConnections*(seats: seq[int]): ConnectionLedger =
  for seat in seats:
    if seat >= 0 and seat < HouseCount and seat notin result.seats:
      result.seats.add(seat)
  result.seats.sort()
  for i, a in result.seats:
    for j in i+1 ..< result.seats.len:
      result.bonds.add(Bond(a:a, b:result.seats[j], strength:0.5))

proc strength*(bonds: seq[Bond], a, b: int): float =
  for bond in bonds:
    if (bond.a == a and bond.b == b) or (bond.a == b and bond.b == a):
      return bond.strength
  0.5

proc connectionScore*(bonds: seq[Bond], seat: int): float =
  for bond in bonds:
    if seat in [bond.a, bond.b]: result += bond.strength

proc rankContribution*(rank, count: int): float =
  ## With only one partner ordinal rank conveys no preference: neutral.
  if count <= 1: return 0
  0.5 - float(rank-1) / float(count-1)

proc parseInterview*(text: string, seat, day: int, seats: seq[int]): Interview =
  result = Interview(seat:seat, day:day)
  try:
    let first = text.find('{')
    let last = text.rfind('}')
    if first < 0 or last < first: raise newException(ValueError,"Expected JSON")
    let node = parseJson(text[first..last])
    if node{"ranking"}.isNil or node{"ranking"}.kind != JArray: raise newException(ValueError,"Expected ranking array")
    var seen: seq[int]
    for item in node["ranking"]:
      let other = item{"name"}.getStr().houseIndexForPlayerName()
      if other == seat or other notin seats or other in seen:
        raise newException(ValueError,"Rank each other seated gnome exactly once")
      let reason = item{"reason"}.getStr().strip()
      if reason.len == 0 or reason.len > 240:
        raise newException(ValueError,"Each ranking needs a short reason (1-240 characters)")
      seen.add(other)
      result.ranking.add(Ranking(seat:other,reason:reason))
    if seen.len != seats.len-1: raise newException(ValueError,"Ranking is incomplete")
    result.valid = true
  except CatchableError as e:
    result.ranking.setLen(0)
    result.error = e.msg

proc contribution(interview: Interview, other: int): float =
  if not interview.valid: return 0
  for i, ranking in interview.ranking:
    if ranking.seat == other: return rankContribution(i+1,interview.ranking.len)

proc applyDay*(ledger: var ConnectionLedger, day: int,
    interviews: Table[int, Interview]): bool =
  ## Commit all pair changes together once, independent of response order.
  if day <= ledger.appliedDay: return false
  for bond in ledger.bonds.mitems:
    let a = interviews.getOrDefault(bond.a)
    let b = interviews.getOrDefault(bond.b)
    let da = if a.day == day: a.contribution(bond.b) else: 0.0
    let db = if b.day == day: b.contribution(bond.a) else: 0.0
    bond.strength = clamp(bond.strength + (da+db)/2,0.0,1.0)
  ledger.appliedDay = day
  true

proc record*(event: ConnectionEvent): string =
  var node = %*{"kind":event.kind,"version":1,"tick":event.tick,
    "day":event.day,"seat":event.seat}
  case event.kind
  of "connection-start", "connection-update":
    node["seats"] = %event.seats
    node["bonds"] = %event.bonds
  of "connection-interview": node["interview"] = %event.interview
  of "connection-action":
    node["action"] = %event.action
    node["reason"] = %event.reason
  of "connection-emoji":
    node["target"] = %event.target
    node["emotion"] = %event.emotion.emotionName
  else: discard
  $node

proc parseConnections*(text: string): ConnectionTimeline =
  for line in text.splitLines():
    try:
      let node = parseJson(line)
      let kind = node{"kind"}.getStr()
      if not kind.startsWith("connection-") or node{"version"}.getInt() != 1: continue
      var event = ConnectionEvent(kind:kind,tick:node{"tick"}.getInt(),
        day:node{"day"}.getInt(),seat:node{"seat"}.getInt())
      if event.tick < 0 or event.seat notin 0..<HouseCount: continue
      case kind
      of "connection-start", "connection-update":
        event.seats = node["seats"].to(seq[int])
        let expected = initConnections(event.seats)
        event.bonds = node["bonds"].to(seq[Bond])
        if expected.seats != event.seats or expected.bonds.len != event.bonds.len: continue
        var valid = true
        for i,bond in event.bonds:
          if bond.a != expected.bonds[i].a or bond.b != expected.bonds[i].b or
              classify(bond.strength) in {fcNan,fcInf,fcNegInf} or
              bond.strength < 0 or bond.strength > 1: valid = false
        if not valid: continue
      of "connection-interview": event.interview = node["interview"].to(Interview)
      of "connection-action":
        event.action = node["action"].getStr()
        event.reason = node["reason"].getStr()
      of "connection-emoji":
        event.target = node["target"].getInt()
        if event.target notin 0..<HouseCount or event.target == event.seat or
            not parseEmotion(node["emotion"].getStr(),event.emotion): continue
      else: continue
      result.events.add(event)
    except CatchableError: discard
  result.events.sort(proc(a,b:ConnectionEvent):int = cmp(a.tick,b.tick))

proc bondsAt*(timeline: ConnectionTimeline, tick: int): seq[Bond] =
  for event in timeline.events:
    if event.tick > tick: break
    if event.kind in ["connection-start","connection-update"]: result = event.bonds

proc latestInterview*(timeline: ConnectionTimeline, tick, seat: int): Interview =
  for event in timeline.events:
    if event.tick > tick: break
    if event.kind == "connection-interview" and event.seat == seat: result = event.interview

proc nightlyReviews*(timeline: ConnectionTimeline): seq[NightlyReview] =
  ## One review per committed night. Gather same-tick interviews explicitly:
  ## the recorded world clock holds while replies arrive and bonds commit.
  var before: seq[Bond]
  for event in timeline.events:
    if event.kind == "connection-update":
      var night = NightlyReview(tick:event.tick, day:event.day,
        seats:event.seats, before:before, after:event.bonds)
      for seat in night.seats:
        var interview = Interview(seat:seat,day:event.day)
        for row in timeline.events:
          if row.tick > event.tick: break
          if row.kind == "connection-interview" and row.day == event.day and row.seat == seat:
            interview = row.interview
        night.interviews.add(interview)
      result.add(night)
    if event.kind in ["connection-start", "connection-update"]:
      before = event.bonds

proc interviewPrompt*(seats: seq[int], self: int): string =
  var names: seq[string]
  for seat in seats:
    if seat != self: names.add(seat.playerNameForHouse())
  "Bedtime interview. Rank every other seated gnome, most connected first: " &
    names.join(", ") & ". Base this on TODAY's actual interactions: who helped " &
    "you earn food/game points, care, promises kept or broken, and dinner " &
    "attendance/hosting. Do not invent events. Explain lack of interaction honestly. " &
    "Return only {\"ranking\":[{\"name\":\"Anton\",\"reason\":\"short evidence from today\"},...]}. " &
    "No self, omissions or duplicates. Keep each reason to one short sentence. " &
    "This is an interview, not an action request. No action/message fields."

proc latestAction*(timeline: ConnectionTimeline, tick, seat: int): ConnectionEvent =
  for event in timeline.events:
    if event.tick > tick: break
    if event.kind == "connection-action" and event.seat == seat: result = event
