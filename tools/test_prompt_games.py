"""Complete seven-day games through the actual scheduler and action executor."""

import hashlib
import json
import subprocess
import sys
import tempfile
from typing import TextIO, cast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = str(Path(sys.argv[1]).resolve())
ORIGINAL = str(Path(sys.argv[2]).resolve()) if len(sys.argv) == 3 else None
WORDINGS = (
    "canonical",
    "plain",
    "numbered",
    "questions",
    "reordered",
    "heldout-briefing",
    "heldout-reference",
)


def play(binary, seed, players, wording, prompt_seed):
    with (
        tempfile.TemporaryFile(mode="w+") as log,
        subprocess.Popen(
            [binary],
            cwd=ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=log,
            text=True,
        ) as engine,
    ):
        writer = cast(TextIO, engine.stdin)
        reader = cast(TextIO, engine.stdout)

        def request(command):
            writer.write(json.dumps(command) + "\n")
            writer.flush()
            line = reader.readline()
            assert line, (log.seek(0), log.read())[1]
            return json.loads(line)

        observation = request(
            {
                "kind": "reset",
                "seed": str(seed),
                "players": players,
                "promptVariant": wording,
                "promptSeed": prompt_seed,
                "split": "validation",
            }
        )
        first = observation
        counts = [0] * players
        systems = {}
        transcript = []
        while observation["kind"] == "decision":
            assert len(transcript) < players * 7 * 120
            seat = observation["seat"]
            system = observation["messages"][0]["content"]
            assert systems.setdefault(seat, system) == system
            assert "heartleaf-dinner-training-v1" in system
            assert "highest connection score wins" not in system
            assert "Play to maximize your terminal dinner score." in system
            normalized = json.loads(json.dumps(observation))
            if binary == BRIDGE:
                metadata = normalized["semantic_view"].pop("prompt_template")
                resolved = WORDINGS[prompt_seed % 5] if wording == "mixed" else wording
                assert metadata["variant"] == resolved
                assert metadata["bank"] == "heartleaf-rules-v3"
                assert (
                    metadata["selection"] == wording and metadata["seed"] == prompt_seed
                )
                for role, content in (
                    ("system", system),
                    ("user", observation["messages"][-1]["content"]),
                ):
                    assert (
                        metadata[role + "_sha256"]
                        == hashlib.sha256(content.encode()).hexdigest()
                    )
                assert normalized.pop("inference_mode") == "text_action"
            # Compare the unchanged soul; complete canonical systems are compared below.
            prefix = system.split("Response format:\n", 1)[0]
            normalized["messages"][0]["content"] = prefix
            action = (
                {"action": "gather_plants"}
                if counts[seat] < 6
                else {"action": "go_to_house", "targetName": "Ivan"}
            )
            result = request(
                {
                    "kind": "step",
                    "decision_id": observation["decision_id"],
                    "response": json.dumps(action),
                }
            )
            assert result["kind"] == "accepted"
            transcript.append((normalized, result["action"]))
            observation = result["observation"]
            counts[seat] += 1
        assert len(systems) == players and set(observation["scores"]) == {
            str(i) for i in range(players)
        }
        assert sum(observation["scores"].values()) > 0
        reset = request(
            {
                "kind": "reset",
                "seed": str(seed),
                "players": players,
                "promptVariant": wording,
                "promptSeed": prompt_seed,
                "split": "validation",
            }
        )
        assert reset == first
        writer.close()
        assert engine.wait(timeout=10) == 0
        return transcript, observation, systems


games = 0
for players in (2, 9):
    for seed in (91002, 91003):
        canonical = play(BRIDGE, seed, players, "canonical", 0)
        games += 1
        if ORIGINAL:
            original = play(ORIGINAL, seed, players, "canonical", 0)
            assert original == canonical, (
                "canonical messages or full-game behavior changed"
            )
        for wording, prompt_seed in [(wording, 0) for wording in WORDINGS[1:]] + [
            ("mixed", seed % 5)
        ]:
            result = play(BRIDGE, seed, players, wording, prompt_seed)
            assert result[:2] == canonical[:2], (players, seed, wording, prompt_seed)
            games += 1
        print(players, seed, "seven-day wording games PASS", flush=True)
print(games, "complete seven-day games PASS", flush=True)

for wording in WORDINGS[-2:]:
    for split in (None, "train", "unknown"):
        command = {
            "kind": "reset",
            "seed": "91002",
            "players": 2,
            "promptVariant": wording,
        }
        if split is not None:
            command["split"] = split
        result = subprocess.run(
            [BRIDGE],
            cwd=ROOT,
            input=json.dumps(command) + "\n",
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert result.returncode != 0 and not result.stdout
print("Held-out admission rejects omitted, training, and unknown splits", flush=True)
