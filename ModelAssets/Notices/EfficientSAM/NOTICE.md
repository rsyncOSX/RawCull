# EfficientSAM third-party notices

This notice catalog is prepared for RawCull's converted
`efficient_sam_vitt_float16_static_q64.aimodel` asset. The planned export uses
EfficientSAM-Ti with 64 independent point queries, allowing PhotoAIKit to use
an 8×8 point grid for local subject discovery.

## Components and licences

- The EfficientSAM implementation and EfficientSAM-Ti checkpoint are
  distributed under Apache License 2.0. The complete licence is in
  `EfficientSAM-Apache-2.0.txt`.
- The conversion recipe was adapted from Apple `coreai-models`. Its complete
  BSD 3-Clause notice is in `Apple-coreai-models-BSD-3-Clause.txt`.

The immutable source and checkpoint revisions, verified checkpoint checksum,
planned conversion configuration, and remaining evidence fields are recorded
in `PROVENANCE.json`. Preserve this entire directory with every redistributed
copy of the asset pack.

## Preparation status

The upstream source, checkpoint, conversion recipe, and complete licence texts
are recorded. Distribution remains blocked until the exact final converted
bundle is validated, its runtime fingerprint is recorded, and the generated
Managed Background Assets archive has a recorded byte size and SHA-256.

The model can produce inaccurate or biased results and is provided without
warranty under the accompanying licences.
