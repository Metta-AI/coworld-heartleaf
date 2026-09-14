# Operating a Heartleaf candidate campaign

The campaign does not require a chat agent to select or launch each round. Once
started, the controller runs the successive-cohort loop and the independent
monitor observes spend. The live dashboard is documented in
[heartleaf_dashboard.md](heartleaf_dashboard.md).

## One command to start or resume

From the Heartleaf repository, using the project evaluation environment:

```bash
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_campaign_ops.py start \
  --campaign tmp/heartleaf-eval/20260909-candidate-campaign
```

This starts the spend monitor before the controller, writes process receipts,
and keeps logs in the campaign directory. It leaves already-running processes
alone. On macOS it uses the existing `caffeinate -is` execution pattern. It never
cancels games, changes experimental parameters, clears a budget pause, or
automatically retries a stopped controller. An explicit `start` resumes after
the operator has investigated the stop.

Inspect without starting anything:

```bash
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_campaign_ops.py status \
  --campaign tmp/heartleaf-eval/20260909-candidate-campaign
```

Status checks the PID's current command and campaign path. A saved `active`
status alone does not establish that the controller is alive. Spend timestamps
show whether the independently collected accounting is fresh. Known spend is a
lower bound while billing is incomplete.

Wait for a meaningful change instead of repeatedly requesting status:

```bash
tmp/heartleaf-eval-venv/bin/python eval/tools/heartleaf_campaign_ops.py wait \
  --campaign tmp/heartleaf-eval/20260909-candidate-campaign
```

This read-only command checks locally every 30 seconds and returns when a game
finishes, the round changes, a process stops, the budget pauses, or spend data
becomes stale. Existing issues return immediately. Routine call-count and cost
increments do not wake the operator; the dashboard continues displaying those.
It sends no external notifications and never restarts or cancels a game.

## Games running at once

The runner uses the frozen `max_parallel_games` unless its linked campaign has
an `execution-policy.json` with an operational override:

```json
{"max_parallel_games": 5}
```

The runner rereads this value when checking launch capacity, including the
submission preflight. It applies to the current and future rounds without
rewriting frozen model, soul, seed, duration, or request inputs. Lowering it
allows already-submitted games to finish. The independent campaign spend guard
still checks every new launch and may permit fewer games near the spend limit.
Rounds remain sequential because selecting a new roster requires all five
results. Record the reason and timestamp alongside the override when changing it.
An older runner must be restarted locally after archiving the code revision;
hosted games continue and their existing receipts are reused.

## What is automated

| Responsibility | Implementation / durable state |
| --- | --- |
| Candidate list, queue order, previous rounds and coverage | `campaign.json` |
| Five seven-day games, fixed seeds, roster and no-canary setting | Frozen round `experiment.json`; canonical experiment runner |
| Games running at once | Frozen default or campaign `execution-policy.json` override |
| Policy preparation and upload reuse | `heartleaf_eval_campaign.prepare_round` and existing player uploader |
| Submission receipts and duplicate protection | Experiment submission intents and locks |
| Transient read retries and artifact collection | Experiment runner and result collector |
| Scores, failure events, latency and known costs | Immutable per-game summaries and raw artifacts |
| Artifact hashes, roster and measurement validation | `latest_records` and result normalization |
| Top-two cost/score and top-two failures, union of removals | `rank_round`, `removal_lists`; persisted decisions |
| Zero scores, ties, survivor seats and final-round fillers | Campaign code; documented in `heartleaf_experiments.md` |
| All candidates tested in a complete five-game round | Campaign coverage calculation and completion condition |
| New-spend accounting, launch guard and allowing submitted games to finish | Spend policy, independent monitor, runner preflight |
| Starting both processes and distinguishing stopped from live | `heartleaf_campaign_ops.py` |
| Current progress and cumulative completed-game performance | Local dashboard |

The exact five selection-failure categories are `deadline_exceeded`, `token_limit`,
`empty_response`, `invalid_action`, and `upstream_error`. Other categories remain
visible but are not silently added to selection. Cost/score uses pooled known
inference cost provisionally; compute is counted in campaign spend, not attributed
to a particular model's selection cost.

## What still needs judgment

- Establishing a new candidate list or changing the experimental design.
- Recovering genuinely missing or inconsistent evidence, diagnosing infrastructure
  failures, or fixing newly encountered collector defects. Do not delete receipts
  or mark incomplete measurements verified to force progression.
- Reviewing and archiving code changes with the runner's `revise-runner` command
  before new submissions. This preserves the code provenance of the experiment.
- James's approval before resuming beyond the spend ceiling.
- A final independent review of the complete campaign before making research claims.

These are explicit boundaries, rather than instructions an agent must remember
between normal rounds. Start/status is intentionally not an automatic restart loop:
the controller stops on an integrity failure for a reason. See `controller.log`
and the current `round-NN.log`, fix or reconcile the evidence, then resume the
same campaign directory.

## Process management choice

We considered macOS [launchd](https://support.apple.com/guide/terminal/script-management-with-launchd-apdc6c1077b-5d5d-4d35-9c19-60f2397b2369/mac)
for machine-managed services. This campaign already runs two detached Python
commands; a small wrapper around the existing
[subprocess API](https://docs.python.org/3/library/subprocess.html) is sufficient
to make those commands repeatable without installing machine-wide services or
automatically restarting integrity failures. It uses the existing project helpers
for locking and atomic receipts and adds no dependency. A reboot still requires
an explicit start; this command does not install a login service.
