# Heartleaf Rules

Heartleaf is a multiplayer garden dinner game for up to 9 gnomes.
Each player controls one gnome with a house, inventory, dinner history,
and cumulative score.

## Day Cycle

A game is a week of seven in-game days. Each day runs from 9:00 AM to
9:00 PM and lasts three real minutes, so four game hours pass every real
minute (15 seconds a game hour at 24 frames a second), followed by a
10-second score screen. A whole game is about 22 minutes of play, inside
the hosted 30-minute deadline (the game refuses a configuration that is
not). Dinner is served at 6:00 PM and the dinner result stays on screen
for 10 seconds.

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

The host score is counted first from the pantry as it was when dinner
started:

```text
host score = (food items in the host inventory) x (number of visitors)
```

Everyone at that party then eats from the host inventory only, including
the host. Guests never spend their own stash. Diners are shuffled into
one random order and that order is reused for 3 rounds. Each gnome takes
1 bite per round.

On each bite:

- If the host still has a type that gnome has not eaten this game, they
  take it and score +3.
- Else if any food remains, they take a random leftover and score +1.
- If the host pantry is empty, they skip and score 0.

One dinner is at most 9 eating points (`3 x 3`). After dinner, the
host's served food is removed. Visitors keep their own inventory.

## Scoring

Hosts gain the food-times-visitors score above, plus whatever they ate.
Guests gain only their eating score.

## Souls And Brains

Every gnome is played by the game from its player's soul file. One soul per
seat; the first line names the model, the rest is the gnome's character.
The game builds the gnome's view of the village, asks the model, and
carries out the reply. With tokens configured the village waits for every
seat's soul (up to `soulTimeoutSeconds`) before day 1 begins; a seat that
never sends one is reported as a player failure and gets no gnome. A
player that disconnects after its soul was accepted keeps playing.

Model calls for different gnomes overlap. The clock stops only while every
gnome is waiting on the model with nothing left to do, and a failed call is
retried; no gnome is ever penalised for a slow or failed model.

## End Of Day

At 9:00 PM, every gnome returns to their own house. Each gnome sees
their cumulative score, then the next day begins from the morning setup.
