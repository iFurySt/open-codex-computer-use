import argparse
import pathlib
import tempfile
import unittest
from unittest.mock import patch

import run


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
        result = argparse.Namespace(stdout=output, stderr='', returncode=0)
        with patch.object(run.subprocess, 'run', return_value=result):
            counts = run.log_counts(10, 12)
        self.assertEqual(counts['profile_calls'], {'Test': 2})
        self.assertEqual(counts['profile_calls_per_second'], 1)

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


if __name__ == '__main__':
    unittest.main()
