# IR 实现思路

## 1. 目标和约束

当前阶段的目标是：

```text
输入：原始图片 + 该图片经过某个特效渲染后的视频关键帧
输出：库中特效候选排序
目标：尽量识别出该视频对应库中的哪个特效
```

实际部署时有一个关键约束：

```text
库侧只能拿到特效代码，不能拿到库中特效在同输入图上的渲染视频。
```

因此，正式可落地方案必须满足：

```text
库侧：代码 -> IR
查询侧：原始图 + 视频关键帧 -> IR
比较：查询 IR vs 库 IR
```

之前的 `visual_template_score` 需要库侧模板视频，只能作为离线实验上限，不能作为最终部署方案。

## 2. 当前可落地方案

当前可落地方案是：

```text
结构化 IR + 变化签名 + 诊断关键词
```

它不依赖库侧视频，只依赖库侧由代码生成的 IR。

92 样本结果：

| 方法 | 是否可部署 | Top-1 | Top-5 |
|---|---|---:|---:|
| 旧版 IR 相似度 | 是 | 15.22% | 29.35% |
| 当前可落地 IR 检索 | 是 | 14.13% | 36.96% |
| IR + 视觉模板重排 | 否，仅离线上限实验 | 30.43% | 56.52% |

当前可落地结果文件：

```text
effect_ir_pipeline/reports/llm_92_compare_retrieval_ensemble_retuned.json
```

离线上限实验结果文件：

```text
effect_ir_pipeline/reports/llm_92_compare_retrieval_template_rerank.json
```

## 3. IR 表示方式

IR 的作用是描述“特效对图像造成了什么变化”，而不是描述输入图片内容。

一个典型 IR 如下：

```json
{
  "schema_version": "effect_ir_v1",
  "summary": "Maps the source image onto a rotating 3D sphere with specular lighting.",
  "ops": [
    {
      "type": "geometry_transform",
      "subtype": "sphere_map",
      "strength": 0.8,
      "region": "center",
      "temporal": "monotonic"
    }
  ],
  "attributes": {
    "color_shift": 0.2,
    "brightness_change": 0.1,
    "contrast_change": 0.1,
    "blur_strength": 0.0,
    "distortion_strength": 0.8,
    "pixelation_strength": 0.0,
    "edge_emphasis": 0.0,
    "mask_dependency": 0.2,
    "motion_intensity": 0.3
  },
  "temporal": {
    "is_animated": true,
    "pattern": "monotonic"
  },
  "controls": [],
  "tags": ["3d", "sphere", "lighting"]
}
```

主要字段：

| 字段 | 作用 |
|---|---|
| `summary` | 一句话描述视觉变化 |
| `ops` | 主要操作类型，例如 blur、distortion、mask_matte、particle_light |
| `attributes` | 连续强度，例如颜色变化、模糊、畸变、运动 |
| `temporal` | 是否随时间变化以及变化模式 |
| `tags` | 关键视觉概念，例如 sphere、bokeh、page_turn |

`ops.type` 的主要候选包括：

```text
color_adjustment, blur, distortion, pixelation, edge,
compositing, geometry_transform, transition, mask_matte,
particle_light, procedural_texture, stylization, pass_through
```

`attributes` 包括：

```text
color_shift, brightness_change, contrast_change,
blur_strength, distortion_strength, pixelation_strength,
edge_emphasis, mask_dependency, motion_intensity
```

## 4. 查询侧 IR 生成

查询侧输入是：

```text
原始图 + 视频关键帧
```

模型需要根据原图和关键帧之间的差异生成 IR。这里强调的是“相对原图发生了什么变化”，不是描述图像里有什么物体。

例如：

```text
错误方向：画面中有一张渐变图、一个圆环、一些线条。
正确方向：图像被球面映射、边缘被拉伸、亮度周期性闪烁、局部区域被遮罩。
```

## 5. 库侧 IR 生成

库侧输入是：

```text
filter.json + Lua shader 源码
```

大模型根据代码生成同样格式的 IR。库侧不依赖任何渲染视频。

这一步的目标是把 shader 行为翻译成视觉语义，例如：

```text
该 shader 是否做了几何变形？
是否有颜色调整？
是否有遮罩或 alpha reveal？
是否随时间变化？
```

## 6. 变化签名

完整 IR 字段较多，直接比较容易受 LLM 表述差异影响。因此系统会从完整 IR 中抽取一个更稳定的变化签名。

代码位置：

```text
effect_ir_pipeline/effect_ir/schema.py
distill_ir_signature(...)
```

变化签名示例：

```json
{
  "primary": "warp",
  "secondary": "color",
  "mechanisms": ["warp", "color"],
  "spatial_scope": "full_frame",
  "temporal_group": "periodic",
  "profile": [0.12, 0.0, 0.45, 0.0, 0.0, 0.0, 0.03],
  "profile_labels": [
    "photometric",
    "blur",
    "warp",
    "pixelate",
    "edge",
    "mask",
    "motion"
  ]
}
```

变化签名关注：

