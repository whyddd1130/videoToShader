# 单 Shader 特效训练数据集

该目录包含非转场、单 Shader 图片特效的已渲染训练集。

## 入口文件

- `manifest_train.jsonl`：仅包含可直接用于训练的样本。每一行都有 `status=rendered`、非空的 mp4 文件，以及对应的参数侧车 JSON。
- `manifest.jsonl`：所有尝试生成的样本，包括失败样本。
- `manifest_failed.jsonl`：打包或渲染失败的样本。
- `dataset_summary.json`：聚合统计和完整性检查结果。

## 样本布局

每个已渲染样本都由 `sample_id` 标识，通常格式为 `<EffectName>__<InputVariant>`。

```text
code/<EffectName or SampleId>/ 从源目录复制过来的插件源码
input_images/<InputVariant>.png 用于渲染的自定义输入图片
params/<SampleId>.json         参数关键帧和强度元数据
videos/<SampleId>/*.mp4        已渲染的 5 秒预览视频
materials/<SampleId>/          用于渲染的已打包 material
```

同一份特效代码可能对应多个已渲染样本，因为每个特效都会针对六种输入变体进行渲染：`model`、`ring_mask`、`rg_split`、`cross_lines`、`gray_ramp` 和 `color_gradient`。

## 数量统计

- 总尝试样本数：774
- 可用于训练的已渲染样本数：676
- 失败样本数：98
- 已渲染视频文件数：676
- 参数 JSON 文件数：694

失败特效：

- 原始数据集的失败项仍记录在 `dataset_summary.json` 中。
- 本次合并的剪映 single-pass 数据新增了 `low_temporal_change`、`near_black_video` 等失败类型；完整的逐特效统计见 `dataset_summary.json`。

## 参数元数据

对于每个已渲染样本，`params/<SampleId>.json` 记录了用于生成视频的参数动画。对训练最重要的字段包括：

- `sample_id`
- `effect_name`
- `input.variant`
- `input.image_path`
- `primary_strength_param`
- `video`
- `params[].keyframes[]`

关键帧会拉伸覆盖完整的 5 秒视频；在 25 fps 下，通常位于第 `0`、`62` 和 `124` 帧。
