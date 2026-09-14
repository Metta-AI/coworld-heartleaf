# Heartleaf live dashboard

Start the local, read-only dashboard from the repository root:

```bash
python3 eval/tools/heartleaf_campaign_dashboard.py \
  --campaign tmp/heartleaf-eval/20260909-candidate-campaign \
  --port 8765
```

Open <http://127.0.0.1:8765>. The browser refreshes every ten seconds. It shows
completed rounds (including the baseline), current-round completed games and
roster, full-round candidate coverage, controller/monitor process checks, spend
freshness, and a sortable, filterable performance table with elimination history.

The server binds only to localhost and serves exactly `/` and `/api/status`.
It needs no credentials, makes no platform requests, and cannot launch, pause,
or cancel games. It does not serve raw logs, replay files, or response bodies.
Keep it local; this is not an authenticated production web service.

## Data contract

- `campaign.json` supplies the candidate queue, round paths, roster and recorded
  elimination decisions. Process health comes from actual process inspection,
  not the campaign status string alone.
- `baseline-records.json` supplies the recovered, frozen baseline. Other rounds
  use immutable `games/*/latest.json` generation summaries.
- Only completed, measurement-verified seven-day evaluation games contribute to
  performance. Duplicate request IDs are excluded. A partial current round's
  verified games appear immediately, before the controller finishes that round.
- All candidates are visible, including untested candidates. Baseline models
  outside the candidate list are retained and identified by their model tooltip.
- Scores and inference costs are pooled across games; score/game and $/score use
  those totals. Billing gaps stay unknown and are counted. Zero-score $/score is
  undefined. Compute is included only in the separate new-spend card.
- Failure columns show counts divided by each model's completed verified game count,
  using the five campaign selection categories. Other unusable, unpriced calls,
  and unreported calls also display per game. Untested models show no value.
  The API retains cumulative totals alongside explicit `_per_game` fields.
  Campaign elimination decisions still use the previous full round's totals. Other unusable
  outcomes remain separate. Latency percentiles pool raw platform call latencies from each immutable
  generation, including baseline sources; the sample count is explicit. Missing
  raw files do not fabricate latency samples. Max latency is the maximum observed
  call latency. Unreported game calls are separate from unpriced platform calls.
- Elimination reasons come from recorded round decisions; a returning model can
  be Current while retaining its previous elimination history. The history lists
  each elimination separately, sorted by round (oldest first), then reason, then
  model name. An elimination for both reasons retains both labels.
- Overall performance is descriptive: models have unequal game counts and faced
  different opponents. It is not a controlled global ranking.

A failed refresh leaves the last view visible with an explicit stale-data error.
Spend older than two minutes is also flagged. A stopped dashboard does not affect
experiments; restart it with the same command. New launch operations live in
`eval/tools/heartleaf_campaign_ops.py`; the dashboard remains observation-only.

## Design choice and validation

[Streamlit timed fragments](https://docs.streamlit.io/develop/api-reference/execution-flow/st.fragment)
provide a maintained dashboard framework, but installing its dependency stack is
unnecessary for these two read-only routes. This tool uses the existing Python
[HTTP server library](https://docs.python.org/3/library/http.server.html) and a
small browser table, with no new dependencies or asynchronous Python code.

```bash
python3 -m unittest discover -s eval/tests -p 'test_heartleaf_campaign_dashboard.py'
```
