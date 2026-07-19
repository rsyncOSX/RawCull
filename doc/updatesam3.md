# Updating the SAM3 Core AI Model

The current SAM3 model exporter is pinned to `coreai-torch==0.4.0`. On macOS
27, Core AI can fail while specializing models produced by that version, with
errors such as:

```text
error: expected AICode versioned location
error: Failed to convert to versioned IR
LLVM ERROR: cannot unwrap empty `odiec_module_t`
```

Apple's macOS 27 release notes recommend converting affected models with
`coreai-torch` 0.4.1 or newer:

<https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes?changes=l_2>

The LLVM failure terminates the process and cannot be caught as a normal Swift
error. Follow this procedure to regenerate, validate, and install a compatible
SAM3 model.

## 1. Avoid SAM3 while updating

Before changing the model:

1. Quit RawCull.
2. Do not start subject-mask generation until the replacement model has been
   installed and validated.
3. Preserve the current model bundles so they can be inspected or restored.

Normal culling, sharpness scoring, and Vision-based similarity do not require
SAM3.

## 2. Check the toolchain

From the repository root:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull

sw_vers
xcodebuild -version
uv --version
```

Core AI requires macOS 27 and Xcode 27. If `uv` is unavailable and Homebrew is
installed, install it with:

```sh
brew install uv
```

The export downloads SAM3, Transformers, Torch, and Core AI dependencies. It
requires network access, access to `facebook/sam3`, and substantial free disk
space. Keep enough space for the downloaded weights, Python environment, old
backup, source `.aimodel`, and optimized `.aimodel`.

If Hugging Face reports that the model is gated or unauthorized, accept the
model's license on its Hugging Face page and authenticate locally before
retrying. Depending on the installed Hugging Face CLI, use either:

```sh
hf auth login
```

or:

```sh
huggingface-cli login
```

## 3. Update the exporter dependency

Open `../PhotoAIKit/tools/export_sam3.py` and change:

```python
"coreai-torch==0.4.0",
```

to:

```python
"coreai-torch==0.4.1",
```

Update `coreai-core` to the version required by `coreai-torch` 0.4.1. Keep the
other dependencies unchanged initially. The block should be:

```python
dependencies = [
    "coreai-core==1.0.0b2",
    "coreai-torch==0.4.1",
    "tokenizers<0.23.0rc",
    "torchvision",
    "transformers>=5.5.4,<5.10.1",
]
```

`coreai-torch==0.4.1` requires `coreai-core==1.0.0b2`; retaining b1 makes the
dependency set unsatisfiable. Using exact versions makes the export
reproducible. Changing the inline dependency declaration causes `uv` to create
or select an environment matching the new specification.

## 4. Preserve the old development bundle

The export uses `--overwrite`, so preserve the existing bundle first:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull

mv RawCull/Resources/Models/SAM3 \
   RawCull/Resources/Models/SAM3-coreai-torch-0.4.0-broken
```

Confirm the backup exists:

```sh
du -sh RawCull/Resources/Models/SAM3-coreai-torch-0.4.0-broken
```

Do not rename the installed Application Support copy yet. Keeping it in place
provides a rollback until the new export succeeds.

## 5. Re-export SAM3

Run:

```sh
make sam3-export
```

The equivalent direct command is:

```sh
uv run ../PhotoAIKit/tools/export_sam3.py \
  --output-dir RawCull/Resources/Models \
  --bundle-name SAM3 \
  --dtype float16 \
  --overwrite
```

Expected stages include:

```text
[INFO] Sourcing model...
[INFO] Model exported. Converting to Core AI...
[INFO] Model converted.
[INFO] Saving AOT source model...
[INFO] Optimizing runtime model...
[INFO] Saving optimized runtime model...
[INFO] SAM3 bundle ready...
```

The resulting directory should contain:

```text
RawCull/Resources/Models/SAM3/
|-- metadata.json
|-- sam3_float16.aimodel
|-- sam3_float16_source.aimodel
`-- tokenizer/
```

The normal portable runtime asset is `sam3_float16.aimodel`. Check the bundle's
selected asset:

```sh
python3 -c 'import json; print(json.load(open("RawCull/Resources/Models/SAM3/metadata.json"))["assets"]["main"])'
```

Expected output before optional AOT compilation:

```text
sam3_float16.aimodel
```

## 6. Confirm that a new artifact was produced

Compare the old and new optimized graph hashes:

```sh
shasum \
  RawCull/Resources/Models/SAM3-coreai-torch-0.4.0-broken/sam3_float16.aimodel/main.mlirb \
  RawCull/Resources/Models/SAM3/sam3_float16.aimodel/main.mlirb
```

The hashes should differ. If either bundle uses a different internal filename,
list it first:

```sh
find RawCull/Resources/Models/SAM3 -maxdepth 2 -type f -print
```

Verify the Python package version independently:

```sh
uv run --with coreai-torch==0.4.1 python -c \
  'import importlib.metadata as m; print(m.version("coreai-torch"))'
