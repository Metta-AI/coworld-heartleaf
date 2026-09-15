"""Apply captured billing evidence to the report; preserve original snapshots.

Inputs are the timestamped Observatory and OpenRouter reads in data/reconciliation.
No network calls or production writes occur here. Decimal arithmetic preserves
provider amounts; shared job compute is allocated equally to its nine seats.
"""
import csv
import json
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path
import argparse


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2, default=str) + '\n')


def reconcile(root):
    data = root / 'data'
    evidence = data / 'reconciliation'
    games = read(data / 'games.json')
    models = read(data / 'models.json')
    attempts = read(evidence / 'attempts.json')
    providers = read(evidence / 'providers.json') + read(evidence / 'unmatched-provider-details.json')
    assert len({p['generation_id'] for p in providers}) == len(providers)
    by_call = defaultdict(list)
    for provider in providers:
        by_call[provider['platform_call_id']].append(provider)
    attempts_by_id = {a['platform_call_id']: a for a in attempts}
    jobs = {j: g for g in games for j in g['job_attempt_ids']}
    compute = {c['id']: Decimal(str(c['compute_usd'])) for c in read(evidence / 'compute.json')}
    assert set(compute) == set(jobs) and len(jobs) == 50
    lookups = {x['platform_call_id']: x for x in read(evidence / 'provider-lookups.json')}
    ledger = []
    for call_id in sorted(set(attempts_by_id) | set(by_call)):
        attempt = attempts_by_id.get(call_id)
        rows = by_call[call_id]
        metadata = attempt['request_metadata'] if attempt else rows[0]['request_metadata']
        game = jobs[metadata['job_request_id']]
        slot = int(metadata['slot'])
        model = next(s['expected_model'] for s in game['seats'] if s['slot'] == slot)
        cost = sum((Decimal(p['billed_cost_usd']) for p in rows if p['billed_cost_usd'] is not None), Decimal(0))
        classification = 'provider_billed'
        if not rows or any(p['billed_cost_usd'] is None for p in rows):
            body = read(evidence / 'bodies' / (call_id + '.json'))['provider_response']
            if isinstance(body, str):
                try:
                    body = json.loads(body)
                except ValueError:
                    body = None
            if isinstance(body, dict) and body.get('type') == 'error' and body.get('error'):
                assert not rows or lookups[call_id]['status_code'] == 404
                # Zero is a policy-based classification of an explicit provider
                # error, not a fabricated provider invoice or a 404-only inference.
                classification = 'provider_error_zero_by_policy'
            else:
                classification = 'unresolved_transport'
                cost = None
        ledger.append(dict(platform_call_id=call_id, generation_ids=[p['generation_id'] for p in rows],
                           job_id=metadata['job_request_id'], game=game['report_game'], round=game['round'],
                           model=model, slot=slot, inference_usd=None if cost is None else str(cost),
                           classification=classification, attempt_present=attempt is not None,
                           attempt_error=attempt['error_type'] if attempt else None,
                           input_tokens=sum(p['input_tokens'] + p['cache_read_tokens'] + p['cache_write_tokens'] for p in rows) if rows else None,
                           output_tokens=sum(p['output_tokens'] for p in rows) if rows else None,
                           reasoning_tokens=sum(p['reasoning_tokens'] for p in rows) if rows else None))
    save(evidence / 'ledger.json', ledger)
    per_seat = defaultdict(list)
    for row in ledger:
        per_seat[(row['game'], row['slot'])].append(row)
    def costs(rows):
        return sum((Decimal(x['inference_usd']) for x in rows if x['inference_usd'] is not None), Decimal(0))
    for game in games:
        for seat in game['seats']:
            rows = per_seat[(game['report_game'], seat['slot'])]
            seat['provider_cost_usd'] = {'known': float(costs(rows)), 'missing': sum(r['inference_usd'] is None for r in rows)}
        game['provider_cost_usd'] = {'known': sum(s['provider_cost_usd']['known'] for s in game['seats']),
                                     'missing': sum(s['provider_cost_usd']['missing'] for s in game['seats'])}
        game['compute_usd'] = float(sum(compute[j] for j in game['job_attempt_ids']))
        save(root / game['report_directory'] / 'campaign-summary.json', game)
    for model in models:
        rows = [r for r in ledger if r['model'] == model['model']]
        cost = costs(rows)
        game_ids = {r['game'] for r in rows}
        shared = sum((compute[j] / 9 for j, g in jobs.items() if g['report_game'] in game_ids), Decimal(0))
        model.update(known_inference_usd=float(cost), inference_usd_exact=str(cost), compute_usd=float(shared),
                     known_total_usd=float(cost + shared), calls=len(rows),
                     unpriced_calls=sum(r['inference_usd'] is None for r in rows),
                     policy_zero_calls=sum(r['classification'] == 'provider_error_zero_by_policy' for r in rows),
                     provider_only_calls=sum(not r['attempt_present'] for r in rows))
        for key in ('input_tokens', 'output_tokens', 'reasoning_tokens'):
            model[key] = sum(r[key] for r in rows if r[key] is not None)
        model['calls_without_token_usage'] = sum(r['input_tokens'] is None for r in rows)
        model['score_per_output_token'] = model['score'] / model['output_tokens'] if model['output_tokens'] else None
        model['unpriced_calls_per_game'] = model['unpriced_calls'] / model['games']
        model['policy_zero_calls_per_game'] = model['policy_zero_calls'] / model['games']
        model['usd_per_score'] = float(cost) / model['score'] if model['score'] else None
        model['total_usd_per_score'] = float(cost + shared) / model['score'] if model['score'] else None
        path = data / 'models' / (''.join(c if c.isascii() and (c.isalnum() or c in '_-') else '_' for c in model['model']) + '.json')
        dossier = read(path)
        dossier['metrics'] = model
        for g in dossier['games']:
            rr = [r for r in rows if r['game'] == g['game']]
            for key in ('input_tokens', 'output_tokens', 'reasoning_tokens'):
                g[key] = sum(r[key] for r in rr if r[key] is not None)
            g['calls_without_token_usage'] = sum(r['input_tokens'] is None for r in rr)
            g['known_inference_usd'] = float(costs(rr))
            g['unpriced_calls'] = sum(r['inference_usd'] is None for r in rr)
        save(path, dossier)
    inference = costs(ledger)
    compute_total = sum(compute.values(), Decimal(0))
    spend = dict(observed_at=read(evidence / 'audit.json')['retrieved_at'], request_ids=[g['request_id'] for g in games],
                 active_request_ids=[], games=50, calls=len(ledger), provider_generations=len(providers),
                 known_inference_usd=float(inference), inference_usd_exact=str(inference),
                 known_compute_usd=float(compute_total), compute_usd_exact=str(compute_total),
                 known_total_usd=float(inference + compute_total), total_usd_exact=str(inference + compute_total),
                 classifications=dict(Counter(r['classification'] for r in ledger)),
                 unpriced_calls=sum(r['inference_usd'] is None for r in ledger), missing_compute_jobs=0,
                 complete_invoice_reconciliation=not any(r['inference_usd'] is None for r in ledger))
    save(data / 'spend.json', spend)
    save(data / 'games.json', games)
    save(data / 'models.json', models)
    with (data / 'models.csv').open('w', newline='') as f:
        columns = [k for k, v in models[0].items() if not isinstance(v, (dict, list))]
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction='ignore')
        writer.writeheader(); writer.writerows(models)
    print(json.dumps(spend, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    reconcile(parser.parse_args().report)
