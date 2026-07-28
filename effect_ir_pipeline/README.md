# Structured Effect IR Pipeline

这个目录保留当前采用的结构化 IR 与闭环 shader 迭代流程。

## 保留脚本

- `effect_ir/build_library_ir_llm.py`: 从 `code/<EffectName>/` 生成库侧结构化 IR。
- `effect_ir/compare_video_ir.py`: 将“原始图 + 目标视频”转成结构化 IR，并和库侧 IR 排序得到 Top-K。
- `effect_ir/closed_loop_shader_iter.py`: 对“原始图 + 目标视频”执行 Top1 检索、shader 生成/改写、Shader Lab 渲染和大模型视觉审查闭环。

## 支撑模块

- `effect_ir/visual_observation.py`: 使用显式原始图作为 reference，抽取目标/候选视频帧并生成 observation/profile。
- `effect_ir/visual_distance.py`: 独立的直接视觉距离工具；当前闭环迭代不再调用它做评选或停止。
- `effect_ir/llm_adapter.py`: 构造结构化 IR prompt。
- `effect_ir/model_client.py`: 统一模型调用。
- `effect_ir/schema_ir.py`: 结构化 IR schema、解析和规范化。
- `effect_ir/structured_similarity.py`: 结构化 IR 相似度。
- `effect_ir/manifest.py`: manifest 读取和路径解析。
- `effect_ir/update_library_category_info.py`: 根据原子化建议为库侧 IR 增加 `category_info`，用于后续多 bucket、多 shader 参考。

## 常用命令

生成或更新库侧结构化 IR：

```bash
source .venv/bin/activate
python -m effect_ir_pipeline.effect_ir.build_library_ir_llm \
  --manifest manifest_train.jsonl \
  --code-root code \
  --output effect_ir_pipeline/library_structured_ir_llm.jsonl
```

为库侧 IR 补充分类信息：

```bash
source .venv/bin/activate
python -m effect_ir_pipeline.effect_ir.update_library_category_info \
  --input effect_ir_pipeline/library_structured_ir_llm.jsonl \
  --output effect_ir_pipeline/library_structured_ir_llm.jsonl \
  --summary effect_ir_pipeline/library_category_summary.json
```

对单个“原始图 + 视频”生成 IR 并检索 Top-K：

```bash
source .venv/bin/activate
python -m effect_ir_pipeline.effect_ir.compare_video_ir \
  test_videos/test2.mp4 \
  --input-image input_images/yyf.jpg \
  --library-structured effect_ir_pipeline/library_structured_ir_llm.jsonl
```

运行闭环 shader 迭代：

```bash
source .venv/bin/activate
python -m effect_ir_pipeline.effect_ir.closed_loop_shader_iter \
  test_videos/test2.mp4 \
  --input-image input_images/fulltest2.jpg \
  --repo-root . \
  --work-dir effect_ir_pipeline/reports/closed_loop_run \
  --max-iters 5
```

新接口要求调用方显式提供原始图 `--input-image`。为了兼容历史命令，如果省略
`--input-image`，脚本仍会临时回退到“目标视频第一帧作为原图”的旧行为；后续正式实验
建议始终传入原始图。

闭环流程里，IR 仍用于库侧 Top1 检索和迭代诊断；循环固定执行 `--max-iters`
指定的轮数，默认 5 轮，不再使用差异阈值或直接视觉距离做停止、best 选择或回退。
每一轮渲染成功后，大模型会基于 target/candidate/diff contact sheet、target IR、
candidate IR 和当前 shader 进行视觉审查，输出 `primitive_edit_plan` 与
`match_score`。`match_score.overall` 是 0-100 的整体人类主观相似度评分：模型只比较
target video 和 rendered candidate video 看起来像不像，不再按 geometry/appearance/temporal/mask
几个技术分项打分或求平均。这个分数用于对所有轮次排序并指出 `best_iteration_by_llm_score`。

视觉审查 prompt 保持短规则优先，避免把所有经验都塞进长 prompt。当前要求模型先写 `frame_by_frame_observation`：按
`p=0.00/0.25/0.50/0.75/1.00` 分别描述 target 和 candidate 在每一帧具体长什么样，
再总结 `target_video_observation`、`candidate_video_observation`、`most_important_gap`
和 `next_change_in_plain_words`。这些字段会告诉 code 模型“画面里发生了什么、最该改什么”，避免只堆
pixelation/displacement/primitive 等术语导致 shader 在抽象标签里原地打转。
`primitive_edit_plan` 仍会保留，但它主要作为代码落地接口，而不是审查结果的唯一重点。

当前默认 shader 生成链路已经改为：

```text
LLM 看图判断差异
→ 输出 primitive/edit plan
→ 程序化 shader builder 生成源码
→ 渲染
→ LLM 审查
→ 下一轮继续调 primitive 参数
```

也就是说，默认不再让视觉模型每轮自由重写完整 shader。第一轮会从 target IR 推导
初始 primitive/edit plan；后续轮次使用视觉审查返回的 `primitive_edit_plan`。
`effect_ir.shader_builder` 会把 edit plan 转成稳定的 GLSL 模板，并在每轮结果里记录
`shader_builder` 与 `shader_edit_plan_used`，便于排查模型判断和代码落地之间的问题。

