import { Page } from "playwright";
import type { AIAdapter } from "../types.js";

const LIMIT_PATTERNS = [
  "you've reached", "rate limit", "too many requests",
  "message limit", "quota exceeded", "try again later",
];

export class ChatGPTAdapter implements AIAdapter {
  loginUrl = "https://chat.openai.com/auth/login";

  private selectors = {
    input:    "#prompt-textarea, [data-testid=\"chat-input\"]",
    send:     '[data-testid="send-button"], button[aria-label="Send message"]',
    response: '[data-testid="assistant-message"]:last-child, .markdown:last-of-type',
    limit:    '.text-red-500, [data-testid="rate-limit-message"]',
  };

  constructor(private page: Page) {}

  async isLoginRequired(): Promise<boolean> {
    try {
      await this.page.goto("https://chat.openai.com", { waitUntil: "domcontentloaded", timeout: 15_000 });
      const input = await this.page.$(this.selectors.input);
      return input === null;
    } catch {
      return true;
    }
  }

  async openLoginPage(headed: boolean): Promise<void> {
    await this.page.goto(this.loginUrl, { waitUntil: "domcontentloaded" });
  }

  async send(payload: string): Promise<{ text: string; tokenEst: number; limitHit: boolean }> {
    if (!this.page.url().includes("chat.openai.com")) {
      await this.page.goto("https://chat.openai.com", { waitUntil: "domcontentloaded" });
    }

    const input = await this.page.waitForSelector(this.selectors.input, { timeout: 10_000 });
    await input.fill(payload);

    const sendBtn = await this.page.waitForSelector(this.selectors.send, { timeout: 5_000 });
    await sendBtn.click();

    // Wait for response — ChatGPT shows a "Stop generating" button while streaming
    await this.page.waitForFunction(
      () => !document.querySelector('button[aria-label="Stop generating"]'),
      { timeout: 90_000, polling: 500 }
    );

    const text = await this.page.$eval(this.selectors.response, (el) => el.textContent?.trim() ?? "")
      .catch(() => "");

    const limitHit = LIMIT_PATTERNS.some((p) => text.toLowerCase().includes(p));
    return { text, tokenEst: Math.ceil(text.length / 4), limitHit };
  }
}