| 字段 | 含义 |
|---|---|
| `primary` | 最主要变化机制 |
| `secondary` | 次要变化机制 |
| `mechanisms` | 变化机制集合 |
| `spatial_scope` | 作用区域 |
| `temporal_group` | 时序类型 |
| `profile` | 连续强度向量 |

当前机制类别：

```text
color, blur, warp, pixelate, edge, mask_reveal,
overlay, light, pattern, mirror_repeat, identity
```

## 7. 可落地 IR 相似度

正式可部署相似度只包含三路分数：

```python
score = (
    0.40 * structured_score
    + 0.40 * signature_score
    + 0.20 * diagnostic_score
)
```

代码位置：

```text
effect_ir_pipeline/effect_ir/compare_llm_samples.py
retrieval_similarity(...)
```

### 7.1 structured_score

`structured_score` 比较完整 IR 的结构语义。

代码位置：

```text
effect_ir_pipeline/effect_ir/schema.py
ir_similarity(...)
```

它比较：

| 子项 | 作用 |
|---|---|
| `ops_presence` | 操作类型是否一致 |
| `op_strength` | 操作强度是否接近 |
| `attributes` | 连续属性是否接近 |
| `temporal` | 时序模式是否一致 |
| `subtype` | 子类型是否相似 |
| `region` | 作用区域是否相似 |
| `tags` | 视觉标签是否重叠 |
| `controls` | 控制参数语义是否相似 |
| `summary` | 摘要关键词是否相似 |

### 7.2 signature_score

`signature_score` 比较变化签名。

代码位置：

```text
effect_ir_pipeline/effect_ir/schema.py
signature_similarity(...)
```

它比较：

| 子项 | 作用 |
|---|---|
| `primary` | 主变化机制是否一致 |
| `secondary` | 次变化机制是否一致 |
| `mechanism_overlap` | 机制集合是否重叠 |
| `spatial` | 作用区域是否一致 |
| `temporal` | 时序类型是否一致 |
| `profile` | 强度向量是否接近 |

### 7.3 diagnostic_score

`diagnostic_score` 比较诊断关键词。

代码位置：

```text
effect_ir_pipeline/effect_ir/compare_llm_samples.py
diagnostic_token_similarity(...)
```

典型诊断概念：

| 概念 | 示例词 |
|---|---|
| `bokeh` | bokeh, hexagonal, diamond, polygon |
| `page_turn` | page, turn, curl, fold, shadow |
| `sphere` | sphere, spherical, 3d, lighting, specular |
| `mirror` | mirror, symmetry, repeat, tile, cross |
| `mask` | mask, alpha, wipe, reveal, matte |
| `light` | glow, flash, sparkle, highlight |
| `warp` | distortion, stretch, twirl, lens, wave |
| `mosaic` | mosaic, pixel, block, glass |
| `edge` | edge, outline, sobel, stroke, emboss |
| `color` | hue, saturation, lut, gradient, channel |

这一步用于区分结构相似但视觉概念不同的特效。

## 8. visual_template_score 的定位

`visual_template_score` 之前带来了最高离线结果：

```text
Top-1: 30.43%
Top-5: 56.52%
```

但它依赖库侧模板视频：

```text
查询视频关键帧
vs
库中特效在同输入图变体下的渲染视频关键帧
```

实际部署时无法获取库视频，因此它不能作为正式方案的一部分。

现在代码中该功能保留为显式离线实验选项：

```bash
--enable-visual-template
```

默认不启用。默认行为只使用代码侧 IR。

## 9. 当前结论

当前结论需要区分两类结果：

| 类型 | 方案 | 可部署 | Top-1 | Top-5 |
|---|---|---|---:|---:|
| 正式方案 | 结构化 IR + 变化签名 + 诊断关键词 | 是 | 14.13% | 36.96% |
| 离线上限 | 正式方案 + 视觉模板重排 | 否 | 30.43% | 56.52% |

正式方案的优点是满足实际约束：

```text
库侧只需要代码，不需要渲染视频。
```

它的主要问题是 Top-1 精排能力仍然不足。很多正确特效能进入候选集，但第一名容易被同家族特效抢走。

## 10. 下一步优化方向

在不能使用库视频的前提下，后续优化应集中在代码侧 IR 和查询侧 IR 的质量上：

| 方向 | 说明 |
|---|---|
| 改进代码侧 IR | 从 shader 代码中更准确提取几何、颜色、时序、遮罩语义 |
| 改进查询侧 IR | 让模型更稳定描述“相对原图的变化”，减少输入内容干扰 |
| 增强诊断词体系 | 对 bokeh、warp、mask/wipe、3D/lens 等易混类别加细粒度概念 |
| 引入视觉模型生成 IR | 用视觉模型辅助生成查询侧 IR，但不和库视频比较 |
| 学习式相似度 | 用现有评测数据学习 IR 字段权重，而不是手工设定 |
| 代码静态特征融合 | 从 Lua/filter.json 提取参数、采样模式、时间变量等确定性特征 |

当前最现实的下一步是：

```text
优化代码侧 IR 生成 + 优化查询侧 IR prompt + 学习 IR 相似度权重
```

这条路线不依赖库视频，符合最终实际使用条件。
