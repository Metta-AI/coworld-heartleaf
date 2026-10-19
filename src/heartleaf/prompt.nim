## The fixed part of every villager's prompt. The soul a player sends is
## only personality and strategy; the simulation appends these mechanics
## so every gnome understands the state report and answers in the JSON
## the executor can carry out.

import std/strutils, heartleaf/[protocol, souls, prompts]

const
  ## The rules of the game as the model must understand them: response
  ## format, memory, talking, actions, greeting, and the vegetable hunt.
  ## Identical for every villager.
  MechanicsBlock* = """Response format:
Return only one JSON object and no prose. Allowed actions are
gather_plants, talk_to, say, bye, follow, go_home, go_to_house,
go_to_garden, wait, and wander. Fields are action, targetName,
message, and reason. targetName is a gnome name (Ivan, Anton, Yura,
Sasha, Maxim, Nikita, Vova, Dima, Egor). The message field is the line
said out loud; the reason field is your notes to yourself.

Conversation memory:
The conversation is the history of this game, all days so far,
ending with the current state report. User turns are things you heard
and noticed: each spoken chat line as its own turn, formatted Name:
text or You: for a line you said; the Clock once every hour; notes
in parentheses like (Day 2 begins.), (You see Anton for the first
time today.), (You now carry: Carrot x2, Beet.), (Your action was
ignored: ...), (Dinner: you ate at Anton's house with Yura. You ate
Carrot, Beet (+7 score). Still looking for: Pear.), and (Day 2
ends.). Earlier state reports are
not kept; only the last one is current. Your own earlier turns are
the JSON replies you gave. Use all of it. Even with a long history,
always respond with only one JSON object.

Talking:
Talking is modal. Chat lines arrive as user turns, one spoken line
each. The live report has Talking: yes or Talking: no. If Talking:
yes, only talk_to, say, and bye do anything. If Talking: no, say and
bye do nothing; walk with wait, wander, gather_plants, follow,
go_home, go_to_house, or go_to_garden, or start a chat with talk_to
when you are next to someone. An illegal action is ignored: you wait,
a parenthetical note tells you why, and the village moves on. bye
with a spoken message is the only way to leave a conversation. say
adds a line everyone in the group hears. talk_to with a targetName
and message pulls that gnome in if they are next to you. If Last JSON was ignored
is in the report, that action did nothing this turn. A conversation can grow
to every gnome in the village.

Actions:
gather_plants walks garden to garden and picks food until every
garden has been checked, then stands still. follow walks with a
named gnome; if they go into a house you go in too. go_home walks
you INSIDE your own house and you stay. go_to_house walks you INSIDE
that gnome's house and you stay. go_to_garden waits OUTSIDE at that
gnome's door; just before 6:00pm you go inside so you are in for
dinner. wait stands still. wander walks the village house to house
so you run into people.

Dinner:
The live report has a Where line: inside a named house, outside a
named garden (at that door), or outside in the village. At 6:00pm
you must be INSIDE a house to eat. A host scores only if they are
inside their own house with at least one guest inside. Standing at
a door at 6:00pm misses dinner. When the walk would miss 6:00pm, a
Dinner bell line says leave now. After dinner stay at the party
from 6:00pm to 9:00pm. Chat about tomorrow: who will host, who
will come to whose house, and what you will cook. Invite gnomes to
your dinner tomorrow, and take invites to theirs. Do not go home
for night. At 9:00pm the portal takes you with no penalty,
wherever you are.

Repeating yourself:
A line said twice in one day is dropped and never heard, so every
message must be new: a different food, a different question, a
different reason.

Greeting:
When you meet a gnome for the first time in a day, say hello and
something of your own; after that, no more hellos to them that day.

Vegetable hunt:
Every gnome wants to eat every garden food once this game. The state
report lists Food looking for, and Food collected when you carry
something. Always use those names. Never say vegetable 0 or food 3.
Ask nearby gnomes if they have one food you still need. Talk about
the foods you gathered.

Connections and winning:
Connection points measure time truly spent together. Each spoken
turn you take in a conversation, right after another member spoke,
gives you and that member one connection point each. Nothing else
earns them: shouting outside a conversation earns zero, standing
silent in one earns zero, and dinners earn zero connection. Your
connection score is the sum of the square root of your points with
each gnome, so real talks with many different gnomes beat many
words with one. The gnome with the highest connection score wins
the game. Your current points appear in the state report."""

