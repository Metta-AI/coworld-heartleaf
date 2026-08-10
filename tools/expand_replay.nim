## Re-simulate a recorded Heartleaf replay and dump per-tick player positions
## plus player-tagged game events (harvest, house enter/exit, chat, score,
## dinner, join/leave) as JSONL — a navigation and behaviour debugging tool.
##
## Playback re-simulates the recorded inputs through the real game, so this
## binary must be built from the SAME game version that recorded the replay.
## A per-tick hash validates that; a mismatch is reported in the summary row
## (playback still completes, but derived state past the mismatch is suspect).
## See heartleaf_lab/tools/build_expand_replay.sh in the player-labs repo.
##
## Usage:
##   expand_replay [--format jsonl|text] [--snapshot-every N] <replay.(json|bitreplay)>
##
## `--snapshot-every N` subsamples the position rows (default 1 = every tick);
## events are ALWAYS emitted at their exact tick regardless of N.

import
  std/[json, os, sequtils, strutils, tables],
  ../src/heartleaf,
  ../src/heartleaf/common,
  ../src/heartleaf/protocol,
  ../src/replays

type
  OutputFormat = enum
    JsonlFormat
    TextFormat

  CliConfig = object
    replayPath: string
    format: OutputFormat
    snapshotEvery: int

const
  SchemaVersion = "heartleaf-replay/v2"
  UsageText =
    "Usage: expand_replay [--format jsonl|text] " &
    "[--snapshot-every N] <replay.(json|bitreplay)>"

proc fail(message: string) =
  ## Prints an error and exits non-zero.
  stderr.writeLine(message)
  quit(1)

proc parseArgs(): CliConfig =
  ## Parses command-line options.
  result = CliConfig(format: JsonlFormat, snapshotEvery: 1)
  var paths: seq[string]
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    let arg = args[i]
    case arg
    of "--help", "-h":
      echo UsageText
      quit(0)
    of "--format":
      inc i
      if i >= args.len: fail("--format needs a value\n" & UsageText)
      case args[i]
      of "jsonl": result.format = JsonlFormat
      of "text": result.format = TextFormat
      else: fail("unknown format: " & args[i] & "\n" & UsageText)
    of "--snapshot-every":
      inc i
      if i >= args.len: fail("--snapshot-every needs a value\n" & UsageText)
      try:
        result.snapshotEvery = parseInt(args[i])
      except ValueError:
        fail("invalid --snapshot-every: " & args[i])
      if result.snapshotEvery < 1:
        fail("--snapshot-every must be >= 1")
    else:
      if arg.startsWith("--"):
        fail("unknown option: " & arg & "\n" & UsageText)
      paths.add(arg)
    inc i
  if paths.len != 1:
    fail("expected exactly one replay path\n" & UsageText)
  result.replayPath = paths[0]

proc emit(config: CliConfig, row: JsonNode, text: string) =
  ## Writes one output row in the configured format.
  case config.format
  of JsonlFormat:
    stdout.writeLine($row)
  of TextFormat:
    if text.len > 0:
      stdout.writeLine(text)

proc playerRow(snapshot: ReplayPlayerSnapshot): JsonNode =
  ## Compact per-player position row.
  %*{
    "slot": snapshot.slot,
    "name": snapshot.playerName,
    "user": snapshot.username,
    "x": snapshot.x,
    "y": snapshot.y,
    "map": snapshot.mapIndex,
    "house": snapshot.houseIndex,
    "dir": snapshot.direction,
    "inv": snapshot.inventoryTotal,
    "score": snapshot.score,
    "msg": snapshot.message
  }

proc harvestedFoods(
  before, after: ReplayPlayerSnapshot,
  foodNames: seq[string]
): JsonNode =
  ## Per-veggie increases between two inventories, named.
  result = newJArray()
  for slot in 0 ..< after.inventory.len:
    let previous = if slot < before.inventory.len: before.inventory[slot] else: 0
    let gained = after.inventory[slot] - previous
    if gained > 0:
      let name = if slot < foodNames.len: foodNames[slot] else: "food" & $slot
      result.add(%*{"food": name, "count": gained})

