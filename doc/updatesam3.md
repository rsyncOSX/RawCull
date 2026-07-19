# Updating the SAM3 Core AI Model

Older SAM3 model artifacts were exported with `coreai-torch==0.4.0`. On macOS
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

The authoritative developer model directory is now:

```text
/Users/thomas/GitHub/Models/SAM3
```

This directory contains the PhotoAIKit-compatible Core AI bundle used as the
source for local installation. It is separate from RawCull's installed runtime
copy under Application Support. Hugging Face checkpoint files are cached under
`/Users/thomas/GitHub/Models/.huggingface` during export.

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
requires network access, approved access to the gated `facebook/sam3`
repository, and substantial free disk space. Keep enough space for the
downloaded weights, Python environment, old backup, source `.aimodel`, and
optimized `.aimodel`.

## 3. Get SAM3 from Hugging Face and prepare it for conversion

The token already exists, so start by placing it in `HF_TOKEN` without writing
it into shell history. Run these commands in zsh:

```sh
read -s "HF_TOKEN?Hugging Face token: "
export HF_TOKEN
echo
```

Keep this terminal open for the remaining download and export steps. Do not
paste the token into the document, a script, a Git-tracked file, or a command
argument.

1. Define the common model root and keep the Hugging Face cache beneath it:

   ```sh
   export RAWCULL_MODELS_DIR=/Users/thomas/GitHub/Models
   export HF_HOME="$RAWCULL_MODELS_DIR/.huggingface"
   mkdir -p "$HF_HOME"
   ```

