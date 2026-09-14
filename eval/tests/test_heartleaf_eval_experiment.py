"""Failure-oriented contracts for configurable experiments and evidence collection."""

import copy
import json
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import Mock, patch
from uuid import UUID

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import heartleaf_eval_experiment as runner
import heartleaf_eval_results as results


def fixture():
    variants = [
        {
            "key": f"S{i}-M",
            "policy_version_id": str(UUID(int=i + 1)),
            "source_rank": i + 1,
            "source_policy_version_id": str(UUID(int=i + 20)),
            "soul_sha256": "a" * 64,
            "body_sha256": "b" * 64,
            "model": "test/model:nitro",
            "model_header": "#!test/model:nitro",
        }
        for i in range(9)
    ]
    batch = {
        "batch_id": "test",
        "coworld_id": "cow_test",
        "coworld_version": "0.1.5",
        "league_id": None,
        "variants": variants,
        "game_provenance": {"viewer_bundle": "viewer@digest"},
    }
    job = str(UUID(int=99))
    detail = {
        "id": "xreq_test",
        "coworld_id": "cow_test",
        "status": "completed",
        "episode_count": 1,
        "variant_id": "league",
        "episodes": [
            {
                "id": "ereq_test",
                "episode_id": str(UUID(int=100)),
                "job_id": job,
                "coworld_id": "cow_test",
                "coworld_version": "0.1.5",
                "status": "completed",
                "game_config": {"maxDays": 7},
                "participants": [
                    {"position": i, "policy_version_id": v["policy_version_id"]}
                    for i, v in enumerate(variants)
                ],
                "participant_scores": [{"position": i, "score": i} for i in range(9)],
            }
        ],
    }
    rows = [
        {
            "platform_call_id": str(UUID(int=i + 200)),
            "job_id": job,
            "slot": str(i),
            "canonical_model": "test/model:nitro",
            "provider": "upstream",
            "ok": True,
            "latency_ms": 500,
            "finish_reason": "stop",
            "input_tokens": 10,
            "output_tokens": 3,
            "reasoning_tokens": 0,
            "billed_cost_usd": 0.01,
            "reconciled_from_broadcast": True,
        }
        for i in range(9)
    ]
    log = "Heartleaf config: test\n" + "\n".join(
        f"soul accepted seat={i} hash=abc\nllm request day=7 tag={i}:1 model=test/model:nitro\ntag={i}:1 outcome=usable"
        for i in range(9)
    )
    raw = {
        "calls.json": rows,
        "attempts.json": [{"id": job}],
        "jobs.json": [
            {
                "id": job,
                "status": "completed",
                "compute_usd": 0.1,
                "llm_routing": {"provider": "openrouter"},
            }
        ],
        "privacy.json": [
            {"private": True, "coworld_id": "cow_test", "league_id": None}
        ],
        "results": {"day": 7, "scores": list(range(9))},
    }
    return batch, detail, raw, log


class ResultsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.batch, self.detail, self.raw, self.log = fixture()

    def summarize(self):
        for filename, value in self.raw.items():
            results.write_json(self.directory / filename, value)
        results.atomic_bytes(self.directory / "logs", self.log.encode())
        results.atomic_bytes(self.directory / "replay", b"replay-evidence")
        return results.normalize(self.batch, "eval-0001", self.detail, self.directory)

    def structured_evidence(self):
        events = []
        for slot in range(9):
            for text in (
                f"llm request day=7 tag={slot}:1 model=test/model:nitro",
                f"llm reply day=7 tag={slot}:1 outcome=usable",
            ):
                events.append(
                    {
                        "sequence": len(events),
                        "role": "llm",
                        "seat": slot,
                        "gnome": f"Gnome{slot}",
                        "text": text,
                    }
                )
        return {
            "schema": "heartleaf-eval-evidence/1",
            "event_count": len(events),
            "events": events,
            "accepted_seats": [
                {"slot": s, "model": "test/model:nitro"} for s in range(9)
            ],
        }

    def test_structured_artifact_survives_more_than_10000_stdout_lines(self):
        self.raw["results"]["evaluation"] = self.structured_evidence()
        self.batch["eval_artifact_required"] = True
        self.log = "movement chatter\n" * 12000
        record = self.summarize()
        self.assertTrue(record["measurement_verified"], record["measurement_problems"])
        self.assertEqual(record["calls"], 9)
        self.assertEqual(record["applied_actions"], 9)
        (self.directory / "logs").unlink()
        record = results.normalize(self.batch, "eval-0001", self.detail, self.directory)
        self.assertTrue(record["measurement_verified"], record["measurement_problems"])

    def test_required_or_corrupt_structured_evidence_cannot_fall_back_to_stdout(self):
        self.batch["eval_artifact_required"] = True
        self.assertIn("missing_eval_evidence", self.summarize()["measurement_problems"])
        evidence = self.structured_evidence()
        evidence["event_count"] += 1
        self.raw["results"]["evaluation"] = evidence
        self.assertIn(
            "unreadable_eval_evidence", self.summarize()["measurement_problems"]
        )

    def test_artifact_runtime_terminal_day_rollover(self):
        self.batch.update(coworld_version="0.1.9", eval_artifact_required=True)
        evidence = self.structured_evidence()
        for event in evidence["events"]:
            event["day"] = 7
        self.raw["results"].update(day=8, evaluation=evidence)
        record = self.summarize()
        self.assertEqual(record["reported_day"], 8)
        self.assertEqual(record["realized_days"], 7)
        self.assertNotIn("duration_unverified", record["measurement_problems"])
        for event in evidence["events"]:
            event["day"] = 6
        self.assertIn("duration_unverified", self.summarize()["measurement_problems"])
        for event in evidence["events"]:
            event["day"] = 8
        self.assertIn("duration_unverified", self.summarize()["measurement_problems"])

    def test_complete_measured_episode(self):
        record = self.summarize()
        self.assertTrue(record["acceptance_verified"])
        self.assertEqual(record["applied_actions"], 9)
        self.assertAlmostEqual(record["cost_usd"], 0.19)
        self.assertEqual(record["seats"][0]["served_models"], ["test/model:nitro"])

    def test_unusable_response_evidence_survives_export_with_join_id(self):
        event = {
            "schema": "heartleaf-call-outcome/1",
            "action": "wait",
            "outcome": "invalid_response",
            "slot": 0,
            "tag": "0:1",
            "platform_call_id": "call-123",
            "response_text": "hello\nworld",
            "response_body": '{"text":"hello"}',
        }
        self.log += (
            "\nIvan: llm failure day=7 now=1.0 event="
            + json.dumps(event)
            + " (8:00pm)\n"
        )
        record = self.summarize()
        self.assertEqual(record["seats"][0]["unusable_wait_actions"], 1)
        export = results.export(self.directory / "export", [record])
        row = json.loads((export / "failures.json").read_text())[0]
        self.assertEqual(row["platform_call_id"], "call-123")
        self.assertEqual(row["response_text"], "hello\nworld")
        self.assertEqual(row["response_body"], event["response_body"])
        self.assertEqual(row["job_id"], self.detail["episodes"][0]["job_id"])

    def test_ignored_action_is_not_an_applied_action(self):
        self.log = self.log.replace(
            "tag=0:1 outcome=usable", "tag=0:1 outcome=usable ignored=wait"
        )
        record = self.summarize()
        self.assertEqual(record["parsed_replies"], 9)
        self.assertEqual(record["applied_actions"], 8)
        self.assertEqual(record["ignored_actions"], 1)
        self.assertFalse(record["acceptance_verified"])

    def test_missing_cost_and_tokens_remain_unknown(self):
        self.raw["calls.json"][0].update(billed_cost_usd=None, input_tokens=None)
        record = self.summarize()
        self.assertIsNone(record["cost_usd"])
        self.assertIsNone(record["input_tokens"]["value"])
        self.assertEqual(record["input_tokens"]["missing"], 1)
        self.assertAlmostEqual(record["known_cost_usd"], 0.18)
        self.assertIn("unresolved_accounting", record["unresolved"])

    def test_missing_call_ingestion_cannot_make_accounting_complete(self):
        self.raw["calls.json"].pop()
        record = self.summarize()
        self.assertIsNone(record["cost_usd"])
        self.assertIn("call_log_count_mismatch", record["unresolved"])

    def test_unfinished_final_request_is_valid_but_cost_remains_unknown(self):
        self.log = self.log.replace(
            "llm request day=7 tag=0:1", "llm request day=7 now=1000.0 tag=0:1"
        )
        self.log += "\nllm request day=7 now=1010.0 tag=0:2 model=test/model:nitro\n"
        self.raw["calls.json"][0]["timestamp"] = "1970-01-01T00:16:40.500000+00:00"
        record = self.summarize()
        self.assertTrue(record["measurement_verified"])
        self.assertIsNone(record["cost_usd"])
        self.assertIn("in_flight_at_episode_end", record["unresolved"])
        self.assertEqual(record["seats"][0]["unreported_in_flight_tags"], ["0:2"])
        # A reply proves this was a completed request with missing telemetry.
        self.log += "llm reply day=7 now=1011.0 tag=0:2 outcome=usable\n"
        self.assertIn(
            "call_log_count_mismatch", self.summarize()["measurement_problems"]
        )

    def test_unfinished_request_requires_unique_timestamp_match(self):
        log = "llm request day=1 now=1000.0 tag=0:1\nllm request day=1 now=1010.0 tag=0:2\n"
        calls = [{"timestamp": "1970-01-01T00:16:40.5+00:00", "latency_ms": 500}]
        self.assertEqual(results.unreported_requests(log, 0, calls, []), (["0:2"], []))
        calls[0]["latency_ms"] = 20000
        self.assertEqual(results.unreported_requests(log, 0, calls, []), ([], []))
        self.assertEqual(results.unreported_requests(log, 0, [], []), ([], []))

    def test_missing_timeout_telemetry_preserves_turn_and_unknown_cost(self):
        self.log = self.log.replace(
            "llm request day=7 tag=0:1", "llm request day=7 now=1000.0 tag=0:1"
        )
        self.raw["calls.json"][0]["timestamp"] = "1970-01-01T00:16:40.500000+00:00"
        event = {
            "schema": "heartleaf-call-outcome/1", "action": "wait",
            "slot": 0, "tag": "0:2", "outcome": "deadline_exceeded",
            "request_started_at": 1010.0, "http_status": 0,
            "error": "Timeout was reached", "response_text": "",
        }
        self.log += (
            "\nllm request day=7 now=1010.0 tag=0:2\n"
            "llm reply day=7 now=1030.0 tag=0:2 outcome=transient\n"
            "llm failure day=7 event=" + json.dumps(event) + "\n"
            "llm request day=7 now=1040.0 tag=0:3\n"
        )
        record = self.summarize()
        self.assertTrue(record["measurement_verified"], record["measurement_problems"])
        self.assertIsNone(record["cost_usd"])
        self.assertEqual(record["calls"], 9)
        self.assertEqual(record["seats"][0]["unreported_timeout_tags"], ["0:2"])
        self.assertEqual(record["seats"][0]["unreported_in_flight_tags"], ["0:3"])
        self.assertEqual(record["unusable_responses"][0]["outcome"], "deadline_exceeded")
        self.assertIn("timeout_call_telemetry_missing", record["unresolved"])
        self.log = self.log.replace('"outcome": "deadline_exceeded"', '"outcome": "upstream_error"')
        self.assertIn("call_log_count_mismatch", self.summarize()["measurement_problems"])

    def test_missing_timeout_record_requires_matching_failure_identity(self):
        log = (
            "llm request day=7 now=1000.0 tag=0:1\n"
            "llm request day=7 now=1010.0 tag=0:2\n"
            "llm reply day=7 tag=0:2 outcome=transient\n"
        )
        calls = [{"timestamp": "1970-01-01T00:16:40.5+00:00", "latency_ms": 500}]
        failure = {"slot": 0, "tag": "0:2", "outcome": "deadline_exceeded",
                   "request_started_at": 1010.0, "http_status": 0, "error": "Timeout was reached"}
        self.assertEqual(results.unreported_requests(log, 0, calls, [failure]), ([], ["0:2"]))
        for change in ({"slot": 1}, {"tag": "0:3"}, {"request_started_at": 1000.0},
                       {"http_status": 200}, {"error": "Other failure"}):
            with self.subTest(change=change):
                self.assertEqual(results.unreported_requests(log, 0, calls, [failure | change]), ([], []))
        self.assertEqual(results.unreported_requests(log, 0, calls, [failure, failure]), ([], []))

    def test_local_rate_limit_is_a_failed_turn_without_a_platform_call(self):
        event = {
            "schema": "heartleaf-call-outcome/1", "action": "wait",
            "slot": 0, "tag": "0:2", "outcome": "upstream_error",
            "request_started_at": 1010.0, "http_status": 429,
            "platform_call_id": "", "response_body": json.dumps({
                "message": "sidecar request rate limit reached (30 requests/minute)",
                "__type": "ThrottlingException",
            }),
        }
        self.log += (
            "\nllm request day=7 now=1010.0 tag=0:2\n"
            "llm reply day=7 now=1010.1 tag=0:2 outcome=transient\n"
            "llm failure day=7 event=" + json.dumps(event) + "\n"
        )
        record = self.summarize()
        self.assertTrue(record["measurement_verified"], record["measurement_problems"])
        self.assertEqual(record["seats"][0]["local_rate_limit_tags"], ["0:2"])
        self.assertEqual(record["calls"], 9)
        self.assertEqual(record["unusable_responses"][0]["outcome"], "upstream_error")
        for change in ({"platform_call_id": "exists"}, {"http_status": 500},
                       {"request_started_at": 900.0}, {"response_body": "{}"}):
            with self.subTest(change=change):
                self.assertEqual(results.local_rate_limit_tags(self.log, 0, [event | change]), [])
        self.assertEqual(results.local_rate_limit_tags(self.log, 0, [event, event]), [])

    def test_sql_pagination_fetches_beyond_silent_api_cap(self):
        client = Mock()
        first, second = Mock(), Mock()
        first.json.return_value = {
            "columns": ["id"],
            "rows": [[i] for i in range(1000)],
        }
        second.json.return_value = {"columns": ["id"], "rows": [[1000]]}
        client.post.side_effect = [first, second]
        rows = results.query(client, "SELECT id FROM calls ORDER BY id", paginate=True)
        self.assertEqual(len(rows), 1001)
        self.assertIn("OFFSET 1000", client.post.call_args.kwargs["json"]["query"])

    def test_unpaginated_capped_query_fails_explicitly(self):
        client = Mock()
        client.post.return_value.json.return_value = {
            "columns": ["id"],
            "rows": [[i] for i in range(1000)],
        }
        with self.assertRaisesRegex(ValueError, "1000-row cap"):
            results.query(client, "SELECT id FROM calls")

    def test_duplicate_provider_join_cannot_multiply_costs(self):
        self.raw["calls.json"].append(copy.deepcopy(self.raw["calls.json"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate call"):
            self.summarize()

    def test_calls_from_wrong_job_are_rejected(self):
        self.raw["calls.json"][0]["job_id"] = str(UUID(int=999))
        with self.assertRaisesRegex(ValueError, "realized job"):
            self.summarize()

    def test_missing_attempt_is_rejected(self):
        self.raw["jobs.json"] = []
        with self.assertRaisesRegex(ValueError, "each attempt"):
            self.summarize()

    def test_all_retry_costs_retained_but_action_scope_is_incomplete(self):
        job = str(UUID(int=998))
        self.raw["attempts.json"].append({"id": job})
        self.raw["jobs.json"].append(
            {"id": job, "compute_usd": 0.2, "llm_routing": {"provider": "openrouter"}}
        )
        record = self.summarize()
        self.assertAlmostEqual(record["cost_usd"], 0.39)
        self.assertIn("prior_attempt_actions_unavailable", record["unresolved"])
        self.assertFalse(record["acceptance_verified"])

    def test_results_day_and_score_must_match(self):
        self.raw["results"].update(day=1, scores=[0] * 9)
        record = self.summarize()
        self.assertIn("duration_unverified", record["unresolved"])
        self.assertIn("score_readback_mismatch", record["unresolved"])

    def test_missing_replay_is_visible(self):
        self.summarize()
        (self.directory / "replay").unlink()
        record = results.normalize(self.batch, "eval-0001", self.detail, self.directory)
        self.assertIn("missing_replay", record["unresolved"])
        self.assertFalse(record["acceptance_verified"])

    def test_client_timeout_cannot_pass_even_when_metadata_looks_ok(self):
        self.log += "\nTimeout was reached\n"
        self.assertIn("client_timeout", self.summarize()["unresolved"])

    def test_slow_response_is_valid_measurement_not_passing_performance(self):
        self.raw["calls.json"][0]["latency_ms"] = 25000
        self.log += "\nTimeout was reached\n"
        record = self.summarize()
        self.assertTrue(record["measurement_verified"])
        self.assertFalse(record["acceptance_verified"])
        self.assertEqual(record["seats"][0]["outcome"], "deadline_exceeded")
        self.assertEqual(record["seats"][0]["deadline_exceeded_calls"], 1)

    def test_explicit_client_timeout_is_attributed_even_below_latency_boundary(self):
        self.log = self.log.replace(
            "llm request day=7 tag=0:1", "Ivan: llm request day=7 tag=0:1"
        )
        self.log += "\nIvan: llm error status=0 Timeout was reached\n"
        self.log += "Ivan: llm timeout action=wait\n"
        record = self.summarize()
        self.assertEqual(record["seats"][0]["outcome"], "deadline_exceeded")
        self.assertEqual(record["seats"][0]["client_timeout_replies"], 1)
        self.assertEqual(record["seats"][0]["timeout_wait_actions"], 1)
        self.assertEqual(record["seats"][1]["timeout_wait_actions"], 0)
        self.assertTrue(record["measurement_verified"])

    def test_model_failures_and_missing_billing_do_not_discard_game(self):
        self.raw["calls.json"][0].update(ok=False, billed_cost_usd=None)
        record = self.summarize()
        self.assertTrue(record["measurement_verified"])
        self.assertIsNone(record["cost_usd"])
        self.assertEqual(record["seats"][0]["outcome"], "upstream_error")

    def test_wrong_model_still_invalidates_measurement(self):
        self.raw["calls.json"][0]["canonical_model"] = "wrong/model"
        self.assertFalse(self.summarize()["measurement_verified"])

    def test_duplicate_export_does_not_replace_latest(self):
        record = self.summarize()
        out = self.directory / "out"
        generation = results.export(out, [record])
        before = (out / "latest.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "duplicate episodes"):
            results.export(out, [record, record])
        self.assertEqual((out / "latest.json").read_bytes(), before)
        manifest = json.loads((generation / "manifest.json").read_text())
        for name, expected in manifest["files"].items():
            self.assertEqual(results.digest(generation / name), expected)

    def test_transient_artifact_failure_retries_without_publishing_partial_snapshot(
        self,
    ):
        client = Mock()
        artifact_client = Mock()
        artifact_client.get_bytes.side_effect = [
            b"log",
            httpx.ReadTimeout("https://secret?token=do-not-store"),
            b"replay",
        ]
        with (
            patch.object(
                results,
                "query",
                side_effect=[
                    self.raw["attempts.json"],
                    self.raw["calls.json"],
                    self.raw["jobs.json"],
                    self.raw["privacy.json"],
                ],
            ),
            self.assertRaises(httpx.ReadTimeout),
        ):
            results.snapshot(
                self.batch,
                "eval",
                self.detail,
                self.directory,
                client,
                artifact_client,
            )
        self.assertEqual((self.directory / "logs").read_bytes(), b"log")
        self.assertFalse((self.directory / "replay").exists())
        self.assertEqual(
            json.loads((self.directory / "artifact-errors.json").read_text()),
            {"results": "ReadTimeout"},
        )


class ExperimentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.batch, self.detail, _, _ = fixture()
        self.experiment = {
            "name": "test",
            "batch": self.batch,
            "parameters": runner.parameters({"public_replays_accepted": True}),
            "code_sha256": {},
        }
        self.experiment["schedule"] = runner.schedule(
            [v["key"] for v in self.batch["variants"]], self.experiment["parameters"]
        )
        self.game = self.experiment["schedule"][0]

    def test_parameters_reject_mistyped_unknown_and_nonfinite(self):
        for values in (
            {"days": 1},
            {"max_days": True},
            {"seeds": [1, 1]},
            {"seeds": "1"},
            {"projected_game_usd": float("nan")},
            {"max_ignored_fraction": 1.1},
        ):
            with self.subTest(values=values), self.assertRaises(ValueError):
                runner.parameters(values)

    def test_campaign_concurrency_override_launches_all_five_without_changing_inputs(self):
        self.experiment["parameters"].update(
            max_parallel_games=3, stop_threshold_usd=None,
            cost_authorization="Campaign spend guard", canary_days=0,
            seeds=[91002, 91003, 91004, 91005, 91006],
        )
        self.experiment["schedule"] = runner.schedule(
            [v["key"] for v in self.batch["variants"]], self.experiment["parameters"]
        )
        results.write_json(self.directory / "campaign-budget.json", {"campaign": str(self.directory)})
        policy = self.directory / "execution-policy.json"
        results.write_json(policy, {"max_parallel_games": 5})
        submitted = []

        def submit(experiment, game, directory, client):
            submitted.append(game["id"])
            response = {"id": "xreq_" + game["id"]}
            results.write_json(directory / "games" / game["id"] / "response.json", response)
            return response

        def collect(*args):
            self.assertEqual(len(submitted), 5)
            return {"status": "completed", "measurement_verified": True, "unresolved": []}

        with (
            patch.object(runner, "submit", side_effect=submit),
            patch.object(runner, "collect", side_effect=collect),
            patch.object(runner, "publish"),
            patch.object(runner.time, "sleep"),
        ):
            runner.run_parallel(self.experiment, self.directory, Mock(), Mock(), 5, 1)
        self.assertEqual(self.experiment["parameters"]["max_parallel_games"], 3)
        for invalid in (0, -1, True, "5"):
            results.write_json(policy, {"max_parallel_games": invalid})
            with self.assertRaises(ValueError):
                runner.parallel_game_limit(self.experiment, self.directory)
        results.write_json(policy, {"max_parallel_games": 2})
        self.assertEqual(runner.parallel_game_limit(self.experiment, self.directory), 2)

    def test_seed_and_duration_are_real_request_overrides(self):
        self.experiment["parameters"].update(day_seconds=90)
        self.game.update(seed=123, max_days=3)
        body = runner.request_body(self.experiment, self.game)
        self.assertEqual(body["game_config_overrides"]["seed"], 123)
        self.assertEqual(body["game_config_overrides"]["maxDays"], 3)
        self.assertEqual(body["game_config_overrides"]["daySeconds"], 90)
        self.assertTrue(body["private"])
        self.assertNotIn("idempotency_key", body)

    def test_every_seed_gets_its_own_pair_coverage_and_all_policies_canary(self):
        keys = [str(i) for i in range(18)]
        config = runner.parameters({"seeds": [123, 456], "meetings": 3})
        games = runner.schedule(keys, config)
        self.assertEqual(
            {key for g in games if g["kind"] == "canary" for key in g["policy_keys"]},
            set(keys),
        )
        for seed in config["seeds"]:
            counts = runner.count_pairs(
                keys,
                [
                    g["policy_keys"]
                    for g in games
                    if g["kind"] == "evaluation" and g["seed"] == seed
                ],
            )
            self.assertGreaterEqual(min(counts.values()), 3)

    def test_ambiguous_intent_blocks_even_different_game(self):
        results.write_json(self.directory / "games" / "canary-0001" / "intent.json", {})
        client = Mock()
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            runner.submit(
                self.experiment, self.experiment["schedule"][1], self.directory, client
            )
        client.post.assert_not_called()

    def test_existing_receipt_never_reposts(self):
        results.write_json(
            self.directory / "games" / self.game["id"] / "response.json",
            {"id": "xreq_known"},
        )
        client = Mock()
        self.assertEqual(
            runner.submit(self.experiment, self.game, self.directory, client)["id"],
            "xreq_known",
        )
        client.post.assert_not_called()

    def test_http_failure_persists_intent_and_next_run_cannot_repeat_post(self):
        client = Mock()
        client.post.side_effect = httpx.ReadTimeout("ambiguous response")
        with (
            patch.object(runner, "refresh_routing", return_value=self.batch),
            patch.object(runner.api, "validate_setup"),
            patch.object(runner.api, "inspect_scope"),
            patch(
                "coworld.upload.resolve_coworld_download_id", return_value="cow_test"
            ),
            patch.object(runner.api, "get_json", return_value={"state": "certified"}),
            patch.object(results, "query", return_value=[]),
            patch.object(runner, "budget_check"),
            self.assertRaisesRegex(ValueError, "outcome uncertain"),
        ):
            runner.submit(self.experiment, self.game, self.directory, client)
        intent = self.directory / "games" / self.game["id"] / "intent.json"
        self.assertEqual(
            json.loads(intent.read_text()),
            runner.request_body(self.experiment, self.game),
        )
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            runner.submit(self.experiment, self.game, self.directory, client)
        self.assertEqual(client.post.call_count, 1)

    def test_reconcile_uses_get_and_requires_exact_roster(self):
        body = runner.request_body(self.experiment, self.game)
        game_dir = self.directory / "games" / self.game["id"]
        results.write_json(game_dir / "intent.json", body)
        self.detail["requested"] = {"notes": body["notes"], "num_episodes": 1}
        self.detail["episodes"][0]["game_config"] = body["game_config_overrides"]
        client = Mock()
        client.get.return_value.json.return_value = self.detail
        runner.reconcile(
            self.experiment, self.game, self.directory, "xreq_test", client
        )
        client.post.assert_not_called()
        self.detail["episodes"][0]["participants"][0]["policy_version_id"] = str(
            UUID(int=999)
        )
        with self.assertRaisesRegex(ValueError, "seating"):
            runner.reconcile(
                self.experiment, self.game, self.directory, "xreq_test", client
            )

    def ledger(self):
        results.write_json(self.directory / "evidence.json", {"review": "test"})
        ledger = {
            "observed_at": datetime.now(UTC).isoformat(),
            "experiment_sha256": runner.fingerprint(self.experiment),
            "evidence_file": "evidence.json",
            "known_prior_usd": 2,
            "unresolved_reserve_usd": 2,
            "authorized_limit_usd": 10,
            "unresolved_prior_items": ["old-job"],
            "reserve_basis": "test",
        }
        results.write_json(self.directory / "budget.json", ledger)
        return ledger

    def test_budget_uses_larger_live_total_plus_unknown_reserve_and_projection(self):
        self.ledger()
        with (
            patch.object(results, "query", return_value=[{"usd": 8}]),
            self.assertRaisesRegex(ValueError, "soft stop"),
        ):
            runner.budget_check(self.experiment, self.directory, self.game, Mock())
        readback = json.loads(
            (
                self.directory / "games" / self.game["id"] / "budget-readback.json"
            ).read_text()
        )
        self.assertEqual(readback["projected_charged_usd"], 10.8)

    def test_unresolved_current_cost_stops_instead_of_charging_zero(self):
        self.ledger()
        with (
            patch.object(runner, "latest_records", return_value=[{"cost_usd": None}]),
            self.assertRaisesRegex(ValueError, "accounting is unresolved"),
        ):
            runner.budget_check(self.experiment, self.directory, self.game, Mock())

    def test_nonfinite_live_spend_cannot_bypass_budget_stop(self):
        self.ledger()
        with (
            patch.object(results, "query", return_value=[{"usd": "NaN"}]),
            self.assertRaisesRegex(ValueError, "finite"),
        ):
            runner.budget_check(self.experiment, self.directory, self.game, Mock())

    def test_unlimited_budget_requires_authorization_and_keeps_unknown_costs(self):
        with self.assertRaisesRegex(ValueError, "authorization"):
            runner.parameters({"stop_threshold_usd": None})
        self.experiment["parameters"] = runner.parameters(
            {
                "stop_threshold_usd": None,
                "cost_authorization": "User authorized this full study without a cost limit",
            }
        )
        client = Mock()
        record = runner.budget_check(self.experiment, self.directory, self.game, client)
        self.assertIsNone(record["limit_usd"])
        self.assertTrue(record["accounting_required_in_results"])
        client.post.assert_not_called()

    def test_measurement_mode_counts_slow_models_but_legacy_strict_does_not(self):
        record = {"measurement_verified": True, "acceptance_verified": False}
        self.assertTrue(runner.progression_verified(self.experiment, record))
        self.experiment["parameters"]["evaluation_mode"] = "strict"
        self.assertFalse(runner.progression_verified(self.experiment, record))

    def test_parallel_runner_finishes_canary_before_evaluations_and_obeys_bound(self):
        self.experiment["parameters"]["max_parallel_games"] = 2
        events = []

        def submit(experiment, game, directory, client):
            events.append(("submit", game["kind"]))
            response = {"id": "xreq_" + game["id"]}
            results.write_json(
                directory / "games" / game["id"] / "response.json", response
            )
            return response

        def collect(experiment, game, directory, client, artifacts):
            events.append(("complete", game["kind"]))
            return {
                "status": "completed",
                "measurement_verified": True,
                "unresolved": [],
            }

        with (
            patch.object(runner, "submit", side_effect=submit),
            patch.object(runner, "collect", side_effect=collect),
            patch.object(runner, "publish"),
            patch.object(runner.time, "sleep"),
        ):
            runner.run_parallel(self.experiment, self.directory, Mock(), Mock(), 2, 1)
        self.assertEqual(
            events,
            [
                ("submit", "canary"),
                ("complete", "canary"),
                ("submit", "evaluation"),
                ("complete", "evaluation"),
            ],
        )

    def test_frozen_parameters_cannot_be_edited_in_place(self):
        frozen = dict(self.experiment, schema="heartleaf-experiment/1", source_files={})
        path = self.directory / "experiment.json"
        results.write_json(path, frozen)
        results.write_json(
            self.directory / "fingerprint.json", {"sha256": runner.fingerprint(frozen)}
        )
        with patch.object(runner.api, "BATCH_ROOT", self.directory):
            self.assertEqual(runner.load(path), frozen)
            changed = copy.deepcopy(frozen)
            changed["parameters"]["max_days"] += 1
            results.write_json(path, changed)
            with self.assertRaisesRegex(ValueError, "Frozen experiment changed"):
                runner.load(path)

    def test_runner_revision_preserves_request_and_detects_changed_archive(self):
        body = runner.request_body(self.experiment, self.game)
        manifest = runner.revise_runner(
            self.experiment, self.directory, "Fix read retries"
        )
        hashes = runner.runner_revision(self.experiment, self.directory)
        self.assertEqual(
            hashes[Path(runner.__file__).name], results.digest(Path(runner.__file__))
        )
        self.assertEqual(body, runner.request_body(self.experiment, self.game))
        (manifest.parent / Path(runner.__file__).name).write_text("changed")
        with self.assertRaisesRegex(ValueError, "Archived runner revision changed"):
            runner.runner_revision(self.experiment, self.directory)

    def test_poll_retries_connections_timeouts_and_server_errors_without_posting(self):
        results.write_json(
            self.directory / "games" / self.game["id"] / "response.json",
            {"id": "xreq_known"},
        )
        response = httpx.Response(
            503, request=httpx.Request("GET", "https://example.com")
        )
        errors = [
            httpx.ConnectError("offline"),
            httpx.ReadTimeout("late"),
            httpx.HTTPStatusError(
                "unavailable", request=response.request, response=response
            ),
        ]
        complete = {
            "status": "completed",
            "measurement_verified": True,
            "unresolved": [],
        }
        with (
            patch.object(runner, "collect", side_effect=[*errors, complete]) as collect,
            patch.object(runner, "submit") as submit,
            patch.object(runner, "publish"),
            patch.object(runner.time, "sleep") as sleep,
        ):
            runner.run_parallel(self.experiment, self.directory, Mock(), Mock(), 0, 1)
        self.assertEqual(collect.call_count, 4)
        self.assertEqual(sleep.call_count, 3)
        submit.assert_not_called()

    def test_preflight_connection_error_retries_before_creating_game(self):
        def submit(experiment, game, directory, client):
            results.write_json(
                directory / "games" / game["id"] / "response.json", {"id": "xreq_new"}
            )
            return {"id": "xreq_new"}

        attempts = 0

        def flaky_submit(*args):
            nonlocal attempts
            attempts += 1
            if attempts == 1:
                raise httpx.ConnectError("offline")
            return submit(*args)

        with (
            patch.object(runner, "submit", side_effect=flaky_submit),
            patch.object(
                runner,
                "collect",
                return_value={
                    "status": "completed",
                    "measurement_verified": True,
                    "unresolved": [],
                },
            ),
            patch.object(runner, "publish"),
            patch.object(runner.time, "sleep"),
        ):
            runner.run_parallel(self.experiment, self.directory, Mock(), Mock(), 1, 1)
        self.assertEqual(attempts, 2)

    def test_authentication_errors_are_not_transient(self):
        response = httpx.Response(
            403, request=httpx.Request("GET", "https://example.com")
        )
        self.assertFalse(
            results.transient_read_error(
                httpx.HTTPStatusError(
                    "forbidden", request=response.request, response=response
                )
            )
        )

    def test_failed_atomic_replacement_preserves_old_file(self):
        path = self.directory / "receipt.json"
        results.write_json(path, {"id": "old"})
        before = path.read_bytes()
        with (
            patch.object(results.os, "replace", side_effect=OSError("disk full")),
            self.assertRaises(OSError),
        ):
            results.write_json(path, {"id": "new"})
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(list(self.directory.glob(".writing-*")), [])


class LiveLogTests(unittest.TestCase):
    def test_preserves_platform_tail_and_requires_exact_job_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            captures = root / "hosted-logs"
            captures.mkdir()
            generation = root / "snapshot"
            generation.mkdir()
            (generation / "logs").write_text("truncated platform log")
            (captures / "job-one.log").write_text(
                "Heartleaf config: test\ncomplete stdout"
            )
            receipt = captures / "job-one.capture.json"
            receipt.write_text(json.dumps({"job_id": "job-one", "container": "game"}))
            with patch.object(runner.api, "BATCH_ROOT", root):
                runner.preserve_live_log("job-other", generation)
                self.assertEqual(
                    (generation / "logs").read_text(), "truncated platform log"
                )
                runner.preserve_live_log("job-one", generation)
                self.assertEqual(
                    (generation / "platform-logs").read_text(), "truncated platform log"
                )
                self.assertIn("complete stdout", (generation / "logs").read_text())
                receipt.write_text(
                    json.dumps({"job_id": "job-wrong", "container": "game"})
                )
                with self.assertRaisesRegex(ValueError, "identity mismatch"):
                    runner.preserve_live_log("job-one", generation)


class RescheduleTests(unittest.TestCase):
    def test_existing_request_notes_and_identity_are_preserved(self):
        source = {
            "name": "old",
            "batch": {
                "batch_id": "test",
                "coworld_id": "cow_test",
                "variants": [
                    {"key": f"P{i}", "policy_version_id": str(UUID(int=i + 1))}
                    for i in range(9)
                ],
            },
            "parameters": {"day_seconds": 180},
            "schedule": [
                {
                    "id": "eval-0001",
                    "seed": 1,
                    "max_days": 7,
                    "policy_keys": [f"P{i}" for i in range(9)],
                }
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            game_dir = directory / "games" / "eval-0001"
            game_dir.mkdir(parents=True)
            body = runner.request_body(source, source["schedule"][0])
            (game_dir / "intent.json").write_text(json.dumps(body))
            (game_dir / "response.json").write_text(json.dumps({"id": "xreq_existing"}))
            target = copy.deepcopy(source)
            target["name"] = "new"
            attached = runner.carry_requests(source, directory, target)
            self.assertEqual(len(attached), 1)
            self.assertEqual(runner.request_body(target, target["schedule"][0]), body)
            target["schedule"][0]["policy_keys"].reverse()
            with self.assertRaisesRegex(ValueError, "change an existing"):
                runner.carry_requests(source, directory, target)
            target["schedule"] = []
            with self.assertRaisesRegex(ValueError, "drop an existing"):
                runner.carry_requests(source, directory, target)
            (game_dir / "response.json").unlink()
            with self.assertRaisesRegex(ValueError, "ambiguous"):
                runner.carry_requests(source, directory, target)


if __name__ == "__main__":
    unittest.main()
