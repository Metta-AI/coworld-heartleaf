# Heartleaf Gameplay Specification

Heartleaf is a cozy multiplayer garden dinner game for up to 9 gnomes. Each
gnome lives in their own house, spends the day collecting food from the shared
map, and tries to feed other gnomes at dinner.

The game is about planning the day, choosing where to go, and deciding whether
to host dinner or visit someone else. A gnome scores by feeding guests, not by
hoarding food.

## Gnomes

Each player controls one gnome.

Each gnome has:

- A personal house.
- A personal inventory of collected food.
- A dinner history that records what they ate or fed.
- A cumulative score.

Each gnome starts the game inside their own house. From there, they can leave
the house, walk around the shared map, collect food, visit other houses, or
return home before dinner.

## Basic Play

The main day activity is gathering food.

Gardens on the map can contain food. A garden with food is marked so gnomes can
find it quickly. When a gnome stands near a garden and interacts with it, the
food in that garden moves into that gnome's inventory.

Food stays in a gnome's inventory until it is used as host food at dinner. A
gnome can carry food while visiting other houses. Visiting another dinner does
not remove the visitor's own inventory.

Houses are used for hiding, visiting, and dinner. A gnome can enter a house from
the shared map. While inside a house, the gnome is on that house's indoor map.
A gnome can leave the house again through the exit.

## Day Cycle

Each round is one in-game day.

The day starts at 8:00 AM and ends at 10:00 PM. A full day lasts 3 minutes of
real time by default. The clock advances in 5 minute in-game intervals and is shown in the
upper right of the UI.

The world starts bright in the morning. Later in the day, the map darkens
through five visible evening stages. The evening colors shift from daylight into
purple, then into dark blue as night approaches.

## Dinner Time

Dinner happens at 6:00 PM.

Each house can host its own dinner party. The gnome who owns the house is the
host for that house.

A dinner party happens only if:

- The host is inside their own house.
- At least one visiting gnome is inside that same house.

Multiple dinner parties can happen at the same time in different houses. In a
full 9 gnome game, the evening might create 3 parties with 3 hosts and 2 guests
each, or any other mix based on where the gnomes choose to gather.

The visitors in a house eat from that house's host. Food is multiplicative. Each
visitor gets the full amount of everything the host collected.

Example:

If the host has 3 apples, 1 pear, and 2 potatoes, then every visitor at that
party eats 3 apples, 1 pear, and 2 potatoes.

The host loses all hosted food after dinner. Visitors keep their own inventory,
so they can still use it if they are also hosting a separate dinner party in
their own house.

## Dinner Results

After dinner, each gnome sees a short black dinner panel.

For a visitor, the panel says:

```text
At dinner party you ate:
```

It then lists the food and counts the visitor ate. The list can span multiple
lines.

For a host, the panel says:

```text
During dinner party you fed:
```

It then lists the food and counts the host served, the followed by a sprite of
each visitor and their name, and then followed by the score gained.

The dinner party panel lasts about 10 seconds.

Each gnome keeps a dinner history of the party host and what they ate or fed.

## Scoring

Score comes from feeding other gnomes.

A host scores:

```text
Total hosted food items x number of visitors
```

If a host has 1 food item and feeds 3 visitors, the host gains 3 score. If a
host has 6 total food items and feeds 2 visitors, the host gains 12 score.

Visitors do not gain score for eating. Their benefit is that they can eat at
someone else's party while keeping their own inventory for hosting.

The end-of-day score is cumulative. It shows the total score each gnome has
earned from all dinner parties so far.

## End Of Day

At 10:00 PM, every gnome is teleported back to their own house.

A black score panel appears next to each gnome and shows that gnome's cumulative
score. The score panel lasts about 10 seconds.

After the score screen, the next day begins from the morning setup. Gnomes start
inside their own houses again, gardens are ready to gather from, and the day
cycle begins again at 8:00 AM.
