"""Export complete private capture-v1 candidates; independent review owns admission."""

import argparse
import hashlib
import json
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, JsonValue


class Attempt(BaseModel):
    model_config = ConfigDict(extra="forbid")
    attempt_id: str
    policy: str
    origin: Literal["model", "unknown"]
    prompt: JsonValue
    request: JsonValue
    response: str | None
    raw_response: str | None
    http_status: int | None
    platform_call_id: str | None
    provider_request_id: str | None
    stop_reason: str | None
    parsed_action: JsonValue
    accepted: bool
    rejection_reason: str | None


class Decision(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schema_version: Literal["1"] = "1"
    event_type: Literal["decision"] = "decision"
    episode_id: str
    decision_id: str
    decision_index: int
    game: Literal["heartleaf"] = "heartleaf"
    game_version: str
    source_revision: str
    seat: str
    visibility: Literal["private"] = "private"
    observation: JsonValue
    prompt: JsonValue
    attempts: list[Attempt]
    selected_attempt_id: str | None
    executed_action: JsonValue
    action_status: Literal["accepted", "fallback"]
    fallback_origin: str | None
    terminal: bool = False


class Episode(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schema_version: Literal["1"] = "1"
    event_type: Literal["episode"] = "episode"
    episode_id: str
    seed_family: str
    game: Literal["heartleaf"] = "heartleaf"
    game_version: str
    source_revision: str
    status: Literal["completed"] = "completed"
    outcome: JsonValue
    participant_outcomes: JsonValue


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def export(runs: Path, output: Path) -> dict:
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    sources = []
    with (output / "trajectories.jsonl").open("x") as destination:
        (output / "trajectories.jsonl").chmod(0o600)
        for run in sorted(path for path in runs.iterdir() if path.is_dir()):
            capture_bytes = (run / "capture.json").read_bytes()
            capture = json.loads(capture_bytes)
            assert capture["schema"] == "heartleaf-private-capture/1"
            assert not capture["source_dirty"], "candidate source must be committed"
            revision = capture["source_revision"]
            assert len(revision) == 40 and all(
                c in "0123456789abcdef" for c in revision
            )
            config = capture["config"]
            assert config["maxGames"] == 1 and config["maxDays"] == 7
            assert config["promptVariant"] not in (
                "heldout-briefing",
                "heldout-reference",
            )
            assert config["promptSeed"] >= 0
            results = json.loads((run / "results.json").read_text())
            completed = json.loads((run / "completed.json").read_text())
            assert completed == {"seed": config["seed"], "scores": results["scores"]}
            assert results["day"] == 8, "all seven days must finish"
            evaluation = results["evaluation"]
            assert evaluation["schema"] == "heartleaf-eval-evidence/1"
            assert evaluation["event_count"] == len(evaluation["events"])
            assert [event["sequence"] for event in evaluation["events"]] == list(
                range(evaluation["event_count"])
            )
            seats = {entry["slot"] for entry in evaluation["accepted_seats"]}
            assert seats == set(range(len(results["scores"])))
            assert len(list(run.glob("seat*.jsonl"))) == len(seats)
            episode_id = "heartleaf-" + digest(capture_bytes)
            version = "source-" + revision
            decisions = []
            transcript_digests = {}
            unresolved = {}
            for seat in sorted(seats):
                path = run / f"seat{seat}.jsonl"
                raw = path.read_bytes()
                transcript_digests[path.name] = digest(raw)
                rows = [json.loads(line) for line in raw.decode().splitlines()]
                assert all(
                    row["game"] == 1
                    and row["seat"] == seat
                    and row["sequence"] == index
                    for index, row in enumerate(rows)
                )
                requests, transports, responses = {}, {}, {}
                pending, abandoned = [], set()
                for row in rows:
                    role = row["role"]
                    if role in ("system", "user", "assistant"):
                        continue
                    evidence = json.loads(row["text"])
                    tag = evidence["tag"]
                    if role == "request":
                        assert tag not in requests
                        messages = evidence["messages"]
                        metadata = evidence["prompt_template"]
                        assert (
                            messages[0]["role"] == "system"
                            and messages[-1]["role"] == "user"
                        )
                        assert metadata["bank"] == "heartleaf-rules-v1"
                        assert (
                            metadata["selection"] == config["promptVariant"]
                            and metadata["seed"] == config["promptSeed"]
                        )
                        variants = (
                            "canonical",
                            "plain",
                            "numbered",
                            "questions",
                            "reordered",
                        )
                        expected = (
                            variants[config["promptSeed"] % 5]
                            if config["promptVariant"] == "mixed"
                            else config["promptVariant"]
                        )
                        assert metadata["variant"] == expected
                        for message_role, message in (
                            ("system", messages[0]),
                            ("user", messages[-1]),
                        ):
                            assert metadata[message_role + "_sha256"] == digest(
                                message["content"].encode()
                            )
                        if "messages_sha256" in metadata:
                            digest_state = hashlib.sha256()
                            for message in messages:
                                for field in ("role", "content"):
                                    encoded = message[field].encode()
                                    digest_state.update(
                                        str(len(encoded)).encode() + b":" + encoded
                                    )
                            assert (
                                digest_state.hexdigest() == metadata["messages_sha256"]
                            )
                        requests[tag] = evidence
                        pending.append(tag)
                    elif role == "transport":
                        assert tag in requests and tag not in transports
                        transports[tag] = evidence
                    elif role == "response":
                        assert tag in requests and tag not in responses
                        responses[tag] = evidence
                    elif role == "abandoned":
                        assert tag in pending
                        abandoned.add(tag)
                    elif role == "applied":
                        assert (
                            tag in pending and tag in responses and tag not in abandoned
                        )
                        attempts = []
                        for attempt_tag in pending:
                            transport = transports[attempt_tag]
                            accepted = attempt_tag == tag and evidence["accepted"]
                            received = attempt_tag in responses
                            attempts.append(
                                Attempt(
                                    attempt_id=attempt_tag,
                                    policy=transport["model"],
                                    origin=transport["origin"],
                                    prompt=requests[attempt_tag]["messages"],
                                    request=transport["body"],
                                    response=responses[attempt_tag]["text"]
                                    if received
                                    else None,
                                    raw_response=(
                                        responses[attempt_tag]["body"] or None
                                    )
                                    if received
                                    else None,
                                    http_status=(
                                        responses[attempt_tag]["http_status"] or None
                                    )
                                    if received
                                    else None,
                                    platform_call_id=(
                                        responses[attempt_tag]["platform_call_id"]
                                        or None
                                    )
                                    if received
                                    else None,
                                    provider_request_id=(
                                        responses[attempt_tag]["provider_request_id"]
                                        or None
                                    )
                                    if received
                                    else None,
                                    stop_reason=(
                                        responses[attempt_tag]["stop_reason"] or None
                                    )
                                    if received
                                    else None,
                                    parsed_action=evidence["action"]
                                    if accepted
                                    else None,
                                    accepted=accepted,
                                    rejection_reason=None
                                    if accepted
                                    else (
                                        evidence["rejection_reason"] or "not_selected"
                                    ),
                                )
                            )
                        decisions.append(
                            Decision(
                                episode_id=episode_id,
                                decision_id=tag,
                                decision_index=evidence["decision_index"],
                                game_version=version,
                                source_revision=revision,
                                seat=str(seat),
                                observation={
                                    "report": requests[tag]["messages"][-1]["content"],
                                    "prompt_attempts": [
                                        {
                                            "attempt_id": key,
                                            "prompt_template": requests[key][
                                                "prompt_template"
                                            ],
                                        }
                                        for key in pending
                                    ],
                                },
                                prompt=requests[tag]["messages"],
                                attempts=attempts,
                                selected_attempt_id=tag
                                if evidence["accepted"]
                                else None,
                                executed_action=evidence["action"],
                                action_status="accepted"
                                if evidence["accepted"]
                                else "fallback",
                                fallback_origin=None
                                if evidence["accepted"]
                                else "engine-wait",
                            )
                        )
                        pending = []
                    else:
                        raise ValueError(f"Unknown private event role: {role}")
                unresolved[str(seat)] = pending
            decisions.sort(key=lambda decision: decision.decision_index)
            assert decisions and [
                decision.decision_index for decision in decisions
            ] == list(range(len(decisions)))
            decisions[-1].terminal = True
            for decision in decisions:
                destination.write(decision.model_dump_json() + "\n")
            episode = Episode(
                episode_id=episode_id,
                seed_family=f"heartleaf-{config['seed']}",
                game_version=version,
                source_revision=revision,
                outcome=results,
                participant_outcomes={
                    str(seat): {"score": score}
                    for seat, score in enumerate(results["scores"])
                },
            )
            destination.write(episode.model_dump_json() + "\n")
            sources.append(
                {
                    "episode_id": episode_id,
                    "capture_sha256": digest(capture_bytes),
                    "results_sha256": digest((run / "results.json").read_bytes()),
                    "transcripts_sha256": transcript_digests,
                    "decisions": len(decisions),
                    "unresolved_request_tags": unresolved,
                }
            )
    assert sources, "no complete captures found"
    manifest = {
        "schema_version": "1",
        "format": "coworld-private-candidates-v1",
        "game": "heartleaf",
        "review_required": True,
        "sources": sources,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "manifest.json").chmod(0o600)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    options = parser.parse_args()
    print(json.dumps(export(options.runs, options.output)))
