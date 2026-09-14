"""Real CLI preparation checks; no uploads, providers, or submitted code run."""

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from uuid import UUID

ROOT = Path(__file__).resolve().parents[2]


class ExpandedPreparationTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "tmp/heartleaf-eval").mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=ROOT / "tmp")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.digest = "a" * 64
        self.base = f"registry/base@sha256:{self.digest}"
        self.raw = b"#!old-model\r\nKeep this exact body.\r\nFinal line.  "
        (self.directory / "soul.md").write_bytes(self.raw)
        self.cohort = {
            "reviewed": True,
            "batch_id": self.directory.name,
            "captured_at": "2026-09-08T12:00:00Z",
            "league_id": "source-league",
            "division_id": "source-division",
            "ranking_metric": "score",
            "game_provenance": {
                "coworld_id": "cow_original",
                "version": "0.2.7",
                "game_image": f"registry/game@sha256:{self.digest}",
                "viewer_bundle": f"sha256:{self.digest}",
            },
            "sources": [
                {
                    "rank": rank,
                    "policy_version_id": str(UUID(int=rank)),
                    "image_id": f"img_{rank}",
                    "image_digest": f"sha256:{self.digest}",
                    "image_ref": f"registry/player@sha256:{self.digest}",
                    "soul_path": "soul.md",
                    "container_soul_path": "/soul.md",
                    "soul_sha256": hashlib.sha256(self.raw).hexdigest(),
                }
                for rank in range(1, 10)
            ],
        }
        self.models = [
            {"key": f"M{i}", "model": f"test/model-{i}:nitro",
             "model_header": f"#!test/model-{i}:nitro"}
            for i in range(1, 11)
        ]
        self.output = ROOT / "tmp/heartleaf-eval" / self.directory.name
        # Generated test artifacts are removed by their exact temporary handle.
        self.generated = tempfile.TemporaryDirectory(
            prefix=self.directory.name + "-", dir=ROOT / "tmp/heartleaf-eval"
        )
        self.addCleanup(self.generated.cleanup)
        self.cohort["batch_id"] = Path(self.generated.name).name + "-batch"
        self.output = Path(self.generated.name) / self.cohort["batch_id"]

    def prepare(self):
        cohort_path = self.directory / "cohort.json"
        model_path = self.directory / "models.json"
        cohort_path.write_text(json.dumps(self.cohort))
        model_path.write_text(json.dumps(self.models))
        # Invoke the same parser and preparation code as the operator CLI while
        # restricting all generated files to a managed temporary directory.
        script = (
            "import sys; from pathlib import Path; "
            "sys.path.insert(0, 'eval/tools'); import heartleaf_eval as driver; "
            "driver.BATCH_ROOT = Path(sys.argv[1]); "
            "raise SystemExit(driver.main(sys.argv[2:]))"
        )
        return subprocess.run(
            [sys.executable, "-c", script, self.generated.name, "prepare",
             "--cohort", str(cohort_path), "--base-image", self.base,
             "--models", str(model_path)],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )

    def test_nine_by_ten_preserves_bodies_and_covers_pairs(self):
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        batch = json.loads((self.output / "batch.json").read_text())
        self.assertEqual(batch["schema"], "heartleaf-eval/2")
        self.assertEqual(len(batch["variants"]), 90)
        self.assertEqual(len(batch["duplicate_source_bodies"]), 36)
        pairs = {}
        for game in batch["schedule"]:
            self.assertEqual(game["max_days"], 7)
            self.assertEqual(len(set(game["policy_keys"])), 9)
            keys = sorted(game["policy_keys"])
            for index, left in enumerate(keys):
                for right in keys[index + 1:]:
                    pairs[left, right] = pairs.get((left, right), 0) + 1
        self.assertEqual(len(pairs), 4005)
        self.assertGreaterEqual(min(pairs.values()), 2)
        for variant in batch["variants"]:
            raw = (self.output / variant["context"] / "soul.md").read_bytes()
            self.assertEqual(raw, variant["model_header"].encode() + self.raw[len(b"#!old-model"):])
            self.assertIsNone(variant["policy_version_id"])
        self.assertEqual(batch["stop_threshold_usd"], 10)
        again = self.prepare()
        self.assertNotEqual(again.returncode, 0)

    def test_one_soul_can_fill_nine_seats_with_different_models(self):
        self.cohort["sources"] = self.cohort["sources"][:1]
        self.models = self.models[:9]
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        batch = json.loads((self.output / "batch.json").read_text())
        self.assertEqual(len(batch["variants"]), 9)
        self.assertEqual(len(batch["schedule"]), 2)

    def test_expanded_batch_cannot_use_legacy_submission_or_report(self):
        self.assertEqual(self.prepare().returncode, 0)
        script = (
            "import json, sys; from pathlib import Path; "
            "sys.path.insert(0, 'eval/tools'); import heartleaf_eval as driver; "
            "path = Path(sys.argv[1]); "
            "driver.make_request(json.loads(path.read_text()), 'canary') "
            "if sys.argv[2] == 'submit' else driver.report(path, path)"
        )
        for command in ("submit", "report"):
            with self.subTest(command=command):
                result = subprocess.run(
                    [sys.executable, "-c", script, str(self.output / "batch.json"), command],
                    cwd=ROOT, capture_output=True, text=True, check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("expanded batches support local preparation only", result.stderr)
        self.assertFalse((self.output / "results.md").exists())

    def test_haiku_retains_existing_protocol_header(self):
        self.models[0] = {
            "key": "H", "model": "anthropic/claude-haiku-4.5",
            "model_header": "#!us.anthropic.claude-haiku-4-5-20251001-v1:0",
        }
        self.assertEqual(self.prepare().returncode, 0)
        raw = (self.output / "variants/S1-H/soul.md").read_bytes()
        self.assertTrue(raw.startswith(self.models[0]["model_header"].encode() + b"\r\n"))

    def test_invalid_catalog_rejected_before_writing(self):
        for invalid in (
            [],
            [None],
            self.models + [self.models[0]],
            [dict(self.models[0], key="../escape")],
            [dict(self.models[0], model_header="#!other/model")],
            self.models + [dict(self.models[0], key="OTHER", model="test/model-1",
                                model_header="#!test/model-1")],
        ):
            with self.subTest(models=invalid):
                original = self.models
                self.models = invalid
                result = self.prepare()
                self.models = original
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.output.exists())

    def test_too_few_policies_rejected_before_writing(self):
        self.cohort["sources"] = self.cohort["sources"][:1]
        self.models = self.models[:8]
        self.assertNotEqual(self.prepare().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_missing_rank_rejected_before_writing(self):
        self.cohort["sources"][8]["rank"] = 10
        self.assertNotEqual(self.prepare().returncode, 0)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
