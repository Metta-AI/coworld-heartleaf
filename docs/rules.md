# Heartleaf Rules

Heartleaf is a multiplayer garden dinner game for up to 9 gnomes.
Each player controls one gnome with a house, inventory, dinner history,
and cumulative score.

## Day Cycle

Each round is one in-game day. The day starts at 8:00 AM and ends at
10:00 PM. A full day lasts 5 minutes of real time.

Gnomes spend the day collecting vegetables from garden plots. Gardens
with food show an exclamation marker. A gnome collects food by standing
near a garden and interacting with it.

## Houses

Each gnome has a personal house. A gnome can enter a house from the
shared map, move around inside it, and leave through the exit.

Food stays in a gnome's inventory until that gnome hosts dinner. Visiting
another house does not remove the visitor's own inventory.

## Dinner

Dinner happens at 6:00 PM. A house hosts dinner if its owner is inside
the house and at least one visiting gnome is also inside.

The visitors eat from the host's inventory. Each visitor gets the full
amount of every food item the host collected. After dinner, the host's
served food is removed. Visitors keep their own inventory.

## Scoring

Only hosts score points. A host gains:

```text
Total hosted food items x number of visitors
```

Visitors do not gain score for eating. Their benefit is that they can
eat elsewhere while keeping their own food for hosting.

## End Of Day

At 10:00 PM, every gnome returns to their own house. Each gnome sees
their cumulative score, then the next day begins from the morning setup.
