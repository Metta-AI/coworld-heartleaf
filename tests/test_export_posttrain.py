"""Check the join between private applied decisions and player transcripts."""

import json
import tempfile
import unittest
from pathlib import Path

from tools.export_posttrain import export


class ExportTest(unittest.TestCase):
    def test_complete_episodes_require_applied_actions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runs = root / "runs"
            runs.mkdir()
            for seed in (1, 2):
                run = runs / f"heartleaf-{seed}"
                run.mkdir()
                scores = [12]
                events = [
                    {
                        "sequence": 0,
                        "kind": "reply",
                        "seat": 0,
                        "tick": 10,
                        "text": "outcome=usable",
                    },
                    {
                        "sequence": 1,
                        "kind": "reply",
                        "seat": 0,
                        "tick": 20,
                        "text": "outcome=parse",
                    },
                ]
                results = {
                    "scores": scores,
                    "evaluation": {
                        "schema": "heartleaf-eval-evidence/1",
                        "event_count": len(events),
                        "events": events,
                        "accepted_seats": [{"slot": 0, "model": "test-model"}],
                    },
                }
                (run / "results.json").write_text(json.dumps(results))
                (run / "completed.json").write_text(
                    json.dumps({"seed": seed, "scores": scores})
                )
                rows = [
                    {"role": "system", "index": -1, "tick": 0, "text": "rules"},
                    {
                        "role": "user",
                        "index": -1,
                        "tick": 10,
                        "text": "observation one",
                    },
                    {
                        "role": "assistant",
                        "index": 0,
                        "tick": 10,
                        "text": '{"action":"keep_gathering_plants"}',
                    },
                    {
                        "role": "user",
                        "index": -1,
                        "tick": 20,
                        "text": "observation two",
                    },
                    {"role": "assistant", "index": 1, "tick": 20, "text": "bad JSON"},
                ]
                (run / "seat0.jsonl").write_text(
                    "".join(
                        json.dumps({**row, "game": 1, "seat": 0, "sequence": index})
                        + "\n"
                        for index, row in enumerate(rows)
                    )
                )
                effect = {
                    "game": 1,
                    "seat": 0,
                    "index": 0,
                    "tick": 10,
                    "action": "gather_plants",
                    "target_name": "",
                    "house_index": -1,
                    "message": "",
                    "reason": "",
                }
                effects = [effect]
                if seed == 2:
                    effects.append({**effect, "index": 1, "tick": 20, "action": "wait"})
                (run / "seat0.effects.jsonl").write_text(
                    "".join(json.dumps(item) + "\n" for item in effects)
                )

            output = root / "output"
            manifest = export(runs, output, "test-revision")
            self.assertEqual(
                (manifest["train_examples"], manifest["validation_examples"]), (1, 1)
            )
            episodes = [
                json.loads(line)
                for line in (output / "episodes.jsonl").read_text().splitlines()
            ]
            self.assertEqual(len(episodes), 2)
            for episode in episodes:
                accepted, second = episode["decisions"]
                self.assertEqual(accepted["executed_action"]["action"], "gather_plants")
                self.assertEqual(
                    accepted["attempts"][0]["response"],
                    '{"action":"keep_gathering_plants"}',
                )
                if (
                    episode["episode"]["episode_id"]
                    == episodes[0]["episode"]["episode_id"]
                ):
                    self.assertEqual(second["action_status"], "rejected")
                    self.assertIsNone(second["executed_action"])
                else:
                    self.assertEqual(second["action_status"], "fallback")
                    self.assertEqual(second["executed_action"]["action"], "wait")

            (runs / "heartleaf-1" / "seat0.effects.jsonl").write_text("")
            with self.assertRaisesRegex(
                ValueError, "reply and applied action disagree"
            ):
                export(runs, root / "bad-output", "test-revision")


if __name__ == "__main__":
    unittest.main()