2. Run the current Hugging Face CLI with `uvx`:

   ```sh
   uvx hf version
   uvx hf auth whoami
   ```

   [`uvx hf`](https://huggingface.co/docs/huggingface_hub/en/guides/cli#using-uv)
   runs the CLI in an isolated environment. `hf auth whoami` must identify the
   account associated with the token. `facebook/sam3` is gated, so that account
   must already have model access.

3. Preview the checkpoint download and confirm there is enough disk space:

   ```sh
   df -h "$RAWCULL_MODELS_DIR"
   uvx hf download facebook/sam3 --exclude sam3.pt --dry-run
   ```

   The Transformers exporter uses `model.safetensors`; excluding `sam3.pt`
   avoids downloading a second multi-gigabyte representation of the weights.

4. Download the checkpoint into the cache shared with the exporter:

   ```sh
   SAM3_SNAPSHOT="$(uvx hf download facebook/sam3 \
     --exclude sam3.pt \
     --quiet)"
   printf 'SAM3 snapshot: %s\n' "$SAM3_SNAPSHOT"
   ```

   The [`hf download` CLI](https://huggingface.co/docs/huggingface_hub/en/package_reference/cli#hf-download)
   uses `HF_TOKEN` for authenticated repositories and `HF_HOME` for its local
   cache.

5. Verify the files required by `Sam3Model`, `Sam3Processor`, and the tokenizer:

   ```sh
   test -f "$SAM3_SNAPSHOT/config.json"
   test -f "$SAM3_SNAPSHOT/model.safetensors"
   test -f "$SAM3_SNAPSHOT/processor_config.json"
   test -f "$SAM3_SNAPSHOT/tokenizer.json"
   test -f "$SAM3_SNAPSHOT/tokenizer_config.json"
   printf 'Hugging Face revision: %s\n' "$(basename "$SAM3_SNAPSHOT")"
   ```

   Record the printed snapshot revision with the converted artifact. The
   [SAM3 repository](https://huggingface.co/facebook/sam3/tree/main) lists the
   checkpoint and tokenizer files. If a command returns HTTP 401 or 403, stop:
   the token or gated-model access is not valid for this account.

6. Freeze model resolution to the downloaded snapshot for conversion:

   ```sh
   export HF_HUB_OFFLINE=1
   ```

   Leave `HF_HOME`, `HF_TOKEN`, and `HF_HUB_OFFLINE` exported. The conversion
   command in section 6 uses Transformers' `from_pretrained("facebook/sam3")`.
   Offline mode prevents a later `main` revision from being fetched between
   the explicit download and conversion, and the exporter produces the source
   `.aimodel` needed by `coreai-build`.

## 4. Verify the exporter dependency

Open `../PhotoAIKit/Tools/export_sam3.py` and verify that it contains:

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

## 5. Preserve the old developer model source

The export uses `--overwrite`, so preserve the existing bundle first:

```sh
mv /Users/thomas/GitHub/Models/SAM3 \
   /Users/thomas/GitHub/Models/SAM3-coreai-torch-0.4.0-broken
```

Confirm the backup exists:

```sh
du -sh /Users/thomas/GitHub/Models/SAM3-coreai-torch-0.4.0-broken
```

Do not rename the installed Application Support copy yet. Keeping it in place
provides a rollback until the new export succeeds.

## 6. Convert SAM3 to a Core AI bundle

From the RawCull repository root, run the PhotoAIKit exporter directly. Keep
the Hugging Face environment values from section 3 in this shell:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull
uv run ../PhotoAIKit/Tools/export_sam3.py \
  --output-dir /Users/thomas/GitHub/Models \
  --bundle-name SAM3 \
  --dtype float16 \
  --overwrite
```

After the conversion finishes, re-enable normal Hub access:

```sh
unset HF_HUB_OFFLINE
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
/Users/thomas/GitHub/Models/SAM3/
|-- metadata.json
|-- sam3_float16.aimodel
|-- sam3_float16_source.aimodel
`-- tokenizer/
```

The normal portable runtime asset is `sam3_float16.aimodel`. Check the bundle's
selected asset:

```sh
python3 -c 'import json; print(json.load(open("/Users/thomas/GitHub/Models/SAM3/metadata.json"))["assets"]["main"])'
```

Expected output before optional AOT compilation:

```text
sam3_float16.aimodel
```

The portable `sam3_float16.aimodel` is ready for RawCull. The
`sam3_float16_source.aimodel` is the input for optional ahead-of-time
compilation in section 9; do not pass the optimized runtime asset to
`coreai-build`.

## 7. Confirm that a new artifact was produced

Compare the old and new optimized graph hashes:

```sh
shasum \
  /Users/thomas/GitHub/Models/SAM3-coreai-torch-0.4.0-broken/sam3_float16.aimodel/main.mlirb \
  /Users/thomas/GitHub/Models/SAM3/sam3_float16.aimodel/main.mlirb
```

The hashes should differ. If either bundle uses a different internal filename,
list it first:

```sh
find /Users/thomas/GitHub/Models/SAM3 -maxdepth 2 -type f -print
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

## 8. Validate the portable model

Apple provides Core AI Debugger for inspecting, specializing, executing, and
validating `.aimodel` assets:

<https://developer.apple.com/core-ai-debugger/>

Open this optimized portable asset:

```text
/Users/thomas/GitHub/Models/SAM3/sam3_float16.aimodel
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

## 9. Optionally compile an AOT asset

This step is optional. First check whether the compiler is available:

```sh
xcrun --find coreai-build
```

If it is available, compile the source asset rather than the already optimized
runtime asset:

```sh
xcrun coreai-build compile \
  /Users/thomas/GitHub/Models/SAM3/sam3_float16_source.aimodel \
  --platform macOS \
  --architecture h16c \
  --output /Users/thomas/GitHub/Models/SAM3
```

`h16c` is the architecture used by the current local Apple M4 artifact. Query
the local Core AI device architecture and use that value instead when targeting
another Mac. To see the compiler's current options, run:

```sh
xcrun coreai-build compile --help
```

To ask the compiler to emit all supported variants, omit `--architecture`:

```sh
xcrun coreai-build compile \
  /Users/thomas/GitHub/Models/SAM3/sam3_float16_source.aimodel \
  --platform macOS \
  --output /Users/thomas/GitHub/Models/SAM3
```

If compilation produces an `.aimodelc` directly inside the SAM3 bundle, point
`metadata.json` at it with PhotoAIKit's selector. The selector updates both
`assets.main` and its fingerprint:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull
python3 ../PhotoAIKit/Tools/select_sam3_asset.py \
  <generated-file>.aimodelc \
  --bundle-dir /Users/thomas/GitHub/Models/SAM3
```

Verify the selection:

```sh
python3 -c 'import json; print(json.load(open("/Users/thomas/GitHub/Models/SAM3/metadata.json"))["assets"]["main"])'
```

If compilation fails, or the compiler reports missing source bytecode, leave
the metadata pointed at the portable asset:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull
python3 ../PhotoAIKit/Tools/select_sam3_asset.py \
  sam3_float16.aimodel \
  --bundle-dir /Users/thomas/GitHub/Models/SAM3
```

Do not use an `.aimodelc` generated by Xcode 27 Beta 2 or earlier. Apple's
macOS 27 release notes recommend recompiling old AOT assets with Xcode 27 Beta
3 or newer.

## 10. Back up the installed faulty model

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

## 11. Install the regenerated model

Copy the regenerated bundle from the authoritative developer source into
RawCull's sandboxed Application Support location:

```sh
SAM3_SOURCE=/Users/thomas/GitHub/Models/SAM3
SAM3_INSTALL_DIR="$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/SAM3"
mkdir -p "$(dirname "$SAM3_INSTALL_DIR")"
rsync -a --exclude .DS_Store "$SAM3_SOURCE/" "$SAM3_INSTALL_DIR/"
```

Verify the installed structure and the asset selected by `metadata.json`:

```sh
test -f "$SAM3_INSTALL_DIR/metadata.json"
test -f "$SAM3_INSTALL_DIR/tokenizer/tokenizer.json"
SAM3_ASSET="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["assets"]["main"])' "$SAM3_INSTALL_DIR/metadata.json")"
test -e "$SAM3_INSTALL_DIR/$SAM3_ASSET"
printf 'SAM3 model installed at %s using %s\n' "$SAM3_INSTALL_DIR" "$SAM3_ASSET"
```

Expected output ends with something similar to:

```text
SAM3 model installed at ... using sam3_float16.aimodel
```

If an AOT asset was selected, its filename should appear instead. This check
confirms that the files, tokenizer, and metadata exist; it does not by itself
prove that Core AI can specialize and execute the graph.

## 12. Build and test RawCull

Build Debug:

```sh
make debug
```

Locate the resulting application if needed:

```sh
find /Users/thomas/GitHub/RawCull/RawCull/build \
  -maxdepth 2 -name RawCull.app -type d -print
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

## 13. If it still crashes

First verify the exporter version and artifact:

```sh
uv run --with coreai-torch==0.4.1 python -c \
  'import importlib.metadata as m; print(m.version("coreai-torch"))'

shasum /Users/thomas/GitHub/Models/SAM3/sam3_float16.aimodel/main.mlirb
```

Then try the newest available compatible exporter by changing the dependency
to:

```python
"coreai-torch>=0.4.1",
```

Preserve the failed export and repeat the direct conversion command from
section 6. Record the exact resolved `coreai-torch`, Transformers, Torch, and
Torchvision versions used.

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
cd /Users/thomas/GitHub/RawCull/RawCull
python3 ../PhotoAIKit/Tools/select_sam3_asset.py \
  sam3_float16.aimodel \
  --bundle-dir /Users/thomas/GitHub/Models/SAM3
```

Then reinstall it using section 11.

## 14. Roll back if necessary

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
