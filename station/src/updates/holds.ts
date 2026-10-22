// What keeps the station from updating itself for now (updates.ts `toUpdateTo`): work an update would cut off and that
// is not handed over to the next station process, as running turns are. A command run with a vault grant
// (vault/secrets.ts `run`) is one: its proxy or ssh-agent lives in this process, so the command, which goes on, would
// be left without it. Once the last hold is let go, an update that waited goes ahead (`onLetGo`).
const holds = new Set<symbol>();
const told = new Set<() => void>();

/// Held while it runs: the returned function lets go (once).
export function hold(): () => void {
  const h = Symbol();
  holds.add(h);
  return () => {
    if (!holds.delete(h) || holds.size > 0) return;
    for (const f of told) f();
  };
}

/// How many holds there are now.
export const holding = (): number => holds.size;

/// `f` called each time the last hold is let go; the returned function stops it.
export function onLetGo(f: () => void): () => void {
  told.add(f);
  return () => void told.delete(f);
}
