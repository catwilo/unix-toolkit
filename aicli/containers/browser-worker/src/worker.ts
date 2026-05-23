/**
 * browser-worker/src/worker.ts
 *
 * Receives JSON-line commands on the Unix socket specified by WORKER_SOCK.
 * Responds with JSON-line events (response | stream | limit | login_needed | ready | error).
 */
import { chromium, BrowserContext, Page } from "playwright";
import * as net from "net";
import * as fs from "fs";
import * as readline from "readline";
import { ClaudeAdapter } from "./adapters/claude.js";
import { ChatGPTAdapter } from "./adapters/chatgpt.js";
import { GeminiAdapter } from "./adapters/gemini.js";
import type { AIAdapter, WorkerCommand, WorkerResponse } from "./types.js";

// ── Config ────────────────────────────────────────────────────────────────────

const AI          = (process.env.AI          ?? "claude") as "claude" | "chatgpt" | "gemini";
const ACCOUNT_ID  = process.env.ACCOUNT_ID   ?? "default";
const PROFILE_DIR = process.env.PROFILE_DIR  ?? "/profile";
const WORKER_SOCK = process.env.WORKER_SOCK  ?? "/tmp/aicli/worker-default.sock";
const CHROME_BIN  = process.env.CHROME_BIN   ?? "/usr/bin/google-chrome-stable";

// ── Browser setup ─────────────────────────────────────────────────────────────

let context: BrowserContext;
let adapter: AIAdapter;

async function initBrowser(): Promise<void> {
  fs.mkdirSync(PROFILE_DIR, { recursive: true });

  context = await chromium.launchPersistentContext(PROFILE_DIR, {
    executablePath: CHROME_BIN,
    headless: process.env.HEADLESS !== "false",
    args: [
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--disable-blink-features=AutomationControlled",
      "--window-size=1280,900",
    ],
    ignoreDefaultArgs: ["--enable-automation"],
    viewport: { width: 1280, height: 900 },
  });

  const page = context.pages()[0] ?? await context.newPage();

  switch (AI) {
    case "claude":   adapter = new ClaudeAdapter(page);   break;
    case "chatgpt":  adapter = new ChatGPTAdapter(page);  break;
    case "gemini":   adapter = new GeminiAdapter(page);   break;
    default:
      throw new Error(`Unknown AI: ${AI}`);
  }

  const loginNeeded = await adapter.isLoginRequired();
  if (loginNeeded) {
    send({ event: "login_needed", url: adapter.loginUrl });
  } else {
    send({ event: "ready", text: `${AI}/${ACCOUNT_ID} ready` });
  }
}

// ── Unix socket server ────────────────────────────────────────────────────────

function send(resp: WorkerResponse): void {
  process.stdout.write(JSON.stringify(resp) + "\n");
}

async function handleCommand(cmd: WorkerCommand): Promise<void> {
  switch (cmd.cmd) {
    case "send": {
      try {
        const { text, tokenEst, limitHit } = await adapter.send(cmd.payload ?? "");
        if (limitHit) {
          send({ event: "limit", type: "token" });
        } else {
          send({ event: "response", text, tokenEst });
        }
      } catch (err: any) {
        send({ event: "error", msg: String(err?.message ?? err) });
      }
      break;
    }
    case "ping":
      send({ event: "ready", text: "pong" });
      break;
    case "login": {
      await adapter.openLoginPage(cmd.headed ?? true);
      send({ event: "login_needed", url: adapter.loginUrl });
      break;
    }
    case "status": {
      const loginNeeded = await adapter.isLoginRequired();
      send({ event: "ready", text: JSON.stringify({ logged_in: !loginNeeded, ai: AI }) });
      break;
    }
    case "shutdown":
      await context?.close();
      process.exit(0);
  }
}

function startSocketServer(): void {
  try { fs.unlinkSync(WORKER_SOCK); } catch {}
  fs.mkdirSync("/tmp/aicli", { recursive: true });

  const server = net.createServer((socket) => {
    const rl = readline.createInterface({ input: socket, terminal: false });
    rl.on("line", (line) => {
      try {
        const cmd: WorkerCommand = JSON.parse(line);
        handleCommand(cmd).catch((err) => {
          send({ event: "error", msg: String(err?.message ?? err) });
        });
      } catch {
        send({ event: "error", msg: "invalid JSON" });
      }
    });
  });

  server.listen(WORKER_SOCK, () => {
    fs.chmodSync(WORKER_SOCK, 0o600);
  });
}

// ── Entry ─────────────────────────────────────────────────────────────────────

(async () => {
  startSocketServer();
  await initBrowser();
})();
