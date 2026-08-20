# Video-to-Shader

本项目将“原图 + 特效视频”翻译为可执行 Shader，包含两条正式链路：

- **单 Pass**：多模态理解目标变化 → 库侧 IR 检索 → 生成 Shader → 固定轮次渲染、审查与修改。
- **多 Pass Agent**：理解原图与目标视频 → 规划 Pass 图 → 实现各层 Shader/FBO → 本地渲染 → 持续人工反馈与定向修订。

## 项目结构

```text
videoToShader/
├── datasets/                         数据集，不与实现代码混放
│   ├── effect_training/
│   │   ├── single_shader_multi/      单 Pass 数据（含剪映合并数据）
│   │   │   ├── code/                 去重后的效果源码库
│   │   │   ├── input_images/         标准输入图
│   │   │   ├── videos/               渲染视频
│   │   │   ├── shaders/              样本级 Shader
│   │   │   ├── params/               宿主参数与关键帧
│   │   │   ├── diagnostics/          抽帧与质量诊断
│   │   │   └── manifest_*.jsonl      数据索引
│   │   ├── kuaiying_multi_pass/      快影多 Pass 原始数据
│   │   └── multipass_data/           构造的多 Pass 样本
│   ├── shadertoy_single_pass/        Shadertoy 单 Pass 数据
│   └── test_videos/                  回归与消融测试视频
├── effect_ir_pipeline/               视频理解、IR、检索和 Agent 核心实现
├── muti_pass/multipass-studio/       多 Pass 可视化工作台
├── tools/                             本地渲染器、任务服务和启动脚本
├── runs/                              历史及新生成的实验结果
│   ├── single_pass/
│   ├── multi_pass/
│   └── legacy_outputs/
├── demo/comic_model/                 最小多 Pass 演示素材
├── deliverables/                     最终汇报材料
├── requirements.txt                  Python 依赖
└── .env.example                      无密钥的配置模板
```

数据规模概览：完整单 Pass 清单记录了 774 次尝试和 676 个有效渲染；当前精筛训练 manifest 保留 436 条可用样本，其中 124 条来自剪映。目录中共保留 711 个单 Pass 视频、52 个快影多 Pass 视频、300 个 Shadertoy 视频和 53 个测试视频。

## 环境安装

要求：macOS、Python 3.10+、Node.js 22.13+、ffmpeg。

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

cd muti_pass/multipass-studio
npm ci
cd ../..

cp .env.example env.sh
# 在 env.sh 中填写模型推理点、API key 和 Shader Lab 地址
source env.sh
```

不要提交 `env.sh`、`.env` 或真实密钥。

## 单 Pass 流程

```bash
python -m effect_ir_pipeline.effect_ir.closed_loop_shader_iter \
  datasets/test_videos/random/test9.mp4 \
  --input-image datasets/effect_training/single_shader_multi/input_images/model.png \
  --repo-root . \
  --work-dir runs/single_pass/test9 \
  --max-iters 5
```

核心阶段：

1. 从原图与目标视频抽取视觉证据并生成结构化 IR。
2. 在 `effect_ir_pipeline/library_structured_ir_llm.jsonl` 中检索最相似参考；库内消融测试会自动排除自身。
3. 生成第一版 Shader，渲染后由多模态模型直接比较目标视频与候选视频。
4. 模型输出简化的修改计划，代码模型落实修改；每轮均保存 Shader、视频、审查和计划。
5. 达到固定轮次后结束，不使用像素差或阈值提前停止。

重新构建库侧 IR：

```bash
python -m effect_ir_pipeline.effect_ir.build_library_ir_llm
```

默认读取 `datasets/effect_training/single_shader_multi/manifest_train.jsonl` 和其中的 `code/`。

## 多 Pass Agent

启动网页和任务服务：

```bash
cd muti_pass/multipass-studio
npm run agent
```

网页中上传原图与目标视频。效果描述、Pass 数量和各 Pass 职责都可以独立留空；未提供的信息由模型根据视频抽帧推断。Agent 会规划纹理依赖图、FBO 尺寸、顶点/片元 Shader、时间参数与各 Pass 职责。首轮渲染后，网页可切换“当前视频/原视频”，并持续接收人工 feedback。

CLI 示例：

```bash
python -m effect_ir_pipeline.effect_ir.agentic_multipass_translation \
  demo/comic_model/final.mp4 \
  --input-image demo/comic_model/input.png \
  --repo-root . \
  --work-dir runs/multi_pass/comic_demo \
  --wait-for-feedback
```

`tools/local_multipass_renderer.py` 使用 ModernGL 离屏执行 Pass 图；网页负责编辑、预览、状态反馈与人工修订。

## 数据与运行产物

- `datasets/` 保存可复用输入、源码、manifest 和视频数据。
- `runs/` 只保存实验过程与输出，不作为程序依赖。
- `effect_ir_pipeline/` 与 `muti_pass/` 只放实现代码及必要配置。
- 大体积视频和运行结果默认不进入 Git；交付或迁移时需要单独复制 `datasets/` 与 `runs/`。

## 验证

```bash
python -m unittest discover -s effect_ir_pipeline/tests -v
cd muti_pass/multipass-studio && npm test
```
