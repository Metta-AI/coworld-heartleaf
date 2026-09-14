# Heartleaf eval: client transport fix

September 8, 2026 Pacific; hosted timestamps may be September 9 UTC.

## Implemented and published

Heartleaf's LLM client now disables `CURLOPT_PIPEWAIT`, preventing a slow first
response from holding other villagers' requests before they reach the sidecar.
The existing nine-handle cap and 20-second request deadline are unchanged.
This fixes the mechanism established in the [local reproduction](heartleaf-eval-startup-investigation-2026-09-08.md),
not provider-side generation that itself exceeds 20 seconds.

The new evaluation world is certified and canonical:

- `heartleaf-eval:0.1.5`
- Coworld: `cow_88c0215f-6f90-42ec-826c-c1729312e494`
- Game image: `public.ecr.aws/q5f4m8t9/cogames@sha256:4a186a7cf10ce05fc94fa57b05ff8e8ded6a0d235ef18a530792a63848aface0`
- Manifest hash: `sha256:7931c41f76f1cd7dd665b437387b9dee1ea9ec081978f3e52de0de7a590e6068`
- Runtime executable SHA-256: `721d65e713e3ed705bb1e9f73dd94bad04e9ff8b09a5496380b8ebd21239f27d`

All five hosted upload smoke episodes and all ten hosted certification steps
passed. A subsequent read verified canonical resolution and certified state;
the CLI's earlier `Canonical: no` output described the pre-graduation stage,
not the final state. The original Heartleaf manifest hash remained unchanged.
No backend code, deployment, league settings, or platform permissions changed.

## Small behavioral change, reproducible dependency packaging

The installed and current upstream Curly APIs do not expose PIPEWAIT.
Replacing the HTTP client or using one blocking worker per seat would be a
larger change. Patching the shared Nimby installation would not reliably carry
into other developers' builds, CI, or uploads.

Instead, `vendor/curly/curly.nim` retains the full pinned Curly 1.1.1 module
from `a0f42baacbc48f4e5924b18854c0df9dcc251466`, with only a per-client
`pipeWait = true` constructor option, its stored field, and the corresponding
curl option assignment. The value is set before worker creation. The default
preserves upstream behavior.

`src/heartleaf/bedrock_client.nim` explicitly imports that module and passes
`pipeWait = false`. Other users, including credential fetching, still import
the normal Nimby dependency. The upstream MIT license and provenance are kept
beside the copied module; the runtime image includes the license at
`/usr/share/licenses/heartleaf/curly/LICENSE`. See [vendor maintenance notes](../../../vendor/curly/README.md).

## Regression and validation

The new regression uses the actual `BedrockClient`, a threaded local fake
sidecar, and response barriers. It holds the first response open, then requires
the other eight requests to reach the server and return usable actions before
releasing that first response. It repeats with the same client. It does not
depend on a sub-second speed threshold or call any provider.

- Fixed client: both waves passed, **18 usable replies**.
- Isolated control with only `pipeWait = true`: failed at the first barrier,
  with only seat 0 received. No shared source or installed dependency was
  modified for that control.
- Added to CI: `nim c tests/bedrock_transport.nim`, then
  `python3 tests/test_bedrock_transport.py --probe out/bedrock_transport`.
- Frozen eval-source unit suite: passed.
- Current-source unit suite: passed after correcting the test mount to include
  the current assets; the initial mixed-source/old-assets invocation failed
  because `data/backdrop.png` was absent.
- Current-source socket integration: first invocation failed its one-second
  soul-acceptance window; an unchanged retry passed. That test uses mock
  replies and never creates Curly, so the PIPEWAIT path was not exercised.
  This is an observed transient test failure, not a claimed longstanding
  baseline defect.
- All 42 offline eval-driver tests passed; the new Python harness passed Ruff
  checks and formatting. `git diff --check` passed.
- Independent source review found no correctness issues in initialization,
  shared header types, import scope, or build inclusion.
- Final exact-image local certification: all ten steps passed before upload.

## Frozen source and build evidence

Main development checkout was fetched and verified at
`ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`, equal to `origin/master`;
pre-existing unrelated edits were preserved. The release was built from a
separate worktree, `/Users/jamesboggs/coding/coworlds/heartleaf-eval-transport`,
at the same frozen original game revision used by the prior evaluation,
`fa7b3f654174c9c7ddbde412ef610f63484eb487`, plus the existing Qwen request
override and this transport/license change. This avoids importing unrelated
current game behavior into the evaluation.

Build used the repository Dockerfile, Nim 2.2.4, locked Nimby dependencies,
Linux amd64, ORC, and threads enabled. Runtime libcurl is
`7.88.1-10+deb12u15`, matching the reproduction. Source changes are local;
no Git branch was pushed and no PR was created.

Project-local Coworld 0.1.46 and Softmax CLI 0.26.32 were checked against
available releases before execution. The live backend added
`game.player_runtime: platform-hosted`, which this latest released CLI rejects.
The upload manifest omits only this field after verifying its value and the
backend's documented default, leaving behavior unchanged. The standard
manifest validation then passed; no validator or toolchain guard was bypassed.
The first validation failure and final passing runs are retained.

Artifacts: `tmp/heartleaf-eval/20260908-transport/` contains the manifest,
before/after readbacks, certification and build logs, unit and integration logs,
and upload transcript. `tmp/heartleaf-eval/startup-investigation/` contains
the red/green regression logs and original controlled timing reproduction.

## Gemini follow-up

The separate `20260908-gemini` batch preserves the three existing Haiku policies
and three GPT-OSS Nitro policies, replacing the three Qwen policies with
`google/gemini-2.5-flash-lite` as explicitly confirmed by James. Nine seats,
source soul bodies, 2,048 output-token cap, and the 20-second deadline remain
fixed. The game revision and model replacement are both recorded changes;
this is not an isolated model-speed benchmark against the previous run.

The subsequent hosted canary completed with **105 usable actions, no timeouts,
and all nine seats participating**. All 105 raw Broadcast traces were found.
Initial game-request timestamps to earliest upstream starts were approximately
10–58 ms across the nine seats; these compare the logged game-frame clock with
the upstream clock, rather than directly measuring individual network stages.
The previous multi-second startup wait did not recur in this canary.

The [Gemini canary report](heartleaf-eval-gemini-canary-2026-09-08.md) records
model timings, results, and accounting. It also records a separate privacy
gap: the XP row is private, but its gameplay replay is downloadable without
authentication. This specific replay contains gameplay/chat, no embedded
conversation records, and no full source soul-body matches. The experiment
does not meet strict team-only artifact visibility. Further paid runs are on
hold pending James's direction; backend/storage permissions were not changed.
No full evaluation coverage is claimed by the one-day canary or certification.
