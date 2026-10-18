# Offline training bridge

`training_bridge` runs the real simulation, villager scheduler, parser, executor, and dinner evaluator without provider
requests. It intercepts requests through `newScriptedBedrockClient`, returns their exact player-visible messages, and
feeds responses back through the existing engine. It does not reconstruct observations from spectator state.

From a workspace with the repository's locked Nim dependencies installed:

```sh
nim c -d:release tools/training_bridge.nim
python3 -m unittest discover -s tests -p test_training_bridge.py -v
```

The tests cover complete games, deterministic reset, malformed responses, illegal conversation actions, stale IDs, and a
seven-day nine-seat game. The scripted gathering/hosting policy earns nonzero dinner scores. These are protocol tests,
not evidence of model quality or historical-campaign parity.

## JSONL protocol

Run `out/training_bridge` from the repository root. Its optional positional argument sets the episode length, from one
through seven days; default is seven. The simulation uses the standard day length and includes score screens. Standard
output contains one JSON value per input line. Diagnostics go to standard error. The Unix file-descriptor redirect
supports Linux and macOS.

```json
{ "kind": "reset", "seed": "91002", "players": 9 }
```

Reset creates a fresh game with one through nine seats. Seeds are decimal integer strings. The result is a `decision`
with `decision_id`, `game`, `seat`, `engine_seat`, `turn`, `semantic_view`, `inbox`,
`messages`, `speech_messages`, `typed_question`, and `action_schema`. The
semantic view repeats only the player-visible live report. Heartleaf's open
text actions use the model's native tokenizer, so `typed_question` is null.
Submit the model's unmodified response string:

```json
{ "kind": "step", "decision_id": 0, "response": "{\"action\":\"gather_plants\"}" }
```

Step returns one of three outcomes:

| Kind                 | Meaning                                                    | Fields                                                |
| -------------------- | ---------------------------------------------------------- | ----------------------------------------------------- |
| `accepted`           | Engine parser and mode gate accept the decision.           | Normalized `action`, next `observation`.              |
| `consumed_rejection` | Unusable model output consumes the turn as an engine wait. | `reason`, executed wait `action`, next `observation`. |
| `rejected`           | Stale ID or no active decision; engine did not advance.    | `reason`.                                             |

A terminal observation has `kind: terminal` and seat-indexed `scores` copied from `dailyResultsJson`. It is returned
only after the configured days finish. Reset is required before further steps. Malformed commands fail the process.
There is no teacher endpoint or automatic model retry.

The Metta collector consumes `consumed_rejection` as a spent turn. It excludes
those responses from positive supervised labels and retains the executed wait
separately from model success.

## Prompt and scoring condition

The bridge uses `heartleaf-dinner-training-v1`, embedded in every system prompt. The fixed soul asks the player to
maximize dinner score. The offline prompt replaces the appended “Connections and winning” block with the actual dinner
objective. All other mechanics, history, and current state reports come from the ordinary player path. Hosted prompts
and game rules are unchanged.

This condition fixes an existing contradiction: the original mechanics say the highest connection score wins, but
`dailyResultsJson` exports `player.score`. The latter accumulates dinner eating and hosting rewards. Connection scores
remain diagnostic. Preserve original prompts when reproducing old campaigns; do not silently mix these training prompts
into historical datasets.

Record the source commit, binary digest, this prompt revision, day count, seed, and seat count with each collected
episode. The bridge uses a deterministic virtual clock and immediate scripted replies. It does not simulate provider
latency, token limits, outages, or deadline failures. Therefore its outcomes must not be presented as matched hosted
model benchmarks.

## Prompt variation

Reset accepts `promptVariant` and nonnegative `promptSeed`. Five training wordings
are available: canonical, plain, numbered, questions, and reordered. Mixed selects
one of those five using the independent prompt seed. Selection stays fixed for the
episode, including history shrink and retries. Heldout-briefing and
heldout-reference are evaluation-only; `split: "train"` rejects them.

Only the game-owned response instruction varies. Souls, mechanics, scoring
condition, house names, histories, and live reports remain unchanged. Canonical
preserves the original prompt exactly. `semantic_view.prompt_template` identifies
the bank, selected wording, seed, and hashes of the actual system and last user
messages. `inference_mode` is `text_action`.

Run `python3 tools/test_prompt_games.py out/training_bridge ORIGINAL_BRIDGE` to
compare complete seven-day games across wordings and against the original source.
These deterministic checks do not measure model quality or training stability.
