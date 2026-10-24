#!/usr/bin/env python3
import unittest
from AnalyzeGridPreparation import PHASES, analyze


def metric(phase, end, milliseconds, succeeded=True):
    return dict(phase=phase, elapsedSeconds=end, milliseconds=milliseconds, succeeded=succeeded)


class GridPreparationAnalysisTests(unittest.TestCase):
    def windows(self):
        return [metric(phase, index * 10 + 5, 2000) for index, phase in enumerate(PHASES)]

    def test_separates_passes_and_preserves_failed_grid_counts(self):
        metrics = self.windows()
        for index in range(4):
            metrics.append(metric("grid.preloadResize", index * 10 + 4, 100, index != 2))
        result = analyze(metrics)
        self.assertEqual(result["unassigned_grid_count"], 0)
        self.assertEqual([result["phases"][phase]["grid_count"] for phase in PHASES], [1] * 4)
        self.assertEqual(result["phases"][PHASES[2]]["grid_failed"], 1)
        self.assertEqual(result["phases"][PHASES[0]]["grid_sum_ms"], 100)

    def test_crossing_boundary_and_outside_metrics_are_unassigned(self):
        metrics = self.windows() + [metric("grid.preloadResize", 3.1, 200),
                                    metric("grid.preloadResize", 9, 100)]
        self.assertEqual(analyze(metrics)["unassigned_grid_count"], 2)

    def test_overlapping_windows_are_ambiguous(self):
        metrics = [metric(phase, 5, 2000) for phase in PHASES]
        metrics.append(metric("grid.preloadResize", 4, 100))
        self.assertEqual(analyze(metrics)["unassigned_grid_count"], 1)

    def test_missing_duplicate_and_failed_windows_are_rejected(self):
        for metrics in [self.windows()[:-1], self.windows() + [self.windows()[0]],
                        [metric(PHASES[0], 5, 2000, False)] + self.windows()[1:]]:
            with self.assertRaises(ValueError):
                analyze(metrics)


if __name__ == "__main__":
    unittest.main()