当前 edit plan 支持可执行的分阶段过程：每个 primitive 可以携带独立的 `temporal`、
`from/to` 和 `params.keyframes`，也可以通过 `process_stages` 描述多阶段组合。builder 会
分别编译每项操作的时间包络，不再把所有修改压缩为一个全局强度。`exposure` 与
`color_remap` 用于表达过曝、通道增益/偏置和颜色矩阵等全屏调色过程。系统不再用
源码正则判断 primitive 是否落实：Shader 是否可执行由渲染平台验证，edit plan 是否
真正改善视频则由下一轮多模态审查判断，避免等价 GLSL 写法被误拒绝。

多操作过程还支持生命周期和交接：`weight_curve` 控制操作参与程度，`value_curve`
控制真实参数；`after` 可取 `hold/fade/disable/reverse/handoff`。阶段之间可通过
`handoff_constraints` 声明 `crossfade`。调度器会同时降低前序操作并提高后序操作，
避免曝光、模糊、形变等操作在达到峰值后永久叠加。阶段提前结束却未声明 `after` 时，
系统采用“到视频末尾淡出”的安全回退，并在结果中记录 timeline warning。

如需接入代码能力更强的大模型，可使用：

```bash
python -m effect_ir_pipeline.effect_ir.closed_loop_shader_iter \
  test_videos/test9.mp4 \
  --input-image input_images/model.png \
  --repo-root . \
  --work-dir effect_ir_pipeline/reports/code_model_run \
  --max-iters 5 \
  --code-model <your-code-model-id>
```

当前主循环固定使用 code model：系统会先用程序化 builder 生成一版稳定 draft shader，再把
可执行 edit plan、精简后的目标/候选 IR、上轮关键视觉结论和 draft shader 传给 code 模型优化。
视觉模型的原始回复、逐帧证据、重复的 primitive plan 不会进入下一轮；库侧源码只在第一轮提供，
后续轮次只保留当前有效状态。视觉审查端也只接收 Shader 的操作结构摘要，不接收完整 GLSL。
这样可以避免历史内容逐轮嵌套，同时保留 primitive 参数、时间曲线、合成策略和 handoff 约束。
draft shader 只是可运行的安全起点，不是必须保留的模板；code 模型可以依据当前轮的
edit plan 大幅重构 Fragment Shader，而不是只做小幅参数微调。

固定轮数结束后，`closed_loop_result.json` 和命令行摘要会列出每一轮生成的视频、shader 和评分；
工作目录默认保留每一轮的 `iter_XX_rendered.mp4`、`iter_XX_shader.md`、vertex/fragment 源码，
便于人工比较中间结果。`best_iteration_by_llm_score` 只是最高分版本，`final_*` 字段仍只是最后一轮结果的别名，
不代表最高分版本。

可以从已有结果的最后一个已接受轮次继续运行，而不重新分析目标或重置 Shader：

```bash
python -m effect_ir_pipeline.effect_ir.closed_loop_shader_iter \
  test_videos/lib/DBFunhouseMirror_fulltest.mp4 \
  --input-image input_images/fulltest.png \
  --resume-result effect_ir_pipeline/20260722/previous_run/closed_loop_result.json \
  --work-dir effect_ir_pipeline/20260722/continued_run \
  --max-iters 5
```

续跑会恢复最后一轮的 Shader、候选视频、候选 IR、edit plan、视觉反馈和
`required_change`，轮次编号继续累加；第一个新轮次会以旧的最终视频作为 BEFORE 基线。

闭环渲染时，Shader Lab 接收的输入图也来自同一个 `--input-image`；target IR 与每轮
candidate IR 都会使用这张原始图作为 reference，而不是再各自取视频第 0 帧。

如果某一轮生成的 shader 不完整、接口不符合要求，或渲染出不可用/黑帧视频，系统会重新生成该轮；
这些失败尝试会记录到 `failed_generation_attempts`，但不计入 `--max-iters`。可用
`--max-generation-attempts` 控制单轮最多重试次数。

每轮视觉审查必须同时返回数值化的 `match_score.overall`、评分理由、
`optimization_priority`、`most_important_gap` 和 `primitive_edit_plan`。JSON 截断或字段
缺失时会重新审查，默认最多 3 次；无有效分数的结果不会写入报告，也不会进入下一轮。

从第二轮开始，审查模型还会同时看到上一版与当前版的 BEFORE/AFTER contact sheet，
并用 `required_change_check` 验收上一轮的 `required_change`。判定为 `not_implemented` 或
`regressed` 时，本轮不计数，携带可见证据重新生成 Shader；判定为 `partial` 时允许保留
有效进展，但下一轮继续锁定同一必改项；只有 `implemented` 才允许转向新的优化重点。

## 环境变量

模型和 Shader Lab 的本地配置由项目根目录的 `env.sh` 在激活 `.venv` 时自动加载。
