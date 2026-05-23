import { Page } from "playwright";
import type { AIAdapter } from "../types.js";

const LIMIT_PATTERNS = [
  "you've reached", "rate limit", "too many requests",
  "message limit", "quota exceeded", "try again later",
];

export class ClaudeAdapter implements AIAdapter {
  loginUrl = "https://claude.ai/login";

  private selectors = {
    // Ordered: specific data-testid first, aria-label fallback
    input:    '[data-testid="chat-input"], div[contenteditable="true"]',
    send:     '[data-testid="send-button"], button[aria-label*="Send"]',
    response: '[data-testid="message-content"]:last-child, .prose:last-of-type',
    limit:    '[data-testid="rate-limit-message"], .rate-limit',
    userMenu: '[data-testid="user-menu-button"], [aria-label*="Account"]',
  };

  constructor(private page: Page) {}

  async isLoginRequired(): Promise<boolean> {
    try {
      await this.page.goto("https://claude.ai", { waitUntil: "domcontentloaded", timeout: 15_000 });
      // If we can find the input, we're logged in
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
    // Ensure we're on Claude
    if (!this.page.url().includes("claude.ai")) {
      await this.page.goto("https://claude.ai", { waitUntil: "domcontentloaded" });
    }

    // Wait for input and fill
    const input = await this.page.waitForSelector(this.selectors.input, { timeout: 10_000 });
    await input.click();
    await this.page.keyboard.type(payload, { delay: 0 });

    // Submit
    const sendBtn = await this.page.waitForSelector(this.selectors.send, { timeout: 5_000 });
    await sendBtn.click();

    // Wait for response using MutationObserver pattern (no polling)
    const text = await this.page.evaluate(
      async ({ responseSelector, limitSelector, limitPatterns }) => {
        return new Promise<string>((resolve) => {
          const timeout = setTimeout(() => resolve("__TIMEOUT__"), 60_000);

          const observer = new MutationObserver(() => {
            // Check for limit message first
            const limitEl = document.querySelector(limitSelector);
            if (limitEl?.textContent) {
              const low = limitEl.textContent.toLowerCase();
              if (limitPatterns.some((p: string) => low.includes(p))) {
                clearTimeout(timeout);
                observer.disconnect();
                resolve("__LIMIT__");
                return;
              }
            }

            // Check if response element exists and is not empty and stream has settled
            const els = document.querySelectorAll(responseSelector);
            const last = els[els.length - 1];
            if (!last?.textContent?.trim()) return;

            // Heuristic: streaming is done when the send button is re-enabled
            const sendBtn = document.querySelector('[data-testid="send-button"]') as HTMLButtonElement | null;
            if (sendBtn && !sendBtn.disabled) {
              clearTimeout(timeout);
              observer.disconnect();
              resolve(last.textContent.trim());
            }
          });

          observer.observe(document.body, { childList: true, subtree: true, characterData: true });
        });
      },
      {
        responseSelector: this.selectors.response,
        limitSelector:    this.selectors.limit,
        limitPatterns:    LIMIT_PATTERNS,
      }
    );

    if (text === "__TIMEOUT__") {
      return { text: "", tokenEst: 0, limitHit: true };
    }
    if (text === "__LIMIT__") {
      return { text: "", tokenEst: 0, limitHit: true };
    }

    const limitHit = LIMIT_PATTERNS.some((p) => text.toLowerCase().includes(p));
    const tokenEst = Math.ceil(text.length / 4);
    return { text, tokenEst, limitHit };
  }
}
