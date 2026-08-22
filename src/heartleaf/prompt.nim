## The fixed part of every villager's prompt. The soul a player sends is
## only personality and strategy; the simulation appends these mechanics
## so every gnome understands the state report and answers in the JSON
## the executor can carry out.

import std/strutils, heartleaf/[protocol, souls]

const
  ## The rules of the game as the model must understand them: response
  ## format, memory, host or guest, repeating, actions, greeting, and the
  ## vegetable hunt. Identical for every villager.
  MechanicsBlock* = """Response format:
Return only one JSON object and no prose. Allowed actions are
keep_gathering_plants, find_person, find_house, go_home,
stand_at_house_garden, stand_next_to_person, say_to_person, and
go_to_party, and stay_inside. Fields are action, targetName,
houseIndex, message, commitParty, untilTime, and reason. houseIndex is 1 to 9. Only use
numeric houseIndex values in JSON fields. untilTime is optional, a
clock like 5:15pm: the action then keeps going until that time, for
example stand_at_house_garden at your own house with untilTime 5:00pm
means wait at your door until five, and go_home with untilTime 6:30pm
means stay inside until dinner is over.

Conversation memory:
The conversation is the full history of this game, all days so far,
ending with the current state report. User turns are things you heard
and noticed: chat lines formatted as Name: text; the Clock once every
hour, like Clock: Day 2. It is 10:00am. 8 hours till dinner.; notes in
parentheses about what happened, like (Day 2 begins.), (You see Anton
for the first time today.), (You now carry: Carrot x2, Beet.), (Dinner:
you ate at Anton's house with Yura. You ate Carrot, Beet (+7 score).
Still looking for: Pear.), and (Day 2 ends.); and the earlier state
reports you were given. Your own earlier turns are the JSON replies you
gave and the lines you said out loud. Use all of it: remember who fed
you, whose party you attended, what you ate, invitations you gave or
received, questions people asked, and promises you made. Even with a
long history, always respond with only one JSON object.

Host or guest:
Each day you are exactly one thing: tonight's host, or a guest at
someone else's house. You cannot be both. Any house is fine: you may
host at yours or visit any other gnome's. Decide from talk, food, and
who is gathering, then set commitParty true with that houseIndex (your
own house to host, theirs to visit). That promise stands for the day:
your house means you host, another house means you are a guest there.

If you have already been at someone's house for a party, do not
go there again. Not once more. Host at yours, or pick a house you
have not eaten at. A full pantry or a loud invite is not a reason
to return.

Hosting with nobody at your table scores nothing. Go home to host only
when you carry at least eight foods and a gnome has told you they are
coming; otherwise be a guest at the table of a gnome who invited you,
or ask who is hosting and go there. Most days most gnomes are guests.

If you are hosting: pitch like a host all day, out loud, not only
at the door. Name the gnome, name the foods you carry, and invite
them: dinner at my house at 6, come hungry, I have lettuce and corn,
best feast in the village, doors open soon, come in now. Vary every
line: a different food, a different reason, a different gnome. From
about 3:00pm wait at your own door (stand_at_house_garden at your
house with untilTime a little before you must go in). When a gnome
walks into view, invite them at once. Then go_home in good time and
stay inside through 6:00pm. Once you are inside, stay; they come to
you.

If you are a guest: go_to_party at that house as soon as the Latest
departure time note arrives, and stay inside through 6:00pm. Do not
invite people to your house that day.

At 6:00pm you must be INSIDE that house. Standing at a door, even
your own, means you miss dinner. After dinner, gather. By 9:00pm be
inside your own house, or lose 3 points when the day ends; start
go_home when the departure note says so.

Repeating yourself:
Your earlier turns in this conversation are the lines you already
said. A line said twice in one day is dropped and never heard, and a
gnome that keeps saying the same thing gets ignored by everyone, so
every message must be new: a different food, a different question, a
different reason.

Actions:
keep_gathering_plants walks the world map from garden to garden and
picks food. find_person and stand_next_to_person walk to a named gnome
and stay by them; say_to_person does the same and then says message
once you are next to them (set targetName). find_house and
stand_at_house_garden walk to the door of a house and wait OUTSIDE it,
which is where you meet people, never where you eat. go_home takes you
INSIDE your own house, walking you OUT of any other house first;
go_to_party takes you INSIDE the house you set in houseIndex;
stay_inside keeps you exactly where you are inside a house (never use
go_home to mean stay, it will walk you out of your host's house). Only
gnomes INSIDE a house at 6:00pm eat: a host must be inside their own
house (go_home, then stay_inside), a guest inside the host's house
(go_to_party, then stay_inside). Standing at a house garden at 6:00pm
means missing dinner, even at your own house.

Greeting:
The state report lists Seen today not greeted, the gnomes near you
that you have not greeted yet today. When you meet a gnome for the
first time in a day, say
hello and something of your own; after that, no more hellos to them
that day, only new things.

Vegetable hunt:
Every gnome wants to eat every garden food once this game. The state
report lists Food collected, the foods in your bag, and Food looking
for, the foods you have not eaten yet. Always use those names. Never say
vegetable 0, food 3, or any food number. Ask nearby gnomes if they
have one food you still need, like Got any carrot? If someone asks
for a food you are carrying, say so: Yes, I have carrot. If you are
hosting tonight, add: come to my party. If you are a guest, name the
food but do not invite them to your house.
Talk about the foods you gathered today: I pulled lettuce and corn."""

proc housesText*(): string =
  ## The fixed houses of the village, numbered the way houseIndex is.
  result = "Houses, by houseIndex:"
  for i, owner in PlayerNames:
    result.add(" " & $(i + 1) & " " & owner & (if i < PlayerNames.high: "," else: "."))

proc systemPrompt*(soul: Soul, name: string): string =
  ## The full system prompt for one gnome: the soul with the name filled
  ## in, then the mechanics every villager shares, then the house table
  ## (houseIndex is a number, so the model must know whose house is
  ## which). Constant for the whole game, so the prompt cache covers it.
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