```

Expected output:

```text
0.4.1
```

## 7. Validate the portable model

Apple provides Core AI Debugger for inspecting, specializing, executing, and
validating `.aimodel` assets:

<https://developer.apple.com/core-ai-debugger/>

Open this optimized portable asset:

```text
/Users/thomas/GitHub/RawCull/RawCull/RawCull/Resources/Models/SAM3/sam3_float16.aimodel
```

Confirm that:

- The model opens without an IR conversion error.
- A `main` function exists.
- Inputs include `pixel_values` and `input_ids`.
- Outputs include `pred_masks`, `pred_boxes`, `pred_logits`,
  `presence_logits`, and `semantic_seg`.
- Specialization completes on the local Mac.

Loading an `.aimodel` performs device-specific specialization and normally
caches the result. See Apple's documentation:

<https://developer.apple.com/documentation/CoreAI/managing-model-specialization-and-caching>

If the installed Xcode does not expose `xcrun coreai-build`, skip the optional
AOT compilation in the next section. The portable `sam3_float16.aimodel` can be
used directly and will be specialized on first load.

## 8. Optionally compile an AOT asset

This step is optional. First check whether the compiler is available:

```sh
xcrun --find coreai-build
```

If it is available, compile the source asset rather than the already optimized
runtime asset:

```sh
make sam3-compile
```

The Makefile defaults to architecture `h16c`, which is configured for the local
Apple M4 development machine. For another architecture, use:

```sh
make sam3-compile SAM3_COMPILE_ARCH=<architecture>
```

To compile for every supported architecture:

```sh
make sam3-compile-all
```

If compilation produces an `.aimodelc` directly inside the SAM3 bundle, point
`metadata.json` at it with:

```sh
make sam3-use-asset ASSET=<generated-file>.aimodelc
```

Verify the selection:

```sh
python3 -c 'import json; print(json.load(open("RawCull/Resources/Models/SAM3/metadata.json"))["assets"]["main"])'
```

If compilation fails, or the compiler reports missing source bytecode, leave
the metadata pointed at the portable asset:

```sh
make sam3-use-asset ASSET=sam3_float16.aimodel
```

Do not use an `.aimodelc` generated by Xcode 27 Beta 2 or earlier. Apple's
macOS 27 release notes recommend recompiling old AOT assets with Xcode 27 Beta
3 or newer.

## 9. Back up the installed faulty model

Quit RawCull completely.

The sandboxed runtime installation is:

```text
~/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/SAM3
```

Rename it if it exists:

```sh
mv \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/SAM3" \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/SAM3-coreai-torch-0.4.0-broken"
```

There may also be a non-container development copy:

```text
~/Library/Application Support/RawCull/Models/SAM3
```

Preserve it too if present:

```sh
mv \
  "$HOME/Library/Application Support/RawCull/Models/SAM3" \
  "$HOME/Library/Application Support/RawCull/Models/SAM3-coreai-torch-0.4.0-broken"
```

If either command reports `No such file or directory`, that copy simply does
not exist.

## 10. Install the regenerated model

Run:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull
make install-sam3-model
```

This copies the new bundle into sandboxed Application Support and runs the
repository's structural verification. Repeat verification explicitly if
desired:

```sh
make verify-model
```

Expected output ends with something similar to:

```text
SAM3 model installed at ... using sam3_float16.aimodel
```

If an AOT asset was selected, its filename should appear instead. This check
confirms that the files, tokenizer, and metadata exist; it does not by itself
prove that Core AI can specialize and execute the graph.

## 11. Build and test RawCull

Build Debug:

```sh
make build-debug
```

Locate the resulting application if needed:

```sh
make print-debug-app
```

Test with a small catalog before processing a large set:

1. Launch RawCull and open **Settings > AI**.
2. Confirm the SAM3 model reports **Installed**.
3. Load a catalog containing one or two representative images.
4. Start subject-mask generation for a single image.
5. Allow extra time for the first load and specialization.
6. Confirm model loading completes without IR or LLVM errors.
7. Confirm the progress UI advances through inference.
8. Verify that the resulting mask aligns with the requested subject.
9. Repeat with a small batch before processing a full catalog.

The first SAM3 run can take substantially longer because Core AI specializes
the portable model for the current hardware.

## 12. If it still crashes

First verify the exporter version and artifact:

```sh
uv run --with coreai-torch==0.4.1 python -c \
  'import importlib.metadata as m; print(m.version("coreai-torch"))'

shasum RawCull/Resources/Models/SAM3/sam3_float16.aimodel/main.mlirb
```

Then try the newest available compatible exporter by changing the dependency
to:

```python
"coreai-torch>=0.4.1",
```

Preserve the failed export and run `make sam3-export` again. Record the exact
resolved `coreai-torch`, Transformers, Torch, and Torchvision versions used.

If the same fatal IR error persists with `coreai-torch` 0.4.1 or newer, check
for a mismatch between the macOS 27 beta, Xcode 27 beta, and installed Metal
Toolchain:

1. Update macOS 27 and Xcode 27 to matching/current beta builds.
2. In Xcode, open **Settings > Components**.
3. Install or update the Metal Toolchain.
4. Re-export the model after updating.
5. If using AOT, rebuild the `.aimodelc` with the updated Xcode toolchain.
6. Test the portable `.aimodel` if the AOT asset fails.

If the portable asset works but the AOT asset does not, select the portable
asset and reinstall:

```sh
make sam3-use-asset ASSET=sam3_float16.aimodel
make install-sam3-model
```

## 13. Roll back if necessary

Do not start SAM3 mask generation. Preserve the failed new installation and
restore the old folder:

```sh
mv \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/SAM3" \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/SAM3-new-failed"

mv \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/SAM3-coreai-torch-0.4.0-broken" \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/SAM3"
```

The restored artifact remains incompatible if it was exported with
`coreai-torch` 0.4.0 and may still crash when loaded. The rollback preserves
the files for inspection; keep SAM3 operations disabled until a compatible
model is installed.
