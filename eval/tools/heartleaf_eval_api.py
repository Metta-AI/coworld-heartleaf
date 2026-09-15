"""Existing-API boundary for the Heartleaf eval driver; never configures the backend.

The batch needs ``setup_evidence`` naming a JSON file inside its directory. This
operator-authored record bridges facts with no supported read API: ``mechanism``
(the supported private-league setup), ``league_id``, ``reconciled_at``,
``reconciliation_evidence`` (a relative raw evidence file), ``routing_observed_at``,
``routing_evidence`` (a relative raw deployment read), and ``routing_settings``
containing the two deployed COWORLD_OPENROUTER settings. Evidence is not permission
to change settings. The operator must inspect it; the driver additionally checks
fresh league visibility, runtime, pause state, policies, settings and budgets.

Explicit ``submission_mode: leagueless`` instead requires a setup record with
``coworld_id`` and the routing evidence/settings above. Its ``seed_league_id``
is inspected only to ensure automatic rounds stay paused; omit it only when the
fresh team-only seed catalog confirms no seed for this Coworld. It is never an XP
target or evidence of private-league access. The private request flag is recorded
in durable intent; the current detail API does not expose it for readback.

For progression, ``acceptance/<game>.json`` records the request ID, a relative
``evidence_file`` with reviewed seat/log/usage findings, nine ``seats`` with slot,
policy_version_id, served_model, provider, successful_calls, usable_actions and
truncations, plus ``cost_usd`` (all attempts), ``projected_next_game_usd`` and
``accounting_status: reconciled``. Missing accounting is never zero spend. These
are operator-reviewed evidence imports, not automatic provider verification.

``budget_evidence`` names another reviewed JSON file with ``batch_id``,
``accounting_status: reconciled``, ``setup_cost_usd`` (including certification),
``projected_canary_usd`` and a relative ``evidence_file``. Even the first canary
requires this record. Setup plus accepted game costs plus the next-game estimate
must remain below $10; this is a driver stop, not a provider spending cap.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import math
import os
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit
from uuid import UUID

import httpx

GAMES = ("canary", "eval-a", "eval-b")
ORIGINAL_COWORLD_ID = "cow_f7e8be04-190b-470f-befe-fe98ca1cbcea"
BATCH_ROOT = Path(__file__).resolve().parents[2] / "tmp" / "heartleaf-eval"
# Existing backend protocol header; the released softmax.auth does not export it.
ELEVATED_PRIVILEGES_HEADER = "X-Use-Elevated-Privileges"


def observatory_base_url(server: str) -> str:
    """Use the same API-root convention as the released CoworldApiClient."""
    return server.rstrip("/") + "/observatory/"


def validate_batch_path(path: Path) -> Path:
    path = Path(path).resolve()
    if not path.is_relative_to(BATCH_ROOT.resolve()) or path.name != "batch.json":
        raise ValueError(
            "batch.json must be inside the ignored tmp/heartleaf-eval directory"
        )
    return path


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


def write_json(path: Path, value: dict, *, exclusive: bool = False) -> None:
    """Persist before network writes; exclusive intents cannot be overwritten."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x" if exclusive else "w") as stream:
        os.chmod(path, 0o600)
        json.dump(value, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    directory_fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def safe_evidence(value):
    """Keep response data, but never retain URL credentials or signed queries."""
    if isinstance(value, dict):
        return {
            key: safe_evidence(item)
            for key, item in value.items()
            if key.lower()
            not in {
                "token",
                "tokens",
                "access_token",
                "refresh_token",
                "session_token",
                "secret",
                "secrets",
                "authorization",
                "password",
                "credentials",
                "aws_secret_access_key",
                "aws_session_token",
                "api_key",
            }
        }
    if isinstance(value, list):
        return [safe_evidence(item) for item in value]
    if isinstance(value, str) and value.startswith(("https://", "http://")):
        parsed = urlsplit(value)
        return urlunsplit(
            (parsed.scheme, parsed.netloc.split("@")[-1], parsed.path, "", "")
        )
    return value


def get_json(client, path: str) -> dict | list:
    response = client.get(path)
    response.raise_for_status()
    return response.json()


def validate_scope(
    batch: dict,
    league: dict | None,
    paused: dict | None,
    world: dict,
    policies: list[dict],
) -> None:
    expected_world = batch["coworld_id"]
    if expected_world in (ORIGINAL_COWORLD_ID, batch.get("original_coworld_id")):
        raise ValueError("Refusing an original-Heartleaf submission")
    leagueless = batch.get("submission_mode") == "leagueless"
    if leagueless:
        if batch.get("league_id") is not None or (league or {}).get("id") != batch.get(
            "seed_league_id"
        ):
            raise ValueError(
                "League-less requests cannot target a league; identify the paused seed separately"
            )
    elif league["id"] != batch["league_id"] or league.get("public") is not False:
        raise ValueError("Target league must be the dedicated private league")
    if league is not None:
        if league.get("hidden") is not False or league.get("disabled_at") is not None:
            raise ValueError("Target league must be enabled and team-readable")
        if (paused or {}).get("paused") is not True or not league.get(
            "rounds_paused_at"
        ):
            raise ValueError("Automatic league rounds must remain paused")
        if league["game"].get("coworld_id") != expected_world:
            raise ValueError(
                "League resolved runtime differs from the pinned eval Coworld"
            )
    if world["id"] != expected_world or world["name"] != "heartleaf-eval":
        raise ValueError("Expected the separate heartleaf-eval Coworld")
    if not batch.get("coworld_version") or world["version"] != batch["coworld_version"]:
        raise ValueError("Eval Coworld version differs from pinned upload")
    provenance = batch["game_provenance"]
    game = world["manifest"]["game"]
    expected_game_image = batch.get("eval_game_image", provenance["game_image"])
    if game["runnable"]["image"].split("@")[-1] != expected_game_image.split("@")[-1]:
        raise ValueError("Game image digest differs from the pinned eval game")
    if game["replay_viewer"]["bundle"] != provenance["viewer_bundle"]:
        raise ValueError("Replay viewer digest differs from the original pinned viewer")
    if str(game["runnable"].get("env", {}).get("BEDROCK_MAX_TOKENS")) != "2048":
        raise ValueError("Expected the shared eval token cap of 2048")
    timeout_as_wait = (
        game["runnable"].get("env", {}).get("HEARTLEAF_TIMEOUT_AS_WAIT", "false")
    )
    expected_timeout_as_wait = (
        "true" if batch.get("timeout_as_wait", False) else "false"
    )
    if timeout_as_wait != expected_timeout_as_wait:
        raise ValueError("Eval timeout behavior differs from the frozen batch")
    unusable_as_wait = (
        game["runnable"].get("env", {}).get("HEARTLEAF_UNUSABLE_AS_WAIT", "false")
    )
    if unusable_as_wait != (
        "true" if batch.get("unusable_as_wait", False) else "false"
    ):
        raise ValueError(
            "Eval unusable-response behavior differs from the frozen batch"
        )
    if (
        batch.get("eval_artifact_required")
        and game["runnable"].get("env", {}).get("HEARTLEAF_EVAL_ARTIFACT") != "true"
    ):
        raise ValueError("Eval runtime must write structured results evidence")
    if (
        batch.get("episode_timeout_minutes") is not None
        and world["manifest"].get("episode_timeout_minutes")
        != batch["episode_timeout_minutes"]
    ):
        raise ValueError("Eval episode timeout differs from the frozen batch")
    variants = [v for v in world["manifest"]["variants"] if v["id"] == "league"]
    if len(variants) != 1 or len(variants[0]["game_config"]["players"]) != 9:
        raise ValueError("The standard league variant must have nine seats")
    expected = [str(UUID(v["policy_version_id"])) for v in batch["variants"]]
    if len(expected) != 9 or len(set(expected)) != 9:
        raise ValueError("Exactly nine distinct uploaded policy UUIDs are required")
    if [p["id"] for p in policies] != expected:
        raise ValueError("Uploaded policy readback does not match the frozen roster")
    for variant, policy in zip(batch["variants"], policies):
        if (
            not variant.get("container_image_id")
            or policy.get("container_image_id") != variant["container_image_id"]
        ):
            raise ValueError(
                "Policy image identity is missing or differs from upload provenance"
            )


def evidence_file(directory: Path, relative: str) -> Path:
    path = (directory / relative).resolve()
    if (
        not path.is_relative_to(directory.resolve())
        or not path.is_file()
        or not path.stat().st_size
    ):
        raise ValueError("Evidence must be a nonempty file inside the batch directory")
    return path


def validate_setup(batch: dict, directory: Path) -> None:
    if not batch.get("setup_evidence"):
        raise ValueError(
            "Setup remains unresolved: supply reviewed setup/routing evidence"
        )
    record = read_json(evidence_file(directory, batch["setup_evidence"]))
    fields = ["routing_observed_at"]
    if batch.get("submission_mode") == "leagueless":
        if record.get("coworld_id") != batch["coworld_id"]:
            raise ValueError("Setup evidence must identify the standalone eval Coworld")
    else:
        if record["league_id"] != batch["league_id"] or not record["mechanism"].strip():
            raise ValueError(
                "Evidence must identify the dedicated league and supported setup mechanism"
            )
        evidence_file(directory, record["reconciliation_evidence"])
        fields.append("reconciled_at")
    evidence_file(directory, record["routing_evidence"])
    now = datetime.now(UTC)
    for field in fields:
        observed = datetime.fromisoformat(record[field].replace("Z", "+00:00"))
        if observed.tzinfo is None or not timedelta(0) <= now - observed <= timedelta(
            minutes=30
        ):
            raise ValueError(
                f"Refresh {field}: evidence must be within the last 30 minutes"
            )
    settings = record["routing_settings"]
    if (
        str(settings.get("COWORLD_OPENROUTER_ROUTING_ENABLED")).lower() != "true"
        or str(settings.get("COWORLD_OPENROUTER_EPISODE_PERCENT")) != "100"
    ):
        raise ValueError(
            "Default OpenRouter routing must still be enabled at 100%; no override is used"
        )


def inspect_scope(batch: dict, directory: Path, client) -> dict:
    league_id = (
        batch.get("seed_league_id")
        if batch.get("submission_mode") == "leagueless"
        else batch["league_id"]
    )
    seeds = None
    if batch.get("submission_mode") == "leagueless":
        seeds = [
            seed
            for seed in get_json(client, "v2/coworld-league-seeds")
            if seed["coworld_name"] == "heartleaf-eval"
        ]
        if (league_id is None and seeds) or (
            league_id is not None
            and (len(seeds) != 1 or seeds[0].get("league_id") != league_id)
        ):
            raise ValueError(
                "Seed catalog changed; reconcile all eval leagues before submission"
            )
    league = get_json(client, f"v2/leagues/{league_id}") if league_id else None
    paused = (
        get_json(client, f"v2/leagues/{league_id}/rounds-paused") if league_id else None
    )
    world = get_json(client, f"v2/coworlds/{batch['coworld_id']}")
    policies = [
        get_json(client, f"stats/policy-versions/{v['policy_version_id']}")
        for v in batch["variants"]
    ]
    validate_scope(batch, league, paused, world, policies)
    images = [
        get_json(client, f"v2/container_images/{v['container_image_id']}")
        for v in batch["variants"]
    ]
    for variant, image in zip(batch["variants"], images):
        if (
            image["id"] != variant["container_image_id"]
            or image.get("status") != "ready"
        ):
            raise ValueError("Submitted image must be the ready uploaded image")
        if image.get("public_image_uri") or image.get("is_coworld_image"):
            raise ValueError(
                "Extracted-soul images must not be public or bundled Coworld images"
            )
        if (
            not variant.get("image_digest")
            or image.get("image_digest") != variant["image_digest"]
        ):
            raise ValueError(
                "Submitted image digest differs from frozen upload provenance"
            )
    result = {
        "observed_at": datetime.now(UTC).isoformat(),
        "seed_league"
        if batch.get("submission_mode") == "leagueless"
        else "league": league,
        "paused": paused,
        "world": world,
        "policies": policies,
        "images": images,
        "league_settings": get_json(client, f"v2/leagues/{league_id}/settings")
        if league_id
        else None,
        "budget": get_json(client, "v2/coworlds/heartleaf-eval/budget"),
    }
    if batch.get("submission_mode") == "leagueless":
        result["seed_catalog"] = seeds
    write_json(directory / "evidence" / "scope.json", safe_evidence(result))
    return result


def validate_request_readback(body: dict, detail: dict, coworld_id: str) -> None:
    if detail.get("coworld_id") != coworld_id or detail.get("episode_count") != 1:
        raise ValueError("Request readback has unexpected runtime or episode count")
    if detail.get("variant_id") != body["variant_id"]:
        raise ValueError("Request variant readback differs")
    # The existing API projects requested to notes/count/human-readable labels;
    # it does not expose private, target, key or the original full request_spec.
    requested = detail.get("requested") or {}
    if requested.get("notes") != body["notes"] or requested.get("num_episodes") != 1:
        raise ValueError("Request purpose/count readback differs")
    episodes = detail.get("episodes", [])
    if len(episodes) != 1 or episodes[0].get("coworld_id") != coworld_id:
        raise ValueError("Expected one child episode on the pinned Coworld")
    episode = episodes[0]
    expected = {seat["slot"]: seat["player"]["policy_ref"] for seat in body["roster"]}
    participants = episode.get("participants", [])
    actual = {seat["position"]: seat.get("policy_version_id") for seat in participants}
    if len(participants) != 9 or actual != expected:
        raise ValueError("Episode UUID seating differs from persisted intent")
    for key, value in body["game_config_overrides"].items():
        if (episode.get("game_config") or {}).get(key) != value:
            raise ValueError(f"Episode config differs in {key}")


def inspect_batch(batch_path: Path, client) -> dict:
    batch_path = validate_batch_path(batch_path)
    batch = read_json(batch_path)
    directory = batch_path.parent
    result = {"scope": inspect_scope(batch, directory, client), "requests": {}}
    for game_id in GAMES:
        response_path = directory / "requests" / f"{game_id}.response.json"
        if response_path.exists():
            request_id = read_json(response_path)["id"]
            detail = get_json(client, f"v2/experience-requests/{request_id}")
            intent = read_json(directory / "requests" / f"{game_id}.intent.json")
            validate_request_readback(intent, detail, batch["coworld_id"])
            result["requests"][game_id] = detail
            write_json(
                directory / "evidence" / f"{game_id}.json", safe_evidence(detail)
            )
    return result


def validate_progression(
    batch: dict, directory: Path, game_id: str, requests: dict
) -> None:
    if not batch.get("budget_evidence"):
        raise ValueError(
            "Reviewed setup accounting and canary projection are required before submission"
        )
    budget = read_json(evidence_file(directory, batch["budget_evidence"]))
    evidence_file(directory, budget["evidence_file"])
    if (
        budget.get("batch_id") != batch["batch_id"]
        or budget.get("accounting_status") != "reconciled"
    ):
        raise ValueError(
            "Setup accounting must be reconciled for this batch; missing spend is not zero"
        )
    values = (budget.get("setup_cost_usd"), budget.get("projected_canary_usd"))
    if any(
        type(v) not in (int, float) or not math.isfinite(v) or v < 0 for v in values
    ):
        raise ValueError(
            "Setup spend and canary projection must be finite nonnegative amounts"
        )
    cost, projected = values
    for previous in GAMES[: GAMES.index(game_id)]:
        detail = requests.get(previous)
        if (
            detail is None
            or detail.get("status") != "completed"
            or detail.get("completed_count") != 1
        ):
            raise ValueError(f"{previous} must finish successfully before progression")
        record = read_json(evidence_file(directory, f"acceptance/{previous}.json"))
        evidence_file(directory, record["evidence_file"])
        if (
            record["request_id"] != detail["id"]
            or record.get("accounting_status") != "reconciled"
        ):
            raise ValueError("Missing or lagging accounting is not zero spend")
        values = (record.get("cost_usd"), record.get("projected_next_game_usd"))
        if any(
            type(v) not in (int, float) or not math.isfinite(v) or v < 0 for v in values
        ):
            raise ValueError(
                "Measured spend and next-game projection must be finite nonnegative amounts"
            )
        cost += values[0]
        projected = values[1]
        seats = record["seats"]
        if (
            len(seats) != 9
            or any(type(s.get("slot")) is not int for s in seats)
            or {s["slot"] for s in seats} != set(range(9))
        ):
            raise ValueError("Acceptance needs all nine distinct seats")
        episodes = detail.get("episodes", [])
        if len(episodes) != 1:
            raise ValueError(
                "Acceptance requires exactly one realized preceding episode"
            )
        participants = episodes[0].get("participants", [])
        realized = {
            seat["position"]: seat.get("policy_version_id") for seat in participants
        }
        if (
            len(participants) != 9
            or {seat["slot"]: seat["policy_version_id"] for seat in seats} != realized
        ):
            raise ValueError(
                "Acceptance slot-to-policy mapping differs from realized preceding episode"
            )
        expected = {v["policy_version_id"]: v["model"] for v in batch["variants"]}
        if {s["policy_version_id"] for s in seats} != set(expected):
            raise ValueError("Acceptance policies differ from frozen cohort")
        for seat in seats:
            if (
                seat["served_model"] != expected[seat["policy_version_id"]]
                or seat["provider"] != "openrouter"
            ):
                raise ValueError("Realized provider/model differs from the experiment")
            if (
                any(
                    type(seat.get(field)) is not int or seat[field] <= 0
                    for field in ("successful_calls", "usable_actions")
                )
                or type(seat.get("truncations")) is not int
                or seat["truncations"] != 0
            ):
                raise ValueError("Canary action/call/truncation gate has not passed")
    if cost + projected >= 10:
        raise ValueError(
            "Projected batch spend reaches the $10 soft stop; request a revised budget"
        )


@contextmanager
def batch_lock(directory: Path):
    with (directory / ".submission.lock").open("a") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ValueError("Another submission is operating on this batch") from exc
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def submit_one(batch_path: Path, game_id: str, client) -> dict:
    if __package__:
        from .heartleaf_eval import make_request
    else:
        from heartleaf_eval import make_request

    batch_path = validate_batch_path(batch_path)
    directory = batch_path.parent
    with batch_lock(directory):
        batch = read_json(batch_path)
        body = make_request(batch, game_id)
        validate_setup(batch, directory)
        state = inspect_batch(batch_path, client)
        existing = state["requests"].get(game_id)
        if existing:
            return existing
        if any(
            r.get("status") not in ("completed", "failed", "cancelled")
            for r in state["requests"].values()
        ):
            raise ValueError("One batch request is still active")
        for other in GAMES:
            if (
                (other != game_id or batch.get("submission_mode") == "leagueless")
                and (directory / "requests" / f"{other}.intent.json").exists()
                and other not in state["requests"]
            ):
                raise ValueError(
                    f"Reconcile ambiguous {other} intent before submission; do not repost league-less requests"
                )
        validate_progression(batch, directory, game_id, state["requests"])
        intent_path = directory / "requests" / f"{game_id}.intent.json"
        if intent_path.exists():
            if read_json(intent_path) != body:
                raise ValueError(
                    "Persisted request intent changed; never reuse a key with a different body"
                )
        else:
            write_json(intent_path, body, exclusive=True)
        # No automatic retry. Only league-targeted requests have backend dedup;
        # league-less intents without responses must be recovered using GET.
        try:
            response = client.post("v2/experience-requests", json=body)
            response.raise_for_status()
            detail = response.json()
            if not isinstance(detail, dict) or not detail.get("id"):
                raise ValueError("Create response did not contain a durable request ID")
        except (httpx.HTTPError, ValueError) as exc:
            raise ValueError(
                "Submission outcome uncertain; intent retained. Reconcile by a known request ID; do not repost"
            ) from exc
        write_json(
            directory / "requests" / f"{game_id}.response.json", safe_evidence(detail)
        )
        validate_request_readback(body, detail, batch["coworld_id"])
        return detail


def reconcile_one(batch_path: Path, game_id: str, request_id: str, client) -> dict:
    """Attach a recovered request using GET only; never replay a POST."""
    if __package__:
        from .heartleaf_eval import make_request
    else:
        from heartleaf_eval import make_request

    batch_path = validate_batch_path(batch_path)
    directory = batch_path.parent
    with batch_lock(directory):
        batch = read_json(batch_path)
        intent = read_json(directory / "requests" / f"{game_id}.intent.json")
        if intent != make_request(batch, game_id):
            raise ValueError("Persisted request intent differs from the frozen batch")
        response_path = directory / "requests" / f"{game_id}.response.json"
        if response_path.exists() and read_json(response_path)["id"] != request_id:
            raise ValueError("Refusing to replace an already attached request")
        # Request IDs are opaque API identifiers, but must remain one path segment.
        if not request_id or any(
            c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
            for c in request_id
        ):
            raise ValueError("Invalid request ID")
        detail = get_json(client, f"v2/experience-requests/{request_id}")
        if detail.get("id") != request_id:
            raise ValueError("Recovered request ID differs from readback")
        validate_request_readback(intent, detail, batch["coworld_id"])
        write_json(response_path, safe_evidence(detail))
        return detail


def main(argv: list[str] | None = None) -> int:
    from softmax.auth import get_api_server, load_user_token

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("submit-one", "inspect", "reconcile-one"))
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--game", choices=GAMES)
    parser.add_argument("--request-id")
    parser.add_argument("--api-url", default=get_api_server())
    args = parser.parse_args(argv)
    if args.command in ("submit-one", "reconcile-one") and args.game is None:
        parser.error(f"{args.command} requires --game")
    if args.command == "reconcile-one" and not args.request_id:
        parser.error("reconcile-one requires --request-id")
    server = args.api_url.rstrip("/")
    token = load_user_token(server=server)
    if not token:
        parser.error("No saved user credential for this API server; use softmax login")
    headers = {"Authorization": f"Bearer {token}", ELEVATED_PRIVILEGES_HEADER: "true"}
    try:
        with httpx.Client(
            base_url=observatory_base_url(server),
            headers=headers,
            timeout=60,
            follow_redirects=False,
        ) as client:
            if args.command in ("submit-one", "reconcile-one"):
                detail = (
                    submit_one(args.batch, args.game, client)
                    if args.command == "submit-one"
                    else reconcile_one(args.batch, args.game, args.request_id, client)
                )
                print(json.dumps({"id": detail["id"], "status": detail["status"]}))
            else:
                state = inspect_batch(args.batch, client)
                print(
                    json.dumps(
                        {
                            game: {"id": item["id"], "status": item["status"]}
                            for game, item in state["requests"].items()
                        }
                    )
                )
    except (ValueError, KeyError, OSError, httpx.HTTPError) as exc:
        # HTTP errors can embed credential-bearing URLs; never echo responses.
        print(
            f"Stopped: {str(exc) if isinstance(exc, ValueError) else type(exc).__name__}"
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
