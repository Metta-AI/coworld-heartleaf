"""Offline coverage tests for nine-player games over the full 90-policy cohort."""

import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "heartleaf_eval_schedule",
    Path(__file__).resolve().parents[1] / "tools/heartleaf_eval_schedule.py",
)
scheduler = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scheduler)


class ScheduleTests(unittest.TestCase):
    def test_full_cartesian_product_meets_every_pair_twice(self):
        keys = [f"S{s}-M{m}" for s in range(1, 10) for m in range(1, 11)]
        games = scheduler.covering_schedule(keys, meetings=2)
        self.assertTrue(all(len(game) == len(set(game)) == 9 for game in games))
        counts = scheduler.count_pairs(keys, games)
        self.assertEqual(len(counts), 4005)
        self.assertGreaterEqual(min(counts.values()), 2)
        # Same-soul/different-model and same-model/different-soul are real pairs.
        self.assertGreaterEqual(counts[tuple(sorted(("S1-M1", "S1-M2")))], 2)
        self.assertGreaterEqual(counts[tuple(sorted(("S1-M1", "S2-M1")))], 2)

    def test_affine_81_policy_schedule_is_minimal_and_preserves_initial_games(self):
        from collections import Counter

        keys = [f"S{s}-M{m:02}" for s in range(1, 10) for m in range(1, 10)]
        games = scheduler.covering_schedule(keys, meetings=1)
        self.assertEqual(len(games), 90)
        self.assertEqual(set(scheduler.count_pairs(keys, games).values()), {1})
        self.assertEqual(set(Counter(k for g in games for k in g).values()), {10})
        self.assertEqual(games[:9], scheduler.covering_schedule(keys, meetings=2)[:9])
        self.assertEqual(games, scheduler.covering_schedule(keys[::-1], meetings=1))

    def test_nine_policies_need_two_games(self):
        keys = [f"P{i}" for i in range(9)]
        games = scheduler.covering_schedule(keys, meetings=2)
        self.assertEqual(len(games), 2)
        self.assertNotEqual(games[0], games[1])
        self.assertEqual(set(scheduler.count_pairs(keys, games).values()), {2})

    def test_order_is_deterministic(self):
        keys = [f"P{i}" for i in range(18)]
        self.assertEqual(
            scheduler.covering_schedule(keys), scheduler.covering_schedule(keys[::-1])
        )

    def test_invalid_inputs(self):
        for keys in (
            ["same"] * 9,
            [str(i) for i in range(8)],
            [""] + [str(i) for i in range(8)],
        ):
            with self.assertRaises(ValueError):
                scheduler.covering_schedule(keys)
        for meetings in (0, -1, True, 1.5):
            with self.assertRaises(ValueError):
                scheduler.covering_schedule([str(i) for i in range(9)], meetings)

    def test_counter_rejects_invalid_games_and_unknown_keys(self):
        keys = [str(i) for i in range(9)]
        for game in (keys[:-1], [keys[0]] * 9, keys[:-1] + ["unknown"]):
            with self.assertRaises(ValueError):
                scheduler.count_pairs(keys, [game])

    def test_failed_short_and_duplicate_episodes_do_not_inflate_coverage(self):
        keys = [str(i) for i in range(9)]
        good = {
            "episode_id": "one",
            "status": "completed",
            "max_days": 7,
            "policy_keys": keys,
            "acceptance_verified": True,
        }
        evidence = [
            good,
            dict(good),
            dict(good, episode_id="failed", status="failed"),
            dict(good, episode_id="canary", max_days=1),
            dict(good, episode_id="unverified", acceptance_verified=False),
        ]
        counts = scheduler.completed_pair_coverage(keys, evidence)
        self.assertEqual(set(counts.values()), {1})
        with self.assertRaises(ValueError):
            scheduler.completed_pair_coverage(keys, [good, dict(good, status="failed")])


if __name__ == "__main__":
    unittest.main()
