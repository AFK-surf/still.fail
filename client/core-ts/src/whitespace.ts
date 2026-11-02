// White space as Rust's `char::is_whitespace` has it (Unicode's White_Space), for the station and the core alike:
// trimmed and split the same on both sides (a title, a first line).

/// Rust's `trim`.
export const trim = (s: string) => s.replace(/^\p{White_Space}+|\p{White_Space}+$/gu, "");

/// Rust's `trim_start`.
export const trimStart = (s: string) => s.replace(/^\p{White_Space}+/u, "");

/// Rust's `split_whitespace`.
export const splitWhitespace = (s: string) => s.split(/\p{White_Space}+/u).filter((w) => w !== "");
