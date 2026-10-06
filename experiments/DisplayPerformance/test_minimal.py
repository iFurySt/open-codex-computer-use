import argparse
import os
import unittest
from unittest.mock import Mock, patch

import minimal


class MinimalTests(unittest.TestCase):
    def reply(self, data, expected):
        reader, writer = os.pipe()
        try:
            os.write(writer, data); os.close(writer); writer = None
            process = Mock(stdout=Mock(fileno=lambda: reader))
            return minimal.read_reply(process, expected, seconds=.2)
        finally:
            os.close(reader)
            if writer is not None: os.close(writer)

    def test_reply_and_eof(self):
        self.assertEqual(self.reply(b'{"stage":"init","display_id":1}\n', 'init')['display_id'], 1)
        with self.assertRaisesRegex(RuntimeError, 'exited'):
            self.reply(b'', 'init')
        with self.assertRaisesRegex(RuntimeError, 'Unexpected'):
            self.reply(b'{"stage":"apply"}\n', 'init')
        with self.assertRaisesRegex(RuntimeError, 'Oversized'):
            self.reply(b'x'*4097, 'init')

    def test_baseline_guard_prevents_demo_start(self):
        args = argparse.Namespace(slot=28, seconds=20, probe='unused')
        experiment = Mock(records=[])
        experiment.phase.return_value = {'cpu': {
            'colorsync.displayservices': {'mean': 15}, 'colorsyncd': {'mean': 6}}}
        with patch.object(minimal, 'Experiment', return_value=experiment), \
             patch.object(minimal, 'snapshot', return_value={'displays': []}), \
             patch.object(minimal.subprocess, 'Popen') as spawn:
            with self.assertRaisesRegex(RuntimeError, 'baseline above'):
                minimal.run(args)
        spawn.assert_not_called()
        self.assertEqual(experiment.records[-1]['name'], 'batch_error')

    def test_bad_bounds_before_start(self):
        for slot, seconds in ((32,20),(-1,20),(28,0),(28,61)):
            with self.assertRaises(ValueError):
                minimal.run(argparse.Namespace(slot=slot,seconds=seconds))


if __name__ == '__main__':
    unittest.main()
