"""Run complete local Heartleaf games and retain player transcripts."""

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path


def collect(
    root: Path,
    server_binary: Path,
    player_binary: Path,
    souls: list[Path],
    seeds: list[int],
    output: Path,
    port: int,
    max_ticks: int,
    max_days: int,
    timeout_seconds: int,
    mock_reply: str,
    prompt_variant: str,
    prompt_seed: int,
) -> None:
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    for offset, seed in enumerate(seeds):
        run = output / f"heartleaf-{seed}"
        run.mkdir(mode=0o700)
        tokens = [f"training-{seed}-{seat}" for seat in range(len(souls))]
        config = {
            "tokens": tokens,
            "maxGames": 1,
            "seed": seed,
            "promptVariant": prompt_variant,
            "promptSeed": prompt_seed + offset
            if prompt_variant == "mixed"
            else prompt_seed,
        }
        if max_days:
            config["maxDays"] = max_days
        else:
            config["maxTicks"] = max_ticks
        if mock_reply:
            config["mockReply"] = mock_reply
        (run / "config.json").write_text(json.dumps(config) + "\n")
        source_status = subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=root, text=True
        ).strip()
        (run / "capture.json").write_text(
            json.dumps(
                {
                    "schema": "heartleaf-private-capture/1",
                    "source_revision": subprocess.check_output(
                        ["git", "rev-parse", "HEAD"],
                        cwd=root,
                        text=True,
                    ).strip(),
                    "source_dirty": bool(source_status),
                    "source_status": source_status,
                    "server_sha256": hashlib.sha256(
                        server_binary.read_bytes()
                    ).hexdigest(),
                    "player_sha256": hashlib.sha256(
                        player_binary.read_bytes()
                    ).hexdigest(),
                    "souls_sha256": [
                        hashlib.sha256(soul.read_bytes()).hexdigest() for soul in souls
                    ],
                    "config": config,
                }
            )
            + "\n"
        )
        environment = os.environ.copy()
        environment["COGAME_RESULTS_URI"] = (run / "results.json").as_uri()
        environment["HEARTLEAF_EVAL_ARTIFACT"] = "true"
        environment["HEARTLEAF_TRAINING_DIR"] = str(run)
        with (run / "server.log").open("w") as server_log:
            server = subprocess.Popen(
                [
                    str(server_binary),
                    f"--port:{port + offset}",
                    "--config:" + json.dumps(config),
                ],
                cwd=root,
                env=environment,
                stdout=server_log,
                stderr=subprocess.STDOUT,
            )
            players = []
            logs = []
            try:
                for seat, (soul, token) in enumerate(zip(souls, tokens, strict=True)):
                    handle = (run / f"player{seat}.log").open("w")
                    logs.append(handle)
                    players.append(
                        subprocess.Popen(
                            [
                                str(player_binary),
                                f"--url:ws://localhost:{port + offset}/player?slot={seat}&token={token}",
                                f"--soul:{soul}",
                                f"--name:Train{seat}",
                            ],
                            cwd=root,
                            stdout=handle,
                            stderr=subprocess.STDOUT,
                        )
                    )
                if server.wait(timeout=timeout_seconds) != 0:
                    raise RuntimeError(f"Heartleaf server failed for seed {seed}")
                for player in players:
                    if player.wait(timeout=20) != 0:
                        raise RuntimeError(f"Heartleaf player failed for seed {seed}")
            finally:
                if server.poll() is None:
                    server.terminate()
                    server.wait(timeout=10)
                for player in players:
                    if player.poll() is None:
                        player.terminate()
                        player.wait(timeout=10)
                for handle in logs:
                    handle.close()
        result = json.loads((run / "results.json").read_text())
        (run / "completed.json").write_text(
            json.dumps({"seed": seed, "scores": result["scores"]}) + "\n"
        )
        print(seed, result["scores"], result["evaluation"]["event_count"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--player", type=Path, required=True)
    parser.add_argument("--soul", type=Path, action="append", required=True)
    parser.add_argument("--seed", type=int, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=18963)
    length = parser.add_mutually_exclusive_group(required=True)
    length.add_argument("--max-ticks", type=int, default=0)
    length.add_argument("--max-days", type=int, default=0)
    parser.add_argument("--timeout-seconds", type=int, default=3600)
    parser.add_argument("--mock-reply", default="")
    parser.add_argument(
        "--prompt-variant",
        default="canonical",
        choices=(
            "canonical",
            "plain",
            "numbered",
            "questions",
            "reordered",
            "heldout-briefing",
            "heldout-reference",
            "mixed",
        ),
    )
    parser.add_argument("--prompt-seed", type=int, default=0)
    options = parser.parse_args()
    if max(options.max_ticks, options.max_days) <= 0:
        parser.error("game length must be positive")
    collect(
        Path(__file__).resolve().parents[1],
        options.server.resolve(),
        options.player.resolve(),
        [soul.resolve() for soul in options.soul],
        options.seed,
        options.output.resolve(),
        options.port,
        options.max_ticks,
        options.max_days,
        options.timeout_seconds,
        options.mock_reply,
        options.prompt_variant,
        options.prompt_seed,
    )
