# Heartleaf eval: first hosted milestone

Status: implementation in progress, 2026-09-08. Incorporates James's nine exported review comments and his subsequent approval of league-less private requests when no supported new private league can be established. No backend changes are proposed or authorized.

Current execution contract: use the [operator runbook](../heartleaf_eval.md)'s explicit league-less mode. The new world is `cow_8bbab666-3bcb-4d0d-930b-27c9d6cd2ced`, `heartleaf-eval:0.1.0`. Its five hosted upload smoke episodes passed; hosted certification and evaluation acceptance remain separate gates. No league seed is configured. The league-targeted request examples and private-league acceptance requirement below describe the superseded proposal, not the current execution path. League-less requests instead use top-level `coworld_id`, `private=true`, no idempotency promise, and no blind POST retry. The nine-seat cohort and schedule are unchanged. See the [private-league history investigation](../recon/private-league-history-2026-09-08.md) for the evidence supporting this change.

## Outcome

Create a separate `heartleaf-eval` Coworld using the existing platform. Accept that its manifest and shared game assets are visible. Use a private league for the experiment and private Experience Requests (XP requests), with explicit nine-seat rosters. Keep spend attributed to the new Coworld, not the original Heartleaf world.

Freeze the top three ranked Heartleaf policies, extract their souls, and cross each soul with Claude Haiku 4.5, Qwen3.5-35B-A3B, and GPT-OSS-120B. This produces nine distinct soul/model policies. Run one nine-player canary and two full nine-player games. Every full game contains all nine policies, including three versions of each soul.

The scope is local tooling plus normal uploads and requests through existing APIs. No Observatory/Metta backend code, migrations, deployments, infrastructure changes, direct database writes, or broadened platform permissions are part of this milestone. The requested private league is an unresolved existing-platform setup constraint: seeded leagues are reconciled back to public. Resolve that operational path before uploading extracted policies or running paid games; do not turn it into a backend project.

## Evidence and current state

The original research used Heartleaf commit `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9` and Metta commit `b4e3589c1e509aaecce23fb63a418c21c7451e38`. The revision refreshed remotes: Heartleaf remains equal to origin/master at the same commit; the new league/routing checks use Metta origin/main `22a97ccd454b3c1d666488214d82e0ae3e45f04b`. The separate Metta worktree was read without rebasing it. No backend files were edited.

Original CLI probes used isolated coworld 0.1.45 and softmax-cli 0.26.32, not global installs. This revision does not depend on running either CLI. Before implementation, check current project-local releases through the project's dependency tool, and record the versions actually used.

References labeled with the Metta repository prefix refer to that repository. Original extraction and attribution citations retain their original pinned commit; the league/routing citations below use the refreshed commit. Live observations are labeled separately.

### Storage access: proven for one submitted soul

A team read-only SQL query found a ready, undeleted submitted image after the image-detail API returned 404. James's existing AWS PowerUser identity could read its manifest and layers without new permissions.

| Provenance | Observed value |
| --- | --- |
| Source policy | `nishadiota-heartleaf-tablekeeper:v2` |
| Policy-version UUID | `5c311a87-5993-4cc1-878c-7a5c137e9645` |
| Image ID | `img_ef1088cd-1292-4800-8aeb-712f6b9fab3c` |
| Registry | `471879937681.dkr.ecr.us-east-1.amazonaws.com` |
| Repository | `cogames/hayb9m1pzz988c5nioyoffel-7114269757e9/nishadiota-heartleaf-tablekeeper` |
| Image digest | `sha256:d6974770bbbb1b1ed358061cb8d8888f071b30be45384a9a13da0d6e4a7b9712` |
| Image size reported by ECR | 88,124,241 bytes |
| Runtime | Linux amd64; `/bin/soul_player`; `HEARTLEAF_SOUL_PATH=/soul.md` |
| Final image layer | `sha256:72a07c3ef736177354cf56fe7c5b8bdcb88809157975bf7b1c98ba1664a650bc` |
| Soul file | `/soul.md`, 3,511 bytes |
| Soul SHA-256 | `60f0c8debbfc0d72cf567f3a40267b9f74834cb333268ee73a19c0651dfbe86b` |

