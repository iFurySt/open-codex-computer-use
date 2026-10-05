import argparse
import pathlib
import tempfile
import unittest
from unittest.mock import patch

import run
import cycles


class MetricsTests(unittest.TestCase):
    def test_cpu_time_formats(self):
        self.assertAlmostEqual(run.cpu_seconds('01:02.34'), 62.34)
        self.assertEqual(run.cpu_seconds('02:03:04'), 7384)
        self.assertEqual(run.cpu_seconds('1-02:03:04'), 93784)

    def test_log_count_excludes_rounded_window_edges(self):
        output = '\n'.join(
            '{"timestamp":"1970-01-01 00:00:%02d+0000",'
            '"eventMessage":"ColorSyncProfileCreateDeviceProfile Profile desc: Test"}' % seconds
            for seconds in (9, 10, 11, 12)
        )
        output += '\n' + '\n'.join(
            '{"timestamp":"1970-01-01 00:00:%02d+0000",'
            '"eventMessage":"received XPC_DISPLAY_INFO_REQUEST"}' % seconds
            for seconds in (11, 12)
        )
        result = argparse.Namespace(stdout=output, stderr='', returncode=0)
        with patch.object(run.subprocess, 'run', return_value=result):
            counts = run.log_counts(10, 12)
        self.assertEqual(counts['profile_calls'], {'Test': 2})
        self.assertEqual(counts['profile_calls_per_second'], 1)
        self.assertEqual(counts['display_info_requests'], 1)
        self.assertEqual(counts['display_info_requests_per_second'], .5)

    def test_capture_skipped_if_target_disappears_after_queries(self):
        with tempfile.TemporaryDirectory() as directory:
            experiment = run.Experiment(argparse.Namespace(
                output=directory, probe='unused', mode='observe', seconds=20))
            with patch.object(experiment, 'phase') as phase, patch.object(run, 'snapshot', return_value={
                'displays': [], 'screen_recording': True,
            }):
                experiment.run()
            self.assertEqual(phase.call_count, 7)
            self.assertEqual([r['name'] for r in experiment.records], ['capture', 'capture-render'])
            self.assertTrue(all('skipped' in r for r in experiment.records))
            self.assertTrue((pathlib.Path(directory) / 'report.json').exists())

    def test_warm_batch_stops_on_new_icc_and_cleans_own_helper(self):
        physical = {'displays': [], 'profiles': {'old': 'hash'}}
        growth = {'displays': [], 'profiles': {'old': 'hash', 'new': 'hash'}}
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(output=directory, probe='unused', cycles=3, slot=28)
            experiment = run.Experiment(args)
            with patch.object(cycles, 'Experiment', return_value=experiment), \
                 patch.object(cycles, 'snapshot', side_effect=[physical, physical, growth, growth]), \
                 patch.object(cycles, 'cpu_times', return_value={}), \
                 patch.object(cycles, 'log_counts', return_value={}), \
                 patch.object(cycles.time, 'sleep'), \
                 patch.object(experiment, 'create', return_value=(object(), 42)) as create, \
                 patch.object(experiment, 'stop') as stop, \
                 patch.object(experiment, 'cleanup') as cleanup:
                with self.assertRaisesRegex(RuntimeError, 'ICC count changed'):
                    cycles.run_batch(args)
            self.assertEqual(create.call_count, 1)
            self.assertEqual(stop.call_count, 1)
            cleanup.assert_called_once()
            self.assertTrue((pathlib.Path(directory) / 'batch.json').exists())


if __name__ == '__main__':
    unittest.main()
