## Shared conversation encounters: one group of gnomes talking, up to
## nine, with a line log every member sees. Pure data plus join and
## leave helpers used by the brains runtime.

import std/[algorithm, strutils, tables], heartleaf/[common, protocol]

type
  Encounter* = ref object
    id*: int
    members*: seq[int]
    lines*: seq[string]
  EncounterBook* = object
    encounters*: Table[int, Encounter]
    nextId*: int

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
