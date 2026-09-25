// One JSON object per line on stdout; launchd or the caller decides where it goes.

type Level = "debug" | "info" | "warn" | "error";
const order: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 };
const threshold = order[(process.env.EMBER_LOG_LEVEL as Level | undefined) ?? "info"] ?? order.info;

function write(level: Level, msg: string, fields?: Record<string, unknown>): void {
  if (order[level] < threshold) return;
  const line: Record<string, unknown> = { t: new Date().toISOString(), level, msg, ...fields };
  for (const [key, value] of Object.entries(line)) {
    if (value instanceof Error) line[key] = { message: value.message, stack: value.stack };
  }
  process.stdout.write(`${JSON.stringify(line)}\n`);
}

export const log = {
  debug: (msg: string, fields?: Record<string, unknown>) => write("debug", msg, fields),
  info: (msg: string, fields?: Record<string, unknown>) => write("info", msg, fields),
  warn: (msg: string, fields?: Record<string, unknown>) => write("warn", msg, fields),
  error: (msg: string, fields?: Record<string, unknown>) => write("error", msg, fields),
};
