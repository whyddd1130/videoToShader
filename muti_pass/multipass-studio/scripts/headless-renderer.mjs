import { chromium } from "playwright";

const url = process.argv[2];
const timeoutMs = Number(process.env.MULTIPASS_BROWSER_TIMEOUT_MS || 180000);
if (!url) throw new Error("Usage: headless-renderer.mjs <render-url>");

let browser;
try {
  browser = await chromium.launch({
    headless: true,
    args: [
      "--enable-webgl",
      "--ignore-gpu-blocklist",
      "--use-angle=metal",
      "--autoplay-policy=no-user-gesture-required",
    ],
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  page.on("console", message => process.stdout.write(`[browser:${message.type()}] ${message.text()}\n`));
  page.on("pageerror", error => process.stderr.write(`[pageerror] ${error.stack || error.message}\n`));
  page.on("requestfailed", request => {
    process.stderr.write(`[requestfailed] ${request.method()} ${request.url()} ${request.failure()?.errorText || ""}\n`);
  });
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
  process.stdout.write(`[ready] ${url}\n`);
  await page.waitForTimeout(timeoutMs);
  throw new Error(`Headless render did not complete within ${timeoutMs} ms`);
} finally {
  if (browser) await browser.close();
}
