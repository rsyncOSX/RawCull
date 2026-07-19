# Updating the CLIP Core AI Model

The current CLIP model was exported with `coreai-torch==0.4.0`. On macOS 27,
Core AI can fail while specializing models produced by that version, ending in
messages such as:

```text
error: expected AICode versioned location
error: Failed to convert to versioned IR
LLVM ERROR: cannot unwrap empty `odiec_module_t`
```

Apple's macOS 27 release notes recommend converting the model with
`coreai-torch` 0.4.1 or newer:

<https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes?changes=l_2>

The LLVM failure terminates the process and cannot be caught by RawCull's Swift
fallback to Vision feature prints. Follow this procedure to regenerate and
install a compatible CLIP model.

## 1. Disable CLIP temporarily

Before changing the model:

1. Launch RawCull.
2. Open **Settings > AI**.
3. Turn off **Use CLIP for similarity**.
4. Restart RawCull.

Burst analysis will use Vision feature prints and avoid loading the faulty
CLIP asset.

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

The export downloads the Hugging Face CLIP model and Python dependencies. It
requires network access and several gigabytes of free temporary disk space.

## 3. Update the exporter dependency

Open `../PhotoAIKit/tools/export_clip.py` and change:

```python
"coreai-torch==0.4.0",
```

to:

```python
"coreai-torch==0.4.1",
```

Update `coreai-core` to the version required by `coreai-torch` 0.4.1. The
dependency block should be:

```python
dependencies = [
    "coreai-core==1.0.0b2",
    "coreai-torch==0.4.1",
    "transformers==4.57.3",
]
```

`coreai-torch==0.4.1` requires `coreai-core==1.0.0b2`; retaining b1 makes the
dependency set unsatisfiable. Exact versions make the export reproducible.
Changing the inline dependency declaration causes `uv` to create or select an
environment matching the new specification.

## 4. Preserve the old development bundle

The export uses `--overwrite`, so preserve the existing model first:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull

mv RawCull/Resources/Models/CLIP \
   RawCull/Resources/Models/CLIP-coreai-torch-0.4.0-broken
```

Confirm the backup exists:

```sh
du -sh RawCull/Resources/Models/CLIP-coreai-torch-0.4.0-broken
```

Do not rename the installed Application Support copy yet. Keeping it in place
provides a simple rollback until the new export succeeds.

## 5. Re-export CLIP

Run:

```sh
make clip-export
```

The equivalent direct command is:

```sh
uv run ../PhotoAIKit/tools/export_clip.py \
  --output-dir RawCull/Resources/Models \
  --bundle-name CLIP \
  --dtype float16 \
  --overwrite
```

Expected stages include:

```text
[INFO] Sourcing model...
[INFO] Model exported. Converting to Core AI...
[INFO] Model converted.
[INFO] Optimizing runtime model...
[INFO] CLIP bundle ready...
```

The resulting directory should contain:

```text
RawCull/Resources/Models/CLIP/
|-- metadata.json
|-- clip-vit-base-patch32_float16_static.aimodel
|-- clip-vit-base-patch32_float16_static_source.aimodel
`-- tokenizer/
```

The application should use the optimized asset rather than the source asset.
Check `assets.main`:

```sh
python3 -c 'import json; print(json.load(open("RawCull/Resources/Models/CLIP/metadata.json"))["assets"]["main"])'
```

Expected output:

```text
clip-vit-base-patch32_float16_static.aimodel
```

## 6. Confirm that a new artifact was produced

Compare the old and new graph hashes:

```sh
shasum \
  RawCull/Resources/Models/CLIP-coreai-torch-0.4.0-broken/clip-vit-base-patch32_float16_static.aimodel/main.mlirb \
  RawCull/Resources/Models/CLIP/clip-vit-base-patch32_float16_static.aimodel/main.mlirb
```

The hashes should differ. If they are identical, verify the installed Python
package version:

```sh
uv run --with coreai-torch==0.4.1 python -c \
  'import importlib.metadata as m; print(m.version("coreai-torch"))'
```

Expected output:

```text
0.4.1
```

## 7. Validate with Core AI Debugger

Apple provides Core AI Debugger for inspecting, specializing, executing, and
validating `.aimodel` assets:

