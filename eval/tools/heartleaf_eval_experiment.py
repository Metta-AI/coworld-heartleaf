"""Configurable Heartleaf experiments using existing hosted APIs.

Start with a prepared and uploaded batch. Freeze parameters with configure, then
run repeatedly to resume. Public replay consent and budget authority are explicit
inputs; this script never publishes policies or changes the game/backend.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import math
import subprocess
import sys
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import httpx

if __package__:
    from . import heartleaf_eval_api as api
    from . import heartleaf_eval_results as results
    from .heartleaf_eval import transform_soul
    from .heartleaf_eval_schedule import count_pairs, covering_schedule
else:
    import heartleaf_eval_api as api
    import heartleaf_eval_results as results
    from heartleaf_eval import transform_soul
    from heartleaf_eval_schedule import count_pairs, covering_schedule

DEFAULTS = {
    "seeds": [91002],
    "meetings": 2,
    "max_days": 7,
    "day_seconds": 180,
    "canary_days": 1,
    "canary_seed": 91001,
    "max_ignored_fraction": 0.0,
    "stop_threshold_usd": 10.0,
    "projected_game_usd": 3.0,
    "projected_canary_usd": 0.8,
    "public_replays_accepted": False,
    "evaluation_mode": "measurement",
    "cost_authorization": "",
    "max_parallel_games": 1,
}


def parameters(value: dict) -> dict:
    if not isinstance(value, dict) or set(value) - set(DEFAULTS):
        raise ValueError("Unknown experiment parameter; see the documented config")
    config = DEFAULTS | value
    if config["evaluation_mode"] not in ("measurement", "strict"):
        raise ValueError("evaluation_mode must be measurement or strict")
    if not isinstance(config["cost_authorization"], str):
        raise TypeError("cost_authorization must be text")
    if (
        config["stop_threshold_usd"] is None
        and not config["cost_authorization"].strip()
    ):
        raise ValueError(
            "Unlimited spending requires explicit recorded cost authorization"
        )
    for key in (
        "meetings",
        "max_days",
        "day_seconds",
        "max_parallel_games",
    ):
        if type(config[key]) is not int or config[key] < 1:
            raise ValueError(f"{key} must be a positive integer")
    if type(config["canary_days"]) is not int or config["canary_days"] < 0:
        raise ValueError("canary_days must be a nonnegative integer; zero skips canaries")
    if config["max_parallel_games"] > 1 and config["stop_threshold_usd"] is not None:
        raise ValueError(
            "Parallel games require explicitly authorized unlimited spending"
        )
    seeds = config["seeds"]
    if (
        not isinstance(seeds, list)
        or not seeds
        or any(type(s) is not int or not 0 <= s < 2**31 for s in seeds)
        or len(set(seeds)) != len(seeds)
    ):
        raise ValueError("seeds must be distinct nonnegative 32-bit integers")
    if type(config["canary_seed"]) is not int or not 0 <= config["canary_seed"] < 2**31:
        raise ValueError("canary_seed must be a nonnegative 32-bit integer")
    for key in (
        "stop_threshold_usd",
        "projected_game_usd",
        "projected_canary_usd",
        "max_ignored_fraction",
    ):
        if key == "stop_threshold_usd" and config[key] is None:
            continue
        if (
            type(config[key]) not in (float, int)
            or not math.isfinite(config[key])
            or config[key] < 0
        ):
            raise ValueError(f"{key} must be finite and nonnegative")
    if any(
        config[key] is not None and config[key] <= 0
        for key in ("stop_threshold_usd", "projected_game_usd", "projected_canary_usd")
    ):
        raise ValueError("Budget and projections must be positive")
    if not 0 <= config["max_ignored_fraction"] <= 1:
        raise ValueError("max_ignored_fraction must be between zero and one")
    if type(config["public_replays_accepted"]) is not bool:
        raise ValueError("public_replays_accepted must be boolean")
    return config


def schedule(keys: list[str], config: dict) -> list[dict]:
    rosters = covering_schedule(keys, config["meetings"])
    # Screen every variant before the full schedule; the last canary is filled
    # with already screened variants when the cohort size is not divisible by 9.
    ordered = sorted(keys)
    canaries = []
    for start in range(0, len(ordered) if config["canary_days"] else 0, 9):
        roster = ordered[start : start + 9]
        roster += [key for key in ordered if key not in roster][: 9 - len(roster)]
        canaries.append(
            {
                "id": f"canary-{len(canaries) + 1:04}",
                "kind": "canary",
                "seed": config["canary_seed"],
                "max_days": config["canary_days"],
                "policy_keys": roster,
            }
        )
    games = list(canaries)
    for seed in config["seeds"]:
        for roster in rosters:
            games.append(
                {
                    "id": f"eval-{len(games) - len(canaries) + 1:04}",
                    "kind": "evaluation",
                    "seed": seed,
                    "max_days": config["max_days"],
                    "policy_keys": roster,
                }
            )
    return games


def fingerprint(value) -> str:
    return hashlib.sha256(
        json.dumps(
            value, sort_keys=True, separators=(",", ":"), allow_nan=False
        ).encode()
    ).hexdigest()


def configure(batch_path: Path, config_path: Path, name: str) -> Path:
    batch_path = api.validate_batch_path(batch_path)
    results.identifier(name)
    config = parameters(api.read_json(config_path))
    batch = api.read_json(batch_path)
    if (
        batch.get("submission_mode") != "leagueless"
        or batch.get("league_id") is not None
    ):
        raise ValueError("Experiment runner requires the dedicated leagueless batch")
    if not batch.get("coworld_id") or batch["coworld_id"] in (
        api.ORIGINAL_COWORLD_ID,
        batch.get("original_coworld_id"),
    ):
        raise ValueError("Pin the separate eval Coworld before configuring")
    variants = batch["variants"]
    keys = [v["key"] for v in variants]
    if len(keys) != len(set(keys)):
        raise ValueError("Duplicate policy keys")
    policies = [str(UUID(v["policy_version_id"])) for v in variants]
    if len(set(policies)) != len(policies):
        raise ValueError("Upload distinct immutable policy versions before configuring")
    source_files = {}
    sources = {source["rank"]: source for source in batch["sources"]}
    for source in batch["sources"]:
        relative = source["soul_path"]
        source_files[relative] = results.digest(
            api.evidence_file(batch_path.parent, relative)
        )
        if source_files[relative] != source["soul_sha256"]:
            raise ValueError("Source soul differs from reviewed hash")
    for v in variants:
        for relative in (v["context"] + "/soul.md", v["context"] + "/Dockerfile"):
            source_files[relative] = results.digest(
                api.evidence_file(batch_path.parent, relative)
            )
        if source_files[v["context"] + "/soul.md"] != v["soul_sha256"]:
            raise ValueError("Prepared soul differs from frozen hash")
        source = sources[v["source_rank"]]
        original = api.evidence_file(
            batch_path.parent, source["soul_path"]
        ).read_bytes()
        if (
            batch_path.parent / v["context"] / "soul.md"
        ).read_bytes() != transform_soul(original, v["model_header"]):
            raise ValueError(
                "Variant must differ from its reviewed source only in the model header"
            )
        if not v.get("container_image_id") or not v.get("image_digest"):
            raise ValueError("Complete private upload receipts before configuring")
    tools_dir = Path(__file__).parent
    code = {
        p.name: results.digest(p) for p in sorted(tools_dir.glob("heartleaf_eval*.py"))
    }
    packages = {
        name: importlib.metadata.version(name)
        for name in ("coworld", "softmax-cli", "httpx")
    }
    frozen = {
        "schema": "heartleaf-experiment/1",
        "name": name,
        "parameters": config,
        "batch": batch,
        "schedule": schedule(keys, config),
        "source_files": source_files,
        "code_sha256": code,
        "packages": packages,
        "git_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=tools_dir, text=True
        ).strip(),
        "created_at": datetime.now(UTC).isoformat(),
    }
    directory = batch_path.parent / "experiments" / name
    directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    # Copy sources as evidence; no dependency on tmp operator scripts survives.
    for relative in source_files:
        results.atomic_bytes(
            directory / "inputs" / relative, (batch_path.parent / relative).read_bytes()
        )
    for filename in code:
        results.atomic_bytes(
            directory / "code" / filename, (tools_dir / filename).read_bytes()
        )
    results.write_json(directory / "experiment.json", frozen)
    results.write_json(directory / "fingerprint.json", {"sha256": fingerprint(frozen)})
    return directory / "experiment.json"


def carry_requests(
    source: dict, directory: Path, target: dict
) -> list[tuple[dict, Path]]:
    """Attach existing requests only when the entire gameplay request is unchanged."""
    attached = []
    old_games = {g["id"]: g for g in source["schedule"]}
    new_games = {g["id"]: g for g in target["schedule"]}
    for intent in sorted((directory / "games").glob("*/intent.json")):
        game_id = intent.parent.name
        response = intent.parent / "response.json"
        if not response.exists():
            raise ValueError("Reconcile ambiguous submission before rescheduling")
        old_body = api.read_json(intent)
        if old_body != request_body(source, old_games[game_id]):
            raise ValueError("Existing intent differs from its frozen experiment")
        if game_id not in new_games:
            raise ValueError("New schedule would drop an existing hosted game")
        game = new_games[game_id]
        game["request_notes"] = old_body["notes"]
        if request_body(target, game) != old_body:
            raise ValueError("New schedule would change an existing hosted game")
        attached.append((game, intent.parent))
    return attached


def reschedule(path: Path, config_path: Path, name: str) -> Path:
    """Create a successor schedule without cancelling or duplicating hosted work."""
    source = load(path)
    config = parameters(api.read_json(config_path))
    if {k: v for k, v in config.items() if k != "meetings"} != {
        k: v for k, v in source["parameters"].items() if k != "meetings"
    }:
        raise ValueError("Reschedule may change only the pair-meeting requirement")
    target = dict(
        source,
        name=name,
        parameters=config,
        schedule=schedule([v["key"] for v in source["batch"]["variants"]], config),
    )
    # Validate all attachments before creating any successor files.
    carry_requests(source, path.parent, target)
    successor = configure(path.parent.parent.parent / "batch.json", config_path, name)
    target = load(successor)
    if target["batch"] != source["batch"]:
        raise ValueError("Batch changed; existing requests cannot be carried over")
    attached = carry_requests(source, path.parent, target)
    target["predecessor"] = {
        "experiment": str(path.resolve()),
        "sha256": fingerprint(source),
        "carried_requests": {
            game["id"]: api.read_json(old_dir / "response.json")["id"]
            for game, old_dir in attached
        },
    }
    results.write_json(successor, target)
    results.write_json(
        successor.parent / "fingerprint.json", {"sha256": fingerprint(target)}
    )
    for game, old_dir in attached:
        new_dir = successor.parent / "games" / game["id"]
        for filename in ("intent.json", "response.json"):
            results.atomic_bytes(new_dir / filename, (old_dir / filename).read_bytes())
    return successor


def load(path: Path) -> dict:
    path = path.resolve()
    if (
        not path.is_relative_to(api.BATCH_ROOT.resolve())
        or path.name != "experiment.json"
    ):
        raise ValueError("experiment.json must be under ignored tmp/heartleaf-eval")
    frozen = api.read_json(path)
    if fingerprint(frozen) != api.read_json(path.parent / "fingerprint.json")["sha256"]:
        raise ValueError("Frozen experiment changed; configure a new experiment")
    if frozen.get("schema") != "heartleaf-experiment/1":
        raise ValueError("Unsupported experiment schema")
    for relative, expected in frozen["source_files"].items():
        if (
            results.digest(api.evidence_file(path.parent / "inputs", relative))
            != expected
        ):
            raise ValueError("Frozen source evidence changed")
    parameters(frozen["parameters"])
    for game_id, request_id in (
        frozen.get("predecessor", {}).get("carried_requests", {}).items()
    ):
        game_dir = path.parent / "games" / game_id
        if (
            not (game_dir / "response.json").exists()
            or api.read_json(game_dir / "response.json")["id"] != request_id
        ):
            raise ValueError(
                "Incomplete request handoff; do not submit replacement games"
            )
        game = next(g for g in frozen["schedule"] if g["id"] == game_id)
        if api.read_json(game_dir / "intent.json") != request_body(frozen, game):
            raise ValueError("Carried request intent differs from frozen schedule")
    return frozen


def request_body(experiment: dict, game: dict) -> dict:
    batch = experiment["batch"]
    variants = {v["key"]: v for v in batch["variants"]}
    return {
        "coworld_id": batch["coworld_id"],
        "variant_id": "league",
        "private": True,
        "num_episodes": 1,
        "notes": game.get(
            "request_notes",
            f"heartleaf-eval {batch['batch_id']} {experiment['name']} {game['id']}; config {fingerprint(experiment)}",
        ),
        "game_config_overrides": {
            "seed": game["seed"],
            "maxGames": 1,
            "maxDays": game["max_days"],
            "daySeconds": experiment["parameters"]["day_seconds"],
            "maxTicks": 0,
            "mockReply": "",
        },
        "roster": [
            {"slot": slot, "player": {"policy_ref": variants[key]["policy_version_id"]}}
            for slot, key in enumerate(game["policy_keys"])
        ],
    }


def latest_records(directory: Path) -> list[dict]:
    records = []
    for pointer in sorted((directory / "games").glob("*/latest.json")):
        reference = api.read_json(pointer)
        relative = reference["generation"]
        generation = api.evidence_file(
            pointer.parent, relative + "/summary.json"
        ).parent
        if results.digest(generation / "summary.json") != reference["summary_sha256"]:
            raise ValueError("Result summary changed after collection")
        record = api.read_json(generation / "summary.json")
        for filename, expected in record["evidence_sha256"].items():
            path = (generation / filename).resolve()
            if (
                not path.is_relative_to(generation.resolve())
                or results.digest(path) != expected
            ):
                raise ValueError("Raw result evidence changed after collection")
        records.append(record)
    return records


def preserve_live_log(job_id: str | None, generation: Path) -> None:
    """Retain full live stdout beside the platform's 10,000-line tail artifact."""
    if job_id is None:
        return
    job_id = results.identifier(job_id)
    capture = api.BATCH_ROOT / "hosted-logs" / (job_id + ".log")
    metadata = capture.with_suffix(".capture.json")
    if not capture.is_file() or not metadata.is_file():
        return
    receipt = api.read_json(metadata)
    if receipt["job_id"] != job_id or receipt["container"] != "game":
        raise ValueError("Live log capture identity mismatch")
    contents = capture.read_bytes()
    if not contents:
        return
    results.game_log(contents.decode("utf-8"))
    if (generation / "logs").exists():
        results.atomic_bytes(
            generation / "platform-logs", (generation / "logs").read_bytes()
        )
    results.atomic_bytes(generation / "logs", contents)
    results.write_json(generation / "live-log-source.json", receipt)


