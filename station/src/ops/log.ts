// What the station says about itself: one line each on stderr (launchd keeps it as stillfail.log), as the Rust
// station's tracing lines read: time, level, where, message, fields.
type Fields = Record<string, unknown>;

function line(level: string, at: string, message: string, fields?: Fields) {
  const rest = fields ? Object.entries(fields).map(([k, v]) => ` ${k}=${typeof v === "string" ? v : JSON.stringify(v)}`).join("") : "";
  process.stderr.write(`${new Date().toISOString()} ${level.padStart(5)} ${at}: ${message}${rest}\n`);
}

export const log = {
  info: (at: string, message: string, fields?: Fields) => line("INFO", at, message, fields),
  warn: (at: string, message: string, fields?: Fields) => line("WARN", at, message, fields),
  error: (at: string, message: string, fields?: Fields) => line("ERROR", at, message, fields),
};
