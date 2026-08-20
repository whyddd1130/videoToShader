import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", { headers: { accept: "text/html" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("server-renders the Agent launch workspace", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>MultiPass Studio<\/title>/i);
  assert.match(html, /从原图与目标视频生成多 Pass Shader/);
  assert.match(html, /原始输入图/);
  assert.match(html, /目标特效视频/);
  assert.match(html, /Pass 数量（可选）/);
  assert.match(html, /每个 Pass 的职责（可选）/);
  assert.match(html, /画面特效辅助说明（可选）/);
  assert.match(html, /模型始终先独立观察视频抽帧/);
  assert.match(html, /和视频冲突时以视频为准/);
});

test("keeps the browser workflow wired to the persistent Agent API", async () => {
  const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");

  assert.match(page, /127\.0\.0\.1:8792\/api\/agent/);
  assert.match(page, /\/source-image/);
  assert.match(page, /\/target-video/);
  assert.match(page, /\/feedback/);
  assert.match(page, /\/cancel/);
  assert.match(page, /setInterval\([^]*1200\)/);
  assert.match(page, /planning_mode/);
  assert.match(page, /waiting_for_human_feedback/);
  assert.match(page, /applying_repair_transaction/);
  assert.match(page, /current_obligation/);
  assert.match(page, /effect_description/);
  assert.match(page, /VISUAL FIRST/);
  assert.doesNotMatch(page, /画面特效描述模式不能同时指定/);
  assert.doesNotMatch(page, /请同时填写 Pass 数量和职责/);
  assert.match(page, /declaredType === "int"[^]*uniform1i/);
  assert.match(page, /requestedVideoVersionRef/);
  assert.match(page, /candidate-badge/);
  assert.match(page, /video-mode-tabs/);
  assert.match(page, /comparison-target-video/);
  assert.match(page, />当前视频</);
  assert.match(page, />原视频</);
  assert.match(page, /targetPreviewUrl \|\| jobStatus\?\.target_url/);
  assert.match(page, /__renderMultiPassJob/);
  assert.match(page, /numericCount < 1/);
  assert.doesNotMatch(page, /numericCount > 5|max="5"/);
  assert.doesNotMatch(page, /__renderMultipassDataset|legacyRender/);
});
