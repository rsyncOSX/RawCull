import copy
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

import ValidateCatalogSignposts as validator


def event(name, kind, timestamp, identifier='1', message='', process='RawCull (1)'):
    return dict(name=name, kind=kind, time_ns=timestamp, id=identifier, message=message,
                process=process, scope='Process', thread='worker')


def session(identifier='1', start=0, prepared=809):
    return [event('CatalogOpen', 'Begin', start, identifier),
            event('CatalogMetadataScan', 'Begin', start + 1, identifier),
            event('CatalogMetadataScan', 'End', start + 2, identifier),
            event('CatalogThumbnailPreload', 'Begin', start + 3, identifier, 'pixels=1\u00a0616'),
            event(validator.COMPLETE, 'Event', start + 4, identifier, f'prepared={prepared} pixels=1\u00a0616'),
            event('CatalogThumbnailPreload', 'End', start + 5, identifier),
            event('CatalogOpen', 'End', start + 6, identifier)]


class CatalogSignpostValidationTests(unittest.TestCase):
    def test_success_and_partial_cancellation_counts(self):
        for prepared in (0, 4, 809):
            result = validator.validate(session(prepared=prepared))
            self.assertEqual(result['status'], 'passed')
            self.assertEqual(result['intervals'][1]['prepared'], prepared)

    def test_switching_overlapping_ids_are_paired_by_process_and_name(self):
        first = session(start=0, prepared=2)
        second = session(start=2, prepared=809)
        for e in second:
            e['process'] = 'RawCull (2)'
        self.assertEqual(validator.validate(sorted(first + second, key=lambda e: e['time_ns']))['status'], 'passed')
        # Same-process overlapping catalogs use distinct signpost IDs.
        second = session(identifier='2', start=2)
        self.assertEqual(validator.validate(sorted(first + second, key=lambda e: e['time_ns']))['status'], 'passed')

    def test_truncated_unmatched_and_duplicate_events_fail(self):
        cases = [session()[:-1], session()[1:], session()[:1] + session(),
                 [e for e in session() if e['name'] != validator.COMPLETE]]
        duplicate_completion = session()
        duplicate_completion.insert(5, copy.deepcopy(duplicate_completion[4]))
        cases.append(duplicate_completion)
        wrong_pixels = session()
        wrong_pixels[4]['message'] = 'prepared=809 pixels=1600'
        cases.append(wrong_pixels)
        for events in cases:
            self.assertEqual(validator.validate(events)['status'], 'failed')
        self.assertEqual(validator.validate([])['status'], 'failed')

    def test_xml_schema_and_references_are_resolved(self):
        columns = ['time', 'thread', 'process', 'event-type', 'scope', 'identifier',
                   'name', 'subsystem', 'category', 'message']
        schema = '<schema>' + ''.join(f'<col><mnemonic>{c}</mnemonic></col>' for c in columns) + '</schema>'
        row = ('<row><time>20</time><thread>worker</thread><process fmt="RawCull (1)"/>'
               '<kind>Begin</kind><scope>Process</scope><id>1</id><name>CatalogOpen</name>'
               '<subsystem id="sub">no.blogspot.RawCull</subsystem><category>CatalogPerformance</category>'
               '<message/></row>')
        row2 = row.replace('<time>20</time>', '<time>10</time>').replace(
            '<subsystem id="sub">no.blogspot.RawCull</subsystem>', '<subsystem ref="sub"/>')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'events.xml'
            path.write_text('<result>' + schema + row + row2 + '</result>')
            events = validator.catalog_events(path)
            self.assertEqual([e['time_ns'] for e in events], [10, 20])
            path.write_text('<result>' + schema + row2 + '</result>')
            with self.assertRaisesRegex(ValueError, 'Unresolved'):
                validator.catalog_events(path)
            path.write_text('<result><row>')
            with self.assertRaises(ET.ParseError):
                validator.catalog_events(path)


if __name__ == '__main__':
    unittest.main()
