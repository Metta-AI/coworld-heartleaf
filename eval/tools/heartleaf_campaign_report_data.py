"""Collect immutable campaign evidence and model dossiers for a final report.

Uses the campaign's existing normalization and hash checks. The optional replay
reader must emit joins/chats/records JSON using Heartleaf's native replay codec.
"""
import argparse
import ast
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

import heartleaf_campaign_dashboard as dashboard
import heartleaf_eval_experiment as experiment


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def slug(model):
    return re.sub(r'[^a-zA-Z0-9_-]', '_', model)


def decoded_game_log(path):
    raw = path.read_text()
    if '===== container: game =====' in raw:
        raw = raw.split('===== container: game =====', 1)[1].split('===== container:', 1)[0].strip()
    if raw.startswith(("b'", 'b"')):
        value = ast.literal_eval(raw)
        return value.decode('utf-8')
    return raw


def collect(campaign, output, decoder):
    state = dashboard.read_json(campaign / 'campaign.json')
    snapshot = dashboard.snapshot(campaign)
    assert state['status'] == 'complete' and not snapshot['warnings']
    models = {r['model']: {k: v for k, v in r.items() if k != 'status'} for r in snapshot['rows']}
    dossiers = {m: {'model': m, 'games': [], 'actions': [], 'dialogue': [], 'failures': []} for m in models}
    sources = dashboard.read_json(campaign / 'baseline-sources.json')
    baseline = dashboard.read_json(campaign / 'baseline-records.json')
    manifest, records = [], []
    seen = set()
    for rnd in state['rounds']:
        number = rnd['round']
        if number == 0:
            pairs = list(zip(baseline, [Path(s['generation']) for s in sources]))
        else:
            root = Path(rnd['experiment']).parent
            summaries = experiment.latest_records(root)
            pairs = [(r, root / 'games' / r['game_id'] / dashboard.read_json(root / 'games' / r['game_id'] / 'latest.json')['generation']) for r in summaries]
            write_json(output / 'data' / f'round-{number:02d}-experiment.json', dashboard.read_json(root / 'experiment.json'))
        assert len(pairs) == 5
        for index, (record, source) in enumerate(pairs, 1):
            assert record['request_id'] not in seen
            seen.add(record['request_id'])
            assert record['status'] == 'completed' and record['measurement_verified'] and record['realized_days'] == 7
            key = f'r{number:02d}-g{index}'
            target = output / 'data' / 'games' / key
            target.mkdir(parents=True, exist_ok=True)
            for file in source.iterdir():
                if file.is_file():
                    shutil.copy2(file, target / file.name)
                    manifest.append({'path': str((target / file.name).relative_to(output)), 'source': str(file.resolve()), 'sha256': hashlib.sha256(file.read_bytes()).hexdigest(), 'bytes': file.stat().st_size})
            # The recovered baseline's canonical summary is the campaign copy.
            write_json(target / 'campaign-summary.json', record)
            raw = dashboard.read_json(target / 'results')
            assert raw['scores'] == [s['score'] for s in record['seats']]
            log = decoded_game_log(target / 'logs')
            (target / 'game.log').write_text(log)
            replay_path = target / 'dialogue.json'
            if decoder:
                decoded = json.loads(subprocess.check_output([str(decoder.resolve()), str(target / 'replay')]))
                write_json(replay_path, decoded)
            else:
                decoded = dashboard.read_json(replay_path)
            slots = {j['player']: j['slot'] for j in decoded['joins']}
            assert set(slots.values()) == set(range(9))
            names = raw['playerNames']
            events = raw.get('evaluation', {}).get('events', [])
            record = record | {'round': number, 'report_game': key, 'source_directory': str(source.resolve()), 'report_directory': str(target.relative_to(output))}
            records.append(record)
            for seat in record['seats']:
                model, slot = seat['expected_model'], seat['slot']
                failures = [f for f in record['unusable_responses'] if f['slot'] == slot]
                counts = Counter(f['outcome'] for f in failures)
                actions = []
                for line_number, line in enumerate(log.splitlines(), 1):
                    match = re.search(r'^' + re.escape(names[slot]) + r': llm action (\w+)(.*)', line)
                    if match:
                        actions.append({'game': key, 'line': line_number, 'action': match[1], 'text': line, 'source': f'data/games/{key}/game.log'})
                chats = [c | {'game': key, 'slot': slot, 'source': f'data/games/{key}/dialogue.json'} for c in decoded['chats'] if slots[c['player']] == slot]
                samples = [c for c in dashboard.read_json(target / 'calls.json') if int(c['slot']) == slot]
                game = {'game': key, 'round': number, 'request_id': record['request_id'], 'slot': slot, 'gnome': names[slot],
                        'score': seat['score'], 'calls': seat['calls'], 'known_inference_usd': seat['provider_cost_usd']['known'],
                        'unpriced_calls': seat['provider_cost_usd']['missing'], 'failures': dict(counts),
                        'applied_actions': seat['applied_actions'], 'logged_actions': len(actions), 'dialogue_lines': len(chats),
                        'logged_reply_lines': len(re.findall(r'^' + re.escape(names[slot]) + r': llm reply ', log, re.M)),
                        'expected_reply_lines': seat['parsed_replies'] + seat['unusable_replies'],
                        'input_tokens': sum(c.get('input_tokens') or 0 for c in samples),
                        'output_tokens': sum(c.get('output_tokens') or 0 for c in samples),
                        'reasoning_tokens': sum(c.get('reasoning_tokens') or 0 for c in samples),
                        'local_rate_limit_rejections': seat.get('local_rate_limit_rejections', 0),
                        'platform_errors': dict(Counter(str(c.get('error_type')) for c in samples if not c.get('ok')))}
                dossiers[model]['games'].append(game)
                dossiers[model]['actions'].extend(actions)
                dossiers[model]['dialogue'].extend(chats)
                dossiers[model]['failures'].extend(f | {'game': key, 'source': f'data/games/{key}/campaign-summary.json'} for f in failures)
            print(key, 'collected', flush=True)
    assert len(seen) == 50
    for model, dossier in dossiers.items():
        row = models[model]
        row['rounds'] = sorted({g['round'] for g in dossier['games']})
        row['min_score'] = min(g['score'] for g in dossier['games'])
        row['max_score'] = max(g['score'] for g in dossier['games'])
        row['action_counts'] = dict(Counter(a['action'] for a in dossier['actions']))
        row['dialogue_lines'] = len(dossier['dialogue'])
        row['logged_actions'] = len(dossier['actions'])
        row['applied_actions'] = sum(g['applied_actions'] for g in dossier['games'])
        row['local_rate_limit_rejections'] = sum(g['local_rate_limit_rejections'] for g in dossier['games'])
        row['errors'] = dict(Counter((f['outcome'] + ': ' + f.get('error', ''))[:240] for f in dossier['failures']))
        dossier['metrics'] = row
        write_json(output / 'data' / 'models' / (slug(model) + '.json'), dossier)
    write_json(output / 'data' / 'models.json', list(models.values()))
    write_json(output / 'data' / 'games.json', records)
    write_json(output / 'data' / 'campaign.json', state)
    write_json(output / 'data' / 'spend.json', dashboard.read_json(campaign / 'spend-latest.json'))
    write_json(output / 'data' / 'source-manifest.json', manifest)
    with (output / 'data' / 'models.csv').open('w') as stream:
        fields = [k for k, v in next(iter(models.values())).items() if not isinstance(v, (dict, list))]
        writer = csv.DictWriter(stream, fields, extrasaction='ignore'); writer.writeheader(); writer.writerows(models.values())
    return models


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--replay-reader', type=Path)
    args = parser.parse_args()
    collect(args.campaign, args.output, args.replay_reader)
