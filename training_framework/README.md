# 视频到 Lua 训练框架

这是一个轻量级训练框架骨架，用于探索以下任务：

```text
video + input image + parameter description -> code/<EffectName>/*.lua
```

第一版推荐采用“先检索、再生成”的 practical baseline：

```text
1. 训练一个视频/输入图/参数编码器，用来预测 effect_name。
2. 根据 effect_name 检索 code/<EffectName>/。
3. 使用参数文本和检索到的代码上下文，微调代码模型生成规范化 Lua。
```

## 目录结构

```text
training_framework/
  requirements.txt
  config.yaml
  videolua/
    data.py              Dataset 与样本组装
    video.py             视频帧读取
    text.py              参数/代码文本格式化
    model.py             baseline 模型定义
    train.py             特效分类训练入口
    evaluate.py          检索式评估
    build_sft_jsonl.py   构建监督微调 JSONL
    manifest.py          manifest 读取与路径解析
    config.py            配置加载
```

## 安装依赖

这里只列出依赖，框架本身不会自动安装。

```bash
cd training_framework
python -m pip install --upgrade pip
python -m pip install --index-url https://download.pytorch.org/whl/cu113 torch==1.12.1 torchvision==0.13.1
python -m pip install -r requirements.txt
```

如果你的机器和当前仓库一样，驱动版本比较老，直接安装较新的 `torch>=2.3` / `cu12x` 轮子通常会导致 CUDA 不可用，或者像 `libtorch_global_deps.so` 这类导入错误。上面的 `cu113` 组合对旧驱动更稳妥。

如果容器里的 `libcuda.so.1` 默认软链指到了错误的兼容库，而不是宿主机驱动版本，可以直接使用仓库里提供的 `train_gpu.sh` / `eval_gpu.sh`。这两个脚本会强制预加载当前机器上的 `470.57.02` 驱动库，避免 `Error 804: forward compatibility was attempted on non supported HW`。

## 训练特效分类器

```bash
cd training_framework
./train_gpu.sh
```

训练脚本会自动选择 `cuda` 或 `cpu`，启动时会打印当前设备。确认 GPU 可用后，日志里应看到 `Using device: cuda`。

该命令训练一个 baseline 模型：

```text
frames + input image + parameter text -> effect_name
```

训练 checkpoint 会保存到 `output_dir` 配置对应的目录下。

## 构建 Lua 生成 SFT 数据

```bash
cd training_framework
python -m videolua.build_sft_jsonl --config config.yaml --output runs/sft_train.jsonl
```

每一行包含：

```json
{
  "sample_id": "...",
  "prompt": "...",
  "target": "..."
}
```

其中 `prompt` 包含视频路径、输入图路径、参数描述，以及一个检索代码上下文占位；`target` 是 `code/<EffectName>/` 下的 Lua 文件内容。

## 评估

训练完成后，可以用：

```bash
cd training_framework
./eval_gpu.sh --config config.yaml --checkpoint runs/video_to_lua_baseline/best.pt --split test
```

评估会输出 top-1 / top-5 准确率，并把预测结果写到 `output_dir` 下。

## 说明

这个框架有意从较小的 baseline 开始。使用当前数据集直接做完全开放式的视频到 shader 生成是不充分确定的：同一种视觉效果可以由多种 shader 实现，而且许多 Lua 文件包含单个渲染样本中没有激活的分支。

因此推荐的训练路线是：

```text
先学会识别 / 检索已有 effect
再基于检索到的代码和参数描述做 Lua 生成
最后逐步扩展到代码改写和新 shader 生成
```
