# 库侧 Shader 分类与多候选检索设计

本文档记录当前库侧 shader 的分类思路，用于后续把“全库只选一个最相似 shader”优化为“在多个类别中分别检索相似 shader，并共同作为第一轮生成参考”。

## 背景

当前闭环流程中，目标视频会先生成 structured IR，然后在库侧所有 shader IR 中检索 top1，第一轮 shader 生成只参考这一个最相似效果的源码。

这种方式的问题是：一个目标视频经常同时包含多个视觉因素，例如：

- 几何拉伸 + 翻转
- 颜色偏移 + 对比度增强
- 模糊 + 光效
- mask reveal + 局部变形

如果只选全局 top1，模型容易被某一个效果家族牵引，忽略其他重要因素。因此更合理的方式是：先把库侧 shader 分成若干视觉操作类别，每个类别内部找最相似的一个或几个 shader，再把这些参考源码一起交给模型生成第一轮 code。

## 分类依据

分类不建议按效果名硬分，而应基于当前 IR schema 中已有字段：

- `geometry_ops`
- `appearance_ops`
- `region_scope`
- `temporal_pattern`
- `subject_hint`
- `geometry_pattern`
- `mask_shape_source`

其中最适合作为一级分类依据的是：

- `geometry_ops`
- `appearance_ops`

适合作为二级 gate 或过滤条件的是：

- `region_scope`
- `subject_hint`
- `mask_shape_source`
- `geometry_pattern`
- `temporal_pattern`

当前库中共有约 92 个 structured IR。大致分布如下：

- `geometry_ops=none`：48
- `warp`：20
- `displacement`：11
- `crop_transform`：9
- `fold_page`：4
- `mirror_repeat`：4
- `lens_distortion`：3
- `bulge_twirl`：2

appearance 侧大致分布：

- `color_adjust`：16
- `composite_cutout`：16
- `light_glow_flash`：10
- `blur_bokeh`：9
- `edge_outline_emboss`：9
- `pixelation_mosaic`：8
- `channel_shift`：5

因此不适合分得过细，否则很多类别只有一两个样本，检索意义不大。

## 推荐分类

建议先使用 8 个主 bucket，加 1 个特殊 gate bucket。

### 1. `geometry_warp`

用于覆盖局部或整体几何形变。

对应 IR：

- `geometry_ops` 包含 `warp`
- `geometry_ops` 包含 `displacement`
- `geometry_ops` 包含 `lens_distortion`
- `geometry_ops` 包含 `bulge_twirl`

典型效果：

- `BezierWarp`
- `WaveWarp`
- `JellyDistortion`
- `LensDistortion2`
- `Bulge`
- `Twirl`
- `DisplacementMap`
- `OpticsCompensation`

适合目标：

- 拉伸
- 扭曲
- 波动
- 局部膨胀
- 镜头畸变
- 液态形变

### 2. `transform_transition`

用于覆盖整屏空间变换、翻页、折叠、镜像、滑动类转场。

对应 IR：

- `geometry_ops` 包含 `crop_transform`
- `geometry_ops` 包含 `fold_page`
- `geometry_ops` 包含 `mirror_repeat`
- `geometry_pattern` 为 `global`、`directional` 或 `tiled`

典型效果：

- `Transform`
- `CCPageTurn`
- `CCPageTurn2`
- `CCPageTurnWithBg`
- `Fold`
- `SlicingSlide`
- `cornerPinAndTile`
- `CCCylinder`
- `CCSphere`

适合目标：

- 翻转
- 翻页
- 平移
- 滑动
- 折叠
- 镜像
- 整体缩放/裁切

### 3. `color_tone`

用于覆盖颜色、亮度、对比度、饱和度、通道类变化。

对应 IR：

- `appearance_ops` 包含 `color_adjust`
- `appearance_ops` 包含 `channel_shift`
- `color_hint` 不为 `none`

典型效果：

- `ColorBalanceHLS`
- `Lumetri`
- `Lut`
- `Invert`
- `ExtractChannel`
- `ShiftChannels`
- `LeaveColor`
- `HairDyeing`

适合目标：

- 亮度变化
- 对比度变化
- 饱和度变化
- 色相偏移
- RGB 分离
- 反色
- 通道隔离

### 4. `blur_bokeh`

用于覆盖模糊、景深、散景、运动模糊类效果。

对应 IR：

- `appearance_ops` 包含 `blur_bokeh`
- `edge_hint` 为 `soften`

典型效果：

- `Bokeh`
- `DiamondBokeh`
- `HexagonalBokeh`
- `PolygonBokeh`
- `MipmapBlur`
- `SurfaceBlur`
- `motionBlur`

适合目标：

- 整体模糊
- 局部模糊
- 景深
- 光斑
- 运动拖影

### 5. `light_glow_flash`

用于覆盖发光、闪烁、扫光、高光增强。

对应 IR：

- `appearance_ops` 包含 `light_glow_flash`
- `color_hint` 为 `highlight_boost`
- `motion_hint` 为 `flicker`

典型效果：

- `BlingBling`
- `BrightFlash`
- `FlashWarning`
- `CCLightSweep`
- `EdgeGlow`
- `NeonArc`

适合目标：

- 闪光
- 发光
- 光扫
- 边缘高光
- 局部亮斑

### 6. `pixel_style`

用于覆盖像素化、马赛克、网格采样、ASCII/印刷风格。

对应 IR：

