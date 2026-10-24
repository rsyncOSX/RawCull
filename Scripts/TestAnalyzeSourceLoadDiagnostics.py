import copy
import unittest
from AnalyzeSourceLoadDiagnostics import analyze


def events():
    return [{"event": "source-load", "journalOriginUptime": 100,
             "timing": {"id": "test", "operation": "thumbnail.preload", "source": "file:///catalog/image%201.ARW",
                        "requestedPixelSize": 1616, "submitted": 101, "accessReady": 101.001,
                        "taskStarted": 101.002, "parserReturned": 102.202, "delivered": 102.203,
                        "succeeded": True, "cancelled": False}},
            {"phase": "decode.preload", "detail": "image 1.ARW", "elapsedSeconds": 3,
             "milliseconds": 2001, "succeeded": True}]


class SourceLoadAnalysisTests(unittest.TestCase):
    def test_preserves_parser_wait_and_reporting_as_different_spans(self):
        result = analyze(events())
        record = result["records"][0]
        self.assertEqual(record["dominant_span"], "parser_roundtrip_ms")
        self.assertAlmostEqual(record["parser_roundtrip_ms"], 1200)
        self.assertAlmostEqual(record["outside_adapter_ms"], 798)
        self.assertEqual(len(result["outer_outliers"]), 1)
        self.assertEqual(result["unmatched_or_ambiguous"], 0)

    def test_cancelled_loads_do_not_become_ordinary_failures_or_outliers(self):
        data = events()
        data[0]["timing"].update(cancelled=True, succeeded=False)
        result = analyze(data)
        self.assertEqual(result["cancelled_count"], 1)
        self.assertEqual(result["ordinary_failures"], 0)
        self.assertEqual(result["adapter_outliers"], [])

    def test_repeated_file_requires_containing_operation_interval(self):
        data = events()
        extra = copy.deepcopy(data[-1])
        extra["elapsedSeconds"] = 20
        data.append(extra)
        self.assertEqual(analyze(data)["unmatched_or_ambiguous"], 0)
        data.append(copy.deepcopy(data[-2]))
        self.assertEqual(analyze(data)["unmatched_or_ambiguous"], 1)

    def test_bad_timestamps_and_duplicate_ids_are_rejected(self):
        for value in [float("nan"), 100]:
            data = events()
            data[0]["timing"]["parserReturned"] = value
            with self.assertRaises(ValueError):
                analyze(data)
        data = events()
        data.append(copy.deepcopy(data[0]))
        with self.assertRaises(ValueError):
            analyze(data)

    def test_missing_outer_metric_does_not_invent_zero_reporting_cost(self):
        result = analyze(events()[:1])
        self.assertIsNone(result["records"][0]["outer_ms"])
        self.assertNotIn("outside_adapter_ms", result["records"][0])
        self.assertEqual(result["unmatched_or_ambiguous"], 1)
