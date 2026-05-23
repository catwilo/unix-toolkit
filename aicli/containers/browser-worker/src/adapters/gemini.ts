import { Page } from "playwright";
import type { AIAdapter } from "../types.js";

const LIMIT_PATTERNS = [
  "you've reached", "rate limit", "too many requests",
  "quota exceeded", "try again later",
];

export class GeminiAdapter implements AIAdapter {
  loginUrl = "https://gemini.google.com";

  private selectors = {
    input:    "rich-textarea .ql-editor, [aria-label*='Enter a prompt']",
    send:     "button[aria-label*='Send message'], .send-button",
    response: "message-content:last-of-type model-response, .response-container:last-child",
    limit:    ".error-message, [data-error]",
  };

  constructor(private page: Page) {}

  async isLoginRequired(): Promise<boolean> {
    try {
      await this.page.goto("https://gemini.google.com", { waitUntil: "domcontentloaded", timeout: 15_000 });
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
    if (!this.page.url().includes("gemini.google.com")) {
      await this.page.goto("https://gemini.google.com", { waitUntil: "domcontentloaded" });
    }

    const input = await this.page.waitForSelector(this.selectors.input, { timeout: 10_000 });
    await input.click();
    await this.page.keyboard.type(payload, { delay: 0 });

    const sendBtn = await this.page.waitForSelector(this.selectors.send, { timeout: 5_000 });
    await sendBtn.click();

    // Gemini shows a loading spinner — wait for it to disappear
    await this.page.waitForFunction(
      () => !document.querySelector('.loading-indicator, [aria-label="Loading"]'),
      { timeout: 90_000, polling: 500 }
    );

    const text = await this.page.$eval(this.selectors.response, (el) => el.textContent?.trim() ?? "")
      .catch(() => "");

    const limitHit = LIMIT_PATTERNS.some((p) => text.toLowerCase().includes(p));
    return { text, tokenEst: Math.ceil(text.length / 4), limitHit };
  }
}
