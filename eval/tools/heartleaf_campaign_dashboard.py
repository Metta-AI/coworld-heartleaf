"""Serve a read-only campaign dashboard on localhost without service credentials."""
import argparse
from collections import Counter
from datetime import datetime, timezone
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import math
import statistics
from pathlib import Path
import subprocess

FAILURES = ('deadline_exceeded', 'token_limit', 'empty_response', 'invalid_action', 'upstream_error')


def read_json(path):
    return json.loads(path.read_text())


@lru_cache(maxsize=256)
def immutable_summary(path):
    return read_json(Path(path))


def process_status(directory, filename, expected):
    path = directory / filename
    if not path.exists():
        return {'live': False, 'pid': None}
    pid = int(read_json(path)['pid'])
    process = subprocess.run(['ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True)
    return {'live': process.returncode == 0 and expected in process.stdout and str(directory.resolve()) in process.stdout, 'pid': pid}


def snapshot(directory):
    state = read_json(directory / 'campaign.json')
    current = state['rounds'][-1]
    roster = current.get('roster', [r['model'] for r in current.get('metrics', [])])
    records = []
    call_paths = {}
    sources_path = directory / 'baseline-sources.json'
    baseline_sources = read_json(sources_path) if sources_path.exists() else []
    games = []
    warnings = []
    completed_rounds = []
    seen = set()
    for round_ in state['rounds']:
        number = round_['round']
        if number == 0:
            summaries = [(r, None) for r in read_json(directory / 'baseline-records.json')]
            for (record, _), source in zip(summaries, baseline_sources):
                call_paths[record['request_id']] = Path(source['generation']) / 'calls.json'
        else:
            summaries = []
            experiment = Path(round_['experiment']).parent
            for pointer in sorted(experiment.glob('games/*/latest.json')):
                generation = pointer.parent / read_json(pointer)['generation']
                record = immutable_summary(str(generation / 'summary.json'))
                if record.get('kind') == 'evaluation':
                    summaries.append((record, pointer.parent.name))
                    call_paths[record['request_id']] = generation / 'calls.json'
        verified = 0
        for record, name in summaries:
            valid = record.get('status') == 'completed' and record.get('measurement_verified') is True and record.get('realized_days') == 7
            if number == current['round']:
                games.append({'game': name or record['game_id'], 'status': record['status'], 'verified': valid and record['request_id'] not in seen,
                              'calls': record.get('calls', 0), 'problems': record.get('measurement_problems', [])})
            if not valid:
                if record.get('status') == 'completed':
                    warnings.append(f"Round {number} {name}: completed but excluded until measurement is verified")
                continue
            request = record['request_id']
            if request in seen:
                warnings.append(f'Duplicate request excluded: {request}')
                continue
            seen.add(request)
            verified += 1
            records.append((number, record))
        if verified == 5:
            completed_rounds.append(number)
    history = {}
    for round_ in state['rounds']:
        for model in round_.get('removed', []):
            reasons = []
            if model in round_['highest_cost']:
                reasons.append('highest $/score')
            if model in round_['most_failures']:
                reasons.append('most failed turns')
            history.setdefault(model, []).append({'after_round': round_['round'] - 1, 'reasons': reasons})
    models = dict.fromkeys(state['candidates'] + roster + [s['expected_model'] for _, r in records for s in r['seats']])
    rows = {m: {'model': m, 'candidate': m in state['candidates'], 'games': 0, 'score': 0, 'calls': 0,
                'known_inference_usd': 0, 'unpriced_calls': 0, 'max_latency_s': None,
                'failures': 0, 'other_unusable': 0, 'unreported_calls': 0, 'latencies': [], 'eliminations': history.get(m, []),
                **dict.fromkeys(FAILURES, 0)} for m in models}
    for _, record in records:
        failures = Counter((f['slot'], f['outcome']) for f in record['unusable_responses'])
        calls_path = call_paths.get(record['request_id'])
        calls = immutable_summary(str(calls_path)) if calls_path and calls_path.exists() else []
        for seat in record['seats']:
            row = rows[seat['expected_model']]
            row['games'] += 1
            row['score'] += seat['score']
            row['calls'] += seat['calls']
            row['unreported_calls'] += seat.get('unreported_timeout_calls', 0) + seat.get('unreported_in_flight_calls', 0)
            row['latencies'].extend(float(c['latency_ms']) / 1000 for c in calls if c.get('latency_ms') is not None and int(c['slot']) == seat['slot'])
            row['known_inference_usd'] += seat['provider_cost_usd']['known']
            row['unpriced_calls'] += seat['provider_cost_usd']['missing']
            maximum = seat.get('max_s')
            if maximum is not None:
                row['max_latency_s'] = max(maximum, row['max_latency_s'] or 0)
            for (slot, outcome), count in failures.items():
                if slot == seat['slot']:
                    if outcome in FAILURES:
                        row[outcome] += count
                        row['failures'] += count
                    else:
                        row['other_unusable'] += count
    for model, row in rows.items():
        times = sorted(row.pop('latencies'))
        row['latency_samples'] = len(times)
        row['p50_s'] = statistics.median(times) if times else None
        row['p95_s'] = times[math.ceil(len(times) * .95) - 1] if times else None
        for field in (*FAILURES, 'failures', 'other_unusable', 'unpriced_calls', 'unreported_calls'):
            row[field + '_per_game'] = row[field] / row['games'] if row['games'] else None
        row['score_per_game'] = row['score'] / row['games'] if row['games'] else None
        row['usd_per_score'] = row['known_inference_usd'] / row['score'] if row['score'] > 0 else None
        row['status'] = 'Current' if model in roster else 'Eliminated' if row['eliminations'] else 'Tested' if row['games'] else 'Untested'
    spend = read_json(directory / 'spend-latest.json') if (directory / 'spend-latest.json').exists() else {}
    now = datetime.now(timezone.utc)
    age = (now - datetime.fromisoformat(spend['observed_at'])).total_seconds() if spend else None
    tested = {s['expected_model'] for n, r in records if n in completed_rounds for s in r['seats']}
    return {'updated_at': now.isoformat(), 'campaign_status': state['status'], 'current_round': current['round'],
            'rounds_completed': len(completed_rounds), 'new_rounds_completed': sum(n > 0 for n in completed_rounds),
            'current_games_completed': sum(g['verified'] for g in games), 'games': games, 'roster': roster,
            'candidate_count': len(state['candidates']), 'candidates_tested_full_round': len(tested.intersection(state['candidates'])),
            'rows': sorted(rows.values(), key=lambda r: (-(r['score_per_game'] or 0), r['model'])),
            'controller': process_status(directory, 'launch.json', 'heartleaf_eval_campaign.py'),
            'spend_monitor': process_status(directory, 'monitor-launch.json', 'heartleaf_eval_campaign_budget.py'),
            'spend': {k: spend.get(k) for k in ('observed_at', 'known_new_spend_usd', 'unpriced_calls', 'limit_usd')},
            'spend_age_seconds': age, 'budget_paused': read_json(directory / 'spend-policy.json').get('paused', False) if (directory / 'spend-policy.json').exists() else None, 'warnings': warnings}


HTML = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Heartleaf · Live evaluation</title>
<style>
:root{font:14px system-ui;color:#d9e4ed;background:#0c141d}body{margin:0;padding:32px}h1{font-size:28px;margin:4px 0 10px}h2{font-size:18px}p{color:#94a8bb}.eyebrow{color:#66dab2;text-transform:uppercase;letter-spacing:2px;font-size:11px}.cards{display:flex;gap:16px;flex-wrap:wrap;margin:24px 0}.card{background:#15222e;border:1px solid #2a3c4d;padding:20px;border-radius:12px;min-width:160px;flex:1}.big{font-size:30px;margin-bottom:6px}.muted{color:#94a8bb}.bad{color:#ffbd82}.good{color:#66dab2}#roster{display:flex;flex-wrap:wrap;gap:8px}.chip{border:1px solid #30465a;border-radius:6px;padding:7px 10px}.scroll{overflow:auto;border:1px solid #293b4b;border-radius:10px}table{border-collapse:collapse;width:100%;white-space:nowrap}th,td{padding:11px 12px;text-align:right;border-bottom:1px solid #263542}th{background:#1a2b39;font-size:12px;cursor:pointer}td:first-child,th:first-child{text-align:left;position:sticky;left:0;background:#14212d}td:nth-child(2){text-align:left}tr.eliminated{color:#a5afba}tr.current td:first-child{border-left:3px solid #66dab2}input,select{background:#15222e;color:#d9e4ed;border:1px solid #395269;padding:9px;border-radius:6px;margin:0 10px 14px 0}details{margin:24px 0}li{margin:8px 0}#error{color:#ffbd82}footer{color:#94a8bb;font-size:12px;line-height:1.7;margin-top:18px}.status{font-size:12px}button{cursor:pointer}a{color:#66dab2}
</style><div class="eyebrow">Heartleaf / soul × model benchmark</div><h1>Live evaluation</h1><div id="health" class="status">Loading campaign…</div><p id="error"></p><div id="cards" class="cards"></div><h2>Current roster</h2><div id="roster"></div><p id="games"></p><h2>Model performance so far</h2><input id="search" placeholder="Filter model…" aria-label="Filter model"><select id="scope" aria-label="Filter status"><option value="">All models</option><option>Current</option><option>Eliminated</option><option>Untested</option></select><div class="scroll"><table><thead id="head"></thead><tbody id="body"></tbody></table></div><footer>Aggregates include baseline and every completed, verified seven-day game, including partial current rounds. Different opponents and unequal game counts mean this is descriptive, not a controlled overall ranking.<br>Costs are known inference charges only; $/score = pooled known inference cost ÷ pooled score. Missing bills remain unknown. New spend above includes compute and excludes baseline. Latency percentiles pool available raw platform call latencies; sample count is shown. Max latency is the maximum observed call latency. Unreported calls are separate from unpriced platform calls.<br>Failures count deadline misses + token-limit hits + empty responses + invalid actions + upstream errors. Failure and other unusable columns show counts per completed verified game. Unpriced and unreported calls are also per game. Other unusable outcomes stay separate. Submitted games always finish; the budget guard affects new launches only.</footer><details><summary>Elimination history</summary><ul id="history"></ul></details><p id="fresh" class="status muted"></p>
<script>
let data=null,sort='score_per_game',direction=-1;
const cols=[['model','Model'],['status','Status'],['games','Games'],['score_per_game','Score/game'],['score','Total score'],['known_inference_usd','Inference $'],['usd_per_score','$/score'],['calls','Calls'],['p50_s','p50 s'],['p95_s','p95 s'],['max_latency_s','Max latency s'],['failures_per_game','Failed turns/game'],['deadline_exceeded_per_game','Deadline/game'],['token_limit_per_game','Token limit/game'],['empty_response_per_game','Empty/game'],['invalid_action_per_game','Invalid/game'],['upstream_error_per_game','Upstream/game'],['other_unusable_per_game','Other unusable/game'],['unpriced_calls_per_game','Unpriced calls/game'],['unreported_calls_per_game','Unreported calls/game'],['latency_samples','Latency samples']];
function el(tag,text,cls){let e=document.createElement(tag);e.textContent=text;if(cls)e.className=cls;return e}
function fmt(v,k){if(v===null||v===undefined)return '—';if(typeof v==='number')return v.toLocaleString(undefined,{maximumFractionDigits:k==='usd_per_score'?5:k.includes('usd')?3:(k.includes('latency')||k==='p50_s'||k==='p95_s')?2:k.endsWith('_per_game')?2:0});return v}
function render(){let d=data;document.getElementById('health').textContent=`Controller ${d.controller.live?'running':'not running'} (PID ${d.controller.pid??'—'}) · Spend monitor ${d.spend_monitor.live?'running':'not running'} · Campaign: ${d.campaign_status} · Budget launches: ${d.budget_paused?'PAUSED':'allowed'}`;let cards=document.getElementById('cards');cards.replaceChildren();for(let [v,label] of [[`${d.rounds_completed}`,`Rounds complete (${d.new_rounds_completed} new + baseline)`],[`${d.current_games_completed}/5`,`Games complete · round ${d.current_round}`],[`${d.candidates_tested_full_round}/${d.candidate_count}`,'Candidates with full round'],['$'+fmt(d.spend.known_new_spend_usd,'usd'),'Known new spend · $'+(d.spend.limit_usd??1500)+' limit']]){let c=el('div','','card');c.append(el('div',v,'big'),el('div',label,'muted'));cards.append(c)}document.getElementById('roster').replaceChildren(...d.roster.map(m=>el('span',m,'chip')));document.getElementById('games').textContent=d.games.map(g=>`${g.game}: ${g.status}${g.verified?' ✓':''} (${g.calls} calls)`).join(' · ');let q=document.getElementById('search').value.toLowerCase(),scope=document.getElementById('scope').value;let rows=d.rows.filter(r=>r.model.toLowerCase().includes(q)&&(!scope||r.status===scope)).sort((a,b)=>{let av=a[sort],bv=b[sort];if(av===null)return 1;if(bv===null)return -1;return direction*(typeof av==='string'?av.localeCompare(bv):av-bv)});document.getElementById('body').replaceChildren(...rows.map(r=>{let tr=el('tr','',r.status.toLowerCase());for(let [key]of cols){let td=el('td',fmt(r[key],key));if(key==='model'&&!r.candidate)td.title='Baseline model outside candidate list';tr.append(td)}return tr}));document.getElementById('history').replaceChildren(...d.rows.flatMap(r=>r.eliminations.map(h=>({model:r.model,round:h.after_round,reason:h.reasons.join(' + ')}))).sort((a,b)=>a.round-b.round||a.reason.localeCompare(b.reason)||a.model.localeCompare(b.model)).map(h=>el('li',`After round ${h.round} · ${h.reason} · ${h.model}`)));document.getElementById('fresh').textContent=`Dashboard refreshed ${new Date(d.updated_at).toLocaleTimeString()} · Spend observed ${d.spend.observed_at?new Date(d.spend.observed_at).toLocaleTimeString():'unknown'} (${Math.round(d.spend_age_seconds??0)}s ago) · Refresh every 10 seconds`;document.getElementById('error').textContent=[...d.warnings,...(d.spend_age_seconds>120?['Spend snapshot is stale.']:[])].join(' · ')}
let hr=document.createElement('tr');for(let [k,label]of cols){let th=el('th',label);th.onclick=()=>{direction=sort===k?-direction:-1;sort=k;render()};hr.append(th)}document.getElementById('head').append(hr);document.getElementById('search').oninput=()=>render();document.getElementById('scope').onchange=()=>render();async function refresh(){try{let r=await fetch('/api/status',{cache:'no-store'});if(!r.ok)throw Error('Snapshot unavailable');data=await r.json();render()}catch(e){document.getElementById('error').textContent='Refresh failed; displayed data may be stale. '+e.message}setTimeout(refresh,10000)}refresh();
</script></html>'''


def handler(directory):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/':
                body, content_type = HTML.encode(), 'text/html; charset=utf-8'
            elif self.path == '/api/status':
                try:
                    body = json.dumps(snapshot(directory), allow_nan=False).encode()
                except (OSError, ValueError, KeyError):
                    self.send_error(503, 'Campaign snapshot unavailable')
                    return
                content_type = 'application/json'
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            pass
    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign', type=Path, required=True)
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    server = HTTPServer(('127.0.0.1', args.port), handler(args.campaign.resolve()))
    print(f'Heartleaf dashboard: http://127.0.0.1:{server.server_port}', flush=True)
    server.serve_forever()