def collect(experiment: dict, game: dict, directory: Path, client, artifacts) -> dict:
    game_dir = directory / "games" / game["id"]
    request_id = results.identifier(api.read_json(game_dir / "response.json")["id"])
    detail = api.get_json(client, "v2/experience-requests/" + request_id)
    api.validate_request_readback(
        request_body(experiment, game), detail, experiment["batch"]["coworld_id"]
    )
    generation = game_dir / ("snapshot-" + uuid4().hex)
    results.snapshot(
        experiment["batch"], game["id"], detail, generation, client, artifacts
    )
    if not experiment["batch"].get("eval_artifact_required"):
        preserve_live_log(detail["episodes"][0].get("job_id"), generation)
    record = results.normalize(
        experiment["batch"],
        game["id"],
        detail,
        generation,
        max_ignored_fraction=experiment["parameters"]["max_ignored_fraction"],
    )
    record["experiment_sha256"] = fingerprint(experiment)
    record["collector_code_sha256"] = {
        p.name: results.digest(p)
        for p in Path(__file__).parent.glob("heartleaf_eval*.py")
    }
    record["kind"] = game["kind"]
    record["evidence_directory"] = str(generation.relative_to(directory))
    record["evidence_sha256"] = {
        str(p.relative_to(generation)): results.digest(p)
        for p in generation.rglob("*")
        if p.is_file()
    }
    results.write_json(generation / "summary.json", record)
    results.write_json(
        game_dir / "latest.json",
        {
            "generation": generation.name,
            "summary_sha256": results.digest(generation / "summary.json"),
        },
    )
    return record


