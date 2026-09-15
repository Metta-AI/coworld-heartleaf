## Garden feedback must distinguish a search that still has unchecked empty
## stops from one that has actually completed its per-day checklist.
import std/strutils
import heartleaf
import heartleaf/[common, encounters, observation, report, souls, villager]

let
  sim = initSimServer(51)
  layout = sim.worldLayoutFor()
  navigation = sim.navigationFor()
  soul = parseSoul("#!test-model\nYou are {name}.")
  agent = newVillager(0, soul, layout.gardens.len)

doAssert sim.addPlayer("alice", 0) == 0
var view = sim.observe(0)
view.scene = Outdoors
view.currentHouse = -1
view.gardensWithFood = 3
let available = agent.stateReport(view, navigation, layout)
doAssert "Garden search: food remains in the village gardens." in available
doAssert "Gathering is complete" notin available

view.gardensWithFood = 0
let emptyButUnchecked = agent.stateReport(view, navigation, layout)
doAssert "no food remains in the village gardens" in emptyButUnchecked
doAssert "finish checking your remaining gardens, then stand still" in
  emptyButUnchecked
doAssert "Gathering is complete" notin emptyButUnchecked

for checked in agent.gardenChecked.mitems:
  checked = true
let complete = agent.stateReport(view, navigation, layout)
doAssert "you checked every garden" in complete
doAssert "gather_plants now stands still" in complete
doAssert "choose a different action if you want to move" in complete
doAssert complete.endsWith("Return JSON now.")

agent.startNewDay(2)
let nextMorning = agent.stateReport(view, navigation, layout)
doAssert "Gathering is complete" notin nextMorning,
  "a new day must reset the completed garden checklist"
doAssert "finish checking your remaining gardens" in nextMorning

# A live conversation names actual participants separately from visible
# outsiders. Without this distinction, a model can repeatedly question a
# bystander who cannot answer in its speaking rotation.
view.foot = Point(x: 100, y: 100)
view.visiblePlayers = @[
  VisiblePlayer(
    name: "Anton", houseIndex: 1, foot: Point(x: 110, y: 100)
  ),
  VisiblePlayer(
    name: "Yura", houseIndex: 2, foot: Point(x: 120, y: 100)
  ),
  VisiblePlayer(
    name: "Sasha", houseIndex: 3, foot: Point(x: 300, y: 300)
  )
]
let encounter = Encounter(id: 7, members: @[0, 1])
agent.encounterId = encounter.id
let talking = agent.stateReport(view, navigation, layout, encounter)
doAssert "Conversation members: Anton" in talking
doAssert "Nearby bystanders (not in this conversation): Yura" in talking
doAssert "talk_to with a nearby bystander's name" in talking
doAssert "People next to:" notin talking
doAssert "Sasha" notin talking, "a distant outsider is not called nearby"

agent.encounterId = 0
let notTalking = agent.stateReport(view, navigation, layout)
doAssert "Talking: no" in notTalking
doAssert "People next to: Anton, Yura" in notTalking
doAssert "Conversation members:" notin notTalking
doAssert "Nearby bystanders" notin notTalking

echo "Action feedback distinguishes garden completion, conversation members, and nearby bystanders."
