"""Prepare a frozen Heartleaf soul/model cohort and report captured evidence.

This module never downloads or executes a submitted image. Extract reviewed souls
with Docker first; hosted inspection and submission live in heartleaf_eval_api.
All sensitive generated files stay under the repository's ignored tmp directory.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
import re
import sys
from pathlib import Path
from uuid import UUID

ROOT = Path(__file__).resolve().parents[2]
BATCH_ROOT = ROOT / "tmp" / "heartleaf-eval"
ORIGINAL_COWORLD_ID = "cow_f7e8be04-190b-470f-befe-fe98ca1cbcea"
MODEL_HEADERS = {
    "H": "#!us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "Q": "#!qwen/qwen3.5-35b-a3b",
    "G": "#!openai/gpt-oss-120b",
}
MODEL_SLUGS = {
    "H": "anthropic/claude-haiku-4.5",
    "Q": "qwen/qwen3.5-35b-a3b",
    "G": "openai/gpt-oss-120b",
}
POLICY_KEYS = [f"S{rank}-{model}" for rank in range(1, 4) for model in MODEL_HEADERS]


def _soul_parts(raw: bytes) -> tuple[bytes, bytes, bytes]:
    if not raw or len(raw) > 32768:
        raise ValueError("soul must contain 1 to 32768 bytes")
    if b"\0" in raw:
        raise ValueError("soul contains a NUL byte")
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError("soul is not valid UTF-8") from exc
    newline = re.search(rb"\r\n|\r|\n", raw)
    if newline is None:
        raise ValueError("soul has no body after its model header")
    header = raw[: newline.start()]
    body = raw[newline.end() :]
    if not header.startswith(b"#!"):
        raise ValueError("first soul line must start with #!")
    model = header[2:].strip()
    if re.fullmatch(rb"[A-Za-z0-9._:/-]{1,128}", model) is None:
        raise ValueError(
            "soul model id is empty, too long, or contains invalid characters"
        )
    if not body.strip():
        raise ValueError("soul body is empty")
    return header, newline.group(), body


def transform_soul(raw: bytes, model_header: str) -> bytes:
    """Replace only the first line, retaining the separator and raw body bytes."""
    _, separator, body = _soul_parts(raw)
    try:
        header = model_header.encode("ascii")
    except UnicodeEncodeError as exc:
        raise ValueError("replacement header must be ASCII") from exc
    if re.fullmatch(rb"#![A-Za-z0-9._:/-]{1,128}", header) is None:
        raise ValueError("replacement must be one valid #!model-id line")
    result = header + separator + body
    _soul_parts(result)
    return result


def make_schedule() -> list[dict]:
    rotated = POLICY_KEYS[-4:] + POLICY_KEYS[:-4]
    return [
        {
            "id": "canary",
            "seed": 91001,
            "max_days": 1,
            "policy_keys": list(POLICY_KEYS),
        },
        {
            "id": "eval-a",
            "seed": 91002,
            "max_days": 7,
            "policy_keys": list(POLICY_KEYS),
        },
        {"id": "eval-b", "seed": 91002, "max_days": 7, "policy_keys": rotated},
    ]


def _required_text(record: dict, key: str) -> str:
    value = record.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"missing nonempty {key}")
    return value


def _batch_id(value: str) -> str:
    if re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,79}", value) is None:
        raise ValueError(
            "batch_id must be 1-80 lowercase letters, digits, underscores, or hyphens"
        )
    return value


def make_request(batch: dict, game_id: str) -> dict:
    """Build the selected private XP request; live safety checks precede POST."""
    if batch.get("schema", "heartleaf-eval/1") != "heartleaf-eval/1":
        raise ValueError("expanded batches support local preparation only")
    batch_id = _batch_id(_required_text(batch, "batch_id"))
    mode = batch.get("submission_mode", "private-league")
    if mode not in ("private-league", "leagueless"):
        raise ValueError("unknown submission_mode")
    if mode == "leagueless" and batch.get("league_id") is not None:
        raise ValueError("leagueless mode must not have a target league_id")
    league_id = _required_text(batch, "league_id") if mode == "private-league" else None
    coworld_id = _required_text(batch, "coworld_id")
    if coworld_id in {ORIGINAL_COWORLD_ID, batch.get("original_coworld_id")}:
        raise ValueError("refusing to submit to the original Heartleaf Coworld")
    variants = batch.get("variants", [])
    if len(variants) != 9 or {v.get("key") for v in variants} != set(POLICY_KEYS):
        raise ValueError("batch must contain exactly the nine planned policy keys")
    policies = {}
    for variant in variants:
        ref = _required_text(variant, "policy_version_id")
        try:
            policies[variant["key"]] = str(UUID(ref))
        except ValueError as exc:
            raise ValueError("policy_version_id must be an immutable UUID") from exc
    if len(set(policies.values())) != 9:
        raise ValueError("all nine variants must have distinct policy-version UUIDs")
    game = next((game for game in make_schedule() if game["id"] == game_id), None)
    if game is None:
        raise ValueError(f"unknown scheduled game: {game_id}")
    body = {
        "variant_id": "league",
        "private": True,
        "num_episodes": 1,
        "notes": f"heartleaf-eval {batch_id} {game_id}; three souls by three models",
        "game_config_overrides": {
            "seed": game["seed"],
            "maxGames": 1,
            "maxDays": game["max_days"],
            "daySeconds": 180,
            "maxTicks": 0,
            "mockReply": "",
        },
        "roster": [
            {"player": {"policy_ref": policies[key]}, "slot": slot}
            for slot, key in enumerate(game["policy_keys"])
        ],
    }
    if mode == "leagueless":
        body["coworld_id"] = coworld_id
    else:
        body["target"] = {"league_id": league_id}
        body["idempotency_key"] = f"{batch_id}-{game_id}"
    return body


def pair_coverage(episodes: list[dict]) -> dict[str, int]:
    """Count distinct completed full episodes, excluding canaries and failures.

    Records are normalized inspection evidence, not XP request submissions. A
    caller must reconcile their terminal status and roster against hosted results.
    Conflicting records for an episode are rejected instead of choosing a winner.
    """
    counts = {
        "|".join(pair): 0 for pair in itertools.combinations(sorted(POLICY_KEYS), 2)
    }
    seen = {}
    for episode in episodes:
        episode_id = _required_text(episode, "episode_id")
        signature = (
            episode.get("status"),
            episode.get("game_id"),
            tuple(episode.get("policy_keys", [])),
        )
        if episode_id in seen:
            if seen[episode_id] != signature:
                raise ValueError(f"conflicting evidence for episode {episode_id}")
            continue
        seen[episode_id] = signature
        if episode.get("status") != "completed" or episode.get("game_id") not in {
            "eval-a",
            "eval-b",
        }:
            continue
        keys = episode.get("policy_keys", [])
        if len(keys) != 9 or set(keys) != set(POLICY_KEYS):
            raise ValueError(
                "completed full episode must contain the nine distinct policy keys"
            )
        for pair in itertools.combinations(sorted(keys), 2):
            counts["|".join(pair)] += 1
    return counts


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _image_ref(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/-]*@sha256:[0-9a-f]{64}", value) is None:
        raise ValueError(
            "image must be a registry reference pinned with @sha256:<64 lowercase hex digits>"
        )
    return value


def _batch_directory(batch_id: str) -> Path:
    directory = BATCH_ROOT / _batch_id(batch_id)
    if not directory.resolve().is_relative_to(BATCH_ROOT.resolve()):
        raise ValueError("batch artifacts must stay under tmp/heartleaf-eval")
    return directory


def prepare(cohort_path: Path, base_image: str, models_path: Path | None = None) -> Path:
    """Write thin-image contexts and a schedule from reviewed frozen sources."""
    models = [
        {"key": key, "model": MODEL_SLUGS[key], "model_header": header}
        for key, header in MODEL_HEADERS.items()
    ]
    if models_path is not None:
        models = json.loads(models_path.read_text())
        if not isinstance(models, list) or not models:
            raise ValueError("models must be a nonempty list")
        keys, identities = set(), set()
        for model in models:
            if not isinstance(model, dict):
                raise ValueError("each model must be an object")
            key = _required_text(model, "key")
            slug = _required_text(model, "model")
            header = _required_text(model, "model_header")
            if re.fullmatch(r"[A-Z][A-Z0-9]{0,15}", key) is None or key in keys:
                raise ValueError("model keys must be unique uppercase alphanumeric identifiers")
            transform_soul(b"#!original\nbody", header)
            expected_header = MODEL_HEADERS["H"] if slug == MODEL_SLUGS["H"] else "#!" + slug
            if header != expected_header:
                raise ValueError("model_header must match its model (Haiku uses its Bedrock header)")
            identity = slug.removesuffix(":nitro")
            if identity in identities:
                raise ValueError("models must have distinct identities; Nitro is a routing variant")
            keys.add(key)
            identities.add(identity)
    cohort = json.loads(cohort_path.read_text())
    if cohort.get("reviewed") is not True:
        raise ValueError("cohort must be explicitly reviewed before preparation")
    for key in ("captured_at", "league_id", "division_id", "ranking_metric"):
        _required_text(cohort, key)
    base_image = _image_ref(base_image)
    provenance = cohort.get("game_provenance", {})
    for key in ("coworld_id", "version", "game_image", "viewer_bundle"):
        _required_text(provenance, key)
    _image_ref(provenance["game_image"])
    if re.fullmatch(r"sha256:[0-9a-f]{64}", provenance["viewer_bundle"]) is None:
        raise ValueError("viewer_bundle must be its immutable SHA-256 digest")
    sources = cohort.get("sources", [])
    source_count = len(sources)
    if (
        not 1 <= source_count <= 9
        or (models_path is None and source_count != 3)
        or any(type(source.get("rank")) is not int for source in sources)
        or {source.get("rank") for source in sources} != set(range(1, source_count + 1))
    ):
        raise ValueError("cohort must freeze consecutive ranks 1 through 3, or 1 through 9 with --models")
    policy_keys = [f"S{rank}-{model['key']}" for rank in range(1, source_count + 1) for model in models]
    schedule = make_schedule()
    if models_path is not None:
        if __package__:
            from .heartleaf_eval_schedule import covering_schedule
        else:
            from heartleaf_eval_schedule import covering_schedule

        schedule = [
            {"id": f"eval-{index + 1:04d}", "seed": 91002, "max_days": 7, "policy_keys": roster}
            for index, roster in enumerate(covering_schedule(policy_keys))
        ]
    prepared = []
    policy_ids = set()
    for source in sorted(sources, key=lambda item: item["rank"]):
        source = dict(source)
        policy_id = str(UUID(_required_text(source, "policy_version_id")))
        policy_ids.add(policy_id)
        for key in (
            "image_id",
            "image_digest",
            "soul_path",
            "image_ref",
            "container_soul_path",
            "soul_sha256",
        ):
            _required_text(source, key)
        if re.fullmatch(r"sha256:[0-9a-f]{64}", source["image_digest"]) is None:
            raise ValueError("source image_digest must be an immutable SHA-256 digest")
        if _image_ref(source["image_ref"]).split("@", 1)[1] != source["image_digest"]:
            raise ValueError("source image reference does not match its digest")
        soul_path = Path(source["soul_path"])
        if not soul_path.is_absolute():
            soul_path = cohort_path.parent / soul_path
        raw = soul_path.read_bytes()
        if re.fullmatch(r"[0-9a-f]{64}", source["soul_sha256"]) is None:
            raise ValueError(
                "reviewed soul_sha256 must contain 64 lowercase hexadecimal digits"
            )
        if _sha256(raw) != source["soul_sha256"]:
            raise ValueError("source soul differs from its reviewed SHA-256 digest")
        _, _, body = _soul_parts(raw)
        source.update(
            policy_version_id=policy_id,
            soul_sha256=_sha256(raw),
            body_sha256=_sha256(body),
        )
        generated = {
            model["key"]: transform_soul(raw, model["model_header"])
            for model in models
        }
        prepared.append((source, raw, generated))
    if len(policy_ids) != source_count:
        raise ValueError(
            "source cohort must contain distinct policy-version UUIDs"
        )
    batch_id = _batch_id(_required_text(cohort, "batch_id"))
    directory = _batch_directory(batch_id)
    # Do not replace a frozen batch or partially rewrite it during validation.
    directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    batch = {
        "schema": "heartleaf-eval/1" if models_path is None else "heartleaf-eval/2",
        "batch_id": batch_id,
        "original_coworld_id": provenance["coworld_id"],
        "coworld_id": None,
        "league_id": None,
        "cohort": {
            key: cohort[key]
            for key in ("captured_at", "league_id", "division_id", "ranking_metric")
        },
        "game_provenance": provenance,
        "uploader_base_image": base_image,
        "bedrock_max_tokens": 2048,
        "stop_threshold_usd": 10,
        "sources": [],
        "variants": [],
        "schedule": schedule,
        "duplicate_source_bodies": [],
    }
    for source, raw, generated in prepared:
        source_key = f"S{source['rank']}"
        relative_source = f"sources/{source_key}/soul.md"
        source_directory = directory / "sources" / source_key
        source_directory.mkdir(parents=True)
        (directory / relative_source).write_bytes(raw)
        source["soul_path"] = relative_source
        batch["sources"].append(source)
        for model in models:
            variant_raw = generated[model["key"]]
            key = f"{source_key}-{model['key']}"
            context = directory / "variants" / key
            context.mkdir(parents=True)
            (context / "soul.md").write_bytes(variant_raw)
            (context / "Dockerfile").write_text(
                f"FROM {base_image}\nCOPY soul.md /soul.md\n"
                'ENV HEARTLEAF_SOUL_PATH=/soul.md\nENTRYPOINT ["/bin/soul_player"]\n'
            )
            batch["variants"].append(
                {
                    "key": key,
                    "source_rank": source["rank"],
                    "source_policy_version_id": source["policy_version_id"],
                    "model": model["model"],
                    "model_header": model["model_header"],
                    "soul_sha256": _sha256(variant_raw),
                    "body_sha256": source["body_sha256"],
                    "context": f"variants/{key}",
                    "platform": "linux/amd64",
                    "policy_name": f"heartleaf-eval-{batch_id}-{key.lower()}",
                    "policy_version_id": None,
                    "container_image_id": None,
                    "image_digest": None,
                }
            )
    for left, right in itertools.combinations(batch["sources"], 2):
        if left["body_sha256"] == right["body_sha256"]:
            batch["duplicate_source_bodies"].append([left["rank"], right["rank"]])
    path = directory / "batch.json"
    path.write_text(json.dumps(batch, indent=2) + "\n")
    (directory / "friction.md").write_text(
        "# Website and API friction\n\n"
        "Record evidence, operator effort, workaround, risk, and suggested improvement.\n"
    )
    return path


def report(batch_path: Path, evidence_path: Path) -> Path:
    """Summarize captured evidence without inventing missing usage or acceptance."""

    def finite_number(value) -> bool:
        return type(value) in (int, float) and math.isfinite(value)

    def nonnegative_count(value) -> bool:
        return type(value) is int and value >= 0

    batch = json.loads(batch_path.read_text())
    if batch.get("schema", "heartleaf-eval/1") != "heartleaf-eval/1":
        raise ValueError("expanded batches support local preparation only")
    directory = _batch_directory(batch["batch_id"])
    if batch_path.resolve().parent != directory.resolve():
        raise ValueError("batch.json must be inside its ignored batch directory")
    evidence = json.loads(evidence_path.read_text())
    if evidence.get("batch_id") != batch["batch_id"]:
        raise ValueError("evidence belongs to a different batch")
    episodes = evidence.get("episodes", [])
    coverage = pair_coverage(episodes)
    totals = evidence.get("costs", {})
    checks = evidence.get("verification", {})
    required = [
        "provenance",
        "private_requests"
        if batch.get("submission_mode") == "leagueless"
        else "private_league",
        "seed_rounds_paused"
        if batch.get("submission_mode") == "leagueless"
        else "paused_rounds",
        "nine_variants",
        "canary",
        "full_games",
        "routing",
        "accounting",
        "replays",
        "image_visibility",
    ]
    unresolved = [key for key in required if checks.get(key) is not True]
    cost_fields = ("canary_usd", "evaluation_usd", "setup_compute_usd", "total_usd")
    cost_tolerance_usd = 1e-6
    if any(
        not finite_number(totals.get(field)) or totals[field] < 0
        for field in cost_fields
    ):
        unresolved.append("complete_cost_totals")
    elif not math.isclose(
        totals["total_usd"],
        sum(totals[field] for field in cost_fields[:-1]),
        rel_tol=0,
        abs_tol=cost_tolerance_usd,
    ):
        unresolved.append("cost_total_reconciliation")
    policies = {}
    for variant in batch.get("variants", []):
        try:
            policies[variant.get("key")] = str(UUID(variant.get("policy_version_id")))
        except (ValueError, TypeError, AttributeError):
            continue
    if (
        len(batch.get("variants", [])) != 9
        or set(policies) != set(POLICY_KEYS)
        or len(set(policies.values())) != 9
    ):
        unresolved.append("uploaded_policy_identities")
    completed = {
        episode.get("game_id")
        for episode in episodes
        if episode.get("status") == "completed"
    }
    if completed != {"canary", "eval-a", "eval-b"}:
        unresolved.append("three_completed_scheduled_games")
    for episode in episodes:
        if episode.get("status") != "completed":
            continue
        seats = episode.get("seats", [])
        if len(seats) != 9 or {seat.get("policy_key") for seat in seats} != set(
            POLICY_KEYS
        ):
            unresolved.append(f"seat_results:{episode['episode_id']}")
            continue
        slots = [seat.get("slot") for seat in seats]
        roster = episode.get("policy_keys", [])
        if (
            not all(type(slot) is int for slot in slots)
            or set(slots) != set(range(9))
            or not isinstance(roster, list)
            or len(roster) != 9
            or any(roster[seat["slot"]] != seat["policy_key"] for seat in seats)
        ):
            unresolved.append(f"seat_order:{episode['episode_id']}")
            continue
        for seat in seats:
            variant = next(v for v in batch["variants"] if v["key"] == seat["policy_key"])
            try:
                policy_id = str(UUID(seat.get("policy_version_id")))
            except (ValueError, TypeError, AttributeError):
                policy_id = None
            if (
                seat.get("served_model") != variant["model"]
                or seat.get("provider") != "openrouter"
                or policy_id is None
                or policy_id != policies.get(seat["policy_key"])
                or not finite_number(seat.get("score"))
                or not finite_number(seat.get("llm_cost_usd"))
                or seat["llm_cost_usd"] < 0
                or any(
                    not nonnegative_count(seat.get(field))
                    for field in (
                        "successful_calls",
                        "usable_actions",
                        "failed_calls",
                        "truncations",
                        "timeouts",
                        "input_tokens",
                        "output_tokens",
                    )
                )
                or seat["successful_calls"] == 0
                or seat["usable_actions"] == 0
                or seat["truncations"] != 0
            ):
                unresolved.append(
                    f"seat_evidence:{episode['episode_id']}:{seat['policy_key']}"
                )
    if set(coverage.values()) != {2}:
        unresolved.append("all_pairs_m2")
    result = {
        "schema": "heartleaf-eval-results/1",
        "batch_id": batch["batch_id"],
        "coworld_id": batch.get("coworld_id"),
        "league_id": batch.get("league_id"),
        "sources": batch.get("sources", []),
        "variants": batch.get("variants", []),
        "game_provenance": batch.get("game_provenance", {}),
        "schedule": make_schedule(),
        "evidence_file": str(evidence_path.resolve()),
        "episodes": episodes,
        "costs": totals,
        "cost_reconciliation_tolerance_usd": cost_tolerance_usd,
        "pair_coverage": coverage,
        "verification": checks,
        "unresolved": unresolved,
        "acceptance": "unresolved"
        if unresolved
        else "reported verified by supplied evidence",
        "limitations": evidence.get("limitations", []),
    }
    (directory / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    lines = [
        f"# Heartleaf eval: {batch['batch_id']}",
        "",
        f"Acceptance: {result['acceptance']}.",
        "",
        "This report summarizes supplied evidence; it does not independently verify hosted state.",
        "",
        "## Accounting",
        "",
        "Total must equal canary plus evaluation plus setup compute within an absolute tolerance of 0.000001 USD.",
        "",
    ]
    for field in cost_fields:
        value = totals.get(field)
        lines.append(
            f"- {field}: {'unresolved (not zero)' if value is None else value}"
        )
    lines.extend(
        ["", "## Episodes", "", "| Game | Episode | Status |", "| --- | --- | --- |"]
    )
    for episode in episodes:
        values = [
            episode.get(key, "unresolved")
            for key in ("game_id", "episode_id", "status")
        ]
        lines.append(
            "| "
            + " | ".join(
                str(value).replace("|", "\\|").replace("\n", " ") for value in values
            )
            + " |"
        )
    lines.extend(
        [
            "",
            "## Per-seat results",
            "",
            "Missing measurements are unresolved, not zero. Full records, attempts, and artifact links are retained in results.json.",
            "",
            "| Episode | Seat | Policy | Served model | Score | Successful calls | Failed calls | Truncations | Timeouts | Input tokens | Output tokens | LLM USD |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    seat_fields = (
        "slot",
        "policy_key",
        "served_model",
        "score",
        "successful_calls",
        "failed_calls",
        "truncations",
        "timeouts",
        "input_tokens",
        "output_tokens",
        "llm_cost_usd",
    )
    for episode in episodes:
        for seat in episode.get("seats", []):
            values = [episode["episode_id"]] + [
                seat.get(field) for field in seat_fields
            ]
            lines.append(
                "| "
                + " | ".join(
                    "unresolved"
                    if value is None
                    else str(value).replace("|", "\\|").replace("\n", " ")
                    for value in values
                )
                + " |"
            )
    lines.extend(
        [
            "",
            "## Pair coverage",
            "",
            "Only distinct completed full episodes count. Canary and failed episodes are excluded.",
            "",
            "| Policy | " + " | ".join(POLICY_KEYS) + " |",
            "| --- | " + " | ".join(["---"] * 9) + " |",
        ]
    )
    for key in POLICY_KEYS:
        row = [
            "—" if key == other else str(coverage["|".join(sorted([key, other]))])
            for other in POLICY_KEYS
        ]
        lines.append("| " + key + " | " + " | ".join(row) + " |")
    lines.extend(["", "## Remaining checks", ""])
    lines.extend(
        f"- {item}"
        for item in unresolved or ["None reported by the supplied verification record."]
    )
    lines.extend(
        [
            "",
            "## Interpretation and friction",
            "",
            "Two correlated full villages are descriptive evidence, not independent pairwise trials or proof of model superiority.",
            "",
            "See friction.md for operational evidence and workarounds.",
            "",
        ]
    )
    lines.extend(f"- {item}" for item in result["limitations"])
    path = directory / "results.md"
    path.write_text("\n".join(lines) + "\n")
    return path


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] in {"submit-one", "inspect", "reconcile-one"}:
        from heartleaf_eval_api import main as api_main

        return api_main(argv)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser(
        "prepare", help="generate reviewed local soul/model image contexts"
    )
    prep.add_argument("--cohort", type=Path, required=True)
    prep.add_argument("--base-image", required=True)
    prep.add_argument("--models", type=Path, help="explicit model catalog for local expanded preparation")
    summary = commands.add_parser("report", help="summarize saved episode evidence")
    summary.add_argument("--batch", type=Path, required=True)
    summary.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        path = (
            prepare(args.cohort, args.base_image, args.models)
            if args.command == "prepare"
            else report(args.batch, args.evidence)
        )
    except (ValueError, OSError, KeyError, TypeError) as exc:
        parser.error(str(exc))
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
