# Heartleaf benchmark session recovery

## Recovered conversation

The original Codex thread is `01a081e2-2de6-7192-b2f9-ac15283ff5f2`.
Its authoritative local transcript is
`~/.codex/sessions/2026/09/08/rollout-2026-09-08T09-37-58-01a081e2-2de6-7192-b2f9-ac15283ff5f2.jsonl`.
The transcript database associated this thread with a child transcript, so the
original JSONL was read directly to recover the actual user turns and ending.

The last event, at September 8, 2026, 18:24:53 Pacific, reports:
“This request was blocked by our safety systems. Reason: Potentially unintended activity.”
It names `misalignment_policy_violation`, but provides no specific explanation
of which operation triggered the rejection. It is not evidence of a code crash
or an intentional user stop.

## Decisions and previous results

- Extract the top-ranked submitted souls without running their images, preserve
  body bytes, and cross source identities with model identities.
- Use a separate `heartleaf-eval` world for accounting, nine seats per game,
  and explicit XP scheduling. Same-soul variants may play together.
- Team-only privacy was explicitly requested. Backend changes were excluded.
  League-less private XP was subsequently authorized, as were routine paid run
  attempts within the milestone's existing budget and acceptance gates.
- The eventual objective expanded to nine souls by ten working models, with
  every unordered policy pair meeting at least twice. The 20-second deadline
  and prohibition on hacky workarounds remained in effect.
- Historical canary evidence: transport-fixed eval version 0.1.5 completed
  105 usable actions without timeouts or truncation using Haiku 4.5,
  GPT-OSS-120B Nitro, and Gemini 2.5 Flash-Lite. Canary cost was $0.18548717.
  These are recovered results, not a new live verification.
- That private XP nevertheless produced an anonymously downloadable gameplay
  replay. The previous inspection found chat but no complete source soul bodies
  in that replay. The team-only requirement therefore remained unmet.
- Nine ranked sources were extracted; ranks 7 and 9 have identical bodies but
  remain distinct source identities. Seven more models had not passed screening.

See the [canary evidence](heartleaf-eval-gemini-canary-2026-09-08.md),
[privacy investigation](heartleaf-eval-existing-replay-privacy-controls-2026-09-08.md),
and [candidate plan](heartleaf-eval-ten-model-screening-2026-09-08.md).

## Exact unfinished operation and resumed work

The final operation added expanded-preparation tests. Two failed because the
CLI did not accept `prepare --models`. The September 9 continuation reproduced
those failures, then implemented that option using the existing pair scheduler.
Expanded preparation accepts one to nine consecutive ranked souls and a model
catalog, preserving the original three-by-three default behavior.

Expanded batches use schema `heartleaf-eval/2`. Legacy submission and reporting
reject that schema rather than interpreting the new schedule as the old milestone.
No models are marked accepted by preparation. See the updated
[operator runbook](../heartleaf_eval.md#expanded-cohort-local-groundwork).

Validation: all 55 evaluation tests passed, including 90-variant body preservation,
coverage of all 4,005 pairs at least twice, invalid catalog rejection, same-soul
villages, Haiku protocol preservation, and legacy submission/report rejection.
`git diff --check` passed. No Nim behavior changed in this continuation.

A real local preparation using the frozen nine sources and three previously
successful model configurations produced 27 image contexts and 24 planned games,
covering 351 pairs twice or more. It retains the rank-7/rank-9 duplicate bodies.
Artifacts: `tmp/heartleaf-eval/20260909-top9-controls-local/batch.json`.
These are local contexts, not built/uploaded policies or played games. The six
additional souls have not been verified with these models in hosted gameplay.

Freshness: fetched/pruned Heartleaf; HEAD and `origin/master` both equal
`ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`. Coworld 0.1.46 and Softmax CLI
0.26.32 remain the latest available releases in the project environment's
package-index check. Existing workspace changes were preserved.

## Remaining work

1. Resolve the team-only replay requirement before creating further hosted
   artifacts. The recovery did not change privacy policy or backend code.
2. Refresh accounting and estimate screening plus full evaluation costs against
   the existing $10 soft stop. The expansion has no verified budget projection.
3. Screen additional distinct models, then verify all 90 soul/model combinations.
4. Extend hosted submission, acceptance, and reporting for the expanded schedule.
5. Complete full-length runs and reconcile routing, costs, privacy, results, and
   actual pair coverage. Neither the first milestone nor the full benchmark is
   complete.

No remote writes, uploads, or paid inference were performed in this continuation.
