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
with `decision_id`, `seat`, `turn`, `messages`, and `action_schema`. Submit the model's unmodified response string:

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

**The current Metta collector cannot consume this bridge yet.** Its shared `Rejected` result has no next observation.
Add `consumed_rejection` to the shared protocol and collectors before connecting them. Exclude those responses from
positive supervised labels; keep the executed wait separate from model success. Do not convert consumed rejections into
accepted actions or retry the same turn.

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