proc mechanics(selection: PromptSelection): string =
  const CanonicalInstruction = "Response format:\nReturn only one JSON object and no prose."
  if selection.selectedVariant == pvCanonical: return MechanicsBlock
  let talkingStart = MechanicsBlock.find("Talking:\n")
  let partyStart = MechanicsBlock.find("After dinner stay at the party")
  let restStart = MechanicsBlock.find("Repeating yourself:\n")
  let heldout = selection.selectedVariant in {pvHeldoutBriefing, pvHeldoutReference}
  let talking = if heldout:
      """Conversation mode is shown as Talking: yes or Talking: no in the live report. Each incoming chat line is a separate user turn. In a conversation, only talk_to, say, and bye have an effect. Outside one, say and bye do nothing; use wait, wander, gather_plants, follow, go_home, go_to_house, or go_to_garden, or talk_to a neighbor to begin chatting. An illegal choice becomes a wait while the village continues, with a parenthetical explanation. A report saying Last JSON was ignored means that action had no effect this turn.
Leaving requires bye accompanied by a spoken message. A say message reaches the whole group. With targetName and message, talk_to brings that gnome into the conversation if adjacent. Groups may expand to include every village gnome."""
    else:
      """Talking is a mode, indicated by Talking: yes or Talking: no. Spoken lines arrive individually as user turns. While Talking: yes, talk_to, say, and bye are the only effective actions. While Talking: no, say and bye have no effect: use wait, wander, gather_plants, follow, go_home, go_to_house, or go_to_garden, or start conversation with talk_to beside another gnome. Illegal actions are ignored and become a wait; a parenthetical note explains why while the village advances. Last JSON was ignored confirms that the reported action did nothing this turn.
To leave a conversation, send bye with a spoken message. say speaks to everyone in the group. talk_to plus targetName and message invites that adjacent gnome into the group, which can grow to contain the whole village."""
  let actions = if heldout:
      """Choose gather_plants to visit gardens and collect their food, stopping after checking them all. follow tracks a named gnome and follows them indoors too. go_home takes you inside your own house to remain there; go_to_house does the same at the named gnome's house. go_to_garden waits outdoors at that gnome's door, moving inside just before 6:00pm for dinner. wait keeps you still. wander tours houses around the village so you encounter people."""
    else:
      """gather_plants visits gardens and picks food until all gardens have been checked, then stops. follow walks with the named gnome and enters any house they enter. go_home walks INSIDE your own house and stays there. go_to_house walks INSIDE the named gnome's house and stays. go_to_garden waits OUTSIDE that gnome's door, then enters just before 6:00pm for dinner. wait stands still. wander goes house to house through the village so you meet people."""
  let dinner = if heldout:
      """Where in the live report distinguishes being inside a named house, outside a named garden at its door, or outside in the village. Eating at 6:00pm requires being INSIDE a house; a doorway does not count. Hosts score only while inside their own house with at least one guest also inside. When travel would miss 6:00pm, the Dinner bell line tells you to leave now. """
    else:
      """Read Where to distinguish inside a named house, outside a named garden at its door, or elsewhere outside. You must be INSIDE a house at 6:00pm to eat; waiting at its door misses dinner. To score as host, be inside your own house together with at least one guest. A Dinner bell warning tells you to leave now when the walk would miss 6:00pm. """
  let sections = ["Talking:\n" & talking, "Actions:\n" & actions,
    "Dinner:\n" & dinner & MechanicsBlock[partyStart ..< restStart].strip()]
  let order = case selection.selectedVariant
    of pvPlain: [0, 1, 2]
    of pvNumbered: [1, 2, 0]
    of pvQuestions: [2, 0, 1]
    of pvReordered: [1, 0, 2]
    of pvHeldoutBriefing: [0, 2, 1]
    of pvHeldoutReference: [2, 1, 0]
    else: raise newException(Defect, "expected resolved alternate wording")
  result = selection.responseInstruction() & MechanicsBlock[CanonicalInstruction.len ..< talkingStart]
  for index, section in order:
    if selection.selectedVariant == pvNumbered: result.add($(index + 1) & ". ")
    result.add(sections[section] & "\n\n")
  result.add(MechanicsBlock[restStart .. ^1])

proc housesText*(): string =
  ## The fixed houses of the village, by owner name.
  result = "Houses:"
  for i, owner in PlayerNames:
    result.add(" " & owner &
      (if i < PlayerNames.high: "," else: "."))

proc systemPrompt*(soul: Soul, name: string, selection: PromptSelection): string =
  ## The full system prompt for one gnome: the soul with the name filled
  ## in, then the mechanics every villager shares, then the house table.
  let cleanName =
    if name.strip().len > 0:
      name.strip()
    else:
      "a Heartleaf gnome"
  let body = soul.text.strip()
  result =
    if body.contains("{name}"):
      body.replace("{name}", cleanName)
    else:
      "Your name is " & cleanName & ". You are a Heartleaf gnome player.\n\n" & body
  result.add("\n\n" & selection.mechanics())
  result.add("\n\n" & housesText())
