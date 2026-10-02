// Keep a just-sent image available while its draft becomes an outbox row and then the station's message.
// The staged file keeps its unique stored filename when the station moves it into the session's uploads.
const pictures = new Map<string, { url: string; timer: ReturnType<typeof setTimeout> }>();
export const sentImageKey = (path: string): string => path.split("/").at(-1)!;
const keyOf = (station: string, path: string) => `${station}\n${sentImageKey(path)}`;

export function sentImage(station: string, path: string): string | undefined {
  return pictures.get(keyOf(station, path))?.url;
}

export function keepSentImage(station: string, path: string, blob: Blob): void {
  const key = keyOf(station, path);
  const drop = (id: string) => {
    const old = pictures.get(id);
    if (!old) return;
    clearTimeout(old.timer);
    URL.revokeObjectURL(old.url);
    pictures.delete(id);
  };
  drop(key);
  pictures.set(key, { url: URL.createObjectURL(blob), timer: setTimeout(() => drop(key), 60_000) });
  // Bound memory even if many large images are sent before the timers expire.
  while (pictures.size > 20) drop(pictures.keys().next().value!);
}
