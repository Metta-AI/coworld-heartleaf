"""Preserve full game stdout before hosted artifact tail truncation.

Run alongside the experiment runner. Reads local result pointers and uses the
existing tournament kubectl identity. Never submits or cancels hosted games.
"""

import argparse
import json
import subprocess
import time
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--hours", type=float, default=24)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    children = []
    deadline = time.monotonic() + args.hours * 3600
    try:
        while time.monotonic() < deadline:
            for experiment in args.experiment:
                for latest in (experiment.parent / "games").glob("*/latest.json"):
                    pointer = json.loads(latest.read_text())
                    record = json.loads(
                        (
                            latest.parent / pointer["generation"] / "summary.json"
                        ).read_text()
                    )
                    job = record.get("final_job_id")
                    if not job or record["status"] in (
                        "completed",
                        "failed",
                        "cancelled",
                    ):
                        continue
                    receipt = args.output / (job + ".capture.json")
                    if receipt.exists():
                        continue
                    query = subprocess.run(
                        [
                            "kubectl",
                            "--context",
                            "tournament",
                            "-n",
                            "jobs",
                            "get",
                            "pods",
                            "-o",
                            "json",
                        ],
                        check=False,
                        capture_output=True,
                        text=True,
                        timeout=45,
                    )
                    if query.returncode:
                        continue
                    pods = [
                        p["metadata"]["name"]
                        for p in json.loads(query.stdout)["items"]
                        if p["metadata"]["name"].startswith("job-" + job[:8] + "-")
                        and "-game-player-" not in p["metadata"]["name"]
                    ]
                    if len(pods) != 1:
                        continue
                    command = [
                        "kubectl",
                        "--context",
                        "tournament",
                        "-n",
                        "jobs",
                        "logs",
                        pods[0],
                        "-c",
                        "game",
                        "-f",
                    ]
                    with (
                        (args.output / (job + ".log")).open("wb") as out,
                        (args.output / (job + ".stderr")).open("wb") as err,
                    ):
                        child = subprocess.Popen(
                            command, stdin=subprocess.DEVNULL, stdout=out, stderr=err
                        )
                    children.append(child)
                    receipt.write_text(
                        json.dumps(
                            {
                                "job_id": job,
                                "pod": pods[0],
                                "container": "game",
                                "context": "tournament",
                                "pid": child.pid,
                                "command": command,
                            }
                        )
                        + "\n"
                    )
                    print(json.dumps({"capturing": job, "pid": child.pid}), flush=True)
            time.sleep(20)
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()


if __name__ == "__main__":
    main()
