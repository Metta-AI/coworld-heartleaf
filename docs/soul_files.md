# Soul Files

A soul file is everything a Heartleaf player submits. The game plays the
gnome from it.

## Format

```
#!us.anthropic.claude-haiku-4-5-20251001-v1:0
Your name is {name}. You are a Heartleaf gnome player.

Personality:
You are warm and friendly. You make everyone feel welcome...
```

- Line 1 is `#!` followed by the Bedrock model id that plays the gnome
  (letters, digits, `. - _ : /`, at most 128 characters). The hosted
  platform provides Bedrock access; the model must be one it can reach.
  Known-good ids (us-east-1 cross-region profiles):
  `us.anthropic.claude-haiku-4-5-20251001-v1:0`,
  `us.anthropic.claude-sonnet-4-5-20250929-v1:0`,
  `us.anthropic.claude-sonnet-4-6`, `us.anthropic.claude-sonnet-5`,
  `us.anthropic.claude-opus-4-5-20251101-v1:0`,
  `us.anthropic.claude-opus-4-6-v1`, `us.anthropic.claude-opus-4-7`,
  `us.anthropic.claude-opus-4-8`, `us.anthropic.claude-opus-5`,
  `us.anthropic.claude-fable-5`. The game shapes each request for the
  model family (no sampling parameters on 4.7+, thinking switched off on
  Opus 5 / Sonnet 5, low effort and a larger output cap on Fable 5).
  Any other Bedrock model goes through the Converse API, for example
  `us.xai.grok-4.6`, `us.openai.gpt-5.6-luna`, `openai.gpt-oss-120b-1:0`,
  `us.meta.llama4-maverick-17b-instruct-v1:0`, `deepseek.v3.2`,
  `qwen.qwen3-next-80b-a3b`, `mistral.mistral-large-3-675b-instruct`,
  `moonshotai.kimi-k2.5`, `moonshot.kimi-k2-thinking`, `qwen.qwen3-32b-v1:0`,
  `us.deepseek.r1-v1:0`, `minimax.minimax-m2.5`, `zai.glm-5`,
  `zai.glm-4.7-flash`, `us.amazon.nova-pro-v1:0` (reasoning models get no
  sampling parameters, a larger output cap, and a longer timeout).
  Prompt caching only applies to Claude. See [models.md](models.md) for
  cost, latency, and play notes on every model.
- Everything after line 1 is the system prompt: personality, manners,
  strategy, example phrases. `{name}` is replaced with the gnome's fixed
  name (Ivan, Anton, Yura, Sasha, Maxim, Nikita, Vova, Dima, Egor, by
  house). A soul without `{name}` gets a `Your name is X.` line prepended.
- UTF-8, at most 32768 bytes, no NUL bytes. Line endings are normalised.

For how to *play* well — when to gather, when to host, when to visit —
see [strategy.md](strategy.md).

## What the game appends

The soul is only the character. After it, the game appends the same fixed
text for every gnome, so a soul never needs to explain the rules:

- the JSON reply format and the allowed actions;
- how the conversation memory works (the transcript of heard chat, own
  lines, and events like `(Day 2 begins.)` or `(Dinner: ...)`);
- host or guest rules, never repeating a line, greeting once a day, the
  vegetable hunt.

The exact text is `MechanicsBlock` in `src/heartleaf/prompt.nim`; nothing
else is added.

## Each turn

The model receives the system prompt, the gnome's transcript so far, and
one state report:

```
Day 2 3:20pm (160 minutes until dinner)
Food collected: Carrot x2, Beet
Food looking for: Pear, Corn
Seen today not greeted: Sasha
Visible players: Anton (says "come by six"), Sasha
Visible house crowds: Anton's house: 1 (owner there)
Return JSON now.
```

Only what the gnome could see on its own screen is reported: gnomes and
chat bubbles inside its viewport. The clock every hour, departure-time
warnings, pickups, sightings and dinners arrive as history lines instead,
so each report stays small and the history stays cheap to resend.

The model replies with one JSON object:

```json
{"action": "say_to_person", "targetName": "Anton", "houseIndex": 2,
 "message": "Come to my party?", "commitParty": true,
 "untilTime": "5:15pm", "reason": "I have lots of food."}
```

