## What the villager brains say to the model and what they read back:
## the conversation turns sent to Bedrock and the strict JSON decision a
## model replies with.

import std/[json, strutils]

import heartleaf/[common, protocol]

const
  UnknownHouse* = -1

type
  ConversationMessage* = object
    ## One turn sent to the model: role is system, user, or assistant.
    role*: string
    content*: string

  Action* = enum
    Invalid
    GatherPlants
    TalkTo
    Say
    Bye
    Follow
    GoHome
    GoToHouse
    GoToGarden
    Wait
    Wander

  Decision* = object
    valid*: bool
    malformed*: bool
      ## True when the reply is not a JSON object worth acting on.
    action*: Action
    targetName*: string
    houseIndex*: int
    message*: string
    reason*: string
    error*: string

proc asciiPunctuation(text: string): string =
  ## Swaps the Unicode punctuation models like to write for the ASCII the
  ## chat font can show, so "today—found" reads as "today - found"
  ## instead of "todayfound".
  text.multiReplace([
    ("\u2014", " - "), ("\u2013", " - "), ("\u2026", "..."),
    ("\u2018", "'"), ("\u2019", "'"), ("\u201c", "\""), ("\u201d", "\""),
    ("\u00a0", " ")
  ])

proc cleanDecisionText*(text: string): string =
  ## Returns a printable ASCII chat string capped to Heartleaf chat size.
  for ch in text.asciiPunctuation().strip():
    if result.len >= ChatMaxChars:
      break
    let value = ord(ch)
    if value >= 32 and value < 127:
      result.add(ch)

proc stripOneSelfPrefix(text: string, name: string): string =
  ## Removes one leading "Name:" label naming this bot, tolerating
  ## markdown or bracket decoration like "**Name:**" or "[Name]:".
  ## Returns the text unchanged when it does not start with the label.
  result = text
  if name.len == 0:
    return
  var at = 0
  while at < text.len and text[at] in {'*', '[', '(', '"', ' '}:
    inc at
  if at + name.len > text.len:
    return
  if text[at ..< at + name.len].toLowerAscii() != name.toLowerAscii():
    return
  at += name.len
  while at < text.len and text[at] in {'*', ']', ')', '"', ' '}:
    inc at
  if at >= text.len or text[at] != ':':
    return
  inc at
  while at < text.len and text[at] in {'*', '"', ' '}:
    inc at
  result = text[at .. ^1]

proc stripSelfPrefix*(text: string, selfNames: openArray[string]): string =
  ## Removes leading speaker labels the model wrote for itself, so a bot
  ## named Vova never says "Vova: hello"; the game already shows who is
  ## talking. Repeats until no self label is left.
  result = text.strip()
  while true:
    var changed = false
    for name in selfNames:
      let stripped = result.stripOneSelfPrefix(name)
      if stripped != result:
        result = stripped.strip()
        changed = true
    if not changed or result.len == 0:
      return

proc actionName*(action: Action): string =
  ## Returns the JSON action name for one LLM action.
  case action
  of Invalid:
    "invalid"
  of GatherPlants:
    "gather_plants"
  of TalkTo:
    "talk_to"
  of Say:
    "say"
  of Bye:
    "bye"
  of Follow:
    "follow"
  of GoHome:
    "go_home"
  of GoToHouse:
    "go_to_house"
  of GoToGarden:
    "go_to_garden"
  of Wait:
    "wait"
  of Wander:
    "wander"

proc parseAction*(text: string): Action =
  ## Parses one strict JSON action name.
  case text.strip().toLowerAscii()
  of "gather_plants", "keep_gathering_plants":
    GatherPlants
  of "talk_to":
    TalkTo
  of "say":
    Say
  of "bye":
    Bye
  of "follow":
    Follow
  of "go_home":
    GoHome
  of "go_to_house":
    GoToHouse
  of "go_to_garden":
    GoToGarden
  of "wait":
    Wait
  of "wander":
    Wander
  else:
    Invalid

proc jsonText(text: string): string =
  ## Extracts the first complete JSON object from model text, ignoring
  ## anything a model writes after it (some keep narrating, or invent the
  ## next turn, complete with a second object).
  let start = text.find('{')
  if start < 0:
    return ""
  var
    depth = 0
    inString = false
    escaped = false
  for i in start ..< text.len:
    let c = text[i]
    if inString:
      if escaped:
        escaped = false
      elif c == '\\':
        escaped = true
      elif c == '"':
        inString = false
      continue
    case c
    of '"':
      inString = true
    of '{':
      inc depth
    of '}':
      dec depth
      if depth == 0:
        return text[start .. i]
    else:
      discard
  # Unbalanced: fall back to the widest span and let the parser complain.
  let stop = text.rfind('}')
  if stop < start:
    return ""
  text[start .. stop]

proc stringField(node: JsonNode, name: string): string =
  ## Reads one optional string field.
  if not node.hasKey(name) or node[name].kind != JString:
    return ""
  node[name].getStr().strip()

proc houseField(node: JsonNode, name: string): int =
  ## Reads one optional one-based house index as a zero-based index.
  result = UnknownHouse
  if not node.hasKey(name):
    return
  var value = 0
  case node[name].kind
  of JInt:
    value = node[name].getInt()
  of JString:
    try:
      value = parseInt(node[name].getStr().strip())
    except ValueError:
      return
  else:
    return
  if value >= 1 and value <= HouseCount:
    result = value - 1

proc parseDecision*(
  text: string,
  selfNames: openArray[string] = []
): Decision =
  ## Parses one strict decision JSON object. selfNames are the names
  ## this gnome goes by; a message that starts with one as a speaker label
  ## has that label removed.
  result = Decision(
    valid: false,
    action: Invalid,
    houseIndex: UnknownHouse
  )
  let body = text.jsonText()
  if body.len == 0:
    result.error = "Decision did not contain a JSON object."
    result.malformed = true
    return
  var node: JsonNode
  try:
    node = parseJson(body)
  except JsonParsingError as e:
    result.error = "Decision JSON could not parse: " & e.msg
    result.malformed = true
    return
  if node.kind != JObject:
    result.error = "Decision JSON must be an object."
    result.malformed = true
    return
  let action = node.stringField("action").parseAction()
  if action == Invalid:
    result.error = "Decision action is missing or unknown."
    return
  result.valid = true
  result.action = action
  result.targetName = node.stringField("targetName")
  result.houseIndex = node.houseField("houseIndex")
  result.message = node.stringField("message")
    .stripSelfPrefix(selfNames).cleanDecisionText()
  result.reason = node.stringField("reason")
  if result.houseIndex < 0 and result.targetName.len > 0:
    result.houseIndex = result.targetName.houseIndexForPlayerName()

proc waitDecision*(): Decision =
  ## A silent stand-still when the model picked an illegal action.
  Decision(
    valid: true,
    action: Wait,
    houseIndex: UnknownHouse
  )

proc foodNamesIn*(text: string): seq[string] =
  ## Returns the food names in "Carrot x2, Beet" style text.
  for part in text.split(","):
    var name = part.strip()
    let at = name.rfind(" x")
    if at > 0 and at + 2 < name.len and name[at + 2].isDigit():
      name = name[0 ..< at]
    if name.len > 0 and name != "none":
      result.add(name)
