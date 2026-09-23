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

python3 tools/export_posttrain.py \
  --runs /tmp/heartleaf-training-runs \
  --output /tmp/heartleaf-training-dataset \
  --source-revision "$(git rev-parse HEAD)"
```

The collector writes each seat's player-visible transcript beside the game
results when `HEARTLEAF_TRAINING_DIR` is set. It writes `completed.json` only
after the server and soul uploaders exit successfully. The exporter checks
that completion proof, event sequence, seat count, transcript sequence, and
reply ticks agree. It retains decisions that the game accepted and splits
whole games by seed into `train.jsonl` and `validation.jsonl`. The manifest
records source revision, scores, and input hashes. The files contain soul
prompts, observations, and model replies; keep them out of the repository.

The exported rows use the Metta post-training `Example` schema. From a Metta
checkout with `metta-posttrain` installed, run:

```sh
uv run --package metta-posttrain --extra train python -m metta_posttrain.train \
  --dataset /tmp/heartleaf-training-dataset \
  --output /tmp/heartleaf-posttrain-run \
  --model MODEL_OR_PATH --max-steps 1000 --max-length 8192
```

Choose `--max-length` for the selected model and inspect the training
manifest's `train_overlength` and `validation_overlength` counts. A full
Heartleaf game carries its conversation history forward, so examples become
longer as the game progresses. This trains a decision model from complete
games; deploying that model through Heartleaf's hosted Bedrock provider is a
separate model registration step.