def budget_check(experiment: dict, directory: Path, game: dict, client) -> dict:
    campaign_marker = directory / "campaign-budget.json"
    if campaign_marker.exists():
        import heartleaf_eval_campaign_budget

        campaign = Path(api.read_json(campaign_marker)["campaign"])
        snapshot, _ = heartleaf_eval_campaign_budget.check(client, campaign, launching=True)
        results.write_json(directory / "games" / game["id"] / "budget-readback.json", snapshot)
        return snapshot
    if experiment["parameters"]["stop_threshold_usd"] is None:
        record = {
            "observed_at": datetime.now(UTC).isoformat(),
            "limit_usd": None,
            "authorization": experiment["parameters"]["cost_authorization"],
            "accounting_required_in_results": True,
        }
        results.write_json(
            directory / "games" / game["id"] / "budget-readback.json", record
        )
        return record
    ledger = api.read_json(directory / "budget.json")
    observed = datetime.fromisoformat(ledger["observed_at"].replace("Z", "+00:00"))
    if observed.tzinfo is None or not timedelta(0) <= datetime.now(
        UTC
    ) - observed <= timedelta(minutes=30):
        raise ValueError(
            "Refresh budget.json; reconciliation must be within 30 minutes"
        )
    if ledger.get("experiment_sha256") != fingerprint(experiment):
        raise ValueError("Budget ledger belongs to another experiment")
    api.evidence_file(directory, ledger["evidence_file"])
    for key in ("known_prior_usd", "unresolved_reserve_usd", "authorized_limit_usd"):
        value = ledger.get(key)
        if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
            raise ValueError("Budget values must be finite nonnegative numbers")
    if ledger.get("unresolved_prior_items") and (
        ledger["unresolved_reserve_usd"] <= 0 or not ledger.get("reserve_basis")
    ):
        raise ValueError("Unknown historical costs need an explicit justified reserve")
    records = latest_records(directory)
    if any(r["cost_usd"] is None for r in records):
        raise ValueError(
            "Current experiment accounting is unresolved; collect again before continuing"
        )
    usage = results.query(
        client,
        "SELECT sum(coalesce(estimated_cost_usd,cost_usd)) AS usd FROM usage_records WHERE coworld_name='heartleaf-eval'",
    )
    metered = float(usage[0]["usd"] or 0)
    if not math.isfinite(metered) or metered < 0:
        raise ValueError("Live study spending must be finite and nonnegative")
    known = max(
        metered, ledger["known_prior_usd"] + sum(r["cost_usd"] for r in records)
    )
    config = experiment["parameters"]
    projection = (
        config["projected_canary_usd"]
        if game["kind"] == "canary"
        else config["projected_game_usd"]
    )
    limit = min(config["stop_threshold_usd"], ledger["authorized_limit_usd"])
    record = {
        "observed_at": datetime.now(UTC).isoformat(),
        "metered_usd": metered,
        "known_usd": known,
        "unresolved_reserve_usd": ledger["unresolved_reserve_usd"],
        "projected_next_usd": projection,
        "limit_usd": limit,
        "projected_charged_usd": known + ledger["unresolved_reserve_usd"] + projection,
    }
    results.write_json(
        directory / "games" / game["id"] / "budget-readback.json", record
    )
    if record["projected_charged_usd"] >= limit:
        raise ValueError("Projected spend reaches the authorized soft stop")
    return record


