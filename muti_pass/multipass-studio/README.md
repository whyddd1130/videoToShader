# MultiPass Studio

本地 WebGL 多 pass shader 编辑与渲染页面。

## 启动

```bash
cd muti_pass/multipass-studio
npm ci
npm run dev -- --host localhost --port 3001
```

浏览器打开 <http://localhost:3001/>。

## 能力

- 上传本地输入图片，不上传到服务器；
- 方向只在纹理上传边界转换一次：输入图片、模型证据和 Shader 均保持正常人眼方向，
  浏览器使用 `UNPACK_FLIP_Y_WEBGL=1` 统一处理 HTML/WebGL 原点差异；
- 添加、删除和调整 pass 顺序；
- 每个 pass 可输出 RGBA8 FBO 中间纹理，并可按 `scale` 设为原图的 1/4、1/2 或全尺寸；
- 图谱 pass 可同时绑定多个具名输入纹理，例如原图与模糊结果；
- 图谱参数支持关键帧，在每个视频帧自动插值并写入对应 uniform；
- 每层可分别编辑 vertex 与 fragment shader；vertex 留空时自动使用公共全屏顶点 shader；
- 支持 `inputImageTexture`、`uProgress`、`uTime`；每个 Pass 自动获得当前 FBO 的
  `uResolution`、`uOutputResolution`、`uTexelSize`，以及原图尺寸 `uSourceResolution`；
- 实时编译 GLSL，并显示编译错误；
- 播放或拖动 5 秒归一化时间线；
- 使用浏览器 `MediaRecorder` 导出 MP4（浏览器支持时）或 WebM。

片元 shader 使用 GLSL ES 1.00/WebGL 1 语法。每个 pass 必须声明
`varying vec2 textureCoord` 并写入 `gl_FragColor`。

## 图谱中的自定义顶点 shader

`pass_graph.json` 中每个 pass 支持可选 `vertex_shader` 字段：

```json
{
  "name": "Vertex squeeze",
  "vertex_shader": "pass_01.vertex.glsl",
  "fragment_shader": "pass_01.fragment.glsl"
}
```

未提供 `vertex_shader` 时，网站会复用默认的全屏四边形顶点 shader。自定义顶点
shader 与其 fragment shader 必须使用一致的 `varying` 接口；默认约定为
`attribute vec2 position` 与 `varying vec2 textureCoord`。这使空间形变层可以在顶点
阶段实现，而模糊、调色和合成层仍可只使用 fragment shader。

## 执行图、资源与参数

没有 `inputs`、`output`、`scale` 或 `parameters` 的旧图谱仍会按顺序串行运行。
新图谱可表达分支合流、低分辨率 FBO 和宿主关键帧：

```json
{
  "input_image": "input.png",
  "parameters": {
    "gridNumRatio": {
      "type": "float",
      "keyframes": [[0, 0.06], [0.5, 0.25], [1, 0.06]]
    }
  },
  "passes": [
    {
      "id": "blur_h",
      "inputs": {"inputImageTexture": "source"},
      "output": "blur_h",
      "scale": 0.25,
      "fragment_shader": "pass_01.frag.glsl"
    },
    {
      "id": "comic",
      "inputs": {
        "inputImageTexture": "source",
        "inputImageTexture1": "blur_h"
      },
      "output": "final",
      "scale": 1.0,
      "fragment_shader": "pass_02.frag.glsl"
    }
  ]
}
```

每个 `inputs` 键就是 GLSL 中对应 sampler uniform 的名字；值为 `source` 或更早
pass 的 `output`。`parameters` 中的键对应 GLSL uniform，关键帧的横坐标是归一化
进度 `0..1`。
