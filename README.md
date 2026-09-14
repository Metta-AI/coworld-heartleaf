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

The model evaluation harness (which hosted models play Heartleaf well, and at
what cost) lives separately under [`eval/`](eval/README.md). It is operator
tooling, not part of the game or its Docker image.

OpenRouter Qwen 3.5 requests explicitly disable optional thinking through
Converse's `additionalModelRequestFields`, preserving the normal 20-second
action deadline and leaving the output budget for the action itself. OpenRouter
GPT-5/GPT-6 and newer Claude families omit unsupported temperature parameters
without extending that deadline or increasing the configured output cap.

The LLM client disables curl's connection-multiplexing wait so one slow
response cannot delay other villagers before their requests are sent.
The nine-request limit and action deadline are unchanged. A pinned
[Curly module](vendor/curly/README.md) provides the per-client setting;
other HTTP consumers keep the normal dependency.

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
- The league plays a week of seven 12-hour days, three real minutes each
  (four game hours a minute, about 22 minutes a game); a game seats 2-9
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

The quickest way to watch a game is the launcher, which plays one game the
way the league does: it builds the server and the soul player, seats the
nine example souls with a week of seven days, opens the global viewer in
your browser, and writes each gnome's model log to `tmp/logs/`:

```sh
BEDROCK_KEY=... nim r tools/play.nim
```

Add `--mock` to play without a model, `--days:2` for a shorter game,
`--port:N`, `--seed:N`, `--no-browser`, or `--no-build` to reuse the
binaries in `out/`.

To run the pieces by hand:

```sh
nim r src/heartleaf.nim
```

Then open `http://localhost:8080/`. There is one view: the root,
`/director`, `/global`, `/client/global`, `/client/replay` and `/replay`
all serve the director cut, which is what the hosted platform opens.

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

Deadline-sensitive evaluations can set `HEARTLEAF_TIMEOUT_AS_WAIT=true` in the
game environment. A client timeout then spends the decision on a wait action and
records `llm timeout action=wait`, allowing the village to continue. It does not
fabricate a model response. The default is `false`, which retains retries; other
transport errors still retry in either mode. Pin the runtime manifest when
comparing results, since this setting changes how missed deadlines affect play.

For strict evaluations, set `HEARTLEAF_UNUSABLE_AS_WAIT=true`. This extends the
policy to empty, truncated, malformed, invalid-action, and failed responses:
each consumes its decision without retry. It also makes `BEDROCK_TIMEOUT_SECONDS`
the hard client deadline for every model family. A structured `llm failure` event
retains response text/body, stop reason, usage, timestamps, seat/tag, and the
platform call ID from `X-Softmax-Llm-Call-Id` when received. Request credentials
and system prompts are not copied into that diagnostic event.

When `HEARTLEAF_EVAL_ARTIFACT=true`, each results JSON also contains a versioned
`evaluation` object: accepted seats and every LLM lifecycle event, with an event
count and contiguous sequence numbers. This is the durable eval record; it does
not depend on the platform's 10,000-line stdout tail. It excludes system prompts
and general conversation history, while failure events retain response evidence.
The manifest results schema must allow `evaluation` (the checked-in template does);
eval manifests should require it. Batch configs set `eval_artifact_required: true`
to prevent missing evidence from silently falling back to stdout.

## Developing

The transport regression uses a local fake sidecar, with no model calls:

```sh
nim c tests/bedrock_transport.nim
python3 tests/test_bedrock_transport.py --probe out/bedrock_transport
```

It requires the other eight requests to finish while the first response is
held open, on both a new and a reused client.

From a clean machine, clone the repository and sync the lock into a
workspace in the parent directory:

```sh
git clone <this repository>
cd <parent of the checkout>
nimby create
nimby sync coworld-heartleaf/nimby.lock
```

Nimby 0.2 refuses to create a workspace inside a git checkout, and Nim
finds `nim.cfg` by walking up from the file it compiles, so the
workspace has to be the parent directory: the pinned packages land
beside the repository and the compiler finds them from inside it.
`nimby sync` installs the lock's pinned packages; plain `nimby install`
does not. Then the run commands above work as written. If a sync is
aborted partway, nimby can leave a stale lock behind — `rmdir
~/.nimby/nimbylock` clears it.

CI does the same thing: `treeform/setup-nim-action@v6` puts Nim and
nimby on PATH, then each job runs `nimby create` and `nimby sync` in the
parent of the checkout.

## Build A Soul

A soul is a markdown file. The first line is `#!` followed by the Bedrock
model id; the rest is the system prompt: personality, manners, strategy,
example phrases. `{name}` is replaced with the gnome's name. The game
appends the rules every gnome must know (the state report, the actions,
the JSON reply format), so a soul never has to explain those. See
[docs/soul_files.md](docs/soul_files.md) for the format and what the
model is told each turn.

The nine `players/*_villager/soul.md` files are examples. Each persona
directory also holds a Dockerfile that packages its soul with the tiny
`players/soul_player` uploader. Locally, `soul_player` finds a soul from
its `--name`: `grumpy_villager1` plays `players/grumpy_villager/soul.md`,
and `soul_player3` plays the third persona, so bitworld's quick_run can
field the whole village with one group:

```sh
cd ../bitworld && nim r tools/quick_run.nim ../coworld-heartleaf \
  --connect --port:8080 --bots:soul_player:9
```

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
- `tests/tests.nim` contains smoke checks (`nim r tests/tests.nim`);
  `tests/routes.nim` pins the viewer front door against a real replay
  server (`nim c src/heartleaf.nim`, then `nim r tests/routes.nim`).

## License

MIT

### Viewer stability review

The director preserves the original village and uses light parchment framing
with the existing pixel-art wooden/leaf border by default. The full village
fills the window height with controls overlaid; conversation shots fill the window.
Use `?background=forest` to compare the optional forest surround (art review
pending). A zoomed conversation shows its current speaker's card with portrait,
dialogue, points and connections. The card uses reusable parts, and emojis sit
above gnomes and names. Replays retain their transport, while live spectators
retain the historical live-only behavior.
See [viewer changes, validation and review limits](docs/viewer-stability.md).
