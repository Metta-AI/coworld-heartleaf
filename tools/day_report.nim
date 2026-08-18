## Re-simulate a recorded Heartleaf replay and print, per day, the things
## that decide whether the villagers played the village plan: who scored
## at dinner and how, where every gnome was at 3:30pm (hosts should be at
## their own door), where every gnome was inside at 6:00pm (nobody alone at
## home, nobody outside, nobody at a guest farmer's table), and whether
## everyone was inside their own house when the day ended at 10:00pm.
##
## Like expand_replay, playback re-simulates the recorded inputs through the
## real game, so build this from the SAME game version that recorded the
## replay.
##
## Usage:
##   day_report [--host NAME] <replay.(json|bitreplay)>
##
## `--host NAME` marks one gnome (the scripted host_villager) so guests at
## its table are called out.

import
  std/[algorithm, os, strutils, tables],
  ../src/heartleaf,
  ../src/heartleaf/common,
  ../src/heartleaf/protocol,
  ../src/replays,
  bitworld/resources

const
  DoorCheckMinutes = 15 * 60 + 30
  DinnerCheckMinutes = DinnerMinutes
  NightCheckMinutes = DayEndMinutes - 5
  DoorRadius = 110
  UsageText = "Usage: day_report [--host NAME] <replay.(json|bitreplay)>"

type
  DinnerRow = object
    host: string
    wasHost: bool
    guests: int
    food: int
    score: int

  DayFacts = object
    day: int
    doorAt330: Table[string, string]      ## gnome -> where they stood
    insideAt6: Table[string, int]         ## gnome -> house index or -1
    dinner: Table[string, DinnerRow]      ## gnome -> their dinner result
    insideAt10: Table[string, int]        ## gnome -> house index or -1
    homeIndex: Table[string, int]

proc fail(message: string) =
  stderr.writeLine(message)
  quit(1)

proc dayMinutes(sim: SimServer): int =
  ## The in-game clock minute of day, as expand_replay computes it.
  const StepMinutes = 5
  let day = sim.replaySimDay()
  let stepCount = (DayEndMinutes - DayStartMinutes) div StepMinutes
  DayStartMinutes +
    min(stepCount, day.dayTick * stepCount div max(1, day.dayTicks)) * StepMinutes

proc houseRects(): seq[Rect] =
  ## House door rectangles from the map resource, indexed by house.
  result = newSeq[Rect](HouseCount)
  for rect in loadResourceRects("data" / "map.resource"):
    let name = rect.rectName()
    if name == "garden":
      continue
    let index = name.houseIndexFromName()
    if index >= 0 and index < HouseCount:
      result[index] = rect.toRect()

proc nearRect(x, y: int, rect: Rect, radius: int): bool =
  pointRectDistanceSquared(x, y, rect) <= radius * radius

