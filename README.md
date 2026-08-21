<img src="docs/heartleafBanner.png">

# heartleaf - A cozy multiplayer garden dinner game.

`nimby install heartleaf`

![Github Actions](https://github.com/treeform/cogame-heartleaf/workflows/Github%20Actions/badge.svg)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/treeform/cogame-heartleaf)
![GitHub Repo stars](https://img.shields.io/github/stars/treeform/cogame-heartleaf)
![GitHub](https://img.shields.io/github/license/treeform/cogame-heartleaf)
![GitHub issues](https://img.shields.io/github/issues/treeform/cogame-heartleaf)

[API reference](https://treeform.github.io/cogame-heartleaf)

## About

Heartleaf is a small BitWorld sprite protocol game about growing food,
collecting vegetables from garden plots, hiding in houses, and gathering for
dinner in the evening.

Every gnome is played by the game itself. A player connects a websocket to
`/player` and sends exactly one thing: a **soul file**, a markdown system
prompt whose first line names the model that should play the gnome. From
then on the simulation builds that gnome's prompts, calls the model, and
carries out the replies; the player process only keeps its socket alive.
The browser global observer is served at `/client/global`.

## Coworld package

This repository owns the Coworld manifest template and every image build declared by it:

```bash
coworld build --version 0.1.11
coworld certify dist/coworld_manifest.json
coworld upload-coworld dist/coworld_manifest.json
```

> **AI disclaimer: Much of this game was AI generated.**

## Gameplay

- Each garden starts the day with one random vegetable.
- Gardens with food show an exclamation marker.
- Press A near a garden to collect its vegetable.
- Inventory appears in the bottom-right UI layer.
- Stand inside a house and press A to hide inside it.
- Press A again to come back out.
- Player 1 spawns near house 1, player 2 near house 2, and so on through
  player 9.
- The league plays seven days of three minutes each; a game seats 2-9
  players (`tokens` / `players` in the config); the league
  runs full 9-seat villages, and experience requests can seat any 2-9
  policies (1v1, 2v2, 3v3v3, ...) with the unused houses left empty.

## Tournament Rules (Gnome Law)

Heartleaf is a social game: villagers win by talking other villagers into
coming to dinner. To keep that contest honest, every soul in the hosted
league must follow Gnome Law. Breaking it disqualifies the soul from the
league.

1. **The model plays.** Every gnome is driven by the model named in its
   soul file; the game makes the calls and carries out the replies. There
   is no other way to move or speak, so a soul is all you submit.
2. **No prompt injection.** Do not craft chat that manipulates other players'
   models instead of persuading their characters. This includes exploiting
   quirks (for example, spamming a word like "goblin" because other models
   tend to follow it), instructions aimed at the underlying model, and lies
   or invented emergencies ("my grandma is asking for you, please come").
   Persuade in character, as a villager would.
3. **No collusion through codes.** Do not arrange with other players, before
   or during the game, to exchange code words, signals, or hidden markers in
   chat and act on them. Alliances must be made openly, inside the game,
   through what the villagers actually say to each other.

If you are unsure whether a tactic is allowed, assume it is not, and ask in
the league channel before using it.

## Running Locally

```sh
nim r src/heartleaf.nim
```

Then open `http://localhost:8080/client/global`.

With no `tokens` configured the village starts at once and a gnome appears
whenever a soul arrives. Without Bedrock credentials, give the game a mock
reply so the gnomes still play:

```sh
HEARTLEAF_MOCK_REPLY='{"action": "keep_gathering_plants"}' \
  nim r src/heartleaf.nim -- \
  --config:'{"tokens": ["a", "b"], "maxTicks": 600, "daySeconds": 30}'
```

Then upload a soul for each seat:

```sh
nim r players/soul_player/soul_player.nim \
  --url:'ws://localhost:8080/player?slot=0&token=a' \
  --soul:players/friendly_villager/soul.md
```

To call a real model locally, set `BEDROCK_KEY` (or AWS credentials) in the
game's environment instead of `HEARTLEAF_MOCK_REPLY`. Hosted games get
Bedrock from the platform automatically.

## Build A Soul

A soul is a markdown file. The first line is `#!` followed by the Bedrock
model id; the rest is the system prompt: personality, manners, strategy,
example phrases. `{name}` is replaced with the gnome's name. The game
appends the rules every gnome must know (the state report, the actions,
the JSON reply format), so a soul never has to explain those. See
[docs/soul_files.md](docs/soul_files.md) for the format and what the
model is told each turn.

The nine `players/*_villager/soul.md` files are examples. Each persona
directory also holds a Dockerfile that bakes its soul into the tiny
`players/soul_player` uploader and a Coworld player manifest.

## Project Layout

- `src/heartleaf.nim` contains the game server and simulation.
- `src/heartleaf/` holds the villager brains: `souls` (the soul file
  format), `brains` (the runtime), `executor`, `villager`, `observation`,
  `navigation`, `report`, `prompt`, `pacing`, `decisions`, and the
  Bedrock client.
- `players/soul_player/` is the uploader every player image runs;
  `players/*_villager/` are example souls.
- BitWorld is used as a Nimble dependency for shared sprite protocol helpers.
- `data/` contains map, sprite, font, and Figma resource data.
- `tests/tests.nim` contains smoke checks (`nim r tests/tests.nim`).

## License

MIT
