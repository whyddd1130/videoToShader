import { createServer } from "node:http";
import { createWriteStream, existsSync, mkdirSync, readFileSync } from "node:fs";
import { appendFile, rename, rm } from "node:fs/promises";
import { basename, extname, join } from "node:path";

const outputDir = process.env.MULTIPASS_OUTPUT_DIR;
const port = Number(process.env.MULTIPASS_RECEIVER_PORT || 8789);
if (!outputDir) throw new Error("MULTIPASS_OUTPUT_DIR is required");
mkdirSync(outputDir, { recursive: true });

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, PUT, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Cache-Control": "no-store",
};
const mime = new Map([
  [".mp4", "video/mp4"], [".webm", "video/webm"], [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"], [".png", "image/png"], [".json", "application/json"],
]);

function reply(response, status, body = "", headers = {}) {
  response.writeHead(status, { ...cors, ...headers });
  response.end(body);
}

function safeTarget(pathname, prefix) {
  const name = decodeURIComponent(pathname.slice(prefix.length));
  if (!name || name !== basename(name)) return null;
  return join(outputDir, name);
}

function collect(request, limit = 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = []; let size = 0;
    request.on("data", chunk => {
      size += chunk.length;
      if (size > limit) { reject(new Error("request body too large")); request.destroy(); }
      else chunks.push(chunk);
    });
    request.on("end", () => resolve(Buffer.concat(chunks)));
    request.on("error", reject);
  });
}

createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", `http://127.0.0.1:${port}`);
    if (request.method === "OPTIONS") return reply(response, 204);
    if (request.method === "GET" && url.pathname === "/health") {
      return reply(response, 200, JSON.stringify({ ok: true }), { "Content-Type": "application/json" });
    }
    if (request.method === "GET" && url.pathname.startsWith("/videos/")) {
      const target = safeTarget(url.pathname, "/videos/");
      if (!target || !existsSync(target)) return reply(response, 404, "not found");
      return reply(response, 200, readFileSync(target), { "Content-Type": mime.get(extname(target).toLowerCase()) || "application/octet-stream" });
    }
    if (request.method === "PUT" && (url.pathname.startsWith("/videos/") || url.pathname.startsWith("/stills/"))) {
      const prefix = url.pathname.startsWith("/videos/") ? "/videos/" : "/stills/";
      const target = safeTarget(url.pathname, prefix);
      if (!target) return reply(response, 400, "invalid filename");
      const temporary = `${target}.${process.pid}.${Date.now()}.upload`;
      const stream = createWriteStream(temporary, { flags: "wx" });
      await new Promise((resolve, reject) => {
        request.pipe(stream); request.on("error", reject); stream.on("error", reject); stream.on("finish", resolve);
      });
      await rename(temporary, target).catch(async error => { await rm(temporary, { force: true }); throw error; });
      return reply(response, 201, JSON.stringify({ ok: true, file: basename(target) }), { "Content-Type": "application/json" });
    }
    if (request.method === "POST" && url.pathname === "/events") {
      const body = await collect(request);
      const event = JSON.parse(body.toString("utf8"));
      await appendFile(join(outputDir, "render_log.jsonl"), `${JSON.stringify(event)}\n`, "utf8");
      return reply(response, 202, JSON.stringify({ ok: true }), { "Content-Type": "application/json" });
    }
    return reply(response, 404, "not found");
  } catch (error) {
    return reply(response, 500, error instanceof Error ? error.message : String(error));
  }
}).listen(port, "127.0.0.1", () => {
  process.stdout.write(`multipass render receiver: http://127.0.0.1:${port}\n`);
});
