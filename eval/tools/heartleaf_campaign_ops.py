"""Start or inspect the existing campaign controller and spend monitor together."""

import argparse
from datetime import UTC, datetime
from pathlib import Path
import shlex
import subprocess
import sys
import time

import heartleaf_eval_api as api
import heartleaf_eval_results as results


PROCESSES = {
    "controller": ("heartleaf_eval_campaign.py", "launch.json", "controller.log"),
    "spend_monitor": ("heartleaf_eval_campaign_budget.py", "monitor-launch.json", "monitor.log"),
}


def process_status(directory, name):
    """Check both the PID and its command, so a reused PID is not called healthy."""
    script, receipt, _ = PROCESSES[name]
    path = directory / receipt
    if not path.exists():
        return {"running": False, "pid": None}
    launch = api.read_json(path)
    pid = int(launch["pid"])
    if pid <= 0:
        raise ValueError("Invalid process ID in " + str(path))
    probe = subprocess.run(
        ["ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True, check=False
    )
    command = shlex.split(probe.stdout.strip())
    expected_script = str(Path(__file__).parent / script)
    running = (
        probe.returncode == 0
        and expected_script in command
        and "--campaign" in command
        and str(directory) in command
    )
    return {"running": running, "pid": pid, "started_at": launch.get("started_at")}


def status(directory):
    state = api.read_json(directory / "campaign.json")
    policy = api.read_json(directory / "spend-policy.json")
    processes = {name: process_status(directory, name) for name in PROCESSES}
    spend_path = directory / "spend-latest.json"
    spend = api.read_json(spend_path) if spend_path.exists() else None
    return {
        "campaign": str(directory),
        "recorded_status": state["status"],
        "controller_stopped": state["status"] == "active" and not processes["controller"]["running"],
        "current_round": state["rounds"][-1]["round"],
        "completed_rounds_including_baseline": sum("metrics" in r for r in state["rounds"]),
        "processes": processes,
        "budget_paused": policy["paused"],
        "limit_usd": policy["limit_usd"],
        "known_new_spend_usd": spend["known_new_spend_usd"] if spend else None,
        "spend_observed_at": spend["observed_at"] if spend else None,
    }


def start(directory):
    """Explicit resume only; never restart live processes or clear budget pauses."""
    operations = directory / "operations"
    operations.mkdir(exist_ok=True)
    with api.batch_lock(operations):
        current = status(directory)
        if current["recorded_status"] == "complete":
            return current
        # Start the independent observer before the controller. A paused
        # campaign may still have submitted games whose charges need observing.
        for name in ("spend_monitor", "controller"):
            if current["processes"][name]["running"]:
                continue
            if name == "controller" and (
                current["budget_paused"]
                or current["recorded_status"] == "awaiting_budget_approval"
                or (directory / "spend-launch-stop.json").exists()
            ):
                continue
            script, receipt, log_name = PROCESSES[name]
            command = [sys.executable, "-u", str(Path(__file__).parent / script), "--campaign", str(directory)]
            if sys.platform == "darwin":
                command = ["/usr/bin/caffeinate", "-is", *command]
            with (directory / log_name).open("ab") as log:
                child = subprocess.Popen(
                    command, cwd=Path(__file__).resolve().parents[2], stdin=subprocess.DEVNULL,
                    stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
                )
            results.write_json(directory / receipt, {
                "pid": child.pid, "command": command, "started_at": datetime.now(UTC).isoformat(),
                "previous_pid": current["processes"][name]["pid"],
            })
    return status(directory)


def milestone(directory):
    """Ignore routine call/spend increments; detect results and operational stops."""
    current = status(directory)
    state = api.read_json(directory / "campaign.json")
    last = state["rounds"][-1]
    terminal = []
    if "experiment" in last:
        for pointer in sorted(Path(last["experiment"]).parent.glob("games/*/latest.json")):
            generation = pointer.parent / api.read_json(pointer)["generation"]
            record = api.read_json(generation / "summary.json")
            if record["status"] in results.TERMINAL:
                terminal.append((record["request_id"], record["status"], record["measurement_verified"]))
    stamp = current["spend_observed_at"]
    stale = stamp is None or (datetime.now(UTC) - datetime.fromisoformat(stamp)).total_seconds() > 120
    return {
        "round": current["current_round"], "status": current["recorded_status"],
        "terminal_games": terminal,
        "processes_live": {n: p["running"] for n, p in current["processes"].items()},
        "budget_paused": current["budget_paused"] or (directory / "spend-launch-stop.json").exists(),
        "spend_stale": stale,
    }


def wait_for_change(directory):
    """Wait locally for a result, round transition, or issue; never mutate a run."""
    previous = milestone(directory)
    while True:
        if (
            previous["status"] != "active" or previous["budget_paused"]
            or previous["spend_stale"] or not all(previous["processes_live"].values())
            or any(s != "completed" or not verified for _, s, verified in previous["terminal_games"])
        ):
            return previous
        time.sleep(30)
        current = milestone(directory)
        if current != previous:
            return current


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("start", "status", "wait"))
    parser.add_argument("--campaign", type=Path, required=True)
    args = parser.parse_args()
    import json

    action = {"start": start, "status": status, "wait": wait_for_change}[args.command]
    print(json.dumps(action(args.campaign.resolve()), indent=2))
