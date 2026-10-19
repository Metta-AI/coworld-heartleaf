# Training from Heartleaf games

Heartleaf players submit a soul file, and the game hosts the language model.
Its training interface is the model's system prompt, conversation history,
live state report, and JSON decision. The game does not expose a numeric
step/action interface for Metta RL or PufferLib.

Build the game and the soul uploader after syncing `nimby.lock` as described
in the [README](../README.md):

```sh
nim c --path:bitworld/src --out:out/heartleaf src/heartleaf.nim
nim c --path:bitworld/src --out:out/soul_player players/soul_player/soul_player.nim
```

Collect completed local games with at least two seeds. Choose souls from
`players/*_villager/soul.md`. Without `--mock-reply`, the game calls the
Bedrock model named by each soul, so the usual model credentials and costs
apply. `--mock-reply` is only for pipeline smoke tests; it repeats one action
and does not produce useful imitation targets.

```sh
python3 tools/collect_posttrain.py \
  --server out/heartleaf --player out/soul_player \
  --soul players/friendly_villager/soul.md \
  --soul players/grumpy_villager/soul.md \
  --seed 2 --seed 7 --max-days 7 \
  --output /tmp/heartleaf-training-runs

python3 -m pip install -r tools/requirements.txt
python3 tools/export_candidates.py \
  --runs /tmp/heartleaf-training-runs \
  --output /tmp/heartleaf-private-candidates
```

Commit source before collection. The collector records its revision, dirty status,
binary and soul hashes, and configuration. It uses the normal game day length.
Pass `--prompt-variant mixed --prompt-seed 3` to select one of five training
wordings independently of the world seed, cycling across requested runs. The two held-out variants are for
evaluation only. The v2 bank paraphrases conversation mode, movement actions, and dinner timing;
section order varies. Souls, response fields, memory guidance, strategic advice,
connection scoring, and canonical rules remain unchanged. Held-out wording uses
separate paraphrases. The exporter still reads stored v1 captures.

The collector writes each seat's player-visible transcript and exact model
request messages beside the game results when `HEARTLEAF_TRAINING_DIR` is set.
Request snapshots preserve the history actually sent after a context shrink;
the exporter uses these snapshots rather than rebuilding prompts from earlier
transcript rows. Collection and dataset directories are owner-only. The collector writes `completed.json` only
after the server and soul uploaders exit successfully. The exporter checks
that completion proof, event sequence, seat count, transcript sequence, actual
request hashes, and applied-action indexes agree. Private capture includes
prepared request bodies, responses, normalized executed actions, retries, and
abandonments. Mocked and scripted replies have unknown origin, never model or
teacher provenance. These records never enter conversation history or public
replay.

The exporter requires clean source and complete seven-day games. It rejects
held-out wording and emits canonical Coworld decision/episode candidates in
`trajectories.jsonl`. Its manifest requires independent review; it assigns no
training labels or train/validation split. Wording replicas share the world-seed
family. Unresolved request tags remain explicit, and hashes identify the original
capture files reviewers need. Keep those files alongside the candidates.

Use Metta's hosted trajectory review workflow to admit exact source hashes before
training. A complete game, valid JSON, or an accepted action does not establish
that a reply is a good learning target. Unknown-origin mocks cannot become model
targets. Full histories can exceed context limits; inspect admitted examples and
training overlength counts before model runs.

`tools/export_posttrain.py` remains the reader for historical transcripts written
before capture-v1. Its historical automatic split is not the current collection
or admission workflow. Do not use it for new capture-v1 data.

The offline bridge has a separately versioned dinner-scoring condition; hosted
souls retain the original connection-scoring instructions. Do not pool those
conditions in matched model comparisons. See [the bridge contract](../tools/training_bridge.md).
Deterministic checks and mocked capture runs do not establish model improvement
or prevention of training collapse. Matched learning comparisons remain unrun.

The CI wording workflow covers 32 complete seven-day games, including two and
nine players. Native capture/export checks remain available manually through
`tools/test_capture_export.py RUNS OUTPUT`; the duplicate CI collection was removed.
