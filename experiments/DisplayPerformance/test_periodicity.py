import unittest
import periodicity


class PeriodicityTests(unittest.TestCase):
    def test_two_recurring_streams_merge_circular_boundary(self):
        values=[100+index*5.053+offset for index in range(9) for offset in (0,.731)]
        result=periodicity.analyze(values)
        self.assertAlmostEqual(result['best_period_seconds'],5.053)
        self.assertEqual(result['phase_cohorts'],2)
        self.assertEqual(sorted(result['cohort_request_counts']),[9,9])
        self.assertEqual(result['aligned_pairs'],result['eligible_pairs'])

    def test_parser_ignores_unrelated_and_malformed_records(self):
        text='bad\n{"timestamp":"2026-10-07T00:00:00+00:00","eventMessage":"other"}\n'
        text+='{"timestamp":"2026-10-07T00:00:05+00:00","eventMessage":"received XPC_DISPLAY_INFO_REQUEST"}'
        self.assertEqual(len(periodicity.timestamps(text)),1)

    def test_short_segments_rejected(self):
        with self.assertRaises(ValueError):periodicity.analyze([0,1,2,3])


if __name__=='__main__':unittest.main()