proc main() =
  var
    replayPath = ""
    hostName = ""
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    case args[i]
    of "--help", "-h":
      echo UsageText
      quit(0)
    of "--host":
      inc i
      if i >= args.len: fail("--host needs a value\n" & UsageText)
      hostName = args[i]
    else:
      if args[i].startsWith("--"):
        fail("unknown option: " & args[i] & "\n" & UsageText)
      replayPath = args[i]
    inc i
  if replayPath.len == 0 or not fileExists(replayPath):
    fail("replay not found\n" & UsageText)

  let data = parseReplayBytes(readFile(replayPath))
  let (seed, dayTicks) = replaySimConfig(data)
  let sim = initSimServer(seed, dayTicks)
  var replay = initReplayPlayer(data)
  replay.looping = false
  let maxTick = replay.replayMaxTick()
  let houses = houseRects()

  var facts: seq[DayFacts]
  var lastDinnerCount = initTable[string, int]()

  proc factsFor(day: int): var DayFacts =
    while facts.len < day:
      facts.add(DayFacts(day: facts.len + 1))
    facts[day - 1]

  proc processTick() =
    let day = sim.replaySimDay().dayNumber
    let minutes = sim.dayMinutes()
    if day <= 0:
      return
    let players = snapshotReplayPlayers(sim)
    for snapshot in players:
      let name = snapshot.playerName
      if name.len == 0:
        continue
      let f = addr factsFor(day)
      f[].homeIndex[name] = snapshot.homeIndex
      if minutes == DoorCheckMinutes and not f[].doorAt330.hasKey(name):
        var where = "outside, away from any door"
        if snapshot.houseIndex >= 0:
          where =
            if snapshot.houseIndex == snapshot.homeIndex: "inside own house"
            else: "inside " & snapshot.houseIndex.playerNameForHouse() & "'s house"
        elif snapshot.homeIndex >= 0 and snapshot.homeIndex < houses.len and
            nearRect(snapshot.x, snapshot.y, houses[snapshot.homeIndex], DoorRadius):
          where = "AT OWN DOOR"
        else:
          for h in 0 ..< HouseCount:
            if nearRect(snapshot.x, snapshot.y, houses[h], DoorRadius):
              where = "at " & h.playerNameForHouse() & "'s door"
              break
        f[].doorAt330[name] = where
      if minutes == DinnerCheckMinutes and not f[].insideAt6.hasKey(name):
        f[].insideAt6[name] = snapshot.houseIndex
      if minutes >= NightCheckMinutes:
        f[].insideAt10[name] = snapshot.houseIndex
      let previousDinners = lastDinnerCount.getOrDefault(name, 0)
      if snapshot.dinnerCount > previousDinners:
        f[].dinner[name] = DinnerRow(
          host: snapshot.lastDinnerHost,
          wasHost: snapshot.lastDinnerWasHost,
          guests: snapshot.lastDinnerGuests,
          food: snapshot.lastDinnerFood,
          score: snapshot.lastDinnerScore
        )
        lastDinnerCount[name] = snapshot.dinnerCount

  processTick()
  while replay.playing and sim.tickCount < maxTick:
    replay.stepReplay(sim)
    processTick()

  for f in facts:
    echo "== Day ", f.day
    var names: seq[string]
    for name in f.homeIndex.keys:
      names.add(name)
    names.sort()
    ## Top scorers tonight.
    var scored: seq[(string, int)]
    for name, row in f.dinner:
      if row.wasHost:
        scored.add((name, row.score))
    scored.sort(proc(a, b: (string, int)): int = cmp(b[1], a[1]))
    if scored.len == 0:
      echo "  nobody hosted a dinner"
    else:
      var text = "  hosts tonight:"
      for (name, score) in scored:
        text.add(" " & name & "=" & $score & " (" &
          $f.dinner[name].guests & " guests, " & $f.dinner[name].food & " food)")
      echo text
    for name in names:
      let home = f.homeIndex[name]
      let door = f.doorAt330.getOrDefault(name, "?")
      var six = "?"
      if f.insideAt6.hasKey(name):
        let house = f.insideAt6[name]
        if house < 0:
          six = "OUTSIDE"
        elif house == home:
          six =
            if f.dinner.hasKey(name) and f.dinner[name].wasHost:
              "hosting " & $f.dinner[name].guests & " guests"
            else:
              "OWN HOUSE ALONE"
        else:
          let owner = house.playerNameForHouse()
          six = "guest at " & owner
          if owner == hostName:
            six.add(" (THE HOST_VILLAGER)")
          if not f.dinner.hasKey(name):
            six.add(" but no dinner served")
      var ten = "?"
      if f.insideAt10.hasKey(name):
        let house = f.insideAt10[name]
        ten =
          if house < 0: "OUTSIDE"
          elif house == home: "home"
          else: "inside " & house.playerNameForHouse() & "'s house"
      let tag = if name == hostName: " [host_villager]" else: ""
      echo "  ", name.alignLeft(7), tag.alignLeft(16),
        " 3:30pm: ", door.alignLeft(28),
        " 6pm: ", six.alignLeft(34),
        " 10pm: ", ten
  if replay.hashValidationFailed:
    echo "HASH MISMATCH at tick ", replay.hashMismatchTick,
      " (build day_report from the game version that recorded this replay)"

when isMainModule:
  main()
