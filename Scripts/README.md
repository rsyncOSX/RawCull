# Script checks

Run `make test-scripts` from the repository root. These tests use temporary
fixtures and mocked Xcode invocations; installed models and photographs are not
required. The explicit `Test*.py` discovery pattern matters: unittest's default
lowercase `test*.py` pattern does not find these files.

| Script | Test file | Coverage |
|---|---|---|
| `CompareAFSharpness.py` | `TestCompareAFSharpness.py` | Pair labels, direction, ties, missing scores, duplicate pairs and burst IDs; optional crop integration. |
| `FreezeCombinedReviewBaseline.py` | `TestFreezeCombinedReviewBaseline.py` | Read-only inventory, identity, hashes, decoded payloads, absent exports and PNG headers. |
| `VerifyModelProvenance.py` | `TestModelProvenance.py` | Current release evidence and rejection of malformed, missing, blocked or inconsistent provenance. |
| `RunAIAnalysis.py` | `TestRunAIAnalysis.py` | Sorted/nonrecursive ARW selection, limits, progress parsing, missing evidence and exit codes. |
| `RunCombinedReviewSix.py` | `TestRunCombinedReviewSix.py` | Catalog/frozen selection, terminal progress, empty inputs, missing evidence and exit codes. |
| Both runners | `TestRunnerPrivacy.py` | Private output permissions and restoration of the caller's umask on success and failure. |

The crop integration test skips if OpenCV is unavailable. To exercise it, select
a Python environment with both `cv2` and `numpy`, then run
`make test-scripts PYTHON=/absolute/path/to/python3`.

`VerifyTestEnumeration.swift` validates Xcode's smoke/performance enumeration via
the Makefile targets. `VerifyAIImportBoundary.sh` checks the AI import boundary.
`release.sh` orchestrates release work; it is not a unit test and is not executed
by `test-scripts`.
