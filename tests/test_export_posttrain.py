import json
import stat
import tempfile
import unittest
from pathlib import Path

from tools.export_posttrain import export, split


class ExactRequestExportTest(unittest.TestCase):
    def test_uses_sent_messages_after_history_shrink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runs = root / "runs"
            runs.mkdir()
            seeds = [
                next(seed for seed in range(100) if split(f"heartleaf-{seed}") == partition)
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
                (run / "completed.json").write_text(json.dumps({"seed": seed, "scores": [1]}))
                transcript = [
                    {"role": "system", "index": -1, "text": "Soul"},
                    {"role": "user", "index": 0, "text": "Old history omitted from request"},
                    {"role": "user", "index": -1, "text": "Current report"},
                    {"role": "request", "index": -1, "text": json.dumps({"tag": "0:1", "messages": prompt})},
                    {"role": "assistant", "index": 1, "text": '{"action":"wait"}'},
                ]
                for sequence, row in enumerate(transcript):
                    row.update({"game": 1, "seat": 0, "sequence": sequence, "tick": 7})
                (run / "seat0.jsonl").write_text("".join(json.dumps(row) + "\n" for row in transcript))

            output = root / "dataset"
            manifest = export(runs, output, "source-revision")
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
            self.assertEqual((manifest["train_examples"], manifest["validation_examples"]), (1, 1))
            for partition in ("train", "validation"):
                example = json.loads((output / f"{partition}.jsonl").read_text())
                self.assertEqual(example["prompt"], prompt)

            transcript_path = runs / f"heartleaf-{seeds[0]}" / "seat0.jsonl"
            transcript = [json.loads(line) for line in transcript_path.read_text().splitlines()]
            transcript[3]["text"] = json.dumps({"tag": "0:9", "messages": prompt})
            transcript_path.write_text("".join(json.dumps(row) + "\n" for row in transcript))
            with self.assertRaisesRegex(ValueError, "reply differs from request"):
                export(runs, root / "tampered", "source-revision")


if __name__ == "__main__":
    unittest.main()
