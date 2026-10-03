// References to chats from the composer (refs.rs).

/// The chat a draft's key names, as the pages key them: `new:<station>` a new chat there, else `<station>:<chat>`.
export function draftAt(key: string): [string, string] | null {
  if (key.startsWith("new:")) {
    const station = key.slice(4);
    return station !== "" ? [station, "new"] : null;
  }
  const at = key.indexOf(":");
  if (at < 0) return null;
  const station = key.slice(0, at);
  const chat = key.slice(at + 1);
  return station !== "" && chat !== "" ? [station, chat] : null;
}
