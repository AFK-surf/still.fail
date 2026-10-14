// Keep a just-sent image available while its draft becomes an outbox row and then the station's message.
// The staged file keeps its unique stored filename when the station moves it into the session's uploads.
const pictures = new Map<string, { url: string; timer: ReturnType<typeof setTimeout> }>();
export const sentImageKey = (path: string): string => path.split("/").at(-1)!;
/** Where an image sent before it was up is kept, by its upload's id (`composer.add`): in its outbox row, and in its
 * message once up (the core says which upload a file was: `Attachment.upload`). */
export const uploadImageKey = (id: string): string => `upload:${id}`;
/** The key a message's file is drawn by, here and in a composer's thumbnail flying to it (`data-send-image`). */
export const sentFileKey = (file: { path: string; upload?: string | undefined }): string => file.upload ? uploadImageKey(file.upload) : sentImageKey(file.path);
const keyOf = (station: string, path: string) => `${station}\n${sentImageKey(path)}`;

export function sentImage(station: string, path: string): string | undefined {
  return pictures.get(keyOf(station, path))?.url;
}

/** `ms`: how long it is kept (one still going up is kept until it has been up a while). */
export function keepSentImage(station: string, path: string, blob: Blob, ms = 60_000): void {
  const key = keyOf(station, path);
  const drop = (id: string) => {
    const old = pictures.get(id);
    if (!old) return;
    clearTimeout(old.timer);
    URL.revokeObjectURL(old.url);
    pictures.delete(id);
  };
  drop(key);
  pictures.set(key, { url: URL.createObjectURL(blob), timer: setTimeout(() => drop(key), ms) });
  // Bound memory even if many large images are sent before the timers expire.
  while (pictures.size > 20) drop(pictures.keys().next().value!);
}
