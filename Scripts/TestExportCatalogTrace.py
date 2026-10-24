import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import ExportCatalogTrace as exporter


class CatalogTraceExportTests(unittest.TestCase):
    def test_selection_includes_waits_and_io_without_exporting_raw_kernel_by_default(self):
        for schema in ('time-profile', 'swiftui-updates', 'os-signpost', 'file-activity', 'thread-state', 'disk-io'):
            self.assertTrue(exporter.selected(schema))
        self.assertFalse(exporter.selected('kdebug'))
        self.assertTrue(exporter.selected('kdebug', True))

    def test_streaming_validation_rejects_truncated_xml_and_counts_rows(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'table.xml'
            path.write_text('<trace-query-result><node><row/><row/></node></trace-query-result>')
            self.assertEqual(exporter.count_rows(path), 2)
            path.write_text('<trace-query-result><node><row/>')
            with self.assertRaises(exporter.ET.ParseError):
                exporter.count_rows(path)

    def test_export_packages_context_and_rejects_empty_cpu_or_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            trace = root / 'input.trace'
            trace.mkdir()
            benchmark = root / 'results.json'
            benchmark.write_text(json.dumps({'status': 'passed', 'benchmark_version': 2}))
            # Keep output outside benchmark's directory, as in the real workflow.
            catalog_report = root / 'benchmark'
            catalog_report.mkdir()
            benchmark.rename(catalog_report / 'results.json')
            benchmark = catalog_report / 'results.json'

            def execute(command, **kwargs):
                path = Path(command[command.index('--output') + 1])
                if '--toc' in command:
                    path.write_text('<trace-toc><run number="1"><info><summary><duration>1</duration></summary></info>'
                                    '<data><table schema="time-profile"/><table schema="potential-hangs"/>'
                                    '</data></run></trace-toc>')
                else:
                    path.write_text('<trace-query-result><node><schema/>' +
                                    ('<row/>' if 'table[1]' in command[command.index('--xpath') + 1] else '') +
                                    '</node></trace-query-result>')
                return exporter.subprocess.CompletedProcess(command, 0, stdout='', stderr='')

            output = root / 'export'
            args = [str(trace), '--benchmark', str(benchmark), '--output', str(output)]
            with patch.object(exporter.subprocess, 'run', side_effect=execute), patch('builtins.print'):
                self.assertEqual(exporter.main(args), 0)
                manifest = json.loads((output / 'export-manifest.json').read_text())
                self.assertEqual(manifest['status'], 'exported')
                self.assertTrue(any('No wait/I/O' in warning for warning in manifest['warnings']))
                self.assertEqual([t['rows'] for t in manifest['tables']], [1, 0])
                self.assertEqual((output / 'benchmark-results.json').read_bytes(), benchmark.read_bytes())
                self.assertEqual(exporter.main(args), 2)
                self.assertEqual(json.loads((output / 'export-manifest.json').read_text())['status'], 'exported')

            def empty_cpu(trace_path, xpath, path):
                path.write_text('<trace-query-result/>')
                return {'rows': 0, 'bytes': path.stat().st_size, 'diagnostics': ''}

            with patch.object(exporter.subprocess, 'run', side_effect=execute), \
                 patch.object(exporter, 'export', side_effect=empty_cpu), patch('builtins.print'):
                self.assertEqual(exporter.main([str(trace), '--benchmark', str(benchmark),
                                                '--output', str(root / 'empty')]), 2)
                self.assertEqual(json.loads((root / 'empty/export-manifest.json').read_text())['status'], 'failed')


if __name__ == '__main__':
    unittest.main()
