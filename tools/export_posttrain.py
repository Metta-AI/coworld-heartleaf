"""Export accepted Heartleaf model decisions from completed local games."""

import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def split(seed: str) -> str:
    fraction = int(hashlib.sha256(seed.encode()).hexdigest()[:8], 16) / 2**32
    return "validation" if fraction < 0.2 else "train"


def export(runs: Path, output: Path, source_revision: str) -> dict:
    examples: dict[str, list[dict]] = {"train": [], "validation": []}
    sources = []
    for run in sorted(path for path in runs.iterdir() if path.is_dir()):
        seed = run.name
        results_path = run / "results.json"
        results = json.loads(results_path.read_text())
        completed = json.loads((run / "completed.json").read_text())
        if completed != {"seed": int(seed.removeprefix("heartleaf-")), "scores": results["scores"]}:
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
        if seats != set(range(len(results["scores"]))):
            raise ValueError(f"{seed}: scores and accepted seats disagree")

        replies: dict[int, list[dict]] = defaultdict(list)
        for event in events:
            if event["kind"] == "reply" and (
                "outcome=usable" in event["text"] or "outcome=parse" in event["text"]
            ):
                replies[event["seat"]].append(event)

        files = sorted(run.glob("seat*.jsonl"))
        if len(files) != len(seats):
            raise ValueError(f"{seed}: missing player transcript")
        file_digests = {}
        for path in files:
            seat = int(path.stem.removeprefix("seat"))
            if seat not in seats:
                raise ValueError(f"{seed}: unexpected seat {seat}")
            raw = path.read_bytes()
            file_digests[path.name] = digest(raw)
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
                    if index != -1 or not request or request[0]["role"] != "system" or request[-1]["role"] != "user":
                        raise ValueError(f"{seed}: invalid request for seat {seat}")
                    if any(message["role"] not in ("system", "user", "assistant") for message in request):
                        raise ValueError(f"{seed}: invalid request message for seat {seat}")
                elif role == "assistant":
                    if request is None:
                        raise ValueError(f"{seed}: missing exact request for seat {seat}")
                    if decision_id >= len(replies[seat]):
                        raise ValueError(f"{seed}: missing reply evidence for seat {seat}")
                    event = replies[seat][decision_id]
                    if event["tick"] != row["tick"] or f"tag={request_tag} " not in event["text"]:
                        raise ValueError(f"{seed}: reply differs from request for seat {seat}")
                    if "outcome=usable" in event["text"] and "ignored=wait" not in event["text"]:
                        examples[split(seed)].append(
                            {
                                "episode_id": digest(f"{source_revision}:{seed}:{seat}".encode())[:32],
                                "seed": seed,
                                "decision_id": decision_id,
                                "prompt": request,
                                "completion": [{"role": "assistant", "content": content}],
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
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    for name, rows in examples.items():
        (output / f"{name}.jsonl").write_text(
            "".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows)
        )
    manifest = {
        "schema_version": 1,
        "game": "heartleaf",
        "source_revision": source_revision,
        "train_examples": len(examples["train"]),
        "validation_examples": len(examples["validation"]),
        "selection": "usable replies from complete games with matching player transcripts",
        "sources": sources,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-revision", required=True)
    options = parser.parse_args()
    print(json.dumps(export(options.runs, options.output, options.source_revision)))
