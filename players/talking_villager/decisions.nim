import std/[json, strutils]

import heartleaf/[common, protocol]

const
  UnknownHouse = -1

type
  LlmActionKind* = enum
    LlmInvalid
    LlmKeepGatheringPlants
    LlmFindPerson
    LlmFindHouse
    LlmGoHome
    LlmStandAtHouseGarden
    LlmStandNextToPerson
    LlmSayToPerson
    LlmGoToParty

  LlmDecision* = object
    valid*: bool
    action*: LlmActionKind
    targetName*: string
    houseIndex*: int
    message*: string
    commitParty*: bool
    reason*: string
    error*: string

proc cleanDecisionText*(text: string): string =
  ## Returns a printable ASCII chat string capped to Heartleaf chat size.
  for ch in text.strip():
    if result.len >= ChatMaxChars:
      break
    let value = ord(ch)
    if value >= 32 and value < 127:
      result.add(ch)

proc actionName*(action: LlmActionKind): string =
  ## Returns the JSON action name for one LLM action.
  case action
  of LlmInvalid:
    "invalid"
  of LlmKeepGatheringPlants:
    "keep_gathering_plants"
  of LlmFindPerson:
    "find_person"
  of LlmFindHouse:
    "find_house"
  of LlmGoHome:
    "go_home"
  of LlmStandAtHouseGarden:
    "stand_at_house_garden"
  of LlmStandNextToPerson:
    "stand_next_to_person"
  of LlmSayToPerson:
    "say_to_person"
  of LlmGoToParty:
    "go_to_party"

proc parseLlmAction*(text: string): LlmActionKind =
  ## Parses one strict JSON action name.
  case text.strip().toLowerAscii()
  of "keep_gathering_plants":
    LlmKeepGatheringPlants
  of "find_person":
    LlmFindPerson
  of "find_house":
    LlmFindHouse
  of "go_home":
    LlmGoHome
  of "stand_at_house_garden":
    LlmStandAtHouseGarden
  of "stand_next_to_person":
    LlmStandNextToPerson
  of "say_to_person":
    LlmSayToPerson
  of "go_to_party":
    LlmGoToParty
  else:
    LlmInvalid

proc jsonText(text: string): string =
  ## Extracts the first JSON object from model text.
  let
    start = text.find('{')
    stop = text.rfind('}')
  if start < 0 or stop < start:
    return ""
  text[start .. stop]

proc stringField(node: JsonNode, name: string): string =
  ## Reads one optional string field.
  if not node.hasKey(name) or node[name].kind != JString:
    return ""
  node[name].getStr().strip()

proc boolField(node: JsonNode, name: string): bool =
  ## Reads one optional boolean field.
  if not node.hasKey(name) or node[name].kind != JBool:
    return false
  node[name].getBool()

proc houseField(node: JsonNode, name: string): int =
  ## Reads one optional one-based house index as a zero-based index.
  result = UnknownHouse
  if not node.hasKey(name) or node[name].kind != JInt:
    return
  let value = node[name].getInt()
  if value >= 1 and value <= HouseCount:
    result = value - 1

proc parseLlmDecision*(text: string): LlmDecision =
  ## Parses one strict LLM decision JSON object.
  result = LlmDecision(
    valid: false,
    action: LlmInvalid,
    houseIndex: UnknownHouse
  )
  let body = text.jsonText()
  if body.len == 0:
    result.error = "Decision did not contain a JSON object."
    return
  var node: JsonNode
  try:
    node = parseJson(body)
  except JsonParsingError as e:
    result.error = "Decision JSON could not parse: " & e.msg
    return
  if node.kind != JObject:
    result.error = "Decision JSON must be an object."
    return

  let action = node.stringField("action").parseLlmAction()
  if action == LlmInvalid:
    result.error = "Decision action is missing or unknown."
    return

  result.valid = true
  result.action = action
  result.targetName = node.stringField("targetName")
  result.houseIndex = node.houseField("houseIndex")
  result.message = node.stringField("message").cleanDecisionText()
  result.commitParty = node.boolField("commitParty")
  result.reason = node.stringField("reason")
