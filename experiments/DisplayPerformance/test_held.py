import argparse
import io
import unittest
from unittest.mock import MagicMock, Mock, patch

import build_minimal_variant
import held


class HeldTests(unittest.TestCase):
    def test_variant_differences_stay_separate(self):
        global_source=build_minimal_variant.source('global')
        typed_source=build_minimal_variant.source('typed')
        self.assertIn('dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)',global_source)
        self.assertNotIn('OCUPrivateDisplaySignature',global_source)
        self.assertIn('dispatch_queue_create("display.minimal", DISPATCH_QUEUE_SERIAL)',typed_source)
        self.assertIn('initWithDescriptor:descriptor]',typed_source)
        self.assertIn('height:1080 refreshRate:60.0]',typed_source)

    def test_held_windows_create_and_remove_only_once(self):
        args=argparse.Namespace(slot=28,windows=3,probe='unused')
        initial={'profiles':{'same':'hash'},'displays':[]}
        baseline={'cpu':{'colorsync.displayservices':{'mean':0},'colorsyncd':{'mean':0}}}
        active=dict(baseline,after={'profiles':{'same':'hash'},'displays':[{'id':42}]})
        e=Mock(records=[],out=MagicMock());e.phase.side_effect=[baseline,active,active,active,{}]
        process=Mock(returncode=0,stderr=io.BytesIO(b''))
        with patch.object(held,'Experiment',return_value=e), \
             patch.object(held,'snapshot',return_value=initial), \
             patch.object(held,'create',return_value=(process,42)) as create:
            held.run(args)
        create.assert_called_once_with(e,28)
        e.stop.assert_called_once_with(process,42)
        e.cleanup.assert_called_once()
        self.assertEqual(e.phase.call_count,5)

    def test_high_baseline_skips_create(self):
        args=argparse.Namespace(slot=28,windows=1,probe='unused')
        e=Mock(records=[]);e.phase.return_value={'cpu':{
            'colorsync.displayservices':{'mean':10},'colorsyncd':{'mean':3}}}
        with patch.object(held,'Experiment',return_value=e), \
             patch.object(held,'snapshot',return_value={'displays':[]}), \
             patch.object(held,'create') as create:
            with self.assertRaisesRegex(RuntimeError,'Baseline above'):
                held.run(args)
        create.assert_not_called();e.cleanup.assert_called_once()


if __name__=='__main__':unittest.main()
