import
  std/os,
  heartleaf/resources,
  ../players/talking_viliger/decisions

echo "Testing assets"
doAssert fileExists("data/map.aseprite"), "map asset should exist"
doAssert fileExists("data/gnomes.aseprite"), "gnome asset should exist"
doAssert fileExists("data/food.aseprite"), "food asset should exist"
doAssert fileExists("data/tiny5.aseprite"), "font asset should exist"
doAssert fileExists("data/home_map.resource"), "home resource should exist"
doAssert fileExists("clients/client.html"), "sprite client should exist"

echo "Testing resources"
let rects = loadResourceRects("data/map.resource")
doAssert rects.len > 0, "resource rectangles should parse"
doAssert rects[0].name.len > 0, "resource rectangle should have a name"
doAssert rects[0].w > 0, "resource rectangle should have a width"
doAssert rects[0].h > 0, "resource rectangle should have a height"
let homeRects = loadResourceRects("data/home_map.resource")
doAssert homeRects.len > 0, "home resource rectangles should parse"
doAssert homeRects[0].name == "exit", "home exit should be first"

echo "Testing talking_viliger decisions"
let inviteDecision = parseLlmDecision("""
{
  "action": "say_to_person",
  "targetName": "Ivan",
  "houseIndex": 2,
  "message": "Come to my party?",
  "commitParty": true,
  "reason": "I have lots of food."
}
""")
doAssert inviteDecision.valid, "invite decision should parse"
doAssert inviteDecision.action == LlmSayToPerson, "action should match"
doAssert inviteDecision.targetName == "Ivan", "target should parse"
doAssert inviteDecision.houseIndex == 1, "house index should be zero based"
doAssert inviteDecision.message == "Come to my party?", "message should parse"
doAssert inviteDecision.commitParty, "commitment should parse"

let invalidDecision = parseLlmDecision("""{"action": "dance"}""")
doAssert not invalidDecision.valid, "unknown actions should be invalid"

let fencedDecision = parseLlmDecision("""
```json
{"action": "go_to_party", "houseIndex": 9, "commitParty": true}
```
""")
doAssert fencedDecision.valid, "fenced JSON should parse defensively"
doAssert fencedDecision.action == LlmGoToParty, "party action should parse"
doAssert fencedDecision.houseIndex == 8, "house 9 should become index 8"
