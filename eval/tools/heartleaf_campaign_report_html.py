"""Render the collected final report as an offline sortable HTML document."""
import argparse
from collections import Counter
import html
import json
import re
from html.parser import HTMLParser
from pathlib import Path

from heartleaf_campaign_report_data import slug


def read(path):
    return json.loads(path.read_text())


def esc(value):
    return html.escape(str(value), quote=True)


def number(value, places=2):
    return '—' if value is None else f'{value:,.{places}f}'


def table(headers, rows):
    return '<div class="scroll"><table><thead><tr>' + ''.join(f'<th>{esc(h)}</th>' for h in headers) + '</tr></thead><tbody>' + ''.join('<tr>' + ''.join(f'<td>{esc(c)}</td>' for c in row) + '</tr>' for row in rows) + '</tbody></table></div>'


def examples(dossier):
    best = max(dossier['games'], key=lambda g: g['score'])['game']
    worst = min(dossier['games'], key=lambda g: g['score'])['game']
    chosen = []
    for action in ('bye', 'go_home', 'go_to_house'):
        matches = [a for a in dossier['actions'] if a['game'] == best and a['action'] == action]
        if matches:
            chosen.append(matches[0])
        if len(chosen) == 2:
            break
    low = [a for a in dossier['actions'] if a['game'] == worst and ('missed' in a['text'].lower() or a['action'] == 'go_to_house')]
    if low and worst != best:
        chosen.append(low[0])
    result = ''.join(f'<blockquote><p>{esc(a["text"])}</p><cite><a href="{esc(a["source"])}">{esc(a["game"])} game.log, line {a["line"]}</a></cite></blockquote>' for a in chosen)
    chats = [c for c in dossier['dialogue'] if c['game'] == best and any(w in c['message'].lower() for w in ('dinner', 'six', 'host', 'promise'))]
    if chats:
        chat = chats[len(chats) // 2]
        result += f'<blockquote><p>{esc(chat["message"])}</p><cite><a href="{esc(chat["source"])}">{best} replay dialogue, player {chat["player"]}, {chat["time_ms"]}ms</a></cite></blockquote>'
    if not chosen and not chats:
        result += '<p>No successful strategic action or spoken dialogue was recovered for this policy. A behavioral explanation would be speculative.</p>'
    return result


def model_section(model, notes, root):
    dossier = read(root / 'data/models' / (slug(model['model']) + '.json'))
    m = model
    rows = []
    for rnd in m['rounds']:
        games = [g for g in dossier['games'] if g['round'] == rnd]
        scores = [g['score'] for g in games]
        failures = Counter()
        for game in games:
            failures.update(game['failures'])
        cost = sum(g['known_inference_usd'] for g in games)
        rows.append([rnd, ', '.join(number(s, 0) for s in scores), number(sum(scores) / 5), '$' + number(cost, 4), number(cost / sum(scores), 5) if sum(scores) else 'undefined', '; '.join(f'{k}: {v}' for k, v in sorted(failures.items()))])
    pieces = [f'<details class="model" id="{slug(m["model"])}"><summary><a class="model-link" href="#{slug(m["model"])}">{esc(m["model"])}</a></summary>',
              '<p class="muted">' + ('OpenRouter candidate' if m['candidate'] else 'User-selected model outside the later candidate set') + f' · {m["games"]} games · rounds {", ".join(map(str,m["rounds"]))}</p>',
              f'<p><strong>{number(m["score_per_game"],1)} score/game</strong> (range {number(m["min_score"],0)}–{number(m["max_score"],0)}); inference ${number(m["known_inference_usd"],4)}; ${number(m["usd_per_score"],5)} per score. Platform latency p50/p95: {number(m["p50_s"])} / {number(m["p95_s"])} seconds. Selection-counted failures: {number(m["failures_per_game"],1)}/game; other unusable: {number(m["other_unusable_per_game"],1)}/game; unpriced calls: {m["unpriced_calls"]} total.</p>',
              f'<p>Allocated compute ${number(m["compute_usd"],4)}; combined cost ${number(m["known_total_usd"],4)}; combined cost/score ${number(m["total_usd_per_score"],5)}. Compute is divided equally among the nine seats.</p>' + '<h3>Interpretation</h3><p>' + esc(notes[m['model']]) + '</p>',
              '<h3>Round-by-round evidence</h3>', table(['Round', 'Five scores', 'Mean score', 'Known inference', '$/score', 'Unusable outcomes (counts)'], rows)]
    removals = '; '.join('after round ' + str(h['after_round']) + ': ' + ' + '.join(h['reasons']) for h in m['eliminations'])
    pieces.append('<p>Recorded elimination history: ' + esc(removals or 'No removal before campaign completion.') + '</p>')
    reasoning = read(root / 'data/reconciliation/reasoning-samples.json')[m['model']]
    commentary = read(root / 'reasoning-analysis.json')[m['model']]
    good = sorted([r for r in reasoning if r['ok']], key=lambda r: r['timestamp'])
    sample = good[len(good)//2] if good else reasoning[0]
    pieces.append('<h3>Response archive analysis</h3><p>' + esc(commentary) + '</p>')
    pieces.append('<p class="muted">Deterministic sample: first, middle and last platform-success responses across the model’s calls, plus each platform error category. Platform success does not guarantee a usable or timely game action. Missing thinking text means unavailable in this sample, not absence of reasoning.</p>')
    pieces.append('<details><summary>Inspect sampled response and reasoning</summary><p><a href="' + esc(sample['source']) + '">Original request and response archive</a> · call <code>' + esc(sample['id']) + '</code> · ' + number(sample['latency_s']) + ' seconds</p><h4>Returned thinking text</h4><pre>' + esc(sample['thinking'] or 'No separate thinking text in this response.') + '</pre><h4>Final output</h4><pre>' + esc(sample['text'] or 'No final text output.') + '</pre></details>')
    pieces.append('<h3>Replay and action evidence</h3>' + examples(dossier))
    errors = sorted(m['errors'].items(), key=lambda x: -x[1])[:4]
    if errors:
        pieces.append(table(['Most common diagnostic', 'Count'], errors))
    actions = ', '.join(f'{k} {v}' for k, v in sorted(m['action_counts'].items(), key=lambda x: -x[1]))
    pieces.append(f'<p class="muted">Recovered evidence: {m["dialogue_lines"]:,} replay dialogue lines and {m["logged_actions"]:,} action-log rows. Observed action rows: {esc(actions)}. These rows include synthetic waits and may cover only a log tail; they are not a complete action distribution.</p>')
    pieces.append(f'<p><a href="data/models/{slug(m["model"])}.json">Full model dossier: all recovered dialogue, actions, failures, call IDs and per-game measurements</a> · <a href="#performance">Back to table</a></p></details>')
    return ''.join(pieces)


def link_model_mentions(document, models):
    aliases = {m['model']: m['model'] for m in models}
    short = {}
    for m in models:
        short.setdefault(m['model'].split('/')[-1].lower().replace('-', ' '), []).append(m['model'])
    for name, ids in short.items():
        if len(ids) == 1:
            aliases[name] = ids[0]
    explicit = {'GPT-5.5': 'openai/gpt-5.5', 'GLM 5.3 Flash': 'z-ai/glm-5.3-flash',
                'MiMo Pro': 'xiaomi/mimo-v2.5-pro', 'Gemini 3.8 Flash': 'google/gemini-3.8-flash'}
    extra = {'Hy4 preview':'tencent/hy4-preview','Hy4':'tencent/hy4-preview','Hy3':'tencent/hy3',
             'MiniMax free':'minimax/minimax-m3:free','MiniMax M3 free':'minimax/minimax-m3:free',
             'Nemotron':'nvidia/nemotron-3-ultra-550b-a55b:free','GPT-OSS':'openai/gpt-oss-120b',
             'Laguna':'poolside/laguna-s-2.1:free','Kimi':'moonshotai/kimi-k3',
             'DeepSeek V4 Flash':'deepseek/deepseek-v4-flash','Sonnet 4.6':'anthropic/claude-sonnet-4.6',
             'Fable 5':'anthropic/claude-fable-5','Terra':'openai/gpt-5.6-terra'}
    extra.update({'Haiku':'anthropic/claude-haiku-4.5','Opus 4.6':'anthropic/claude-opus-4.6','Opus 4.8':'anthropic/claude-opus-4.8','Opus 5':'anthropic/claude-opus-5','Sonnet 4.5':'anthropic/claude-sonnet-4.5','Sonnet 5':'anthropic/claude-sonnet-5','Fable 5.1':'anthropic/claude-fable-5.1','V3.2':'deepseek/deepseek-v3.2','dated 0731 route':'deepseek/deepseek-v4-flash-0731','undated V4 Flash':'deepseek/deepseek-v4-flash','undated V4 Pro':'deepseek/deepseek-v4-pro','Flash Lite':'google/gemini-2.5-flash-lite','Gemma 26B':'google/gemma-4-26b-a4b-it','Gemma 31B':'google/gemma-4-31b-it','Luna':'openai/gpt-5.6-luna','Sol':'openai/gpt-5.6-sol','Astra':'openai/gpt-6-astra','GPT-OSS-120B':'openai/gpt-oss-120b','Qwen':'qwen/qwen3.8-max-0902','Step Flash':'stepfun/step-3.7-flash','Grok':'x-ai/grok-4.6','MiMo':'xiaomi/mimo-v2.5'})
    explicit.update(extra)
    for name, model in explicit.items():
        if model in aliases: aliases[name] = model
    lookup = {k.lower(): v for k,v in aliases.items()}
    pattern = re.compile(r'(?<![\w/-])(' + '|'.join(re.escape(k) for k in sorted(aliases,key=len,reverse=True)) + r')(?![\w/-])', re.I)
    class Linker(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=False); self.output=[]; self.blocked=[]
        def handle_starttag(self,tag,attrs):
            self.output.append(self.get_starttag_text())
            if tag in ('a','script','style','code','summary'): self.blocked.append(tag)
        def handle_endtag(self,tag):
            self.output.append('</'+tag+'>')
            if self.blocked and self.blocked[-1]==tag:self.blocked.pop()
        def handle_startendtag(self,tag,attrs):self.output.append(self.get_starttag_text())
        def handle_decl(self,decl):self.output.append('<!'+decl+'>')
        def handle_entityref(self,name):self.output.append('&'+name+';')
        def handle_charref(self,name):self.output.append('&#'+name+';')
        def handle_data(self,data):
            if not self.blocked:
                data=pattern.sub(lambda m:'<a class="model-link" href="#'+slug(lookup[m[0].lower()])+'">'+m[0]+'</a>',data)
            self.output.append(data)
    parser=Linker();parser.feed(document);return ''.join(parser.output)


def render(root):
    models = read(root / 'data/models.json')
    notes = read(root / 'model-analysis.json')
    assert set(notes) == {m['model'] for m in models}
    campaign = read(root / 'data/campaign.json')
    spend = read(root / 'data/spend.json')
    # This editorial input contains three flat sections whose prose stays intact.
    report_sections = {match.group(1): match.group(0) for match in re.finditer(
        r'<section id="([^"]+)">.*?</section>', (root / 'reconciliation.html').read_text(), re.S)}
    parts = [HEAD, '<div class="eyebrow">Heartleaf · September 9–11, 2026 · Provisional report</div><h1>One soul, 35 candidate models</h1>',
             '<p class="lede">An adaptive, cost-conscious comparison of hosted language-model policies in a social dinner game.</p>',
             '<p><strong>Provisional findings.</strong> The table includes the original 50 games. Shared OpenRouter key exhaustion compromised rounds 8 and 9 and affected the final roster. Replacement runs are deferred. Read <a href="#incident">what happened in rounds 8 and 9</a> before interpreting their scores or eliminations.</p>',
             '<nav><a href="#findings">Findings</a><a href="#performance">Sortable results</a><a href="#response-evidence">Response archives</a><a href="#incident">Rounds 8–9 incident</a><a href="#reconciliation">Costs</a><a href="#method">Methodology</a><a href="#history">Round history</a><a href="#models">Model analyses</a><a href="#decisions">Decision transcripts</a><a href="#data">Downloads</a><a href="#future-work">Future work</a></nav>',
             f'<div class="cards"><div><b>50</b>games across 10 rounds</div><div><b>35 + 6</b>candidates + other initial models</div><div><b>${spend["known_total_usd"]:,.2f}</b>accounted spend · {spend["unpriced_calls"]} calls unresolved</div><div><b>44,721</b>recovered dialogue lines</div></div>',
             '<section id="findings"><h2>What the evidence supports</h2><p><strong>The operational bottleneck matters as much as the model.</strong> Hy4 preview timed out throughout; MiniMax free was unavailable; Nemotron and GPT-OSS frequently missed deadlines; Laguna was repeatedly rate-limited. These are real outcomes for the tested routes, but they do not measure latent strategic ability under a different service contract.</p><p><strong>Several cheap policies remained competitive.</strong> GLM 5.3 Flash, MiMo Pro and undated DeepSeek V4 Flash combined substantial scores with very low known dollars per score over multiple rounds. GPT-5.5 led its final cohort on score, while Kimi and Gemini 3.8 Flash also achieved high means. Their different opponents, seats, rounds and service conditions prevent a defensible single global winner.</p><p><strong>Late infrastructure failures materially weaken comparisons.</strong> The final two rounds had widespread sidecar errors and large score drops among continuing models. Opus candidates, Sonnet 4.6 and Fable 5 were evaluated only in those affected rounds. Their observed rankings should not be presented as clean evidence of inferiority.</p><p><strong>The fixed soul requires balancing conversation with action.</strong> Useful examples leave a conversation before gathering or traveling and preserve explicit dinner commitments. Fast but error-prone policies often request travel or gathering while talking. Slow policies can state the correct plan yet fail to execute before dinner. Stated reasons are evidence of an output, not privileged access to the actual cause of a score.</p></section>',
             '<section id="performance"><h2>Model performance</h2><p>Click any column heading to sort; click a model for its detailed analysis. Failure columns are per completed game. All means pool the selected games.</p><input id="search" aria-label="Filter models" placeholder="Find a model…"><select id="scope" aria-label="Select model population"><option value="all">All 41 models</option><option value="candidate">35 candidates</option><option value="initial">6 other initial models</option></select><span id="count"></span><details id="column-visibility"><summary>Columns <span id="visible-count"></span></summary><p class="muted">Choose the columns to show. Sorting and thresholds still apply to hidden columns.</p><div id="column-choices"></div><button id="key-columns" type="button">Key metrics</button> <button id="all-columns" type="button">Show all</button></details><details id="column-filters"><summary>Column thresholds</summary><p class="muted">Inclusive minimum and maximum. Active bounds exclude missing values. Combine any columns.</p><div id="filter-fields"></div><button id="reset-filters" type="button">Clear thresholds</button></details><div class="scroll"><table id="performance-table"><thead id="head"></thead><tbody id="body"></tbody></table></div><p class="muted">Inference $/score = reconciled pooled inference cost ÷ pooled score. Total $/score includes one ninth of each shared game’s compute cost; that allocation is a convention, not measured per-model compute. Nonbillable errors are classified from original provider error bodies and the provider billing policy, not zero-valued invoices; zero score is undefined. Missing bills are not zero. p50/p95 pool recorded platform latencies, including calls finishing after abandonment. Failed turns is the exact five-category selection sum; Other unusable includes unavailable-model rejections and malformed responses. Opponents and game counts differ.</p><p class="muted">Tokens are cumulative recorded usage across each model’s games, including late and unusable generations. Input includes uncached tokens plus cache reads and writes. Output uses the provider’s output-token count; separate reasoning counts are not added again. Score/output token = pooled score ÷ recorded output tokens, undefined at zero output. Six calls have no provider usage record; their unknown tokens are not estimated.</p></section>',
             report_sections['response-evidence'], report_sections['incident'], report_sections['reconciliation'], (root / 'methodology.html').read_text(), '<section id="history"><h2>Round and elimination history</h2>']
    rows = []
    for rnd in campaign['rounds']:
        rows.append([rnd['round'], ', '.join(m['model'] for m in rnd['metrics']), ', '.join(rnd.get('highest_cost', [])), ', '.join(rnd.get('most_failures', [])), ', '.join(rnd.get('added', [])), ', '.join(rnd.get('returning_fillers', []))])
    parts.extend([table(['Round', 'Roster', 'Removed from prior round: cost', 'Removed from prior round: failures', 'New candidates', 'Returning fillers'], rows), '<p>Removal columns describe the preceding round; round 0 contains the user-selected initial roster.</p></section>'])
    parts.append('<section id="models"><h2>Individual model analyses</h2>')
    for model in models:
        parts.append(model_section(model, notes, root))
    parts.append('</section>')
    parts.append('<section id="decisions"><h2>Recorded decision evidence</h2><p>Recovered with the session-search skill after refreshing the local transcript database. Excerpts retain role, timestamp, session ID and sequence. The initial goal excerpt is the exact objective text from its stored goal message.</p>')
    for entry in read(root / 'decision-evidence.json'):
        parts.append(f'<details id="{entry["id"]}"><summary>{entry["id"]} · {entry["role"]} · {entry["timestamp"]}</summary><p><code>codex:{entry["session"]}@{entry["seq"]}</code></p><pre>{esc(entry["text"])}</pre></details>')
    parts.append('</section><section id="data"><h2>Data and reproducibility</h2><ul><li><a href="data/models.csv">Model metrics CSV</a> / <a href="data/models.json">JSON</a></li><li><a href="data/games.json">All 50 canonical game summaries</a></li><li><a href="data/campaign.json">Campaign rosters and decisions</a></li><li><a href="data/spend.json">Final spend snapshot</a></li><li><a href="data/source-manifest.json">Original artifact checksums and source paths</a></li><li><a href="decision-evidence.json">Decision transcript excerpts</a></li><li><a href="README.md">Rebuild instructions and data dictionary</a></li></ul><p>All 50 games are included. See the billing reconciliation for exact totals, independently priced provider generations, and unresolved transport outcomes.</p></section>')
    parts.append((root / 'future-work.html').read_text())
    payload = json.dumps(models, ensure_ascii=False).replace('<', '\\u003c')
    parts.append('<script id="model-data" type="application/json">' + payload + '</script>' + SCRIPT + '</body></html>')
    (root / 'index.html').write_text(link_model_mentions(''.join(parts), models))


HEAD = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Heartleaf provisional campaign report</title><style>
:root{font:15px/1.65 system-ui,sans-serif;color:#d9e4ed;background:#0c141d}body{max-width:1440px;margin:auto;padding:36px}h1{font-size:46px;line-height:1.15}h2{font-size:26px;margin-top:12px}h3{font-size:18px}a{color:#66dab2}p{max-width:1050px}.lede{font-size:20px;color:#b1c3d4}.eyebrow{color:#66dab2;text-transform:uppercase;letter-spacing:2px;font-size:12px}nav{display:flex;gap:22px;flex-wrap:wrap}.cards{display:flex;gap:16px;flex-wrap:wrap;margin:28px 0}.cards div{background:#15222e;padding:20px;border:1px solid #2a3c4d;border-radius:10px;flex:1;min-width:180px}.cards b{display:block;font-size:30px}.muted{color:#a3b5c6;font-size:13px}section{padding:24px 0;border-bottom:1px solid #2a3c4d;scroll-margin-top:16px}.scroll{overflow:auto;border:1px solid #293b4b;border-radius:8px}table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:10px;text-align:left;border-bottom:1px solid #263542;vertical-align:top}th{background:#1a2b39}#performance-table{white-space:nowrap}#performance-table td,#performance-table th{text-align:right}#performance-table td:first-child,#performance-table th:first-child{text-align:left;position:sticky;left:0;background:#14212d}th button{color:inherit;font:inherit;background:transparent;border:0;cursor:pointer}input,select{background:#15222e;color:#d9e4ed;border:1px solid #395269;padding:10px;border-radius:6px;margin:0 12px 14px 0}blockquote{border-left:3px solid #66dab2;margin:18px 0;padding:8px 18px;background:#14212d;max-width:1050px}blockquote p{margin:4px 0}cite{font-size:12px}details{margin:15px 0;background:#14212d;padding:12px}summary{cursor:pointer}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}code{overflow-wrap:anywhere;font-size:12px}#history td{min-width:180px;max-width:400px}button:focus-visible,a:focus-visible{outline:2px solid #ffbd82}.model>summary{font-size:23px;font-weight:600}.model-link{white-space:nowrap}#filter-fields{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px}#filter-fields label{display:block;font-size:12px}#filter-fields input{width:80px;margin-bottom:0}#column-filters{margin-bottom:20px}#column-choices{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:8px;margin-bottom:16px}#column-choices label{display:flex;align-items:center;gap:8px;font-size:13px;cursor:pointer}#column-choices input{margin:0}#column-visibility button,#column-filters button{background:#1a2b39;color:inherit;border:1px solid #395269;border-radius:6px;padding:7px 12px;cursor:pointer} @media print{body{color:#111;background:white}a{color:#145}section{break-inside:auto}.scroll{overflow:visible}#performance{display:none}.cards div,blockquote,th{background:#eee;color:#111}}</style></head><body>'''


SCRIPT = '''<script>
const data=JSON.parse(document.getElementById('model-data').textContent);
const cols=[["model", "Model"], ["games", "Games"], ["score_per_game", "Score/game"], ["total_usd_per_score", "Total $/score"], ["score_per_output_token", "Score/output token"], ["failures_per_game", "Failed turns/game"], ["p50_s", "p50 seconds"], ["p95_s", "p95 seconds"], ["score", "Total score"], ["known_total_usd", "Total $"], ["known_inference_usd", "Known inference $"], ["compute_usd", "Allocated compute $"], ["usd_per_score", "Inference $/score"], ["input_tokens", "Input tokens"], ["output_tokens", "Output tokens"], ["deadline_exceeded_per_game", "Deadlines/game"], ["token_limit_per_game", "Token limits/game"], ["empty_response_per_game", "Empty/game"], ["invalid_action_per_game", "Invalid actions/game"], ["upstream_error_per_game", "Upstream errors/game"], ["other_unusable_per_game", "Other unusable/game"], ["policy_zero_calls_per_game", "Nonbillable errors/game"], ["max_latency_s", "Max seconds"], ["calls", "Calls"], ["latency_samples", "Latency samples"], ["unpriced_calls_per_game", "Unresolved costs/game"], ["unreported_calls_per_game", "Unreported calls/game"]];
const visibleColumns=new Set(cols.map(([key])=>key));
let sort='score_per_game',direction=-1;
function initColumns(){
 for(const [key,label] of cols){const choice=document.createElement('label');const checkbox=document.createElement('input');checkbox.type='checkbox';checkbox.checked=true;checkbox.dataset.column=key;checkbox.onchange=()=>{if(checkbox.checked)visibleColumns.add(key);else visibleColumns.delete(key);render()};choice.append(checkbox,document.createTextNode(label));document.getElementById('column-choices').append(choice)}
 function selectColumns(keys){visibleColumns.clear();for(const key of keys)visibleColumns.add(key);for(const checkbox of document.querySelectorAll('#column-choices input'))checkbox.checked=visibleColumns.has(checkbox.dataset.column);render()}
 document.getElementById('key-columns').onclick=()=>selectColumns(cols.slice(0,8).map(([key])=>key));
 document.getElementById('all-columns').onclick=()=>selectColumns(cols.map(([key])=>key));
}
function withinBounds(row){return [...document.querySelectorAll('#filter-fields input')].every(input=>{if(input.value==='')return true;const v=row[input.dataset.column];return v!=null&&(input.dataset.bound==='min'?v>=Number(input.value):v<=Number(input.value))})}
function initFilters(){for(const [key,label] of cols.slice(1)){const field=document.createElement('div');const title=document.createElement('label');title.textContent=label;field.append(title);for(const bound of ['min','max']){const input=document.createElement('input');input.type='number';input.step='any';input.dataset.column=key;input.dataset.bound=bound;input.placeholder=bound;input.setAttribute('aria-label',label+' '+bound);input.oninput=render;field.append(input)}document.getElementById('filter-fields').append(field)}document.getElementById('reset-filters').onclick=()=>{for(const input of document.querySelectorAll('#filter-fields input'))input.value='';render()}}
function openModelHash(){const target=document.getElementById(decodeURIComponent(location.hash.slice(1)));if(target?.matches('details.model')){target.open=true;target.scrollIntoView()}}

function fmt(v,k){if(v===null||v===undefined)return '—';if(typeof v==='string')return v;return v.toLocaleString(undefined,{maximumFractionDigits:k==='score_per_output_token'?6:k.endsWith('usd_per_score')?5:k.endsWith('_usd')?4:2})}
function render(){const q=document.getElementById('search').value.toLowerCase(),scope=document.getElementById('scope').value;const rows=data.filter(r=>r.model.toLowerCase().includes(q)&&(scope==='all'||r.candidate===(scope==='candidate'))&&withinBounds(r)).sort((a,b)=>{const av=a[sort],bv=b[sort];if(av==null&&bv==null)return a.model.localeCompare(b.model);if(av==null)return 1;if(bv==null)return -1;return direction*(typeof av==='string'?av.localeCompare(bv):av-bv)||a.model.localeCompare(b.model)});document.getElementById('count').textContent=rows.length+' models';document.getElementById('body').replaceChildren(...rows.map(r=>{const tr=document.createElement('tr');for(const [key] of cols){const td=document.createElement('td');td.dataset.key=key;td.hidden=!visibleColumns.has(key);if(key==='model'){const a=document.createElement('a');a.textContent=r.model;a.href='#'+r.model.replace(/[^a-zA-Z0-9_-]/g,'_');td.append(a);a.className='model-link'}else td.textContent=fmt(r[key],key);tr.append(td)}return tr}));for(const th of document.querySelectorAll('#head th')){th.hidden=!visibleColumns.has(th.dataset.key);th.setAttribute('aria-sort',th.dataset.key===sort?(direction===1?'ascending':'descending'):'none')}document.getElementById('visible-count').textContent='· '+visibleColumns.size+' of '+cols.length+' shown'}
const header=document.createElement('tr');for(const [key,label] of cols){const th=document.createElement('th');th.dataset.key=key;const button=document.createElement('button');button.textContent=label;button.onclick=()=>{direction=sort===key?-direction:-1;sort=key;render()};th.append(button);header.append(th)}document.getElementById('head').append(header);document.getElementById('search').oninput=render;document.getElementById('scope').onchange=render;initColumns();initFilters();render();openModelHash();window.addEventListener('hashchange',openModelHash);
</script>'''


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    render(parser.parse_args().report)
