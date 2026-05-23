export interface AIAdapter {
  loginUrl: string;
  isLoginRequired(): Promise<boolean>;
  openLoginPage(headed: boolean): Promise<void>;
  send(payload: string): Promise<{ text: string; tokenEst: number; limitHit: boolean }>;
}

export type WorkerCommand =
  | { cmd: "send";     payload: string; sessionId?: string }
  | { cmd: "ping" }
  | { cmd: "login";    headed: boolean }
  | { cmd: "status" }
  | { cmd: "shutdown" };

export type WorkerResponse =
  | { event: "response";    text: string;  tokenEst: number }
  | { event: "stream";      chunk: string }
  | { event: "limit";       type: "rate" | "token" | "timeout" }
  | { event: "login_needed"; url: string }
  | { event: "ready";       text: string }
  | { event: "error";       msg: string };
