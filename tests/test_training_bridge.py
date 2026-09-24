"""Offline protocol proof against the compiled Heartleaf engine."""

import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class TrainingBridgeTest(unittest.TestCase):
    def play(self, bad_response="", *, days=1, players=2):
        with subprocess.Popen(
            [str(ROOT / "out/training_bridge"), str(days)],
            cwd=ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        ) as engine:

            def request(command):
                engine.stdin.write(json.dumps(command) + "\n")
                engine.stdin.flush()
                return json.loads(engine.stdout.readline())

            observation = request(
                {"kind": "reset", "seed": "91002", "players": players}
            )
            first = observation
            stale = request({"kind": "step", "decision_id": -1, "response": "{}"})
            self.assertEqual(stale["kind"], "rejected")
            self.assertEqual(first["messages"][0]["role"], "system")
            self.assertIn(
                "heartleaf-dinner-training-v1", first["messages"][0]["content"]
            )
            self.assertNotIn(
                "highest connection score wins", first["messages"][0]["content"]
            )
            self.assertEqual(first["game"], "heartleaf")
            self.assertEqual(first["engine_seat"], first["seat"])
            self.assertEqual(first["semantic_view"], {"report": first["messages"][-1]["content"]})
            self.assertEqual(first["inbox"], [])
            self.assertEqual(first["speech_messages"], [])
            self.assertIsNone(first["typed_question"])
            counts = [0] * players
            rejected = 0
            decisions = 0
            while observation["kind"] == "decision":
                self.assertLess(decisions, players * days * 120)
                seat = observation["seat"]
                action = (
                    {"action": "gather_plants"}
                    if counts[seat] < 6
                    else {"action": "go_to_house", "targetName": "Ivan"}
                )
                response = (
                    bad_response
                    if bad_response and decisions == 0
                    else json.dumps(action)
                )
                result = request(
                    {
                        "kind": "step",
                        "decision_id": observation["decision_id"],
                        "response": response,
                    }
                )
                if bad_response and decisions == 0:
                    self.assertEqual(result["kind"], "consumed_rejection")
                    self.assertEqual(result["action"], {"action": "wait"})
                    self.assertTrue(result["reason"])
                    rejected += 1
                else:
                    self.assertEqual(result["kind"], "accepted")
                    self.assertEqual(result["action"]["action"], action["action"])
                previous_id = observation["decision_id"]
                observation = result["observation"]
                if observation["kind"] == "decision":
                    self.assertGreater(observation["decision_id"], previous_id)
                counts[seat] += 1
                decisions += 1
            self.assertEqual(
                set(observation["scores"]), {str(seat) for seat in range(players)}
            )
            self.assertGreater(sum(observation["scores"].values()), 0)
            # Reset the same owned process: no terminal state or histories leak.
            reset = request({"kind": "reset", "seed": "91002", "players": players})
            self.assertEqual(reset, first)
            engine.stdin.close()
            self.assertEqual(engine.wait(timeout=10), 0)
        return observation, decisions, rejected

    def test_complete_game_and_deterministic_reset(self):
        self.assertEqual(self.play(), self.play())

    def test_consumed_rejection_still_completes_game(self):
        self.assertEqual(self.play(bad_response="not JSON")[2], 1)

    def test_illegal_mode_consumes_turn(self):
        self.assertEqual(
            self.play(bad_response='{"action":"say","message":"Hello"}')[2], 1
        )

    def test_full_seven_day_nine_seat_game(self):
        self.play(days=7, players=9)


if __name__ == "__main__":
    unittest.main()
