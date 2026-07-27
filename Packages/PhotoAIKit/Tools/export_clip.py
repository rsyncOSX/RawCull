#!/usr/bin/env python3
# Copyright 2026 Apple Inc.
#
# Adapted from apple/coreai-models models/clip/export.py.
#
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "coreai-core==1.0.0b2",
#     "coreai-torch==0.4.1",
#     "transformers==4.57.3",
# ]
#
# [tool.uv]
# index-url       = "https://pypi.org/simple"
# prerelease      = "allow"
# index-strategy  = "unsafe-best-match"
# ///
from __future__ import annotations

import argparse
import json
import shutil
import time
from pathlib import Path

import torch
import transformers
from coreai.runtime import AIModelAssetMetadata
from coreai_torch import TorchConverter, get_decomp_table

from model_fingerprint import fingerprint_asset


class ClipModule(torch.nn.Module):
    def __init__(self, model_name: str):
        super().__init__()
        self._model = transformers.CLIPModel.from_pretrained(model_name)
        self.vision_model = self._model.vision_model
        self.text_model = self._model.text_model
        self.visual_projection = self._model.visual_projection
        self.text_projection = self._model.text_projection

    def forward(self, pixel_values, input_ids, attention_mask):
        vision_outputs = self.vision_model(pixel_values=pixel_values)
        image_embeds = self.visual_projection(vision_outputs[1])

        text_outputs = self.text_model(
            input_ids=input_ids,
            attention_mask=attention_mask,
        )
        text_embeds = self.text_projection(text_outputs[1])

        image_embeds = image_embeds / image_embeds.norm(p=2, dim=-1, keepdim=True)
        text_embeds = text_embeds / text_embeds.norm(p=2, dim=-1, keepdim=True)
        logit_scale = self._model.logit_scale.exp()
        logits_per_text = torch.matmul(text_embeds, image_embeds.t()) * logit_scale
        return logits_per_text.t(), logits_per_text, image_embeds, text_embeds


def reference_inputs(
    model_name: str,
    dtype: torch.dtype,
    dynamic: bool = False,
) -> dict[str, torch.Tensor]:
    tokenizer = transformers.AutoTokenizer.from_pretrained(model_name, use_fast=True)
    text_inputs = tokenizer(
        ["a photo of a cat", "a photo of a dog", "a photo of a goat"],
        return_tensors="pt",
        padding="max_length",
        max_length=77,
    )
    return {
        "pixel_values": torch.randn(2 if dynamic else 1, 3, 224, 224).to(dtype),
        "input_ids": text_inputs["input_ids"].to(torch.int32),
        "attention_mask": text_inputs["attention_mask"].to(torch.int32),
    }


def dynamic_shapes() -> dict:
    image_batch = torch.export.Dim("image_batch", min=1, max=64)
    text_batch = torch.export.Dim("text_batch", min=1, max=64)
    return {
        "pixel_values": {0: image_batch},
        "input_ids": {0: text_batch},
        "attention_mask": {0: text_batch},
    }


def variant_name(model_name: str, dtype: torch.dtype, dynamic: bool) -> str:
    safe_name = Path(model_name).name
    dtype_name = str(dtype).split(".")[-1]
    return f"{safe_name}_{dtype_name}_{'dynamic' if dynamic else 'static'}"


def build_aimodel_metadata() -> AIModelAssetMetadata:
    metadata = AIModelAssetMetadata()
    metadata.author = "A. Radford et al."
    metadata.license = "MIT"
    metadata.model_description = (
        "CLIP learns joint representations of images and text for zero-shot "
        "image classification and retrieval. Source: "
        "https://huggingface.co/openai/clip-vit-base-patch32"
    )
    metadata.creation_date = int(time.time())
    return metadata


def save_asset(coreai_program, model_path: Path) -> None:
    if model_path.exists():
        shutil.rmtree(model_path)
    coreai_program.save_asset(model_path, build_aimodel_metadata())


def write_tokenizer(destination: Path, model_name: str) -> None:
    print(f"[INFO] Saving tokenizer from {model_name} to {destination}...")
    tokenizer = transformers.AutoTokenizer.from_pretrained(model_name, use_fast=True)
    tokenizer.save_pretrained(str(destination))


