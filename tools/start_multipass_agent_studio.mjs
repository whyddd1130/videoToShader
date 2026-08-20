#!/usr/bin/env node
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const toolsDir = dirname(fileURLToPath(import.meta.url));
const repo = dirname(toolsDir);
const studio = join(repo, "muti_pass", "multipass-studio");
const children = [];

async function reachable(url) {
  try {
    const response = await fetch(url);
    return response.ok;
  } catch {
    return false;
  }
}

async function waitFor(url, attempts = 100) {
  for (let index = 0; index < attempts; index++) {
    if (await reachable(url)) return;
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${url}`);
}

function launch(command, args, cwd, { tracked = true } = {}) {
  const child = spawn(command, args, { cwd, stdio: "inherit", env: process.env });
  if (tracked) children.push(child);
  return child;
}

function stop() {
  children.forEach(child => { if (!child.killed) child.kill("SIGTERM"); });
}

process.on("SIGINT", () => { stop(); process.exit(130); });
process.on("SIGTERM", () => { stop(); process.exit(143); });

if (!await reachable("http://127.0.0.1:8792/api/agent/health")) {
  launch(join(repo, ".venv", "bin", "python"), [join(repo, "tools", "multipass_agent_server.py")], repo);
}
if (!await reachable("http://localhost:3001")) {
  launch("npm", ["run", "dev", "--", "--host", "localhost", "--port", "3001"], studio);
}

await Promise.all([
  waitFor("http://127.0.0.1:8792/api/agent/health"),
  waitFor("http://localhost:3001"),
]);
console.log("MultiPass Agent Studio ready: http://localhost:3001");
launch("open", ["-a", "Safari", "http://localhost:3001"], repo, { tracked: false });

if (children.length) {
  await new Promise(resolve => children.forEach(child => child.once("exit", resolve)));
  stop();
}
