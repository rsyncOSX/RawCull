# Local AI Analysis diagnostics

Current run results and remaining qualification gates: [AI verification summary](ai-verification-summary.md).

Run from the repository root:

```sh
python3 Scripts/RunAIAnalysis.py --directory "/path/to/catalog" --limit 6
```

Selects regular `.ARW` files directly inside the supplied directory, case insensitive, in filename order. The limit is 1–6 (default 6); fewer available files are accepted. All selected files run through SAM 3 + CLIP first, then Qwen Vision, then automatic Objects, sequentially in one opt-in Swift test. Each file runs once per stage; failures are retained and do not prevent later stages. No application implementation changes or automatic repairs are made.

Options:

- `--models "/path/to/Models"`: defaults to `~/ModelAssets/Release/Models`; requires `SAM3`, `CLIP-DataComp`, and `Qwen/qwen3_vl_2b`.
- `--output "/private/tmp/my-analysis/evidence"`: must be new; defaults to unique temporary output. Evidence is retained after failures.
- `--packages "/path/to/SourcePackages"`: reuse installed Swift package checkouts.
- `--preflight-only`: check selection, hashes and installed model directories without building or inference.

The runner prints evidence and build log paths. Adjacent files hold input SHA-256 hashes, the complete Xcode log and `.xcresult`. Inside the evidence directory:

- `models.txt`: runtime capabilities and validation outcomes.
- `sam-clip-N.txt`, `qwen-N.txt`, `objects-N.txt`: complete Swift result dumps, including structured assessments, rejected text, instance descriptors, model metadata, timings and failures where exposed by each feature.
- `clip-N.txt`: real CLIP image embedding. The SAM 3 + CLIP tab currently invokes Deep Review without calling CLIP; this is an explicitly separate embedding probe, not a claim that Deep Review used CLIP.
- `*-request-N.txt`, `.png`, `.response.txt` or `.error.txt`: full Qwen instruction, token cap, actual image dimensions, exact input image (including Objects boards), untruncated response or inference error.
- `progress.json`: atomically updated per completed analysis, with stage, file, elapsed seconds, failure and result path.
- `diagnostic.json`: completed summary; missing means the test did not finish.
- Private runtime cache directories retain SAM mask artifacts, isolated from application caches.

The test uses auto preset and embedded previews, matching default analysis behavior. Camera AF and precomputed catalog sharpness/subject evidence are not populated by this standalone probe. A new runtime prevents reuse of application results. Output contains local photo data and is created with private permissions. A nonzero exit means build/setup or analysis failure; inspect evidence before changing implementation. Successful completion alone does not establish photographic correctness.

Runner checks without models:

```sh
python3 -m unittest discover -s Scripts -p TestRunAIAnalysis.py
```