def write_bundle_metadata(
    bundle_dir: Path,
    model_name: str,
    variant: str,
    main_asset: str,
    dynamic: bool,
) -> None:
    metadata = {
        "metadata_version": "0.3",
        "kind": "embedding",
        "family": "clip",
        "source_model": model_name,
        "name": variant,
        "preprocessing_version": "clip-srgb-bilinear-chw-v1",
        "configuration_version": "coreai-clip-image-v1",
        "inputs": {
            "pixel_values": [1 if not dynamic else "1...64", 3, 224, 224],
            "input_ids": [2 if not dynamic else "1...64", 77],
            "attention_mask": [2 if not dynamic else "1...64", 77],
        },
        "outputs": [
            "logits_per_image",
            "logits_per_text",
            "image_embeds",
            "text_embeds",
        ],
        "assets": {"main": main_asset},
        "asset_fingerprints": {
            "main": fingerprint_asset(bundle_dir / main_asset),
        },
    }
    metadata_path = bundle_dir / "metadata.json"
    with metadata_path.open("w") as stream:
        json.dump(metadata, stream, indent=2)
        stream.write("\n")
    print(f"[INFO] Wrote metadata to {metadata_path}.")


def create_clip(
    output_dir: Path,
    bundle_name: str,
    model_name: str,
    dtype: torch.dtype,
    overwrite: bool,
    dynamic: bool,
) -> None:
    print("[INFO] Sourcing model...")
    model = ClipModule(model_name)
    model.eval()
    model.to(dtype)

    print("[INFO] Model sourced. Running torch export with decompositions...")
    example_inputs = reference_inputs(model_name, dtype, dynamic)
    with torch.autocast(device_type="cpu", dtype=dtype):
        exported = torch.export.export(
            model,
            args=(),
            kwargs=example_inputs,
            dynamic_shapes=dynamic_shapes() if dynamic else None,
        )
    exported = exported.run_decompositions(get_decomp_table())

    print("[INFO] Model exported. Converting to Core AI...")
    converter = TorchConverter().add_exported_program(
        exported_program=exported,
        input_names=["pixel_values", "input_ids", "attention_mask"],
        output_names=[
            "logits_per_image",
            "logits_per_text",
            "image_embeds",
            "text_embeds",
        ],
    )
    coreai_program = converter.to_coreai()

    variant = variant_name(model_name, dtype, dynamic)
    bundle_dir = output_dir.resolve() / bundle_name
    if bundle_dir.exists():
        if not overwrite:
            raise FileExistsError(f"{bundle_dir} already exists. Pass --overwrite.")
        shutil.rmtree(bundle_dir)
    bundle_dir.mkdir(parents=True, exist_ok=True)

    source_model_path = bundle_dir / f"{variant}_source.aimodel"
    print(f"[INFO] Saving AOT source model to {source_model_path}...")
    save_asset(coreai_program, source_model_path)

    print("[INFO] Optimizing runtime model...")
    coreai_program.optimize()
    model_path = bundle_dir / f"{variant}.aimodel"
    save_asset(coreai_program, model_path)

    write_tokenizer(bundle_dir / "tokenizer", model_name)
    write_bundle_metadata(bundle_dir, model_name, variant, model_path.name, dynamic)
    print(f"[INFO] CLIP bundle ready at {bundle_dir}.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export a PhotoAIKit-compatible CLIP Core AI bundle.",
    )
    parser.add_argument(
        "--model",
        choices=["openai/clip-vit-base-patch32"],
        default="openai/clip-vit-base-patch32",
        help="Model variant to convert.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Explicit directory that will contain the CLIP bundle.",
    )
    parser.add_argument("--bundle-name", default="CLIP")
    parser.add_argument(
        "--dtype",
        choices=["float16", "bfloat16", "float32"],
        default="float16",
    )
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--dynamic", action="store_true")
    args = parser.parse_args()

    dtype = {
        "float16": torch.float16,
        "bfloat16": torch.bfloat16,
        "float32": torch.float32,
    }[args.dtype]
    create_clip(
        output_dir=args.output_dir,
        bundle_name=args.bundle_name,
        model_name=args.model,
        dtype=dtype,
        overwrite=args.overwrite,
        dynamic=args.dynamic,
    )


if __name__ == "__main__":
    main()
