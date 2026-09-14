# Heartleaf eval: existing replay privacy controls

September 8, 2026, America/Los_Angeles. Read-only investigation.

## Conclusion

**No existing supported control was found that keeps ordinary hosted XP replays team-only while preserving the required replay artifact and current verification contract.** The `private` flag protects the request-facing API, but completed Coworld replays are independently copied to public storage without checking that flag.

The exact completed Gemini canary remains accessible without authentication. A fresh HTTP GET with a one-byte Range header returned **206 and one byte**. Curl configuration files were disabled, and no authorization header or cookies were sent. This confirms anonymous byte access; it is not merely an accessible viewer page. The unlisted artifact URL is deliberately omitted.

Under the unchanged constraints—team-only privacy, hosted XP, and no backend/storage-permission changes—this is a genuine blocker for further hosted episodes. Do not reinterpret “private” as “not listed.” Local preparation, schedule generation, mock validation, and model research can continue without publishing another replay.

## Scope and source freshness

Checked the released Coworld package, current backend source, runner upload/completion paths, Heartleaf recording controls, and the exact previous artifact. No backend code, storage policy, object metadata, hosted requests, or inference calls were changed.

- Coworld **0.1.46**, Softmax CLI **0.26.32**, project Python **3.13.5**. `uv pip list --outdated` found no newer release of either CLI.
- Metta was inspected in the separate `metta_4` checkout. Its working tree has unrelated documentation; those files were preserved. Fetched/pruned and read immutable `origin/main` **`935475525ce0aad25e18bdf2ad7498cc71289b2c`**, rather than assuming checkout HEAD was current.
- That latest commit serves static viewer bundles through a CDN. The replay publication path described below still exists at that exact revision.
- Heartleaf source references describe the current local eval implementation. The historical canary is identified by job `da00a452-89a2-4b91-88be-5b467ab831e4`; its private evidence is in `tmp/heartleaf-eval/20260908-gemini/`.

## What the existing controls actually do

| Candidate control | Actual effect | Meets team-only replay requirement? |
| --- | --- | --- |
| XP `private=true` | Limits request/episode visibility through API authorization | **No:** public replay copy ignores it |
| Private league | Changes enclosing-resource visibility | **No:** same completion/copy path |
| Remove `game.replay_viewer` | Selects container replay fallback; disables the gzip opt-in | **No:** public copying still runs |
| Change `replay_compression` | Chooses identity/gzip browser bytes | **No:** compression is not access control |
| Change Heartleaf `replayPath` | Changes the local temporary recording file | **No:** completed bytes still go to runner destination |
| Local CLI `--no-verify-replay` | Skips local replay validation | **No:** neither an XP privacy flag nor a recording/publication opt-out |
| Private original eval-bucket artifact | Retains the source copy under existing artifact access | **No:** completion creates a second public copy |
| Authenticated replay session / private viewer assets | Protects some viewer/session surfaces | **No:** direct replay-byte URL remains independently readable |

Sources and boundaries for each conclusion follow. No candidate was “tested” by weakening a production check or intentionally failing an upload.

## End-to-end publication path

The following references are in Metta commit `935475525ce0aad25e18bdf2ad7498cc71289b2c`.

1. **The request contract promises private artifacts.** `app_backend/src/metta/app_backend/v2/api_types.py:261` describes `private` as limiting the request, episodes, and artifacts to the requester. The request schema has no alternate replay destination or publication switch. The associated visibility predicate uses the stored flag and enclosing league at `v2/permissions.py:258` and `:276`.
2. **The ordinary dispatcher always supplies replay destinations.** `job_runner/dispatcher.py:862` uses `presigned_artifact_env_vars` for ordinary episode jobs. `dispatch_artifacts.py:21` generates every presigned artifact, and `job_artifacts.py:28` includes `REPLAY_URI`. Separately, `dispatcher.py:945` injects `COGAME_SAVE_REPLAY_URI` pointing to the shared local work directory. The persistent-runtime exception is a different long-lived execution mode, not a private XP replay option.
3. **The worker requires the replay before publishing successful results.** `packages/coworld/src/coworld/runner/kubernetes_runner.py:550` reads the replay first and raises `replay_missing` if it is absent or not a regular file. Its artifact wait uses `require_replay` whenever `REPLAY_URI` is present at `:869` and `:935`. The public game contract explicitly requires replay output in `packages/coworld/src/coworld/docs/roles/GAME.md:51`.
4. **Successful completion includes the replay.** `job_runner/event_processor.py:1267` passes the job replay URL to completion. `job_completion.py:348` calls `_copy_replay_for_job` when that URL is present.
5. **Publication ignores privacy.** `_copy_replay_for_job` at `job_completion.py:330` checks job type and viewer compression, then calls `copy_replay_to_public`. Its inputs contain no requester, league visibility, or private flag. `shared.py:77` selects the shared public destination; `shared.py:101` copies or compresses the source replay there. The implementation has no caller-selectable private destination.
6. **Tests confirm that publication is intentional in this path.** `app_backend/tests/job_runner/test_shared_replay.py:49` asserts the public destination and copy operation. The gzip test at `:72` asserts a public object too. These are not privacy tests; they corroborate the unconditional storage behavior.

