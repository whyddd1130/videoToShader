# 分阶段闭环实现

主循环现按四个持久化阶段运行，每个阶段均写入 `work_dir/stages/`，并可独立检查。

1. `target_observation.json`：原图、目标视频、目标 IR、检索 Top-1 与排除项。
2. `iter_XX_plan.json`：上一轮验收结果、候选 IR、当前 edit plan、必改项与冻结约束。
3. `iter_XX_execution.json`：实际采用的 shader builder 记录、shader 文件、渲染视频与渲染任务。
4. `iter_XX_acceptance.json`：候选视频 IR、视觉审查结果与验收依据。

职责边界：

- 观察阶段只描述目标或候选视频，不决定 shader 改法。
- 规划阶段只生成可执行 edit plan，不渲染。
- 执行阶段只将 plan 落地为 shader 并渲染；第 1 轮直接使用检索 Top-1 源码。
- 验收阶段只比较渲染结果与目标，并为下一轮提供结构化反馈。

发生失败时，可根据最后存在的阶段文件定位：没有 observation 是视频理解失败；没有 execution 是计划/代码生成失败；没有 acceptance 是候选 IR 或审查失败。
