# Heartleaf eval: initial scope

Status: proposal and read-only investigation, 2026-09-08. No world, policies, or episodes were created. No submitted soul was extracted.

Follow-up: [the milestone implementation plan](../designs/heartleaf-eval-milestone-1.md) supersedes the extraction and privacy proposals below. Submitted souls were subsequently extracted through authorized AWS access to ECR. James specified a separate Coworld for spend attribution and permits multiple variants of one soul together. The approved revision prohibits backend changes: the private-league setup remains a stop condition, not authorization for platform privacy work. See the [operator runbook](../heartleaf_eval.md) for the implemented local workflow and remaining hosted gates.

## Mission and evidence

Scope a private evaluation using nine Heartleaf souls crossed with N models, with every distinct policy pair sharing at least M completed games. Investigate source selection, extraction, packaging, privacy, and scheduling.

Heartleaf checkout was clean and equal to freshly fetched `origin/master` at `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`. Metta source was inspected directly at freshly fetched `origin/main`, `6cb6ef84cdf9efc4de7b21359ea868d62c38bb06`, without changing its ahead-of-main checkout. Metta references below are paths at that commit, accessible through [the pinned source tree](https://github.com/Metta-AI/metta/tree/6cb6ef84cdf9efc4de7b21359ea868d62c38bb06).

Installed tools were coworld `0.1.38.post1.dev750` and softmax-cli `0.26.29`. PyPI reported `0.1.45` and `0.26.32`; probes used isolated `uvx` environments with those releases. No global installs changed.

Relevant directory map:

- `src/heartleaf/souls.nim`: soul parser and acceptance protocol.
- `src/heartleaf/bedrock_client.nim`: model request formatting and routing.
- `players/soul_player/`: reusable soul uploader.
- `players/*_villager/`: example soul images.
- `commissioner/`: bundled commissioner configuration; not the current live scheduling authority.
- `coworld_manifest_template.json`: game, roles, variants, and certification fixture.
- Metta `packages/coworld/src/coworld/`: existing CLI, API client, and runtime documentation.
- Metta `app_backend/src/metta/app_backend/v2/`: leaderboard selection, experience requests, league visibility, and scheduling.

## 1. Selecting the nine souls

Live reads identified Heartleaf league `league_f831ba75-e81b-4796-b8c6-cd10be18c0bf`, Competition division `div_396961a3-58af-4276-abc7-3f45fb7fe337`, and canonical Coworld `cow_f7e8be04-190b-470f-befe-fe98ca1cbcea`, version `0.2.7`.

The leaderboard ranks players. Four top-nine rows had null policy labels, but the active champion memberships resolved all nine. This is not evidence that those players lack policies. The platform itself joins ranked players to eligible current champions: Metta `app_backend/src/metta/app_backend/v2/experience_requests.py:578-635`.

Observed ranking and current policy mapping:

| Rank | Player | Current policy |
| --- | --- | --- |
| 1 | NishadIota | nishadiota-heartleaf-tablekeeper:v2 |
| 2 | Aaron | aaron-tablemate:v27 |
| 3 | richard | co-gas-heartleaf-simple-richard:v91 |
| 4 | NanosaurusX | nancy-heartleaf:v4 |
| 5 | Andrew Brower B | towhee:v3 |
| 6 | daveey | heartleaf-hearthpledge:v1 |
| 7 | Andre von Auto | alyonushka:v1 |
| 8 | relh | co-gas-heartleaf-simple-relhalpha:v98 |
| 9 | Andre von Houck | coolbot:v15 |

Read commands: `uvx --from coworld==0.1.45 coworld results div_396961a3-58af-4276-abc7-3f45fb7fe337 --json` and `coworld memberships --division <division> --active-only --champions-only --limit 100 --json`. Ranking and membership reads were separate, so this is an observed mapping, not an atomic frozen cohort.

Recommendation: select ranked eligible current champions, then freeze policy-version UUIDs, ranking timestamp, source image digest, original soul bytes/hash, and original model. New refreshes create new cohorts rather than changing a running cohort. Current player rating may include earlier policy versions; this evaluates current champions of top-ranked players, not necessarily the nine strongest individually measured soul files.

## 2. Can we extract submitted soul files?

Not proven yet. World downloads contain bundled examples, not arbitrary leaderboard policy images. Submitted images remain private according to Metta `packages/coworld/src/coworld/docs/roles/PLAYER.md:118-131`. The image-detail route uses owner-bound authorization: `app_backend/src/metta/app_backend/routes/container_image_routes.py:486-506`.

Live authenticated probe with the documented elevated header:

- `GET /stats/policy-versions/5c311a87-5993-4cc1-878c-7a5c137e9645` returned 200 for the #1 policy.
- It identified `img_ef1088cd-1292-4800-8aeb-712f6b9fab3c`.
- `GET /v2/container_images/img_ef1088cd-1292-4800-8aeb-712f6b9fab3c` returned 404, `Container image not found`.

That establishes a failed retrieval route, not whether the underlying image is missing versus inaccessible. No registry pull, source extraction, or permission changes were attempted.

Proposed extraction order:

1. Obtain an authorized digest-pinned image reference/export through the platform's supported internal access path, or an exact-version source export from the author.
2. Inspect the image command and soul-path configuration, then extract the actual file. The bundled example uses `/soul.md` and `HEARTLEAF_SOUL_PATH`; arbitrary submissions need inspection. See `players/friendly_villager/Dockerfile` and `players/soul_player/soul_player.nim:372-401`.
3. Use standard Docker operations rather than writing an image-layer extractor: [docker create](https://docs.docker.com/reference/cli/docker/container/create/) creates without starting; [docker cp](https://docs.docker.com/reference/cli/docker/container/cp/) can copy from stopped containers.
4. If the soul is compiled in or generated at runtime, file extraction may not work. A separate protocol-capture experiment could collect the submitted text, but that would require running the player and proving the captured soul is representative.

Do not silently substitute a reconstructed system prompt for the original file. Heartleaf adds mechanics and substitutes character names; the log is a derived prompt, not guaranteed original source (`docs/soul_files.md`, sections “What the game appends” and “What the player gets back”).

## 3. Creating the Cartesian product

The format is `#!<model-id>`, not `!<model-slug>`. The parser separates the first line from the prompt body (`src/heartleaf/souls.nim:9-13,43-87`). The existing uploader sends the soul text; the game plays the character (`players/soul_player/soul_player.nim:281-314`).

Proposal: reuse one compiled uploader base image. For each soul/model pair, make a thin image containing the changed soul file, then register a distinct policy with `coworld upload-policy`. Preserve body bytes and verify that only the model header changed. Record source and generated hashes plus policy-version UUIDs in a cohort manifest. This needs no new game behavior or player framework.

Upload extracted variants as submitted policies, not bundled manifest players: bundled images are published through the world-upload path (Metta player-role documentation cited above).

Model names must work through the actual hosted route. Current Heartleaf uses InvokeModel for Anthropic and Converse for other providers, with family-specific settings (`src/heartleaf/bedrock_client.nim:117-139,178-202`). Parsing a header does not prove model availability. `docs/soul_files.md` lists older verified models, while the current parser accepts more families; use hosted canaries for the chosen models. Record requested model, actual served model/routing where available, errors, latency, and spend. Do not infer model identity from the policy name alone.

## 4. Private world versus private execution

A separate named eval world is plausible, but ordinary upload/seeding is not a verified private creation workflow. Metta `app_backend/src/metta/app_backend/v2/seed.py:383-394` constructs seeded leagues with `public=True`. Merely renaming the manifest is insufficient.

League read privacy uses `public=False` with ownership; `hidden=True` also hides from owners and is not the intended private-workspace control (`v2/permissions.py:128-176`). Package/image publication, league discovery, and episode/artifact access are separate surfaces. A private league does not imply private bundled image contents.

Existing experience requests support `private=True`, explicit policy-version selectors, direct Coworld targeting, config overrides, and idempotency keys (`v2/api_types.py:188-225,254-312`). Recommendation for the first execution test: use a private request against a pinned Heartleaf Coworld version. A named `heartleaf-eval` world can follow once its creation and readback flow is proven private from the outset. This is a proposed staging choice, not a replacement for the requested eventual world.

## 5. Pair coverage and experimental design

Live Heartleaf uses platform `balanced_rotation`, two episodes per round, on a 180-minute interval. This supersedes the bundled YAML's shuffled-window configuration. The implementation shuffles an entrant ring and takes successive groups; it has no minimum completed-meetings counter (`v2/round_lifecycle.py:871-883`). Increasing episode count within one ring can repeat the same groups when the roster size is a multiple of nine.

Recommendation: generate explicit nine-seat lineups and submit private experience requests using immutable policy-version IDs. Count coverage from distinct successfully completed episodes, handle failures with replacement games, and stop only when every unordered pair reaches M. Balance total appearances, house/seat assignments, and opponent model composition in addition to coverage. No new container commissioner is needed for the first batch; current seed code also marks container commissioners deprecated and closed to new use (`v2/seed.py:138-164`).

This is a pair-covering block-design problem, related to the established [social golfer problem](https://csplib.github.io/csplib-PR-builds/PR-21/Problems/prob010/). That classic problem avoids repeat pairs; this task requires every pair to occur at least M times. For a constrained scheduler, prefer an existing solver such as [OR-Tools CP-SAT](https://developers.google.com/optimization/cp/cp_solver), with a time-bounded feasible schedule and independently checked coverage, over a custom optimization engine. No solver dependency is needed for a small smoke lineup.

Derived capacity bound: let K = 9N. Every nine-seat episode covers 36 unordered pairs, so at least `ceil(M*K*(K-1)/72)` episodes are necessary. Also each policy needs at least `ceil(M*(K-1)/8)` appearances. These are lower bounds, not achievable schedule promises. For N=4 and M=5, the pair bound is 88 episodes; actual scheduling, balance, and retries may require more.

One consequential fork: “every other policy” includes different models using the same source soul. That requires allowing repeated source souls within a game. Requiring exactly one instance of each of the nine souls per game makes those pairs impossible. Default recommendation: allow these encounters to satisfy the literal coverage requirement.

Pair coverage alone does not establish statistical power or isolate model effects. Report results by soul and model, then aggregate across the fixed nine souls. Treat the episode as the shared interaction unit. Choose whether the target is performance under Heartleaf's real-time pacing or reasoning quality under equalized call/token budgets; the latter may require game changes and would be a different experiment.

## Proposed first milestone and unresolved decisions

1. Resolve access and extract one exact submitted soul; validate its header/body and provenance.
2. Generate two model variants with the existing uploader. Verify unchanged body hashes.
3. Run a small private hosted canary with pinned game/version, explicit seats, and a spending limit. Verify actual model routing, accepted souls, completed results, and private artifact readback.
4. Extract the full nine-soul cohort, generate 9N policies, and produce a schedule plus independent coverage counts before launching the full batch.
5. Add the private named world and repeatable batch driver; periodic refresh remains optional and produces new cohorts.

Resolved at scoping level: selection, packaging, and scheduling approach. Partially resolved: privacy (private requests exist; private world creation needs verification). Unresolved: exact soul extraction through current access, selected model IDs, N/M and budget, who should see the eval, and whether equalized compute is desired. No hosted model canary or privacy test has been run.