<https://developer.apple.com/core-ai-debugger/>

Open this model in the debugger:

```text
/Users/thomas/GitHub/RawCull/RawCull/RawCull/Resources/Models/CLIP/clip-vit-base-patch32_float16_static.aimodel
```

Confirm that:

- The model opens without an IR conversion error.
- A `main` function exists.
- Inputs include `pixel_values`, `input_ids`, and `attention_mask`.
- Outputs include `image_embeds`.
- Specialization completes on the local Mac.

Loading an `.aimodel` performs device-specific specialization and normally
caches the result. See Apple's documentation:

<https://developer.apple.com/documentation/CoreAI/managing-model-specialization-and-caching>

If the installed Xcode does not expose `xcrun coreai-build`, do not use
`make clip-compile` as the validation step. Use Core AI Debugger or an isolated
RawCull launch instead.

## 8. Back up the installed faulty model

Quit RawCull completely.

The sandboxed runtime installation is:

```text
~/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/CLIP
```

Rename it:

```sh
mv \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/CLIP" \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/CLIP-coreai-torch-0.4.0-broken"
```

There may also be a non-container development copy:

```text
~/Library/Application Support/RawCull/Models/CLIP
```

To avoid ambiguity, preserve that copy too if it exists:

```sh
mv \
  "$HOME/Library/Application Support/RawCull/Models/CLIP" \
  "$HOME/Library/Application Support/RawCull/Models/CLIP-coreai-torch-0.4.0-broken"
```

If either command reports `No such file or directory`, that copy simply does
not exist.

## 9. Install the regenerated model

Run:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull
make install-clip-model
```

This copies the new bundle into the sandboxed Application Support location and
runs the repository's structural verification. Repeat verification explicitly
if desired:

```sh
make verify-clip-model
```

Expected output ends with something similar to:

```text
CLIP model installed at ... using clip-vit-base-patch32_float16_static.aimodel
```

This check confirms that the files and metadata exist. It does not by itself
prove that Core AI can specialize the graph.

## 10. Build and test RawCull

Build Debug:

```sh
make build-debug
```

Locate the resulting application if needed:

```sh
make print-debug-app
```

Test in this order:

1. Start with **Use CLIP for similarity** disabled.
2. Load a small catalog of approximately 5-10 images.
3. Confirm burst analysis completes using Vision.
4. Open **Settings > AI**.
5. Confirm CLIP reports **Installed**.
6. Enable **Use CLIP for similarity**.
7. Reindex burst analysis.
8. Watch the transition from sharpness scoring to similarity indexing.
9. Confirm grouping and ranking complete.
10. Check that the backend reports CLIP rather than Vision fallback.

The first CLIP run can take longer because Core AI specializes the portable
`.aimodel` for the current hardware.

## 11. If it still crashes

First verify the exporter version and new artifact:

```sh
uv run --with coreai-torch==0.4.1 python -c \
  'import importlib.metadata as m; print(m.version("coreai-torch"))'

shasum RawCull/Resources/Models/CLIP/clip-vit-base-patch32_float16_static.aimodel/main.mlirb
```

Then try the newest available compatible exporter by changing the dependency
to:

```python
"coreai-torch>=0.4.1",
```

Preserve the failed export and run `make clip-export` again. Record the exact
resolved version used for that export.

If the same fatal IR error persists with version 0.4.1 or newer, check for a
mismatch between the macOS 27 beta, Xcode 27 beta, and installed Metal
Toolchain component:

1. Update macOS 27 and Xcode 27 to matching/current beta builds.
2. In Xcode, open **Settings > Components**.
3. Install or update the Metal Toolchain.
4. Re-export the model after updating.
5. Do not reuse an `.aimodelc` generated by Xcode 27 Beta 2 or earlier; rebuild
   it with Beta 3 or newer.

## 12. Roll back if necessary

Keep CLIP disabled. Preserve the failed new installation and restore the old
folder:

```sh
mv \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/CLIP" \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/CLIP-new-failed"

mv \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/CLIP-coreai-torch-0.4.0-broken" \
  "$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/CLIP"
```

The restored artifact remains incompatible and can still crash if CLIP is
enabled. The rollback only preserves the files while RawCull continues using
Vision similarity.