def refresh_routing(batch: dict, directory: Path) -> dict:
    """Read deployed routing settings using the existing Kubernetes identity."""
    deployment = json.loads(
        subprocess.check_output(
            [
                "kubectl",
                "--context",
                "softmax-main",
                "-n",
                "observatory",
                "get",
                "deployment",
                "observatory-backend",
                "-o",
                "json",
            ]
        )
    )
    server = next(
        c
        for c in deployment["spec"]["template"]["spec"]["containers"]
        if c["name"] == "server"
    )
    env = {entry["name"]: entry.get("value") for entry in server["env"]}
    settings = {
        key: env[key]
        for key in (
            "COWORLD_OPENROUTER_ROUTING_ENABLED",
            "COWORLD_OPENROUTER_EPISODE_PERCENT",
        )
    }
    observation = {
        "observed_at": datetime.now(UTC).isoformat(),
        "settings": settings,
        "backend_image": server["image"],
        "sidecar_image": env["BEDROCK_SIDECAR_IMAGE"],
    }
    results.write_json(directory / "routing-readback.json", observation)
    results.write_json(
        directory / "setup-evidence.json",
        {
            "coworld_id": batch["coworld_id"],
            "routing_observed_at": observation["observed_at"],
            "routing_evidence": "routing-readback.json",
            "routing_settings": settings,
        },
    )
    return dict(batch, setup_evidence="setup-evidence.json")


