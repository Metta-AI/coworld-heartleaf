"""Campaign-scoped spend guard and independent monitor; baseline is excluded."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import time

import httpx
from softmax.auth import get_api_server, load_user_token
import heartleaf_eval_api as api
import heartleaf_eval_results as results


def observe(client, directory):
    state = api.read_json(directory / 'campaign.json')
    requests = {}
    for round_ in state['rounds']:
        if round_['round'] == 0:
            continue
        for file in Path(round_['experiment']).parent.glob('games/*/response.json'):
            response = api.read_json(file)
            requests[response['id']] = [e['id'] for e in response['episodes']]
    episode_ids = [episode for episodes in requests.values() for episode in episodes]
    jobs = []
    episodes = []
    costs = {'usd': 0, 'calls': 0, 'unpriced': 0}
    if episode_ids:
        ids = ','.join("'" + results.identifier(i) + "'" for i in episode_ids)
        episodes = results.query(client, 'SELECT e.episode_request_id,j.status FROM episode_requests e LEFT JOIN job_requests j ON j.id=e.job_request_id WHERE e.episode_request_id IN (' + ids + ')')
        jobs = results.query(client, "SELECT DISTINCT j.id,j.status,j.result->'cost_usd' AS compute_usd FROM job_requests j JOIN episode_request_attempts a ON a.job_request_id=j.id JOIN episode_requests e ON e.id=a.episode_request_id WHERE e.episode_request_id IN (" + ids + ')')
        if jobs:
            ids = ','.join("'" + results.identifier(str(j['id'])) + "'" for j in jobs)
            costs = results.query(client, "SELECT COALESCE(sum(p.billed_cost_usd),0) AS usd,count(*) AS calls,count(*) FILTER (WHERE p.billed_cost_usd IS NULL) AS unpriced FROM llm_attempt_events a LEFT JOIN llm_provider_events p ON p.platform_call_id=a.platform_call_id WHERE a.request_metadata->>'job_request_id' IN (" + ids + ')')[0]
    statuses = {e['episode_request_id']: e['status'] for e in episodes}
    active = [request for request, ids in requests.items() if any(statuses.get(i) not in ('completed', 'failed', 'cancelled') for i in ids)]
    compute = sum(float(j['compute_usd']) for j in jobs if j['compute_usd'] is not None)
    return {'observed_at': datetime.now(timezone.utc).isoformat(), 'request_ids': list(requests),
            'active_request_ids': active, 'calls': costs['calls'], 'unpriced_calls': costs['unpriced'],
            'known_inference_usd': float(costs['usd']), 'known_compute_usd': compute,
            'known_new_spend_usd': float(costs['usd']) + compute,
            'missing_compute_jobs': sum(j['compute_usd'] is None for j in jobs)}


def check(client, directory, launching=False):
    policy_path = directory / 'spend-policy.json'
    policy = api.read_json(policy_path)
    snapshot = observe(client, directory)
    snapshot['limit_usd'] = policy['limit_usd']
    snapshot['projected_committed_usd'] = snapshot['known_new_spend_usd'] + policy['reserve_per_active_game_usd'] * (len(snapshot['active_request_ids']) + int(launching))
    results.write_json(directory / 'spend-latest.json', snapshot)
    if snapshot['known_new_spend_usd'] > policy['limit_usd']:
        policy['paused'] = True
        policy['reason'] = 'Recorded new inference plus compute spend exceeded the user limit'
        results.write_json(policy_path, policy)
    if launching and (policy['paused'] or snapshot['projected_committed_usd'] > policy['limit_usd']):
        results.write_json(directory / 'spend-launch-stop.json', snapshot)
        raise ValueError('Campaign spend guard paused new launches; user approval is required to raise the ceiling')
    return snapshot, policy


def monitor(directory):
    server = get_api_server()
    with httpx.Client(base_url=api.observatory_base_url(server), headers={
            'Authorization': 'Bearer ' + load_user_token(server=server),
            api.ELEVATED_PRIVILEGES_HEADER: 'true'}, timeout=60) as client:
        while True:
            try:
                snapshot, policy = check(client, directory)
                if policy['paused']:
                    # A spend stop affects future launches only. Keep observing
                    # charges while already submitted games finish naturally.
                    if not snapshot['active_request_ids']:
                        return
                if api.read_json(directory / 'campaign.json')['status'] == 'complete':
                    return
            except httpx.HTTPError as exc:
                results.write_json(directory / 'spend-monitor-error.json', {
                    'observed_at': datetime.now(timezone.utc).isoformat(), 'error': type(exc).__name__})
            time.sleep(30)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign', required=True, type=Path)
    args = parser.parse_args()
    monitor(args.campaign.resolve())
