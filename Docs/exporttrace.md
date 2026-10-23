# Exporting Xcode Instruments traces as XML

Exporting Xcode Instruments data as XML makes it easier to inspect and analyze. Keep the original `.trace` file too.

## 1. Export the table of contents

Run this in Terminal, replacing `Recording.trace` with the path to your recording:

```bash
xcrun xctrace export --input "Recording.trace" \
  --toc --output "trace-toc.xml"
```

The table of contents lists the runs and available data tables in the recording.

## 2. Export a relevant data table

Use a schema name from `trace-toc.xml` in the XPath expression:

```bash
xcrun xctrace export --input "Recording.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="SCHEMA-NAME"]' \
  --output "trace-data.xml"
```

Replace `SCHEMA-NAME` with the relevant table schema, and adjust the run number if needed.

## What to provide for analysis

- Start with `trace-toc.xml` so the relevant tables and export commands can be identified.
- Provide the exported data XML files.
- Include which instrument you recorded, such as Time Profiler or Allocations.
- Describe the action that felt slow or used too much memory, including its approximate time in the recording if available.
- Keep the original `.trace` recording available for further inspection.

For Time Profiler, a screenshot or text export of the expanded call tree is also useful alongside the XML.
