import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import heartleaf_campaign_ops as ops


class CampaignOperationsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.write("campaign.json", {"status": "active", "rounds": [{"round": 0, "metrics": []}, {"round": 1}]})
        self.write("spend-policy.json", {"paused": False, "limit_usd": 1500})

    def write(self, name, value):
        (self.directory / name).write_text(json.dumps(value))

    def test_live_pid_with_wrong_command_is_stopped(self):
        self.write("launch.json", {"pid": 123})
        with patch.object(ops.subprocess, "run", return_value=Mock(returncode=0, stdout="python unrelated.py")):
            self.assertFalse(ops.process_status(self.directory, "controller")["running"])
            self.assertTrue(ops.status(self.directory)["controller_stopped"])

    def test_matching_campaign_process_is_live(self):
        self.write("launch.json", {"pid": 123})
        command = f"python {Path(ops.__file__).parent / 'heartleaf_eval_campaign.py'} --campaign {self.directory}"
        with patch.object(ops.subprocess, "run", return_value=Mock(returncode=0, stdout=command)):
            self.assertTrue(ops.process_status(self.directory, "controller")["running"])

    def test_start_does_not_duplicate_live_processes(self):
        with patch.object(ops, "process_status", return_value={"running": True, "pid": 123}), \
             patch.object(ops.subprocess, "Popen") as launch:
            ops.start(self.directory)
        launch.assert_not_called()

    def test_budget_pause_starts_observer_only(self):
        self.write("spend-policy.json", {"paused": True, "limit_usd": 1500})
        with patch.object(ops, "process_status", return_value={"running": False, "pid": None}), \
             patch.object(ops.subprocess, "Popen", return_value=Mock(pid=123)) as launch:
            ops.start(self.directory)
        self.assertEqual(launch.call_count, 1)
        self.assertIn(str(Path(ops.__file__).parent / "heartleaf_eval_campaign_budget.py"), launch.call_args.args[0])
        self.assertTrue(json.loads((self.directory / "spend-policy.json").read_text())["paused"])
        self.assertFalse((self.directory / "launch.json").exists())

    def test_start_launches_monitor_before_controller_with_receipts(self):
        with patch.object(ops, "process_status", return_value={"running": False, "pid": None}), \
             patch.object(ops.subprocess, "Popen", side_effect=[Mock(pid=123), Mock(pid=456)]) as launch:
            ops.start(self.directory)
        self.assertEqual(launch.call_count, 2)
        self.assertEqual(json.loads((self.directory / "monitor-launch.json").read_text())["pid"], 123)
        self.assertEqual(json.loads((self.directory / "launch.json").read_text())["pid"], 456)
        self.assertTrue(launch.call_args.kwargs["start_new_session"])

    def test_wait_returns_for_finished_game_without_launching(self):
        initial = {"status": "active", "budget_paused": False, "spend_stale": False,
                   "processes_live": {"controller": True, "spend_monitor": True}, "terminal_games": []}
        finished = initial | {"terminal_games": [("request-1", "completed", True)]}
        with patch.object(ops, "milestone", side_effect=[initial, initial, finished]), \
             patch.object(ops.time, "sleep") as sleep, patch.object(ops.subprocess, "Popen") as launch:
            self.assertEqual(ops.wait_for_change(self.directory), finished)
        self.assertEqual(sleep.call_count, 2)
        launch.assert_not_called()

    def test_wait_immediately_reports_existing_issue(self):
        healthy = {"status": "active", "budget_paused": False, "spend_stale": False,
                   "processes_live": {"controller": True}, "terminal_games": []}
        for change in ({"budget_paused": True}, {"spend_stale": True},
                       {"processes_live": {"controller": False}},
                       {"terminal_games": [("request-1", "completed", False)]}):
            with self.subTest(change=change), patch.object(ops, "milestone", return_value=healthy | change), \
                 patch.object(ops.time, "sleep") as sleep:
                self.assertEqual(ops.wait_for_change(self.directory), healthy | change)
                sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
