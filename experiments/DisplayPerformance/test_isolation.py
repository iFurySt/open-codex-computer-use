import argparse
import io
import unittest
from unittest.mock import MagicMock, Mock, patch

import build_isolation
import lifecycle


class IsolationTests(unittest.TestCase):
    def test_source_anchor_refuses_missing_or_ambiguous_match(self):
        for source in ('none', 'anchor anchor'):
            with self.assertRaises(ValueError):
                build_isolation.replace_once(source, 'anchor', 'new')
        self.assertEqual(build_isolation.replace_once('anchor', 'anchor', 'new'), 'new')

    def test_variants_keep_treatment_separate(self):
        current_swift, current_bridge = build_isolation.sources('current')
        drain_swift, drain_bridge = build_isolation.sources('drain')
        primary_swift, primary_bridge = build_isolation.sources('primaries')
        self.assertEqual(current_bridge, drain_bridge)
        self.assertEqual(current_swift, primary_swift)
        self.assertNotIn('object_released_before_exit', current_swift)
        self.assertIn('object_released_before_exit', drain_swift)
        self.assertNotIn('forKey:@"whitePoint"', current_bridge)
        self.assertIn('forKey:@"whitePoint"', primary_bridge)

    def test_diagnostics_drop_unrelated_identifiers(self):
        raw = 'noise\n{"display_dealloc":"end","uuid":"private"}\n{"other":"private"}\n'
        self.assertEqual(lifecycle.diagnostics(raw), [{'display_dealloc': 'end'}])

    def test_high_baseline_skips_hotplug_and_cleans_up(self):
        args = argparse.Namespace(cycles=3, slot=28, probe='unused', max_baseline_cpu=5, seconds=20)
        experiment = Mock()
        experiment.phase.return_value = {'cpu': {
            'colorsync.displayservices': {'mean': 6}, 'colorsyncd': {'mean': 0}}}
        with patch.object(lifecycle, 'Experiment', return_value=experiment), \
             patch.object(lifecycle, 'snapshot', return_value={'displays': []}):
            with self.assertRaisesRegex(RuntimeError, 'Baseline above'):
                lifecycle.run(args)
        experiment.create.assert_not_called()
        experiment.cleanup.assert_called_once()

    def test_same_count_icc_change_stops_after_first_cycle(self):
        initial = {'displays': [], 'profiles': {'same': 'old'}}
        changed = {'displays': [], 'profiles': {'same': 'new'}}
        args = argparse.Namespace(cycles=3, slot=28, probe='unused', max_baseline_cpu=5, seconds=20)
        experiment = Mock(records=[], out=MagicMock())
        experiment.phase.return_value = {'cpu': {
            'colorsync.displayservices': {'mean': 0}, 'colorsyncd': {'mean': 0}}}
        process = Mock(stderr=io.BytesIO(b'{"display_dealloc":"end"}'), returncode=0)
        experiment.create.return_value = (process, 42)
        with patch.object(lifecycle, 'Experiment', return_value=experiment), \
             patch.object(lifecycle, 'snapshot', side_effect=[initial, initial, changed]), \
             patch.object(lifecycle.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'ICC identity/content changed'):
                lifecycle.run(args)
        self.assertEqual(experiment.create.call_count, 1)
        experiment.stop.assert_called_once_with(process, 42)
        experiment.cleanup.assert_called_once()
        self.assertEqual(experiment.records[-1]['name'], 'batch_error')

    def test_bounds_rejected_before_measurement(self):
        for cycles, slot in ((4, 28), (0, 28), (1, 32), (1, -1)):
            with self.assertRaises(ValueError):
                lifecycle.run(argparse.Namespace(cycles=cycles, slot=slot))


if __name__ == '__main__':
    unittest.main()
