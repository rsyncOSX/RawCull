import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import RunCatalogPerformance as runner


class CatalogPerformanceRunnerTests(unittest.TestCase):
    def test_manifest_is_nonrecursive_stable_and_tracks_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "b.arw").write_bytes(b"second")
            (root / "A.ARW").write_bytes(b"first")
            (root / "ignore.txt").write_text("ignore")
            (root / "nested").mkdir()
            (root / "nested" / "c.ARW").write_bytes(b"nested")
            before = runner.catalog_manifest(root)
            self.assertEqual(before["file_count"], 2)
            self.assertEqual(before["total_bytes"], 11)
            self.assertEqual(before, runner.catalog_manifest(root))
            (root / "A.ARW").write_bytes(b"changed")
            self.assertNotEqual(before["fingerprint"], runner.catalog_manifest(root)["fingerprint"])

    def test_empty_or_zero_byte_catalog_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, "no regular ARW"):
                runner.catalog_manifest(Path(temporary))
            (Path(temporary) / "empty.ARW").touch()
            with self.assertRaisesRegex(ValueError, "empty ARW"):
                runner.catalog_manifest(Path(temporary))

    def test_missing_results_or_phases_cannot_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertTrue(runner.summarize(root, 1)["failures"])
            (root / "run-1").mkdir()
            (root / "run-1" / "results.json").write_text(json.dumps({
                "metrics": [], "resources": [], "counts": {}, "peakSaves": 0,
            }))
            self.assertEqual(len(runner.summarize(root, 1)["failures"]), len(runner.REQUIRED_PHASES))

    def test_failure_details_and_percentile_survive_summary(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "run-1").mkdir()
            metrics = [{"phase": phase, "milliseconds": 1, "succeeded": True, "detail": ""}
                       for phase in runner.REQUIRED_PHASES]
            metrics += [{"phase": "browse.disk", "milliseconds": 100, "succeeded": False, "detail": "bad.ARW"}]
            (root / "run-1" / "results.json").write_text(json.dumps({
                "metrics": metrics, "resources": [], "counts": {"save": 2}, "peakSaves": 2,
            }))
            summary = runner.summarize(root, 1)
            self.assertEqual(summary["phases"]["browse.disk"]["p95_ms"], 100)
            self.assertIn("bad.ARW", summary["failures"][0])
            self.assertEqual(summary["runs"][0]["metrics"], metrics)
            self.assertEqual(summary["resources"][0]["phases"]["browse.disk"]["count"], 2)
            self.assertEqual(summary["resources"][0]["phases"]["browse.disk"]["total_operation_ms"], 101)

    def report(self):
        return {"benchmark_version": runner.VERSION, "settings": {"runs": 3}, "machine": {"hardware": "test"},
                "catalog": {"fingerprint": "catalog", "directory": "/catalog"}, "status": "passed",
                "source": {"xcode": "Xcode"}, "summary": {"phases": {"preload": runner.distribution([100, 100, 100])}}}

    def test_comparison_gates_medians_only_and_keeps_tail_changes(self):
        before = self.report()
        after = copy.deepcopy(before)
        after["summary"]["phases"]["preload"] = runner.distribution([110, 120, 1000])
        comparison = runner.compare(after, before, 15)
        self.assertEqual(len(comparison), 3)
        self.assertEqual(sum(change["regression"] for change in comparison), 1)
        self.assertAlmostEqual(comparison[0]["change_percent"], 20)
        self.assertFalse(any(change["regression"] for change in runner.compare(after, before, None)))

    def test_incompatible_baseline_rejected(self):
        for key, value in [("settings", {}), ("machine", {}), ("status", "failed")]:
            baseline = self.report()
            baseline[key] = value
            with self.assertRaisesRegex(ValueError, "not comparable"):
                runner.compare(self.report(), baseline, None)

    def test_validate_only_does_not_invoke_xcode(self):
        with tempfile.TemporaryDirectory() as temporary:
            (Path(temporary) / "a.ARW").write_bytes(b"fixture")
            with patch.object(runner, "source_identity") as source, patch("builtins.print"):
                self.assertEqual(runner.main([temporary, "--validate-only"]), 0)
                source.assert_not_called()

    def test_resource_comparison_preserves_unavailable_measurements(self):
        before, after = self.report(), self.report()
        before["summary"]["resources"] = [{"sampled_peak_footprint_bytes": 100}]
        after["summary"]["resources"] = [{"sampled_peak_footprint_bytes": 150}]
        comparison = runner.compare_resources(after, before)
        peak = next(item for item in comparison if item["metric"] == "sampled_peak_footprint_bytes")
        cpu = next(item for item in comparison if item["metric"] == "cpu_seconds_delta")
        self.assertEqual(peak["change_percent"], 50)
        self.assertIsNone(cpu["before"])
        self.assertIsNone(cpu["change_percent"])

    def test_runner_writes_complete_report_and_accepts_it_as_baseline(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog = root / "catalog"
            catalog.mkdir()
            (catalog / "a.ARW").write_bytes(b"fixture")
            source = {"commit": "test", "status": "", "source_sha256": "source", "xcode": "Xcode",
                      "benchmark_sha256": "harness"}

            def execute(command, environment, output, timeout):
                expected = "1" if "diagnostic" in output.name else "0"
                self.assertEqual(environment["TEST_RUNNER_RAWCULL_CATALOG_PERFORMANCE_SOURCE_DIAGNOSTICS"], expected)
                self.assertNotIn("RAWCULL_CATALOG_PERFORMANCE_SOURCE_DIAGNOSTICS", environment)
                self.assertIn("Release", command)
                self.assertIn("RawCullPerformance", command)
                self.assertEqual(environment["TEST_RUNNER_RAWCULL_CATALOG_PERFORMANCE_INPUT"], str(catalog.resolve()))
                directory = output / "run-1"
                directory.mkdir()
                metrics = [{"phase": phase, "milliseconds": 10, "succeeded": True, "detail": ""}
                           for phase in runner.REQUIRED_PHASES]
                (directory / "results.json").write_text(json.dumps({
                    "metrics": metrics, "resources": [], "counts": {}, "peakSaves": 0,
                }))
                return 0

            with patch.object(runner, "source_identity", return_value=source), \
                 patch.object(runner, "command_text", return_value="123"), \
                 patch.object(runner, "run_process", side_effect=execute), \
                 patch.object(runner.platform, "system", return_value="Darwin"), patch("builtins.print"):
                first = root / "before"
                self.assertEqual(runner.main([str(catalog), "--runs", "1", "--output", str(first)]), 0)
                report = json.loads((first / "results.json").read_text())
                self.assertEqual(report["status"], "passed")
                self.assertEqual(len(report["summary"]["runs"][0]["metrics"]), len(runner.REQUIRED_PHASES))
                self.assertTrue((first / "report.md").exists())
                second = root / "after"
                self.assertEqual(runner.main([str(catalog), "--runs", "1", "--output", str(second),
                                              "--baseline", str(first)]), 0)
                compared = json.loads((second / "results.json").read_text())
                self.assertTrue(compared["comparison"])
                self.assertTrue(compared["resource_comparison"])
                diagnostic = root / "diagnostic"
                with patch.dict(runner.os.environ, {"RAWCULL_CATALOG_PERFORMANCE_SOURCE_DIAGNOSTICS": "1"}):
                    self.assertEqual(runner.main([str(catalog), "--runs", "1", "--output", str(diagnostic),
                                                  "--source-diagnostics"]), 0)
                report = json.loads((diagnostic / "results.json").read_text())
                self.assertTrue(report["settings"]["source_diagnostics"])
                with self.assertRaisesRegex(ValueError, "settings"):
                    runner.compare(report, compared, None)




if __name__ == "__main__":
    unittest.main()
