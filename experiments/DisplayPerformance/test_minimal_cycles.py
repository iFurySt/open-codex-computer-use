import argparse
import io
import unittest
from unittest.mock import MagicMock, Mock, patch

import minimal_cycles


class MinimalCycleTests(unittest.TestCase):
    def test_resource_guard_checks_content_not_only_count(self):
        original={'profiles':{'same':'old'},'displays':[]}
        with self.assertRaisesRegex(RuntimeError,'ICC'):
            minimal_cycles.verify_resources(original,{'profiles':{'same':'new'},'displays':[]})
        with self.assertRaisesRegex(RuntimeError,'topology'):
            minimal_cycles.verify_resources(original,{'profiles':{'same':'old'},'displays':[42]})

    def test_bounds_rejected(self):
        for cycles,slot in ((0,28),(31,28),(1,32),(1,-1)):
            with self.assertRaises(ValueError):
                minimal_cycles.run(argparse.Namespace(cycles=cycles,slot=slot))

    def test_three_cycles_are_followed_by_removed_checkpoint_and_cleanup(self):
        args=argparse.Namespace(cycles=3,slot=28,probe='unused')
        e=Mock(records=[],out=MagicMock());initial={'profiles':{'same':'old'},'displays':[]}
        def process(*_):return Mock(returncode=0,stderr=io.BytesIO(b'')),42
        with patch.object(minimal_cycles,'Experiment',return_value=e), \
             patch.object(minimal_cycles,'snapshot',return_value=initial), \
             patch.object(minimal_cycles,'create',side_effect=process) as create, \
             patch.object(minimal_cycles.time,'sleep'):
            minimal_cycles.run(args)
        self.assertEqual(create.call_count,3)
        self.assertEqual(e.stop.call_count,3)
        self.assertEqual(e.phase.call_args_list[2].args,('after-3-cycles',))
        self.assertEqual(e.phase.call_count,6)
        e.cleanup.assert_called_once()

    def test_changed_profile_aborts_after_first_cycle_and_cleans_up(self):
        args=argparse.Namespace(cycles=3,slot=28,probe='unused')
        e=Mock(records=[],out=MagicMock());initial={'profiles':{'same':'old'},'displays':[]}
        changed={'profiles':{'same':'new'},'displays':[]}
        process=Mock(returncode=0,stderr=io.BytesIO(b''))
        with patch.object(minimal_cycles,'Experiment',return_value=e), \
             patch.object(minimal_cycles,'snapshot',side_effect=[initial,initial,initial,changed]), \
             patch.object(minimal_cycles,'create',return_value=(process,42)) as create, \
             patch.object(minimal_cycles.time,'sleep'):
            with self.assertRaisesRegex(RuntimeError,'ICC'):
                minimal_cycles.run(args)
        self.assertEqual(create.call_count,1)
        self.assertEqual(e.records[-1]['name'],'batch_error')
        e.cleanup.assert_called_once()


if __name__=='__main__':unittest.main()
