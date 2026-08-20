"use client";

import { useCallback, useEffect, useRef, useState } from "react";

type Pass = { id: string; name: string; fragment: string; vertex: string; inputs?: Record<string, string>; output?: string; scale?: number; uniforms?: Record<string, UniformSpec> };
type Keyframe = { progress: number; value: number | number[] } | [number, number | number[]];
type UniformSpec = number | number[] | { type?: "float" | "int" | "vec2" | "vec3" | "vec4"; value?: number | number[]; keyframes?: Keyframe[] };
type RenderPass = Pick<Pass, "fragment" | "vertex"> & {
  id?: string;
  inputs?: Record<string, string>;
  output?: string;
  scale?: number;
  uniforms?: Record<string, UniformSpec>;
};
type GeneratedGraph = { id: string; input_image: string; parameters?: Record<string, UniformSpec>; passes: Array<{ id?: string; name?: string; role?: string; fragment_shader: string; vertex_shader?: string; inputs?: Record<string, string>; output?: string; scale?: number; uniforms?: Record<string, UniformSpec> }> };
type AgentJobStatus = {
  job_id: string;
  status: string;
  phase: string;
  planning_mode: "constrained" | "model" | "dense_timeline";
  resolved_pass_count?: number;
  completed_passes: number;
  feedback_round?: number;
  round_count: number;
  passes: Array<{ id: string; name: string; role: string; pass_goal?: string }>;
  video_url?: string;
  video_version?: string;
  video_status?: "accepted" | "candidate";
  graph_url?: string;
  source_url: string;
  target_url: string;
  exit_code?: number;
  error_log?: string;
  current_obligation?: { scope?: string; required_visible_change?: string; acceptance_criteria?: string[] };
  last_transaction?: { committed?: boolean; attempts?: Array<{ verification?: { outcome?: string; requirement_check?: string } }> };
  render_request?: { request_id: string; run: string; kind: "prefix" | "full" | "existing"; graph_url: string; upload_base: string; prefix_count?: number; existing_video_url?: string };
};

declare global {
  interface Window {
    /** Render one model-generated graph stored under the site's public directory. */
    __renderMultiPassJob?: (graphUrl: string, uploadBase: string) => Promise<{ id: string; mime: string; bytes: number }>;
    /** Render selected graph-prefix frames as one contact sheet for the next code-generation step. */
    __renderMultiPassPrefix?: (graphUrl: string, uploadBase: string, passCount: number) => Promise<{ id: string; bytes: number }>;
    /** Load an existing completed video and its graph without rendering it again. */
    __loadMultiPassResult?: (graphUrl: string, videoUrl: string, requestKey?: string) => Promise<{ id: string; bytes: number; stale?: boolean }>;
  }
}

const vertexShader = `
attribute vec2 position;
varying vec2 textureCoord;
void main() {
  textureCoord = position * 0.5 + 0.5;
  gl_Position = vec4(position, 0.0, 1.0);
}`;

const copyFragmentShader = `
precision highp float;
varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
void main() { gl_FragColor = texture2D(inputImageTexture, textureCoord); }`;

const defaultPasses: Pass[] = [
  { id: "preview", name: "01 · Input Preview", inputs: { inputImageTexture: "source" }, output: "preview", scale: 1, fragment: copyFragmentShader.trim(), vertex: "" },
];

const AGENT_API = "http://127.0.0.1:8792/api/agent";
const AGENT_OFFLINE_MESSAGE = "Agent 服务未连接（127.0.0.1:8792）。请启动本地 Agent 服务后重试。";

function networkMessage(reason: unknown) {
  const message = reason instanceof Error ? reason.message : String(reason);
  return /load failed|failed to fetch|networkerror|network request failed/i.test(message) ? AGENT_OFFLINE_MESSAGE : message;
}

function isTransientNetworkMessage(message: string) {
  return message === AGENT_OFFLINE_MESSAGE || /load failed|failed to fetch|networkerror|network request failed/i.test(message);
}

function shader(gl: WebGLRenderingContext, type: number, source: string) {
  const handle = gl.createShader(type)!;
  gl.shaderSource(handle, source);
  gl.compileShader(handle);
  if (!gl.getShaderParameter(handle, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(handle) || "Shader compile failed");
  }
  return handle;
}

function program(gl: WebGLRenderingContext, fragment: string, vertex = vertexShader) {
  const handle = gl.createProgram()!;
  gl.attachShader(handle, shader(gl, gl.VERTEX_SHADER, vertex));
  gl.attachShader(handle, shader(gl, gl.FRAGMENT_SHADER, fragment));
  gl.linkProgram(handle);
  if (!gl.getProgramParameter(handle, gl.LINK_STATUS)) {
    throw new Error(gl.getProgramInfoLog(handle) || "Program link failed");
  }
  return handle;
}

function setTextureOptions(gl: WebGLRenderingContext) {
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
}

function bindGeometry(gl: WebGLRenderingContext, pipeline: WebGLProgram, buffer: WebGLBuffer) {
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  ["position", "vPosition"].forEach(name => {
    const location = gl.getAttribLocation(pipeline, name);
    if (location >= 0) {
      gl.enableVertexAttribArray(location);
      gl.vertexAttribPointer(location, 2, gl.FLOAT, false, 0, 0);
    }
  });
}

function evaluateUniform(spec: UniformSpec, progress: number): number | number[] {
  if (typeof spec === "number" || Array.isArray(spec)) return spec;
  const keyframes = spec.keyframes;
  if (!keyframes?.length) return spec.value ?? 0;
  const points = keyframes.map(frame => Array.isArray(frame) ? { progress: frame[0], value: frame[1] } : frame).sort((a, b) => a.progress - b.progress);
  const right = points.find(point => point.progress >= progress) || points[points.length - 1];
  const left = [...points].reverse().find(point => point.progress <= progress) || points[0];
  if (left === right || right.progress === left.progress) return left.value;
  const amount = (progress - left.progress) / (right.progress - left.progress);
  const a = Array.isArray(left.value) ? left.value : [left.value];
  const b = Array.isArray(right.value) ? right.value : [right.value];
  const value = a.map((item, index) => item + ((b[index] ?? b[b.length - 1]) - item) * amount);
  return Array.isArray(left.value) || Array.isArray(right.value) ? value : value[0];
}

function applyUniform(gl: WebGLRenderingContext, pipeline: WebGLProgram, name: string, spec: UniformSpec, progress: number) {
  const location = gl.getUniformLocation(pipeline, name);
  if (!location) return;
  const value = evaluateUniform(spec, progress);
  const items = Array.isArray(value) ? value : [value];
  const declaredType = typeof spec === "object" && !Array.isArray(spec) ? spec.type : undefined;
  if (declaredType === "int") gl.uniform1i(location, Math.round(items[0]));
  else if (items.length === 1) gl.uniform1f(location, items[0]);
  else if (items.length === 2) gl.uniform2fv(location, items);
  else if (items.length === 3) gl.uniform3fv(location, items);
  else gl.uniform4fv(location, items.slice(0, 4));
}

