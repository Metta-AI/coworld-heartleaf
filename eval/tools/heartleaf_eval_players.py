"""Build and privately upload prepared variants, with durable upload intents."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import heartleaf_eval_api as api
import heartleaf_eval_results as results
import httpx
from heartleaf_eval import transform_soul


def verified_upload(client, variant: dict) -> dict:
    policy = api.get_json(
        client, "stats/policy-versions/" + variant["policy_version_id"]
    )
    image = api.get_json(client, "v2/container_images/" + policy["container_image_id"])
    if (
        image["status"] != "ready"
        or image.get("public_image_uri")
        or image.get("is_coworld_image")
    ):
        raise ValueError("Expected a ready private player image")
    if variant.get("image_digest") and variant["image_digest"] != image["image_digest"]:
        raise ValueError("Uploaded image digest changed")
    return {
        "policy_version_id": policy["id"],
        "container_image_id": image["id"],
        "image_digest": image["image_digest"],
    }


def upload(batch_path: Path, client) -> None:
    batch_path = api.validate_batch_path(batch_path)
    batch = api.read_json(batch_path)
    directory = batch_path.parent
    sources = {s["rank"]: s for s in batch["sources"]}
    reusable = {}
    for path in api.BATCH_ROOT.glob("*/batch.json"):
        other = api.read_json(path)
        if other.get("uploader_base_image") != batch["uploader_base_image"]:
            continue
        for v in other.get("variants", []):
            if v.get("policy_version_id") and v.get("image_digest"):
                reusable[
                    (
                        v.get("source_policy_version_id"),
                        v.get("soul_sha256"),
                        v.get("model"),
                    )
                ] = v
    with api.batch_lock(directory):
        for variant in batch["variants"]:
            context = api.evidence_file(
                directory, variant["context"] + "/soul.md"
            ).parent
            source = sources[variant["source_rank"]]
            original = api.evidence_file(directory, source["soul_path"]).read_bytes()
            raw = (context / "soul.md").read_bytes()
            if results.digest(context / "soul.md") != variant[
                "soul_sha256"
            ] or raw != transform_soul(original, variant["model_header"]):
                raise ValueError("Prepared variant no longer matches its frozen soul")
            key = (
                variant["source_policy_version_id"],
                variant["soul_sha256"],
                variant["model"],
            )
            if variant.get("policy_version_id"):
                verified_upload(client, variant)
                continue
            if key in reusable:
                variant.update(verified_upload(client, reusable[key]))
                variant["reused_from_policy_version_id"] = reusable[key][
                    "policy_version_id"
                ]
                results.write_json(batch_path, batch)
                print(
                    json.dumps(
                        {
                            "reused": variant["key"],
                            "policy_version_id": variant["policy_version_id"],
                        }
                    ),
                    flush=True,
                )
                continue
            record_dir = directory / "uploads" / variant["key"]
            intent = record_dir / "intent.json"
            if not intent.exists():
                image_name = f"{batch['batch_id']}:{variant['key'].lower()}"
                subprocess.run(
                    [
                        "docker",
                        "build",
                        "--platform",
                        "linux/amd64",
                        "-t",
                        image_name,
                        str(context),
                    ],
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                info = json.loads(
                    subprocess.check_output(["docker", "image", "inspect", image_name])
                )[0]
                if info["Architecture"] != "amd64":
                    raise ValueError("Expected linux/amd64 player image")
                variant["local_image"] = image_name
                variant["local_image_id"] = info["Id"]
                results.write_json(batch_path, batch)
                api.write_json(
                    intent,
                    {
                        "policy_name": variant["policy_name"],
                        "local_image_id": info["Id"],
                        "soul_sha256": variant["soul_sha256"],
                    },
                    exclusive=True,
                )
                cli = Path(sys.executable).parent / "coworld"
                with (record_dir / "upload.log").open("w") as log:
                    (record_dir / "upload.log").chmod(0o600)
                    subprocess.run(
                        [
                            str(cli),
                            "upload-policy",
                            image_name,
                            "--name",
                            variant["policy_name"],
                        ],
                        stdout=log,
                        stderr=subprocess.STDOUT,
                        check=True,
                    )
            response = client.get(
                "stats/policy-versions", params={"name_exact": variant["policy_name"]}
            )
            response.raise_for_status()
            entries = response.json()["entries"]
            if len(entries) != 1:
                raise ValueError(
                    "Upload outcome unresolved: reconcile intent; do not upload again"
                )
            variant.update(
                verified_upload(client, {"policy_version_id": entries[0]["id"]})
            )
            results.write_json(record_dir / "receipt.json", variant)
            results.write_json(batch_path, batch)
            print(
                json.dumps(
                    {
                        "uploaded": variant["key"],
                        "policy_version_id": variant["policy_version_id"],
                    }
                ),
                flush=True,
            )


def main():
    from softmax.auth import get_api_server, load_user_token

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    args = parser.parse_args()
    server = get_api_server()
    with httpx.Client(
        base_url=api.observatory_base_url(server),
        headers={
            "Authorization": "Bearer " + load_user_token(server=server),
            api.ELEVATED_PRIVILEGES_HEADER: "true",
        },
        timeout=60,
    ) as client:
        upload(args.batch, client)


if __name__ == "__main__":
    main()