The earlier live probe successfully used `DescribeImages`, `BatchGetImage`, and `GetDownloadUrlForLayer`. It downloaded the final 5,120-byte layer into memory, verified its digest, and found the sole 3,511-byte soul file. Image configuration confirmed the runtime path. No container was started, and no soul text, credentials, or signed download URLs were printed or committed. This proves extraction for one policy, not for all three policies in the revised cohort.

Submitted images live in ECR, not in a separate application-managed S3 image archive. Use the supported registry download path. Upload/storage evidence: `metta/packages/coworld/src/coworld/upload.py:1980-2040`, `metta/app_backend/src/metta/app_backend/routes/container_image_routes.py:170-215,586-627`, and `metta/devops/app-manifests/values.yaml:43-53` at the original research commit.

For implementation, reuse [Docker create](https://docs.docker.com/reference/cli/docker/container/create/) and [Docker cp](https://docs.docker.com/reference/cli/docker/container/cp/) on digest-pinned images. A created, stopped container allows filesystem extraction without running the submitted program. Do not build a custom image-layer merger from the bounded last-layer probe.

### Accepted visibility tradeoff

| Surface | Existing behavior | Revised treatment |
| --- | --- | --- |
| Coworld upload | Upload accepts a manifest, without a Coworld public flag | Rename to heartleaf-eval; do not send public=False |
| Coworld manifest and listing | World metadata is not team-only | Accept visibility explicitly |
| Shared game/viewer assets | Existing public assets remain public | Reuse them; do not claim they are secret |
| League visibility | Team API can set public=False, hidden=False | Desired team-readable experiment league |
| Seeded league | Reconciliation reapplies public=True | Private league setup remains unresolved |
| XP requests | private=True limits ordinary-user access; elevated team reads exist | Set private on every request and verify actual access |
| Extracted souls | Submitted policy images are distinct from bundled game assets | Keep them out of public manifests and bundled player images; verify actual image visibility |

The original strict team-only Coworld requirement is explicitly relaxed by James. Private here describes the requested league and runs, not the world itself. No backend privacy feature will be built. Existing ordinary-owner exceptions and elevated team access must be documented honestly; do not claim stronger isolation than the platform provides.

Original visibility evidence: `metta/app_backend/src/metta/app_backend/routes/coworld_routes.py:381-384,2073-2168`, `metta/app_backend/src/metta/app_backend/v2/permissions.py:259-289,329-365`, and `metta/app_backend/src/metta/app_backend/job_runner/coworld_image_publisher.py:209-239`.

### Private league: the unresolved setup path

The existing visibility endpoint accepts public=False and hidden=False for an enabled league. However, the standard Coworld seed template sets public=True, and reconciliation restores that value. Disabling the seed also disables its league, while XP target selection excludes disabled leagues. Pausing rounds does not stop visibility reconciliation.

Fresh source evidence: `metta/app_backend/src/metta/app_backend/v2/routes/leagues.py:1914-1930`; `metta/app_backend/src/metta/app_backend/v2/seed.py:383-394,654-663,720-748`; `metta/app_backend/src/metta/app_backend/v2/routes/experience_requests.py:205-218`.

The inspected routes did not reveal a supported way to create a new, persistently private, unseeded league. This is a finding, not proof that no operational mechanism exists anywhere. Before execution, identify an existing supported setup mechanism with the platform owner and verify that it survives reconciliation. Do not assume an existing unrelated private league can be repurposed.

If no such mechanism exists, pause at this boundary and ask James whether to use league-less private XP requests on the new world. His latest comment specifically requests a league, so that fallback is not silently authorized. Do not repeatedly flip visibility, disable reconciliation, write database rows, or deploy a backend fix.

### OpenRouter and league-scoped XP requests

A live read of the deployed backend in the softmax-main cluster, observatory namespace, showed `COWORLD_OPENROUTER_ROUTING_ENABLED=true` and `COWORLD_OPENROUTER_EPISODE_PERCENT=100` during this revision. Current GitOps configuration agrees. Normal eligible Coworld episodes should therefore use OpenRouter without an override. This does not establish that every unrelated product's LLM traffic uses OpenRouter. Source: `metta/devops/app-manifests/values.yaml:388-434`.

Omit `llm_routing_override`. Recheck the deployed setting immediately before running and verify the realized route/model in all nine seats. If routing changes, report it rather than silently introducing an override or changing platform settings.

Target the new league through `target.league_id`. Do not also send a top-level Coworld ID: the API rejects mixed league and Coworld selectors. Resolve the league's Coworld first and assert that it is the new heartleaf-eval world. Use explicit policy-version UUIDs and slots 0 through 8. Source: `metta/app_backend/src/metta/app_backend/v2/routes/experience_requests.py:332-392,570-610`.

League-targeted requests use the existing league-scoped idempotency lookup and lock. Give each scheduled game a unique, stable key and persist the request body and returned ID. On an ambiguous response, reconcile or repeat the identical request under the same key, then verify the returned body/roster; do not change the payload under a reused key. Keep one request per game for clear accounting and serial verification, not because normal routing requires it. Sources: `metta/app_backend/src/metta/app_backend/v2/routes/experience_requests.py:939-960` at the refreshed commit and `metta/app_backend/src/metta/app_backend/v2/experience_requests.py:276-310` at the original research commit.

Spend attribution follows job attempt to episode request to Coworld ID/name. A new league alone would not move spend off Heartleaf; its runtime must resolve to the separately uploaded world. This changes the attribution dimension, not the payer. Original evidence: `metta/app_backend/src/metta/app_backend/usage_ingest/llm_attribution.py:85-154` and `metta/app_backend/src/metta/app_backend/usage_ingest/episode_llm_usage.py:14-84`.

## Models and fixed experiment

| Model label | Soul first line | Expected canonical model |
| --- | --- | --- |
| H: Claude Haiku 4.5 | `#!us.anthropic.claude-haiku-4-5-20251001-v1:0` | `anthropic/claude-haiku-4.5` |
| Q: Qwen3.5-35B-A3B | `#!qwen/qwen3.5-35b-a3b` | `qwen/qwen3.5-35b-a3b` |
| G: GPT-OSS-120B | `#!openai/gpt-oss-120b` | `openai/gpt-oss-120b` |

Keep the first two models from the original proposal. Add [GPT-OSS-120B](https://openrouter.ai/openai/gpt-oss-120b), which has [published open weights](https://github.com/openai/gpt-oss), as the third model. [Haiku](https://openrouter.ai/anthropic/claude-haiku-4.5) is the requested baseline; [Qwen](https://openrouter.ai/qwen/qwen3.5-35b-a3b) is the existing efficient open-weight comparison. These are practical comparison choices, not claims of equal capability or cost. Do not use a free or auto model alias.

Heartleaf accepts the header syntax, uses its existing Anthropic path for Haiku, and routes the other two through Converse translation. The hosted canary must prove both canonical-slug paths work and produce useful actions. No provider adapter or self-hosted inference is proposed. Sources: `src/heartleaf/souls.nim:9-13,43-87`, `src/heartleaf/bedrock_client.nim:117-139`, and `metta/app_backend/src/metta/app_backend/job_runner/bedrock_translation.py:305-350,774-787` at the original research commit.

Use the shared eval setting `BEDROCK_MAX_TOKENS=2048`. This deliberately differs from the current default of 192; preserve all other game rules and pacing. Verify both open-weight models return complete actions rather than using the entire budget on reasoning. Record truncations. If changes are needed after the canary, stop, version the experiment, and record them before full games. Source: `src/heartleaf/bedrock_client.nim:15-16,97-105`.

### Freeze three souls and generate nine policies

At preparation time, snapshot the top three ranked eligible policy versions from the chosen Heartleaf leaderboard/division. Record league/division ID, ranking metric, timestamp, rank, policy UUID, and immutable image digest. Label them S1, S2, and S3. Do not use a dynamic top_n selector during evaluation.

The previously extracted Tablekeeper image is a proven extraction example, not a guaranteed member of the refreshed top three. Download each selected image again. If any top-three soul is unavailable or invalid, report the exact failure rather than quietly substituting a lower-ranked policy. Keep identical source bodies if two ranked policies happen to share a soul, but flag the duplicate; do not pretend this is three independent prompt bodies.

| Source | Haiku | Qwen | GPT-OSS |
| --- | --- | --- | --- |
| Rank 1 soul | S1-H | S1-Q | S1-G |
| Rank 2 soul | S2-H | S2-Q | S2-G |
| Rank 3 soul | S3-H | S3-Q | S3-G |

Each cell is a separately named policy with its own immutable UUID. Within a row, the raw soul body must be byte-identical; only the model header changes. Multiple variants of the same soul explicitly belong in the same village. Reporting groups by policy UUID, source soul, and model, never just by uploader/player identity.

### Standard nine-player schedule

Use the canonical nine-seat `league` variant, not a custom two-seat variant and not filler players. The current game technically supports 2-9 seats, but James's requested experiment is a full nine-player village. The standard variant declares nine players and a seven-day game. Source: `coworld_manifest_template.json:292-331`; `README.md:49-54`.

Base seat order is [S1-H, S1-Q, S1-G, S2-H, S2-Q, S2-G, S3-H, S3-Q, S3-G]. For the second full game, move the policy at slot i to slot (i+4) modulo 9. This changes every policy's house. It is not a fully house-balanced design.

| Game | Roster | Seed | Length | Counts toward coverage |
| --- | --- | --- | --- | --- |
| canary | All nine, base order | 91001 | 1 game day, 180 seconds/day | No |
| eval-a | All nine, base order | 91002 | 7 game days, 180 seconds/day | Yes |
| eval-b | All nine, rotated by four seats | 91002 | 7 game days, 180 seconds/day | Yes |

Set maxGames=1, maxTicks=0, and real model replies for each request. Only the canary shortens the duration; it still uses nine seats. Run serially, proceeding only after the previous game's checks pass.

Nine distinct policies give 36 unordered pairs. Each complete full game contains all 36 pairs, so two successful full games give every pair M=2 meetings, including same-soul/different-model pairs. The canary is excluded. Equal seeds do not make model replies deterministic. These correlated village results are infrastructure and behavior evidence, not 36 independent trials or enough evidence to declare a winning model. Full house balancing and the eventual top-nine-by-N cohort are later work.

## Implementation sequence

### 1. Resolve existing-platform setup and freeze inputs

Keep all code work in this Heartleaf repository. Resolve the private-league setup issue described above using only existing supported operations before paid execution. Read the current API schemas rather than assuming a generic create-league endpoint exists.

Pin the original Heartleaf manifest, previously observed as `cow_f7e8be04-190b-470f-befe-fe98ca1cbcea`, version 0.2.7. Refresh that read and preserve exact game/viewer digests. Snapshot the top-three cohort and current model catalog/prices. Do not infer deployed image equality from a current local checkout.

Start a friction log alongside the batch record. Existing findings are the image-detail API 404 despite an image existing, admin SQL/ECR access needed for extraction, the absence of atomic Coworld visibility, seeded-league privacy reconciliation, and mutually exclusive league/Coworld XP selectors. Record evidence, operator effort, workaround, risk, and suggested future API improvement. Do not implement those improvements in this task.

### 2. Build the local driver and nine policy images

Add a small synchronous driver, focused tests, and a runbook. Reuse the Coworld API client, existing httpx dependency where needed, AWS CLI, and Docker. No new service, solver, async framework, backend package edits, or deployment. Local work means the code lives locally; later uploads and XP submissions still create hosted resources and spend money.

The driver supports prepare, submit-one, inspect, and report. Runtime artifacts belong in an ignored batch directory. Never commit source souls, credentials, signed URLs, authenticated logs, or images.

For each of the three digest-pinned images, authenticate using short-lived credentials and a temporary Docker config, create a stopped container, copy the soul from its configured location, and validate it with Heartleaf's parser. If the location differs from the proven example, record it. Remove only the temporary stopped container and temporary credential configuration after extraction. Retain source hashes and provenance.

Split the model header without normalizing body bytes. Generate H/Q/G variants for every source and assert matching body hashes within each triplet. Use one reusable compiled soul-player base and nine thin derived images. Build for Linux amd64, use distinct policy names, and record exact image digests and policy UUIDs.

The batch manifest records source rank/policy/image/soul hashes; nine variant identities; requested models; game/viewer/uploader digests; new Coworld ID/version; league ID and resolved runtime; schedule; request/episode/job-attempt IDs; cost and status.

Tests cover invalid souls, header-only transformation, all nine combinations, explicit unique slots, the four-seat rotation, prevention of original-world submissions, private request fields, omission of routing override, correct league target shape, stable per-game idempotency keys, ambiguous responses, and all 36 pair counters. Count distinct successful full episodes only. Include multiple policies from one uploader and duplicate source-body fixtures.

### September 8 amendment: reasoning-limited eval revision

James authorized limiting reasoning to meet the existing 20-second deadline
after the post-fix canary exposed Qwen reasoning-only responses and timeouts.
The first revision disables optional thinking for OpenRouter Qwen 3.5 via
Converse `additionalModelRequestFields`. Keep the 2048 output cap, nine seats,
souls, other model settings, viewer, and schedule unchanged. Publish only a
new `heartleaf-eval` version; do not change the backend or original Heartleaf.
Retain source `game_provenance` and separately pin `eval_game_image` in the new
batch. This supersedes the unchanged-game-image constraint for this specific
request-shaping change. Hosted verification must measure actual latency and
usable text; disabling reasoning does not guarantee provider latency.
The Qwen-only canary then exposed GPT-OSS deadline failures. The next revision
tested GPT-OSS's lowest supported reasoning effort (`low`), but its
`output_config` parameter excluded every available endpoint on the hosted
route. That change was withdrawn. Qwen also produced a 23.5-second call with
zero reasoning and only 60 output tokens, so reasoning limits alone have not
met the all-request latency gate. Haiku and GPT-OSS remain unchanged in the
restored working configuration; further provider-routing work is not complete.

### 3. Prepare and validate the nine-player game

Create a renamed heartleaf-eval manifest with independent version/ownership, exact pinned game/viewer images, standard nine-seat league variant, and the declared shared token cap. Keep extracted souls and eval policies out of manifest-bundled player entries. Existing public baseline players may serve certification. Do not set an unsupported Coworld public flag.

Run the package's real validation/certification workflow with a mocked fixture to avoid unnecessary model calls. Run all nine generated images together in a local mocked episode and verify soul acceptance, results, and replay. Mock success establishes packaging/protocol only.

Use the repository's pinned Nim toolchain when rebuilding the uploader and its documented unit and integration tests. Follow the existing CI dependency setup. Add driver tests and documentation in the same change. Audit documentation before any commit. This plan does not authorize pushing, merging, deploying, uploading, or spending during the current review turn.

### 4. Upload, establish the private league, and verify scope

Using the approved existing setup path, upload heartleaf-eval through the normal manifest upload API. Wait for certification graduation, successful upload smoke episodes, and version readiness. Verify that the standard variant has nine seats and the original Heartleaf world remains unchanged.

Create or obtain the dedicated league through that supported mechanism, set public=False and hidden=False with the existing team visibility API, and keep automatic rounds paused using the existing rounds-paused setting. Verify the league resolves to the new Coworld/version and standard variant. Record league/division identities as needed by the XP API. Do not start a ladder or commissioner process locally.

Read privacy back after reconciliation, and verify the league remains enabled and usable as an XP target. Confirm there are no unintended automatic rounds. Pausing must be verified before attaching the eval cohort; do not assume a visibility call also stops scheduling. If persistent private setup cannot be established, stop here and report the blocker, without hacking the backend or exposing the cohort through a public league.

Upload the nine submitted policies once the league/privacy path is established. Use explicit UUID selection without champion qualification unless the existing API actually requires membership. If membership is required, record that friction and use the documented route without launching qualification games accidentally.

Check team access and ordinary non-team denial for the league/private requests/artifacts using legitimate credentials or test fixtures. Verify submitted-soul image records do not expose public URIs, including after a publisher cycle. Public Coworld metadata and already-public game assets are expected, not failures. Report any role-testing limitation rather than impersonating a teammate.

### 5. Submit the canary and two full games

Generate one existing-API request per scheduled game:

```json
{
  "target": {"league_id": "<new-private-heartleaf-eval-league-id>"},
  "variant_id": "league",
  "private": true,
  "num_episodes": 1,
  "idempotency_key": "<batch>-canary",
  "notes": "heartleaf-eval <batch> canary; three souls by three models",
  "game_config_overrides": {
    "seed": 91001,
    "maxGames": 1,
    "maxDays": 1,
    "daySeconds": 180,
    "maxTicks": 0,
    "mockReply": ""
  },
  "roster": [
    {"player": {"policy_ref": "<S1-H-uuid>"}, "slot": 0},
    {"player": {"policy_ref": "<S1-Q-uuid>"}, "slot": 1},
    {"player": {"policy_ref": "<S1-G-uuid>"}, "slot": 2},
    {"player": {"policy_ref": "<S2-H-uuid>"}, "slot": 3},
    {"player": {"policy_ref": "<S2-Q-uuid>"}, "slot": 4},
    {"player": {"policy_ref": "<S2-G-uuid>"}, "slot": 5},
    {"player": {"policy_ref": "<S3-H-uuid>"}, "slot": 6},
    {"player": {"policy_ref": "<S3-Q-uuid>"}, "slot": 7},
    {"player": {"policy_ref": "<S3-G-uuid>"}, "slot": 8}
  ]
}
```

The request has neither a top-level Coworld ID nor a routing override. Before POST, assert the target league's resolved world is the new heartleaf-eval ID, visibility remains private, automatic rounds remain paused, and the roster is exactly the intended nine UUIDs. Use James's legitimate user credential and the existing elevation mechanism where needed.

Before the first game, read current budgets, dispatch/per-episode limits, model availability, and default routing. Keep the proposed $10 driver stop threshold pending a nine-seat canary cost check. It is not a guaranteed cost estimate or hard provider cap: ingestion lag and a running game can exceed it. With one active game and three deliberate submissions maximum, wait for canary spend, project the remaining cost, and pause for a revised budget if necessary. Do not silently raise the threshold or invent an XP budget field.

Canary acceptance requires all nine souls accepted, successful real calls from every seat, three correct canonical models, OpenRouter execution, usable action JSON, no persistent truncation/default replies, terminal success, results, and replay. Inspect durable attempts/provider records and player logs; request fields are not execution proof.

After the canary and accounting checks pass, submit eval-a and eval-b with the full-game configuration and seat rotation. Retain failures and their costs. A replacement is an explicit additional submission requiring a reviewed schedule/budget, not an invisible retry until scores look good.

### 6. Verify accounting, coverage, and report results

Reconcile each request to episodes, all attempts, the realized Coworld/version/config, and all nine seated policies. Confirm both full games reach the last day with all nine scores. Watch replay behavior and inspect accepted souls, model calls, actions, truncations/timeouts, and normal completion.

Use the approved read-only SQL/API surfaces for episode-level usage grouped by episode, slot, policy, model/provider where available, and source. Every pilot attempt, including retries, must attribute to heartleaf-eval, never the original heartleaf world. Separately reconcile Coworld budget/spend totals. Include upload/certification compute as setup cost and distinguish canary cost from evaluation cost.

Wait up to a proposed 30 minutes after completion for usage ingest before marking accounting unresolved. Missing rows are not zero cost. Reconcile provider and episode totals within a stated rounding/caching tolerance without double-counting projections of the same calls.

Deliver Markdown and machine-readable results in the ignored batch directory. Include request/episode IDs, seed, seat/house, source soul/rank, policy UUID, requested/served model, final score, successful/failed calls, truncations/timeouts, tokens, LLM cost, compute/setup cost where available, routing evidence, terminal result, authorized replay/log links, and a 9-by-9 pair-coverage matrix. The diagonal is excluded; all 36 off-diagonal unordered pairs must have count 2 from the two full games.

Report descriptive within-soul model comparisons and village-level results without statistical superiority claims. Append the website/API friction log, all workarounds, remaining limitations, and proposed future improvements. Leave automatic league rounds paused and make no recurring-refresh commitment.

Final acceptance is three traced source policies, nine immutable variants with matching within-soul body hashes, a separate visible Coworld, a persistently private enabled league with paused automatic rounds, one successful nine-seat real-model canary, two completed nine-seat full games, verified routing/spend, all-pair M=2 coverage, and an honest results/friction report. The private-league setup constraint must be resolved through existing operations or explicitly renegotiated before claiming this milestone is executable end to end.

## Alternatives and scope boundaries

- Backend Coworld privacy work is removed entirely. A visible renamed world is the accepted tradeoff.
- A two-seat game is removed. Standard nine-player villages use all nine generated policies without fillers.
- Three souls by two models plus filler policies would preserve the old model count, but mixes filler behavior into the experiment. Three by three follows James's requested expansion.
- A single soul across nine separately named variants remains valid for later constant-soul studies. It is not this three-soul cohort.
- A new ladder/tournament scheduler is unnecessary. Existing league-targeted XP requests give exact rosters and per-game tracking; the league supplies context rather than automatic scheduling.
- Repeatedly setting a seeded league private is unreliable because reconciliation undoes it. Disabling its seed also removes it as an XP target. Neither is an acceptable privacy workaround.
- League-less private XP requests would work with a visible new world, but require James to approve relaxing his latest league request. If chosen, restore the stricter no-blind-POST-retry behavior because league-less idempotency is not guaranteed.
- Existing Docker/ECR extraction and the hosted sidecar avoid a custom image export service, layer merger, new provider adapter, or self-hosted inference.

Remaining uncertainty: an existing supported persistent-private-league setup has not been identified; only one source soul extraction is proven; the new nine-policy package and Qwen/GPT-OSS routes have not been exercised in a hosted Heartleaf village; no new-world results or accounting are verified. These are execution checks and one explicit setup blocker, not permission to change the backend.

## Planned local files and validation commands

These are planned local implementation artifacts, not files already implemented by this review.

| Artifact | Purpose |
| --- | --- |
| `eval/tools/heartleaf_eval.py` | Synchronous prepare, submit-one, inspect, and report driver |
| `eval/tests/test_heartleaf_eval.py` | Focused driver, transformation, roster, and coverage tests |
| `eval/docs/heartleaf_eval.md` | Operator runbook, setup limitations, and recovery procedure |
| `tmp/heartleaf-eval/<batch>/` | Ignored source souls, batch manifest, and authenticated evidence |
| `tmp/heartleaf-eval/<batch>/results.md` | Final results with machine-readable companion data |
| `tmp/heartleaf-eval/<batch>/friction.md` | Website/API issues, local workarounds, and future improvements |

Use the project's real environment and check current CLI releases before implementation. Packaging verification uses `coworld run-episode`. When rebuilding the uploader, run `nim r tests/tests.nim`; after building the game, run `HEARTLEAF_SERVER=out/heartleaf nim r tests/integration.nim`. Follow `.github/workflows/tests.yml` for dependency setup. Run the new driver tests through its declared isolated Python environment. No backend test or deployment suite is needed because no backend code is changed.

## Review comment outcomes

| Comment ID | Outcome |
| --- | --- |
| cmtsynlkl0 | Accepted: visible Coworld, no Coworld privacy implementation |
| cmtsyp5qf1 | Accepted: no backend changes; existing visibility tradeoffs documented |
| cmtsyq26i2 | Answered: deployed Coworld routing is enabled at 100%; override removed |
| cmtsyraah3 | Incorporated as the target: private league and league-targeted XP; persistent setup remains blocked by seed reconciliation |
| cmtsytb0n5 | Answered: all nine seats use the three-soul by three-model product; no fillers |
| cmtsyusb76 | Removed platform privacy phase and its deployment requirement |
| cmtsyv2j57 | Expanded to three souls and three models, including GPT-OSS-120B |
| cmtsywnah8 | Clarified local code versus hosted API writes/spend; added per-step website/API friction reporting |
| cmtsyy3i29 | Replaced two-seat variant with the standard nine-seat league variant |

The exported review JSON remains unchanged. Rewritten passages may cause old comments to appear orphaned in the HTML comment sidebar; the table above preserves their disposition.