- `appearance_ops` 包含 `pixelation_mosaic`
- `shape_hint` 为 `grid_tile`、`hexagon`、`star` 等
- `mask_shape_source` 为 `texture_pattern`

典型效果：

- `LowPixel`
- `MosaicBuilding`
- `MosaicBurr`
- `MosaicColor1`
- `MosaicColor2`
- `MosaicGlass2`
- `MosaicHexagon`
- `MosaicStar`
- `AsciiArtStyle`
- `Newsprint`
- `Pattaizer`

适合目标：

- 马赛克
- 像素块
- 六边形采样
- ASCII 风格
- 网点印刷
- 图案化重采样

### 7. `edge_outline`

用于覆盖边缘检测、描边、轮廓、浮雕、素描类效果。

对应 IR：

- `appearance_ops` 包含 `edge_outline_emboss`
- `edge_hint` 为 `enhance` 或 `outline`
- `mask_shape_source` 为 `edge_map`

典型效果：

- `Outline`
- `LayerOutline`
- `Stroke`
- `Sketch`
- `Engrave`
- `EmbossNew`
- `EdgeGlow`

适合目标：

- 描边
- 素描
- 边缘增强
- 浮雕
- 雕刻感
- 轮廓发光

### 8. `mask_composite`

用于覆盖遮罩、alpha、局部显示、wipe、前后景合成。

对应 IR：

- `appearance_ops` 包含 `composite_cutout`
- `mask_dependency` 为 `weak` 或 `strong`
- `mask_shape_source` 为 `analytic_shape`
- `mask_shape_source` 为 `luminance_alpha`

典型效果：

- `LayerMask`
- `RightAlpha`
- `HeadMatting`
- `SplashScreen`
- `RandomImage`
- `Progress`
- `GradientWipe`

适合目标：

- 局部 reveal
- mask wipe
- alpha 合成
- 前景/背景分离
- 圆形、条带、渐变遮罩

### 9. `subject_face`

这是特殊 gate bucket，不建议默认参与所有查询。

对应 IR：

- `subject_hint` 不为 `none`
- `region_scope` 为 `face_region`
- `mask_shape_source` 为 `subject_segmentation`

典型效果：

- `FaceAnchor`
- `FaceLocation`
- `FaceRelocation`
- `HeadTrack`
- `MagnifyHead`
- `EyesSticker`
- `HairDyeing`
- `SEFaceSmooth`

适合目标：

- 人脸绑定
- 头部放大
- 眼睛贴纸
- 头发变色
- 人像分割
- 面部局部美化

使用约束：

只有当目标 IR 明确出现 `face`、`eyes`、`hair`、`subject_segmentation` 等证据时才启用。否则这类源码容易误导模型生成依赖人脸锚点、分割 mask 或主体追踪的代码。

## 查询策略建议

后续检索可以从“全库 top1”改为“多 bucket top1/top2”。

推荐流程：

1. 对目标视频生成 `target_ir`
2. 根据 `target_ir` 判断需要启用哪些 bucket
3. 在每个启用 bucket 内运行当前 structured similarity
4. 每个 bucket 取 top1 或 top2
5. 去重后把多个 shader 源码一起传给第一轮 code 生成模型
6. 要求模型先总结每个参考 shader 的可借鉴 primitive，再生成完整 shader

示例：

如果目标是“拉伸 + 翻转 + 轻微颜色变化”，启用：

```text
geometry_warp
transform_transition
color_tone
```

如果目标是“马赛克 + 色彩增强”，启用：

```text
pixel_style
color_tone
```

如果目标是“中心发光 + 边缘轮廓”，启用：

```text
light_glow_flash
edge_outline
mask_composite
```

如果目标是“人脸局部变形 + 美颜”，启用：

```text
subject_face
geometry_warp
color_tone
```

## 第一轮生成 prompt 建议

给模型多个参考 shader 时，不建议让模型直接“融合所有源码”。更好的要求是：

1. 先列出每个参考 shader 提供的可复用 primitive。
2. 判断哪些 primitive 与 `target_ir` 一致。
3. 拒绝与 `target_ir` 冲突的参考效果。
4. 再生成一个完整、可渲染、只使用允许 uniform 的 shader。

可以加入类似约束：

```text
你会收到多个库侧参考 shader，它们来自不同视觉操作 bucket。
不要机械拼接源码。
请先提取每个参考 shader 中与 target_ir 对齐的 primitive，
忽略与 target_ir 冲突的部分，
再生成一个完整的 vertex shader 和 fragment shader。
```

## 重要注意点

1. 多 bucket 检索不是为了增加源码数量，而是为了覆盖目标视频的多个视觉维度。
2. 不要让所有 bucket 默认参与，否则会重新变成“全库噪声检索”。
3. `subject_face` 必须作为强 gate，不应默认参与。
4. 如果目标 IR 没有几何变化，不应启用 `geometry_warp` 和 `transform_transition`。
5. 如果目标 IR 没有 mask 证据，不应强行启用 `mask_composite`。
6. 如果多个 bucket 检索到同一个 shader，需要去重。
7. 每个 bucket 内仍然使用现有 structured similarity 即可，第一版不需要重新设计相似度公式。

## 推荐默认 bucket 列表

```text
geometry_warp
transform_transition
color_tone
blur_bokeh
light_glow_flash
pixel_style
edge_outline
mask_composite
subject_face
```

其中 `subject_face` 是特殊 gate bucket。

