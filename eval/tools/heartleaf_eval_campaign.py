"""Run successive five-game cohorts using the existing hosted eval runner."""
import argparse
import collections
import copy
from decimal import Decimal
import json
from pathlib import Path
import subprocess
import sys

import heartleaf_eval as prepare
import heartleaf_eval_api as api
import heartleaf_eval_experiment as experiment
import heartleaf_eval_results as results

FAILURES = ('deadline_exceeded', 'token_limit', 'empty_response', 'invalid_action', 'upstream_error')


def rank_round(records):
    if len(records) != 5 or len({r['request_id'] for r in records}) != 5:
        raise ValueError('A round needs five distinct games')
    roster = [s['expected_model'] for s in records[0]['seats']]
    aggregate = {m: {'model': m, 'score': 0, 'known_inference_usd': 0,
                      'unpriced_calls': 0, 'failures': 0} for m in roster}
    for record in records:
        if not record['measurement_verified'] or record['realized_days'] != 7:
            raise ValueError('Cannot select from an incomplete measurement')
        if [s['expected_model'] for s in record['seats']] != roster:
            raise ValueError('Round roster changed')
        counts = collections.Counter(f['slot'] for f in record['unusable_responses'] if f['outcome'] in FAILURES)
        for seat in record['seats']:
            row = aggregate[seat['expected_model']]
            row['score'] += seat['score']
            row['known_inference_usd'] += seat['provider_cost_usd']['known']
            row['unpriced_calls'] += seat['provider_cost_usd']['missing']
            row['failures'] += counts[seat['slot']]
    for row in aggregate.values():
        row['known_usd_per_score'] = row['known_inference_usd'] / row['score'] if row['score'] > 0 else None
    return list(aggregate.values())


def removal_lists(rows):
    cost = sorted(rows, key=lambda r: (-(r['known_usd_per_score'] if r['known_usd_per_score'] is not None else float('inf')), r['model']))
    failures = sorted(rows, key=lambda r: (-r['failures'], r['model']))
    high_cost = [r['model'] for r in cost[:2]]
    high_failure = [r['model'] for r in failures[:2]]
    return high_cost, high_failure, list(dict.fromkeys(high_cost + high_failure))


def read_round(path):
    records = experiment.latest_records(path.parent)
    return [r for r in records if r.get('kind') == 'evaluation']


def command(args, log):
    with log.open('a') as stream:
        subprocess.run([sys.executable, *map(str, args)], check=True, stdout=stream, stderr=subprocess.STDOUT)


def prepare_round(directory, state, decision):
    template_path = Path(state['template'])
    template = api.read_json(template_path)
    batch_id = directory.name + '-r' + str(decision['round']).zfill(2)
    target = api.BATCH_ROOT / batch_id
    batch_path = target / 'batch.json'
    if not batch_path.exists():
        target.mkdir(parents=True, exist_ok=True)
        batch = copy.deepcopy(template['batch'])
        batch['batch_id'] = batch_id
        for relative in template['source_files']:
            results.atomic_bytes(target / relative, (template_path.parent / 'inputs' / relative).read_bytes())
        source = (target / batch['sources'][0]['soul_path']).read_bytes()
        for variant, model in zip(batch['variants'], decision['roster'], strict=True):
            if model != variant['model']:
                for key in ['policy_version_id', 'container_image_id', 'image_digest', 'reused_from_policy_version_id', 'local_image', 'local_image_id']:
                    variant.pop(key, None)
                variant['model'] = model
                variant['model_header'] = prepare.MODEL_HEADERS['H'] if model == prepare.MODEL_SLUGS['H'] else '#!' + model
                raw = prepare.transform_soul(source, variant['model_header'])
                results.atomic_bytes(target / variant['context'] / 'soul.md', raw)
                variant['soul_sha256'] = results.digest(target / variant['context'] / 'soul.md')
                variant['policy_name'] = 'heartleaf-eval-' + batch_id + '-' + variant['key'].lower()
        batch['schedule'] = []
        results.write_json(batch_path, batch)
    path = target / 'experiments/five-games/experiment.json'
    if not path.exists():
        command([Path(__file__).with_name('heartleaf_eval_players.py'), '--batch', batch_path], target / 'upload.log')
        config = template['parameters'] | {'seeds': [91002, 91003, 91004, 91005, 91006], 'canary_days': 0}
        results.write_json(target / 'parameters.json', config)
        path = experiment.configure(batch_path, target / 'parameters.json', 'five-games')
    if (directory / 'spend-policy.json').exists():
        results.write_json(path.parent / 'campaign-budget.json', {'campaign': str(directory)})
    return path


def run(directory):
    # Separate controller lock: the child runner takes the shared submission lock.
    with api.batch_lock(directory):
        state_path = directory / 'campaign.json'
        state = api.read_json(state_path)
        candidates = state['candidates']
        while True:
            last = state['rounds'][-1]
            if 'metrics' not in last:
                path = Path(last['experiment'])
                runner = [Path(__file__).with_name('heartleaf_eval_experiment.py'), 'run', '--experiment', path]
                log = directory / f"round-{last['round']:02d}.log"
                try:
                    command([*runner, '--max-new-games', '5', '--poll-seconds', '30'], log)
                except subprocess.CalledProcessError:
                    if not (directory / 'spend-launch-stop.json').exists():
                        raise
                    command([*runner, '--max-new-games', '0', '--poll-seconds', '30'], log)
                    state['status'] = 'awaiting_budget_approval'
                    results.write_json(state_path, state)
                    return
                records = read_round(path)
                last['metrics'] = rank_round(records)
                last['request_ids'] = [r['request_id'] for r in records]
                results.write_json(state_path, state)
            tested = {r['model'] for round_ in state['rounds'] for r in round_.get('metrics', [])}
            pending = [model for model in candidates if model not in tested]
            state['coverage'] = {'tested_candidates': [m for m in candidates if m in tested], 'pending': pending}
            results.write_json(state_path, state)
            if not pending:
                state['status'] = 'complete'
                results.write_json(state_path, state)
                print(json.dumps({'status': 'complete', 'candidate_count': len(candidates)}), flush=True)
                return
            high_cost, high_failure, removed = removal_lists(last['metrics'])
            added = pending[:len(removed)]
            previous = [r['model'] for r in last['metrics']]
            replacements = list(added)
            # If fewer unseen models remain than removals, fill the last cohort
            # with previously tested models that are not in this removal set.
            history = {r['model']: r for round_ in state['rounds'] for r in round_.get('metrics', [])}
            eligible = sorted((r for m, r in history.items() if m not in previous and m not in added),
                              key=lambda r: (r['known_usd_per_score'] if r['known_usd_per_score'] is not None else float('inf'), r['model']))
            replacements.extend(r['model'] for r in eligible[:len(removed) - len(replacements)])
            iterator = iter(replacements)
            roster = [next(iterator) if m in removed else m for m in previous]
            decision = {'round': last['round'] + 1, 'highest_cost': high_cost, 'most_failures': high_failure,
                        'removed': removed, 'added': added, 'returning_fillers': replacements[len(added):], 'roster': roster}
            results.write_json(directory / f"decision-{decision['round']:02d}.json", decision)
            path = prepare_round(directory, state, decision)
            state['rounds'].append(decision | {'experiment': str(path)})
            results.write_json(state_path, state)
            print(json.dumps(decision), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign', required=True, type=Path)
    args = parser.parse_args()
    run(args.campaign.resolve())
