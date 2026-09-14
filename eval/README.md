# Heartleaf model evaluation

Everything in this directory is operator tooling for evaluating which hosted
language models play Heartleaf well, and at what cost. It is separate from the
game: nothing here is compiled into the Heartleaf binary or its Docker image,
and the game does not depend on it. The one connection is a handful of runtime
environment flags the game honors during evaluations (`HEARTLEAF_TIMEOUT_AS_WAIT`,
`HEARTLEAF_UNUSABLE_AS_WAIT`, `HEARTLEAF_EVAL_ARTIFACT`); those are documented in
the [main README](../README.md) because they are game behavior.

## Layout

| Path | What it is |
|---|---|
| `tools/` | The Python operator tools: batch preparation, hosted submission, experiment freezing and resumption, campaign loops, dashboards, report data collection and HTML rendering, billing reconciliation. `heartleaf_eval_duration.nim` is an offline timing bound calculator. |
| `tools/examples/` | Example experiment and budget configurations. |
| `tests/` | Unit and contract tests for the tools. Run them from the repository root (below). |
| `requirements.txt` | The pinned `coworld` and `softmax-cli` versions the tools were validated against. Install into an isolated venv, never globally. |
| `docs/` | Runbooks, the September 2026 campaign report pointer, recon notes, design documents, and the results slide deck. |

Start with these docs, in order:

1. [`docs/heartleaf_eval.md`](docs/heartleaf_eval.md): the evaluation runbook. Batch preparation, privacy and accounting gates, submission, reports.
2. [`docs/heartleaf_experiments.md`](docs/heartleaf_experiments.md): freezing an experiment, resuming hosted runs, collecting uniform results with raw evidence.
3. [`docs/heartleaf_campaign_operations.md`](docs/heartleaf_campaign_operations.md) and [`docs/heartleaf_dashboard.md`](docs/heartleaf_dashboard.md): running successive model cohorts with automatic replacement, and watching them live.
4. [`docs/heartleaf_final_report.md`](docs/heartleaf_final_report.md): what the September 9–11, 2026 campaign report contains and how to rebuild it.
5. [`docs/heartleaf-model-eval-slides.html`](docs/heartleaf-model-eval-slides.html): the seven-slide summary of that campaign. Open it in a browser.

`docs/recon/` holds dated investigation notes written during the campaign
(latency breakdowns, transport fixes, canary failures). `docs/designs/` holds the
milestone design document and implementation status. Both are historical
records, not maintained references.

## Running the tests

From the repository root:

```sh
uv venv tmp/heartleaf-eval-venv
uv pip install --python tmp/heartleaf-eval-venv/bin/python -r eval/requirements.txt
tmp/heartleaf-eval-venv/bin/python -m unittest discover -s eval/tests -p 'test_heartleaf_*.py'
```

CI runs the same discovery in the `eval-tools` job of `.github/workflows/tests.yml`.

## Where the data lives

Campaign runs, hosted job logs, collected snapshots, and the rendered report are
written under `tmp/heartleaf-eval/` at the repository root. That directory is
gitignored and several gigabytes; the tools resolve it relative to the
repository root, not to this directory. The September 2026 campaign bundle is at
`tmp/heartleaf-eval/20260911-final-report/` on the machine that ran it; see the
final report pointer above for how to regenerate the HTML from that bundle.

Frozen experiments record the SHA-256 of each `heartleaf_eval*.py` source file.
Editing a tool changes those digests, so resuming an older experiment goes
through the `revise-runner` flow described in the experiments runbook.
