"""Offline contract checks for the nine-seat Heartleaf evaluation driver."""

import copy
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import Mock, patch
from uuid import UUID

import httpx

SPEC = importlib.util.spec_from_file_location(
    "heartleaf_eval", Path(__file__).resolve().parents[1] / "tools/heartleaf_eval.py"
)
eval_driver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(eval_driver)
API_SPEC = importlib.util.spec_from_file_location(
    "heartleaf_eval_api",
    Path(__file__).resolve().parents[1] / "tools/heartleaf_eval_api.py",
)
api_driver = importlib.util.module_from_spec(API_SPEC)
API_SPEC.loader.exec_module(api_driver)

POLICY_KEYS = [f"S{rank}-{model}" for rank in range(1, 4) for model in ("H", "Q", "G")]
ORIGINAL_WORLD = "cow_f7e8be04-190b-470f-befe-fe98ca1cbcea"


def batch_fixture():
    return {
        "batch_id": "offline-test",
        "coworld_id": "cow_00000000-0000-4000-8000-000000000001",
        "original_coworld_id": ORIGINAL_WORLD,
        "league_id": "heartleaf-eval-test",
        "variants": [
            {
                "key": key,
                "model": eval_driver.MODEL_SLUGS[key.split("-")[1]],
                "policy_version_id": str(UUID(int=index + 1)),
                "owner_id": "same-owner",
            }
            for index, key in enumerate(POLICY_KEYS)
        ],
    }


class SoulTransformTests(unittest.TestCase):
    def test_expected_model_headers(self):
        self.assertEqual(
            eval_driver.MODEL_HEADERS,
            {
                "H": "#!us.anthropic.claude-haiku-4-5-20251001-v1:0",
                "Q": "#!qwen/qwen3.5-35b-a3b",
                "G": "#!openai/gpt-oss-120b",
            },
        )

    def test_header_only_change_preserves_raw_body_and_line_endings(self):
        body = "  Welcome, {name}!\r\nKeep café plants.\rFinal line.  \n".encode()
        for separator in (b"\n", b"\r\n", b"\r"):
            for header in eval_driver.MODEL_HEADERS.values():
                with self.subTest(separator=separator, header=header):
                    result = eval_driver.transform_soul(
                        b"#!unknown.valid" + separator + body, header
                    )
                    self.assertEqual(result, header.encode() + separator + body)
                    self.assertEqual(
                        hashlib.sha256(result[len(header) + len(separator) :]).digest(),
                        hashlib.sha256(body).digest(),
                    )

    def test_invalid_sources(self):
        invalid = [
            b"",
            b"just a body",
            b"#!model",
            b"#!model\n \t\r\n",
            b"#!\nbody",
            b"#!model\nbody\0",
            b"#!model\n\xff",
            b"#!bad model\nbody",
            b"#!" + b"x" * 129 + b"\nbody",
            b"#!model\n" + b"x" * 32768,
        ]
        for source in invalid:
            with self.subTest(source=source[:40]), self.assertRaises(ValueError):
                eval_driver.transform_soul(source, eval_driver.MODEL_HEADERS["H"])

    def test_invalid_generated_headers(self):
        for header in (
            "",
            "model",
            "#!",
            "#!bad model",
            "#!bad@model",
            "#!a\nbody",
            "#!" + "x" * 129,
        ):
            with self.subTest(header=header), self.assertRaises(ValueError):
                eval_driver.transform_soul(b"#!model\nbody", header)

    def test_generated_size_limit_is_checked(self):
        source = b"#!a\n" + b"x" * (32768 - 4)
        self.assertEqual(eval_driver.transform_soul(source, "#!a"), source)
        with self.assertRaises(ValueError):
            eval_driver.transform_soul(source, eval_driver.MODEL_HEADERS["H"])

    def test_duplicate_source_bodies_remain_identical(self):
        sources = (b"#!anthropic.old\nBe kind.\r\n", b"#!openai/old\nBe kind.\r\n")
        for header in eval_driver.MODEL_HEADERS.values():
            self.assertEqual(
                *(eval_driver.transform_soul(source, header) for source in sources)
            )


