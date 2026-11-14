// The Codex driver's tests (codex.test.ts) with its app-servers' output read on the station's thread, as where the
// MoonBit program is not there (agents/mb-agents.ts): the same tests pass either way.
process.env.STILLFAIL_AGENTS_HOST = "0";
await import("./codex.test.ts");
