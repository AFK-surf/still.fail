// The Claude Code driver's tests (claude.test.ts) with its processes read on the station's thread, as where the MoonBit
// program is not there (agents/mb-agents.ts): the same tests pass either way.
process.env.STILLFAIL_AGENTS_HOST = "0";
await import("./claude.test.ts");
