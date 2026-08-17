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

Players connect over websockets at `/player`. The browser sprite client is
served at `/client/player`, and the global observer is served at
`/client/global`.

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
- A game seats 2-9 players (`tokens` / `players` in the config); the league
  runs full 9-seat villages, and experience requests can seat any 2-9
  policies (1v1, 2v2, 3v3v3, ...) with the unused houses left empty.

## Tournament Rules (Gnome Law)

Heartleaf is a social game: villagers win by talking other villagers into
coming to dinner. To keep that contest honest, every policy in the hosted
league must follow Gnome Law. Breaking it disqualifies the policy from the
league.

1. **Play with an LLM.** Your policy must decide what to say and do with a
   large language model. Scripted or hard-coded chat that only pretends to be
   an LLM is not allowed. If we detect a policy that is not using an LLM to
   play, it is disqualified.
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

Then open:

- `http://localhost:8080/client/player`
- `http://localhost:8080/client/global`

For a short smoke run:

```sh
nim r src/heartleaf.nim -- --maxTicks:120 --maxGames:1
```

## Project Layout

- `src/heartleaf.nim` contains the game server and simulation.
- BitWorld is used as a Nimble dependency for shared sprite protocol helpers.
- `data/` contains map, sprite, font, and Figma resource data.
- `clients/` contains the static sprite protocol web client.
- `tests/tests.nim` contains smoke checks.

## License

MIT
