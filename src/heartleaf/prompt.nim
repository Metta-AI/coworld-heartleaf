## The fixed part of every villager's prompt. The soul a player sends is
## only personality and strategy; the simulation appends these mechanics
## so every gnome understands the state report and answers in the JSON
## the executor can carry out.

import std/strutils, heartleaf/[protocol, souls]

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
Dinner bell line says leave now. After dinner, gather. By 9:00pm be
inside your own house, or lose 3 points.

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
the foods you gathered."""

proc housesText*(): string =
  ## The fixed houses of the village, by owner name.
  result = "Houses:"
  for i, owner in PlayerNames:
    result.add(" " & owner &
      (if i < PlayerNames.high: "," else: "."))

proc systemPrompt*(soul: Soul, name: string): string =
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
  result.add("\n\n" & MechanicsBlock)
  result.add("\n\n" & housesText())
