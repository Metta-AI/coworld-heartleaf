import sys
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import heartleaf_eval_campaign as campaign
import heartleaf_eval_experiment as experiment
import heartleaf_eval_campaign_budget as budget
import heartleaf_eval_results as results


class CampaignTests(unittest.TestCase):
    def test_removal_union_and_deterministic_ties(self):
        rows = [{'model': str(i), 'known_usd_per_score': 9-i, 'failures': i} for i in range(9)]
        self.assertEqual(campaign.removal_lists(rows)[2], ['0', '1', '8', '7'])
        for row in rows:
            row['failures'] = 9-int(row['model'])
        self.assertEqual(campaign.removal_lists(rows)[2], ['0', '1'])
        rows[2]['failures'] = 10
        self.assertEqual(campaign.removal_lists(rows)[2], ['0', '1', '2'])

    def test_zero_score_is_worst_cost_ratio(self):
        rows = [{'model': 'zero', 'known_usd_per_score': None, 'failures': 0},
                {'model': 'cheap', 'known_usd_per_score': .1, 'failures': 0},
                {'model': 'expensive', 'known_usd_per_score': 10, 'failures': 0}]
        self.assertEqual(campaign.removal_lists(rows)[0], ['zero', 'expensive'])

    def test_explicit_no_canary_five_game_schedule(self):
        config = experiment.parameters({'canary_days': 0, 'seeds': list(range(91002, 91007)), 'meetings': 1})
        schedule = experiment.schedule([f'S1-M{i:02d}' for i in range(9)], config)
        self.assertEqual(len(schedule), 5)
        self.assertTrue(all(g['kind'] == 'evaluation' and g['max_days'] == 7 for g in schedule))

    def test_budget_excess_blocks_launches_but_allows_observation(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            results.write_json(directory / 'spend-policy.json', {
                'limit_usd': 1500, 'paused': False, 'reserve_per_active_game_usd': 150})
            snapshot = {'known_new_spend_usd': 1500.01, 'active_request_ids': ['xreq_live']}
            with patch.object(budget, 'observe', return_value=snapshot):
                _, policy = budget.check(None, directory)
                self.assertTrue(policy['paused'])
                with self.assertRaisesRegex(ValueError, 'paused new launches'):
                    budget.check(None, directory, launching=True)

    def test_budget_scope_excludes_baseline(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            results.write_json(directory / 'campaign.json', {
                'rounds': [{'round': 0, 'request_ids': ['old_request']} ]})
            with patch.object(results, 'query') as query:
                snapshot = budget.observe(None, directory)
                self.assertEqual(snapshot['known_new_spend_usd'], 0)
                self.assertEqual(snapshot['request_ids'], [])
                query.assert_not_called()


if __name__ == '__main__':
    unittest.main()
