# Provisional Heartleaf campaign report

The September 9–11 campaign report lives at
`tmp/heartleaf-eval/20260911-final-report/index.html`. It includes all 35 candidates
and six user-selected models, a sortable final table without a Status column,
transcript-backed methodology, and per-model interpretation with raw evidence
links. Open the HTML directly; the live dashboard is not required.

`eval/tools/heartleaf_campaign_report_data.py` collects the selected completed game
snapshots into one directory and builds JSON/CSV metrics and model dossiers. It
reuses experiment hash validation and dashboard metric definitions. The native
replay reader emits joins/chats/records JSON; it decodes recorded dialogue without
re-simulation. The report directory's README describes the reader and commands.

`eval/tools/heartleaf_campaign_report_html.py REPORT_DIRECTORY` renders the offline
HTML from collected data plus `model-analysis.json`, `methodology.html`, and
`decision-evidence.json`. The prose is reviewed analysis, not automatically
inferred rationale. Decision excerpts come from session-search. Re-render after
editing editorial inputs; do not silently modify the historical evidence.

Metrics remain descriptive. Unequal opponents and exposure, the one-soul design,
missing billing, partial action logs and shared infrastructure errors are
explicit limitations. Request rejection and malformed response remain outside
the historical five-category elimination sum and are shown as other unusable.

The report supports collapsible model sections, model links, and a
collapsed panel of numeric column thresholds. Active bounds exclude null values.

`eval/tools/heartleaf_report_reconcile.py REPORT_DIRECTORY` applies saved billing
evidence from `data/reconciliation/` before rendering. It includes provider-only
generations, keeps explicit nonbillable provider errors separate from missing
bills, and allocates shared compute equally across nine seats. It preserves raw
snapshots and frozen selection decisions. Five transport calls remain unresolved;
no zero charges are fabricated for them. Read the bundled README for retrieval
provenance and rebuild order.

The report additionally requires `reasoning-analysis.json`, the indexed response
sample, and `reconciliation.html`. It explains the exhausted OpenRouter key caps
behind the late 403-to-500 errors, PostHog content coverage, and conflicting
prompt objectives. These authored conclusions must be reviewed against the
linked evidence when refreshed.

The report is provisional. Its existing artifact path is retained for stable
links. Rounds 8 and 9 have an explicit incident section and prominent limitation
notice; replacement runs are deferred. The original observations remain in the
table, and the incident section links the three assigned Bugs tasks.

The table also includes cumulative input/output tokens and score per output token.
The reconciler includes provider-only calls and cached input; separately reported
reasoning tokens are not added to output a second time. Score/output uses pooled
totals and is null at zero output. Missing provider usage remains an explicit gap.

The Columns panel supports individual visibility controls and Key metrics / Show
all presets. The user’s seven priority metrics follow Model; remaining columns
are grouped by category. Hidden columns retain sorting/filtering semantics.

The report groups findings, the table and response-archive interpretation before
the incident and billing sections. Methodology and round history lead into a
shared Individual model analyses section; transcripts and downloads follow.
Navigation follows this reading order. Section-order changes preserve all
existing prose rather than summarizing or compressing it.

The closing Future Work / Open Questions section is authored in `future-work.html`
and appended after downloads. It covers additional souls, replacement rounds 8/9,
and controlled comparisons of our serving path with direct OpenRouter requests
to investigate latency and reliability. It records proposed work, not launched runs.
