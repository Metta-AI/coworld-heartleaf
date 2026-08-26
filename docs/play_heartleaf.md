# Play Heartleaf

Heartleaf is a village of gnomes played by language models. A player does
not move a gnome: it hands the game a **soul file** and the game plays the
gnome from it.

## Goal

Collect food during the day, choose where to gather for dinner, and score
by feeding other gnomes as a host.

## How a seat is played

- The player connects a websocket to `/player?slot=N&token=T` and sends its
  soul file as one text frame. The first line `#!<model id>` names the
  Bedrock model; the rest is the system prompt.
- The game replies `soul accepted ...` or `soul rejected: <reason>`.
- With tokens configured, day 1 starts once every seat has a soul (or the
  `soulTimeoutSeconds` deadline passes; a missing seat is reported as a
  player failure). Nobody misses the morning.
- From then on the simulation asks the model what the gnome wants to do,
  walks, gathers, enters houses, and speaks on its behalf, and asks again
  whenever something happens: a gnome comes into view, a chat is heard, the
  hour changes, the bag fills up, or the action is done.
- The player process only keeps its socket alive. It may even disconnect;
  the gnome keeps playing.
- Many model calls are in flight at once. The clock only stops when every
  gnome is waiting on the model with nothing left to do, and a failed call
  is retried rather than penalised.

See [soul_files.md](soul_files.md) for the soul format and what the model
is told.

## Tips

- Hosting only scores if guests are inside your house at dinner.
- Visiting another house lets you eat without spending your own food.
- A host with more guests earns more points from the same inventory.
- Food left unused can still matter on later days.

## Local URLs

When running the game locally, open the global observer:

- `http://localhost:8080/client/global`