function applyBuiltInPassUniforms(
  gl: WebGLRenderingContext,
  pipeline: WebGLProgram,
  outputWidth: number,
  outputHeight: number,
  sourceWidth: number,
  sourceHeight: number,
) {
  const resolution = gl.getUniformLocation(pipeline, "uResolution");
  if (resolution) gl.uniform2f(resolution, outputWidth, outputHeight);
  const outputResolution = gl.getUniformLocation(pipeline, "uOutputResolution");
  if (outputResolution) gl.uniform2f(outputResolution, outputWidth, outputHeight);
  const texelSize = gl.getUniformLocation(pipeline, "uTexelSize");
  if (texelSize) gl.uniform2f(texelSize, 1 / outputWidth, 1 / outputHeight);
  const sourceResolution = gl.getUniformLocation(pipeline, "uSourceResolution");
  if (sourceResolution) gl.uniform2f(sourceResolution, sourceWidth, sourceHeight);
}

/** Renders a resource graph. Old graphs without inputs/outputs remain a linear chain. */
function renderGraphFrame(
  canvas: HTMLCanvasElement,
  image: HTMLImageElement,
  passSources: RenderPass[],
  progress: number,
  time: number,
  maxDimension = 0,
  graphUniforms: Record<string, UniformSpec> = {},
) {
  const gl = canvas.getContext("webgl", { preserveDrawingBuffer: true });
  if (!gl) throw new Error("WebGL is unavailable in this browser");
  const baseScale = maxDimension > 0 ? Math.min(1, maxDimension / Math.max(image.naturalWidth, image.naturalHeight)) : 1;
  canvas.width = Math.max(1, Math.round(image.naturalWidth * baseScale));
  canvas.height = Math.max(1, Math.round(image.naturalHeight * baseScale));
  const buffer = gl.createBuffer()!;
  const textures: WebGLTexture[] = [];
  const framebuffers: WebGLFramebuffer[] = [];
  const programs: WebGLProgram[] = [];
  const resources = new Map<string, WebGLTexture>();
  try {
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, -1,1, 1,-1, 1,1]), gl.STATIC_DRAW);
    const sourceTexture = gl.createTexture()!;
    textures.push(sourceTexture); resources.set("source", sourceTexture); resources.set("input", sourceTexture);
    gl.bindTexture(gl.TEXTURE_2D, sourceTexture);
    // Canonical orientation boundary: model evidence and GLSL stay upright;
    // HTML top-left pixels are converted to WebGL texture coordinates exactly once here.
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image); setTextureOptions(gl);
    let previous = "source";
    let lastOutput = "source";
    passSources.forEach((pass, index) => {
      const output = pass.output || pass.id || `pass_${String(index + 1).padStart(2, "0")}`;
      const passScale = Math.max(0.05, Math.min(1, pass.scale ?? 1));
      const width = Math.max(1, Math.round(canvas.width * passScale));
      const height = Math.max(1, Math.round(canvas.height * passScale));
      const outputTexture = gl.createTexture()!;
      const framebuffer = gl.createFramebuffer()!;
      textures.push(outputTexture); framebuffers.push(framebuffer); resources.set(output, outputTexture);
      gl.bindTexture(gl.TEXTURE_2D, outputTexture);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null); setTextureOptions(gl);
      gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, outputTexture, 0);
      if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) throw new Error(`Pass ${index + 1} framebuffer is incomplete`);
      gl.viewport(0, 0, width, height);
      const pipeline = program(gl, pass.fragment, pass.vertex || vertexShader); programs.push(pipeline); gl.useProgram(pipeline); bindGeometry(gl, pipeline, buffer);
      const inputs = pass.inputs || { inputImageTexture: previous };
      Object.entries(inputs).forEach(([uniform, resourceName], unit) => {
        const texture = resources.get(resourceName === "previous" ? previous : resourceName);
        if (!texture) throw new Error(`Pass ${index + 1} input '${resourceName}' is unavailable`);
        gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, texture);
        const sampler = gl.getUniformLocation(pipeline, uniform); if (sampler) gl.uniform1i(sampler, unit);
      });
      const p = gl.getUniformLocation(pipeline, "uProgress"); if (p) gl.uniform1f(p, progress);
      const t = gl.getUniformLocation(pipeline, "uTime"); if (t) gl.uniform1f(t, time);
      Object.entries({ ...graphUniforms, ...(pass.uniforms || {}) }).forEach(([name, spec]) => applyUniform(gl, pipeline, name, spec, progress));
      applyBuiltInPassUniforms(gl, pipeline, width, height, canvas.width, canvas.height);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
      previous = output; lastOutput = output;
    });
    const finalTexture = resources.get(lastOutput);
    if (!finalTexture) throw new Error("Graph has no final output");
    gl.bindFramebuffer(gl.FRAMEBUFFER, null); gl.viewport(0, 0, canvas.width, canvas.height);
    const copy = program(gl, copyFragmentShader, vertexShader); programs.push(copy); gl.useProgram(copy); bindGeometry(gl, copy, buffer);
    gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, finalTexture);
    const sampler = gl.getUniformLocation(copy, "inputImageTexture"); if (sampler) gl.uniform1i(sampler, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  } finally {
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    framebuffers.forEach(item => gl.deleteFramebuffer(item)); programs.forEach(item => gl.deleteProgram(item)); textures.forEach(item => gl.deleteTexture(item)); gl.deleteBuffer(buffer);
  }
}

function loadBatchImage(url: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error(`Could not load ${url}`));
    image.src = url;
  });
}

async function recordGraphVideo(canvas: HTMLCanvasElement, image: HTMLImageElement, passSources: RenderPass[], graphUniforms: Record<string, UniformSpec> = {}, onProgress?: (fraction: number) => void) {
  // FBO chaining at full 1080p can starve Safari's capture stream. 720p keeps a
  // three-to-five pass export temporally faithful; interactive preview remains native-size.
  const exportLimit = 720;
  renderGraphFrame(canvas, image, passSources, 0, 0, exportLimit, graphUniforms);
  const mime = ["video/mp4", "video/webm;codecs=vp9", "video/webm"].find(MediaRecorder.isTypeSupported) || "";
  const recorder = new MediaRecorder(canvas.captureStream(30), mime ? { mimeType: mime } : undefined);
  const chunks: Blob[] = [];
  recorder.ondataavailable = event => { if (event.data.size) chunks.push(event.data); };
  const stopped = new Promise<void>(resolve => { recorder.onstop = () => resolve(); });
  recorder.start();
  const started = performance.now();
  // Safari heavily throttles or suspends requestAnimationFrame when an
  // automation tab is not frontmost. Advance from wall-clock time instead so
  // a five-second export cannot stall indefinitely in a background window.
  while (true) {
    const now = performance.now();
    const fraction = Math.min((now - started) / 5000, 1);
    renderGraphFrame(canvas, image, passSources, fraction, now / 1000, exportLimit, graphUniforms);
    onProgress?.(fraction);
    if (fraction >= 1) break;
    await new Promise(resolve => setTimeout(resolve, 34));
  }
  recorder.stop();
  await stopped;
  return new Blob(chunks, { type: recorder.mimeType || "video/webm" });
}

