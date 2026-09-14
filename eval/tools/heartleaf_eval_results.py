"""Collect and normalize Heartleaf evidence without submitting an experience.

Raw snapshots are immutable generations. Missing artifacts/accounting remain
explicit; only the last generation pointer is replaced after a complete write.
"""

from __future__ import annotations

import ast
import csv
import hashlib
import io
import json
import math
import os
import re
import statistics
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

import httpx

if __package__:
    from . import heartleaf_eval_api as api
else:
    import heartleaf_eval_api as api

TERMINAL = {"completed", "failed", "cancelled"}


def transient_read_error(exc: httpx.HTTPError) -> bool:
    return isinstance(exc, httpx.TransportError) or (
        isinstance(exc, httpx.HTTPStatusError)
        and exc.response.status_code in (408, 429, 500, 502, 503, 504)
    )


def local_rate_limit_tags(log: str, slot: int, failures: list[dict]) -> list[str]:
    """Identify sidecar rejections that never created a platform call."""
    tags = []
    for event in failures:
        if event.get("slot") != slot or event.get("http_status") != 429:
            continue
        tag = event.get("tag", "")
        if event.get("platform_call_id") or event.get("outcome") != "upstream_error":
            continue
        try:
            body = json.loads(event.get("response_body", ""))
        except (ValueError, TypeError):
            continue
        if not isinstance(body, dict) or body.get("__type") != "ThrottlingException":
            continue
        if not re.fullmatch(r"sidecar request rate limit reached \(\d+ requests/minute\)", body.get("message", "")):
            continue
        requests = re.findall(
            rf"llm request day=[^\n]*?\bnow=([\d.]+)[^\n]*?\btag={re.escape(tag)}\b", log
        )
        replies = re.findall(rf"llm reply day=[^\n]*?\btag={re.escape(tag)}\b", log)
        if (re.fullmatch(rf"{slot}:\d+", tag) and len(requests) == len(replies) == 1
                and sum(f.get("tag") == tag for f in failures) == 1
                and abs(float(requests[0]) - float(event.get("request_started_at", 0))) <= 1):
            tags.append(tag)
    return sorted(tags)


def unreported_requests(
    log: str, slot: int, calls: list[dict], failures: list[dict]
) -> tuple[list[str], list[str]]:
    """Reconcile absent telemetry with final requests or proven client timeouts.

    Each recorded call must map uniquely to a game request by its start time
    (completion timestamp minus latency), within one second for clock skew.
    Counts alone cannot prove which call is missing.
    """
    requests = {
        tag: float(start)
        for start, tag in re.findall(
            rf"llm request day=[^\n]*?\bnow=([\d.]+)[^\n]*?\btag=({slot}:\d+)\b", log
        )
    }
    replied = set(re.findall(rf"llm reply day=[^\n]*?\btag=({slot}:\d+)\b", log))
    matched = set()
    for call in calls:
        if call.get("timestamp") is None or call.get("latency_ms") is None:
            return [], []
        start = (
            datetime.fromisoformat(call["timestamp"]).timestamp()
            - float(call["latency_ms"]) / 1000
        )
        candidates = [tag for tag, stamp in requests.items() if abs(stamp - start) <= 1]
        if len(candidates) != 1 or candidates[0] in matched:
            return [], []
        matched.add(candidates[0])
    missing = set(requests) - matched
    timed_out = []
    for tag in sorted(missing & replied):
        evidence = [f for f in failures if f.get("slot") == slot and f.get("tag") == tag]
        if len(evidence) != 1:
            return [], []
        event = evidence[0]
        if (
            event.get("outcome") != "deadline_exceeded"
            or event.get("http_status") != 0
            or "Timeout was reached" not in event.get("error", "")
            or abs(float(event.get("request_started_at", 0)) - requests[tag]) > 1
        ):
            return [], []
        timed_out.append(tag)
    unfinished = missing - set(timed_out)
    # A client timeout releases the next turn even while the provider may still
    # be working. Only the final unreplied request can lack game-side evidence.
    if unfinished and (
        len(unfinished) != 1
        or requests[next(iter(unfinished))] != max(requests.values())
    ):
        return [], []
    return sorted(unfinished), timed_out