def parallel_game_limit(experiment: dict, directory: Path) -> int:
    """Read the campaign's operational override without changing frozen inputs."""
    config = experiment["parameters"]
    link = directory / "campaign-budget.json"
    if link.exists():
        policy_path = Path(api.read_json(link)["campaign"]) / "execution-policy.json"
        if policy_path.exists():
            policy = api.read_json(policy_path)
            config = parameters(config | {"max_parallel_games": policy["max_parallel_games"]})
    return config.get("max_parallel_games", 1)


def submit(experiment: dict, game: dict, directory: Path, client) -> dict:
    game_dir = directory / "games" / game["id"]
    response_path = game_dir / "response.json"
    body = request_body(experiment, game)
    if response_path.exists():
        return api.read_json(response_path)
    for intent in (directory / "games").glob("*/intent.json"):
        if not (intent.parent / "response.json").exists():
            raise ValueError(
                "Ambiguous submission exists; reconcile its known request ID, never repost"
            )
    config = experiment["parameters"]
    if config["public_replays_accepted"] is not True:
        raise ValueError("Record explicit public replay consent before configuring")
    for name, expected in runner_revision(experiment, directory).items():
        if results.digest(Path(__file__).parent / name) != expected:
            raise ValueError(
                "Runner code changed since configuration; review and configure a new experiment"
            )
    batch = experiment["batch"]
    # Setup evidence is deliberately refreshable, while runtime and roster are frozen.
    live_batch = refresh_routing(batch, game_dir)
    variants = {v["key"]: v for v in batch["variants"]}
    live_batch["variants"] = [variants[key] for key in game["policy_keys"]]
    api.validate_setup(live_batch, game_dir)
    api.inspect_scope(live_batch, game_dir, client)
    from coworld.upload import resolve_coworld_download_id

    if resolve_coworld_download_id("heartleaf-eval") != batch["coworld_id"]:
        raise ValueError("Canonical eval Coworld changed")
    if (
        api.get_json(client, f"v2/coworlds/{batch['coworld_id']}/certification")[
            "state"
        ]
        != "certified"
    ):
        raise ValueError("Pinned eval Coworld is not certified")
    world_id = results.identifier(batch["coworld_id"])
    active = results.query(
        client,
        "SELECT experience_request_id FROM experience_requests WHERE (coworld_id='"
        + world_id
        + "' OR coworld_id IN (SELECT DISTINCT coworld_id FROM usage_records WHERE coworld_name='heartleaf-eval')) AND status NOT IN ('completed','failed','cancelled')",
    )
    owned = {
        api.read_json(p)["id"] for p in (directory / "games").glob("*/response.json")
    }
    if any(row["experience_request_id"] not in owned for row in active):
        raise ValueError("Another Heartleaf eval request is active")
    parallel_limit = parallel_game_limit(experiment, directory)
    if len(active) >= parallel_limit:
        raise ValueError("Experiment concurrency limit reached")
    records = {r["game_id"]: r for r in latest_records(directory)}
    for previous in experiment["schedule"]:
        if previous["id"] == game["id"]:
            break
        if parallel_limit > 1 and (
            game["kind"] == "canary" or previous["kind"] != "canary"
        ):
            continue
        if previous["id"] not in records or not progression_verified(
            experiment, records[previous["id"]]
        ):
            raise ValueError(
                f"Previous game {previous['id']} has not passed the frozen acceptance criteria"
            )
    budget_check(experiment, directory, game, client)
    game_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    api.write_json(game_dir / "intent.json", body, exclusive=True)
    # Leagueless API has no idempotency key. A crash after this point requires
    # GET-only reconciliation, even when the HTTP failure looked like rejection.
    try:
        response = client.post("v2/experience-requests", json=body)
        response.raise_for_status()
        detail = response.json()
        results.identifier(detail["id"])
        results.write_json(response_path, api.safe_evidence(detail))
    except (httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
        raise ValueError(
            "Submission outcome uncertain; intent retained. Reconcile; do not repost"
        ) from exc
    api.validate_request_readback(body, detail, batch["coworld_id"])
    return detail


def reconcile(
    experiment: dict, game: dict, directory: Path, request_id: str, client
) -> None:
    game_dir = directory / "games" / game["id"]
    body = request_body(experiment, game)
    if api.read_json(game_dir / "intent.json") != body:
        raise ValueError("Intent differs from frozen experiment")
    path = game_dir / "response.json"
    if path.exists() and api.read_json(path)["id"] != request_id:
        raise ValueError("Refusing to replace an attached request")
    detail = api.get_json(
        client, "v2/experience-requests/" + results.identifier(request_id)
    )
    if detail.get("id") != request_id:
        raise ValueError("Recovered ID differs")
    api.validate_request_readback(body, detail, experiment["batch"]["coworld_id"])
    results.write_json(path, api.safe_evidence(detail))


def progression_verified(experiment: dict, record: dict) -> bool:
    field = (
        "measurement_verified"
        if experiment["parameters"].get("evaluation_mode", "strict") == "measurement"
        else "acceptance_verified"
    )
    return record.get(field) is True


def runner_revision(experiment: dict, directory: Path) -> dict:
    """A reviewed code revision preserves frozen parameters and request identities."""
    pointer = directory / "runner-revision.json"
    if not pointer.exists():
        return experiment["code_sha256"]
    reference = api.read_json(pointer)
    manifest = api.evidence_file(directory, reference["manifest"])
    if results.digest(manifest) != reference["sha256"]:
        raise ValueError("Runner revision manifest changed")
    revision = api.read_json(manifest)
    if revision["experiment_sha256"] != fingerprint(experiment):
        raise ValueError("Runner revision belongs to another experiment")
    for name, expected in revision["code_sha256"].items():
        if results.digest(api.evidence_file(manifest.parent, name)) != expected:
            raise ValueError("Archived runner revision changed")
    return revision["code_sha256"]


def revise_runner(experiment: dict, directory: Path, reason: str) -> Path:
    if not reason.strip():
        raise ValueError("Record why this runner revision is needed")
    previous = runner_revision(experiment, directory)
    revision_dir = directory / "runner-revisions" / uuid4().hex
    revision_dir.mkdir(parents=True, mode=0o700)
    code = {}
    for source in sorted(Path(__file__).parent.glob("heartleaf_eval*.py")):
        results.atomic_bytes(revision_dir / source.name, source.read_bytes())
        code[source.name] = results.digest(source)
    manifest = revision_dir / "revision.json"
    results.write_json(
        manifest,
        {
            "experiment_sha256": fingerprint(experiment),
            "previous_code_sha256": previous,
            "code_sha256": code,
            "reason": reason,
            "created_at": datetime.now(UTC).isoformat(),
        },
    )
    results.write_json(
        directory / "runner-revision.json",
        {
            "manifest": str(manifest.relative_to(directory)),
            "sha256": results.digest(manifest),
        },
    )
    return manifest


def run_parallel(
    experiment: dict,
    directory: Path,
    client,
    artifacts,
    max_new: int,
    poll_seconds: int,
) -> None:
    """Bounded synchronous polling of independent hosted games; no async runtime."""
    submitted = 0
    terminal = {}
    while True:
        active = []
        pending = []
        retry_pending = False
        for game in experiment["schedule"]:
            if game["id"] in terminal:
                continue
            response = directory / "games" / game["id"] / "response.json"
            if not response.exists():
                pending.append(game)
                continue
            try:
                record = collect(experiment, game, directory, client, artifacts)
            except httpx.HTTPError as exc:
                if not results.transient_read_error(exc):
                    raise
                print(
                    json.dumps(
                        {
                            "game": game["id"],
                            "status": "retrying_read",
                            "error": type(exc).__name__,
                        }
                    ),
                    flush=True,
                )
                active.append(game)
                retry_pending = True
                continue
            print(
                json.dumps(
                    {
                        "game": game["id"],
                        "status": record["status"],
                        "measurement_verified": record["measurement_verified"],
                        "unresolved": record["unresolved"],
                    }
                ),
                flush=True,
            )
            if record["status"] in results.TERMINAL:
                terminal[game["id"]] = record
                publish(experiment, directory)
                if not progression_verified(experiment, record) and max_new > 0:
                    raise ValueError(
                        "Measurement integrity failed; existing hosted requests remain attached for collection"
                    )
            else:
                active.append(game)
        canaries_done = all(
            g["id"] in terminal for g in experiment["schedule"] if g["kind"] == "canary"
        )
        for game in pending:
            if (
                len(active) >= parallel_game_limit(experiment, directory)
                or submitted >= max_new
            ):
                break
            if game["kind"] != "canary" and not canaries_done:
                break
            try:
                detail = submit(experiment, game, directory, client)
            except httpx.HTTPError as exc:
                # submit converts all errors after its durable POST intent into
                # an ambiguity error. Only read-only preflight failures reach here.
                if not results.transient_read_error(exc):
                    raise
                print(
                    json.dumps(
                        {
                            "game": game["id"],
                            "status": "retrying_preflight",
                            "error": type(exc).__name__,
                        }
                    ),
                    flush=True,
                )
                retry_pending = True
                break
            print(
                json.dumps({"submitted": game["id"], "request_id": detail["id"]}),
                flush=True,
            )
            active.append(game)
            submitted += 1
        if not active and not retry_pending:
            break
        time.sleep(max(30, poll_seconds) if retry_pending else poll_seconds)
    print(publish(experiment, directory), flush=True)


def publish(experiment: dict, directory: Path) -> Path:
    records = latest_records(directory)
    destination = results.export(directory / "results", records)
    keys = [v["key"] for v in experiment["batch"]["variants"]]
    by_seed = {}
    for seed in experiment["parameters"]["seeds"]:
        counts = count_pairs(
            keys,
            [
                r["policy_keys"]
                for r in records
                if r.get("kind") == "evaluation"
                and progression_verified(experiment, r)
                and r["game_config"]["seed"] == seed
            ],
        )
        by_seed[str(seed)] = {"|".join(pair): count for pair, count in counts.items()}
    results.write_json(
        directory / "coverage.json",
        {
            "schema": "heartleaf-coverage/1",
            "results_generation": str(destination.relative_to(directory)),
            "planned_games": len(experiment["schedule"]),
            "recorded_games": len(records),
            "required_meetings_per_seed": experiment["parameters"]["meetings"],
            "evaluation_mode": experiment["parameters"].get(
                "evaluation_mode", "strict"
            ),
            "measured_pairs_by_seed": by_seed,
        },
    )
    return destination


def archive(
    batch_path: Path, games: list[str], client=None, artifacts=None
) -> list[dict]:
    """Recompute historical raw evidence without altering the original files."""
    batch_path = api.validate_batch_path(batch_path)
    batch = api.read_json(batch_path)
    records = []
    for game in games:
        results.identifier(game)
        detail = api.read_json(batch_path.parent / "evidence" / (game + ".json"))
        if client is not None:
            detail = api.get_json(
                client, "v2/experience-requests/" + results.identifier(detail["id"])
            )
        intent = api.read_json(batch_path.parent / "requests" / (game + ".intent.json"))
        api.validate_request_readback(intent, detail, batch["coworld_id"])
        raw = batch_path.parent / "hosted" / game
        if client is not None:
            raw = batch_path.parent / "archive-collections" / (game + "-" + uuid4().hex)
            results.snapshot(batch, game, detail, raw, client, artifacts)
            results.write_json(raw / "batch.json", batch)
            results.write_json(raw / "intent.json", intent)
        record = results.normalize(batch, game, detail, raw)
        record["evidence_directory"] = str(raw)
        record["batch_sha256"] = results.digest(batch_path)
        record["evidence_sha256"] = {
            str(p.relative_to(raw)): results.digest(p)
            for p in raw.rglob("*")
            if p.is_file() and p.name not in ("summary.json", "game.log")
        }
        records.append(record)
    return records


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    configure_parser = commands.add_parser(
        "configure", help="Freeze uploaded batch and experimental parameters"
    )
    configure_parser.add_argument("--batch", type=Path, required=True)
    configure_parser.add_argument("--config", type=Path, required=True)
    configure_parser.add_argument("--name", required=True)
    reschedule_parser = commands.add_parser(
        "reschedule",
        help="Create a successor schedule preserving existing hosted requests",
    )
    reschedule_parser.add_argument("--experiment", type=Path, required=True)
    reschedule_parser.add_argument("--config", type=Path, required=True)
    reschedule_parser.add_argument("--name", required=True)
    revision_parser = commands.add_parser(
        "revise-runner",
        help="Archive a reviewed code revision without changing the study or attached requests",
    )
    revision_parser.add_argument("--experiment", type=Path, required=True)
    revision_parser.add_argument("--reason", required=True)
    archive_parser = commands.add_parser(
        "archive", help="Recompute and export prior one-off runs, offline"
    )
    archive_parser.add_argument(
        "--source",
        action="append",
        required=True,
        help="batch.json:game-id (repeatable)",
    )
    archive_parser.add_argument("--output", type=Path, required=True)
    archive_parser.add_argument(
        "--refresh",
        action="store_true",
        help="Recollect existing requests from live APIs; never submit",
    )
    for command in ("run", "collect", "export", "reconcile"):
        sub = commands.add_parser(command)
        sub.add_argument("--experiment", type=Path, required=True)
        if command == "run":
            sub.add_argument("--poll-seconds", type=int, default=20)
            sub.add_argument(
                "--max-new-games",
                type=int,
                default=1,
                help="Bound new submissions this invocation",
            )
        if command == "reconcile":
            sub.add_argument("--game", required=True)
            sub.add_argument("--request-id", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "configure":
            print(configure(args.batch, args.config, args.name))
            return 0
        if args.command == "reschedule":
            with api.batch_lock(api.BATCH_ROOT):
                print(reschedule(args.experiment.resolve(), args.config, args.name))
            return 0
        if args.command == "archive":
            output = args.output.resolve()
            if not output.is_relative_to(api.BATCH_ROOT.resolve()):
                raise ValueError("Output must remain under ignored tmp/heartleaf-eval")
            records = []
            if args.refresh:
                from coworld.api_client import CoworldApiClient
                from softmax.auth import get_api_server, load_user_token

                server = get_api_server()
                token = load_user_token(server=server)
                if not token:
                    raise ValueError(
                        "No saved credential; use project-local softmax login"
                    )
                CoworldApiClient.set_elevated(True)
                with (
                    httpx.Client(
                        base_url=api.observatory_base_url(server),
                        headers={
                            "Authorization": "Bearer " + token,
                            api.ELEVATED_PRIVILEGES_HEADER: "true",
                        },
                        timeout=60,
                    ) as client,
                    CoworldApiClient.from_login(server_url=server) as artifacts,
                ):
                    for source in args.source:
                        path, game = source.rsplit(":", 1)
                        records.extend(archive(Path(path), [game], client, artifacts))
            else:
                for source in args.source:
                    path, game = source.rsplit(":", 1)
                    records.extend(archive(Path(path), [game]))
            print(results.export(output, records))
            return 0
        experiment = load(args.experiment)
        directory = args.experiment.resolve().parent
        if args.command == "revise-runner":
            with api.batch_lock(api.BATCH_ROOT):
                print(revise_runner(experiment, directory, args.reason))
            return 0
        if args.command == "export":
            print(publish(experiment, directory))
            return 0
        if args.command == "run" and (
            not 1 <= args.poll_seconds <= 60 or args.max_new_games < 0
        ):
            raise ValueError(
                "poll-seconds must be 1-60; max-new-games must be nonnegative"
            )
        from coworld.api_client import CoworldApiClient
        from softmax.auth import get_api_server, load_user_token

        server = get_api_server()
        token = load_user_token(server=server)
        if not token:
            raise ValueError("No saved credential; use project-local softmax login")
        CoworldApiClient.set_elevated(True)
        # Shared lock serializes these experiment runners across all local batches.
        with (
            api.batch_lock(api.BATCH_ROOT),
            httpx.Client(
                base_url=api.observatory_base_url(server),
                headers={
                    "Authorization": "Bearer " + token,
                    api.ELEVATED_PRIVILEGES_HEADER: "true",
                },
                timeout=60,
            ) as client,
            CoworldApiClient.from_login(server_url=server) as artifacts,
        ):
            if args.command == "reconcile":
                game = next(
                    (g for g in experiment["schedule"] if g["id"] == args.game), None
                )
                if game is None:
                    raise ValueError("Unknown scheduled game")
                reconcile(experiment, game, directory, args.request_id, client)
                print(json.dumps({"reconciled": args.request_id}))
                return 0
            if args.command == "run":
                run_parallel(
                    experiment,
                    directory,
                    client,
                    artifacts,
                    args.max_new_games,
                    args.poll_seconds,
                )
                return 0
            for game in experiment["schedule"]:
                response = directory / "games" / game["id"] / "response.json"
                if not response.exists():
                    continue
                record = collect(experiment, game, directory, client, artifacts)
                print(
                    json.dumps(
                        {
                            "game": game["id"],
                            "status": record["status"],
                            "cost_usd": record["cost_usd"],
                            "unresolved": record["unresolved"],
                        }
                    ),
                    flush=True,
                )
            print(publish(experiment, directory))
    except KeyboardInterrupt:
        print(
            "Interrupted locally. Hosted requests remain recorded; rerun to collect/resume.",
            file=sys.stderr,
        )
        return 130
    except (ValueError, KeyError, TypeError, OSError, httpx.HTTPError) as exc:
        print(
            "Stopped: "
            + (str(exc) if isinstance(exc, ValueError) else type(exc).__name__),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
