"""Check the join between private applied decisions and player transcripts."""

import json
import stat
import tempfile
import unittest
from pathlib import Path

from tools.export_posttrain import export, split


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
                        "text": "llm reply tag=0:1 outcome=usable",
                    },
                    {
                        "sequence": 1,
                        "kind": "reply",
                        "seat": 0,
                        "tick": 20,
                        "text": "llm reply tag=0:2 outcome=parse",
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
                        "role": "request",
                        "index": -1,
                        "tick": 10,
                        "text": json.dumps(
                            {
                                "tag": "0:1",
                                "messages": [
                                    {"role": "system", "content": "rules"},
                                    {"role": "user", "content": "observation one"},
                                ],
                            }
                        ),
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
                    {
                        "role": "request",
                        "index": -1,
                        "tick": 20,
                        "text": json.dumps(
                            {
                                "tag": "0:2",
                                "messages": [
                                    {"role": "system", "content": "rules"},
                                    {"role": "user", "content": "observation one"},
                                    {
                                        "role": "assistant",
                                        "content": '{"action":"keep_gathering_plants"}',
                                    },
                                    {"role": "user", "content": "observation two"},
                                ],
                            }
                        ),
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
            self.assertEqual(
                [episode["episode"]["seed_family"] for episode in episodes],
                ["heartleaf-1", "heartleaf-2"],
            )
            export(runs, root / "other-revision", "another-revision")
            revised = [
                json.loads(line)
                for line in (root / "other-revision" / "episodes.jsonl")
                .read_text()
                .splitlines()
            ]
            self.assertEqual(
                [episode["episode"]["seed_family"] for episode in revised],
                [episode["episode"]["seed_family"] for episode in episodes],
            )
            self.assertNotEqual(
                [episode["episode"]["episode_id"] for episode in revised],
                [episode["episode"]["episode_id"] for episode in episodes],
            )
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


class ExactRequestExportTest(unittest.TestCase):
    def test_uses_sent_messages_after_history_shrink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runs = root / "runs"
            runs.mkdir()
            seeds = [
                next(
                    seed
                    for seed in range(100)
                    if split(f"heartleaf-{seed}") == partition
                )
                for partition in ("train", "validation")
            ]
            prompt = [
                {"role": "system", "content": "Soul"},
                {"role": "user", "content": "Current report"},
            ]
            for seed in seeds:
                run = runs / f"heartleaf-{seed}"
                run.mkdir()
                result = {
                    "scores": [1],
                    "evaluation": {
                        "schema": "heartleaf-eval-evidence/1",
                        "event_count": 1,
                        "events": [
                            {
                                "sequence": 0,
                                "kind": "reply",
                                "seat": 0,
                                "tick": 7,
                                "text": "llm reply tag=0:1 outcome=usable took=1s",
                            }
                        ],
                        "accepted_seats": [{"slot": 0, "model": "test"}],
                    },
                }
                (run / "results.json").write_text(json.dumps(result))
                (run / "completed.json").write_text(
                    json.dumps({"seed": seed, "scores": [1]})
                )
                transcript = [
                    {"role": "system", "index": -1, "text": "Soul"},
                    {
                        "role": "user",
                        "index": 0,
                        "text": "Old history omitted from request",
                    },
                    {"role": "user", "index": -1, "text": "Current report"},
                    {
                        "role": "request",
                        "index": -1,
                        "text": json.dumps({"tag": "0:1", "messages": prompt}),
                    },
                    {"role": "assistant", "index": 1, "text": '{"action":"wait"}'},
                ]
                for sequence, row in enumerate(transcript):
                    row.update({"game": 1, "seat": 0, "sequence": sequence, "tick": 7})
                (run / "seat0.jsonl").write_text(
                    "".join(json.dumps(row) + "\n" for row in transcript)
                )
                (run / "seat0.effects.jsonl").write_text(
                    json.dumps(
                        {
                            "game": 1,
                            "seat": 0,
                            "index": 1,
                            "tick": 7,
                            "action": "wait",
                            "target_name": "",
                            "house_index": -1,
                            "message": "",
                            "reason": "",
                        }
                    )
                    + "\n"
                )

            output = root / "dataset"
            manifest = export(runs, output, "source-revision")
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
            self.assertEqual(
                (manifest["train_examples"], manifest["validation_examples"]), (1, 1)
            )
            for partition in ("train", "validation"):
                example = json.loads((output / f"{partition}.jsonl").read_text())
                self.assertEqual(example["prompt"], prompt)

            transcript_path = runs / f"heartleaf-{seeds[0]}" / "seat0.jsonl"
            transcript = [
                json.loads(line) for line in transcript_path.read_text().splitlines()
            ]
            transcript[3]["text"] = json.dumps({"tag": "0:9", "messages": prompt})
            transcript_path.write_text(
                "".join(json.dumps(row) + "\n" for row in transcript)
            )
            with self.assertRaisesRegex(ValueError, "reply differs from request"):
                export(runs, root / "tampered", "source-revision")


if __name__ == "__main__":
    unittest.main()
