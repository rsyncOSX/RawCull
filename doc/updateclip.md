# Updating the CLIP Core AI Model

Older CLIP model artifacts were exported with `coreai-torch==0.4.0`. On macOS
27, Core AI can fail while specializing models produced by that version,
ending in messages such as:

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

The authoritative developer model directory is now:

```text
/Users/thomas/GitHub/Models/CLIP
```

This directory contains the PhotoAIKit-compatible Core AI bundle used as the
source for local installation. It is separate from RawCull's installed runtime
copy under Application Support. Hugging Face checkpoint files are cached under
`/Users/thomas/GitHub/Models/.huggingface` during export.

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

## 3. Get CLIP from Hugging Face and prepare it for conversion

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
   account associated with the token.

3. Preview the checkpoint download and confirm there is enough disk space:

   ```sh
   df -h "$RAWCULL_MODELS_DIR"
   uvx hf download openai/clip-vit-base-patch32 \
     --exclude flax_model.msgpack \
     --exclude tf_model.h5 \
     --dry-run
   ```

   The PhotoAIKit exporter uses the PyTorch weights. Excluding the Flax and
   TensorFlow copies avoids downloading two unused 600 MB weight files.

4. Download the checkpoint into the cache shared with the exporter:

   ```sh
   CLIP_SNAPSHOT="$(uvx hf download openai/clip-vit-base-patch32 \
     --exclude flax_model.msgpack \
     --exclude tf_model.h5 \
     --quiet)"
   printf 'CLIP snapshot: %s\n' "$CLIP_SNAPSHOT"
   ```

   The [`hf download` CLI](https://huggingface.co/docs/huggingface_hub/en/package_reference/cli#hf-download)
   uses `HF_TOKEN` for authentication and `HF_HOME` for its local cache.

5. Verify the files required by `CLIPModel` and the tokenizer:

   ```sh
   test -f "$CLIP_SNAPSHOT/config.json"
   test -f "$CLIP_SNAPSHOT/pytorch_model.bin"
   test -f "$CLIP_SNAPSHOT/tokenizer.json"
   test -f "$CLIP_SNAPSHOT/tokenizer_config.json"
   test -f "$CLIP_SNAPSHOT/merges.txt"
   test -f "$CLIP_SNAPSHOT/vocab.json"
   printf 'Hugging Face revision: %s\n' "$(basename "$CLIP_SNAPSHOT")"
   ```

   Record the printed snapshot revision with the converted artifact. The
   [CLIP repository](https://huggingface.co/openai/clip-vit-base-patch32/tree/main)
   lists the PyTorch and tokenizer files. If a command returns HTTP 401 or 403,
   stop and verify that `HF_TOKEN` belongs to the expected account.

6. Freeze model resolution to the downloaded snapshot for conversion:

   ```sh
   export HF_HUB_OFFLINE=1
   ```

   Leave `HF_HOME`, `HF_TOKEN`, and `HF_HUB_OFFLINE` exported. The conversion
   command in section 6 uses Transformers'
   `from_pretrained("openai/clip-vit-base-patch32")`. Offline mode prevents a
   later `main` revision from being fetched between the explicit download and
   conversion, and the exporter produces the source `.aimodel` needed by
   `coreai-build`.

## 4. Verify the exporter dependency

Open `../PhotoAIKit/Tools/export_clip.py` and verify that it contains:

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

## 5. Preserve the old developer model source

The export uses `--overwrite`, so preserve the existing model first:

```sh
mv /Users/thomas/GitHub/Models/CLIP \
   /Users/thomas/GitHub/Models/CLIP-coreai-torch-0.4.0-broken
```

Confirm the backup exists:

```sh
du -sh /Users/thomas/GitHub/Models/CLIP-coreai-torch-0.4.0-broken
```

Do not rename the installed Application Support copy yet. Keeping it in place
provides a simple rollback until the new export succeeds.

## 6. Convert CLIP to a Core AI bundle

From the RawCull repository root, run the PhotoAIKit exporter directly. Keep
the Hugging Face environment values from section 3 in this shell:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull
uv run ../PhotoAIKit/Tools/export_clip.py \
  --output-dir /Users/thomas/GitHub/Models \
  --bundle-name CLIP \
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
[INFO] Optimizing runtime model...
[INFO] CLIP bundle ready...
```

The resulting directory should contain:

```text
/Users/thomas/GitHub/Models/CLIP/
|-- metadata.json
|-- clip-vit-base-patch32_float16_static.aimodel
|-- clip-vit-base-patch32_float16_static_source.aimodel
`-- tokenizer/
```

The application should use the optimized asset rather than the source asset.
Check `assets.main`:

```sh
python3 -c 'import json; print(json.load(open("/Users/thomas/GitHub/Models/CLIP/metadata.json"))["assets"]["main"])'
```

Expected output:

```text
clip-vit-base-patch32_float16_static.aimodel
```

The portable `clip-vit-base-patch32_float16_static.aimodel` is ready for
RawCull. The `_source.aimodel` variant is the input for optional ahead-of-time
compilation in section 9; do not pass the optimized runtime asset to
`coreai-build`.

## 7. Confirm that a new artifact was produced

Compare the old and new graph hashes:

```sh
shasum \
  /Users/thomas/GitHub/Models/CLIP-coreai-torch-0.4.0-broken/clip-vit-base-patch32_float16_static.aimodel/main.mlirb \
  /Users/thomas/GitHub/Models/CLIP/clip-vit-base-patch32_float16_static.aimodel/main.mlirb
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

## 8. Validate with Core AI Debugger

Apple provides Core AI Debugger for inspecting, specializing, executing, and
validating `.aimodel` assets:

<https://developer.apple.com/core-ai-debugger/>

Open this model in the debugger:

```text
/Users/thomas/GitHub/Models/CLIP/clip-vit-base-patch32_float16_static.aimodel
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

If the installed Xcode does not expose `xcrun coreai-build`, skip the optional
AOT compilation in the next section. Use Core AI Debugger or an isolated
RawCull launch to validate the portable asset instead.

## 9. Optionally compile an AOT asset

This step is optional. First check whether the compiler is available:

```sh
xcrun --find coreai-build
```

If it is available, compile the source asset rather than the already optimized
runtime asset:

```sh
xcrun coreai-build compile \
  /Users/thomas/GitHub/Models/CLIP/clip-vit-base-patch32_float16_static_source.aimodel \
  --platform macOS \
  --architecture h16c \
  --output /Users/thomas/GitHub/Models/CLIP
```

`h16c` is the architecture used by the current local Apple M4 artifacts. Query
the local Core AI device architecture and use that value instead when targeting
another Mac. To see the compiler's current options, run:

```sh
xcrun coreai-build compile --help
```

List the generated AOT bundle:

```sh
find /Users/thomas/GitHub/Models/CLIP \
  -maxdepth 1 -name '*.aimodelc' -type d -print
```

The portable `.aimodel` remains selected unless the AOT asset is explicitly
chosen. To choose it, update both `assets.main` and its fingerprint. The
currently available PhotoAIKit selector has a legacy SAM3-specific filename,
but its implementation works with either compatible bundle:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull
python3 ../PhotoAIKit/Tools/select_sam3_asset.py \
  <generated-file>.aimodelc \
  --bundle-dir /Users/thomas/GitHub/Models/CLIP
```

Verify the selection:

```sh
python3 -c 'import json; print(json.load(open("/Users/thomas/GitHub/Models/CLIP/metadata.json"))["assets"]["main"])'
```

If compilation fails, keep or restore the portable asset selection:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull
python3 ../PhotoAIKit/Tools/select_sam3_asset.py \
  clip-vit-base-patch32_float16_static.aimodel \
  --bundle-dir /Users/thomas/GitHub/Models/CLIP
```

## 10. Back up the installed faulty model

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

## 11. Install the regenerated model

Copy the regenerated bundle from the authoritative developer source into
RawCull's sandboxed Application Support location:

```sh
CLIP_SOURCE=/Users/thomas/GitHub/Models/CLIP
CLIP_INSTALL_DIR="$HOME/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/CLIP"
mkdir -p "$(dirname "$CLIP_INSTALL_DIR")"
rsync -a --exclude .DS_Store "$CLIP_SOURCE/" "$CLIP_INSTALL_DIR/"
```

Verify the installed structure and the asset selected by `metadata.json`:

```sh
test -f "$CLIP_INSTALL_DIR/metadata.json"
test -f "$CLIP_INSTALL_DIR/tokenizer/tokenizer.json"
CLIP_ASSET="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["assets"]["main"])' "$CLIP_INSTALL_DIR/metadata.json")"
test -e "$CLIP_INSTALL_DIR/$CLIP_ASSET"
printf 'CLIP model installed at %s using %s\n' "$CLIP_INSTALL_DIR" "$CLIP_ASSET"
```

Expected output ends with something similar to:

```text
CLIP model installed at ... using clip-vit-base-patch32_float16_static.aimodel
```

This check confirms that the files and metadata exist. It does not by itself
prove that Core AI can specialize the graph.

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

## 13. If it still crashes

First verify the exporter version and new artifact:

```sh
uv run --with coreai-torch==0.4.1 python -c \
  'import importlib.metadata as m; print(m.version("coreai-torch"))'

shasum /Users/thomas/GitHub/Models/CLIP/clip-vit-base-patch32_float16_static.aimodel/main.mlirb
```

Then try the newest available compatible exporter by changing the dependency
to:

```python
"coreai-torch>=0.4.1",
```

Preserve the failed export and repeat the direct conversion command from
section 6. Record the exact resolved version used for that export.

If the same fatal IR error persists with version 0.4.1 or newer, check for a
mismatch between the macOS 27 beta, Xcode 27 beta, and installed Metal
Toolchain component:

1. Update macOS 27 and Xcode 27 to matching/current beta builds.
2. In Xcode, open **Settings > Components**.
3. Install or update the Metal Toolchain.
4. Re-export the model after updating.
5. Do not reuse an `.aimodelc` generated by Xcode 27 Beta 2 or earlier; rebuild
   it with Beta 3 or newer.

## 14. Roll back if necessary

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
