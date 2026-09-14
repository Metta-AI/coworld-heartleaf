import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('dashboard', Path(__file__).parents[1] / 'tools/heartleaf_campaign_dashboard.py')
dashboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dashboard)


class DashboardTest(unittest.TestCase):
    def test_verified_partial_round_deduplication_and_elimination(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def write(path, value):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(value))
            def record(request, verified=True, score=10):
                return {'request_id': request, 'game_id': request, 'kind': 'evaluation', 'status': 'completed',
                        'measurement_verified': verified, 'realized_days': 7, 'calls': 4,
                        'seats': [{'expected_model': 'a', 'slot': 0, 'score': score, 'calls': 4,
                                   'provider_cost_usd': {'known': 2, 'missing': 1}, 'max_s': 3, 'unreported_timeout_calls': 1}],
                        'unusable_responses': [{'slot': 0, 'outcome': 'deadline_exceeded'},
                                              {'slot': 0, 'outcome': 'request_rejected'}]}
            write(root / 'baseline-records.json', [record('baseline')])
            write(root / 'campaign.json', {'status': 'running', 'candidates': ['a', 'b', 'c'],
                'rounds': [{'round': 0}, {'round': 1, 'roster': ['b'], 'experiment': str(root / 'eval/experiment.json'),
                            'removed': ['a'], 'highest_cost': ['a'], 'most_failures': ['a']}]})
            for i, r in enumerate([record('new'), record('new'), record('bad', False, 1000)]):
                game = root / f'eval/games/{i}'
                write(game / 'latest.json', {'generation': 'g'})
                write(game / 'g/summary.json', r)
                write(game / 'g/calls.json', [{'slot': '0', 'latency_ms': t} for t in [1000, 2000, 9000]])
            with patch.object(dashboard, 'process_status', return_value={'live': False, 'pid': None}):
                result = dashboard.snapshot(root)
            a = next(r for r in result['rows'] if r['model'] == 'a')
            self.assertEqual((a['games'], a['score'], a['known_inference_usd']), (2, 20, 4))
            self.assertEqual((a['failures'], a['other_unusable'], a['unpriced_calls']), (2, 2, 2))
            self.assertEqual(a['failures_per_game'], 1)
            self.assertEqual(a['deadline_exceeded_per_game'], 1)
            self.assertEqual(a['token_limit_per_game'], 0)
            self.assertEqual(a['other_unusable_per_game'], 1)
            self.assertEqual(a['unpriced_calls_per_game'], 1)
            self.assertEqual(a['unreported_calls_per_game'], 1)
            self.assertIsNone(next(r for r in result['rows'] if r['model'] == 'c')['failures_per_game'])
            self.assertEqual(a['status'], 'Eliminated')
            self.assertEqual((a['p50_s'], a['p95_s'], a['latency_samples']), (2, 9, 3))
            self.assertEqual(a['unreported_calls'], 2)
            self.assertEqual(result['current_games_completed'], 1)
            self.assertEqual(a['eliminations'][0]['reasons'], ['highest $/score', 'most failed turns'])
            self.assertEqual(next(r for r in result['rows'] if r['model'] == 'c')['status'], 'Untested')
            self.assertEqual(len(result['warnings']), 2)

    def test_pid_reuse_does_not_claim_controller_live(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'launch.json').write_text('{"pid":123}')
            with patch.object(dashboard.subprocess, 'run') as run:
                run.return_value.returncode = 0
                run.return_value.stdout = 'unrelated process'
                self.assertFalse(dashboard.process_status(root, 'launch.json', 'heartleaf_eval_campaign.py')['live'])