proc dayMinutes(sim: SimServer): int =
  ## The in-game wall-clock minute of day, matching the HUD clock: the day
  ## runs DayStartMinutes..DayEndMinutes in 5-minute steps over dayTicks.
  const StepMinutes = 5
  let day = sim.replaySimDay()
  let stepCount = (DayEndMinutes - DayStartMinutes) div StepMinutes
  DayStartMinutes +
    min(stepCount, day.dayTick * stepCount div max(1, day.dayTicks)) * StepMinutes

proc eventRow(
  tick, day, minutes, slot: int,
  name, user, kind: string,
  extra: JsonNode
): JsonNode =
  ## One player-tagged event row.
  result = %*{
    "type": "event",
    "tick": tick,
    "day": day,
    "minutes": minutes,
    "clock": clockName(minutes),
    "kind": kind,
    "slot": slot,
    "name": name,
    "user": user
  }
  for key, value in extra:
    result[key] = value

proc main() =
  let config = parseArgs()
  if not fileExists(config.replayPath):
    fail("replay not found: " & config.replayPath)

  let data = parseReplayBytes(readFile(config.replayPath))
  let (seed, dayTicks) = replaySimConfig(data)
  let foodNames = replayFoodNames()

  let sim = initSimServer(seed, dayTicks)
  var replay = initReplayPlayer(data)
  replay.looping = false
  let maxTick = replay.replayMaxTick()

  # Meta row: everything a consumer needs to interpret the stream.
  config.emit(
    %*{
      "type": "meta",
      "schema": SchemaVersion,
      "replay": config.replayPath.extractFilename(),
      "seed": seed,
      "day_ticks": dayTicks,
      "max_tick": maxTick,
      "snapshot_every": config.snapshotEvery,
      "food_names": %foodNames
    },
    "meta seed=" & $seed & " max_tick=" & $maxTick
  )

  # Track prior state per slot to diff events. Slots are stable within a game.
  var previous = initTable[int, ReplayPlayerSnapshot]()

  proc processTick(tick: int) =
    let day = sim.replaySimDay().dayNumber
    let minutes = sim.dayMinutes()
    let players = snapshotReplayPlayers(sim)
    var nameBySlot = initTable[int, string]()
    for snapshot in players:
      nameBySlot[snapshot.slot] = snapshot.playerName
    var seen: seq[int]

    for snapshot in players:
      seen.add(snapshot.slot)
      let hadPrior = previous.hasKey(snapshot.slot)
      let before =
        if hadPrior: previous[snapshot.slot]
        else: ReplayPlayerSnapshot(slot: snapshot.slot, houseIndex: -1)

      if not hadPrior:
        config.emit(
          eventRow(tick, day, minutes, snapshot.slot, snapshot.playerName,
            snapshot.username, "join",
            %*{"home": snapshot.homeIndex}),
          "t" & $tick & " join " & snapshot.playerName)

      # Harvest: inventory grew.
      if snapshot.inventoryTotal > before.inventoryTotal:
        config.emit(
          eventRow(tick, day, minutes, snapshot.slot, snapshot.playerName,
            snapshot.username, "harvest",
            %*{
              "amount": snapshot.inventoryTotal - before.inventoryTotal,
              "total": snapshot.inventoryTotal,
              "foods": harvestedFoods(before, snapshot, foodNames)
            }),
          "t" & $tick & " harvest " & snapshot.playerName & " +" &
            $(snapshot.inventoryTotal - before.inventoryTotal))

      # House transitions.
      if snapshot.houseIndex != before.houseIndex:
        if snapshot.houseIndex >= 0:
          config.emit(
            eventRow(tick, day, minutes, snapshot.slot, snapshot.playerName,
              snapshot.username, "enter_house",
              %*{"house": snapshot.houseIndex,
                 "own": snapshot.houseIndex == snapshot.homeIndex}),
            "t" & $tick & " enter_house " & snapshot.playerName & " -> " &
              $snapshot.houseIndex)
        elif before.houseIndex >= 0:
          config.emit(
            eventRow(tick, day, minutes, snapshot.slot, snapshot.playerName,
              snapshot.username, "exit_house",
              %*{"house": before.houseIndex,
                 "own": before.houseIndex == snapshot.homeIndex}),
            "t" & $tick & " exit_house " & snapshot.playerName & " <- " &
              $before.houseIndex)

      # Chat: message changed to a new non-empty bubble. Chat has no explicit
      # radius — a player "hears" it when the speaker's bubble lands in their
      # viewport (same map), so record everyone in range at the speaking tick.
      if snapshot.message.len > 0 and snapshot.message != before.message:
        var heardBy = newJArray()
        for slot in sim.replayChatAudience(snapshot.slot):
          heardBy.add(%*{"slot": slot, "name": nameBySlot.getOrDefault(slot)})
        config.emit(
          eventRow(tick, day, minutes, snapshot.slot, snapshot.playerName,
            snapshot.username, "chat",
            %*{
              "text": snapshot.message,
              "heard_count": heardBy.len,
              "heard_by": heardBy
            }),
          "t" & $tick & " chat " & snapshot.playerName & " (heard by " &
            $heardBy.len & "): " & snapshot.message)

      # Score: hosting reward accrued.
      if snapshot.score > before.score:
        config.emit(
          eventRow(tick, day, minutes, snapshot.slot, snapshot.playerName,
            snapshot.username, "score",
            %*{"amount": snapshot.score - before.score,
               "total": snapshot.score}),
          "t" & $tick & " score " & snapshot.playerName & " +" &
            $(snapshot.score - before.score))

      # Dinner: a completed dinner was recorded this tick.
      if snapshot.dinnerCount > before.dinnerCount:
        config.emit(
          eventRow(tick, day, minutes, snapshot.slot, snapshot.playerName,
            snapshot.username, "dinner",
            %*{
              "host": snapshot.lastDinnerHost,
              "was_host": snapshot.lastDinnerWasHost,
              "guests": snapshot.lastDinnerGuests,
              "food": snapshot.lastDinnerFood,
              "score": snapshot.lastDinnerScore
            }),
          "t" & $tick & " dinner " & snapshot.playerName &
            " host=" & snapshot.lastDinnerHost)

      previous[snapshot.slot] = snapshot

    # Leaves: a slot we had is gone.
    for slot, before in previous.pairs:
      if slot notin seen:
        config.emit(
          eventRow(tick, day, minutes, slot, before.playerName, before.username,
            "leave", newJObject()),
          "t" & $tick & " leave " & before.playerName)
    for slot in toSeq(previous.keys):
      if slot notin seen:
        previous.del(slot)

    # Position row (subsampled).
    if tick == 0 or tick == maxTick or tick mod config.snapshotEvery == 0:
      var rows = newJArray()
      for snapshot in players:
        rows.add(playerRow(snapshot))
      config.emit(
        %*{"type": "tick", "tick": tick, "day": day, "minutes": minutes,
           "clock": clockName(minutes), "players": rows},
        "")

  processTick(0)
  while replay.playing and sim.tickCount < maxTick:
    replay.stepReplay(sim)
    processTick(sim.tickCount)

  config.emit(
    %*{
      "type": "summary",
      "ticks": sim.tickCount,
      "max_tick": maxTick,
      "hash_failed": replay.hashValidationFailed,
      "hash_mismatch_tick": replay.hashMismatchTick
    },
    "summary ticks=" & $sim.tickCount &
      (if replay.hashValidationFailed:
        " HASH MISMATCH at " & $replay.hashMismatchTick
      else: " hash ok"))

when isMainModule:
  main()