class PreparationTests(unittest.TestCase):
    def complete_evidence(self):
        batch = batch_fixture()
        policies = {
            variant["key"]: variant["policy_version_id"]
            for variant in batch["variants"]
        }
        episodes = []
        for game in eval_driver.make_schedule():
            episodes.append(
                {
                    "episode_id": "ep-" + game["id"],
                    "game_id": game["id"],
                    "status": "completed",
                    "policy_keys": game["policy_keys"],
                    "seats": [
                        {
                            "slot": slot,
                            "policy_key": key,
                            "policy_version_id": policies[key],
                            "served_model": eval_driver.MODEL_SLUGS[key.split("-")[1]],
                            "provider": "openrouter",
                            "score": 1.0,
                            "successful_calls": 2,
                            "usable_actions": 2,
                            "failed_calls": 0,
                            "truncations": 0,
                            "timeouts": 0,
                            "input_tokens": 100,
                            "output_tokens": 20,
                            "llm_cost_usd": 0.01,
                        }
                        for slot, key in enumerate(game["policy_keys"])
                    ],
                }
            )
        return {
            "batch_id": batch["batch_id"],
            "episodes": episodes,
            "costs": {
                "canary_usd": 0.09,
                "evaluation_usd": 0.18,
                "setup_compute_usd": 0.03,
                "total_usd": 0.30,
            },
            "verification": {
                key: True
                for key in (
                    "provenance",
                    "private_league",
                    "paused_rounds",
                    "nine_variants",
                    "canary",
                    "full_games",
                    "routing",
                    "accounting",
                    "replays",
                    "image_visibility",
                )
            },
        }

    def generate_report(self, evidence, batch=None):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / "offline-test"
            batch_path = directory / "batch.json"
            evidence_path = directory / "evidence.json"
            api_driver.write_json(batch_path, batch or batch_fixture())
            api_driver.write_json(evidence_path, evidence)
            with patch.object(eval_driver, "BATCH_ROOT", root):
                eval_driver.report(batch_path, evidence_path)
            return json.loads((directory / "results.json").read_text())

    def test_complete_consistent_supplied_report_evidence(self):
        result = self.generate_report(self.complete_evidence())
        self.assertEqual(result["unresolved"], [])
        self.assertEqual(result["acceptance"], "reported verified by supplied evidence")

    def test_report_verifies_revised_frozen_model_instead_of_original_key(self):
        batch = batch_fixture()
        batch["variants"][1]["model"] = "google/gemini-2.5-flash-lite"
        evidence = self.complete_evidence()
        self.assertTrue(self.generate_report(evidence, batch)["unresolved"])
        for episode in evidence["episodes"]:
            for seat in episode["seats"]:
                if seat["policy_key"] == "S1-Q":
                    seat["served_model"] = "google/gemini-2.5-flash-lite"
        self.assertEqual(self.generate_report(evidence, batch)["unresolved"], [])

    def test_leagueless_report_requires_request_privacy_not_private_league(self):
        batch = batch_fixture()
        batch.update(submission_mode="leagueless", league_id=None)
        evidence = self.complete_evidence()
        result = self.generate_report(evidence, batch)
        self.assertIn("private_requests", result["unresolved"])
        self.assertIn("seed_rounds_paused", result["unresolved"])
        del evidence["verification"]["private_league"]
        del evidence["verification"]["paused_rounds"]
        evidence["verification"].update(private_requests=True, seed_rounds_paused=True)
        result = self.generate_report(evidence, batch)
        self.assertEqual(result["unresolved"], [])
        self.assertNotIn("private_league", result["verification"])
        self.assertNotIn("paused_rounds", result["verification"])

    def test_report_invalid_measurements_cannot_claim_verification(self):
        mutations = [
            ("slot", -1),
            ("slot", True),
            ("slot", 1),
            ("policy_version_id", "latest"),
            ("policy_version_id", str(UUID(int=99))),
            ("score", float("nan")),
            ("score", True),
            ("llm_cost_usd", -1),
            ("successful_calls", True),
            ("usable_actions", 0),
            ("truncations", 1),
            ("failed_calls", -1),
            ("input_tokens", 1.5),
        ]
        for field, value in mutations:
            evidence = self.complete_evidence()
            evidence["episodes"][0]["seats"][0][field] = value
            with self.subTest(field=field, value=value):
                self.assertEqual(
                    self.generate_report(evidence)["acceptance"], "unresolved"
                )
        for field in (
            "slot",
            "policy_version_id",
            "score",
            "llm_cost_usd",
            "successful_calls",
            "usable_actions",
            "failed_calls",
            "truncations",
            "timeouts",
            "input_tokens",
            "output_tokens",
        ):
            evidence = self.complete_evidence()
            del evidence["episodes"][0]["seats"][0][field]
            with self.subTest(missing=field):
                self.assertEqual(
                    self.generate_report(evidence)["acceptance"], "unresolved"
                )

    def test_report_inconsistent_cost_totals_cannot_claim_verification(self):
        evidence = self.complete_evidence()
        evidence["costs"]["total_usd"] = 0
        self.assertEqual(self.generate_report(evidence)["acceptance"], "unresolved")

    def test_tampered_source_fails_before_creating_batch(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source = directory / "soul.md"
            source.write_bytes(b"#!anthropic.old\nChanged body\n")
            digest = "a" * 64
            cohort = {
                "reviewed": True,
                "batch_id": "tamper-test",
                "captured_at": "2026-09-08T12:00:00Z",
                "league_id": "source-league",
                "division_id": "source-division",
                "ranking_metric": "score",
                "game_provenance": {
                    "coworld_id": ORIGINAL_WORLD,
                    "version": "0.2.7",
                    "game_image": f"registry/game@sha256:{digest}",
                    "viewer_bundle": f"sha256:{digest}",
                },
                "sources": [
                    {
                        "rank": rank,
                        "policy_version_id": str(UUID(int=rank)),
                        "image_id": f"img_{rank}",
                        "image_digest": f"sha256:{digest}",
                        "image_ref": f"registry/player@sha256:{digest}",
                        "soul_path": str(source),
                        "container_soul_path": "/soul.md",
                        "soul_sha256": hashlib.sha256(
                            b"#!anthropic.old\nReviewed body\n"
                        ).hexdigest(),
                    }
                    for rank in range(1, 4)
                ],
            }
            path = directory / "cohort.json"
            api_driver.write_json(path, cohort)
            output = directory / "batches"
            with (
                patch.object(eval_driver, "BATCH_ROOT", output),
                self.assertRaises(ValueError),
            ):
                eval_driver.prepare(path, f"registry/base@sha256:{digest}")
            self.assertFalse(output.exists())

    def test_report_never_turns_missing_costs_into_verified_zero(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / "offline-test"
            batch_path = directory / "batch.json"
            api_driver.write_json(batch_path, batch_fixture())
            evidence_path = directory / "evidence.json"
            api_driver.write_json(
                evidence_path,
                {
                    "batch_id": "offline-test",
                    "episodes": [],
                    "verification": {"accounting": True},
                },
            )
            with patch.object(eval_driver, "BATCH_ROOT", root):
                result_path = eval_driver.report(batch_path, evidence_path)
            result = json.loads((directory / "results.json").read_text())
            self.assertEqual(result["acceptance"], "unresolved")
            self.assertIn("unresolved (not zero)", result_path.read_text())


class ScheduleTests(unittest.TestCase):
    def test_three_games_have_nine_distinct_variants(self):
        schedule = eval_driver.make_schedule()
        self.assertEqual(
            [(game["id"], game["seed"], game["max_days"]) for game in schedule],
            [("canary", 91001, 1), ("eval-a", 91002, 7), ("eval-b", 91002, 7)],
        )
        for game in schedule:
            self.assertEqual(len(game["policy_keys"]), 9)
            self.assertEqual(set(game["policy_keys"]), set(POLICY_KEYS))
        self.assertEqual(schedule[0]["policy_keys"], POLICY_KEYS)
        self.assertEqual(schedule[1]["policy_keys"], POLICY_KEYS)
        for slot, policy in enumerate(POLICY_KEYS):
            self.assertEqual(schedule[2]["policy_keys"][(slot + 4) % 9], policy)


class RequestTests(unittest.TestCase):
    def test_leagueless_request_is_private_explicit_nine_seat_coworld(self):
        batch = batch_fixture()
        batch.update(submission_mode="leagueless", league_id=None)
        request = eval_driver.make_request(batch, "canary")
        self.assertEqual(request["coworld_id"], batch["coworld_id"])
        self.assertIs(request["private"], True)
        self.assertNotIn("target", request)
        self.assertNotIn("idempotency_key", request)
        self.assertNotIn("llm_routing_override", request)
        self.assertEqual(request["variant_id"], "league")
        self.assertEqual(request["num_episodes"], 1)
        self.assertEqual([row["slot"] for row in request["roster"]], list(range(9)))
        self.assertEqual(
            [row["player"]["policy_ref"] for row in request["roster"]],
            [variant["policy_version_id"] for variant in batch["variants"]],
        )

    def test_leagueless_rejects_original_world_or_accidental_league_target(self):
        for changed in ("original", "league"):
            batch = batch_fixture()
            batch.update(submission_mode="leagueless", league_id=None)
            if changed == "original":
                batch["coworld_id"] = ORIGINAL_WORLD
            else:
                batch["league_id"] = "accidental-target"
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                eval_driver.make_request(batch, "canary")

    def test_private_explicit_league_request_and_same_owner_variants(self):
        batch = batch_fixture()
        request = eval_driver.make_request(batch, "canary")
        self.assertEqual(request["target"], {"league_id": batch["league_id"]})
        self.assertTrue(request["private"])
        self.assertEqual(request["variant_id"], "league")
        self.assertEqual(request["num_episodes"], 1)
        self.assertNotIn("coworld_id", request)
        self.assertNotIn("llm_routing_override", request)
        self.assertEqual(
            request["game_config_overrides"],
            {
                "seed": 91001,
                "maxGames": 1,
                "maxDays": 1,
                "daySeconds": 180,
                "maxTicks": 0,
                "mockReply": "",
            },
        )
        self.assertEqual([row["slot"] for row in request["roster"]], list(range(9)))
        self.assertEqual(
            [row["player"]["policy_ref"] for row in request["roster"]],
            [variant["policy_version_id"] for variant in batch["variants"]],
        )

    def test_stable_distinct_idempotency_keys_and_rotation(self):
        batch = batch_fixture()
        requests = [
            eval_driver.make_request(batch, game)
            for game in ("canary", "eval-a", "eval-b")
        ]
        self.assertEqual(len({request["idempotency_key"] for request in requests}), 3)
        self.assertEqual(
            requests[0], eval_driver.make_request(copy.deepcopy(batch), "canary")
        )
        for slot, row in enumerate(requests[1]["roster"]):
            self.assertEqual(
                requests[2]["roster"][(slot + 4) % 9]["player"], row["player"]
            )
        self.assertEqual(requests[2]["game_config_overrides"]["maxDays"], 7)

    def test_original_world_rejected(self):
        batch = batch_fixture()
        batch["coworld_id"] = ORIGINAL_WORLD
        with self.assertRaises(ValueError):
            eval_driver.make_request(batch, "canary")

    def test_malformed_or_duplicate_rosters_rejected(self):
        mutations = [
            lambda variants: variants.pop(),
            lambda variants: variants.append(copy.deepcopy(variants[0])),
            lambda variants: variants[1].update(key=variants[0]["key"]),
            lambda variants: variants[1].update(
                policy_version_id=variants[0]["policy_version_id"]
            ),
            lambda variants: variants[0].update(policy_version_id="latest"),
        ]
        for mutate in mutations:
            batch = batch_fixture()
            mutate(batch["variants"])
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                eval_driver.make_request(batch, "canary")

    def test_unknown_game_rejected(self):
        with self.assertRaises(ValueError):
            eval_driver.make_request(batch_fixture(), "unplanned-replacement")


class ApiBoundaryTests(unittest.TestCase):
    def test_observatory_url_matches_released_client_prefix(self):
        for server in ("https://softmax.com/api", "https://softmax.com/api/"):
            with httpx.Client(
                base_url=api_driver.observatory_base_url(server)
            ) as client:
                request = client.build_request("GET", "v2/leagues/id")
                self.assertEqual(
                    str(request.url),
                    "https://softmax.com/api/observatory/v2/leagues/id",
                )

    def test_main_uses_saved_auth_and_existing_elevation_header(self):
        with (
            patch(
                "softmax.auth.load_user_token", return_value="test-token"
            ) as load_token,
            patch.object(api_driver.httpx, "Client") as client,
            patch.object(api_driver, "inspect_batch", return_value={"requests": {}}),
            patch("builtins.print"),
        ):
            result = api_driver.main(
                [
                    "inspect",
                    "--batch",
                    "unused/batch.json",
                    "--api-url",
                    "https://softmax.com/api/",
                ]
            )
        self.assertEqual(result, 0)
        load_token.assert_called_once_with(server="https://softmax.com/api")
        self.assertEqual(
            client.call_args.kwargs["base_url"], "https://softmax.com/api/observatory/"
        )
        self.assertEqual(
            client.call_args.kwargs["headers"],
            {"Authorization": "Bearer test-token", "X-Use-Elevated-Privileges": "true"},
        )

    def test_api_help_loads_released_auth_imports(self):
        result = subprocess.run(
            [
                sys.executable,
                str(Path(__file__).resolve().parents[1] / "tools/heartleaf_eval.py"),
                "inspect",
                "--help",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--batch", result.stdout)

    def scope_fixture(self):
        batch = batch_fixture()
        batch["coworld_version"] = "0.1.0"
        batch["game_provenance"] = {
            "game_image": "registry/game@sha256:" + "a" * 64,
            "viewer_bundle": "sha256:" + "b" * 64,
        }
        for index, variant in enumerate(batch["variants"]):
            variant["container_image_id"] = f"img_{index}"
        league = {
            "id": batch["league_id"],
            "public": False,
            "hidden": False,
            "disabled_at": None,
            "rounds_paused_at": "2026-09-08T12:00:00Z",
            "game": {"coworld_id": batch["coworld_id"]},
        }
        world = {
            "id": batch["coworld_id"],
            "name": "heartleaf-eval",
            "version": "0.1.0",
            "manifest": {
                "game": {
                    "runnable": {
                        "image": batch["game_provenance"]["game_image"],
                        "env": {"BEDROCK_MAX_TOKENS": "2048"},
                    },
                    "replay_viewer": {
                        "bundle": batch["game_provenance"]["viewer_bundle"]
                    },
                },
                "variants": [
                    {"id": "league", "game_config": {"players": [{} for _ in range(9)]}}
                ],
            },
        }
        policies = [
            {
                "id": v["policy_version_id"],
                "container_image_id": v["container_image_id"],
            }
            for v in batch["variants"]
        ]
        return batch, league, {"paused": True}, world, policies

    def test_live_scope_accepts_nine_same_owner_variants(self):
        api_driver.validate_scope(*self.scope_fixture())

    def test_timeout_behavior_must_match_frozen_batch(self):
        batch, league, paused, world, policies = self.scope_fixture()
        batch["timeout_as_wait"] = True
        with self.assertRaisesRegex(ValueError, "timeout behavior"):
            api_driver.validate_scope(batch, league, paused, world, policies)
        world["manifest"]["game"]["runnable"]["env"]["HEARTLEAF_TIMEOUT_AS_WAIT"] = (
            "true"
        )
        api_driver.validate_scope(batch, league, paused, world, policies)
        batch["timeout_as_wait"] = False
        with self.assertRaisesRegex(ValueError, "timeout behavior"):
            api_driver.validate_scope(batch, league, paused, world, policies)

    def test_eval_game_revision_preserves_source_provenance(self):
        batch, league, paused, world, policies = self.scope_fixture()
        original = copy.deepcopy(batch["game_provenance"])
        revised = "registry/eval@sha256:" + "c" * 64
        world["manifest"]["game"]["runnable"]["image"] = revised
        with self.assertRaisesRegex(ValueError, "pinned eval game"):
            api_driver.validate_scope(batch, league, paused, world, policies)

        batch["eval_game_image"] = revised
        api_driver.validate_scope(batch, league, paused, world, policies)
        self.assertEqual(batch["game_provenance"], original)
        world["manifest"]["game"]["runnable"]["image"] = original["game_image"]
        with self.assertRaisesRegex(ValueError, "pinned eval game"):
            api_driver.validate_scope(batch, league, paused, world, policies)

    def test_strict_response_policy_and_episode_limit_match_batch(self):
        batch, league, paused, world, policies = self.scope_fixture()
        batch["unusable_as_wait"] = True
        with self.assertRaisesRegex(ValueError, "unusable-response"):
            api_driver.validate_scope(batch, league, paused, world, policies)
        world["manifest"]["game"]["runnable"]["env"]["HEARTLEAF_UNUSABLE_AS_WAIT"] = (
            "true"
        )
        api_driver.validate_scope(batch, league, paused, world, policies)
        batch["episode_timeout_minutes"] = 100
        with self.assertRaisesRegex(ValueError, "episode timeout"):
            api_driver.validate_scope(batch, league, paused, world, policies)
        world["manifest"]["episode_timeout_minutes"] = 100
        api_driver.validate_scope(batch, league, paused, world, policies)

    def test_leagueless_scope_checks_public_seed_paused_without_claiming_privacy(self):
        batch, league, paused, world, policies = self.scope_fixture()
        batch.update(
            submission_mode="leagueless", league_id=None, seed_league_id=league["id"]
        )
        league["public"] = True
        api_driver.validate_scope(batch, league, paused, world, policies)
        for changed in ("unpaused", "wrong_world", "wrong_seed", "target_league"):
            changed_batch = copy.deepcopy(batch)
            changed_league = copy.deepcopy(league)
            changed_paused = copy.deepcopy(paused)
            if changed == "unpaused":
                changed_paused["paused"] = False
            elif changed == "wrong_world":
                changed_league["game"]["coworld_id"] = ORIGINAL_WORLD
            elif changed == "wrong_seed":
                changed_batch["seed_league_id"] = "unrelated-seed"
            else:
                changed_batch["league_id"] = league["id"]
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                api_driver.validate_scope(
                    changed_batch, changed_league, changed_paused, world, policies
                )

    def test_leagueless_no_seed_requires_fresh_catalog_absence(self):
        batch, _, _, world, policies = self.scope_fixture()
        batch.update(submission_mode="leagueless", league_id=None, seed_league_id=None)
        catalog = [{"coworld_name": "unrelated", "league_id": "other"}]
        responses = {
            "v2/coworld-league-seeds": catalog,
            f"v2/coworlds/{batch['coworld_id']}": world,
            "v2/coworlds/heartleaf-eval/budget": {},
        }
        for variant, policy in zip(batch["variants"], policies):
            variant["image_digest"] = "sha256:" + "a" * 64
            responses[f"stats/policy-versions/{policy['id']}"] = policy
            responses[f"v2/container_images/{variant['container_image_id']}"] = {
                "id": variant["container_image_id"],
                "status": "ready",
                "image_digest": variant["image_digest"],
            }
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with patch.object(
                api_driver, "get_json", side_effect=lambda client, path: responses[path]
            ) as get:
                result = api_driver.inspect_scope(batch, directory, Mock())
                self.assertEqual(result["seed_catalog"], [])
                self.assertIsNone(result["seed_league"])
                self.assertIsNone(result["paused"])
                self.assertNotIn("league", result)
                self.assertFalse(
                    any(
                        call.args[1].startswith("v2/leagues/")
                        for call in get.call_args_list
                    )
                )
                catalog.append(
                    {"coworld_name": "heartleaf-eval", "league_id": "new-seed"}
                )
                get.reset_mock()
                with self.assertRaisesRegex(ValueError, "Seed catalog changed"):
                    api_driver.inspect_scope(batch, directory, Mock())
                self.assertEqual(get.call_count, 1)

    def test_live_scope_rejects_public_unpaused_disabled_or_wrong_world(self):
        for changed in (
            "public",
            "hidden",
            "disabled",
            "paused",
            "world",
            "seats",
            "image",
            "game_digest",
            "viewer_digest",
            "version",
            "token_cap",
        ):
            batch, league, paused, world, policies = self.scope_fixture()
            if changed in ("public", "hidden"):
                league[changed] = True
            elif changed == "disabled":
                league["disabled_at"] = "2026-09-08T12:00:00Z"
            elif changed == "paused":
                paused["paused"] = False
            elif changed == "world":
                league["game"]["coworld_id"] = ORIGINAL_WORLD
            elif changed == "seats":
                world["manifest"]["variants"][0]["game_config"]["players"].pop()
            elif changed == "game_digest":
                world["manifest"]["game"]["runnable"]["image"] = "sha256:" + "c" * 64
            elif changed == "viewer_digest":
                world["manifest"]["game"]["replay_viewer"]["bundle"] = (
                    "sha256:" + "c" * 64
                )
            elif changed == "version":
                world["version"] = "0.9.9"
            elif changed == "token_cap":
                world["manifest"]["game"]["runnable"]["env"]["BEDROCK_MAX_TOKENS"] = (
                    "192"
                )
            else:
                policies[0]["container_image_id"] = "img_wrong"
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                api_driver.validate_scope(batch, league, paused, world, policies)

    def test_readback_requires_realized_roster_config_and_world(self):
        batch = batch_fixture()
        body = eval_driver.make_request(batch, "canary")
        detail = {
            "coworld_id": batch["coworld_id"],
            "episode_count": 1,
            "variant_id": "league",
            "requested": {"notes": body["notes"], "num_episodes": 1},
            "episodes": [
                {
                    "coworld_id": batch["coworld_id"],
                    "game_config": copy.deepcopy(body["game_config_overrides"]),
                    "participants": [
                        {
                            "position": row["slot"],
                            "policy_version_id": row["player"]["policy_ref"],
                        }
                        for row in body["roster"]
                    ],
                }
            ],
        }
        api_driver.validate_request_readback(body, detail, batch["coworld_id"])
        detail["episodes"][0]["participants"][1]["position"] = 0
        with self.assertRaises(ValueError):
            api_driver.validate_request_readback(body, detail, batch["coworld_id"])
        detail["episodes"][0]["participants"][1]["position"] = 1
        detail["coworld_id"] = ORIGINAL_WORLD
        with self.assertRaises(ValueError):
            api_driver.validate_request_readback(body, detail, batch["coworld_id"])

    def test_ambiguous_post_retains_identical_intent_without_automatic_retry(self):
        batch = batch_fixture()
        client = Mock()
        client.post.side_effect = httpx.ReadTimeout("simulated timeout")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            path = directory / "batch.json"
            api_driver.write_json(path, batch)
            with (
                patch.dict(sys.modules, {"heartleaf_eval": eval_driver}),
                patch.object(api_driver, "BATCH_ROOT", directory),
                patch.object(api_driver, "validate_setup"),
                patch.object(
                    api_driver, "inspect_batch", return_value={"requests": {}}
                ),
                patch.object(api_driver, "validate_progression"),
            ):
                with self.assertRaisesRegex(ValueError, "uncertain"):
                    api_driver.submit_one(path, "canary", client)
                self.assertEqual(client.post.call_count, 1)
                saved = json.loads(
                    (directory / "requests/canary.intent.json").read_text()
                )
                self.assertEqual(saved, eval_driver.make_request(batch, "canary"))
                self.assertFalse((directory / "requests/canary.response.json").exists())
                with self.assertRaises(ValueError):
                    api_driver.submit_one(path, "eval-a", client)
                self.assertEqual(client.post.call_count, 1)
                with self.assertRaisesRegex(ValueError, "uncertain"):
                    api_driver.submit_one(path, "canary", client)
                self.assertEqual(client.post.call_count, 2)
                self.assertEqual(
                    client.post.call_args_list[0], client.post.call_args_list[1]
                )

    def test_missing_setup_cannot_post(self):
        client = Mock()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "batch.json"
            api_driver.write_json(path, batch_fixture())
            with (
                patch.dict(sys.modules, {"heartleaf_eval": eval_driver}),
                patch.object(api_driver, "BATCH_ROOT", Path(temporary)),
                self.assertRaises(ValueError),
            ):
                api_driver.submit_one(path, "canary", client)
            client.post.assert_not_called()
            client.get.assert_not_called()

    def test_leagueless_setup_requires_routing_evidence_not_private_league_claims(self):
        batch = batch_fixture()
        batch.update(
            submission_mode="leagueless", league_id=None, setup_evidence="setup.json"
        )
        record = {
            "coworld_id": batch["coworld_id"],
            "routing_observed_at": datetime.now(UTC).isoformat(),
            "routing_evidence": "routing.json",
            "routing_settings": {
                "COWORLD_OPENROUTER_ROUTING_ENABLED": True,
                "COWORLD_OPENROUTER_EPISODE_PERCENT": 100,
            },
        }
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            api_driver.write_json(directory / "routing.json", {"reviewed": "fixture"})
            api_driver.write_json(directory / "setup.json", record)
            api_driver.validate_setup(batch, directory)
            for field, value in (
                ("coworld_id", ORIGINAL_WORLD),
                ("routing_observed_at", "2000-01-01T00:00:00Z"),
                ("routing_evidence", "missing.json"),
                ("routing_settings", {}),
            ):
                changed = copy.deepcopy(record)
                changed[field] = value
                api_driver.write_json(directory / "setup.json", changed)
                with self.subTest(field=field), self.assertRaises(ValueError):
                    api_driver.validate_setup(batch, directory)

    def test_leagueless_ambiguous_intent_never_reposts_even_identical_body(self):
        batch = batch_fixture()
        batch.update(submission_mode="leagueless", league_id=None)
        client = Mock()
        client.post.side_effect = httpx.ReadTimeout("simulated timeout")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            path = directory / "batch.json"
            api_driver.write_json(path, batch)
            with (
                patch.dict(sys.modules, {"heartleaf_eval": eval_driver}),
                patch.object(api_driver, "BATCH_ROOT", directory),
                patch.object(api_driver, "validate_setup"),
                patch.object(
                    api_driver, "inspect_batch", return_value={"requests": {}}
                ),
                patch.object(api_driver, "validate_progression"),
            ):
                with self.assertRaises(ValueError):
                    api_driver.submit_one(path, "canary", client)
                self.assertEqual(client.post.call_count, 1)
                saved_path = directory / "requests/canary.intent.json"
                saved = saved_path.read_bytes()
                self.assertEqual(
                    json.loads(saved), eval_driver.make_request(batch, "canary")
                )
                for game_id in ("canary", "canary", "eval-a"):
                    with self.subTest(game_id=game_id), self.assertRaises(ValueError):
                        api_driver.submit_one(path, game_id, client)
                    self.assertEqual(client.post.call_count, 1)
                    self.assertEqual(saved_path.read_bytes(), saved)
                self.assertFalse((directory / "requests/canary.response.json").exists())

    def test_leagueless_recovery_reads_only_and_validates_before_attaching(self):
        batch = batch_fixture()
        batch.update(submission_mode="leagueless", league_id=None)
        body = eval_driver.make_request(batch, "canary")
        detail = {
            "id": "xp-recovered",
            "coworld_id": batch["coworld_id"],
            "episode_count": 1,
            "variant_id": "league",
            "requested": {"notes": body["notes"], "num_episodes": 1},
            "episodes": [
                {
                    "coworld_id": batch["coworld_id"],
                    "game_config": copy.deepcopy(body["game_config_overrides"]),
                    "participants": [
                        {
                            "position": row["slot"],
                            "policy_version_id": row["player"]["policy_ref"],
                        }
                        for row in body["roster"]
                    ],
                }
            ],
        }
        for changed in (None, "roster", "world", "request_id"):
            response = copy.deepcopy(detail)
            if changed == "roster":
                response["episodes"][0]["participants"][0]["policy_version_id"] = str(
                    UUID(int=99)
                )
            elif changed == "world":
                response["coworld_id"] = ORIGINAL_WORLD
            elif changed == "request_id":
                response["id"] = "xp-other"
            client = Mock()
            client.get.return_value.json.return_value = response
            with (
                tempfile.TemporaryDirectory() as temporary,
                self.subTest(changed=changed),
            ):
                directory = Path(temporary)
                path = directory / "batch.json"
                api_driver.write_json(path, batch)
                api_driver.write_json(directory / "requests/canary.intent.json", body)
                with (
                    patch.dict(sys.modules, {"heartleaf_eval": eval_driver}),
                    patch.object(api_driver, "BATCH_ROOT", directory),
                ):
                    if changed:
                        with self.assertRaises(ValueError):
                            api_driver.reconcile_one(
                                path, "canary", "xp-recovered", client
                            )
                        self.assertFalse(
                            (directory / "requests/canary.response.json").exists()
                        )
                    else:
                        recovered = api_driver.reconcile_one(
                            path, "canary", "xp-recovered", client
                        )
                        self.assertEqual(recovered, detail)
                        self.assertEqual(
                            json.loads(
                                (
                                    directory / "requests/canary.response.json"
                                ).read_text()
                            ),
                            detail,
                        )
                client.post.assert_not_called()
                client.get.assert_called_once_with(
                    "v2/experience-requests/xp-recovered"
                )

    def test_redaction_preserves_usage_but_removes_credentials(self):
        result = api_driver.safe_evidence(
            {
                "input_tokens": 100,
                "output_tokens": 30,
                "token": "credential",
                "authorization": "Bearer secret",
                "url": "https://user:password@example.com/replay?signature=secret#key",
            }
        )
        self.assertEqual(result["input_tokens"], 100)
        self.assertEqual(result["output_tokens"], 30)
        self.assertNotIn("token", result)
        self.assertNotIn("authorization", result)
        self.assertEqual(result["url"], "https://example.com/replay")

    def test_submission_rejects_batch_outside_ignored_root(self):
        client = Mock()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "batch.json"
            api_driver.write_json(path, batch_fixture())
            with (
                patch.dict(sys.modules, {"heartleaf_eval": eval_driver}),
                self.assertRaises(ValueError),
            ):
                api_driver.submit_one(path, "canary", client)
            client.post.assert_not_called()
            client.get.assert_not_called()

    def progression_fixture(self, directory):
        batch = batch_fixture()
        batch["budget_evidence"] = "budget.json"
        api_driver.write_json(
            directory / "findings.json", {"reviewed": "offline fixture"}
        )
        budget = {
            "batch_id": batch["batch_id"],
            "accounting_status": "reconciled",
            "setup_cost_usd": 0.5,
            "projected_canary_usd": 0.2,
            "evidence_file": "findings.json",
        }
        api_driver.write_json(directory / "budget.json", budget)
        seats = [
            {
                "slot": slot,
                "policy_version_id": variant["policy_version_id"],
                "served_model": variant["model"],
                "provider": "openrouter",
                "successful_calls": 1,
                "usable_actions": 1,
                "truncations": 0,
            }
            for slot, variant in enumerate(batch["variants"])
        ]
        acceptance = {
            "request_id": "xp-canary",
            "evidence_file": "findings.json",
            "accounting_status": "reconciled",
            "cost_usd": 0.2,
            "projected_next_game_usd": 1.0,
            "seats": seats,
        }
        api_driver.write_json(directory / "acceptance/canary.json", acceptance)
        requests = {
            "canary": {
                "id": "xp-canary",
                "status": "completed",
                "completed_count": 1,
                "episodes": [
                    {
                        "participants": [
                            {
                                "position": seat["slot"],
                                "policy_version_id": seat["policy_version_id"],
                            }
                            for seat in seats
                        ]
                    }
                ],
            }
        }
        return batch, budget, acceptance, requests

    def test_setup_cost_and_canary_projection_enforce_soft_stop(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            batch, budget, _, _ = self.progression_fixture(directory)
            api_driver.validate_progression(batch, directory, "canary", {})
            budget["setup_cost_usd"] = 9.8
            api_driver.write_json(directory / "budget.json", budget)
            with self.assertRaisesRegex(ValueError, "soft stop"):
                api_driver.validate_progression(batch, directory, "canary", {})
            for value in (True, float("nan"), -1):
                budget["setup_cost_usd"] = value
                api_driver.write_json(directory / "budget.json", budget)
                with self.subTest(setup_cost=value), self.assertRaises(ValueError):
                    api_driver.validate_progression(batch, directory, "canary", {})

    def test_progression_uses_frozen_models_after_cohort_revision(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            batch, _, acceptance, requests = self.progression_fixture(directory)
            batch["variants"][1]["model"] = "google/gemini-2.5-flash-lite"
            batch["variants"][2]["model"] = "openai/gpt-oss-120b:nitro"
            with self.assertRaisesRegex(ValueError, "model differs"):
                api_driver.validate_progression(batch, directory, "eval-a", requests)
            acceptance["seats"][1]["served_model"] = "google/gemini-2.5-flash-lite"
            acceptance["seats"][2]["served_model"] = "openai/gpt-oss-120b:nitro"
            api_driver.write_json(directory / "acceptance/canary.json", acceptance)
            api_driver.validate_progression(batch, directory, "eval-a", requests)

    def test_progression_rejects_invalid_counts_and_mismatched_slot_mapping(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            batch, _, acceptance, requests = self.progression_fixture(directory)
            api_driver.validate_progression(batch, directory, "eval-a", requests)
            for field, value in (
                ("successful_calls", True),
                ("successful_calls", float("nan")),
                ("usable_actions", True),
                ("usable_actions", float("nan")),
                ("truncations", False),
                ("slot", False),
            ):
                modified = copy.deepcopy(acceptance)
                modified["seats"][0][field] = value
                api_driver.write_json(directory / "acceptance/canary.json", modified)
                with (
                    self.subTest(field=field, value=value),
                    self.assertRaises(ValueError),
                ):
                    api_driver.validate_progression(
                        batch, directory, "eval-a", requests
                    )
            modified = copy.deepcopy(acceptance)
            modified["seats"][0]["slot"], modified["seats"][1]["slot"] = 1, 0
            api_driver.write_json(directory / "acceptance/canary.json", modified)
            with self.assertRaises(ValueError):
                api_driver.validate_progression(batch, directory, "eval-a", requests)

    def test_missing_accounting_blocks_progression(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            batch, _, _, requests = self.progression_fixture(directory)
            api_driver.write_json(
                directory / "findings.json", {"status": "usage pending"}
            )
            api_driver.write_json(
                directory / "acceptance/canary.json",
                {
                    "request_id": "xp-canary",
                    "evidence_file": "findings.json",
                    "accounting_status": "pending",
                    "cost_usd": None,
                },
            )
            with self.assertRaisesRegex(ValueError, "accounting"):
                api_driver.validate_progression(
                    batch,
                    directory,
                    "eval-a",
                    requests,
                )


class CoverageTests(unittest.TestCase):
    @staticmethod
    def episode(episode_id, game_id="eval-a", status="completed", policy_keys=None):
        return {
            "episode_id": episode_id,
            "game_id": game_id,
            "status": status,
            "policy_keys": POLICY_KEYS if policy_keys is None else policy_keys,
        }

    def test_all_36_pairs_meet_twice_with_same_soul_variants(self):
        episodes = [
            self.episode("ep-a"),
            self.episode(
                "ep-b", "eval-b", policy_keys=POLICY_KEYS[5:] + POLICY_KEYS[:5]
            ),
        ]
        coverage = eval_driver.pair_coverage(episodes)
        self.assertEqual(len(coverage), 36)
        self.assertEqual(set(coverage.values()), {2})
        self.assertEqual(coverage["S1-H|S1-Q"], 2)
        self.assertFalse(
            any(left == right for left, right in (key.split("|") for key in coverage))
        )

    def test_canary_failed_running_and_duplicate_episodes_do_not_inflate(self):
        full = self.episode("ep-a")
        coverage = eval_driver.pair_coverage(
            [
                full,
                copy.deepcopy(full),
                self.episode("canary", "canary"),
                self.episode("failed", status="failed"),
                self.episode("running", status="running"),
            ]
        )
        self.assertEqual(len(coverage), 36)
        self.assertEqual(set(coverage.values()), {1})

    def test_successful_full_episode_requires_complete_unique_roster(self):
        for roster in (POLICY_KEYS[:-1], POLICY_KEYS[:-1] + [POLICY_KEYS[0]]):
            with self.subTest(roster=roster), self.assertRaises(ValueError):
                eval_driver.pair_coverage([self.episode("bad", policy_keys=roster)])


if __name__ == "__main__":
    unittest.main()