The stored API visibility and artifact publication therefore disagree with the API's privacy description. Switching between league-less and private-league scheduling does not supply the missing decision to the copy function.

## Released manifest and game controls

In the installed Coworld 0.1.46 package, `coworld/types.py:301` defines `CoworldReplayViewer`. It permits only `bundle` and `replay_compression`, with unknown fields rejected. `CoworldGameManifest` at `:377` exposes no replay-publication or optional-recording setting. The documented compression setting explicitly concerns the public browser copy.

Removing the viewer does not suppress recording: the completion code still calls the public-copy function with gzip disabled. It also changes the required replay viewing contract to the container fallback. It is not a privacy solution.

Heartleaf opens its writer using `saveReplayPath` in `src/heartleaf.nim:6368`. At completion it reads that file and calls `runtimeConfig.writeReplay` at `:6619`. Startup derives a local file whenever the runner supplies a replay URI, even if the game-config `replayPath` is empty, at `:7190`. Thus “replayPath off” means no explicit local override, not “do not produce the hosted artifact.” The shared Bitworld runtime's save-replay options set destinations; they do not request private hosted storage.

The local CLI exposes `--verify-replay/--no-verify-replay` in installed `coworld/cli.py:1242` and `:1360`. The local runner still injects its recording destination at `coworld/runner/runner.py:426`. Disabling verification would also remove evidence required for this milestone. It neither changes hosted publication nor satisfies the privacy requirement.

## Excluded workarounds

Do not erase the recording destination, substitute an empty or misleading replay, suppress completion, or race a public copy with deletion. Those approaches break required artifacts, introduce a public exposure window, or bypass the completion/verification contract.

Do not treat encryption, redaction, an unguessable URL, private source images, or a hidden viewer link as an existing team-access control. A proper encrypted replay format and authorized viewer/key workflow would be new design work, not a supported flag. The previous replay's lack of embedded soul prompts limits that incident's contents; it does not satisfy team-only gameplay/chat privacy.

A private source artifact can be read through authorized existing paths, but retaining it does not undo the separate public copy. Changing public bucket policy, moving published objects, or teaching completion to retain private replay URLs requires additional authority or backend work outside this investigation.

## Decision and remaining uncertainty

The legitimate path under the current requirement is to keep new hosted runs paused and hand off the publication/access mismatch to the backend owner. A supported fix needs to preserve private artifacts for private requests and authorize their delivery, while retaining ordinary public replay behavior. The acceptance check must include an anonymous direct-byte request that is denied, not just a private XP readback or hidden browse entry.

This investigation does not prove that every other artifact class is private. A final end-to-end privacy gate must cover them too. Nor does current source prove an exact deployed revision; the fresh anonymous GET independently confirms the completed canary remains exposed now. No supported operator-level remedy was found in the checked current/released surfaces.

## Source map

```text
Released coworld/types.py                Manifest controls and strict schema
Released coworld/runner/runner.py         Local recording and verification
Metta v2/api_types.py, permissions.py    XP request contract and API visibility
Metta job_runner/dispatcher.py           Trusted game and worker artifact targets
Metta job_runner/dispatch_artifacts.py   Presigned artifact environment generation
Metta job_runner/job_artifacts.py        Required replay artifact identity
Metta coworld runner/kubernetes_runner.py Replay requirement and upload
Metta job_runner/job_completion.py       Completion-to-publication decision
Metta job_runner/shared.py               Public replay copy implementation
Heartleaf src/heartleaf.nim              Local replay recording and final write
```

The earlier [Gemini canary report](heartleaf-eval-gemini-canary-2026-09-08.md)
contains the completed-run privacy/readback evidence and exact non-secret run IDs.