export default function Home() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const sourceRef = useRef<HTMLImageElement | null>(null);
  const inputObjectUrlRef = useRef<string | null>(null);
  const renderedVideoUrlRef = useRef<string | null>(null);
  const [passes, setPasses] = useState<Pass[]>(defaultPasses);
  const [selected, setSelected] = useState(0);
  const [shaderStage, setShaderStage] = useState<"fragment" | "vertex">("fragment");
  const [progress, setProgress] = useState(0.42);
  const [playing, setPlaying] = useState(false);
  const [status, setStatus] = useState("等待输入");
  const [error, setError] = useState("");
  const [fileName, setFileName] = useState("尚未选择输入图");
  const [exporting, setExporting] = useState(false);
  const [renderedVideo, setRenderedVideo] = useState<{ url: string; name: string; mime: string; bytes: number } | null>(null);
  const [comparisonView, setComparisonView] = useState<"result" | "target">("result");
  const [feedbackConfig, setFeedbackConfig] = useState<{ job: string; allowFinish: boolean } | null>(null);
  const [feedbackText, setFeedbackText] = useState("");
  const [feedbackState, setFeedbackState] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [feedbackMessage, setFeedbackMessage] = useState("");
  const [graphParameters, setGraphParameters] = useState<Record<string, UniformSpec>>({});
  const [sourceFile, setSourceFile] = useState<File | null>(null);
  const [targetFile, setTargetFile] = useState<File | null>(null);
  const [targetPreviewUrl, setTargetPreviewUrl] = useState("");
  const [passCountInput, setPassCountInput] = useState("");
  const [passDescriptionInput, setPassDescriptionInput] = useState("");
  const [effectDescriptionInput, setEffectDescriptionInput] = useState("");
  const [denseTimelineMode, setDenseTimelineMode] = useState(false);
  const [activeJob, setActiveJob] = useState("");
  const [jobStatus, setJobStatus] = useState<AgentJobStatus | null>(null);
  const [agentOnline, setAgentOnline] = useState<boolean | null>(null);
  const [startingJob, setStartingJob] = useState(false);
  const loadedVideoVersionRef = useRef("");
  const loadingVideoVersionRef = useRef("");
  const requestedVideoVersionRef = useRef("");
  const feedbackRoundRef = useRef<number | null>(null);
  const activeRenderRequestRef = useRef("");
  const startRef = useRef(performance.now());

  useEffect(() => {
    const queryJob = new URLSearchParams(window.location.search).get("job");
    const savedJob = window.localStorage.getItem("multipass-agent-job");
    const job = queryJob || savedJob || "";
    if (job) setActiveJob(job);
  }, []);

  const publishRenderedVideo = useCallback((blob: Blob, name: string) => {
    if (renderedVideoUrlRef.current) URL.revokeObjectURL(renderedVideoUrlRef.current);
    const url = URL.createObjectURL(blob);
    renderedVideoUrlRef.current = url;
    setRenderedVideo({ url, name, mime: blob.type || "video/webm", bytes: blob.size });
    setComparisonView("result");
    setStatus(`渲染完成：${name} · ${(blob.size / 1024 / 1024).toFixed(1)} MB`);
    setError("");
  }, []);

  useEffect(() => () => {
    if (inputObjectUrlRef.current) URL.revokeObjectURL(inputObjectUrlRef.current);
    if (renderedVideoUrlRef.current) URL.revokeObjectURL(renderedVideoUrlRef.current);
  }, []);
  useEffect(() => () => { if (targetPreviewUrl) URL.revokeObjectURL(targetPreviewUrl); }, [targetPreviewUrl]);

  const submitFeedback = async (action: "revise" | "finish") => {
    if (!feedbackConfig || (action === "revise" && !feedbackText.trim()) || feedbackState === "sending") return;
    setFeedbackState("sending");
    setFeedbackMessage("正在把反馈发送给本地工作流…");
    const endpoint = `${AGENT_API}/jobs/${encodeURIComponent(feedbackConfig.job)}/feedback`;
    const payload = JSON.stringify({ action, feedback: feedbackText.trim(), job_id: feedbackConfig.job });
    try {
      const response = await fetch(endpoint, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: payload,
      });
      if (!response.ok) throw new Error(`反馈提交失败 (${response.status})`);
      setFeedbackState("sent");
      setFeedbackMessage(action === "finish" ? "已接受当前结果，工作流正在结束…" : "已提交。工作流已收到反馈，正在启动下一轮修复…");
      setStatus(action === "finish" ? "人工已接受当前结果" : "人工反馈已提交，后端正在生成下一轮…");
    } catch (e) {
      const message=e instanceof Error ? e.message : String(e);
      setFeedbackState("error");
      setFeedbackMessage(`提交失败：${message}`);
      setError(message);
    }
  };

  const render = useCallback((p = progress, time = performance.now() / 1000) => {
    const canvas = canvasRef.current;
    const image = sourceRef.current;
    if (!canvas || !image) return;
    try {
      renderGraphFrame(canvas, image, passes, p, time, 0, graphParameters);
      setError("");
      setStatus(`${passes.length} passes · resource graph · ${canvas.width}×${canvas.height}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setStatus("图谱渲染失败");
    }
  }, [passes, progress, graphParameters]);

  useEffect(() => { render(); }, [render]);
  useEffect(() => {
    const loadGeneratedGraph = async (graphUrl: string) => {
      const graph = await fetch(graphUrl, { cache: "no-store" }).then(async response => {
        if (!response.ok) throw new Error(`Generated graph unavailable: ${response.status}`);
        return response.json() as Promise<GeneratedGraph>;
      });
      if (!graph.id || !Array.isArray(graph.passes) || graph.passes.length === 0) {
        throw new Error("Generated graph requires an id and at least one pass");
      }
      const inputUrl = new URL(graph.input_image, graphUrl).toString();
      setFileName(graph.input_image.split("/").pop() || "generated input");
      setStatus(`输入已载入：${graph.id} · 正在准备 ${graph.passes.length} 层…`);
      const image = await loadBatchImage(inputUrl);
      const passSources = await Promise.all(graph.passes.map(async (pass, index) => {
        if (!pass.fragment_shader) throw new Error(`Pass ${index + 1} has no fragment shader`);
        const fragmentResponse = await fetch(new URL(pass.fragment_shader, graphUrl), { cache: "no-store" });
        if (!fragmentResponse.ok) throw new Error(`Pass ${index + 1} shader unavailable`);
        const vertex = pass.vertex_shader ? await fetch(new URL(pass.vertex_shader, graphUrl), { cache: "no-store" }).then(async response => {
          if (!response.ok) throw new Error(`Pass ${index + 1} vertex shader unavailable`);
          return response.text();
        }) : "";
        return { ...pass, fragment: await fragmentResponse.text(), vertex };
      }));
      sourceRef.current = image;
      setPasses(passSources.map((pass, index) => ({
        id: pass.id || `pass_${index + 1}`,
        name: pass.name || `Pass ${index + 1}`,
        fragment: pass.fragment,
        vertex: pass.vertex,
        inputs: pass.inputs,
        output: pass.output,
        scale: pass.scale,
        uniforms: pass.uniforms,
      })));
      setSelected(0);
      setGraphParameters(graph.parameters || {});
      if (canvasRef.current) renderGraphFrame(canvasRef.current, image, passSources, 0, 0, 0, graph.parameters || {});
      return { graph, image, passSources };
    };
    window.__renderMultiPassJob = async (graphUrl, uploadBase) => {
      const { graph, image, passSources } = await loadGeneratedGraph(graphUrl);
      const canvas = document.createElement("canvas");
      canvas.style.cssText = "position:fixed;left:-10000px;top:0";
      document.body.appendChild(canvas);
      try {
        setStatus(`正在渲染 ${graph.id} · ${passSources.length} Pass · 0%`);
        const blob = await recordGraphVideo(canvas, image, passSources, graph.parameters || {}, fraction => {
          setStatus(`正在渲染 ${graph.id} · ${passSources.length} Pass · ${Math.round(fraction * 100)}%`);
        });
        publishRenderedVideo(blob, graph.id);
        setStatus(`视频已编码：${graph.id} · 正在保存到本地结果目录…`);
        const extension = blob.type.includes("mp4") ? "mp4" : "webm";
        const response = await fetch(`${uploadBase.replace(/\/$/, "")}/${encodeURIComponent(graph.id)}.${extension}`, {
          method: "PUT", headers: { "Content-Type": blob.type }, body: blob,
        });
        if (!response.ok) throw new Error(`Video upload failed: ${response.status}`);
        setStatus(`渲染并保存完成：${graph.id}`);
        return { id: graph.id, mime: blob.type, bytes: blob.size };
      } finally {
        canvas.remove();
      }
    };
    window.__loadMultiPassResult = async (graphUrl, videoUrl, requestKey) => {
      const { graph } = await loadGeneratedGraph(graphUrl);
      setStatus(`正在载入已完成视频：${graph.id}`);
      const response = await fetch(videoUrl, { cache: "no-store" });
      if (!response.ok) throw new Error(`Completed video unavailable: ${response.status}`);
      const blob = await response.blob();
      if (requestKey && requestedVideoVersionRef.current !== requestKey) {
        return { id: graph.id, bytes: blob.size, stale: true };
      }
      publishRenderedVideo(blob, graph.id);
      setStatus(`已载入完整结果：${graph.id} · 等待人工反馈`);
      return { id: graph.id, bytes: blob.size };
    };
    window.__renderMultiPassPrefix = async (graphUrl, uploadBase, passCount) => {
      const graph = await fetch(graphUrl, { cache: "no-store" }).then(async response => {
        if (!response.ok) throw new Error(`Generated graph unavailable: ${response.status}`);
        return response.json() as Promise<GeneratedGraph>;
      });
      if (!Number.isInteger(passCount) || passCount < 1 || passCount > graph.passes.length) {
        throw new Error("Prefix pass count is outside the generated graph");
      }
      const image = await loadBatchImage(new URL(graph.input_image, graphUrl).toString());
      const passSources = await Promise.all(graph.passes.slice(0, passCount).map(async (pass, index) => {
        if (!pass.fragment_shader) throw new Error(`Pass ${index + 1} has no fragment shader`);
        const fragmentResponse = await fetch(new URL(pass.fragment_shader, graphUrl), { cache: "no-store" });
        if (!fragmentResponse.ok) throw new Error(`Pass ${index + 1} shader unavailable`);
        const vertex = pass.vertex_shader ? await fetch(new URL(pass.vertex_shader, graphUrl), { cache: "no-store" }).then(async response => {
          if (!response.ok) throw new Error(`Pass ${index + 1} vertex shader unavailable`);
          return response.text();
        }) : "";
        return { ...pass, fragment: await fragmentResponse.text(), vertex };
      }));
      const canvas = document.createElement("canvas");
      canvas.style.cssText = "position:fixed;left:-10000px;top:0";
      document.body.appendChild(canvas);
      try {
        const progressValues = [0, 0.5, 1];
        const frames: Array<{ progress: number; bitmap: ImageBitmap }> = [];
        for (const progressValue of progressValues) {
          renderGraphFrame(canvas, image, passSources, progressValue, progressValue * 5.0, 720, graph.parameters || {});
          frames.push({ progress: progressValue, bitmap: await createImageBitmap(canvas) });
        }
        const sheet = document.createElement("canvas");
        sheet.width = canvas.width * frames.length;
        sheet.height = canvas.height + 28;
        const context = sheet.getContext("2d");
        if (!context) throw new Error("Could not create prefix contact sheet");
        context.fillStyle = "white"; context.fillRect(0, 0, sheet.width, sheet.height);
        context.fillStyle = "#141414"; context.font = "14px system-ui";
        frames.forEach((frame, index) => {
          context.drawImage(frame.bitmap, index * canvas.width, 28);
          context.fillText(`PREFIX ${passCount} · p=${frame.progress.toFixed(2)}`, index * canvas.width + 8, 19);
          frame.bitmap.close();
        });
        const blob = await new Promise<Blob>((resolve, reject) => sheet.toBlob(value => value ? resolve(value) : reject(new Error("Could not encode prefix sheet")), "image/jpeg", 0.92));
        const stillBase = uploadBase.replace(/\/videos\/?$/, "/stills");
        const response = await fetch(`${stillBase.replace(/\/$/, "")}/${encodeURIComponent(graph.id)}_prefix_${passCount}.jpg`, {
          method: "PUT", headers: { "Content-Type": blob.type }, body: blob,
        });
        if (!response.ok) throw new Error(`Prefix upload failed: ${response.status}`);
        return { id: graph.id, bytes: blob.size };
      } finally {
        canvas.remove();
      }
    };
    return () => {
      delete window.__renderMultiPassJob;
      delete window.__renderMultiPassPrefix;
      delete window.__loadMultiPassResult;
    };
  }, [publishRenderedVideo]);
  useEffect(() => {
    if (!activeJob) return;
    let cancelled = false;
    const refresh = async () => {
      try {
        const response = await fetch(`${AGENT_API}/jobs/${encodeURIComponent(activeJob)}`, { cache: "no-store" });
        if (!response.ok) throw new Error(`任务状态不可用 (${response.status})`);
        const next = await response.json() as AgentJobStatus;
        if (cancelled) return;
        setAgentOnline(true);
        setError(current => isTransientNetworkMessage(current) ? "" : current);
        setJobStatus(next);
        const labels: Record<string, string> = {
          running: "正在准备模型规划…",
          pass_implementation: `正在实现 Pass ${Math.min(next.completed_passes + 1, next.resolved_pass_count || next.completed_passes + 1)}…`,
          final_refinement: "所有 Pass 已生成，正在渲染完整视频…",
          waiting_for_human_feedback: `第 ${next.round_count} 版已完成，等待人工反馈`,
          applying_human_feedback: `正在落实第 ${(next.feedback_round ?? 0) + 1} 条人工反馈…`,
          applying_repair_transaction: "正在修改、渲染并验收必须落实的变化…",
          complete: "任务已完成",
          failed: "Agent 执行失败",
          cancelled: "任务已取消",
          interrupted: "服务重启前的任务已中断",
        };
        setStatus(labels[next.phase] || `Agent：${next.phase}`);
        if (next.phase === "waiting_for_human_feedback") {
          setFeedbackConfig({ job: activeJob, allowFinish: true });
          const currentFeedbackRound = next.feedback_round ?? 0;
          if (feedbackRoundRef.current !== currentFeedbackRound) {
            feedbackRoundRef.current = currentFeedbackRound;
            setFeedbackState("idle");
            setFeedbackText("");
            setFeedbackMessage("");
          }
        } else {
          setFeedbackConfig(null);
        }
        if (next.phase === "failed" || (next.exit_code != null && next.exit_code !== 0)) {
          setError(next.error_log || "Agent 进程异常结束");
        }
        const renderRequest = next.render_request;
        if (renderRequest && activeRenderRequestRef.current !== renderRequest.request_id) {
          activeRenderRequestRef.current = renderRequest.request_id;
          const graphUrl = new URL(renderRequest.graph_url, window.location.origin).toString();
          const eventsUrl = renderRequest.upload_base.replace(/\/videos\/?$/, "/events");
          const report = (event: Record<string, unknown>) => fetch(eventsUrl, {
            method: "POST", headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ at: new Date().toISOString(), run: renderRequest.run, graph: renderRequest.graph_url, broker: true, ...event }),
          }).catch(() => undefined);
          void report({ event: "job_started", kind: renderRequest.kind, pass_count: renderRequest.prefix_count });
          try {
            if (renderRequest.kind === "prefix") {
              await window.__renderMultiPassPrefix?.(graphUrl, renderRequest.upload_base, Number(renderRequest.prefix_count));
            } else if (renderRequest.kind === "existing" && renderRequest.existing_video_url) {
              await window.__loadMultiPassResult?.(graphUrl, renderRequest.existing_video_url);
            } else {
              await window.__renderMultiPassJob?.(graphUrl, renderRequest.upload_base);
            }
            void report({ event: "job_complete", kind: renderRequest.kind });
          } catch (reason) {
            const message = reason instanceof Error ? reason.message : String(reason);
            void report({ event: "job_failed", kind: renderRequest.kind, error: message });
            setError(message);
          }
        }
        if (next.video_url && next.video_version && next.graph_url && loadedVideoVersionRef.current !== next.video_version && loadingVideoVersionRef.current !== next.video_version && window.__loadMultiPassResult) {
          const version = next.video_version;
          requestedVideoVersionRef.current = version;
          loadingVideoVersionRef.current = version;
          try {
            const result = await window.__loadMultiPassResult(new URL(next.graph_url, window.location.origin).toString(), `${next.video_url}?v=${encodeURIComponent(version)}`, version);
            if (!result.stale && requestedVideoVersionRef.current === version) loadedVideoVersionRef.current = version;
          } finally {
            if (loadingVideoVersionRef.current === version) loadingVideoVersionRef.current = "";
          }
        }
      } catch (reason) {
        if (!cancelled) {
          const message = networkMessage(reason);
          if (message === AGENT_OFFLINE_MESSAGE) setAgentOnline(false);
          setError(message);
        }
      }
    };
    void refresh();
    const timer = window.setInterval(() => { void refresh(); }, 1200);
    return () => { cancelled = true; window.clearInterval(timer); };
  }, [activeJob]);
  useEffect(() => {
    const query = new URLSearchParams(window.location.search);
    const graphPath = query.get("renderPrefix");
    if (!graphPath) return;
    const passCount = Number(query.get("prefixCount"));
    const graphUrl = new URL(graphPath, window.location.origin).toString();
    const uploadBase = query.get("renderOutput") || "http://127.0.0.1:8789/videos";
    const runId = query.get("run") || "";
    const report = (event: Record<string, unknown>) => fetch(uploadBase.replace(/\/videos\/?$/, "/events"), {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ at: new Date().toISOString(), run: runId, graph: graphPath, ...event }),
    }).catch(() => undefined);
    setStatus(`正在渲染前 ${passCount} 层的中间结果…`);
    void report({ event: "job_started", kind: "prefix", pass_count: passCount });
    window.__renderMultiPassPrefix?.(graphUrl, uploadBase, passCount)
      .then(result => { void report({ event: "job_complete", kind: "prefix", id: result.id, bytes: result.bytes }); setStatus(`前缀渲染完成：${result.id}`); })
      .catch(error => { const message=error instanceof Error ? error.message : String(error); void report({ event: "job_failed", kind: "prefix", error: message }); setError(message); setStatus("前缀渲染失败"); });
  }, []);
  useEffect(() => {
    const query = new URLSearchParams(window.location.search);
    const graphPath = query.get("renderJob");
    if (!graphPath) return;
    const graphUrl = new URL(graphPath, window.location.origin).toString();
    const uploadBase = query.get("renderOutput") || "http://127.0.0.1:8789/videos";
    const runId = query.get("run") || "";
    const report = (event: Record<string, unknown>) => fetch(uploadBase.replace(/\/videos\/?$/, "/events"), {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ at: new Date().toISOString(), run: runId, graph: graphPath, ...event }),
    }).catch(() => undefined);
    setStatus("正在渲染模型生成的多 pass 图谱…");
    void report({ event: "job_started" });
    window.__renderMultiPassJob?.(graphUrl, uploadBase)
      .then(result => { void report({ event: "job_complete", id: result.id, bytes: result.bytes, mime: result.mime }); setStatus(`渲染完成：${result.id}`); })
      .catch(error => {
        const message = error instanceof Error ? error.message : String(error);
        void report({ event: "job_failed", error: message });
        setError(message); setStatus("多 pass 渲染失败");
      });
  }, []);
  useEffect(() => {
    if (!playing) return;
    let frame = 0;
    const tick = (now: number) => {
      const value = ((now - startRef.current) % 5000) / 5000;
      setProgress(value);
      render(value, now / 1000);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [playing, render]);

  const loadImage = (file: File) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => {
      if (inputObjectUrlRef.current) URL.revokeObjectURL(inputObjectUrlRef.current);
      inputObjectUrlRef.current = url;
      sourceRef.current = image;
      setFileName(file.name);
      if (renderedVideoUrlRef.current) URL.revokeObjectURL(renderedVideoUrlRef.current);
      renderedVideoUrlRef.current = null;
      setRenderedVideo(null);
      setStatus(`输入已载入：${file.name} · ${image.naturalWidth}×${image.naturalHeight}`);
      render();
    };
    image.onerror = () => { URL.revokeObjectURL(url); setError(`无法读取输入图片：${file.name}`); setStatus("输入加载失败"); };
    image.src = url;
  };

  const chooseSource = (file: File) => {
    setSourceFile(file);
    loadImage(file);
  };

  const chooseTarget = (file: File) => {
    if (targetPreviewUrl) URL.revokeObjectURL(targetPreviewUrl);
    setTargetFile(file);
    setTargetPreviewUrl(URL.createObjectURL(file));
  };

  const startAgentJob = async () => {
    if (!sourceFile || !targetFile || startingJob) return;
    const description = passDescriptionInput.trim();
    const effectDescription = effectDescriptionInput.trim();
    const count = passCountInput.trim();
    const numericCount = count ? Number(count) : null;
    if (denseTimelineMode && (description || effectDescription || numericCount != null)) {
      setError("逐 0.2 秒描述实验不接受 Pass 数、Pass 职责或画面文字先验，请先清空三个输入。 ");
      return;
    }
    if (numericCount != null && (!Number.isInteger(numericCount) || numericCount < 1)) {
      setError("Pass 数量必须是正整数。");
      return;
    }
    setStartingJob(true);
    setError("");
    try {
      setStatus("正在创建 Agent 任务…");
      const create = await fetch(`${AGENT_API}/jobs`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pass_count: numericCount, pass_description: description, effect_description: effectDescription, dense_timeline: denseTimelineMode, source_name: sourceFile.name, video_name: targetFile.name }),
      });
      if (!create.ok) throw new Error(`创建任务失败 (${create.status})`);
      const metadata = await create.json() as { job_id: string };
      setStatus("正在上传原图…");
      const sourceUpload = await fetch(`${AGENT_API}/jobs/${metadata.job_id}/source-image`, { method: "PUT", headers: { "Content-Type": sourceFile.type || "application/octet-stream" }, body: sourceFile });
      if (!sourceUpload.ok) throw new Error(`原图上传失败 (${sourceUpload.status})`);
      setStatus("正在上传目标视频…");
      const videoUpload = await fetch(`${AGENT_API}/jobs/${metadata.job_id}/target-video`, { method: "PUT", headers: { "Content-Type": targetFile.type || "application/octet-stream" }, body: targetFile });
      if (!videoUpload.ok) throw new Error(`目标视频上传失败 (${videoUpload.status})`);
      const start = await fetch(`${AGENT_API}/jobs/${metadata.job_id}/start`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
      if (!start.ok) {
        const payload = await start.json().catch(() => ({})) as { error?: string };
        throw new Error(payload.error || `启动失败 (${start.status})`);
      }
      loadedVideoVersionRef.current = "";
      loadingVideoVersionRef.current = "";
      requestedVideoVersionRef.current = "";
      setActiveJob(metadata.job_id);
      window.localStorage.setItem("multipass-agent-job", metadata.job_id);
      setStatus(denseTimelineMode ? "模型正在逐 0.2 秒观察；随后先归纳完整动态过程，再自主规划 Pass…" : description || effectDescription || numericCount ? "输入已提交：模型先独立观察视频，再用文字补充可见信息…" : "模型正在独立观察原图和时序抽帧并规划 Pass 图谱…");
    } catch (reason) {
      const message = networkMessage(reason);
      if (message === AGENT_OFFLINE_MESSAGE) setAgentOnline(false);
      setError(message);
      setStatus("任务启动失败");
    } finally {
      setStartingJob(false);
    }
  };

  const exportVideo = async () => {
    const canvas = canvasRef.current;
    if (!canvas || !sourceRef.current) return;
    setExporting(true);
    setPlaying(false);
    setStatus("正在编码 5 秒视频 · 0%");
    try {
      const blob = await recordGraphVideo(canvas, sourceRef.current, passes, graphParameters, fraction => {
        setStatus(`正在编码 5 秒视频 · ${Math.round(fraction * 100)}%`);
      });
      const extension = blob.type.includes("mp4") ? "mp4" : "webm";
      publishRenderedVideo(blob, `multipass-render.${extension}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setStatus("视频编码失败");
    } finally {
      setExporting(false);
    }
  };

  const cancelAgentJob = async () => {
    if (!activeJob) return;
    const response = await fetch(`${AGENT_API}/jobs/${encodeURIComponent(activeJob)}/cancel`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
    if (!response.ok) {
      const payload = await response.json().catch(() => ({})) as { error?: string };
      setError(payload.error || `取消失败 (${response.status})`);
      return;
    }
    setStatus("任务已取消");
  };

  const resumeAgentJob = async () => {
    if (!activeJob || startingJob) return;
    setStartingJob(true);
    setError("");
    setStatus("正在从最近检查点恢复…");
    try {
      const response = await fetch(`${AGENT_API}/jobs/${encodeURIComponent(activeJob)}/resume`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
      if (!response.ok) {
        const payload = await response.json().catch(() => ({})) as { error?: string };
        throw new Error(payload.error || `恢复失败 (${response.status})`);
      }
      loadedVideoVersionRef.current = "";
      loadingVideoVersionRef.current = "";
      requestedVideoVersionRef.current = "";
      setStatus("已恢复，将从失败步骤继续执行…");
    } catch (reason) {
      const message = networkMessage(reason);
      if (message === AGENT_OFFLINE_MESSAGE) setAgentOnline(false);
      setError(message);
      setStatus("恢复失败");
    } finally {
      setStartingJob(false);
    }
  };

  const updatePass = (source: string) => {
    setPasses(items => items.map((item, index) => index === selected ? { ...item, [shaderStage]: source } : item));
  };

  const updatePassGraph = (change: Partial<Pick<Pass, "inputs" | "output" | "scale">>) => {
    setPasses(items => items.map((item, index) => index === selected ? { ...item, ...change } : item));
  };

  const comparisonTargetUrl = targetPreviewUrl || jobStatus?.target_url || "";

  return (
    <main>
      <header className="topbar">
        <div className="brand"><span className="mark">MP</span><div><strong>MultiPass Studio</strong><small>WebGL render graph</small></div></div>
        {activeJob && <div className="agent-chip"><span></span><div><strong>{jobStatus?.phase || "starting"}</strong><small>{jobStatus?.resolved_pass_count ? `${jobStatus.completed_passes}/${jobStatus.resolved_pass_count} Pass · ${jobStatus.round_count} 个完整版本` : "正在分析输入"}</small></div></div>}
        <div className={`health ${agentOnline === false ? "offline" : ""}`}><span></span>{agentOnline === false ? "Agent offline" : "Agent + GPU ready"}</div>
        {activeJob && !["complete", "failed", "cancelled", "interrupted"].includes(jobStatus?.phase || "") && <button className="new-job" onClick={cancelAgentJob}>取消任务</button>}
        {activeJob && ["failed", "interrupted"].includes(jobStatus?.phase || "") && <button className="new-job" disabled={startingJob} onClick={resumeAgentJob}>{startingJob ? "恢复中…" : "从失败处继续"}</button>}
        {activeJob && ["complete", "failed", "cancelled", "interrupted"].includes(jobStatus?.phase || "") && <button className="new-job" onClick={() => { window.localStorage.removeItem("multipass-agent-job"); setActiveJob(""); setJobStatus(null); setFeedbackConfig(null); loadedVideoVersionRef.current = ""; loadingVideoVersionRef.current = ""; requestedVideoVersionRef.current = ""; }}>新任务</button>}
        <button className="export" disabled={exporting || !sourceRef.current} onClick={exportVideo}>{exporting ? "编码中…" : "导出 5 秒视频"}</button>
      </header>

      {!activeJob && <section className="agent-launcher">
        <div className="launcher-card">
          <div className="launcher-heading"><span>AGENT WORKFLOW</span><h1>从原图与目标视频生成多 Pass Shader</h1><p>模型始终先独立观察视频抽帧。Pass 数量与职责是结构约束；画面描述仅作辅助，和视频冲突时以视频为准。</p></div>
          <button
            type="button"
            role="switch"
            aria-checked={denseTimelineMode}
            className={`dense-mode-card ${denseTimelineMode ? "enabled" : ""}`}
            onClick={() => {
              const enabled = !denseTimelineMode;
              setDenseTimelineMode(enabled);
              if (enabled) {
                setPassCountInput("");
                setPassDescriptionInput("");
                setEffectDescriptionInput("");
              }
              setError("");
            }}
          >
            <span className="dense-mode-icon">{denseTimelineMode ? "✓" : "0.2s"}</span>
            <span className="dense-mode-copy">
              <small>NEW EXPERIMENT · 无 Pass 先验</small>
              <strong>每 0.2 秒描述 → 整体变化归纳 → Agent 规划</strong>
              <em>{denseTimelineMode ? "已启用：逐段观察后会先生成详细的连续过程规格" : "点击启用。模型先逐段观察，再归纳完整动态，最后自主生成多 Pass Shader。"}</em>
            </span>
            <span className="dense-mode-switch" aria-hidden="true"><i /></span>
          </button>
          <div className="asset-grid">
            <label className={`asset-drop ${sourceFile ? "ready" : ""}`}>
              <span>01 · 原始输入图</span><strong>{sourceFile?.name || "选择图片"}</strong><small>{sourceFile ? `${(sourceFile.size / 1024 / 1024).toFixed(1)} MB` : "Agent 实际渲染的干净原图"}</small>
              <input type="file" accept="image/*" onChange={event => event.target.files?.[0] && chooseSource(event.target.files[0])} />
            </label>
            <label className={`asset-drop ${targetFile ? "ready" : ""}`}>
              <span>02 · 目标特效视频</span><strong>{targetFile?.name || "选择视频"}</strong><small>{targetFile ? `${(targetFile.size / 1024 / 1024).toFixed(1)} MB` : "用于观察完整动态过程"}</small>
              <input type="file" accept="video/*" onChange={event => event.target.files?.[0] && chooseTarget(event.target.files[0])} />
            </label>
          </div>
          <div className="plan-grid">
            {denseTimelineMode && <div className="dense-mode-notice">密集时序模式已锁定：以下三个先验输入已禁用，防止 Pass 信息泄漏。</div>}
            <label className="effect-description"><span>画面特效辅助说明（可选）</span><textarea disabled={denseTimelineMode} value={effectDescriptionInput} onChange={event => setEffectDescriptionInput(event.target.value)} placeholder={denseTimelineMode ? "密集时序实验中已禁用" : '可补充难以从抽帧确认的信息。模型会先看视频，只采用能被画面支持的部分；冲突内容会被忽略。'} /></label>
            <label><span>Pass 数量（可选）</span><input disabled={denseTimelineMode} type="number" min="1" value={passCountInput} onChange={event => setPassCountInput(event.target.value)} placeholder={denseTimelineMode ? "实验模式中已禁用" : "留空则由模型决定"} /></label>
            <label><span>每个 Pass 的职责（可选）</span><textarea disabled={denseTimelineMode} value={passDescriptionInput} onChange={event => setPassDescriptionInput(event.target.value)} placeholder={denseTimelineMode ? "密集时序实验中已禁用" : '填写已知职责；未描述的顺序、连接或其他职责由模型补全。例如：\n一层负责产生动态遮罩\n最终层负责颜色与合成'} /></label>
          </div>
          <div className="launcher-preview">
            {targetPreviewUrl ? <video src={targetPreviewUrl} controls playsInline /> : <div><span>VIDEO PREVIEW</span><small>上传后可在这里确认目标视频</small></div>}
            <div className={`launcher-mode ${denseTimelineMode ? "dense" : ""}`}><span>{denseTimelineMode ? "DENSE TIMELINE ACTIVE" : passDescriptionInput.trim() || passCountInput.trim() || effectDescriptionInput.trim() ? "VISUAL FIRST" : "MODEL PLAN"}</span><p>{denseTimelineMode ? "按真实时间每 0.2 秒逐区间描述，再单独归纳起始、传播、峰值、恢复和重复关系，之后才规划 Pass 图谱。" : passDescriptionInput.trim() || passCountInput.trim() || effectDescriptionInput.trim() ? "先从抽帧建立视觉事实；仅 Pass 数量和职责属于硬约束，画面文字只是待验证提示。" : "三个输入均为空，模型仅观察原图和时序抽帧，自行决定完整 Pass 图谱。"}</p></div>
          </div>
          <button className={`start-agent ${denseTimelineMode ? "dense" : ""}`} disabled={!sourceFile || !targetFile || startingJob} onClick={startAgentJob}>{startingJob ? status : denseTimelineMode ? "启动 0.2s 密集时序实验" : "启动 Agent"}</button>
          {error && <pre className="launcher-error">{error}</pre>}
        </div>
      </section>}

      <section className="workspace">
        <aside className="sidebar">
          <div className="section-title"><span>PASS GRAPH</span></div>
          <div className="source-node"><i>IN</i><div><strong>Source texture</strong><small>{fileName}</small></div></div>
          <div className="connector" />
          {passes.map((pass, index) => (
            <div key={pass.id}>
              <button className={`pass-node ${selected === index ? "active" : ""}`} onClick={() => setSelected(index)}>
                <i>{index + 1}</i><div><strong>{pass.name}</strong><small>{Object.entries(pass.inputs || { inputImageTexture: index === 0 ? "source" : "previous" }).map(([uniform, resource]) => `${uniform} ← ${resource}`).join(" · ")}</small><small>{pass.output || `pass_${index + 1}`} · FBO {pass.scale ?? 1}×</small></div><b>›</b>
              </button>
              {index < passes.length - 1 && <div className="connector" />}
            </div>
          ))}
        </aside>

        <section className="stage">
          <div className="stage-head"><div><span>{renderedVideo ? "AGENT RESULT" : "LIVE PROGRESS"}</span><strong aria-live="polite">{status}</strong></div></div>
          <div className="canvas-wrap">
            {activeJob && !renderedVideo && <div className="agent-progress-card">
              <div className="agent-spinner" />
              <span>{jobStatus?.planning_mode === "dense_timeline" ? "DENSE TIMELINE → AGENT" : jobStatus?.planning_mode === "model" ? "MODEL PLANNING" : "CONSTRAINED PLANNING"}</span>
              <strong>{status}</strong>
              <p>页面会保持不动；后台完成规划、逐层生成和渲染后，首版视频会自动出现在这里。</p>
              {jobStatus?.passes?.length ? <ol>{jobStatus.passes.map((item, index) => <li key={item.id}><b>{index + 1}</b><div><strong>{item.name}</strong><small>{item.role}</small></div></li>)}</ol> : <small>正在读取原图与目标视频的时序变化…</small>}
            </div>}
            {activeJob && jobStatus?.current_obligation && <div className="transaction-status" aria-live="polite"><span>REPAIR TRANSACTION · {jobStatus.current_obligation.scope || "scoped"}</span><strong>{jobStatus.current_obligation.required_visible_change || "正在落实当前修改"}</strong>{jobStatus.current_obligation.acceptance_criteria?.length ? <small>验收：{jobStatus.current_obligation.acceptance_criteria.join("；")}</small> : null}</div>}
            {!activeJob && !sourceRef.current && <div className="empty"><div>◎</div><strong>等待 Agent 输入</strong><span>请先上传原图和目标视频</span></div>}
            <canvas ref={canvasRef} />
            {renderedVideo && <div className="main-rendered-video">
              <div className="rendered-toolbar"><strong>{renderedVideo.name}</strong><span>{(renderedVideo.bytes / 1024 / 1024).toFixed(1)} MB</span>{jobStatus?.video_status === "candidate" && <span className="candidate-badge">当前 Feedback 候选 · 可继续修改</span>}<a href={renderedVideo.url} download={renderedVideo.name}>下载视频</a></div>
              <div className="video-mode-tabs" role="tablist" aria-label="对比视频切换">
                <button role="tab" aria-selected={comparisonView === "result"} className={comparisonView === "result" ? "active" : ""} onClick={() => setComparisonView("result")}>当前视频</button>
                <button role="tab" aria-selected={comparisonView === "target"} className={comparisonView === "target" ? "active" : ""} disabled={!comparisonTargetUrl} onClick={() => setComparisonView("target")}>原视频</button>
              </div>
              <div className="single-video-pane">
                {comparisonView === "result" && <video data-testid="rendered-result-video" key={renderedVideo.url} src={renderedVideo.url} controls playsInline />}
                {comparisonView === "target" && comparisonTargetUrl && <video data-testid="comparison-target-video" key={comparisonTargetUrl} src={comparisonTargetUrl} controls playsInline />}
              </div>
            </div>}
            {feedbackConfig && renderedVideo && <div className="human-feedback-panel">
              <span>HUMAN FEEDBACK · {feedbackConfig.job}</span>
              {feedbackState === "sent" ? <strong>{feedbackMessage}</strong> : <><textarea value={feedbackText} onChange={event => { setFeedbackText(event.target.value); setFeedbackState("idle"); setFeedbackMessage(""); }} placeholder="描述当前视频与目标相比还差在哪里…" /><div><button disabled={!feedbackText.trim() || feedbackState === "sending"} onClick={() => submitFeedback("revise")}>{feedbackState === "sending" ? "提交中…" : "提交反馈并继续"}</button>{feedbackConfig.allowFinish && <button disabled={feedbackState === "sending"} onClick={() => submitFeedback("finish")}>接受当前结果并结束</button>}</div>{feedbackMessage && <small className={feedbackState === "error" ? "feedback-error" : ""}>{feedbackMessage}</small>}<code>反馈会关联当前版本和责任 Pass</code></>}
            </div>}
            {error && <pre className="error">{error}</pre>}
          </div>
          <div className="transport">
            <button onClick={() => { startRef.current = performance.now() - progress * 5000; setPlaying(v => !v); }}>{playing ? "Ⅱ" : "▶"}</button>
            <span>0:00</span>
            <input type="range" min="0" max="1" step="0.001" value={progress} onChange={e => { const p=Number(e.target.value); setPlaying(false); setProgress(p); render(p); }} />
            <span>0:05</span><output>{progress.toFixed(3)}</output>
          </div>
        </section>

        <aside className="editor">
          <div className="editor-head"><div><span>{shaderStage === "fragment" ? "FRAGMENT SHADER" : "VERTEX SHADER"}</span><strong>{passes[selected]?.name}</strong></div><em>GLSL ES</em></div>
          <div className="shader-tabs"><button className={shaderStage === "fragment" ? "active" : ""} onClick={() => setShaderStage("fragment")}>Fragment</button><button className={shaderStage === "vertex" ? "active" : ""} onClick={() => setShaderStage("vertex")}>Vertex {passes[selected]?.vertex ? "●" : "(default)"}</button></div>
          <textarea spellCheck={false} placeholder={shaderStage === "vertex" ? "留空时使用默认全屏顶点 shader" : ""} value={passes[selected]?.[shaderStage] || ""} onChange={e => updatePass(e.target.value)} />
          <div className="uniforms">
            <span>AVAILABLE UNIFORMS</span>
            {Object.keys(passes[selected]?.inputs || { inputImageTexture: "previous" }).map(name => <code key={name}>{name}</code>)}<code>uProgress · {progress.toFixed(3)}</code><code>uTime</code><code>uResolution</code><code>uTexelSize</code><code>uSourceResolution</code>{Object.keys(graphParameters).map(name => <code key={name}>{name}</code>)}
          </div>
          <div className="inspector">
            <div><span>Input</span><strong>{JSON.stringify(passes[selected]?.inputs || { inputImageTexture: selected === 0 ? "source" : "previous" })}</strong></div>
            <div><span>Output</span><strong>{passes[selected]?.output || `pass_${selected + 1}`}</strong></div>
            <div><span>Format</span><strong>RGBA8</strong></div>
          </div>
          <div className="graph-config">
            <span>PASS RESOURCES</span>
            <label>Inputs (sampler → resource)<textarea key={`inputs-${selected}`} defaultValue={JSON.stringify(passes[selected]?.inputs || { inputImageTexture: selected === 0 ? "source" : "previous" })} onBlur={event => { try { const value=JSON.parse(event.currentTarget.value); if (!value || Array.isArray(value)) throw new Error(); updatePassGraph({ inputs: value }); setError(""); } catch { setError("Inputs 必须是 JSON 对象，例如 {\"inputImageTexture\":\"source\"}"); } }} /></label>
            <label>Output resource<input value={passes[selected]?.output || ""} onChange={event => updatePassGraph({ output: event.target.value || `pass_${selected + 1}` })} /></label>
            <label>FBO scale <output>{(passes[selected]?.scale ?? 1).toFixed(2)}×</output><input type="range" min="0.25" max="1" step="0.25" value={passes[selected]?.scale ?? 1} onChange={event => updatePassGraph({ scale: Number(event.target.value) })} /><div className="scale-actions">{[0.25, 0.5, 1].map(scale => <button key={scale} className={(passes[selected]?.scale ?? 1) === scale ? "active" : ""} onClick={() => updatePassGraph({ scale })}>{scale === 1 ? "原尺寸" : `${scale}×`}</button>)}</div><small>当前输出：{sourceRef.current ? `${Math.round(sourceRef.current.naturalWidth * (passes[selected]?.scale ?? 1))} × ${Math.round(sourceRef.current.naturalHeight * (passes[selected]?.scale ?? 1))}` : "载入图片后显示"}</small></label>
            <span>GRAPH PARAMETERS</span>
            <label>JSON keyframes<textarea key={`parameters-${JSON.stringify(graphParameters)}`} defaultValue={JSON.stringify(graphParameters, null, 2)} placeholder={'{"gridNumRatio":{"keyframes":[[0,0.06],[0.5,0.25],[1,0.06]]}}'} onBlur={event => { try { const value=JSON.parse(event.currentTarget.value || "{}"); if (!value || Array.isArray(value)) throw new Error(); setGraphParameters(value); setError(""); } catch { setError("Parameters 必须是 JSON 对象"); } }} /></label>
          </div>
        </aside>
      </section>
      <footer><span>All processing stays local</span><span>FBO chain · WebGL 1 · 30 FPS export</span></footer>
    </main>
  );
}
