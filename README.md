# Single Shader Effect Training Dataset

This directory contains the rendered training set for non-transition, single-shader picture effects.

## Entry Points

- `manifest_train.jsonl`: training-ready samples only. Every row has `status=rendered`, a non-empty mp4, and a parameter sidecar JSON.
- `manifest.jsonl`: all attempted samples, including failures.
- `manifest_failed.jsonl`: samples that failed packaging or rendering.
- `dataset_summary.json`: aggregate counts and integrity check results.

## Sample Layout

Each rendered sample is keyed by `sample_id`, usually `<EffectName>__<InputVariant>`.

```text
code/<EffectName or SampleId>/ plugin source code copied from the source tree
input_images/<InputVariant>.png custom input images used for rendering
params/<SampleId>.json         parameter keyframes and strength metadata
videos/<SampleId>/*.mp4        rendered 5 second preview video
materials/<SampleId>/          packaged material used for rendering
```

The same effect code can map to multiple rendered samples because each effect is rendered against six input variants: `model`, `ring_mask`, `rg_split`, `cross_lines`, `gray_ramp`, and `color_gradient`.

## Counts

- Total attempted samples: 774
- Training-ready rendered samples: 676
- Failed samples: 98
- Rendered video files: 676
- Parameter JSON files: 694

Failed effects:

- Original dataset failures are still listed in `dataset_summary.json`.
- The merged Jianying single-pass batch adds failures such as `low_temporal_change` and `near_black_video`; see `dataset_summary.json` for the full per-effect breakdown.

## Parameter Metadata

For each rendered sample, `params/<SampleId>.json` records the parameter animation used to produce the video. The most important fields for training are:

- `sample_id`
- `effect_name`
- `input.variant`
- `input.image_path`
- `primary_strength_param`
- `video`
- `params[].keyframes[]`

Keyframes are stretched across the full 5 second video, usually frame `0`, `62`, and `124` at 25 fps.
