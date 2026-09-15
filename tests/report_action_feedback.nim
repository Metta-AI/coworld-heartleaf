## Garden feedback must distinguish a search that still has unchecked empty
## stops from one that has actually completed its per-day checklist.
import std/strutils
import heartleaf
import heartleaf/[observation, report, souls, villager]

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

echo "Garden feedback distinguishes available food, empty unchecked stops, completion, and next-day reset."
