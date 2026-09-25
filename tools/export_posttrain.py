"""Export accepted Heartleaf model decisions from completed local games."""

import argparse
import hashlib
import json
import os
from collections import defaultdict
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def split(seed: str) -> str:
    fraction = int(hashlib.sha256(seed.encode()).hexdigest()[:8], 16) / 2**32
    return "validation" if fraction < 0.2 else "train"


def export(runs: Path, output: Path, source_revision: str) -> dict:
    examples: dict[str, list[dict]] = {"train": [], "validation": []}
    episodes = []
    sources = []
    for run in sorted(path for path in runs.iterdir() if path.is_dir()):
        seed = run.name
        results_path = run / "results.json"
        results = json.loads(results_path.read_text())
        completed = json.loads((run / "completed.json").read_text())
        if completed != {
            "seed": int(seed.removeprefix("heartleaf-")),
            "scores": results["scores"],
        }:
            raise ValueError(f"{seed}: completion proof differs from results")
        evidence = results["evaluation"]
        if evidence["schema"] != "heartleaf-eval-evidence/1":
            raise ValueError(f"{seed}: unknown evaluation evidence")
        events = evidence["events"]
        if evidence["event_count"] != len(events) or any(
            event["sequence"] != index for index, event in enumerate(events)
        ):
            raise ValueError(f"{seed}: incomplete evaluation events")
        seats = {entry["slot"] for entry in evidence["accepted_seats"]}
        models = {entry["slot"]: entry["model"] for entry in evidence["accepted_seats"]}
        if seats != set(range(len(results["scores"]))):
            raise ValueError(f"{seed}: scores and accepted seats disagree")

        replies: dict[int, list[dict]] = defaultdict(list)
        for event in events:
            if event["kind"] == "reply" and (
                "outcome=usable" in event["text"] or "outcome=parse" in event["text"]
            ):
                replies[event["seat"]].append(event)

        files = sorted(
            path
            for path in run.glob("seat*.jsonl")
            if path.stem.removeprefix("seat").isdigit()
        )
        if len(files) != len(seats):
            raise ValueError(f"{seed}: missing player transcript")
        file_digests = {}
        episode_id = digest(f"{source_revision}:{seed}".encode())[:32]
        decisions = []
        for path in files:
            seat = int(path.stem.removeprefix("seat"))
            if seat not in seats:
                raise ValueError(f"{seed}: unexpected seat {seat}")
            raw = path.read_bytes()
            file_digests[path.name] = digest(raw)
            effects_path = run / f"seat{seat}.effects.jsonl"
            effects_raw = effects_path.read_bytes()
            file_digests[effects_path.name] = digest(effects_raw)
            effects = {}
            for line in effects_raw.splitlines():
                effect = json.loads(line)
                key = (effect["index"], effect["tick"])
                if effect["game"] != 1 or effect["seat"] != seat or key in effects:
                    raise ValueError(f"{seed}: invalid applied effect for seat {seat}")
                effects[key] = effect
            rows = [json.loads(line) for line in raw.decode().splitlines()]
            if not rows or any(
                row["game"] != 1 or row["seat"] != seat or row["sequence"] != index
                for index, row in enumerate(rows)
            ):
                raise ValueError(f"{seed}: incomplete seat {seat} transcript")
            request = None
            request_tag = None
            decision_id = 0
            for row in rows:
                role, index, content = row["role"], row["index"], row["text"]
                if role == "request":
                    snapshot = json.loads(content)
                    request_tag = snapshot["tag"]
                    request = snapshot["messages"]
                    if (
                        index != -1
                        or not request
                        or request[0]["role"] != "system"
                        or request[-1]["role"] != "user"
                        or any(
                            message["role"] not in ("system", "user", "assistant")
                            for message in request
                        )
                    ):
                        raise ValueError(f"{seed}: invalid request for seat {seat}")
                elif role == "assistant":
                    if request is None:
                        raise ValueError(
                            f"{seed}: missing exact request for seat {seat}"
                        )
                    if decision_id >= len(replies[seat]):
                        raise ValueError(
                            f"{seed}: missing reply evidence for seat {seat}"
                        )
                    event = replies[seat][decision_id]
                    if (
                        event["tick"] != row["tick"]
                        or f"tag={request_tag} " not in event["text"]
                    ):
                        raise ValueError(
                            f"{seed}: reply differs from request for seat {seat}"
                        )
                    accepted = (
                        "outcome=usable" in event["text"]
                        and "ignored=wait" not in event["text"]
                    )
                    ignored = "ignored=wait" in event["text"]
                    effect = effects.pop((index, row["tick"]), None)
                    if (accepted or ignored) and effect is None:
                        raise ValueError(
                            f"{seed}: reply and applied action disagree for seat {seat}"
                        )
                    if (
                        effect is not None
                        and not accepted
                        and effect["action"] != "wait"
                    ):
                        raise ValueError(
                            f"{seed}: rejected reply applied a non-wait action for seat {seat}"
                        )
                    action = (
                        {
                            key: effect[key]
                            for key in (
                                "action",
                                "target_name",
                                "house_index",
                                "message",
                                "reason",
                            )
                        }
                        if effect is not None
                        else None
                    )
                    prompt = request
                    attempt_id = f"{seat}:{decision_id}"
                    status = (
                        "accepted"
                        if accepted
                        else "fallback"
                        if effect is not None
                        else "rejected"
                    )
                    decisions.append(
                        {
                            "schema_version": "1",
                            "event_type": "decision",
                            "event_id": str(
                                uuid5(NAMESPACE_URL, f"{episode_id}:{attempt_id}")
                            ),
                            "episode_id": episode_id,
                            "decision_id": attempt_id,
                            "decision_index": -1,
                            "game": "heartleaf",
                            "source_revision": source_revision,
                            "seat": str(seat),
                            "visibility": "private",
                            "observation": request[-1]["content"],
                            "prompt": prompt,
                            "attempts": [
                                {
                                    "attempt_id": attempt_id,
                                    "policy": models[seat],
                                    "origin": "model",
                                    "response": content,
                                    "parsed_action": action if accepted else None,
                                    "accepted": accepted,
                                    "rejection_reason": None
                                    if accepted
                                    else "ignored_action"
                                    if ignored
                                    else "parse_error",
                                }
                            ],
                            "selected_attempt_id": attempt_id if accepted else None,
                            "executed_action": action,
                            "action_status": status,
                            "fallback_origin": "game_wait"
                            if status == "fallback"
                            else None,
                            "reward": None,
                            "terminal": False,
                            "_tick": row["tick"],
                        }
                    )
                    if accepted:
                        examples[split(seed)].append(
                            {
                                "episode_id": digest(
                                    f"{source_revision}:{seed}:{seat}".encode()
                                )[:32],
                                "seed": seed,
                                "decision_id": decision_id,
                                "prompt": prompt,
                                "completion": [
                                    {"role": "assistant", "content": content}
                                ],
                                "game": "heartleaf",
                                "action_schema_revision": "heartleaf-decisions-v1",
                            }
                        )
                    request = None
                    request_tag = None
                    decision_id += 1
                elif role not in ("system", "user"):
                    raise ValueError(f"{seed}: unknown transcript role {role}")
            if decision_id != len(replies[seat]):
                raise ValueError(f"{seed}: reply evidence differs for seat {seat}")
            if effects:
                raise ValueError(f"{seed}: unmatched applied effects for seat {seat}")
        decisions.sort(
            key=lambda item: (
                item.pop("_tick"),
                int(item["seat"]),
                int(item["decision_id"].split(":")[1]),
            )
        )
        for index, decision in enumerate(decisions):
            decision["decision_index"] = index
        episodes.append(
            {
                "schema_version": "1",
                "episode": {
                    "schema_version": "1",
                    "event_type": "episode",
                    "event_id": str(uuid5(NAMESPACE_URL, f"{episode_id}:completed")),
                    "episode_id": episode_id,
                    "seed_family": seed,
                    "game": "heartleaf",
                    "source_revision": source_revision,
                    "status": "completed",
                    "outcome": results["scores"],
                    "participant_outcomes": {
                        str(seat): score for seat, score in enumerate(results["scores"])
                    },
                },
                "decisions": decisions,
            }
        )
        sources.append(
            {
                "seed": seed,
                "results_sha256": digest(results_path.read_bytes()),
                "transcripts_sha256": file_digests,
                "scores": results["scores"],
            }
        )

    if not all(examples.values()):
        raise ValueError("Both splits need completed games with accepted decisions")
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    for name, rows in examples.items():
        path = output / f"{name}.jsonl"
        path.write_text(
            "".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows)
        )
        os.chmod(path, 0o600)
    episodes_path = output / "episodes.jsonl"
    episodes_path.write_text(
        "".join(json.dumps(row, separators=(",", ":")) + "\n" for row in episodes)
    )
    os.chmod(episodes_path, 0o600)
    manifest = {
        "schema_version": 1,
        "game": "heartleaf",
        "source_revision": source_revision,
        "train_examples": len(examples["train"]),
        "validation_examples": len(examples["validation"]),
        "complete_episodes": len(episodes),
        "selection": "usable replies from complete games with matching player transcripts",
        "sources": sources,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    os.chmod(output / "manifest.json", 0o600)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-revision", required=True)
    options = parser.parse_args()
    print(json.dumps(export(options.runs, options.output, options.source_revision)))