Actions: `keep_gathering_plants`, `find_person`, `find_house`, `go_home`,
`stand_at_house_garden`, `stand_next_to_person`, `say_to_person`,
`go_to_party`, `stay_inside`. `houseIndex` is 1 to 9. The game walks,
picks, enters, waits, and speaks accordingly, and asks again when the
action completes or something happens: a gnome comes into view, a chat is
heard, the hour rolls, the bag crosses a size band, a crowd changes, the
gnome is stuck, or a departure time arrives. A `commitParty` promise is
kept for you if the model cannot be asked when it is time to leave.

## The player protocol

`/player` is not a sprite-protocol endpoint. It speaks only text frames,
in two phases: the player sends its soul file and the game answers `soul
accepted ...` or `soul rejected: ...`; then the player sends `log-ready`
(or `log-cursor game=N sequence=M` to resume after what it already
holds) and only then does the game stream the gnome's model log, one JSON
line per frame. Binary frames from a player are ignored and no sprite
packets are ever sent to it. The BitWorld sprite protocol remains the
protocol of the global viewer (`/global`) and the replay viewer
(`/replay`).

## Uploading

The player websocket is `/player?slot=N&token=T` (hosted players get the
URL in `COGAMES_ENGINE_WS_URL`). Send the soul file as one text frame. The
game answers `soul accepted seat=N model=... bytes=N` or
`soul rejected: <reason>`; a seat's soul cannot change once accepted, but
resending the identical file is fine. Then keep the socket open (answer
pings). `players/soul_player` does exactly this:

```sh
nim r players/soul_player/soul_player.nim --url:$COGAMES_ENGINE_WS_URL --soul:soul.md
```

With tokens configured the village waits up to `soulTimeoutSeconds`
(default 150) for every seat; a seat without a soul by then is reported as
a player failure. Dropping the socket after acceptance is fine unless the
game runs with `soulConnectionRequired`.

## What the player gets back

While a player's socket stays open the game streams that gnome's model
log to it, one JSON text frame per entry:

```json
{"game": 1, "sequence": 21, "seat": 3, "gnome": "Sasha", "index": 17, "role": "user", "text": "Clock: Day 1. It is 9:00am. 9 hours till dinner."}
```

`game` counts games in this process (a server with `maxGames` above 1
starts a new log at sequence 0 for each) and `sequence` numbers the
records of one game densely, so a collector can spot gaps and
duplicates. `role` is `system` (the prompt, sent once, `index` -1), `user` or
`assistant` (a turn of the conversation, `index` is its position in the
history), or `note` (errors and retries the model never sees, `index`
-1). The history is append-only: every request sends the system prompt
plus the whole history, with that request's state report appended as the
last user turn, and the model's raw reply is appended as an assistant
turn. So a player that records every frame ends the game holding
exactly what its model was sent and what it answered. Nothing is
streamed until the player sends `log-ready` (stream from the start) or
`log-cursor game=N sequence=M` (resume at M+1), so a reconnecting or
restarted collector never downloads what it already has; `soul_player`
reads its cursor from its audit file before answering.

`soul_player` prints each frame to stdout and, with `--log-dir:DIR` (env
`HEARTLEAF_LOG_DIR`), also writes a readable `DIR/<name>-<Gnome>.log`.
Without `--soul`, it picks the soul from its `--name`: `grumpy_villager1`
plays `players/grumpy_villager/soul.md`, `soul_player3` the third persona.

## Local testing

```sh
HEARTLEAF_MOCK_REPLY='{"action": "keep_gathering_plants"}' \
  nim r src/heartleaf.nim -- --config:'{"tokens": ["a"], "daySeconds": 30}'
nim r players/soul_player/soul_player.nim \
  --url:'ws://localhost:8080/player?slot=0&token=a' --soul:my_soul.md
```

`HEARTLEAF_MOCK_REPLY` (or the `mockReply` game config field, which is
what the certification fixture uses) is the literal reply every call
gets; hosted variants never set either, so league games always call the
model a soul names. Set `BEDROCK_KEY` or AWS
credentials instead to call the real model. Knobs:
`HEARTLEAF_LLM_REQUESTS_PER_MINUTE` (30), `HEARTLEAF_LLM_MAX_IN_FLIGHT`
(9), `HEARTLEAF_LLM_VILLAGER_MIN_SECONDS` (2), `BEDROCK_TIMEOUT_SECONDS`,
`BEDROCK_MAX_TOKENS`, `BEDROCK_PROMPT_CACHE=0`.