def atomic_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".writing-")
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def write_json(path: Path, value) -> None:
    atomic_bytes(path, (json.dumps(value, indent=2, allow_nan=False) + "\n").encode())


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identifier(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise ValueError("Invalid API identifier")
    return value


def query(client, sql: str, *, paginate: bool = False) -> list[dict]:
    """The SQL API silently caps each response at 1,000 rows.

    Paginated callers must provide a deterministic ORDER BY. Terminal snapshots
    can be recollected as late telemetry arrives; they are observations in time.
    """
    rows = []
    while True:
        statement = sql + f" LIMIT 1000 OFFSET {len(rows)}" if paginate else sql
        response = client.post("sql/query", json={"query": statement})
        response.raise_for_status()
        data = response.json()
        page = [dict(zip(data["columns"], row, strict=True)) for row in data["rows"]]
        rows.extend(page)
        if len(page) < 1000:
            return rows
        if not paginate:
            raise ValueError(
                "SQL result reached the 1000-row cap; use ordered pagination"
            )


def game_log(raw: str) -> str:
    sections = []
    for line in raw.splitlines():
        if line.startswith(("b'", 'b"')):
            decoded = ast.literal_eval(line)
            if isinstance(decoded, bytes):
                decoded = decoded.decode("utf-8")
                if "Heartleaf config:" in decoded:
                    sections.append(decoded)
    if not sections and "Heartleaf config:" in raw:
        sections = [raw]
    if len(sections) != 1:
        raise ValueError("Expected exactly one Heartleaf game log")
    return sections[0]


def evaluation_log(evidence: dict) -> tuple[str, set[int]]:
    """Validate the complete structured results payload before using any events."""
    if evidence["schema"] != "heartleaf-eval-evidence/1":
        raise ValueError("Unknown eval evidence schema")
    events = evidence["events"]
    if evidence["event_count"] != len(events):
        raise ValueError("Eval event count mismatch")
    seats = evidence["accepted_seats"]
    accepted = {seat["slot"] for seat in seats}
    if len(accepted) != len(seats) or any(
        type(s) is not int or not 0 <= s < 9 for s in accepted
    ):
        raise ValueError("Invalid accepted seats")
    lines = []
    for index, event in enumerate(events):
        if (
            event["sequence"] != index
            or event["role"] != "llm"
            or event["seat"] not in accepted
        ):
            raise ValueError("Invalid eval event sequence or seat")
        if not event["text"].startswith("llm ") or "\n" in event["text"]:
            raise ValueError("Invalid eval lifecycle line")
        lines.append(event["gnome"] + ": " + event["text"])
    return "\n".join(lines), accepted


def total(rows: list[dict], field: str) -> dict:
    values = [row.get(field) for row in rows]
    known = [float(value) for value in values if value is not None]
    if any(not math.isfinite(value) or value < 0 for value in known):
        raise ValueError(f"Invalid nonnegative measurement: {field}")
    missing = sum(value is None for value in values)
    return {
        "value": sum(known) if not missing else None,
        "known": sum(known),
        "missing": missing,
    }


def call_metrics(rows: list[dict]) -> dict:
    times = sorted(
        float(row["latency_ms"]) / 1000
        for row in rows
        if row.get("latency_ms") is not None
    )
    if any(not math.isfinite(value) or value < 0 for value in times):
        raise ValueError("Invalid call latency")
    return {
        "calls": len(rows),
        "successful_calls": sum(row.get("ok") is True for row in rows),
        "failed_calls": sum(row.get("ok") is False for row in rows),
        "unknown_outcomes": sum(type(row.get("ok")) is not bool for row in rows),
        "request_rejections": sum(
            row.get("error_type")
            in {
                "upstream_http_400",
                "upstream_http_401",
                "upstream_http_403",
                "upstream_http_404",
            }
            for row in rows
        ),
        "truncations": sum(row.get("finish_reason") == "length" for row in rows),
        "at_or_over_deadline": sum(value >= 20 for value in times),
        "missing_latency": len(rows) - len(times),
        "p50_s": statistics.median(times) if times else None,
        "p95_s": times[math.ceil(len(times) * 0.95) - 1] if times else None,
        "max_s": max(times) if times else None,
        "served_models": sorted({str(row.get("canonical_model")) for row in rows}),
        "upstream_providers": sorted({str(row.get("provider")) for row in rows}),
        "input_tokens": total(rows, "input_tokens"),
        "output_tokens": total(rows, "output_tokens"),
        "reasoning_tokens": total(rows, "reasoning_tokens"),
        "provider_cost_usd": total(rows, "billed_cost_usd"),
        "unreconciled_calls": sum(
            row.get("billed_cost_usd") is None
            or row.get("reconciled_from_broadcast") is not True
            for row in rows
        ),
    }


def normalize(
    batch: dict,
    game_id: str,
    detail: dict,
    directory: Path,
    *,
    max_ignored_fraction: float = 0,
) -> dict:
    """Derive results from raw evidence; never trust an earlier summary's gates."""
    episodes = detail.get("episodes", [])
    if len(episodes) != 1:
        raise ValueError("Expected one realized episode per request")
    episode = episodes[0]
    calls = api.read_json(directory / "calls.json")
    attempts = api.read_json(directory / "attempts.json")
    jobs = api.read_json(directory / "jobs.json")
    if len({row["platform_call_id"] for row in calls}) != len(calls):
        raise ValueError("Duplicate call IDs: provider join is not one-to-one")
    attempt_ids = {str(UUID(row["id"])) for row in attempts}
    if (
        len(attempt_ids) != len(attempts)
        or {str(row["id"]) for row in jobs} != attempt_ids
        or len(jobs) != len(attempts)
    ):
        raise ValueError("Job readback does not cover each attempt exactly once")
    if any(row["job_id"] not in attempt_ids for row in calls):
        raise ValueError("Call does not belong to a realized job attempt")
    if any(str(row.get("slot")) not in {str(i) for i in range(9)} for row in calls):
        raise ValueError("Call has no valid seat attribution")
    variants = {v["policy_version_id"]: v for v in batch["variants"]}
    participants = episode.get("participants", [])
    if len(participants) != 9 or {p["position"] for p in participants} != set(range(9)):
        raise ValueError("Realized roster must have nine distinct positions")
    if len({p["policy_version_id"] for p in participants}) != 9:
        raise ValueError("Realized roster repeats a policy")
    if any(p["policy_version_id"] not in variants for p in participants):
        raise ValueError("Realized policy is absent from frozen cohort")
    problems = []
    artifacts = {}
    for kind in ("logs", "results", "replay"):
        path = directory / kind
        if path.is_file() and path.stat().st_size:
            artifacts[kind] = {
                "path": kind,
                "bytes": path.stat().st_size,
                "sha256": digest(path),
            }
        else:
            problems.append("missing_" + kind)
    log = None
    results = None
    accepted_seats = None
    if "results" in artifacts:
        try:
            results = json.loads((directory / "results").read_text())
            if not isinstance(results, dict):
                results = None
                problems.append("unreadable_results")
        except (ValueError, UnicodeError):
            problems.append("unreadable_results")
    if results is not None and "evaluation" in results:
        try:
            log, accepted_seats = evaluation_log(results["evaluation"])
            # Stdout is optional diagnostic evidence for artifact-enabled games.
            problems = [p for p in problems if p != "missing_logs"]
        except (ValueError, KeyError, TypeError):
            problems.append("unreadable_eval_evidence")
    elif batch.get("eval_artifact_required"):
        problems.append("missing_eval_evidence")
    elif "logs" in artifacts:
        try:
            log = game_log((directory / "logs").read_text())
        except (ValueError, SyntaxError, UnicodeError):
            problems.append("unreadable_game_log")
    failures = []
    if log is not None:
        for line in log.splitlines():
            if "llm failure day=" not in line:
                continue
            try:
                event, _ = json.JSONDecoder().raw_decode(line.split(" event=", 1)[1])
                if (
                    event["schema"] != "heartleaf-call-outcome/1"
                    or event["action"] != "wait"
                ):
                    raise ValueError("Unexpected failure event")
                failures.append(event | {"job_id": episode.get("job_id")})
            except (ValueError, KeyError, IndexError, TypeError):
                problems.append("unreadable_failure_event")
    # Episode artifacts identify the final attempt. Earlier job artifacts are
    # fetched separately when available; retries still require explicit review.
    if len(attempts) != 1:
        problems.append("retried_episode_requires_review")
        if any(
            not (directory / "attempt-artifacts" / job_id / "logs").is_file()
            for job_id in attempt_ids
            if job_id != episode.get("job_id")
        ):
            problems.append("prior_attempt_actions_unavailable")
    final_job = episode.get("job_id")
    if final_job not in attempt_ids:
        problems.append("missing_final_job")
    route_ok = bool(jobs) and all(
        (j.get("llm_routing") or {}).get("provider") == "openrouter" for j in jobs
    )
    if not route_ok:
        problems.append("routing_unverified")
    if (
        detail.get("coworld_id") != batch["coworld_id"]
        or episode.get("coworld_version") != batch["coworld_version"]
    ):
        problems.append("runtime_mismatch")
    privacy = api.read_json(directory / "privacy.json")
    private = (
        len(privacy) == 1
        and privacy[0].get("private") is True
        and privacy[0].get("coworld_id") == batch["coworld_id"]
        and privacy[0].get("league_id") == batch.get("league_id")
    )
    if not private:
        problems.append("privacy_unverified")
    scores = {s["position"]: s["score"] for s in episode.get("participant_scores", [])}
    seats = []
    call_log_complete = log is not None
    for participant in sorted(participants, key=lambda p: p["position"]):
        slot = participant["position"]
        variant = variants[participant["policy_version_id"]]
        rows = [row for row in calls if int(row["slot"]) == slot]
        parsed = ignored = unusable = None
        if log is not None:
            parsed_lines = [
                line
                for line in log.splitlines()
                if re.search(rf"tag={slot}:\d+ outcome=usable\b", line)
            ]
            parsed = len(parsed_lines)
            ignored = sum("ignored=wait" in line for line in parsed_lines)
            unusable = len(
                re.findall(
                    rf"tag={slot}:\d+ outcome=(?:parse|transient|permanent)\b", log
                )
            )
        metrics = call_metrics(rows)
        logged_requests = (
            len(re.findall(rf"llm request day=[^\n]*\btag={slot}:\d+\b", log))
            if log is not None
            else None
        )
        final_calls = sum(row["job_id"] == final_job for row in rows)
        unfinished = []
        unreported_timeouts = []
        local_rejections = local_rate_limit_tags(log, slot, failures) if log is not None else []
        if logged_requests is None or logged_requests - len(local_rejections) != final_calls:
            call_log_complete = False
            if detail.get("status") == "completed" and log is not None:
                unfinished, unreported_timeouts = unreported_requests(
                    "\n".join(line for line in log.splitlines() if not any(
                        re.search(rf"\btag={re.escape(tag)}\b", line) for tag in local_rejections
                    )), slot, [r for r in rows if r["job_id"] == final_job], failures
                )
            if not (unfinished or unreported_timeouts) or (
                logged_requests - final_calls - len(local_rejections) != len(unfinished) + len(unreported_timeouts)
            ):
                problems.append("call_log_count_mismatch")
        seat = {
            "unusable_wait_actions": sum(f["slot"] == slot for f in failures),
            "unreported_in_flight_tags": unfinished,
            "unreported_in_flight_calls": len(unfinished),
            "local_rate_limit_tags": local_rejections,
            "local_rate_limit_rejections": len(local_rejections),
            "unreported_timeout_tags": unreported_timeouts,
            "unreported_timeout_calls": len(unreported_timeouts),
            "slot": slot,
            "policy_key": variant["key"],
            "policy_version_id": variant["policy_version_id"],
            "source_rank": variant["source_rank"],
            "source_policy_version_id": variant["source_policy_version_id"],
            "soul_sha256": variant["soul_sha256"],
            "body_sha256": variant["body_sha256"],
            "expected_model": variant["model"],
            "model_header": variant["model_header"],
            "score": scores.get(slot),
            "parsed_replies": parsed,
            "ignored_actions": ignored,
            "logged_requests": logged_requests,
            "final_job_calls": final_calls,
            "applied_actions": parsed - ignored if parsed is not None else None,
            "unusable_replies": unusable,
            "soul_accepted": (slot in accepted_seats)
            if accepted_seats is not None
            else (f"soul accepted seat={slot} " in log if log is not None else None),
            **metrics,
        }
        names = (
            set(
                re.findall(
                    rf"^(.+?): llm request [^\n]*\btag={slot}:\d+\b", log, re.MULTILINE
                )
            )
            if log is not None
            else set()
        )
        seat["client_timeout_replies"] = (
            sum(
                "Timeout was reached" in line
                and any(line.startswith(name + ": llm error ") for name in names)
                for line in log.splitlines()
            )
            if log is not None
            else None
        )
        seat["timeout_wait_actions"] = (
            sum(
                any(
                    line.startswith(name + ": llm timeout action=wait")
                    for name in names
                )
                for line in log.splitlines()
            )
            if log is not None
            else None
        )
        if accepted_seats is not None:
            missed = sum(
                f["slot"] == slot and f["outcome"] == "deadline_exceeded"
                for f in failures
            )
            seat["client_timeout_replies"] = missed
            seat["timeout_wait_actions"] = missed
        seat["response_checks_passed"] = (
            bool(rows)
            and route_ok
            and seat["soul_accepted"] is True
            and (seat["applied_actions"] or 0) > 0
            and metrics["served_models"] == [variant["model"]]
            and all(
                seat[key] == 0
                for key in (
                    "failed_calls",
                    "unknown_outcomes",
                    "truncations",
                    "at_or_over_deadline",
                    "missing_latency",
                    "unusable_replies",
                )
            )
        )
        seat["deadline_exceeded_calls"] = metrics["at_or_over_deadline"]
        seat["outcome"] = (
            "request_rejected"
            if seat["request_rejections"]
            else "deadline_exceeded"
            if seat["deadline_exceeded_calls"] or seat["client_timeout_replies"]
            else "upstream_error"
            if seat["failed_calls"]
            else "truncated_response"
            if seat["truncations"]
            else "invalid_response"
            if seat["unusable_replies"]
            else "invalid_action"
            if seat["ignored_actions"]
            else "responded"
            if seat["applied_actions"]
            else "no_response_observed"
        )
        if seat["soul_accepted"] is not True:
            problems.append(f"soul_not_accepted_slot_{slot}")
        if metrics["served_models"] != [variant["model"]]:
            problems.append(f"model_unverified_slot_{slot}")
        seats.append(seat)
    measurements = call_metrics(calls)
    compute = total(jobs, "compute_usd")
    if not calls:
        problems.append("missing_calls")
    if any(s["unreported_in_flight_calls"] for s in seats):
        problems.append("in_flight_at_episode_end")
    if any(s["unreported_timeout_calls"] for s in seats):
        problems.append("timeout_call_telemetry_missing")
    if measurements["unreconciled_calls"] or compute["missing"] or not jobs:
        problems.append("unresolved_accounting")
    expected_days = episode.get("game_config", {}).get("maxDays")
    realized_days = results.get("day") if results else None
    reported_day = realized_days
    # Runtime 0.1.9 writes again after the final score screen, when startDay
    # has advanced the counter. Its structured events still identify played days.
    if (
        batch.get("coworld_version") == "0.1.9"
        and batch.get("eval_artifact_required")
        and detail.get("status") == "completed"
        and type(expected_days) is int
        and reported_day == expected_days + 1
        and results is not None
        and "evaluation" in results
        and "unreadable_eval_evidence" not in problems
    ):
        event_days = [event.get("day") for event in results["evaluation"]["events"]]
        if event_days and all(type(day) is int for day in event_days) and max(event_days) == expected_days:
            realized_days = expected_days
    if realized_days != expected_days or realized_days is None:
        problems.append("duration_unverified")
    if not all(seat["score"] is not None for seat in seats):
        problems.append("missing_scores")
    if results and results.get("scores") != [seat["score"] for seat in seats]:
        problems.append("score_readback_mismatch")
    if detail.get("status") != "completed" or episode.get("status") != "completed":
        problems.append("episode_not_completed")
    if not all(seat["response_checks_passed"] for seat in seats):
        problems.append("response_checks_failed")
    if log is not None and "Timeout was reached" in log:
        problems.append("client_timeout")
    ignored_total = (
        sum(s["ignored_actions"] for s in seats) if log is not None else None
    )
    parsed_total = sum(s["parsed_replies"] for s in seats) if log is not None else None
    ignored_fraction = ignored_total / parsed_total if parsed_total else None
    technical = not problems
    if ignored_fraction is None or ignored_fraction > max_ignored_fraction:
        problems.append("ignored_action_threshold")
    performance_or_accounting = {
        "response_checks_failed",
        "client_timeout",
        "ignored_action_threshold",
        "unresolved_accounting",
        "in_flight_at_episode_end",
        "timeout_call_telemetry_missing",
    }
    measurement_problems = [p for p in problems if p not in performance_or_accounting]
    models = []
    for model in sorted({s["expected_model"] for s in seats}):
        members = [s for s in seats if s["expected_model"] == model]
        slots = {s["slot"] for s in members}
        metrics = call_metrics([row for row in calls if int(row["slot"]) in slots])
        aggregate = {
            "model": model,
            **metrics,
            "response_checks_passed": all(s["response_checks_passed"] for s in members),
        }
        for field in (
            "parsed_replies",
            "ignored_actions",
            "applied_actions",
            "unusable_replies",
            "score",
            "client_timeout_replies",
            "timeout_wait_actions",
            "unreported_in_flight_calls",
            "unreported_timeout_calls",
            "local_rate_limit_rejections",
            "unusable_wait_actions",
        ):
            aggregate[field] = (
                sum(s[field] for s in members)
                if all(s[field] is not None for s in members)
                else None
            )
        models.append(aggregate)
    return {
        "schema": "heartleaf-results/1",
        "batch_id": batch["batch_id"],
        "game_id": game_id,
        "request_id": detail["id"],
        "episode_id": episode.get("episode_id"),
        "episode_request_id": episode["id"],
        "job_attempt_ids": sorted(attempt_ids),
        "final_job_id": final_job,
        "status": detail["status"],
        "coworld_id": episode.get("coworld_id"),
        "coworld_version": episode.get("coworld_version"),
        "timeout_as_wait": batch.get("timeout_as_wait", False),
        "unusable_as_wait": batch.get("unusable_as_wait", False),
        "unusable_responses": failures,
        "game_config": episode.get("game_config"),
        "realized_days": realized_days,
        "reported_day": reported_day,
        "created_at": detail.get("created_at"),
        "completed_at": detail.get("completed_at"),
        "game_image": batch.get("eval_game_image"),
        "viewer_bundle": batch["game_provenance"]["viewer_bundle"],
        "policy_keys": [s["policy_key"] for s in seats],
        "seats": seats,
        "models": models,
        "action_scope": "final_job_only",
        "call_scope": "all_job_attempts",
        "parsed_replies": parsed_total,
        "ignored_actions": ignored_total,
        "applied_actions": parsed_total - ignored_total
        if parsed_total is not None
        else None,
        "ignored_fraction": ignored_fraction,
        "max_ignored_fraction": max_ignored_fraction,
        "client_timeouts": log.count("Timeout was reached")
        if log is not None
        else None,
        **measurements,
        "compute_cost_usd": compute,
        "known_cost_usd": measurements["provider_cost_usd"]["known"] + compute["known"],
        "cost_usd": measurements["provider_cost_usd"]["known"] + compute["known"]
        if calls
        and jobs
        and call_log_complete
        and not measurements["unreconciled_calls"]
        and not compute["missing"]
        else None,
        "private_request_verified": private,
        "artifacts": artifacts,
        "technical_screen_passed": technical,
        "acceptance_verified": not problems,
        "measurement_verified": not measurement_problems,
        "measurement_problems": measurement_problems,
        "unresolved": problems,
    }


def snapshot(
    batch: dict, game_id: str, detail: dict, directory: Path, client, artifacts
) -> None:
    """Fetch all attempts and call metadata; artifact failures are durable evidence."""
    write_json(directory / "detail.json", api.safe_evidence(detail))
    write_json(
        directory / "observation.json", {"started_at": datetime.now(UTC).isoformat()}
    )
    episode = detail["episodes"][0]
    episode_id = identifier(episode["id"])
    request_id = identifier(detail["id"])
    attempts = query(
        client,
        "SELECT ea.job_request_id::text AS id FROM episode_request_attempts ea JOIN episode_requests e ON e.id=ea.episode_request_id WHERE e.episode_request_id='"
        + episode_id
        + "'",
    )
    ids = ",".join("'" + str(UUID(a["id"])) + "'" for a in attempts)
    calls = jobs = []
    if ids:
        calls = query(
            client,
            "SELECT a.platform_call_id,a.timestamp,a.request_metadata->>'slot' AS slot,a.request_metadata->>'job_request_id' AS job_id,a.canonical_model,a.ok,a.error_type,a.latency_ms,p.provider,p.input_tokens,p.reasoning_tokens,p.output_tokens,p.finish_reason,p.billed_cost_usd,p.reconciled_from_broadcast FROM llm_attempt_events a LEFT JOIN llm_provider_events p ON p.platform_call_id=a.platform_call_id WHERE a.request_metadata->>'job_request_id' IN ("
            + ids
            + ") ORDER BY a.timestamp,a.platform_call_id",
            paginate=True,
        )
        jobs = query(
            client,
            "SELECT id,status,result->'cost_usd' AS compute_usd,result->'llm_routing' AS llm_routing FROM job_requests WHERE id IN ("
            + ids
            + ")",
        )
    privacy = query(
        client,
        "SELECT request_spec->'private' AS private,league_id,coworld_id FROM experience_requests WHERE experience_request_id='"
        + request_id
        + "'",
    )
    for name, value in (
        ("attempts", attempts),
        ("calls", calls),
        ("jobs", jobs),
        ("privacy", privacy),
    ):
        write_json(directory / (name + ".json"), api.safe_evidence(value))
    errors = {}
    if detail["status"] in TERMINAL:
        for kind in ("logs", "results", "replay"):
            try:
                data = artifacts.get_bytes(
                    f"/v2/episode-requests/{episode_id}/artifacts/{kind}", timeout=60
                )
                atomic_bytes(
                    directory / kind, data.encode() if isinstance(data, str) else data
                )
            except (httpx.HTTPError, RuntimeError) as exc:
                # SDK exception messages may contain signed URLs. Keep only type.
                errors[kind] = type(exc).__name__
                if isinstance(exc, httpx.HTTPError) and transient_read_error(exc):
                    write_json(directory / "artifact-errors.json", errors)
                    raise
        for attempt in attempts:
            job_id = str(UUID(attempt["id"]))
            if job_id == episode.get("job_id"):
                continue
            for kind in ("logs", "results", "replay"):
                relative = f"attempt-artifacts/{job_id}/{kind}"
                try:
                    data = artifacts.get_bytes(
                        f"/jobs/{job_id}/artifacts/{kind}", timeout=60
                    )
                    atomic_bytes(directory / relative, data)
                except (httpx.HTTPError, RuntimeError) as exc:
                    errors[relative] = type(exc).__name__
    write_json(directory / "artifact-errors.json", errors)


def export(directory: Path, records: list[dict]) -> Path:
    """Publish one consistent generation, then atomically point readers to it."""
    identities = [r["episode_request_id"] for r in records]
    if len(set(identities)) != len(identities):
        raise ValueError("Refusing duplicate episodes in results export")
    generation = directory / ("export-" + uuid4().hex)
    generation.mkdir(parents=True, mode=0o700)
    write_json(generation / "episodes.json", records)
    tables = {"episodes": [], "seats": [], "models": [], "failures": []}
    for record in records:
        common = {
            key: record[key]
            for key in (
                "batch_id",
                "game_id",
                "request_id",
                "episode_request_id",
                "episode_id",
                "coworld_id",
                "coworld_version",
            )
        }
        common["game_config"] = record["game_config"]
        common["timeout_as_wait"] = record.get("timeout_as_wait", False)
        common["unusable_as_wait"] = record.get("unusable_as_wait", False)
        tables["episodes"].append(
            {k: v for k, v in record.items() if k not in ("seats", "models")}
        )
        tables["seats"].extend({**common, **seat} for seat in record["seats"])
        tables["models"].extend({**common, **model} for model in record["models"])
        tables["failures"].extend(
            {**common, **event} for event in record.get("unusable_responses", [])
        )
    for name, rows in tables.items():
        if name != "episodes":
            write_json(generation / (name + ".json"), rows)
        stream = io.StringIO(newline="")
        fields = sorted({key for row in rows for key in row})
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    key: json.dumps(value, sort_keys=True, allow_nan=False)
                    if isinstance(value, (dict, list))
                    else value
                    for key, value in row.items()
                }
            )
        atomic_bytes(generation / (name + ".csv"), stream.getvalue().encode())
    write_json(
        generation / "manifest.json",
        {
            "schema": "heartleaf-export/1",
            "created_at": datetime.now(UTC).isoformat(),
            "files": {p.name: digest(p) for p in sorted(generation.iterdir())},
        },
    )
    write_json(directory / "latest.json", {"generation": generation.name})
    return generation
