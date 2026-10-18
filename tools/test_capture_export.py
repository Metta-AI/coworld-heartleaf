"""Qualify candidate export against complete native captures, including tampering."""

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
runs, output = (Path(arg).resolve() for arg in sys.argv[1:3])
output.mkdir(mode=0o700, parents=True, exist_ok=False)
exporter = [sys.executable, str(ROOT / "tools/export_candidates.py")]
subprocess.run(
    exporter + ["--runs", str(runs), "--output", str(output / "candidates")], check=True
)
records = [
    json.loads(line)
    for line in (output / "candidates/trajectories.jsonl").read_text().splitlines()
]
decisions = [row for row in records if row["event_type"] == "decision"]
episodes = [row for row in records if row["event_type"] == "episode"]
assert len(episodes) == len(list(runs.iterdir()))
assert decisions and all(episode["status"] == "completed" for episode in episodes)
assert not (output / "candidates/train.jsonl").exists()
assert not (output / "candidates/validation.jsonl").exists()
assert json.loads((output / "candidates/manifest.json").read_text())["review_required"]
assert (output / "candidates/trajectories.jsonl").stat().st_mode & 0o777 == 0o600
actual = {}
for run in sorted(runs.iterdir()):
    capture = json.loads((run / "capture.json").read_text())
    revision = capture["source_revision"]
    for path in run.glob("seat*.jsonl"):
        seat = path.stem.removeprefix("seat")
        for line in path.read_text().splitlines():
            row = json.loads(line)
            if row["role"] == "applied":
                applied = json.loads(row["text"])
                actual[revision, capture["config"]["seed"], seat, applied["tag"]] = (
                    applied["action"]
                )
families = {
    episode["episode_id"]: int(episode["seed_family"].removeprefix("heartleaf-"))
    for episode in episodes
}
for decision in decisions:
    key = (
        decision["source_revision"],
        families[decision["episode_id"]],
        decision["seat"],
        decision["decision_id"],
    )
    assert decision["executed_action"] == actual.pop(key)
assert not actual

mutated = output / "corrupted-input"
shutil.copytree(runs, mutated)
path = next(mutated.glob("*/seat0.jsonl"))
rows = [json.loads(line) for line in path.read_text().splitlines()]
request = next(row for row in rows if row["role"] == "request")
evidence = json.loads(request["text"])
evidence["prompt_template"]["system_sha256"] = "0" * 64
request["text"] = json.dumps(evidence)
path.write_text("".join(json.dumps(row) + "\n" for row in rows))
failed = subprocess.run(
    exporter + ["--runs", str(mutated), "--output", str(output / "rejected")],
    capture_output=True,
    text=True,
)
assert failed.returncode != 0 and "AssertionError" in failed.stderr
print(
    len(episodes),
    "complete captures;",
    len(decisions),
    "applied decisions and deliberate hash-corruption rejection PASS",
)
